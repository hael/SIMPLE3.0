module simple_cont3D_matcher
use simple_defs
use simple_build,             only: build
use simple_params,            only: params
use simple_cmdline,           only: cmdline
use simple_polarft_corrcalc,  only: polarft_corrcalc
use simple_oris,              only: oris
use simple_ori,               only: ori
!use simple_masker,           only: automask
use simple_cont3D_greedysrch, only: cont3D_greedysrch
use simple_cont3D_srch,       only: cont3D_srch
use simple_hadamard_common   ! use all in there
use simple_math              ! use all in there
implicit none

public :: cont3D_exec
private
#include "simple_local_flags.inc"
integer,                   parameter :: BATCHSZ_MUL = 10   ! particles per thread
integer,                   parameter :: MAXNPEAKS   = 10
integer,                   parameter :: NREFS       = 50

type(polarft_corrcalc)               :: pftcc
type(oris)                           :: orefs                   !< per particle projection direction search space
type(cont3D_srch),       allocatable :: cont3Dsrch(:)
type(cont3D_greedysrch), allocatable :: cont3Dgreedysrch(:)
logical, allocatable                 :: state_exists(:)
real                                 :: reslim          = 0.
!real                                 :: frac_srch_space = 0.   ! so far unused
integer                              :: nptcls          = 0
integer                              :: nrefs_per_ptcl  = 0
integer                              :: neff_states     = 0

contains

    !>  \brief  is the 3D continous algorithm
    subroutine cont3D_exec( b, p, cline, which_iter, converged )
        use simple_map_reduce, only: split_nobjs_even
        use simple_qsys_funs,  only: qsys_job_finished
        use simple_strings,    only: int2str_pad
        use simple_projector,  only: projector
        !$ use omp_lib
        !$ use omp_lib_kinds
        class(build),   intent(inout) :: b
        class(params),  intent(inout) :: p
        class(cmdline), intent(inout) :: cline
        integer,        intent(in)    :: which_iter
        logical,        intent(inout) :: converged
        ! batches-related variables
        type(projector),         allocatable :: batch_imgs(:)
        type(polarft_corrcalc),  allocatable :: pftccs(:)
        integer,                 allocatable :: batches(:,:)
        ! other variables
        type(oris)           :: softoris
        type(ori)            :: orientation
        integer              :: nbatches, batch, fromp, top, iptcl,iptcl_tmp, state, alloc_stat, ind
        ! AUTOMASKING DEACTIVATED FOR NOW
        ! MULTIPLE STATES DEACTIVATED FOR NOW
        if(p%nstates>1)stop 'MULTIPLE STATES DEACTIVATED FOR NOW; cont3D_matcher::cont3Dexec'
        ! INIT
        nptcls = p%top - p%fromp + 1                    ! number of particles processed
        ! states
        allocate(state_exists(p%nstates))
        state_exists = b%a%get_state_exist(p%nstates)   ! state existence
        neff_states  = count(state_exists)              ! number of non-empty states
        ! number of references per particle
        select case(p%refine)
            case('yes')
                nrefs_per_ptcl = NREFS*neff_states
            case('greedy')
                nrefs_per_ptcl = 1
            case DEFAULT
                stop 'Uknown refinement mode; pcont3D_matcher::cont3D_exec'
        end select
        ! Fraction of the search space
        ! frac_srch_space = b%a%get_avg('frac')      ! unused
        ! batches
        nbatches = ceiling(real(nptcls)/real(p%nthr*BATCHSZ_MUL))
        batches  = split_nobjs_even(nptcls, nbatches)

        ! SET BAND-PASS LIMIT RANGE
        call set_bp_range( b, p, cline )
        reslim = p%lp

        ! CALCULATE ANGULAR THRESHOLD (USED BY THE SPARSE WEIGHTING SCHEME)
        p%athres = rad2deg(atan(max(p%fny,p%lp)/(p%moldiam/2.)))
        if( p%refine.eq.'yes' )write(*,'(A,F6.2)')'>>> ANGULAR THRESHOLD: ', p%athres

        ! DETERMINE THE NUMBER OF PEAKS
        select case(p%refine)
            case('yes')
                if( .not. cline%defined('npeaks') )then
                    p%npeaks = min(MAXNPEAKS,b%e%find_npeaks(p%lp, p%moldiam))
                endif
                write(*,'(A,I2)')'>>> NPEAKS: ', p%npeaks
            case DEFAULT
                p%npeaks = 1
        end select

        ! SETUP WEIGHTS FOR THE 3D RECONSTRUCTION
        if( p%nptcls <= SPECWMINPOP )then
            call b%a%calc_hard_ptcl_weights(p%frac)
        else
            call b%a%calc_spectral_weights(p%frac)
        endif

        ! PREPARE REFERENCE VOLUMES
        call prep_vols(b, p, cline)

        ! RESET RECVOLS
        if(p%norec .eq. 'no')then
            do state=1,p%nstates
                if( state_exists(state) )then
                    if( p%eo .eq. 'yes' )then
                        call b%eorecvols(state)%reset_all
                    else
                        call b%recvols(state)%reset
                    endif
                endif
            end do
            if(debug)write(*,*)'*** pcont3D_matcher ***: did reset recvols'
        endif

        ! INIT IMGPOLARIZER
        ! dummy pftcc is only init here so the img polarizer can be initialized
        ! todo: write init_imgpolarizer constructor that does not require pftcc
        call pftcc%new(nrefs_per_ptcl, [1,1], [p%boxmatch,p%boxmatch,1],p%kfromto, p%ring2, p%ctf)
        call b%img_match%init_polarizer(pftcc)
        call pftcc%kill

        ! INITIALIZE
        write(*,'(A,1X,I3)')'>>> CONTINUOUS POLAR-FT ORIENTATION SEARCH, ITERATION:', which_iter
        if( .not. p%l_distr_exec )then
            p%outfile = 'cont3Ddoc_'//int2str_pad(which_iter,3)//'.txt'
        endif

        ! BATCH PROCESSING
        call del_file(p%outfile)
        do batch = 1, nbatches
            ! BATCH INDICES
            fromp = p%fromp-1 + batches(batch,1)
            top   = p%fromp-1 + batches(batch,2)
            ! PREP BATCH
            allocate(pftccs(fromp:top), cont3Dsrch(fromp:top), cont3Dgreedysrch(fromp:top),&
                &batch_imgs(fromp:top), stat=alloc_stat)
            call alloc_err('In pcont3D_matcher::pcont3D_exec_single',alloc_stat)
            do iptcl = fromp, top

                state = nint(b%a%get(iptcl, 'state'))
                if(state == 0)cycle
                ! stash raw image for rec
                call read_img_from_stk(b, p, iptcl)
                call batch_imgs(iptcl)%copy(b%img)
                ! prep pftccs & ctf
                call init_pftcc(p, iptcl, pftccs(iptcl))
                call prep_pftcc_ptcl(b, p, iptcl_tmp, pftccs(iptcl))
                if( p%ctf.ne.'no' )call pftccs(iptcl)%create_polar_ctfmats(p%smpd, b%a)
                select case(p%refine)
                    case('yes')
                        call prep_pftcc_refs(b, p, iptcl, pftccs(iptcl))
                        call cont3Dsrch(iptcl)%new(p, orefs, pftccs(iptcl))
                    case('greedy')
                        call cont3Dgreedysrch(iptcl)%new(p, pftccs(iptcl), b%refvols)
                    case DEFAULT
                        stop 'Uknown refinement mode; pcont3D_matcher::cont3D_exec'
                end select
            enddo
            ! SERIAL SEARCHES
            !$omp parallel do default(shared) schedule(guided) private(iptcl) proc_bind(close)
            do iptcl = fromp, top
                select case(p%refine)
                    case('yes')
                        call cont3Dsrch(iptcl)%exec_srch(b%a, iptcl)
                    case('greedy')
                        call cont3Dgreedysrch(iptcl)%exec_srch(b%a, iptcl, 1, 1)
                end select
            enddo
            !$omp end parallel do
            ! GRID & 3D REC
            if(p%norec .eq. 'no')then
                do iptcl = fromp, top
                    orientation = b%a%get_ori(iptcl)
                    state       = nint(orientation%get('state'))
                    if(state == 0)cycle
                    ind   = iptcl-fromp+1
                    call b%img%copy(batch_imgs(iptcl))
                    if(p%npeaks == 1)then
                        call grid_ptcl(b, p, orientation)
                    else
                        softoris = cont3Dsrch(iptcl)%get_softoris()
                        call grid_ptcl(b, p, orientation, os=softoris)
                    endif
                enddo
            endif
            ! ORIENTATIONS OUTPUT: only here for now
            do iptcl = fromp, top
                call b%a%write(iptcl, p%outfile)
            enddo
            ! CLEANUP BATCH
            do iptcl = fromp, top
                call cont3Dsrch(iptcl)%kill
                call cont3Dgreedysrch(iptcl)%kill
                call pftccs(iptcl)%kill
                call batch_imgs(iptcl)%kill
            enddo
            deallocate(pftccs, cont3Dsrch, cont3Dgreedysrch, batch_imgs)
        enddo
        ! CLEANUP SEARCH
        call b%img_match%kill_polarizer
        do state=1,p%nstates
            call b%refvols(state)%kill_expanded
            call b%refvols(state)%kill
        enddo

        ! ORIENTATIONS OUTPUT
        !call b%a%write(p%outfile, [p%fromp,p%top])
        p%oritab = p%outfile

        ! NORMALIZE STRUCTURE FACTORS
        if(p%norec .eq. 'no')then
            if( p%eo .eq. 'yes' )then
                call eonorm_struct_facts(b, p, reslim, which_iter)
            else
                call norm_struct_facts(b, p, which_iter)
            endif
        endif

        ! REPORT CONVERGENCE
        if( p%l_distr_exec )then
            call qsys_job_finished( p, 'simple_pcont3D_matcher :: cont3D_exec')
        else
            converged = b%conv%check_conv_cont3D()
        endif

        ! DEALLOCATE
        deallocate(batches)
        deallocate(state_exists)
    end subroutine cont3D_exec

    !>  \brief  preps volumes for projection
    subroutine prep_vols( b, p, cline )
        class(build),   intent(inout) :: b
        class(params),  intent(inout) :: p
        class(cmdline), intent(inout) :: cline
        integer :: state
        do state=1,p%nstates
            if( state_exists(state) )then
                call preprefvol( b, p, cline, state, doexpand=.false. )
                b%refvols(state) = b%vol
                call b%refvols(state)%expand_cmat
            endif
        enddo
        DebugPrint 'prep volumes done'
        ! bring back the original b%vol size
        if( p%boxmatch < p%box )call b%vol%new([p%box,p%box,p%box], p%smpd) ! to double check
    end subroutine prep_vols

    !>  \brief  initialize pftcc
    subroutine init_pftcc(p, iptcl, pftcc)
        class(params),              intent(inout) :: p
        integer,                    intent(in)    :: iptcl
        class(polarft_corrcalc),    intent(inout) :: pftcc
        if( p%l_xfel )then
            call pftcc%new(nrefs_per_ptcl, [iptcl,iptcl], [p%boxmatch,p%boxmatch,1],p%kfromto, p%ring2, p%ctf, isxfel='yes')
        else
            call pftcc%new(nrefs_per_ptcl, [iptcl,iptcl], [p%boxmatch,p%boxmatch,1],p%kfromto, p%ring2, p%ctf)
        endif
    end subroutine init_pftcc

    !>  \brief  preps search space and performs reference projection
    subroutine prep_pftcc_refs(b, p, iptcl, pftcc)
        use simple_image, only: image
        use simple_ctf,   only: ctf
        class(build),               intent(inout) :: b
        class(params),              intent(inout) :: p
        integer,                    intent(in) :: iptcl
        class(polarft_corrcalc),    intent(inout) :: pftcc
        type(ctf)   :: tfun
        type(image) :: ref_img, ctf_img
        type(oris)  :: cone
        type(ori)   :: optcl, oref
        real        :: eullims(3,2),  dfx, dfy, angast
        integer     :: state, iref, cnt
        optcl = b%a%get_ori(iptcl)
        ! SEARCH SPACE PREP
        eullims = b%se%srchrange()
        call cone%rnd_proj_space(NREFS, optcl, p%athres, eullims)
        call cone%set_euler(1, optcl%get_euler()) ! previous best is the first
        do iref = 1, NREFS
            call cone%e3set(iref, 0.)
        enddo
        ! replicates to states
        if( p%nstates==1 )then
            call cone%set_all2single('state', 1.)
            orefs = cone
        else
            call orefs%new(NREFS*neff_states)
            cnt = 0
            do state = 1,p%nstates
                if(state_exists(state))then
                    call cone%set_all2single('state',real(state))
                    do iref=1,NREFS
                        cnt = cnt+1
                        call orefs%set_ori(cnt, cone%get_ori(iref))
                    enddo
                endif
            enddo
        endif
        ! REFERENCES PROJECTION
        do iref=1,nrefs_per_ptcl
            oref  = orefs%get_ori(iref)
            state = nint(oref%get('state'))
            call b%refvols(state)%fproject_polar(iref, oref, pftcc)
        enddo
    end subroutine prep_pftcc_refs

    !>  \brief  particle projection into pftcc
    subroutine prep_pftcc_ptcl(b, p, iptcl, pftcc)
        class(build),               intent(inout) :: b
        class(params),              intent(inout) :: p
        integer,                    intent(in) :: iptcl
        class(polarft_corrcalc),    intent(inout) :: pftcc
        type(ori)  :: optcl
        optcl = b%a%get_ori(iptcl)
        call prepimg4align(b, p, optcl)
        call b%img_match%polarize(pftcc, iptcl, isptcl=.true.)
    end subroutine prep_pftcc_ptcl

end module simple_cont3D_matcher

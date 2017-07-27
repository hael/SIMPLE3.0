module simple_hadamard3D_matcher
!$ use omp_lib
!$ use omp_lib_kinds
use simple_defs
use simple_polarft_corrcalc, only: polarft_corrcalc
use simple_prime3D_srch,     only: prime3D_srch
use simple_ori,              only: ori
use simple_build,            only: build
use simple_params,           only: params
use simple_cmdline,          only: cmdline
use simple_gridding,         only: prep4cgrid
use simple_strings,          only: str_has_substr
use simple_cont3D_matcher    ! use all in there
use simple_hadamard_common   ! use all in there
use simple_math              ! use all in there
implicit none

public :: prime3D_find_resrange, prime3D_exec, gen_random_model
public :: preppftcc4align, prep_refs_pftcc4align, pftcc
private

integer, parameter              :: MAXNPEAKS=10
logical, parameter              :: DEBUG=.false.
type(polarft_corrcalc)          :: pftcc
type(prime3D_srch), allocatable :: primesrch3D(:)
real                            :: reslim
real                            :: frac_srch_space = 0.
type(ori)                       :: orientation, o_sym
character(len=:), allocatable   :: ppfts_fname

contains

    subroutine prime3D_find_resrange( b, p, lp_start, lp_finish )
        use simple_oris, only: oris
        class(build),  intent(inout) :: b
        class(params), intent(inout) :: p
        real,          intent(out)   :: lp_start, lp_finish
        real, allocatable :: peaks(:)
        type(oris)        :: o
        integer :: lfny, alloc_stat, k, pos10, pos6
        call o%new(p%nspace)
        call o%spiral
        lfny = b%img_match%get_lfny(1)
        allocate( peaks(lfny), stat=alloc_stat )
        call alloc_err("In: prime3D_find_resrange, simple_hadamard3D_matcher", alloc_stat)
        do k=2,b%img_match%get_lfny(1)
            peaks(k) = real(o%find_npeaks(b%img_match%get_lp(k), p%moldiam))
        end do
        peaks(1)  = peaks(2)
        pos10     = locate(peaks, lfny, 10.)
        pos6      = locate(peaks, lfny,  6.)
        lp_start  = b%img_match%get_lp(pos10)
        lp_finish = b%img_match%get_lp(pos6)
        deallocate(peaks)
        call o%kill
    end subroutine prime3D_find_resrange

    subroutine prime3D_exec( b, p, cline, which_iter, update_res, converged )
        use simple_qsys_funs, only: qsys_job_finished
        use simple_oris,      only: oris
        use simple_strings,   only: int2str_pad
        class(build),   intent(inout) :: b
        class(params),  intent(inout) :: p
        class(cmdline), intent(inout) :: cline
        integer,        intent(in)    :: which_iter
        logical,        intent(inout) :: update_res, converged
        type(oris)        :: prime3D_oris
        real              :: norm, corr_thresh
        integer           :: iptcl, inptcls, prev_state, istate
        integer           :: statecnt(p%nstates)

        inptcls = p%top - p%fromp + 1

        ! SET FRACTION OF SEARCH SPACE
        frac_srch_space = b%a%get_avg('frac')

        ! SET BAND-PASS LIMIT RANGE
        call set_bp_range( b, p, cline )

        ! CALCULATE ANGULAR THRESHOLD (USED BY THE SPARSE WEIGHTING SCHEME)
        p%athres = rad2deg( atan(max(p%fny,p%lp)/(p%moldiam/2.) ))
        reslim   = p%lp
        if( DEBUG ) write(*,*) '*** hadamard3D_matcher ***: calculated angular threshold (used by the sparse weighting scheme)'

        ! DETERMINE THE NUMBER OF PEAKS
        if( .not. cline%defined('npeaks') )then
            select case(p%refine)
                case('no', 'neigh', 'greedy', 'greedyneigh')
                    p%npeaks = min(MAXNPEAKS,b%e%find_npeaks(p%lp, p%moldiam))
                case DEFAULT
                    p%npeaks = 1
            end select
            if( DEBUG ) write(*,*) '*** hadamard3D_matcher ***: determined the number of peaks'
        endif

        ! RANDOM MODEL GENERATION
        if( p%vols(1) .eq. '' .and. p%nstates==1 )then
            if( p%nptcls > 1000 )then
                call gen_random_model(b, p, 1000)
            else
                call gen_random_model(b, p)
            endif
            if( DEBUG ) write(*,*) '*** hadamard3D_matcher ***: generated random model'
        endif

        ! SETUP WEIGHTS
        if( p%nptcls <= SPECWMINPOP )then
            call b%a%calc_hard_ptcl_weights(p%frac)
        else
            call b%a%calc_spectral_weights(p%frac)
        endif

        ! EXTREMAL LOGICS
        if( p%refine.eq.'het' )then
            if( frac_srch_space < 98. .or. p%extr_thresh > 0.025 )then
                corr_thresh  = b%a%extremal_bound(p%extr_thresh)
                statecnt(:)  = 0
            else
                corr_thresh = -huge(corr_thresh)
            endif
        endif       

        ! PREPARE THE POLARFT_CORRCALC DATA STRUCTURE
        if( p%refine.eq.'het' )then
            ! generate filename for memoization of particle pfts
            if( allocated(ppfts_fname) ) deallocate(ppfts_fname)
            if( p%l_distr_exec )then
                allocate( ppfts_fname, source='ppfts_memoized_part'//int2str_pad(p%part,p%numlen)//'.bin' )
            else
                allocate( ppfts_fname, source='ppfts_memoized.bin' )
            endif
            ! generate projections (polar FTs)
            call preppftcc4align( b, p, cline, ppfts_fname )
        else
            ! generate projections (polar FTs)
            call preppftcc4align( b, p, cline )
        endif
        
        ! INITIALIZE
        write(*,'(A,1X,I3)') '>>> PRIME3D DISCRETE STOCHASTIC SEARCH, ITERATION:', which_iter
        if( .not. p%l_distr_exec )then
            if( p%refine .eq. 'snhc')then
                p%outfile = SNHCDOC
            else
                p%outfile = 'prime3Ddoc_'//int2str_pad(which_iter,3)//'.txt'
            endif
        endif

        ! STOCHASTIC IMAGE ALIGNMENT
        ! create the search objects, need to re-create every round because parameters are changing
        allocate( primesrch3D(p%fromp:p%top) )
        do iptcl=p%fromp,p%top
            call primesrch3D(iptcl)%new(b%a, p, pftcc)
        end do
        ! prep ctf & filter
        if(p%ctf .ne. 'no') call pftcc%create_polar_ctfmats(b%a)
        ! execute the search
        call del_file(p%outfile)
        select case(p%refine)
            case( 'snhc' )
                !$omp parallel do default(shared) schedule(guided) private(iptcl) proc_bind(close)
                do iptcl=p%fromp,p%top
                    call primesrch3D(iptcl)%exec_prime3D_srch(pftcc, iptcl, b%a, b%e, p%lp, szsn=p%szsn)
                end do
                !$omp end parallel do
            case( 'no','shc' )
                if( p%oritab .eq. '' )then
                    !$omp parallel do default(shared) schedule(guided) private(iptcl) proc_bind(close)
                    do iptcl=p%fromp,p%top
                        call primesrch3D(iptcl)%exec_prime3D_srch(pftcc, iptcl, b%a, b%e, p%lp, greedy=.true.)
                    end do
                    !$omp end parallel do
                else
                    !$omp parallel do default(shared) schedule(guided) private(iptcl) proc_bind(close)
                    do iptcl=p%fromp,p%top
                        call primesrch3D(iptcl)%exec_prime3D_srch(pftcc, iptcl, b%a, b%e, p%lp)
                    end do
                    !$omp end parallel do
                endif
            case('neigh','shcneigh')
                if( p%oritab .eq. '' ) stop 'cannot run the refine=neigh mode without input oridoc (oritab)'
                !$omp parallel do default(shared) schedule(guided) private(iptcl) proc_bind(close)
                do iptcl=p%fromp,p%top
                    call primesrch3D(iptcl)%exec_prime3D_srch(pftcc, iptcl, b%a,&
                        b%e, p%lp, nnmat=b%nnmat, grid_projs=b%grid_projs)
                end do
                !$omp end parallel do
            case('greedy')
                !$omp parallel do default(shared) schedule(guided) private(iptcl) proc_bind(close)
                do iptcl=p%fromp,p%top
                    call primesrch3D(iptcl)%exec_prime3D_srch(pftcc, iptcl, b%a, b%e, p%lp, greedy=.true.)
                end do
                !$omp end parallel do
            case('greedyneigh')
                !$omp parallel do default(shared) schedule(guided) private(iptcl) proc_bind(close)
                do iptcl=p%fromp,p%top
                    call primesrch3D(iptcl)%exec_prime3D_srch(pftcc, iptcl, b%a, b%e, p%lp,&
                        greedy=.true., nnmat=b%nnmat, grid_projs=b%grid_projs)
                end do
                !$omp end parallel do
            case('het')
                if(p%oritab .eq. '') stop 'cannot run the refine=het mode without input oridoc (oritab)'
                if( corr_thresh > 0. )then
                    write(*,'(A,F8.2)') '>>> PARTICLE RANDOMIZATION(%):', 100.*p%extr_thresh
                    write(*,'(A,F8.2)') '>>> CORRELATION THRESHOLD:    ', corr_thresh
                endif
                !$omp parallel do default(shared) schedule(guided) private(iptcl) reduction(+:statecnt) proc_bind(close)
                do iptcl=p%fromp,p%top
                    call primesrch3D(iptcl)%exec_prime3D_srch_het(pftcc, iptcl, b%a, b%e, corr_thresh, statecnt)
                end do
                !$omp end parallel do
                if(corr_thresh > 0.)then
                    norm = real(sum(statecnt))
                    do istate=1,p%nstates
                        print *,'% randomized ptcls for state ',istate,' is ',100.*(real(statecnt(istate))/norm),&
                            &'; pop=',statecnt(istate)
                    end do
                endif
            case DEFAULT
                write(*,*) 'The refinement mode: ', trim(p%refine), ' is unsupported'
                stop
        end select
        call pftcc%kill

        ! output orientations
        call b%a%write(p%outfile, [p%fromp,p%top])
        p%oritab = p%outfile

        ! volumetric 3d reconstruction
        if( p%norec .eq. 'no' )then
            ! init volumes
            call preprecvols(b, p)
            ! reconstruction
            do iptcl=p%fromp,p%top
                orientation = b%a%get_ori(iptcl)
                prev_state  = nint( orientation%get('state') )
                if( prev_state > 0 )then
                    call read_img_from_stk( b, p, iptcl )
                    if( p%npeaks > 1 )then
                        call primesrch3D(iptcl)%get_oris(prime3D_oris, orientation)
                        call grid_ptcl(b, p, orientation, prime3D_oris)
                    else
                        call grid_ptcl(b, p, orientation)
                    endif
                endif
            end do
            ! normalise structure factors
            if( p%eo .eq. 'yes' )then
                call eonorm_struct_facts(b, p, reslim, which_iter)
            else
                call norm_struct_facts(b, p, which_iter)
            endif
            ! destruct volumes
            call killrecvols(b, p)
        endif

        ! destruct
        do iptcl=p%fromp,p%top
            call primesrch3D(iptcl)%kill
        end do
        deallocate( primesrch3D )
        call prime3D_oris%kill

        ! report convergence
        if( p%l_distr_exec )then
            call qsys_job_finished( p, 'simple_hadamard3D_matcher :: prime3D_exec')
        else
            if( p%refine .eq. 'het' )then
                converged = b%conv%check_conv_het()
            else
                converged = b%conv%check_conv3D(update_res)
            endif
        endif
    end subroutine prime3D_exec

    subroutine gen_random_model( b, p, nsamp_in )
        use simple_ran_tabu,   only: ran_tabu
        use simple_kbinterpol, only: kbinterpol
        class(build),      intent(inout) :: b
        class(params),     intent(inout) :: p
        integer, optional, intent(in)    :: nsamp_in
        type(ran_tabu)       :: rt
        integer, allocatable :: sample(:)
        integer              :: i, k, nsamp, alloc_stat
        type(kbinterpol)     :: kbwin
        if( p%vols(1) == '' )then
            ! init volumes
            call preprecvols(b, p)
            p%oritab = 'prime3D_startdoc.txt'
            call b%a%rnd_oris
            call b%a%zero_shifts
            if( p%l_distr_exec .and. p%part.ne.1 )then
                ! so random oris only written once in distributed mode
            else
                call b%a%write( p%oritab )
            endif
            p%vols(1) = 'startvol'//p%ext
            if( p%noise .eq. 'yes' )then
                call b%vol%ran
                call b%vol%write(p%vols(1), del_if_exists=.true.)
                return
            endif
            nsamp = p%nptcls
            if( present(nsamp_in) ) nsamp = nsamp_in
            allocate( sample(nsamp), stat=alloc_stat )
            call alloc_err("In: gen_random_model; simple_hadamard3D_matcher", alloc_stat)
            if( present(nsamp_in) )then
                rt = ran_tabu(p%nptcls)
                call rt%ne_ran_iarr(sample)
                call rt%kill
            else
                forall(i=1:nsamp) sample(i) = i
            endif
            write(*,'(A)') '>>> RECONSTRUCTING RANDOM MODEL'
            kbwin = b%recvols(1)%get_kbwin()
            do i=1,nsamp
                call progress(i, nsamp)
                orientation = b%a%get_ori(sample(i))
                call b%img%read(p%stk, sample(i), isxfel=p%l_xfel)
                if( p%l_xfel )then
                    call b%img%pad(b%img_pad)
                else
                    call prep4cgrid(b%img, b%img_pad, p%msk, kbwin)
                endif
                if( p%pgrp == 'c1' )then
                    call b%recvols(1)%inout_fplane(orientation, .true., b%img_pad)
                else
                    do k=1,b%se%get_nsym()
                        o_sym = b%se%apply(orientation, k)
                        call b%recvols(1)%inout_fplane(o_sym, .true., b%img_pad)
                    end do
                endif
            end do
            deallocate(sample)
            call norm_struct_facts(b, p)
            call killrecvols(b, p)
        endif
    end subroutine gen_random_model

    subroutine preppftcc4align( b, p, cline, ppfts_fname )
        class(build),               intent(inout) :: b
        class(params),              intent(inout) :: p
        class(cmdline),             intent(inout) :: cline
        character(len=*), optional, intent(in)    :: ppfts_fname
        integer :: nrefs
        if( .not. p%l_distr_exec ) write(*,'(A)') '>>> BUILDING PRIME3D SEARCH ENGINE'
        ! must be done here since p%kfromto is dynamically set based on FSC from previous round
        ! or based on dynamic resolution limit update
        nrefs = p%nspace*p%nstates
        if( p%l_xfel )then
            call pftcc%new(nrefs, [p%fromp,p%top], [p%boxmatch,p%boxmatch,1],&
            p%smpd, p%kfromto, p%ring2, p%ctf, isxfel='yes')
        else
            call pftcc%new(nrefs, [p%fromp,p%top], [p%boxmatch,p%boxmatch,1],&
            p%smpd, p%kfromto, p%ring2, p%ctf)
        endif
        call prep_refs_pftcc4align( b, p, cline )
        call prep_ptcls_pftcc4align( b, p, ppfts_fname )
        ! subtract the mean shell values for xfel correlations
        if( p%l_xfel ) call pftcc%xfel_subtract_shell_mean()
        if( DEBUG ) write(*,*) '*** hadamard3D_matcher ***: finished preppftcc4align'
    end subroutine preppftcc4align

    subroutine prep_refs_pftcc4align( b, p, cline )
        class(build),   intent(inout) :: b
        class(params),  intent(inout) :: p
        class(cmdline), intent(inout) :: cline
        type(ori)         :: o
        integer           :: cnt, s, iref, nrefs
        ! PREPARATION OF REFERENCES IN PFTCC
        ! read reference volumes and create polar projections
        nrefs = p%nspace*p%nstates
        cnt   = 0
        if( .not. p%l_distr_exec ) write(*,'(A)') '>>> BUILDING REFERENCES'
        do s=1,p%nstates
            if( p%oritab .ne. '' )then
                ! greedy start
                if( b%a%get_statepop(s) == 0 )then
                    ! empty state
                    cnt = cnt + p%nspace
                    call progress(cnt, nrefs)
                    cycle
                endif
            endif
            call preprefvol( b, p, cline, s )
            ! generate discrete projections
            do iref=1,p%nspace
                cnt = cnt+1
                call progress(cnt, nrefs)
                o = b%e%get_ori(iref)
                call b%vol%fproject_polar(cnt, o, pftcc)
            end do
        end do
        ! cleanup
        call b%vol%kill_expanded
        ! bring back the original b%vol size for clean exit
        if( p%boxmatch < p%box )call b%vol%new([p%box,p%box,p%box], p%smpd)
    end subroutine prep_refs_pftcc4align

    subroutine prep_ptcls_pftcc4align( b, p, ppfts_fname )
        class(build),               intent(inout) :: b
        class(params),              intent(inout) :: p
        character(len=*), optional, intent(in)    :: ppfts_fname
        ! read particle images and create polar projections
        if( present(ppfts_fname) )then
            if( file_exists(ppfts_fname) )then
                call pftcc%read_pfts_ptcls(ppfts_fname)
            else
                call prep_pftcc_local
                call pftcc%write_pfts_ptcls(ppfts_fname)
            endif
        else
            call prep_pftcc_local
        endif

        contains

            subroutine prep_pftcc_local
                type(ori) :: o
                integer   :: cnt, s, iptcl, istate, ntot
                if( .not. p%l_distr_exec ) write(*,'(A)') '>>> BUILDING PARTICLES'
                ! initialize
                call b%img_match%init_polarizer(pftcc)
                ntot = p%top-p%fromp+1
                cnt  = 0
                do s=1,p%nstates
                    if( b%a%get_statepop(s) == 0 )then
                        ! empty state
                        cycle
                    endif
                    do iptcl=p%fromp,p%top
                        o      = b%a%get_ori(iptcl)
                        istate = nint(o%get('state'))
                        if( istate /= s ) cycle
                        cnt = cnt + 1
                        call progress(cnt, ntot)
                        call read_img_from_stk( b, p, iptcl )
                        call prepimg4align(b, p, o)
                        call b%img_match%polarize(pftcc, iptcl)
                    end do
                end do
                call progress(ntot, ntot)
            end subroutine prep_pftcc_local
        
    end subroutine prep_ptcls_pftcc4align

end module simple_hadamard3D_matcher

! projection-matching based on Hadamard products, high-level search routines for PRIME3D
module simple_strategy3D_matcher
!$ use omp_lib
!$ use omp_lib_kinds
#include "simple_lib.f08"
use simple_polarft_corrcalc,         only: polarft_corrcalc
use simple_ori,                      only: ori
use simple_oris,                     only: oris
use simple_build,                    only: build
use simple_params,                   only: params
use simple_cmdline,                  only: cmdline
use simple_binoris_io,               only: binwrite_oritab
use simple_kbinterpol,               only: kbinterpol
use simple_prep4cgrid,               only: prep4cgrid
use simple_strategy3D,               only: strategy3D
use simple_strategy3D_srch,          only: strategy3D_spec
use simple_strategy3D_alloc,         only: o_peaks, clean_strategy3D, prep_strategy3D
use simple_strategy3D_cluster,       only: strategy3D_cluster
use simple_strategy3D_single,        only: strategy3D_single
use simple_strategy3D_multi,         only: strategy3D_multi
use simple_strategy3D_snhc_single,   only: strategy3D_snhc_single
use simple_strategy3D_greedy_single, only: strategy3D_greedy_single
use simple_strategy3D_greedy_multi,  only: strategy3D_greedy_multi
use simple_strategy2D3D_common       ! use all in there
use simple_timer                     ! use all in there
implicit none

public :: prime3D_find_resrange, prime3D_exec, gen_random_model
public :: preppftcc4align, pftcc
private
#include "simple_local_flags.inc"

logical, parameter             :: L_BENCH = .false.
type(polarft_corrcalc), target :: pftcc
integer, allocatable           :: pinds(:)
logical, allocatable           :: ptcl_mask(:)
integer                        :: nptcls2update
integer(timer_int_kind)        :: t_init, t_prep_pftcc, t_align, t_rec, t_tot, t_prep_primesrch3D
real(timer_int_kind)           :: rt_init, rt_prep_pftcc, rt_align, rt_rec, rt_prep_primesrch3D
real(timer_int_kind)           :: rt_tot
character(len=STDLEN)          :: benchfname

contains

    subroutine prime3D_find_resrange( b, p, lp_start, lp_finish )
        use simple_oris, only: oris
        class(build),  intent(inout) :: b
        class(params), intent(inout) :: p
        real,          intent(out)   :: lp_start, lp_finish
        real, allocatable :: peaks(:)
        type(oris)        :: o
        integer :: lfny, k, pos10, pos6
        call o%new(p%nspace)
        call o%spiral
        lfny = b%img_match%get_lfny(1)
        allocate( peaks(lfny), stat=alloc_stat )
        allocchk("In: prime3D_find_resrange, simple_strategy3D_matcher")
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
        use simple_fileio,    only: del_file
        use simple_sym,       only: sym
        use simple_image,     only: image
        class(build),  target, intent(inout) :: b
        class(params), target, intent(inout) :: p
        class(cmdline),        intent(inout) :: cline
        integer,               intent(in)    :: which_iter
        logical,               intent(inout) :: update_res, converged
        type(image),     allocatable :: rec_imgs(:)
        integer, target, allocatable :: symmat(:,:)
        logical,         allocatable :: het_mask(:)
        class(strategy3D), pointer   :: strategy3Dsrch(:)
        type(strategy3D_spec) :: strategy3Dspec
        type(ori)             :: orientation
        type(kbinterpol)      :: kbwin
        type(sym)             :: c1_symop
        type(prep4cgrid)      :: gridprep
        character(len=STDLEN) :: fname, refine
        real    :: skewness, frac_srch_space, reslim, extr_thresh, corr_thresh
        integer :: iptcl, iextr_lim, i, zero_pop, fnr, cnt, i_batch, batchlims(2), ibatch
        logical :: doprint, do_extr

        if( L_BENCH )then
            t_init = tic()
            t_tot  = t_init
        endif

        ! CHECK THAT WE HAVE AN EVEN/ODD PARTITIONING
        if( p%eo .ne. 'no' )then
            if( p%l_distr_exec )then
                if( b%a%get_nevenodd() == 0 ) stop 'ERROR! no eo partitioning available; strategy3D_matcher :: prime2D_exec'
            else
                if( b%a%get_nevenodd() == 0 ) call b%a%partition_eo
            endif
        else
            call b%a%set_all2single('eo', -1.)
        endif

        ! SET FOURIER INDEX RANGE
        call set_bp_range( b, p, cline )

        ! CALCULATE ANGULAR THRESHOLD (USED BY THE SPARSE WEIGHTING SCHEME)
        p%athres = rad2deg( atan(max(p%fny,p%lp)/(p%moldiam/2.) ))
        reslim   = p%lp
        DebugPrint '*** strategy3D_matcher ***: calculated angular threshold (used by the sparse weighting scheme)'

        ! DETERMINE THE NUMBER OF PEAKS
        if( .not. cline%defined('npeaks') )then
            select case(p%refine)
            case('cluster', 'snhc', 'clustersym', 'clusterdev')
                    p%npeaks = 1
                case DEFAULT
                    if( p%eo .ne. 'no' )then
                        p%npeaks = min(b%e%find_npeaks_from_athres(NPEAKSATHRES), MAXNPEAKS)
                    else
                        p%npeaks = min(10,b%e%find_npeaks(p%lp, p%moldiam))
                    endif
            end select
            DebugPrint '*** strategy3D_matcher ***: determined the number of peaks'
        endif

        ! RANDOM MODEL GENERATION
        if( p%vols(1) .eq. '' .and. p%nstates == 1 )then
            if( p%nptcls > 1000 )then
                call gen_random_model(b, p, 1000)
            else
                call gen_random_model(b, p)
            endif
            DebugPrint '*** strategy3D_matcher ***: generated random model'
        endif

        ! SET FRACTION OF SEARCH SPACE
        frac_srch_space = b%a%get_avg('frac')

        ! SETUP WEIGHTS
        if( p%weights3D.eq.'yes' )then
            if( p%nptcls <= SPECWMINPOP )then
                call b%a%calc_hard_weights(p%frac)
            else
                call b%a%calc_spectral_weights(p%frac)
            endif
        else
            call b%a%calc_hard_weights(p%frac)
        endif

        ! READ FOURIER RING CORRELATIONS
        if( file_exists(p%frcs) ) call b%projfrcs%read(p%frcs)

        ! POPULATION BALANCING LOGICS
        ! this needs to be done prior to search such that each part
        ! sees the same information in distributed execution
        if( p%balance > 0 )then
            call b%a%balance( p%balance, NSPACE_BALANCE, p%nsym, p%eullims, skewness )
            write(*,'(A,F8.2)') '>>> PROJECTION DISTRIBUTION SKEWNESS(%):', 100. * skewness
        else
            call b%a%set_all2single('state_balance', 1.0)
        endif

        ! PARTICLE INDEX SAMPLING FOR FRACTIONAL UPDATE (OR NOT)
        if( allocated(pinds) )     deallocate(pinds)
        if( allocated(ptcl_mask) ) deallocate(ptcl_mask)
        if( p%l_frac_update )then
            allocate(ptcl_mask(p%fromp:p%top))
            call b%a%sample4update_and_incrcnt([p%fromp,p%top], p%update_frac, nptcls2update, pinds, ptcl_mask)
            ! correct convergence stats
            do iptcl=p%fromp,p%top
                if( .not. ptcl_mask(iptcl) )then
                    ! these are not updated
                    call b%a%set(iptcl, 'mi_proj',     1.0)
                    call b%a%set(iptcl, 'mi_inpl',     1.0)
                    call b%a%set(iptcl, 'mi_state',    1.0)
                    call b%a%set(iptcl, 'mi_joint',    1.0)
                    call b%a%set(iptcl, 'dist',        0.0)
                    call b%a%set(iptcl, 'dist_inpl',   0.0)
                    call b%a%set(iptcl, 'frac',      100.0)
                endif
            end do
        else
            nptcls2update = p%top - p%fromp + 1
            allocate(pinds(nptcls2update), ptcl_mask(p%fromp:p%top))
            pinds = (/(i,i=p%fromp,p%top)/)
            ptcl_mask = .true.
        endif

        ! EXTREMAL LOGICS
        do_extr  = .false.
        select case(trim(p%refine))
        case('cluster','clusterdev','clustersym')
                if(allocated(het_mask))deallocate(het_mask)
                allocate(het_mask(p%fromp:p%top), source=ptcl_mask)
                zero_pop    = count(.not.b%a%included(consider_w=.false.))
                corr_thresh = -huge(corr_thresh)
                if(p%l_frac_update) then
                    ptcl_mask = .true.
                    iextr_lim = ceiling(2.*log(real(p%nptcls-zero_pop)) * (2.-p%update_frac))
                    if( which_iter==1 .or.(frac_srch_space <= 99. .and. p%extr_iter <= iextr_lim) )&
                        &do_extr = .true.
                else
                    iextr_lim = ceiling(2.*log(real(p%nptcls-zero_pop)))
                    if( which_iter==1 .or.(frac_srch_space <= 98. .and. p%extr_iter <= iextr_lim) )&
                        &do_extr = .true.
                endif
                if( do_extr )then
                    extr_thresh = EXTRINITHRESH * cos(PI/2. * real(p%extr_iter-1)/real(iextr_lim))
                    corr_thresh = b%a%extremal_bound(extr_thresh)
                endif
                if(trim(p%refine).eq.'clustersym')then
                   ! symmetry pairing matrix
                    c1_symop = sym('c1')
                    p%nspace = min( p%nspace*b%se%get_nsym(), 3000 )
                    call b%e%new( p%nspace )
                    call b%e%spiral
                    call b%se%nearest_sym_neighbors( b%e, symmat )
                endif
            case DEFAULT
                ! nothing to do
        end select
        if( L_BENCH ) rt_init = toc(t_init)

        ! PREPARE THE POLARFT_CORRCALC DATA STRUCTURE
        if( L_BENCH ) t_prep_pftcc = tic()
        call preppftcc4align( b, p, cline )
        if( L_BENCH ) rt_prep_pftcc = toc(t_prep_pftcc)

        write(*,'(A,1X,I3)') '>>> PRIME3D DISCRETE STOCHASTIC SEARCH, ITERATION:', which_iter
        if( .not. p%l_distr_exec )then
            if( p%refine .eq. 'snhc')then
                p%outfile = trim(SNHCDOC)
            else
                p%outfile = trim(REFINE3D_ITER_FBODY)//int2str_pad(which_iter,3)//trim(METADATA_EXT)
            endif
        endif

        ! STOCHASTIC IMAGE ALIGNMENT
        if( L_BENCH ) t_prep_primesrch3D = tic()
        ! clean big objects before starting to allocate new big memory chunks
        if( p%l_distr_exec )then
            call b%vol%kill
            call b%vol2%kill
        endif
        ! array allocation for strategy3D
        call prep_strategy3D( b, p, ptcl_mask )
        if( L_BENCH ) rt_prep_primesrch3D = toc(t_prep_primesrch3D)
        ! switch for polymorphic strategy3D construction
        if( p%oritab.eq.'' )then
            if( p%nstates==1 )then
                refine = 'greedy_single'
            else
                stop 'Refinement mode unsupported'
            endif
        else
            refine = p%refine
        endif
        select case(trim(refine))
            case('snhc')
                allocate(strategy3D_snhc_single   :: strategy3Dsrch(p%fromp:p%top))
            case('single')
                allocate(strategy3D_single        :: strategy3Dsrch(p%fromp:p%top))
            case('multi')
                allocate(strategy3D_multi         :: strategy3Dsrch(p%fromp:p%top))
            case('greedy_single')
                allocate(strategy3D_greedy_single :: strategy3Dsrch(p%fromp:p%top))
            case('greedy_multi')
                allocate(strategy3D_greedy_multi  :: strategy3Dsrch(p%fromp:p%top))
            case('cluster','clustersym','clusterdev')
                allocate(strategy3D_cluster       :: strategy3Dsrch(p%fromp:p%top))
            case DEFAULT
                write(*,*) 'refine flag: ', trim(refine)
                stop 'Refinement mode unsupported'
        end select
        ! actual construction
        cnt = 0
        do iptcl=p%fromp,p%top
            if( ptcl_mask(iptcl) )then
                cnt = cnt + 1
                ! search spec
                strategy3Dspec%iptcl       =  iptcl
                strategy3Dspec%iptcl_map   =  cnt
                strategy3Dspec%szsn        =  p%szsn
                strategy3Dspec%corr_thresh =  corr_thresh
                strategy3Dspec%pp          => p
                strategy3Dspec%ppftcc      => pftcc
                strategy3Dspec%pa          => b%a
                strategy3Dspec%pse         => b%se
                if(allocated(b%nnmat))      strategy3Dspec%nnmat      => b%nnmat
                if(allocated(b%grid_projs)) strategy3Dspec%grid_projs => b%grid_projs
                if( allocated(het_mask) )   strategy3Dspec%do_extr    =  het_mask(iptcl)
                if( allocated(symmat) )     strategy3Dspec%symmat     => symmat
                ! search object
                call strategy3Dsrch(iptcl)%new(strategy3Dspec)
            endif
        end do
        ! memoize CTF matrices
        if( p%ctf .ne. 'no' ) call pftcc%create_polar_ctfmats(b%a)
        ! memoize FFTs for improved performance
        call pftcc%memoize_ffts
        ! memoize B-factors
        if( p%objfun.eq.'ccres' ) call pftcc%memoize_bfacs(b%a)
        ! search
        call del_file(p%outfile)
        if( L_BENCH ) t_align = tic()
        !$omp parallel do default(shared) private(i,iptcl) schedule(static) proc_bind(close)
        do i=1,nptcls2update
            iptcl = pinds(i)
            call strategy3Dsrch(iptcl)%srch
        end do
        !$omp end parallel do
        ! clean
        call clean_strategy3D()
        call pftcc%kill
        do iptcl = p%fromp,p%top
            if( ptcl_mask(iptcl) ) call strategy3Dsrch(iptcl)%kill
        end do
        deallocate(strategy3Dsrch)
        if( L_BENCH ) rt_align = toc(t_align)
        if( allocated(symmat)   ) deallocate(symmat)
        if( allocated(het_mask) ) deallocate(het_mask)

        ! OUTPUT ORIENTATIONS
        call binwrite_oritab(p%outfile, b%spproj, b%a, [p%fromp,p%top])
        p%oritab = p%outfile

        ! VOLUMETRIC 3D RECONSTRUCTION
        if( L_BENCH ) t_rec = tic()
        if( p%norec .ne. 'yes' )then
            ! make the gridding prepper
            if( p%eo .ne. 'no' )then
                kbwin = b%eorecvols(1)%get_kbwin()
            else
                kbwin = b%recvols(1)%get_kbwin()
            endif
            call gridprep%new(b%img, kbwin, [p%boxpd,p%boxpd,1])
            ! init volumes
            call preprecvols(b, p)
            ! prep rec imgs
            allocate(rec_imgs(MAXIMGBATCHSZ))
            do i=1,MAXIMGBATCHSZ
                call rec_imgs(i)%new([p%boxpd, p%boxpd, 1], p%smpd)
            end do
            ! prep batch imgs
            call prepimgbatch(b, p, MAXIMGBATCHSZ)
            ! gridding batch loop
            do i_batch=1,nptcls2update,MAXIMGBATCHSZ
                batchlims = [i_batch,min(nptcls2update,i_batch + MAXIMGBATCHSZ - 1)]
                call read_imgbatch(b, p, nptcls2update, pinds, batchlims)
                ! parallel gridprep
                !$omp parallel do default(shared) private(i,ibatch) schedule(static) proc_bind(close)
                do i=batchlims(1),batchlims(2)
                    ibatch = i - batchlims(1) + 1
                    ! normalise (read_imgbatch does not normalise)
                    call b%imgbatch(ibatch)%norm()
                    ! in dev=yes code, we filter before inserting into 3D vol
                    call gridprep%prep_serial_no_fft(b%imgbatch(ibatch), rec_imgs(ibatch))
                end do
                !$omp end parallel do
                ! gridding
                do i=batchlims(1),batchlims(2)
                    iptcl       = pinds(i)
                    ibatch      = i - batchlims(1) + 1
                    orientation = b%a%get_ori(iptcl)
                    if( orientation%isstatezero() .or. nint(orientation%get('state_balance')) == 0 ) cycle
                    if( trim(p%refine).eq.'clustersym' )then
                        ! always C1 reconstruction
                        call grid_ptcl(b, p, rec_imgs(ibatch), c1_symop, orientation, o_peaks(iptcl))
                    else
                        call grid_ptcl(b, p, rec_imgs(ibatch), b%se, orientation, o_peaks(iptcl))
                    endif
                end do
            end do
            ! normalise structure factors
            if( p%eo .ne. 'no' )then
                call eonorm_struct_facts(b, p, cline, reslim, which_iter)
            else
                call norm_struct_facts(b, p, which_iter)
            endif
            ! destruct
            call killrecvols(b, p)
            call gridprep%kill
            do ibatch=1,MAXIMGBATCHSZ
                call rec_imgs(ibatch)%kill
                call b%imgbatch(ibatch)%kill
            end do
            deallocate(rec_imgs, b%imgbatch)
            call gridprep%kill
        endif
        if( L_BENCH ) rt_rec = toc(t_rec)

        ! REPORT CONVERGENCE
        if( p%l_distr_exec )then
            call qsys_job_finished( p, 'simple_strategy3D_matcher :: prime3D_exec')
        else
            select case(trim(p%refine))
            case('cluster','clustersym','clusterdev')
                    converged = b%conv%check_conv_cluster()
                case DEFAULT
                    converged = b%conv%check_conv3D(update_res)
            end select
        endif
        if( L_BENCH )then
            rt_tot  = toc(t_tot)
            doprint = .true.
            if( p%l_distr_exec .and. p%part /= 1 ) doprint = .false.
            if( doprint )then
                benchfname = 'HADAMARD3D_BENCH_ITER'//int2str_pad(which_iter,3)//'.txt'
                call fopen(fnr, FILE=trim(benchfname), STATUS='REPLACE', action='WRITE')
                write(fnr,'(a)') '*** TIMINGS (s) ***'
                write(fnr,'(a,1x,f9.2)') 'initialisation          : ', rt_init
                write(fnr,'(a,1x,f9.2)') 'pftcc preparation       : ', rt_prep_pftcc
                write(fnr,'(a,1x,f9.2)') 'primesrch3D preparation : ', rt_prep_primesrch3D
                write(fnr,'(a,1x,f9.2)') 'stochastic alignment    : ', rt_align
                write(fnr,'(a,1x,f9.2)') 'reconstruction          : ', rt_rec
                write(fnr,'(a,1x,f9.2)') 'total time              : ', rt_tot
                write(fnr,'(a)') ''
                write(fnr,'(a)') '*** RELATIVE TIMINGS (%) ***'
                write(fnr,'(a,1x,f9.2)') 'initialisation          : ', (rt_init/rt_tot)             * 100.
                write(fnr,'(a,1x,f9.2)') 'pftcc preparation       : ', (rt_prep_pftcc/rt_tot)       * 100.
                write(fnr,'(a,1x,f9.2)') 'primesrch3D preparation : ', (rt_prep_primesrch3D/rt_tot) * 100.
                write(fnr,'(a,1x,f9.2)') 'stochastic alignment    : ', (rt_align/rt_tot)            * 100.
                write(fnr,'(a,1x,f9.2)') 'reconstruction          : ', (rt_rec/rt_tot)              * 100.
                write(fnr,'(a,1x,f9.2)') '% accounted for         : ',&
                    &((rt_init+rt_prep_pftcc+rt_prep_primesrch3D+rt_align+rt_rec)/rt_tot) * 100.
                call fclose(fnr)
            endif
        endif
    end subroutine prime3D_exec

    subroutine gen_random_model( b, p, nsamp_in )
        use simple_ran_tabu,   only: ran_tabu
        class(build),      intent(inout) :: b         !< build object
        class(params),     intent(inout) :: p         !< param object
        integer, optional, intent(in)    :: nsamp_in  !< num input samples
        type(ran_tabu)       :: rt
        type(ori)            :: orientation
        integer, allocatable :: sample(:)
        integer              :: i, nsamp, alloc_stat
        type(kbinterpol)     :: kbwin
        type(prep4cgrid)     :: gridprep
        if( p%vols(1) == '' )then
            ! init volumes
            call preprecvols(b, p)
            p%oritab = 'prime3D_startdoc'//trim(METADATA_EXT)
            if( trim(p%refine).eq.'tseries' )then
                call b%a%spiral
            else
                call b%a%rnd_oris
                call b%a%zero_shifts
            endif
            if( p%l_distr_exec .and. p%part.ne.1 )then
                ! so random oris only written once in distributed mode
            else
                call binwrite_oritab(p%oritab, b%spproj, b%a, [1,p%nptcls])
            endif
            p%vols(1) = 'startvol'//p%ext
            if( p%noise .eq. 'yes' )then
                call b%vol%ran
                call b%vol%write(p%vols(1), del_if_exists=.true.)
                return
            endif
            nsamp = p%top - p%fromp + 1
            if( present(nsamp_in) ) nsamp = nsamp_in
            allocate( sample(nsamp), stat=alloc_stat )
            call alloc_errchk("In: gen_random_model; simple_strategy3D_matcher", alloc_stat)
            if( present(nsamp_in) )then
                rt = ran_tabu(p%top - p%fromp + 1)
                call rt%ne_ran_iarr(sample)
                call rt%kill
            else
                forall(i=1:nsamp) sample(i) = i
            endif
            write(*,'(A)') '>>> RECONSTRUCTING RANDOM MODEL'
            ! make the gridding prepper
            kbwin = b%recvols(1)%get_kbwin()
            call gridprep%new(b%img, kbwin, [p%boxpd,p%boxpd,1])
            do i=1,nsamp
                call progress(i, nsamp)
                orientation = b%a%get_ori(sample(i) + p%fromp - 1)
                call read_img_and_norm( b, p, sample(i) + p%fromp - 1 )
                call gridprep%prep(b%img, b%img_pad)
                call b%recvols(1)%insert_fplane(b%se, orientation, b%img_pad, pwght=1.0)
            end do
            deallocate(sample)
            call norm_struct_facts(b, p)
            call killrecvols(b, p)
        endif
    end subroutine gen_random_model

    !> Prepare alignment search using polar projection Fourier cross correlation
    subroutine preppftcc4align( b, p, cline )
        use simple_polarizer, only: polarizer
        class(build),               intent(inout) :: b     !< build object
        class(params),              intent(inout) :: p     !< param object
        class(cmdline),             intent(inout) :: cline !< command line
        type(polarizer), allocatable :: match_imgs(:)
        integer   :: cnt, s, iptcl, ind, iref, nrefs
        integer   :: batchlims(2), imatch, iptcl_batch
        logical   :: do_center
        real      :: xyz(3)
        if( .not. p%l_distr_exec ) write(*,'(A)') '>>> BUILDING PRIME3D SEARCH ENGINE'
        nrefs  = p%nspace * p%nstates
        ! must be done here since p%kfromto is dynamically set based on FSC from previous round
        ! or based on dynamic resolution limit update
        if( p%eo .ne. 'no' )then
            call pftcc%new(nrefs, p, ptcl_mask, nint(b%a%get_all('eo', [p%fromp,p%top])))
        else
            call pftcc%new(nrefs, p, ptcl_mask)
        endif

        ! PREPARATION OF REFERENCES IN PFTCC
        ! read reference volumes and create polar projections
        cnt   = 0
        if( .not. p%l_distr_exec ) write(*,'(A)') '>>> BUILDING REFERENCES'
        do s=1,p%nstates
            if( p%oritab .ne. '' )then
                if( b%a%get_pop(s, 'state') == 0 )then
                    ! empty state
                    cnt = cnt + p%nspace
                    call progress(cnt, nrefs)
                    cycle
                endif
            endif
            call cenrefvol_and_mapshifts2ptcls(b, p, cline, s, p%vols(s), do_center, xyz)
            if( p%eo .ne. 'no' )then
                if( p%nstates.eq.1 )then
                    if( .not. p%l_distr_exec ) write(*,'(A)') '>>> BUILDING EVEN REFERENCES'
                    call preprefvol(b, p, cline, s, p%vols_even(s), do_center, xyz)
                    !$omp parallel do default(shared) private(iref) schedule(static) proc_bind(close)
                    do iref=1,p%nspace
                        call b%vol%fproject_polar((s - 1) * p%nspace + iref, b%e%get_ori(iref), pftcc, iseven=.true.)
                    end do
                    !$omp end parallel do
                    if( .not. p%l_distr_exec ) write(*,'(A)') '>>> BUILDING ODD REFERENCES'
                    call preprefvol(b, p, cline, s, p%vols_odd(s), do_center, xyz)
                    !$omp parallel do default(shared) private(iref) schedule(static) proc_bind(close)
                    do iref=1,p%nspace
                        call b%vol%fproject_polar((s - 1) * p%nspace + iref, b%e%get_ori(iref), pftcc, iseven=.false.)
                    end do
                    !$omp end parallel do
                else
                    if( .not. p%l_distr_exec ) write(*,'(A)') '>>> BUILDING REFERENCES'
                    call preprefvol(b, p, cline, s, p%vols(s), do_center, xyz)
                    !$omp parallel do default(shared) private(iref, ind) schedule(static) proc_bind(close)
                    do iref=1,p%nspace
                        ind = (s - 1) * p%nspace + iref
                        call b%vol%fproject_polar(ind, b%e%get_ori(iref), pftcc, iseven=.true.)
                        call pftcc%cp_even2odd_ref(ind)
                    end do
                    !$omp end parallel do
                endif
            else
                ! low-pass set or multiple states
                call preprefvol(b, p, cline, s, p%vols(s), do_center, xyz)
                !$omp parallel do default(shared) private(iref) schedule(static) proc_bind(close)
                do iref=1,p%nspace
                    call b%vol%fproject_polar((s - 1) * p%nspace + iref, b%e%get_ori(iref), pftcc, iseven=.true.)
                end do
                !$omp end parallel do
            endif
        end do
        ! cleanup
        call b%vol%kill_expanded
        ! bring back the original b%vol size
        call b%vol%new([p%box,p%box,p%box], p%smpd)

        ! PREPARATION OF PARTICLES IN PFTCC
        ! prepare the polarizer images
        call b%img_match%init_polarizer(pftcc, p%alpha)
        allocate(match_imgs(MAXIMGBATCHSZ))
        do imatch=1,MAXIMGBATCHSZ
            call match_imgs(imatch)%new([p%boxmatch, p%boxmatch, 1], p%smpd)
            call match_imgs(imatch)%copy_polarizer(b%img_match)
        end do
        call build_pftcc_particles( b, p, pftcc, MAXIMGBATCHSZ, match_imgs, .true., ptcl_mask)

        ! DESTRUCT
        do imatch=1,MAXIMGBATCHSZ
            call match_imgs(imatch)%kill_polarizer
            call match_imgs(imatch)%kill
            call b%imgbatch(imatch)%kill
        end do
        deallocate(match_imgs, b%imgbatch)

        DebugPrint '*** strategy3D_matcher ***: finished preppftcc4align'
    end subroutine preppftcc4align

end module simple_strategy3D_matcher
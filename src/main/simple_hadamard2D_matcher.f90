! projection-matching based on Hadamard products, high-level search routines for PRIME2D
module simple_hadamard2D_matcher
!$ use omp_lib
!$ use omp_lib_kinds
use simple_polarft_corrcalc, only: polarft_corrcalc
use simple_prime2D_srch,     only: prime2D_srch
use simple_ori,              only: ori
use simple_build,            only: build
use simple_params,           only: params
use simple_cmdline,          only: cmdline
use simple_strings,          only: int2str_pad
use simple_jiffys            ! use all in there
use simple_fileio            ! use all in there
use simple_hadamard_common   ! use all in there
use simple_filterer          ! use all in there
use simple_defs              ! use all in there
use simple_syslib            ! use all in there
implicit none

public :: prime2D_exec, prime2D_assemble_sums, prime2D_norm_sums, prime2D_assemble_sums_from_parts,&
prime2D_write_sums, preppftcc4align, pftcc, prime2D_read_sums, prime2D_write_partial_sums
private
#include "simple_local_flags.inc"

type(polarft_corrcalc)          :: pftcc
type(prime2D_srch), allocatable :: primesrch2D(:)

contains

    !>  \brief  is the prime2D algorithm
    subroutine prime2D_exec( b, p, cline, which_iter, converged )
        use simple_qsys_funs,   only: qsys_job_finished
        use simple_strings,     only: str_has_substr
        use simple_procimgfile, only: random_selection_from_imgfile
        use simple_binoris_io,  only: binwrite_oritab
        class(build),   intent(inout) :: b
        class(params),  intent(inout) :: p
        class(cmdline), intent(inout) :: cline
        integer,        intent(in)    :: which_iter
        logical,        intent(inout) :: converged
        logical, allocatable :: ptcl_mask(:)
        integer :: iptcl, icls
        real    :: corr_thresh, frac_srch_space, skewness, extr_thresh

        ! PREP REFERENCES
        if( p%l_distr_exec )then
            if( .not. cline%defined('refs') )then
                stop 'need refs to be part of command line for distributed prime2D execution'
            else if( cline%defined('refs') )then
                if( .not. file_exists(p%refs) ) stop 'input references (refs) does not exist in cwd'
            endif
            call prime2D_read_sums( b, p )
        else
            ! for shared-memory or chunk-based parallellisation we need initial references for iter=1 only
            if( which_iter == p%startit )then
                if( cline%defined('refs') )then
                    if( .not. file_exists(p%refs) ) stop 'input references (refs) does not exist in cwd'
                    call prime2D_read_sums( b, p )
                else
                    ! we need to make references
                    if( cline%defined('oritab') )then
                        ! we make class averages
                        call prime2D_assemble_sums(b, p)
                    else
                        ! we randomly select particle images as initial references
                        p%refs = 'start2Drefs'//p%ext
                        if( p%chunktag .ne. '' ) p%refs = trim(p%chunktag)//trim(p%refs)
                        ptcl_mask = b%a%included()
                        call random_selection_from_imgfile(p%stk, p%refs, p%ncls, p%box, p%smpd, ptcl_mask)
                        deallocate(ptcl_mask)
                        call prime2D_read_sums( b, p )
                    endif
                endif
            endif
        endif

        ! SET FRACTION OF SEARCH SPACE
        frac_srch_space = b%a%get_avg('frac')

        ! SETUP WEIGHTS
        ! this needs to be done prior to search such that each part
        ! sees the same information in distributed execution
        if( p%weights2D .eq. 'yes' .and. frac_srch_space >= FRAC_INTERPOL )then
            if( p%nptcls <= SPECWMINPOP )then
                call b%a%set_all2single('w', 1.0)
            else
                ! frac is one by default in prime2D (no option to set frac)
                ! so spectral weighting is done over all images
                call b%a%calc_spectral_weights(1.0, 'class', p%nsym, p%eullims)
            endif
        else
            ! defaults to unitary weights
            call b%a%set_all2single('w', 1.0)
        endif

        ! POPULATION BALANCING LOGICS
        ! this needs to be done prior to search such that each part
        ! sees the same information in distributed execution
        if( p%balance > 0 )then
            call b%a%balance(p%balance, skewness)
            write(*,'(A,F8.2)') '>>> CLASS DISTRIBUTION SKEWNESS(%):', 100. * skewness
        else
            call b%a%set_all2single('state_balance', 1.0)
        endif

        ! EXTREMAL LOGICS
        if( frac_srch_space < 98. .or. p%extr_iter <= 15 )then
            extr_thresh = EXTRINITHRESH * (1.-EXTRTHRESH_CONST)**real(p%extr_iter-1)  ! factorial decay
            extr_thresh = min(EXTRINITHRESH, max(0., extr_thresh))
            corr_thresh = b%a%extremal_bound(extr_thresh)
        else
            corr_thresh = -huge(corr_thresh)
        endif

        ! SET FOURIER INDEX RANGE
        call set_bp_range2D( b, p, cline, which_iter, frac_srch_space )

        ! GENERATE REFERENCE & PARTICLE POLAR FTs
        call preppftcc4align( b, p )

        ! INITIALIZE
        write(*,'(A,1X,I3)') '>>> PRIME2D DISCRETE STOCHASTIC SEARCH, ITERATION:', which_iter
        if( .not. p%l_distr_exec )then
            p%outfile = 'prime2Ddoc_'//int2str_pad(which_iter,3)//'.txt'
            if( p%chunktag .ne. '' ) p%outfile= trim(p%chunktag)//trim(p%outfile)
        endif

        ! STOCHASTIC IMAGE ALIGNMENT
        allocate( primesrch2D(p%fromp:p%top) )
        do iptcl=p%fromp,p%top
            call primesrch2D(iptcl)%new(p, pftcc)
        end do
        ! calculate CTF matrices
        if( p%ctf .ne. 'no' ) call pftcc%create_polar_ctfmats(b%a)
        ! execute the search
        call del_file(p%outfile)
        select case(trim(p%refine))
            case('neigh')
                !$omp parallel do default(shared) schedule(guided) private(iptcl) proc_bind(close)
                do iptcl=p%fromp,p%top
                    call primesrch2D(iptcl)%nn_srch(pftcc, iptcl, b%a, b%nnmat)
                end do
                !$omp end parallel do
            case DEFAULT
                if( p%oritab .eq. '' )then
                    !$omp parallel do default(shared) schedule(guided) private(iptcl) proc_bind(close)
                    do iptcl=p%fromp,p%top
                        call primesrch2D(iptcl)%exec_prime2D_srch(pftcc, iptcl, b%a, greedy=.true.)
                    end do
                    !$omp end parallel do
                else
                    if( corr_thresh > 0. )then
                        write(*,'(A,F8.2)') '>>> PARTICLE RANDOMIZATION(%):', 100.*extr_thresh
                        write(*,'(A,F8.2)') '>>> CORRELATION THRESHOLD:    ', corr_thresh
                    endif
                    !$omp parallel do default(shared) schedule(guided) private(iptcl) proc_bind(close)
                    do iptcl=p%fromp,p%top
                        call primesrch2D(iptcl)%exec_prime2D_srch(pftcc, iptcl, b%a, extr_bound=corr_thresh)
                    end do
                    !$omp end parallel do
                endif
        end select
        DebugPrint ' hadamard2D_matcher; completed alignment'

        ! REMAPPING OF HIGHEST POPULATED CLASSES
        if( p%l_distr_exec )then
            ! this is done in cavg_assemble
        else
            call b%a%fill_empty_classes()
        endif

        ! OUTPUT ORIENTATIONS
        call binwrite_oritab(p%outfile, b%a, [p%fromp,p%top])
        p%oritab = p%outfile

        ! WIENER RESTORATION OF CLASS AVERAGES
        ! if( frac_srch_space > FRAC_INTERPOL .and. which_iter > 1 )then
        if( frac_srch_space > FRAC_INTERPOL )then
            ! gridded rotation
            call prime2D_assemble_sums(b, p, grid=.true.)
        else
            ! real-space rotation
            call prime2D_assemble_sums(b, p, grid=.false.)
        endif
        DebugPrint ' generated class averages'

        ! OUTPUT CLASS AVERAGES
        if( p%l_distr_exec )then
            call prime2D_write_partial_sums( b, p )
        else
            call prime2D_write_sums( b, p, which_iter )
        endif

        ! DESTRUCT
        do iptcl=p%fromp,p%top
            call primesrch2D(iptcl)%kill
        end do
        deallocate( primesrch2D )
        call pftcc%kill

        ! REPORT CONVERGENCE
        if( p%l_distr_exec )then
            call qsys_job_finished(p, 'simple_hadamard2D_matcher :: prime2D_exec')
        else
            converged = b%conv%check_conv2D()
        endif
    end subroutine prime2D_exec

    subroutine prime2D_read_sums( b, p )
        class(build),  intent(inout) :: b
        class(params), intent(inout) :: p
        integer :: icls
        if( file_exists(p%refs) )then            
            do icls=1,p%ncls
                call b%cavgs(icls)%read(p%refs, icls)
            end do
        else
            write(*,*) 'File does not exists: ', trim(p%refs)
            stop 'In: simple_hadamard2D_matcher :: prime2D_read_sums'
        endif
    end subroutine prime2D_read_sums

    subroutine prime2D_init_sums( b, p )
        class(build),  intent(inout) :: b
        class(params), intent(inout) :: p
        integer :: icls
        !$omp parallel do schedule(static) default(shared) private(icls) proc_bind(close)
        do icls=1,p%ncls
            b%cavgs(icls) = 0.
            b%ctfsqsums(icls) = cmplx(0.,0.)
        end do
        !$omp end parallel do
    end subroutine prime2D_init_sums

    subroutine prime2D_assemble_sums( b, p, grid )
        use simple_projector_hlev, only: rot_imgbatch
        use simple_map_reduce,     only: split_nobjs_even
        use simple_oris,           only: oris
        use simple_ctf,            only: ctf
        class(build),      intent(inout) :: b
        class(params),     intent(inout) :: p
        logical, optional, intent(in)    :: grid
        type(oris)               :: a_here, batch_oris
        type(ori)                :: orientation
        type(image)              :: batch_imgsum, cls_imgsum
        type(image), allocatable :: batch_imgs(:) 
        integer,     allocatable :: ptcls_inds(:), batches(:,:)
        logical,     allocatable :: batch_mask(:)
        real      :: w
        integer   :: icls, iptcl, istart, iend, inptcls, icls_pop
        integer   :: i, nbatches, batch, batchsz, cnt
        logical   :: l_grid
        integer, parameter :: BATCHTHRSZ = 20
        l_grid = .true.
        if( present(grid) ) l_grid = grid
        if( .not. p%l_distr_exec )then
            write(*,'(a)') '>>> ASSEMBLING CLASS SUMS'
        endif
        ! init
        call prime2D_init_sums( b, p )
        if( p%l_distr_exec )then
            istart  = p%fromp
            iend    = p%top
            inptcls = iend - istart +1
            call a_here%new(inptcls)
            cnt = 0
            do iptcl = istart, iend
                cnt = cnt + 1
                call a_here%set_ori(cnt, b%a%get_ori(iptcl))
            enddo
        else
            istart  = 1
            iend    = p%nptcls
            inptcls = p%nptcls
            a_here  = b%a
        endif
        ! cluster loop
        do icls = 1, p%ncls
            call progress(icls,p%ncls)
            icls_pop = a_here%get_pop( icls, 'class' )
            if(icls_pop == 0)cycle
            call cls_imgsum%new([p%box, p%box, 1], p%smpd)
            ptcls_inds = a_here%get_pinds( icls, 'class' )
            ! batch planning
            nbatches = ceiling(real(icls_pop)/real(p%nthr*BATCHTHRSZ))
            batches  = split_nobjs_even(icls_pop, nbatches)
            ! batch loop
            do batch = 1, nbatches
                ! prep batch
                batchsz = batches(batch,2) - batches(batch,1) + 1
                allocate(batch_imgs(batchsz), batch_mask(batchsz))
                batch_mask = .true.
                call batch_oris%new(batchsz)
                ! batch particles loop
                do i = 1,batchsz
                    iptcl       = istart - 1 + ptcls_inds(batches(batch,1)+i-1)
                    orientation = b%a%get_ori(iptcl)
                    call batch_oris%set_ori(i, orientation)
                    ! stash images (this goes here or suffer bugs)
                    call read_img_from_stk( b, p, iptcl )
                    batch_imgs(i) = b%img
                    ! enforce state, balancing and weight exclusions
                    if( nint(orientation%get('state')) == 0 .or.&
                        &nint(orientation%get('state_balance')) == 0 .or.&
                        &orientation%get('w') < TINY )then
                        batch_mask(i) = .false.
                        cycle
                    endif
                    ! CTF square sum & shift
                    call apply_ctf_and_shift(batch_imgs(i), orientation)
                enddo
                if( l_grid )then
                    ! rotate batch by gridding
                    call rot_imgbatch(batch_imgs, batch_oris, batch_imgsum, p%msk, batch_mask)
                else
                    ! real space rotation
                    call batch_imgsum%new([p%box, p%box, 1], p%smpd)
                    do i = 1,batchsz
                        if( .not. batch_mask(i) ) cycle
                        iptcl = istart - 1 + ptcls_inds(batches(batch,1)+i-1)
                        orientation = b%a%get_ori(iptcl)
                        w = orientation%get('w')
                        call batch_imgs(i)%rtsq( -orientation%e3get(), 0., 0. )
                        call batch_imgsum%add(batch_imgs(i), w)
                    enddo
                endif
                ! batch summation
                call cls_imgsum%add( batch_imgsum )
                ! batch cleanup
                do i = 1, batchsz
                    call batch_imgs(i)%kill
                enddo
                deallocate(batch_imgs, batch_mask)
            enddo
            ! set class
            b%cavgs(icls) = cls_imgsum
            ! class cleanup
            deallocate(ptcls_inds)
        enddo
        if( .not.p%l_distr_exec ) call prime2D_norm_sums( b, p )

        contains

            !> image is shifted and Fted on exit and the class CTF square sum updated
            subroutine apply_ctf_and_shift( img, o )
                class(image), intent(inout) :: img
                class(ori),   intent(inout) :: o
                type(image) :: ctfsq
                type(ctf)   :: tfun
                real        :: dfx, dfy, angast, x, y, pw
                call ctfsq%new(img%get_ldim(), p%smpd)
                call ctfsq%set_ft(.true.)
                tfun = ctf(img%get_smpd(), o%get('kv'), o%get('cs'), o%get('fraca'))
                ! set CTF and shift parameters
                select case(p%tfplan%mode)
                    case('astig') ! astigmatic CTF
                        dfx    = o%get('dfx')
                        dfy    = o%get('dfy')
                        angast = o%get('angast')
                    case('noastig') ! non-astigmatic CTF
                        dfx    = o%get('dfx')
                        dfy    = dfx
                        angast = 0.
                end select
                x  = -o%get('x')
                y  = -o%get('y')
                pw = o%get('w')
                ! apply
                call img%fwd_ft
                ! take care of the nominator
                select case(p%tfplan%flag)
                    case('yes')  ! multiply with CTF
                        call tfun%apply_and_shift(img, ctfsq, x, y, dfx, 'ctf', dfy, angast)
                    case('flip') ! multiply with abs(CTF)
                        call tfun%apply_and_shift(img, ctfsq, x, y, dfx, 'abs', dfy, angast)
                    case('mul','no')
                        call tfun%apply_and_shift(img, ctfsq, x, y, dfx, '', dfy, angast)
                end select
                ! add to sum
                call  b%ctfsqsums(icls)%add(ctfsq, pw)
            end subroutine apply_ctf_and_shift

    end subroutine prime2D_assemble_sums

    subroutine prime2D_assemble_sums_from_parts( b, p )
        class(build),  intent(inout) :: b
        class(params), intent(inout) :: p
        character(len=STDLEN) :: fname_cavgs, fname_ctfsqsums
        integer :: ipart, icls
        call prime2D_init_sums( b, p )
        do ipart=1,p%nparts
            fname_cavgs     = 'cavgs_part'//int2str_pad(ipart,p%numlen)//p%ext
            fname_ctfsqsums = 'ctfsqsums_part'//int2str_pad(ipart,p%numlen)//p%ext
            ! read & sum partial class averages
            if( file_exists(fname_cavgs) )then
                do icls=1,p%ncls
                    call b%img%read(fname_cavgs, icls)
                    ! add subaverage to class
                    call b%cavgs(icls)%add(b%img)
                end do
            else
                write(*,*) 'File does not exists: ', trim(fname_cavgs)
                stop 'In: simple_hadamard2D_matcher :: prime2D_assemble'
            endif
            ! read & sum partial ctfsqsums
            if( file_exists(fname_ctfsqsums) )then
                do icls=1,p%ncls
                    call b%img%read(fname_ctfsqsums, icls)
                    ! add subaverage to class
                    call b%ctfsqsums(icls)%add(b%img)
                end do
            else
                write(*,*) 'File does not exists: ', trim(fname_ctfsqsums)
                stop 'In: simple_hadamard2D_matcher :: prime2D_assemble'
            endif
        end do
        call prime2D_norm_sums( b, p )
    end subroutine prime2D_assemble_sums_from_parts

    subroutine prime2D_write_partial_sums( b, p )
        class(build),  intent(inout) :: b
        class(params), intent(inout) :: p
        integer :: icls
        do icls=1,p%ncls
            call b%cavgs(icls)%write('cavgs_part'//int2str_pad(p%part,p%numlen)//p%ext, icls)
            call b%ctfsqsums(icls)%write('ctfsqsums_part'//int2str_pad(p%part,p%numlen)//p%ext, icls)
        end do
    end subroutine prime2D_write_partial_sums

    subroutine prime2D_norm_sums( b, p )
        class(build),  intent(inout) :: b
        class(params), intent(inout) :: p
        integer :: icls, pop
        do icls=1,p%ncls
            pop = b%a%get_pop(icls, 'class')
            if( pop > 1 )then
                call b%cavgs(icls)%fwd_ft
                call b%cavgs(icls)%ctf_dens_correct(b%ctfsqsums(icls))
                call b%cavgs(icls)%bwd_ft
            endif
        end do
    end subroutine prime2D_norm_sums

    subroutine prime2D_write_sums( b, p, which_iter, fname )
        class(build),               intent(inout) :: b
        class(params),              intent(inout) :: p
        integer,          optional, intent(in)    :: which_iter
        character(len=*), optional, intent(in)    :: fname
        integer :: icls
        if( present(which_iter) )then
            if( present(fname) ) stop &
            &'fname cannot be present together with which_iter; simple_hadamard2D_matcher :: prime2D_write_sums'
            p%refs = 'cavgs_iter'//int2str_pad(which_iter,3)//p%ext
        else
            if( present(fname) )then
                p%refs = fname
            else
                p%refs = 'startcavgs'//p%ext
            endif
        endif
        if( p%chunktag .ne. '' ) p%refs = trim(p%chunktag)//trim(p%refs)
        ! write to disk
        do icls=1,p%ncls
            call b%cavgs(icls)%write(p%refs, icls)
        end do
    end subroutine prime2D_write_sums

    !>  \brief  prepares the polarft corrcalc object for search
    subroutine preppftcc4align( b, p )
        use simple_syslib,       only: alloc_errchk
        class(build),  intent(inout) :: b
        class(params), intent(inout) :: p
        type(ori) :: o
        integer   :: cnt, iptcl, icls, pop, istate
        integer   :: filtsz, alloc_stat, filnum, io_stat
        if( .not. p%l_distr_exec ) write(*,'(A)') '>>> BUILDING PRIME2D SEARCH ENGINE'
        ! must be done here since constants in p are dynamically set
        call pftcc%new(p%ncls, [p%fromp,p%top], [p%boxmatch,p%boxmatch,1], p%smpd, p%kfromto, p%ring2, p%ctf)
        ! prepare the polarizers
        call b%img_match%init_polarizer(pftcc)
        ! prepare the automasker
        if( p%l_envmsk .and. p%automsk .eq. 'cavg' ) call b%mskimg%init2D(p, p%ncls)
        ! PREPARATION OF REFERENCES IN PFTCC
        ! read references and transform into polar coordinates
        if( .not. p%l_distr_exec ) write(*,'(A)') '>>> BUILDING REFERENCES'
        do icls=1,p%ncls
            call progress(icls, p%ncls)
            pop = 1
            if( p%oritab /= '' ) pop = b%a%get_pop(icls, 'class')
            if( pop > 0 )then
                ! prepare the reference
                b%img = b%cavgs(icls)
                if( p%oritab /= '' )then
                    call prep2Dref(b, p, icls, center=(pop > MINCLSPOPLIM))
                else
                    call prep2Dref(b, p, icls)
                endif
                ! transfer to polar coordinates
                call b%img_match%polarize(pftcc, icls, isptcl=.false.)
            endif
        end do
        ! PREPARATION OF PARTICLES IN PFTCC
        ! read particle images and create polar projections
        if( .not. p%l_distr_exec ) write(*,'(A)') '>>> BUILDING PARTICLES'
        cnt = 0
        do iptcl=p%fromp,p%top
            cnt = cnt+1
            call progress(cnt, p%top-p%fromp+1)
            call read_img_from_stk( b, p, iptcl )
            o = b%a%get_ori(iptcl)
            call prepimg4align(b, p, o)
            ! transfer to polar coordinates
            call b%img_match%polarize(pftcc, iptcl)
        end do
        DebugPrint '*** hadamard2D_matcher ***: finished preppftcc4align'
    end subroutine preppftcc4align

end module simple_hadamard2D_matcher

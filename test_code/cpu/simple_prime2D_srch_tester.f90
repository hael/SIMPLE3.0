module simple_prime2D_srch_tester
use simple_hadamard2D_matcher ! singleton
use simple_defs               ! singleton
use simple_jiffys             ! singleton
use simple_stat,              only: pearsn
use simple_math,              only: euclid
use simple_cmdline,           only: cmdline
use simple_params,            only: params
use simple_build,             only: build
use simple_image,             only: image
use simple_oris,              only: oris
implicit none

public :: exec_prime2D_srch_test
private

! module global constants
integer,           parameter :: NPROJS      = 10
character(len=32), parameter :: refsname    = 'prime2D_srch_test_refs.mrc'
character(len=32), parameter :: ptclsname   = 'prime2D_srch_test_ptcls.mrc'
character(len=32), parameter :: orisname    = 'prime2D_srch_test_oris.txt'
character(len=32), parameter :: outfilename = 'prime2D_srch_test_algndoc.txt'
real,              parameter :: LPLIM       = 10.

! module global variables
type(build)              :: b
type(params)             :: p
type(oris)               :: o_refs, o_ptcls
type(image), allocatable :: imgs_refs(:), imgs_ptcls(:)
type(cmdline)            :: cline_here
logical                  :: verbose=.true.

contains

    subroutine exec_prime2D_srch_test( cline, be_verbose )
        class(cmdline),    intent(inout) :: cline
        logical, optional, intent(in)    :: be_verbose
        call setup_testenv( cline, be_verbose )
        write(*,*) '****prime2D_srch_test, init'
        call test_calc_corrs2D
        call test_prepcorrs4gpusrch
        !call test_greedy_srch
        call shutdown_testenv
        write(*,*) '****prime2D_srch_test, completed'
    end subroutine exec_prime2D_srch_test

    subroutine setup_testenv( cline, be_verbose )
        class(cmdline),    intent(inout) :: cline
        logical, optional, intent(in)    :: be_verbose
        integer :: iproj
        verbose = .false.
        if( present(be_verbose) ) verbose = be_verbose
        ! it is assumed that vol1, smpd, msk are part of the inputted command line
        ! setting the remainder of the command line up in here
        cline_here = cline
        call cline_here%set('ncls',    real(NPROJS))
        call cline_here%set('nptcls',  real(NPROJS))
        call cline_here%set('lp',      LPLIM       )
        call cline_here%set('ctf',     'no'        )
        call cline_here%set('outfile', outfilename )
        ! generate orientations
        call o_refs%new(NPROJS)
        call o_refs%spiral
        o_ptcls = o_refs
        call o_ptcls%rnd_inpls
        ! create parameters and build
        p = params(cline_here)                   ! parameters generated
        p%boxmatch = p%box                       !!!!!!!!!!!!!!!!!! 4 NOW
        call b%build_general_tbox(p, cline_here) ! general objects built
        ! set resolution range
        p%kfromto(1) = 2
        p%kfromto(2) = b%img%get_find(p%lp)
        ! generate images
        call b%vol%read(p%vols(1))
        imgs_refs  = b%proj%projvol(b%vol, o_refs,  p)
        imgs_ptcls = b%proj%projvol(b%vol, o_ptcls, p)
        do iproj=1,NPROJS
            call imgs_refs(iproj)%write(refsname, iproj)
            call imgs_ptcls(iproj)%write(ptclsname, iproj)
        end do
        call cline_here%set('stk',  ptclsname)
        call cline_here%set('refs', refsname)
        ! re-create parameters and build
        p = params(cline_here)                   ! parameters generated
        p%boxmatch = p%box                       !!!!!!!!!!!!!!!!!! 4 NOW
        call b%build_general_tbox(p, cline_here) ! general objects built
        call b%build_hadamard_prime2D_tbox(p)    ! 2D Hadamard matcher built
        ! prepare pftcc object
        call prime2D_read_sums( b, p )
        call preppftcc4align( b, p )
        ! The pftcc & primesrch2D objects are now globally available in the module
        ! because of the use simple_hadamard2D_matcher statement in the top
    end subroutine setup_testenv

    subroutine test_calc_corrs2D
        use simple_corrmat, only: project_corrmat3D_greedy
        real    :: corrmat2d_ref(NPROJS,NPROJS)
        real    :: corrmat2d_tst(NPROJS,NPROJS)
        real    :: corrmat3d(NPROJS,NPROJS,pftcc%get_nrots())
        integer :: inplmat_ref(NPROJS,NPROJS)
        integer :: inplmat_tst(NPROJS,NPROJS)
        integer :: iptcl, iref, loc(1)
        real    :: corrs(pftcc%get_nrots())

        ! generate the reference marices
        do iptcl=1,NPROJS
            do iref=1,NPROJS
                corrs = pftcc%gencorrs(iref, iptcl)
                loc   = maxloc(corrs)
                corrmat2d_ref(iptcl,iref) = corrs(loc(1))
                inplmat_ref(iptcl,iref)   = loc(1)
            end do
        end do

        if( verbose ) write(*,*) 'testing polarft_corrcalc :: gencorrs_all_tester_1'
        call pftcc%gencorrs_all_tester(corrmat2d_tst, inplmat_tst)
        if( .not. test_passed() ) stop '****prime2D_srch_tester FAILURE polarft_corrcalc :: gencorrs_all_tester_1'

        verbose = .true.
        if( verbose ) write(*,*) 'testing polarft_corrcalc :: gencorrs_all_cpu'
        call pftcc%expand_dim
        call pftcc%gencorrs_all_cpu(corrmat3d)
        call project_corrmat3D_greedy(NPROJS, pftcc%get_nrots(), corrmat3d, corrmat2d_tst, inplmat_tst)
        if( .not. test_passed() ) stop '****prime2D_srch_tester FAILURE polarft_corrcalc :: gencorrs_all_cpu'

        if( verbose ) write(*,*) 'testing polarft_corrcalc :: gencorrs_all_cpu, 2nd round'
        call pftcc%expand_dim
        call pftcc%gencorrs_all_cpu(corrmat3d)
        call project_corrmat3D_greedy(NPROJS, pftcc%get_nrots(), corrmat3d, corrmat2d_tst, inplmat_tst)
        if( .not. test_passed() ) stop '****prime2D_srch_tester FAILURE polarft_corrcalc :: gencorrs_all_cpu routine, 2nd round'

        if( verbose ) write(*,*) 'testing primesrch2D :: calc_corrs, mode=bench'
        call primesrch2D%calc_corrs(pftcc, mode='bench')
        do iptcl=1,NPROJS
            do iref=1,NPROJS
                corrmat2d_tst(iptcl,iref) = primesrch2D%get_corr(iptcl,iref)
                inplmat_tst(iptcl,iref)   = primesrch2D%get_inpl(iptcl,iref)
            end do
        end do
        if( .not. test_passed() ) stop '****prime2D_srch_tester FAILURE primesrch2D :: calc_corrs, mode=bench'

        if( verbose ) write(*,*) 'testing primesrch2D :: calc_corrs, mode=cpu'
        call primesrch2D%calc_corrs(pftcc, mode='cpu')
        do iptcl=1,NPROJS
            do iref=1,NPROJS
                corrmat2d_tst(iptcl,iref) = primesrch2D%get_corr(iptcl,iref)
                inplmat_tst(iptcl,iref)   = primesrch2D%get_inpl(iptcl,iref)
            end do
        end do
        if( .not. test_passed() ) stop '****prime2D_srch_tester FAILURE primesrch2D :: calc_corrs, mode=cpu'

    contains

        function test_passed() result( passed )
            logical :: passed
            real    :: ce_corr(2), ce_inpl(2)
            passed = .false.
            ce_corr = compare_corrmats(corrmat2d_ref, corrmat2d_tst)
            ce_inpl = compare_inplmats(inplmat_ref, inplmat_tst)
            !if( verbose ) write(*,*) 'corr, corr/euclid: ', ce_corr(1), ce_corr(2)
            !if( verbose ) write(*,*) 'inpl, corr/euclid: ', ce_inpl(1), ce_inpl(2)
            write(*,*) 'corr, corr/euclid: ', ce_corr(1), ce_corr(2)
            write(*,*) 'inpl, corr/euclid: ', ce_inpl(1), ce_inpl(2)
            if(       ce_corr(1) > 0.999999 .and. ce_corr(2) < 0.00001&
                .and. ce_inpl(1) > 0.999999 .and. ce_inpl(2) < 0.00001 )&
            passed = .true.
        end function test_passed

        function compare_corrmats( cmat1, cmat2 ) result( ce )
            real, intent(in) :: cmat1(NPROJS,NPROJS), cmat2(NPROJS,NPROJS)
            real :: ce(2)
            ce(1) = pearsn(reshape(cmat1,shape=[NPROJS**2]),reshape(cmat2,shape=[NPROJS**2]))
            ce(2) = euclid(reshape(cmat1,shape=[NPROJS**2]),reshape(cmat2,shape=[NPROJS**2]))
        end function compare_corrmats

        function compare_inplmats( inplmat1, inplmat2 ) result( ce )
            integer, intent(in) :: inplmat1(NPROJS,NPROJS), inplmat2(NPROJS,NPROJS)
            real :: ce(2)
            ce(1) = pearsn(reshape(real(inplmat1),shape=[NPROJS**2]),reshape(real(inplmat2),shape=[NPROJS**2]))
            ce(2) = euclid(reshape(real(inplmat1),shape=[NPROJS**2]),reshape(real(inplmat2),shape=[NPROJS**2]))
        end function compare_inplmats

    end subroutine test_calc_corrs2D

    subroutine test_prepcorrs4gpusrch
        real, allocatable :: prev_corrs(:)
        integer :: icorr, icls
        real    :: ref_corrs(NPROJS)
        logical :: passed=.false.
        if( verbose ) write(*,*) 'testing primesrch2D :: prepcorrs4gpusrc'
        do icls=1,NPROJS
            call o_ptcls%set(icls, 'class', real(icls))
            ref_corrs(icls) = pftcc%corr(icls, icls, primesrch2D%get_roind(360.-o_ptcls%e3get(icls)))
        end do
        call primesrch2D%prepcorrs4gpusrch(pftcc, o_ptcls, [1,NPROJS])
        prev_corrs = primesrch2D%get_prev_corrs()
        if( .not. test_passed() ) stop '****prime2D_srch_tester TEST FAILURE primesrch2D :: test_prepcorrs4gpusrch'

    contains

         function test_passed() result( passed )
            logical :: passed
            real    :: ce(2)
            passed = .false.
            ce(1) = pearsn(ref_corrs,prev_corrs)
            ce(2) = euclid(ref_corrs,prev_corrs)
            if( verbose ) write(*,*) 'corr, corr/euclid: ', ce(1), ce(2)
            if( ce(1) > 0.999999 .and. ce(2) < 0.000001 ) passed = .true.
        end function test_passed

    end subroutine test_prepcorrs4gpusrch

    subroutine test_greedy_srch
        use simple_ori, only: ori
        integer    :: iptcl
        type(ori)  :: one_ori
        logical    :: assignments_correct(NPROJS)
        if( verbose ) write(*,*) 'testing primesrch2D :: greedy_srch in CPU mode'
        do iptcl=1,NPROJS
            call primesrch2D%prep4srch(pftcc, iptcl, LPLIM)
            call primesrch2D%greedy_srch(pftcc, iptcl)
            call primesrch2D%get_cls(one_ori)
            assignments_correct(iptcl) = nint(one_ori%get('class')) == iptcl
            print *,iptcl, nint(one_ori%get('class')) 
        end do
        if( all(assignments_correct) )then
            ! the test passed
        else
            print *, 'only ', count(assignments_correct), ' assignments correct'
            stop '****prime2D_srch_tester TEST FAILURE primesrch2D :: test_greedy_srch, CPU mode'
        endif
        if( verbose ) write(*,*) 'testing primesrch2D :: greedy_srch in GPU mode'
        call primesrch2D%set_use_cpu(.false.)
        call primesrch2D%calc_corrs(pftcc, mode='cpu')
        do iptcl=1,NPROJS
            call primesrch2D%greedy_srch(pftcc, iptcl, iptcl)
            call primesrch2D%get_cls(one_ori)
            assignments_correct(iptcl) = nint(one_ori%get('class')) == iptcl
        end do
        call primesrch2D%set_use_cpu(.true.)
        if( all(assignments_correct) )then
            ! the test passed
        else
            stop '****prime2D_srch_tester TEST FAILURE primesrch2D :: test_greedy_srch, GPU mode'
        endif
    end subroutine test_greedy_srch

    subroutine shutdown_testenv
        integer :: iproj
        call b%kill_general_tbox
        call b%kill_hadamard_prime2D_tbox
        call pftcc%kill
        call primesrch2D%kill
        do iproj=1,NPROJS
            call imgs_refs(iproj)%kill
            call imgs_ptcls(iproj)%kill
        end do
        deallocate(imgs_refs, imgs_ptcls)
    end subroutine shutdown_testenv

end module simple_prime2D_srch_tester
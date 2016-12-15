program simple_test_units
use simple_defs              ! singleton
use simple_cuda_defs         ! cuda definitions
use simple_cuda              ! cuda environment and shutdown
use simple_testfuns          ! singleton
use simple_rnd               ! singleton
use simple_ctf,              only: test_ctf
use simple_cmd_dict,         only: test_cmd_dict
use simple_build,            only: test_build
use simple_ftiter,           only: test_ftiter
use simple_ori,              only: test_ori, test_ori_dists
use simple_oris,             only: test_oris
use simple_image,            only: test_image
use simple_hac,              only: test_hac
use simple_kmeans,           only: test_kmeans
use simple_shc_cluster,      only: test_shc_cluster
use simple_aff_prop,         only: test_aff_prop
use simple_args,             only: test_args
use simple_online_var,       only: test_online_var
use simple_hash,             only: test_hash
use simple_imghead,          only: test_imghead
use simple_polarft,          only: test_polarft
use simple_polarft_corrcalc, only: test_polarft_corrcalc
use simple_jiffys,           only: simple_end
use simple_ft_shsrch,        only: test_ft_shsrch
use simple_ftexp_shsrch,     only: test_ftexp_shsrch
use simple_unblur,           only: test_unblur
use simple_timing
implicit none
character(8)          :: date
character(len=STDLEN) :: folder
character(len=300)    :: command
integer               :: err=0
call timestamp()
! COMMENTED OUT BECAUSE WHEN COMPILING WITH DEBUG .EQ. YES =>
! At line 61 of file simple_utils/common/simple_sorting.f90
! Fortran runtime error: Index '0' of dimension 1 of array 'shell_sorted' below lower bound of 1
! call start_Alltimers_cpu()
call seed_rnd
call date_and_time(date=date)
call simple_cuda_init(err)
if (err .ne. 0 ) write(*,*) 'cublas init failed'
folder = './SIMPLE_UNIT_TEST'//date
command = 'mkdir '//folder
call system(command)
call chdir(folder)
call test_cmd_dict
call test_build
call test_polarft_corrcalc
call test_ftiter
call test_ori
call test_ori_dists
call test_oris(.false.)  ! logical for printing or not
call test_imghead
call test_image(.false.) ! logical for plotting or not
call test_hac
call test_kmeans
call test_shc_cluster
call test_aff_prop
call test_args
call test_online_var
call test_hash
call test_ft_shsrch
call test_ftexp_shsrch
call test_unblur
! LOCAL TESTFUNCTIONS
call test_multinomal
call test_testfuns
call test_euler_shift
call simple_test_fit_line
call chdir('../')
call stop_Alltimers_cpu()
! shutting down the environment
call simple_cuda_shutdown()
call simple_end('**** SIMPLE_UNIT_TEST NORMAL STOP ****')

contains

    subroutine test_multinomal
        integer :: i, irnd
        real :: pvec(10), prob
        call seed_rnd
        pvec(1) = 0.8
        do i=2,10
            pvec(i) = 0.2/9.
        end do
        write(*,*) 'this should be one:', sum(pvec)
        prob=0.
        do i=1,1000
            if( multinomal(pvec) == 1 ) prob = prob+1.
        end do
        prob = prob/1000.
        write(*,*) 'this should be 0.8:', prob
        pvec = 0.1
        write(*,*) 'this should be one:', sum(pvec)
        prob=0.
        do i=1,1000
            irnd = multinomal(pvec)
            if( irnd == 1 ) prob = prob+1.
        end do
        prob = prob/1000.
        write(*,*) 'this should be 0.1:', prob
        write(*,'(a)') 'SIMPLE_RND: MULTINOMAL TEST COMPLETED WITHOUT TERMINAL BUGS ;-)'
    end subroutine
    
    subroutine test_testfuns
        procedure(testfun), pointer :: ptr
        integer :: i
        real    :: gmin, range(2)
        logical :: success
        success = .false.
        do i=1,20
            ptr = get_testfun(i, 2, gmin, range)
            select case(i)
                case(1)
                    if( abs(ptr([0.,0.],2)-gmin) < 1e-5 ) success = .true.
                case(2)
                    if( abs(ptr([1.,1.],2)-gmin) < 1e-5 ) success = .true.
                case(3)
                    if( abs(ptr([-2.903534,-2.903534],2)-gmin) < 1e-5 ) success = .true.
                case(4)
                    if( abs(ptr([0.,0.],2)-gmin) < 1e-5 ) success = .true.
                case(5)
                    if( abs(ptr([0.,0.],2)-gmin) < 1e-5 ) success = .true.
                case(6)
                    if( abs(ptr([0.,0.],2)-gmin) < 1e-5 ) success = .true.
                case(7)
                    if( abs(ptr([420.9687,420.9687],2)-gmin) < 1e-5 ) success = .true.
                case(8)
                    if( abs(ptr([0.,0.],2)-gmin) < 1e-5 ) success = .true.
                case(9)
                    if( abs(ptr([1.,1.],2)-gmin) < 1e-5 ) success = .true.
                case(10)
                    if( abs(ptr([3.,0.5],2)-gmin) < 1e-5 ) success = .true.
                case(11)
                    if( abs(ptr([0.,-1.],2)-gmin) < 1e-5 ) success = .true.
                case(12)
                    if( abs(ptr([1.,3.],2)-gmin) < 1e-5 ) success = .true.
                case(13)
                    if( abs(ptr([0.,0.],2)-gmin) < 1e-5 ) success = .true.
                case(14)
                    if( abs(ptr([0.,0.],2)-gmin) < 1e-5 ) success = .true.
                case(15)
                    if( abs(ptr([1.,1.],2)-gmin) < 1e-5 ) success = .true.
                case(16)
                    if( abs(ptr([0.,0.],2)-gmin) < 1e-5 ) success = .true.
                case(17)
                    if( abs(ptr([pi,pi],2)-gmin) < 1e-5 ) success = .true.
                case(18)
                    if( abs(ptr([512.,404.2319],2)-gmin) < 1e-5 ) success = .true.
                case(19)
                    if( abs(ptr([0.,0.],2)-gmin) < 1e-5 ) success = .true.
                case(20)
                    if( abs(ptr([0.,1.25313],2)-gmin) < 1e-5 ) success = .true.
                case DEFAULT
                    stop 'Unknown function index; test_testfuns; simple_unit_test'
            end select
            if( success )then
                cycle
            else
                write(*,*) 'testing of testfun:', i, 'failed!'
                write(*,*) 'minimum:', gmin
            endif
        end do
        write(*,'(a)') 'SIMPLE_TESTFUNS: TEST OF TEST FUNCTIONS COMPLETED ;-)'
    end subroutine
    
    subroutine test_euler_shift
        use simple_ori, only: ori
        use simple_rnd, only: ran3
        type(ori) :: o
        integer   :: i
        real      :: euls(3), euls_shifted(3)
        logical   :: doshift
        call o%new
        do i=1,100000
            euls(1) = ran3()*800.-400.
            euls(2) = ran3()*500-250.
            euls(3) = ran3()*800.-400.
            call o%set_euler(euls)
            euls_shifted = o%get_euler()
            doshift = .false.
            if( euls_shifted(1) < 0. .or. euls_shifted(1) > 360. ) doshift = .true.
            if( euls_shifted(2) < 0. .or. euls_shifted(2) > 180. ) doshift = .true.
            if( euls_shifted(3) < 0. .or. euls_shifted(3) > 360. ) doshift = .true.
            if( doshift ) stop 'euler shifting does not work!'
        end do
    end subroutine
    
    subroutine simple_test_fit_line
        use simple_math
        use simple_rnd
        real    :: slope, intercept, datavec(100,2), corr, x
        integer :: i, j
        do i=1,10000
            ! generate the line
            slope = 5.*ran3()
            if( ran3() < 0.5 ) slope = -slope
            intercept = 10.*ran(3)
            if( ran3() < 0.5 ) intercept = -intercept
!            write(*,*) '***********************************'
!            write(*,*) 'Slope/Intercept:', slope, intercept
            ! generate the data
            x = -1.
            do j=1,100
                datavec(j,1) = x
                datavec(j,2) = slope*datavec(j,1)+intercept
                x = x+0.02
            end do
            ! fit the data
            call fit_straight_line(100, datavec, slope, intercept, corr)
!            write(*,*) 'Fitted Slope/Intercept:', slope, intercept
!            write(*,*) 'Corr:', corr
            if( corr < 0.9999 )then
                stop 'fit_straight_line; simple_math, failed!'        
            endif
        end do
        write(*,'(a)') 'FIT_STRAIGHT_LINE UNIT TEST COMPLETED ;-)'
    end subroutine

end program simple_test_units

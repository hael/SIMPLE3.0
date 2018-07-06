!------------------------------------------------------------------------------!
! SIMPLE               Elmlund & Elmlund Lab         simplecryoem.com          !
!------------------------------------------------------------------------------!
!> Test program for simple CUDA
!
! @author
!
!
! DESCRIPTION:
!> CUDA implementation -- for PGI

!
! REVISION HISTORY:
! 06 Oct 2017 - Initial Version -- PGI
! 07 May 2018 - FortCUDA implementaiton
!------------------------------------------------------------------------------
program simple_test_cuda
    include 'simple_lib.f08'
    use simple_image,            only: image
    use gnufor2
    use CUDA
    use simple_cuda
    use simple_timer_cuda
    use simple_cuda_kernels
    use, intrinsic :: ISO_C_BINDING
    implicit none

    type (timer_cuda) :: ctimer
    type (cudaEvent_t)  :: ev1,ev2
    integer(timer_int_kind) :: t1
    integer(c_int):: runtimeVersion,driverVersion,pValue, deviceCount,free,total
    integer (KIND(cudaLimitStackSize))::limitStackSize= cudaLimitStackSize
    integer (KIND(cudaSuccess)) :: err
    logical :: error_found
    error_found=.false.

    print *," CUDA Runtime functions "
    call cuda_query_version
    call cuda_query_driver_version
    call cuda_query_device_count
    call cuda_query_thread_limit
    call cuda_thread_synchronize
    call cuda_print_mem_info


    call check_cuda_device
    !  call set_cuda_device(0)
    call test_cuda_precision( error_found)

    write (*,'(A)') 'SIMPLE_CUDA timer setup'
    ctimer = timer_cuda()

    write (*,'(A)') 'TESTING CUDAFOR TIMING'
    ! call ctimer%nowCU()
    t1=tic()
    ev1=ctimer%ticU()
    ev2=ctimer%ticU()
    write (*,'(A)') 'SIMPLE_CUDA timer CPU/CUDA'
    print *, " Simple_timer ", toc(t1)
    print *, " CUDA Event timer 1", ctimer%tocU(ev1)
    print *, " CUDA Event timer 2",ctimer%tocU(ev2)
    call ctimer%kill_()


    !  call test_FortCUDA_kernels(0.)
    call test_fortran_mul1dComplex_kernels
    call test_fortran_squaremul2dComplex_kernels
    call test_fortran_mul2dComplex_kernels

    ! #if defined(PGI)
    !     use simple_cuda_tests
    !     use simple_timer_cuda
    !     use cudafor
    !     implicit none
    !     type (cudaDeviceProp) :: prop
    !     type (timer_cuda) :: ctimer
    !     type (cudaEvent_t)  :: ev1,ev2
    !     integer :: i, ierr,istat, cuVer, cuMem, cuFree,n
    !     real, allocatable :: x(:),y(:),y1(:)
    !     logical :: errflag
    !     integer(timer_int_kind) :: t1
    !     write (*,'(A)') 'SIMPLE CUDA TEST'
    !     errflag=.true.
    !     n=10
    !     allocate(x(n),y(n),y1(n))


    !     write (*,'(A)') 'TESTING CUDAFOR INTERFACE'
    !     call cuda_query_version
    !     call cuda_query_devices
    !     call cuda_query_peak_bandwidth

    !     write (*,'(A)') 'TESTING CUDA multi-GPU capability'
    !     call cuda_query_p2pAccess(errflag)
    !     call test_minimal_P2P(errflag)
    !     call test_transposeP2P

    !     errflag=.true.
    !     call test_cuda_precision(errflag)
    !     call test_acc(errflag)





    ! #if 0
    !     write (*,'(A)') 'TESTING CUDAFOR TIMING'
    !     call ctimer%nowCU()
    !     write (*,'(A)') 'SIMPLE_CUDA timer setup'

    !     t1=tic()
    !     ev1=ctimer%ticU()
    !     ev2=ctimer%ticU()
    !     write (*,'(A)') 'SIMPLE_CUDA timer CPU/CUDA', toc(t1), ctimer%tocU(ev1), ctimer%tocU(ev2)
    !     call simple_cuda_stop("In simple_image::fft post fft sync ",__FILENAME__,__LINE__)
    ! #endif
    ! #endif


contains

    subroutine test_cuda_precision(flag)
        implicit none
        logical, intent(inout):: flag
        write(*,"(a)") '  CUDA Query: Test precision'
        call test_precision(flag)
        write(*,"(a)") '  CUDA Query: Sum accuracy'
        call sum_accuracy(flag)
    end subroutine test_cuda_precision

        !> Floating-point precision test
        subroutine test_precision(flag)
            logical, intent(inout):: flag

            real :: x, y, dist
            double precision:: x_dp, y_dp, dist_dp
            x=Z'3F1DC57A'
            y=Z'3F499AA3'
            dist= x**2 +y**2

            x_dp=real(x,8)
            y_dp=real(y,8)
            dist_dp= x_dp**2 +y_dp**2

            print *, 'Result with operands in single precision:'
            print '((2x,z8)) ', dist

            print *, 'Result in double precision with operands'
            print *, 'promoted to double precision:'
            print '((2x,z16))', dist_dp

            print *, 'Result in single precision with operands'
            print *, 'promoted to double precision:'
            print '((2x,z8))', real(dist_dp,4)
        end subroutine test_precision

        !>  Floating-point precision test
        subroutine sum_accuracy(flag)
            logical, intent(inout):: flag

            real, allocatable :: x(:)
            real :: sum_intrinsic,sum_cpu, sum_kahan, sum_pairwise, &
                comp, y, tmp
            double precision :: sum_cpu_dp
            integer :: i,inext,icurrent,  N=10000000

            allocate (x(N))
            x=7.

            ! Summation using intrinsic
            sum_intrinsic=sum(x)

            ! Recursive summation
            sum_cpu=0.
            sum_cpu_dp=0.d0
            do i=1,N
                ! accumulator in single precision
                sum_cpu=sum_cpu+x(i)
                ! accumulator in double precision
                sum_cpu_dp=sum_cpu_dp+x(i)
            end do

            ! Kahan summation
            sum_kahan=0.
            comp=0. ! running compensation to recover lost low-order bits

            do i=1,N
                y    = comp +x(i)
                tmp  = sum_kahan + y     ! low-order bits may be lost
                comp = (sum_kahan-tmp)+y ! (sum-tmp) recover low-order bits
                sum_kahan = tmp
            end do
            sum_kahan=sum_kahan +comp

            ! Pairwise summation
            icurrent=N
            inext=ceiling(real(N)/2)
            do while (inext >1)
                do i=1,inext
                    if ( 2*i <= icurrent) x(i)=x(i)+x(i+inext)
                end do
                icurrent=inext
                inext=ceiling(real(inext)/2)
            end do
            sum_pairwise=x(1)+x(2)

            write(*, "('Summming ',i10,' elements of magnitude ',f3.1)") N,7.
            write(*, "('Sum with intrinsic function       =',f12.1,'   Error=', f12.1)")  &
                sum_intrinsic, 7.*N-sum_intrinsic
            write(*, "('Recursive sum with SP accumulator =',f12.1,'   Error=', f12.1)")  sum_cpu, 7.*N-sum_cpu
            write(*, "('Recursive sum with DP accumulator =',f12.1,'   Error=', f12.1)")  sum_cpu_dp, 7.*N-sum_cpu_dp
            write(*, "('Pairwise sum in SP                =',f12.1,'   Error=', f12.1)")  sum_pairwise, 7.*N-sum_pairwise
            write(*, "('Compensated sum in SP             =',f12.1,'   Error=', f12.1)")  sum_kahan, 7.*N-sum_kahan

            deallocate(x)
        end subroutine sum_accuracy




    ! subroutine test_Jacobi_relaxation(flag)
    !     logical, intent(inout):: flag
    !     integer, parameter :: fp_kind=kind(1.0)
    !     integer, parameter :: n=4096, m=4096, iter_max=1000
    !     integer :: i, j, iter
    !     real(fp_kind), dimension (:,:), allocatable :: A, Anew
    !     real(fp_kind), dimension (:),   allocatable :: y0
    !     real(fp_kind) :: pi=2.0_fp_kind*asin(1.0_fp_kind), tol=1.0e-5_fp_kind, error=1.0_fp_kind
    !     integer(timer_int_kind) :: start_time, stop_time

    !     allocate ( A(0:n-1,0:m-1), Anew(0:n-1,0:m-1) )
    !     allocate ( y0(0:m-1) )
    !     write(*,"(a)") '  Testing CUDA - jacobi relaxation example'
    !     A = 0.0_fp_kind

    !     ! Set B.C.
    !     y0 = sin(pi* (/ (j,j=0,m-1) /) /(m-1))

    !     A(0,:)   = 0.0_fp_kind
    !     A(n-1,:) = 0.0_fp_kind
    !     A(:,0)   = y0
    !     A(:,m-1) = y0*exp(-pi)

    !     write(*,'(a,i5,a,i5,a)') 'Jacobi relaxation Calculation:', n, ' x', m, ' mesh'

    !     start_time = tic()

    !     iter=0
    !     do i=1,m-1
    !         Anew(0,i)   = 0.0_fp_kind
    !         Anew(n-1,i) = 0.0_fp_kind
    !     end do

    !     do i=1,n-1
    !         Anew(i,0)   = y0(i)
    !         Anew(i,m-1) = y0(i)*exp(-pi)
    !     end do


    !     do while ( error .gt. tol .and. iter .lt. iter_max )
    !         error=0.0_fp_kind
    !         do j=1,m-2

    !             do i=1,n-2
    !                 Anew(i,j) = 0.25_fp_kind * ( A(i+1,j  ) + A(i-1,j  ) + &
    !                     A(i  ,j-1) + A(i  ,j+1) )
    !                 error = max( error, abs(Anew(i,j)-A(i,j)) )
    !             end do

    !         end do

    !         if(mod(iter,100).eq.0 ) write(*,'(i5,f10.6)'), iter, error
    !         iter = iter +1



    !         do j=1,m-2

    !             do i=1,n-2
    !                 A(i,j) = Anew(i,j)
    !             end do

    !         end do

    !     end do
    !     stop_time=tic()
    !     write(*,'(a,f10.3,a)')  ' completed in ', stop_time-start_time, ' seconds'
    !     write(*,"(a)") '  Testing CUDA - jacobi relaxation example completed'
    !     deallocate (A,Anew,y0)

    ! end subroutine test_Jacobi_relaxation


    ! subroutine test_transposeP2P


    !     ! global array size
    !     integer, parameter :: nx = 1024, ny = 768

    !     ! toggle async
    !     logical, parameter :: asyncVersion = .true.

    !     ! host arrays (global)
    !     real :: h_idata(nx,ny), h_tdata(ny,nx), gold(ny,nx)
    !     real (kind=8) :: timeStart, timeStop

    !     ! CUDA vars and device arrays
    !     type (dim3) :: dimGrid, dimBlock
    !     type (cudaStream_t), allocatable :: &
    !         streamID(:,:)  ! (device, stage)

    !     ! distributed arrays
    !     type deviceArray
    !         type(cudaArray_t), allocatable :: v(:,:)
    !     end type deviceArray

    !     type (deviceArray), allocatable :: &
    !         d_idata(:), d_tdata(:), d_rdata(:)  ! (0:nDevices-1)

    !     integer :: nDevices
    !     type (cudaDeviceProp) :: propCuda
    !     integer, allocatable :: devices(:)

    !     integer :: p2pTileDimX, p2pTileDimY
    !     integer :: i, j, nyl, jl, jg, p, access, istat
    !     integer :: xOffset, yOffset
    !     integer :: rDev, sDev, stage

    !     ! determine number of devices

    !     istat = cudaGetDeviceCount(nDevices)
    !     write(*,"('Number of CUDA-capable devices: ', i0,/)") &
    !         nDevices

    !     do i = 0, nDevices-1
    !         istat = cudaGetDeviceProperties(propCuda, i)
    !         write(*,"('  Device ', i0, ': ', a)") i, trim(propCuda%name)
    !     end do

    !     ! check to make sure all devices are P2P accessible with
    !     ! each other and enable peer access, if not exit

    !     do j = 0, nDevices-1
    !         do i = j+1, nDevices-1
    !             istat = cudaDeviceCanAccessPeer(access, j, i)
    !             if (access /= 1) then
    !                 write(*,*) &
    !                     'Not all devices are P2P accessible ', &
    !                     'with each other.'
    !                 write(*,*) &
    !                     'Use the p2pAccess code to determine ', &
    !                     'a subset that can do P2P and set'
    !                 write(*,*) &
    !                     'the environment variable ', &
    !                     'CUDA_VISIBLE_DEVICES accordingly'
    !                 write(*,*) "Test Failed: transpose P2P  "
    !                 return
    !             end if
    !             istat = cudaSetDevice(j)
    !             istat = cudaDeviceEnablePeerAccess(i, 0)
    !             istat = cudaSetDevice(i)
    !             istat = cudaDeviceEnablePeerAccess(j, 0)
    !         end do
    !     end do

    !     ! determine partition sizes and check tile sizes

    !     if (mod(nx,nDevices) == 0 .and. mod(ny,nDevices) == 0) then
    !         p2pTileDimX = nx/nDevices
    !         p2pTileDimY = ny/nDevices
    !     else
    !         write(*,*) 'nx, ny must be multiples of nDevices'
    !         stop
    !     endif

    !     if (mod(p2pTileDimX, cudaTileDim) /= 0 .or. &
    !         mod(p2pTileDimY, cudaTileDim) /= 0) then
    !         write(*,*) 'p2pTileDim* must be multiples of cudaTileDim'
    !         stop
    !     end if

    !     if (mod(cudaTileDim, blockRows) /= 0) then
    !         write(*,*) 'cudaTileDim must be a multiple of blockRows'
    !         stop
    !     end if

    !     dimGrid = dim3(p2pTileDimX/cudaTileDim, &
    !         p2pTileDimY/cudaTileDim, 1)
    !     dimBlock = dim3(cudaTileDim, blockRows, 1)

    !     ! write parameters

    !     write(*,*)
    !     write(*,"(/,'Array size: ', i0,'x',i0,/)") nx, ny

    !     write(*,"('CUDA block size: ', i0,'x',i0, &
    !         &',  CUDA tile size: ', i0,'x',i0)") &
    !         cudaTileDim, blockRows, cudaTileDim, cudaTileDim

    !     write(*,"('dimGrid: ', i0,'x',i0,'x',i0, &
    !         &',   dimBlock: ', i0,'x',i0,'x',i0,/)") &
    !         dimGrid%x, dimGrid%y, dimGrid%z, &
    !         dimBlock%x, dimBlock%y, dimBlock%z

    !     write(*,"('nDevices: ', i0, ', Local input array size: ', &
    !         &i0,'x',i0)") nDevices, nx, p2pTileDimY
    !     write(*,"('p2pTileDim: ', i0,'x',i0,/)") &
    !         p2pTileDimX, p2pTileDimY

    !     write(*,"('async mode: ', l,//)") asyncVersion

    !     ! allocate and initialize arrays

    !     call random_number(h_idata)
    !     gold = transpose(h_idata)

    !     ! A stream is associated with a device,
    !     ! so first index of streamID is the device (0:nDevices-1)
    !     ! and second is the stage, which also spans (0:nDevices-1)
    !     !
    !     ! The 0th stage corresponds to the local transpose (on
    !     ! diagonal tiles), and 1:nDevices-1 are the stages with
    !     ! P2P communication

    !     allocate(streamID(0:nDevices-1,0:nDevices-1))
    !     do p = 0, nDevices-1
    !         istat = cudaSetDevice(p)
    !         do stage = 0, nDevices-1
    !             istat = cudaStreamCreate(streamID(p,stage))
    !         enddo
    !     enddo

    !     ! device data allocation and initialization

    !     allocate(d_idata(0:nDevices-1),&
    !         d_tdata(0:nDevices-1), d_rdata(0:nDevices-1))

    !     do p = 0, nDevices-1
    !         istat = cudaSetDevice(p)
    !         allocate(d_idata(p)%v(nx,p2pTileDimY), &
    !             d_rdata(p)%v(nx,p2pTileDimY), &
    !             d_tdata(p)%v(ny,p2pTileDimX))

    !         yOffset = p*p2pTileDimY
    !         d_idata(p)%v(:,:) = h_idata(:, &
    !             yOffset+1:yOffset+p2pTileDimY)
    !         d_rdata(p)%v(:,:) = -1.0
    !         d_tdata(p)%v(:,:) = -1.0
    !     enddo

    !     ! ---------
    !     ! transpose
    !     ! ---------

    !     do p = 0, nDevices-1
    !         istat = cudaSetDevice(p)
    !         call cuda_thread_synchronize
    !     enddo
    !     timeStart = tic()

    !     ! Stage 0:
    !     ! transpose diagonal blocks (local data) before kicking off
    !     ! transfers and transposes of other blocks

    !     do p = 0, nDevices-1
    !         istat = cudaSetDevice(p)
    !         if (asyncVersion) then
    !             call cudaTranspose &
    !                 <<<dimGrid, dimBlock, 0, streamID(p,0)>>> &
    !                 (d_tdata(p)%v(p*p2pTileDimY+1,1), ny, &
    !                 d_idata(p)%v(p*p2pTileDimX+1,1), nx)
    !         else
    !             call cudaTranspose<<<dimGrid, dimBlock>>> &
    !                 (d_tdata(p)%v(p*p2pTileDimY+1,1), ny, &
    !                 d_idata(p)%v(p*p2pTileDimX+1,1), nx)
    !         endif
    !     enddo

    !     ! now send data to blocks to the right of diagonal
    !     ! (using mod for wrapping) and transpose

    !     do stage = 1, nDevices-1    ! stages = offset diagonals
    !         do rDev = 0, nDevices-1  ! device that receives
    !             sDev = mod(stage+rDev, nDevices)  ! dev that sends

    !             if (asyncVersion) then
    !                 istat = cudaSetDevice(rDev)
    !                 istat = cudaMemcpy2DAsync( &
    !                     d_rdata(rDev)%v(sDev*p2pTileDimX+1,1), nx, &
    !                     d_idata(sDev)%v(rDev*p2pTileDimX+1,1), nx, &
    !                     p2pTileDimX, p2pTileDimY, &
    !                     stream=streamID(rDev,stage))
    !             else
    !                 istat = cudaMemcpy2D( &
    !                     d_rdata(rDev)%v(sDev*p2pTileDimX+1,1), nx, &
    !                     d_idata(sDev)%v(rDev*p2pTileDimX+1,1), nx, &
    !                     p2pTileDimX, p2pTileDimY)
    !             end if

    !             istat = cudaSetDevice(rDev)
    !             if (asyncVersion) then
    !                 call cudaTranspose &
    !                     <<<dimGrid, dimBlock, 0, &
    !                     streamID(rDev,stage)>>>  &
    !                     (d_tdata(rDev)%v(sDev*p2pTileDimY+1,1), ny, &
    !                     d_rdata(rDev)%v(sDev*p2pTileDimX+1,1), nx)
    !             else
    !                 call cudaTranspose<<<dimGrid, dimBlock>>> &
    !                     (d_tdata(rDev)%v(sDev*p2pTileDimY+1,1), ny, &
    !                     d_rdata(rDev)%v(sDev*p2pTileDimX+1,1), nx)
    !             endif
    !         enddo
    !     enddo

    !     ! wait for execution to complete and get wallclock
    !     do p = 0, nDevices-1
    !         istat = cudaSetDevice(p)
    !         istat = cudaDeviceSynchronize()
    !     enddo
    !     timeStop = tic()

    !     ! transfer results to host and check for errors

    !     do p = 0, nDevices-1
    !         xOffset = p*p2pTileDimX
    !         istat = cudaSetDevice(p)
    !         h_tdata(:, xOffset+1:xOffset+p2pTileDimX) = &
    !             d_tdata(p)%v(:,:)
    !     end do

    !     if (all(h_tdata == gold)) then
    !         write(*,"(' *** Test transpose P2P: Passed ***',/)")
    !         write(*,"('Bandwidth (GB/s): ', f7.2,/)") &
    !             2.*(nx*ny*4)/(1.0e+9*(timeStop-timeStart))
    !     else
    !         write(*,"(' *** Test transpose P2P: Failed ***',/)")
    !     endif

    !     ! cleanup

    !     do p = 0, nDevices-1
    !         istat = cudaSetDevice(p)
    !         deallocate(d_idata(p)%v, d_tdata(p)%v, d_rdata(p)%v)
    !         do stage = 0, nDevices-1
    !             istat = cudaStreamDestroy(streamID(p,stage))
    !         enddo
    !     end do
    !     deallocate(d_idata, d_tdata, d_rdata)

    ! end subroutine test_transposeP2P


end program simple_test_cuda

module simple_cuda
include 'simple_lib.f08'
use, intrinsic :: ISO_C_BINDING
use CUDA
implicit none

! public :: check_cuda_device, test_FortCUDA_kernels
! private

! #include "simple_local_flags.inc"

contains

    subroutine check_cuda_device
        integer :: device
        integer :: deviceCount
        integer :: gpuDeviceCount
        type( cudaDeviceProp ) :: properties
        integer(c_int) :: cudaResultCode
        deviceCount=0
        gpuDeviceCount=0
        ! Obtain the device count from the system and check for errors
        cudaResultCode = cudaGetDeviceCount(deviceCount)
        if (cudaResultCode /= cudaSuccess) then
            deviceCount = 0
        end if

        ! Check for the device to be an emulator. If not, increment the counter
        do device = 0, deviceCount - 1, 1
            cudaResultCode = cudaGetDeviceProperties(properties, device)
            if (properties%major /= 9999) gpuDeviceCount = gpuDeviceCount + 1
        end do

        print*, gpuDeviceCount, " GPU CUDA device(s) found"

        do device = 0, deviceCount - 1, 1
            print*, "    Cuda device ", device
            cudaResultCode = cudaGetDeviceProperties(properties,device)
            print*, "    name :", properties%name
            print*, "    totalGlobablMem:", properties%totalGlobalMem
            print*, "    sharedMemPerBlock:", properties%sharedMemPerBlock
            print*, "    regsPerBlock:", properties%regsPerBlock
            print*, "    warpSize:", properties%warpSize
            print*, "    memPitch:", properties%memPitch
            print*, "    maxThreadsPerBlock:", properties%maxThreadsPerBlock
            print*, "    maxThreadsDim:", properties%maxThreadsDim(1), properties%maxThreadsDim(2), properties%maxThreadsDim(3)
            print*, "    maxGridSize:", properties%maxGridSize(1), properties%maxGridSize(2), properties%maxGridSize(3)
            print*, "    clockRate:", properties%clockRate
            print*, "    totalConstMem:", properties%totalConstMem
            print*, "    major:", properties%major
            print*, "    minor:", properties%minor
            print*, "    textureAlignment:", properties%textureAlignment
            print*, "    deviceOverlap:", properties%deviceOverlap
            print*, "    multiProcessorCount:", properties%multiProcessorCount
        end do
        print *, " Check CUDA completed "
    end subroutine check_cuda_device

    subroutine set_cuda_device(d)
        integer , intent(in) :: d
        integer :: device
        integer :: deviceCount
        type( cudaDeviceProp ) :: properties
        integer(c_int) :: cudaResultCode

        deviceCount=0
        ! Obtain the device count from the system and check for errors
        cudaResultCode = cudaGetDeviceCount(deviceCount)
        if (cudaResultCode /= cudaSuccess) then
            call simple_stop( "simple_cuda::set_cuda_device  cudaGetDeviceCount failed ")

        end if
        if (d >= deviceCount) call simple_stop( "simple_cuda::set_cuda_device index too high ")

        cudaResultCode = cudaGetDeviceProperties(properties, d)
        if (cudaResultCode /= cudaSuccess) then
            call simple_stop( "simple_cuda::set_cuda_device cudaGetDeviceProperties failed ")
        endif

        cudaResultCode = cudaSetDevice(d)
        if (cudaResultCode /= cudaSuccess) then
            call simple_stop( "simple_cuda::set_cuda_device cudaSetDevice failed ")
        endif

    end subroutine set_cuda_device

    function get_cuda_property(d) result(properties)
         integer , intent(in) :: d
         integer :: deviceCount
         type( cudaDeviceProp ) :: properties
         integer(c_int) :: cudaResultCode

         deviceCount=0

        ! Obtain the device count from the system and check for errors
        cudaResultCode = cudaGetDeviceCount(deviceCount)
        if (cudaResultCode /= cudaSuccess) then
            call simple_stop( "simple_cuda::set_cuda_device  cudaGetDeviceCount failed ")

        end if
        if (d >= deviceCount) call simple_stop( "simple_cuda::set_cuda_device index too high ")

        cudaResultCode = cudaGetDeviceProperties(properties, d)
        if (cudaResultCode /= cudaSuccess) then
            call simple_stop( "simple_cuda::set_cuda_device cudaGetDeviceProperties failed ")
        endif
    end function get_cuda_property


    subroutine test_FortCUDA_kernels (arg)
        use FortCUDA_kernels
        implicit none
        real, intent(in) :: arg

        type :: HostPtr
            real, pointer, dimension(:) :: host_ptr => null()
        end type HostPtr

        real :: diff
        integer :: i, j
        integer, parameter :: num_streams = 5
        integer(c_int), parameter :: NTHREADS = 2000000

        type (cudaEvent_t) :: e_start, e_stop
        type (dim3) :: nblk, nthrd
        type (c_ptr) :: err_ptr
        type (cudaStream_t) :: stream(num_streams)
        type (cudaStream_t) :: all_streams
        type (c_ptr) :: d_A(num_streams), d_B(num_streams), d_C(num_streams)
        type (c_ptr) :: h_c_A(num_streams), h_c_B(num_streams), h_c_C(num_streams)
        type (HostPtr) :: h_A(num_streams), h_B(num_streams), h_C(num_streams)
        integer(kind(cudaSuccess)) :: err

        type (cudaDeviceProp) :: prop

        integer (c_int) :: zero = 0
        real (c_float) :: c_time
        integer(c_int) :: sz, flags, device_count
        integer(c_int) :: NTHREADS_PER_BLOCK = 256
        integer(c_int) :: NUM_BLOCKS

        real(KIND=KIND(1.d0)), parameter :: REAL_DP_ELEMENT = 0.d0
        real, parameter :: REAL_ELEMENT = 0.0
        integer, parameter :: INTEGER_ELEMENT = 0
        character(len=1), parameter :: BYTE(1) = 'A'

        integer, parameter :: SIZE_OF_REAL_DP = SIZE( TRANSFER( REAL_DP_ELEMENT, ['a'] ) )
        integer, parameter :: SIZE_OF_REAL = SIZE( TRANSFER( REAL_ELEMENT, ['a'] ) )
        integer, parameter :: SIZE_OF_INTEGER = SIZE( TRANSFER( INTEGER_ELEMENT, ['a'] ) )

        logical :: b, pass

#define SIZE_OF( element ) SIZE( TRANSFER( element, ['a'] ) )
#define HANDLE_ERROR( return_err )  call my_cudaErrorCheck( return_err, b )
        print*, "Cuda Kernels test:  test_fortcuda_kernels "
        sz = NTHREADS
        ! allocate(h_A(sz), h_B(sz), h_C(sz))
        !..........................................
        ! Create the streams and events for timing
        !..........................................
        stream = cudaStream_t(C_NULL_PTR)
        all_streams = cudaStream_t(C_NULL_PTR)
        e_start = cudaEvent_t(C_NULL_PTR)
        e_stop = cudaEvent_t(C_NULL_PTR)

        print *, 'SIZE_OF_REAL_DP = ', SIZE_OF_REAL_DP, SIZE_OF( REAL_DP_ELEMENT )
        print *, 'SIZE_OF_REAL = ', SIZE_OF_REAL, SIZE_OF( REAL_ELEMENT )
        print *, 'SIZE_OF_INTEGER = ' , SIZE_OF_INTEGER, SIZE_OF( INTEGER_ELEMENT )

        HANDLE_ERROR( cudaGetDeviceCount( device_count ) )
        do i = 0, device_count - 1
            HANDLE_ERROR( cudaGetDeviceProperties( prop, i ) )
            print *, '-------------------------------------------'
            print *, 'Device #', i
            print *, 'Total Global Memory =', prop % totalGlobalMem
            print *, 'Max Threads Per Block =', prop % maxThreadsPerBlock
            print *, 'Max Grid Size =', prop % maxGridSize( 1:3 )
        enddo

        NTHREADS_PER_BLOCK = MAX( NTHREADS_PER_BLOCK, prop % maxThreadsPerBlock )
        NUM_BLOCKS = MIN( prop % maxGridSize( 1 ), &
            & ( NTHREADS + NTHREADS_PER_BLOCK - 1 ) / NTHREADS_PER_BLOCK )

        print *, ''
        print *, '-----------------------------------------'
        print *, '  Dimensions for this Example'
        print *, '-----------------------------------------'
        print *, 'NTHREADS =', NTHREADS
        print *, 'NTHREADS_PER_BLOCK =', NTHREADS_PER_BLOCK
        print *, 'NUM_BLOCKS = ', NUM_BLOCKS
        print *, '-----------------------------------------'

        HANDLE_ERROR( cudaSetDevice( 0 ) )
        HANDLE_ERROR( cudaEventCreate( e_start ) )
        HANDLE_ERROR( cudaEventCreate( e_stop ) )

        do i = 1, num_streams
            HANDLE_ERROR( cudaStreamCreate( stream(i) ) )
            HANDLE_ERROR( cudaMalloc( d_A(i), sz*4 ) )
            HANDLE_ERROR( cudaMalloc( d_B(i), sz*4 ) )
            HANDLE_ERROR( cudaMalloc( d_C(i), sz*4 ) )
        end do


        nblk = dim3( NUM_BLOCKS ,1, 1 )
        nthrd = dim3( NTHREADS_PER_BLOCK, 1, 1 )

        do i = 1, num_streams
            !........................................
            ! Create pinned host memory
            !........................................
            HANDLE_ERROR( cudaMallocHost( h_c_A(i), sz*4 ) )
            HANDLE_ERROR( cudaMallocHost( h_c_B(i), sz*4 ) )
            HANDLE_ERROR( cudaMallocHost( h_c_C(i), sz*4 ) )

            call C_F_POINTER( h_c_A(i), h_A(i) % host_ptr, [sz] )
            call C_F_POINTER( h_c_B(i), h_B(i) % host_ptr, [sz] )
            call C_F_POINTER( h_c_C(i), h_C(i) % host_ptr, [sz] )

            h_A(i) % host_ptr = 10.2
            h_B(i) % host_ptr = 20.1
            h_C(i) % host_ptr  = 0.

        enddo

        HANDLE_ERROR( cudaEventRecord( e_start, all_streams ) )

        do i = 1, num_streams

            err = cudaMemcpyAsync( d_A(i), &
                & c_loc( h_A(i) % host_ptr(1) ), &
                & sz*4, &
                & cudaMemCpyHostToDevice, &
                & stream(i) )
            HANDLE_ERROR( err )
            err = cudaMemcpyAsync( d_B(i), &
                & c_loc( h_B(i) % host_ptr(1) ), &
                & sz*4, &
                & cudaMemCpyHostToDevice, &
                & stream(i) )
            HANDLE_ERROR( err )
            err = cudaMemcpyAsync( d_C(i), &
                & c_loc( h_C(i) % host_ptr(1) ), &
                & sz*4, &
                & cudaMemCpyHostToDevice, &
                & stream(i) )
            HANDLE_ERROR( err )

        enddo

        do i = 1, num_streams

            call vecAdd_Float(d_A(i), d_B(i), d_C(i), nblk, nthrd, NTHREADS, stream(i))

        enddo

        do i = 1, num_streams

            err = cudaMemcpyAsync( c_loc( h_C(i) % host_ptr(1) ), &
                & d_C(i), &
                & sz*4, &
                & cudaMemCpyDeviceToHost, &
                & stream(i) )
            HANDLE_ERROR( err )
            HANDLE_ERROR( cudaStreamQuery( stream(i) ) )

        end do

        HANDLE_ERROR( cudaEventRecord( e_stop, all_streams ) )
        HANDLE_ERROR( cudaEventSynchronize( e_stop ) )

        do i = 1, num_streams
            HANDLE_ERROR( cudaStreamQuery( stream(i) ) )
        enddo

        HANDLE_ERROR( cudaEventElapsedTime( c_time, e_start, e_stop ) )

        print *, 'Elapsed time = ', c_time
        print *,'*--------------------------------------------------------------------------------*'
        if ( sz < 51 ) then
            do j = 1, num_streams
                do i=1,sz
                    diff = h_A(j) % host_ptr(i) + h_B(j) % host_ptr(i) - h_C(j) % host_ptr(i)
                    print *, h_A(j) % host_ptr(i), h_B(j) % host_ptr(i), h_C(j) % host_ptr(i), diff
                enddo
            end do
        else
            do j = 1, num_streams
                pass = .true.
                diff = 0.
                do i = 1, sz
                    diff = h_A(j) % host_ptr(i) + h_B(j) % host_ptr(i) - h_C(j) % host_ptr(i)
                    if ( abs( diff ) > 1.e-6 ) then
                        print *, 'diff = ', diff
                        pass = .false.
                        exit
                    endif
                end do

                if ( .not. pass ) then
                    print *, 'Stream (', j, ') kernel resulted in incorrect values.'
                else
                    print *, 'Stream (', j, ') passed'
                end if
            end do
        end if

        print *,'*--------------------------------------------------------------------------------*'

        HANDLE_ERROR( cudaEventDestroy( e_start ) )
        HANDLE_ERROR( cudaEventDestroy( e_stop ) )
        do i = 1, num_streams
            HANDLE_ERROR( cudaFree( d_A(i) ) )
            HANDLE_ERROR( cudaFree( d_B(i) ) )
            HANDLE_ERROR( cudaFree( d_C(i) ) )
            HANDLE_ERROR( cudaStreamDestroy( stream(i)) )

            HANDLE_ERROR( cudaFreeHost( h_c_A(i) ) )
            HANDLE_ERROR( cudaFreeHost( h_c_B(i) ) )
            HANDLE_ERROR( cudaFreeHost( h_c_C(i) ) )
        enddo

    end subroutine test_FortCUDA_kernels


end module simple_cuda

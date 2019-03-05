! patched-based anisotropic motion correction
module simple_motion_patched
!$ use omp_lib
!$ use omp_lib_kinds
include 'simple_lib.f08'
use simple_parameters,      only: params_glob
use simple_opt_factory,     only: opt_factory
use simple_opt_spec,        only: opt_spec
use simple_optimizer,       only: optimizer
use simple_image,           only: image
use simple_ft_expanded,     only: ft_expanded
use simple_ftexp_shsrch,    only: ftexp_shsrch
use CPlot2D_wrapper_module
implicit none
private
public :: motion_patched
#include "simple_local_flags.inc"

! module global constants
integer, parameter :: NX_PATCHED     = 5   ! number of patches in x-direction
integer, parameter :: NY_PATCHED     = 5   !       "      "       y-direction
integer, parameter :: X_OVERLAP      = 0   ! number of overlapping pixels per patch in x-direction
integer, parameter :: Y_OVERLAP      = 0   !       "      "        "         "         y-direction
real,    parameter :: TOL            = 1e-6 !< tolerance parameter
real,    parameter :: TRS_DEFAULT    = 7.
integer, parameter :: PATCH_PDIM     = 18  ! dimension of fitted polynomial
logical, parameter :: DUMP_STUFF     = .false.

type :: rmat_ptr_type
    real, pointer :: rmat_ptr(:,:,:)
end type rmat_ptr_type

type :: motion_patched
    private
    logical                          :: existence
    type(ft_expanded),  allocatable  :: frame_patches(:,:,:)
    type(ft_expanded),  allocatable  :: ref_patches(:,:,:)
    type(image),        allocatable  :: patches_imgs(:,:,:)
    type(ftexp_shsrch), allocatable  :: shsearch_patches(:,:,:)
    real,               allocatable  :: shifts_patches(:,:,:,:)
    real,               allocatable  :: shifts_patches_for_fit(:,:,:,:)
    character(len=:),   allocatable  :: shift_fname
    integer                          :: nframes
    integer                          :: ldim(3)       ! size of entire frame, reference
    integer                          :: ldim_patch(3) ! size of one patch
    integer                          :: lims_patches(NX_PATCHED,NY_PATCHED,2,2) ! corners of the patches
    real                             :: patch_centers(NX_PATCHED,NY_PATCHED,2)
    real                             :: motion_correct_ftol
    real                             :: motion_correct_gtol
    real(dp)                         :: poly_coeffs(PATCH_PDIM,2)  ! coefficients of fitted polynomial
    real                             :: trs
    real                             :: hp
    real                             :: lp
contains
    procedure, private               :: allocate_fields
    procedure, private               :: deallocate_fields
    procedure, private               :: set_size_frames_ref
    procedure, private               :: set_patches
    procedure, private               :: det_shifts
    procedure, private               :: fit_polynomial
    procedure, private               :: get_local_shift
    procedure, private               :: apply_polytransfo
    procedure, private               :: write_shifts
    procedure, private               :: write_shifts_for_fit
    procedure, private               :: write_polynomial
    procedure, private               :: plot_shifts
    procedure                        :: new             => motion_patched_new
    procedure                        :: correct         => motion_patched_correct
    procedure                        :: kill            => motion_patched_kill
end type motion_patched

contains

    ! Polynomial for patch motion
    function patch_poly(p, n) result(res)
        real(dp), intent(in) :: p(:)
        integer,  intent(in) :: n
        real(dp) :: res(n)
        real(dp) :: x, y, t
        x = p(1)
        y = p(2)
        t = p(3)
        res(    1) = t
        res(    2) = t**2
        res(    3) = t**3
        res( 4: 6) = x * res( 1: 3)  ! x   * {t,t^2,t^3}
        res( 7: 9) = x * res( 4: 6)  ! x^2 * {t,t^2,t^3}
        res(10:12) = y * res( 1: 3)  ! y   * {t,t^2,t^3}
        res(13:15) = y * res(10:12)  ! y^2 * {t,t^2,t^3}
        res(16:18) = y * res( 4: 6)  ! x*y * {t,t^2,t^3}
    end function patch_poly

    function apply_patch_poly(c, x, y, t) result(res_sp)
        real(dp), intent(in) :: c(PATCH_PDIM), x, y, t
        real(sp) :: res_sp
        real(dp) :: res
        real(dp) :: x2, y2, xy, t2, t3
        x2 = x * x
        y2 = y * y
        xy = x * y
        t2 = t * t
        t3 = t2 * t
        res = 0._dp
        res = res + c( 1) * t      + c( 2) * t2      + c( 3) * t3
        res = res + c( 4) * t * x  + c( 5) * t2 * x  + c( 6) * t3 * x
        res = res + c( 7) * t * x2 + c( 8) * t2 * x2 + c( 9) * t3 * x2
        res = res + c(10) * t * y  + c(11) * t2 * y  + c(12) * t3 * y
        res = res + c(13) * t * y2 + c(14) * t2 * y2 + c(15) * t3 * y2
        res = res + c(16) * t * xy + c(17) * t2 * xy + c(18) * t3 * xy
        res_sp = real(res)
    end function apply_patch_poly

    subroutine fit_polynomial( self )
        class(motion_patched), intent(inout) :: self
        real(dp) :: y(  self%nframes*NX_PATCHED*NY_PATCHED)
        real(dp) :: x(3,self%nframes*NX_PATCHED*NY_PATCHED)    ! x,y,t
        real(dp) :: sig(self%nframes*NX_PATCHED*NY_PATCHED)
        real(dp) :: a(PATCH_PDIM), v(PATCH_PDIM,PATCH_PDIM), w(PATCH_PDIM), chisq
        integer  :: iframe, i, j
        integer  :: idx
        integer  :: k1,k2
        do iframe = 1, self%nframes
            do i = 1, NX_PATCHED
                do j = 1, NY_PATCHED
                    self%patch_centers(i,j,1)= real(self%lims_patches(i,j,1,1) + self%lims_patches(i,j,1,2)) / 2.
                    self%patch_centers(i,j,2)= real(self%lims_patches(i,j,2,1) + self%lims_patches(i,j,2,2)) / 2.
                    idx = (iframe-1) * (NX_PATCHED * NY_PATCHED) + (i-1) * NY_PATCHED + j
                    y(idx) = real(self%shifts_patches_for_fit(2,iframe,i,j),dp)   ! shift in x-direction first
                    x(1,idx) = real(self%patch_centers(i,j,1),dp) / real(self%ldim(1),dp) - 0.5_dp
                    x(2,idx) = real(self%patch_centers(i,j,2),dp) / real(self%ldim(2),dp) - 0.5_dp
                    x(3,idx) = real(iframe,dp) - 0.5_dp
                end do
            end do
        end do
        sig = 1.
        ! dump the shifts for debugging purposes
        if (.true.) then
            open(unit=123,file='for_fitting.txt')
            write (123,'(A)',advance='no') 'y=['
            do k1 = 1, self%nframes*NX_PATCHED*NY_PATCHED
                write (123,'(A)',advance='no') trim(dbl2str(y(k1)))
                if (k1 < self%nframes*NX_PATCHED*NY_PATCHED) write (123,'(A)',advance='no') ', '
            end do
            write (123,*) '];'

            do k2 = 1,3

                write (123,'(A)',advance='no') 'x' // trim(int2str(k2)) // '=['
                do k1 = 1, self%nframes*NX_PATCHED*NY_PATCHED
                    write (123,'(A)',advance='no') trim(dbl2str(x(k2,k1)))
                    if (k1 < self%nframes*NX_PATCHED*NY_PATCHED) write (123,'(A)',advance='no') ', '
                end do
                write (123,*) '];'
            end do
            close(123)
        end if
        ! fit polynomial for shifts in x-direction
        call svd_multifit(x,y,sig,a,v,w,chisq,patch_poly)
        ! store polynomial coefficients
        self%poly_coeffs(:,1) = a
        do iframe = 1, self%nframes
            do i = 1, NX_PATCHED
                do j = 1, NY_PATCHED
                    idx = (iframe-1) * (NX_PATCHED * NY_PATCHED) + (i-1) * NY_PATCHED + j
                    y(idx) = real(self%shifts_patches_for_fit(3,iframe,i,j),dp)   ! shift in y-direction first
                end do
            end do
        end do
        ! fit polynomial for shifts in y-direction
        call svd_multifit(x,y,sig,a,v,w,chisq,patch_poly)
        self%poly_coeffs(:,2) = a
        if (DUMP_STUFF) then
            call self%write_polynomial(self%poly_coeffs(:,1),'X:')
            call self%write_polynomial(self%poly_coeffs(:,2),'Y:')
        end if
    end subroutine fit_polynomial

    ! write the polynomials to disk for debugging purposes
    subroutine write_polynomial( self, p, name )
        class(motion_patched),    intent(inout) :: self
        real(dp),                 intent(in)    :: p(PATCH_PDIM)
        character(len=*),         intent(in)    :: name
        integer :: i
        logical :: exist
        inquire(file="polynomial.txt", exist=exist)
        if (exist) then
            open(123, file="polynomial.txt", status="old", position="append", action="write")
        else
            open(123, file="polynomial.txt", status="new", action="write")
        end if
        write (123,*) 'POLYNOMIAL, ' // name
        do i = 1, PATCH_PDIM
            write (123,'(A)') 'c' // trim(int2str(i)) // '=' // trim(dbl2str(p(i)))
        end do
        close(123)
    end subroutine write_polynomial

    subroutine plot_shifts(self)
        class(motion_patched), intent(inout) :: self
        real, parameter       :: SCALE = 40.
        real                  :: shift_scale
        type(str4arr)         :: title
        type(CPlot2D_type)    :: plot2D
        type(CDataSet_type)   :: dataSetStart, dataSet        !!!!!! todo: we don't need this
        type(CDataSet_type)   :: fit, obs
        type(CDataSet_type)   :: patch_start
        type(CDataPoint_type) :: point2, p_obs, p_fit, point
        real                  :: xcenter, ycenter
        integer               :: ipx, ipy, iframe, j
        real                  :: loc_shift(2)
        shift_scale = SCALE
        call CPlot2D__new(plot2D, self%shift_fname)
        call CPlot2D__SetXAxisSize(plot2D, 600._c_double)
        call CPlot2D__SetYAxisSize(plot2D, 600._c_double)
        call CPlot2D__SetDrawLegend(plot2D, C_FALSE)
        call CPlot2D__SetFlipY(plot2D, C_TRUE)
        call CDataSet__new(dataSet)
        call CDataSet__SetDrawMarker(dataSet, C_FALSE)
        call CDataSet__SetDatasetColor(dataSet, 0.0_c_double, 0.0_c_double, 1.0_c_double)
        xcenter = real(self%ldim(1))/2.
        ycenter = real(self%ldim(2))/2.
        do j = 1, self%nframes
            call CDataPoint__new2(real(xcenter,c_double), real(ycenter, c_double), point)
            call CDataSet__AddDataPoint(dataSet, point)
        end do
        call CPlot2D__AddDataSet(plot2D, dataset)

        call CDataSet__new(dataSetStart)
        call CDataSet__SetDrawMarker(dataSetStart, C_TRUE)
        call CDataSet__SetMarkerSize(dataSetStart,5._c_double)
        call CDataSet__SetDatasetColor(dataSetStart, 1.0_c_double,0.0_c_double,0.0_c_double)
        call CDataPoint__new2(real(xcenter,c_double), real(ycenter,c_double), point2)
        call CDataSet__AddDataPoint(dataSetStart, point2)
        call CPlot2D__AddDataSet(plot2D, dataSetStart)
        do ipx = 1, NX_PATCHED
            do ipy = 1, NY_PATCHED
                call CDataSet__new(patch_start)
                call CDataSet__SetDrawMarker(patch_start,C_TRUE)
                call CDataSet__SetMarkerSize(patch_start,5.0_c_double)
                call CDataSet__SetDatasetColor(patch_start,1.0_c_double,0.0_c_double,0.0_c_double)
                call CDataSet__new(fit)
                call CDataSet__new(obs)
                call CDataSet__SetDrawMarker(fit, C_FALSE)
                call CDataSet__SetDatasetColor(fit, 0.0_c_double,0.0_c_double,0.0_c_double)
                call CDataSet__SetDrawMarker(obs, C_FALSE)
                call CDataSet__SetDatasetColor(obs, 0.5_c_double,0.5_c_double,0.5_c_double)
                do iframe = 1, self%nframes
                    call CDataPoint__new2(&
                        real(self%patch_centers(ipx, ipy, 1) + &
                        SCALE * self%shifts_patches_for_fit(2, iframe, ipx, ipy), c_double), &
                        real(self%patch_centers(ipx, ipy, 2) + &
                        SCALE * self%shifts_patches_for_fit(3, iframe, ipx, ipy), c_double), &
                        p_obs)
                    call CDataSet__AddDataPoint(obs, p_obs)
                    call self%get_local_shift(iframe, self%patch_centers(ipx, ipy, 1), &
                        self%patch_centers(ipy, ipy, 2), loc_shift)
                    call CDataPoint__new2(&
                        real(self%patch_centers(ipx, ipy, 1) + SCALE * loc_shift(1), c_double), &
                        real(self%patch_centers(ipx, ipy, 2) + SCALE * loc_shift(2) ,c_double), &
                        p_fit)
                    call CDataSet__AddDataPoint(fit, p_fit)
                    if (iframe == 1) then
                        call CDataSet__AddDataPoint(patch_start, p_fit)
                    end if
                    call CDataPoint__delete(p_fit)
                    call CDataPoint__delete(p_obs)
                end do
                call CPlot2D__AddDataSet(plot2D, obs)
                call CPlot2D__AddDataSet(plot2D, fit)
                call CPlot2D__AddDataSet(plot2D, patch_start)
                call CDataSet__delete(patch_start)
                call CDataSet__delete(fit)
                call CDataSet__delete(obs)
            end do
        end do
        title%str = 'X (in pixels; trajectory scaled by ' // trim(real2str(SHIFT_SCALE)) // ')' // C_NULL_CHAR
        call CPlot2D__SetXAxisTitle(plot2D, title%str)
        title%str(1:1) = 'Y'
        call CPlot2D__SetYAxisTitle(plot2D, title%str)
        call CPlot2D__OutputPostScriptPlot(plot2D, self%shift_fname)
        call CPlot2D__delete(plot2D)
    end subroutine plot_shifts

    subroutine get_local_shift( self, iframe, x, y, shift )
        class(motion_patched), intent(inout) :: self
        integer,               intent(in)  :: iframe
        real,                  intent(in)  :: x, y
        real,                  intent(out) :: shift(2)
        real :: t, xx, yy
        t  = real(iframe - 1)
        xx = x / real(self%ldim(1)) - 0.5
        yy = y / real(self%ldim(2)) - 0.5
        shift(1) = apply_patch_poly(self%poly_coeffs(:,1),real(xx,dp),real(yy,dp),real(t,dp))
        shift(2) = apply_patch_poly(self%poly_coeffs(:,2),real(xx,dp),real(yy,dp),real(t,dp))
    end subroutine get_local_shift

    subroutine apply_polytransfo( self, frames, frames_output )
        class(motion_patched),    intent(inout) :: self
        type(image), allocatable, intent(inout) :: frames(:)
        type(image), allocatable, intent(inout) :: frames_output(:)
        integer :: i, j, iframe
        real    :: x, y, t
        real    :: x_trafo, y_trafo
        type(rmat_ptr_type) :: rmat_ins(self%nframes), rmat_outs(self%nframes)
        do iframe = 1, self%nframes
            call frames_output(iframe)%new(self%ldim, params_glob%smpd)
            if (frames(iframe)%is_ft()) call frames(iframe)%ifft()
            call frames(iframe)%get_rmat_ptr(rmat_ins(iframe)%rmat_ptr)
            call frames_output(iframe)%get_rmat_ptr(rmat_outs(iframe)%rmat_ptr)
        end do
        !$omp parallel do collapse(3) default(shared) private(iframe,j,i,x,y,t,x_trafo,y_trafo) proc_bind(close) schedule(static)
        do iframe = 1, self%nframes
            do i = 1, self%ldim(1)
                do j = 1, self%ldim(2)
                    t = real(iframe - 1)
                    x = real(i) / real(self%ldim(1)) - 0.5
                    y = real(j) / real(self%ldim(2)) - 0.5
                    x_trafo = real(i) - apply_patch_poly(self%poly_coeffs(:,1),real(x,dp),real(y,dp),real(t,dp))
                    y_trafo = real(j) - apply_patch_poly(self%poly_coeffs(:,2),real(x,dp),real(y,dp),real(t,dp))
                    rmat_outs(iframe)%rmat_ptr(i,j,1) = interp_bilin(x_trafo, y_trafo, iframe, rmat_ins )
                end do
            end do
        end do
        !$omp end parallel do
    contains

        function interp_bilin( xval, yval, iiframe, rmat_ins2 ) result(val)
            real,  intent(in)    :: xval, yval
            integer, intent(in)  :: iiframe
            type(rmat_ptr_type), intent(in) :: rmat_ins2(self%nframes)
            real     :: val
            !logical  :: x1_valid, x2_valid, y1_valid, y2_valid
            integer  :: x1_h,  x2_h,  y1_h,  y2_h
            integer  :: x1_hh, x2_hh, y1_hh, y2_hh
            real     :: y1, y2, y3, y4, t, u
            ! if outside of image
!!$        if ((x(1) < 1._dp) .or. (x(1) >= self%ldim_out(1)) .or. (x(2) < 1._dp) .or. (x(2) >= self%ldim_out(2))) then
!!$            val  = 0._dp
!!$            return
!!$        end if
            x1_h = floor(xval)
            x1_hh = x1_h
            if (x1_h < 1) then
                x1_hh = x1_h + self%ldim(1)
            else if (x1_h > self%ldim(1)) then
                x1_hh = x1_h - self%ldim(1)
            end if
            x2_h = x1_h + 1
            x2_hh = x2_h
            if (x2_h < 1) then
                x2_hh = x2_h + self%ldim(1)
            else if (x2_h > self%ldim(1)) then
                x2_hh = x2_h - self%ldim(1)
            end if
            y1_h = floor(yval)
            y1_hh = y1_h
            if (y1_h < 1) then
                y1_hh = y1_h + self%ldim(2)
            else if (y1_h > self%ldim(2)) then
                y1_hh = y1_h - self%ldim(2)
            end if
            y2_h = y1_h + 1
            y2_hh = y2_h
            if (y2_h < 1) then
                y2_hh = y2_h + self%ldim(2)
            else if (y2_h > self%ldim(2)) then
                y2_hh = y2_h - self%ldim(2)
            end if
!!$            y1 = rmat_in(x1_hh, y1_hh, 1)
!!$            y2 = rmat_in(x2_hh, y1_hh, 1)
!!$            y3 = rmat_in(x2_hh, y2_hh, 1)
!!$            y4 = rmat_in(x1_hh, y2_hh, 1)
            if ((x1_hh < 1).or.(x1_hh > self%ldim(1)).or.&
                (x2_hh < 1).or.(x2_hh > self%ldim(1)).or.&
                (y1_hh < 1).or.(y1_hh > self%ldim(2)).or.&
                (y2_hh < 1).or.(y2_hh > self%ldim(2))) then
                write (*,*) 'xval = ', xval
                write (*,*) 'yval = ', yval
                write (*,*) 'x1_hh =', x1_hh
                write (*,*) 'x2_hh =', x2_hh
                write (*,*) 'y1_hh =', y1_hh
                write (*,*) 'y2_hh =', y2_hh
                write (*,*) 'poly_coeffs_x=', self%poly_coeffs(:,1)
                write (*,*) 'poly_coeffs_y=', self%poly_coeffs(:,2)
                call flush(6)
            end if
            y1 = rmat_ins2(iiframe)%rmat_ptr(x1_hh, y1_hh, 1)
            y2 = rmat_ins2(iiframe)%rmat_ptr(x2_hh, y1_hh, 1)
            y3 = rmat_ins2(iiframe)%rmat_ptr(x2_hh, y2_hh, 1)
            y4 = rmat_ins2(iiframe)%rmat_ptr(x1_hh, y2_hh, 1)

            t    = xval - x1_h
            u    = yval - y1_h
            val  =  (1. - t) * (1. - u) * y1 + &
               t  * (1. - u) * y2 + &
               t  *          u  * y3 + &
                (1. - t) *          u  * y4
        end function interp_bilin

    end subroutine apply_polytransfo

    ! write the shifts to disk
    subroutine write_shifts( self )
        class(motion_patched), intent(inout) :: self
        integer :: i,j
        open(123, file='shifts.txt')
        write (123,*) 'shifts_x=[...'
        do i = 1, NX_PATCHED
            do j = 1, NY_PATCHED
                write (123,'(A)',advance='no') real2str(self%shifts_patches(2,1,i,j))
                if (j < NY_PATCHED) write (123,'(A)',advance='no') ', '
            end do
            if (i < NX_PATCHED) write (123,*) '; ...'
        end do
        write (123,*) '];'
        write (123,*) 'shifts_y=[...'
        do i = 1, NX_PATCHED
            do j = 1, NY_PATCHED
                write (123,'(A)',advance='no') real2str(self%shifts_patches(3,1,i,j))
                if (j < NY_PATCHED) write (123,'(A)',advance='no') ', '
            end do
            if (i < NX_PATCHED) write (123,*) '; ...'
        end do
        write (123,*) '];'
        close(123)
    end subroutine write_shifts

    subroutine write_shifts_for_fit( self )
        class(motion_patched), intent(inout) :: self
        integer :: i,j
        open(123, file='shifts_for_fit.txt')
        write (123,*) 'shiftsff_x=[...'
        do i = 1, NX_PATCHED
            do j = 1, NY_PATCHED
                write (123,'(A)',advance='no') real2str(self%shifts_patches_for_fit(2,1,i,j))
                if (j < NY_PATCHED) write (123,'(A)',advance='no') ', '
            end do
            if (i < NX_PATCHED) write (123,*) '; ...'
        end do
        write (123,*) '];'
        write (123,*) 'shiftsff_y=[...'
        do i = 1, NX_PATCHED
            do j = 1, NY_PATCHED
                write (123,'(A)',advance='no') real2str(self%shifts_patches_for_fit(3,1,i,j))
                if (j < NY_PATCHED) write (123,'(A)',advance='no') ', '
            end do
            if (i < NX_PATCHED) write (123,*) '; ...'
        end do
        write (123,*) '];'
        close(123)
    end subroutine write_shifts_for_fit

    subroutine allocate_fields( self )
        class(motion_patched), intent(inout) :: self
        integer :: alloc_stat
        logical :: do_allocate
        do_allocate = .true.
        if (allocated(self%shifts_patches)) then
            if (size(self%shifts_patches, dim=1) < self%nframes) then
                do_allocate = .false.
            else
                call self%deallocate_fields()
            end if
        end if
        if (do_allocate) then
            allocate(self%shifts_patches   (3, self%nframes, NX_PATCHED, NY_PATCHED),&
                self%shifts_patches_for_fit(3, self%nframes, NX_PATCHED, NY_PATCHED),&
                self%frame_patches   (    self%nframes, NX_PATCHED, NY_PATCHED),&
                self%ref_patches     (    self%nframes, NX_PATCHED, NY_PATCHED),&
                self%patches_imgs    (    self%nframes, NX_PATCHED, NY_PATCHED),&
                self%shsearch_patches(    self%nframes, NX_PATCHED, NY_PATCHED),&
                stat=alloc_stat )
            if (alloc_stat /= 0) call allocchk('allocate_fields 1; simple_motion_patched')
        end if
    end subroutine allocate_fields

    subroutine deallocate_fields( self )
        class(motion_patched), intent(inout) :: self
        integer :: iframe, i, j
        write (*,*) 'deallocate_fields ' ; call flush(6)
        if (allocated(self%shifts_patches)) deallocate(self%shifts_patches)
        if (allocated(self%shifts_patches_for_fit)) deallocate(self%shifts_patches_for_fit)
        if (allocated(self%frame_patches)) then
            do iframe = 1, self%nframes
                do j = 1, NY_PATCHED
                    do i = 1, NX_PATCHED
                        call self%frame_patches(iframe,i,j)%kill()
                    end do
                end do
            end do
            deallocate(self%frame_patches)
        end if
        if (allocated(self%ref_patches)) then
            do iframe = 1, self%nframes
                do j = 1, NY_PATCHED
                    do i = 1, NX_PATCHED
                        call self%ref_patches(iframe,i,j)%kill()
                    end do
                end do
            end do
            deallocate(self%ref_patches)
        end if
        if (allocated(self%patches_imgs)) then
            do iframe = 1, self%nframes
                do j = 1, NY_PATCHED
                    do i = 1, NX_PATCHED
                        call self%patches_imgs(iframe,i,j)%kill()
                    end do
                end do
            end do
            deallocate(self%patches_imgs)
        end if
        if (allocated(self%shsearch_patches)) then
            do iframe = 1, self%nframes
                do j = 1, NY_PATCHED
                    do i = 1, NX_PATCHED
                        call self%shsearch_patches(iframe,i,j)%kill()
                    end do
                end do
            end do
            deallocate(self%shsearch_patches)
        end if
    end subroutine deallocate_fields

    subroutine set_size_frames_ref( self )
        class(motion_patched), intent(inout) :: self
        integer :: ldim_nooverlap(2)
        integer :: i, j
        self%ldim_patch(1) = round2even(real(self%ldim(1)) / real(NX_PATCHED)) + 2 * X_OVERLAP
        self%ldim_patch(2) = round2even(real(self%ldim(2)) / real(NY_PATCHED)) + 2 * Y_OVERLAP
        self%ldim_patch(3) = 1
        ldim_nooverlap(1) = round2even(real(self%ldim(1)) / real(NX_PATCHED))
        ldim_nooverlap(2) = round2even(real(self%ldim(2)) / real(NY_PATCHED))
        do j = 1, NY_PATCHED
            do i = 1, NX_PATCHED
                self%lims_patches(i,j,1,1) = (i-1) * ldim_nooverlap(1) - X_OVERLAP + 1
                self%lims_patches(i,j,1,2) =  i    * ldim_nooverlap(1) + X_OVERLAP
                self%lims_patches(i,j,2,1) = (j-1) * ldim_nooverlap(2) - Y_OVERLAP + 1
                self%lims_patches(i,j,2,2) =  j    * ldim_nooverlap(2) + Y_OVERLAP
            end do
        end do
    end subroutine set_size_frames_ref

    subroutine set_patches( self, stack, patches_ftexp, abc )
        class(motion_patched),          intent(inout) :: self
        type(image),       allocatable, intent(inout) :: stack(:)
        type(ft_expanded), allocatable, intent(inout) :: patches_ftexp(:,:,:)
        integer, intent(in) :: abc
        integer :: i, j, iframe, k, l, kk, ll
        integer :: ip, jp           ! ip, jp: i_patch, j_patch
        integer :: lims_patch(2,2)
        type(rmat_ptr_type) :: rmat_ptrs(self%nframes)
        real, pointer :: rmat_patch(:,:,:)
        do iframe=1,self%nframes
            do j = 1, NY_PATCHED
                do i = 1, NX_PATCHED
                    call self%patches_imgs(iframe,i,j)%new(self%ldim_patch, params_glob%smpd)
                end do
            end do
        end do
        do iframe=1,self%nframes
            call stack(iframe)%get_rmat_ptr(rmat_ptrs(iframe)%rmat_ptr)
        end do
        !$omp parallel do collapse(3) default(shared) private(iframe,j,i,lims_patch,rmat_patch,k,l,kk,ll,ip,jp) proc_bind(close) schedule(static)
        do iframe=1,self%nframes
            do j = 1, NY_PATCHED
                do i = 1, NX_PATCHED
                    call self%patches_imgs(iframe,i,j)%get_rmat_ptr(rmat_patch)
                    lims_patch(:,:) = self%lims_patches(i,j,:,:)
                    do k = lims_patch(1,1), lims_patch(1,2)
                        kk = k
                        if (kk < 1) then
                            kk = kk + self%ldim(1)
                        else if (kk > self%ldim(1)) then
                            kk = kk - self%ldim(1)
                        end if
                        ip = k - lims_patch(1,1) + 1
                        do l = lims_patch(2,1), lims_patch(2,2)
                            ll = l
                            if (ll < 1) then
                                ll = ll + self%ldim(2)
                            else if (ll > self%ldim(2)) then
                                ll = ll - self%ldim(2)
                            end if
                            jp = l - lims_patch(2,1) + 1
                            ! now copy the value
                            rmat_patch(ip,jp,1) = rmat_ptrs(iframe)%rmat_ptr(kk,ll,1)
                        end do
                    end do
                    call patches_ftexp(iframe,i,j)%extract_img(self%patches_imgs(iframe,i,j), self%hp, self%lp)
                end do
            end do
        end do
        !$omp end parallel do
    end subroutine set_patches

    subroutine det_shifts( self )
        class(motion_patched), intent(inout) :: self
        integer :: iframe, i, j
        real :: interpolated_xshift0(NX_PATCHED,NY_PATCHED), interpolated_yshift0(NX_PATCHED,NY_PATCHED)
        self%shifts_patches = 0.
        !$omp parallel do collapse(3) default(shared) private(iframe,j,i) proc_bind(close) schedule(static)
        do iframe = 1, self%nframes
            do i = 1, NX_PATCHED
                do j = 1, NY_PATCHED
                    call self%shsearch_patches(iframe,i,j)%new(self%ref_patches(iframe,i,j),self%frame_patches(iframe,i,j),&
                        self%trs, self%motion_correct_ftol, self%motion_correct_gtol)
                    self%shifts_patches(:,iframe,i,j) = self%shsearch_patches(iframe,i,j)%minimize()
                end do
            end do
        end do
        !$omp end parallel do
        ! Set te first shift to 0.
        do iframe = self%nframes, 1, -1
            self%shifts_patches(:,iframe,:,:) = self%shifts_patches(:,iframe,:,:)-self%shifts_patches(:,1,:,:)
        enddo
        interpolated_xshift0(:,:) = -0.5*self%shifts_patches(2,2,:,:)
        interpolated_yshift0(:,:) = -0.5*self%shifts_patches(3,2,:,:)
        do iframe = 1, self%nframes
            self%shifts_patches_for_fit(2,iframe,:,:) = self%shifts_patches(2,iframe,:,:)  - interpolated_xshift0(:,:)
            self%shifts_patches_for_fit(3,iframe,:,:) = self%shifts_patches(3,iframe,:,:)  - interpolated_yshift0(:,:)
        enddo
    end subroutine det_shifts

    subroutine motion_patched_new( self, motion_correct_ftol, motion_correct_gtol, trs )
        class(motion_patched), intent(inout) :: self
        real, optional,        intent(in)    :: motion_correct_ftol, motion_correct_gtol
        real, optional,        intent(in)    :: trs
        call self%kill()
        if (present(motion_correct_ftol)) then
            self%motion_correct_ftol = motion_correct_ftol
        else
            self%motion_correct_ftol = TOL
        end if
        if (present(motion_correct_gtol)) then
            self%motion_correct_gtol = motion_correct_gtol
        else
            self%motion_correct_gtol = TOL
        end if
        if (present(trs)) then
            self%trs = trs
        else
            self%trs = TRS_DEFAULT
        end if
        self%existence = .true.
    end subroutine motion_patched_new

    subroutine motion_patched_correct( self, hp, lp, references, frames, frames_output, shift_fname )
        class(motion_patched),         intent(inout) :: self
        real,                          intent(in)    :: hp, lp
        type(image),      allocatable, intent(inout) :: references(:)
        type(image),      allocatable, intent(inout) :: frames(:)
        type(image),      allocatable, intent(inout) :: frames_output(:)
        character(len=:), allocatable, intent(in)    :: shift_fname
        integer :: ldim_frames(3)
        integer :: i
        self%hp = hp
        self%lp = lp
        self%shift_fname = shift_fname // C_NULL_CHAR
        self%nframes = size(frames,dim=1)
        self%ldim   = references(1)%get_ldim()
        if (DUMP_STUFF) then
            write (*,*) 'ldim(1:2)=', self%ldim(1:2)
            write (*,*) 'nframes=', self%nframes
            do i = 1, self%nframes
                call frames(i)%write('frame_'//trim(int2str(i))//'.mrc')
            end do
        end if
        do i = 1,self%nframes
            ldim_frames = frames(i)%get_ldim()
            if (any(ldim_frames(1:2) /= self%ldim(1:2))) then
                THROW_HARD('error in motion_patched_correct: frame dimensions do not match reference dimension; simple_motion_patched')
            end if
        end do
        call self%allocate_fields()
        call self%set_size_frames_ref()
        ! divide the reference into patches
        call self%set_patches(references, self%ref_patches  ,1)
        call self%set_patches(frames,     self%frame_patches,2)
        ! determine shifts for patches
        call self%det_shifts()
        ! fit the polynomial model against determined shifts
        call self%fit_polynomial()
        ! apply transformation
        call self%apply_polytransfo(frames, frames_output)
        if (DUMP_STUFF) then
            ! write shifts to file
            call self%write_shifts()
            call self%write_shifts_for_fit()
            write (*,*) 'ldim(1:2)=', self%ldim(1:2)
            write (*,*) 'nframes=', self%nframes
            do i = 1, self%nframes
                call frames(i)%write('frame_again_'//trim(int2str(i))//'.mrc')
            end do
            do i = 1, self%nframes
                call frames(i)%write('frame_out_'//trim(int2str(i))//'.mrc')
            end do
        end if
        ! report visual results
        call self%plot_shifts()
    end subroutine motion_patched_correct

    subroutine motion_patched_kill( self )
        class(motion_patched), intent(inout) :: self
        call self%deallocate_fields()
        self%existence = .false.
    end subroutine motion_patched_kill

end module simple_motion_patched

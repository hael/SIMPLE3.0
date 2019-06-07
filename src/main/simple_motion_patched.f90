! patched-based anisotropic motion correction
module simple_motion_patched
!$ use omp_lib
!$ use omp_lib_kinds
include 'simple_lib.f08'
use simple_parameters,       only: params_glob
use simple_opt_factory,      only: opt_factory
use simple_opt_spec,         only: opt_spec
use simple_optimizer,        only: optimizer
use simple_image,            only: image
use simple_ft_expanded,      only: ft_expanded, ftexp_transfmat_init, ftexp_transfmat_kill
use simple_motion_align_iso, only: motion_align_iso
use CPlot2D_wrapper_module
implicit none
private
public :: motion_patched, PATCH_PDIM
#include "simple_local_flags.inc"

! module global constants
integer, parameter :: NX_PATCHED     = 5    ! number of patches in x-direction
integer, parameter :: NY_PATCHED     = 5    !       "      "       y-direction
real,    parameter :: TOL            = 1e-6 !< tolerance parameter
real,    parameter :: TRS_DEFAULT    = 5.
integer, parameter :: PATCH_PDIM     = 18   ! dimension of fitted polynomial

type :: rmat_ptr_type
    real, pointer :: rmat_ptr(:,:,:)
end type rmat_ptr_type

type :: stack_type
    type(image), allocatable :: stack(:)
end type stack_type

type :: motion_patched
    private
    logical                             :: existence
    type(stack_type),       allocatable :: frame_patches(:,:)
    type(motion_align_iso), allocatable :: align_iso(:,:)
    real,                   allocatable :: shifts_patches(:,:,:,:)
    real,                   allocatable :: shifts_patches_for_fit(:,:,:,:)
    real,                   allocatable :: lp(:,:)
    real,                   allocatable :: global_shifts(:,:)
    real,                   allocatable :: frameweights(:)
    integer,                allocatable :: updateres(:,:)
    character(len=:),       allocatable :: shift_fname
    integer                             :: nframes
    integer                             :: ldim(3)       ! size of entire frame, reference
    integer                             :: ldim_patch(3) ! size of one patch
    integer                             :: lims_patches(NX_PATCHED,NY_PATCHED,2,2) ! corners of the patches
    real                                :: patch_centers(NX_PATCHED,NY_PATCHED,2)
    real                                :: motion_correct_ftol
    real                                :: motion_correct_gtol
    real(dp)                            :: poly_coeffs(PATCH_PDIM,2)  ! coefficients of fitted polynomial
    real                                :: trs
    real, public                        :: hp
    real                                :: resstep
    logical                             :: has_global_shifts
    logical                             :: has_frameweights  = .false.
    logical                             :: fitshifts         = .false.

contains
    procedure, private                  :: allocate_fields
    procedure, private                  :: deallocate_fields
    procedure, private                  :: set_size_frames_ref
    procedure, private                  :: set_patches
    procedure, private                  :: det_shifts
    procedure, private                  :: fit_polynomial
    procedure, private                  :: get_local_shift
    procedure, private                  :: apply_polytransfo
    procedure, private                  :: write_shifts
    procedure, private                  :: write_shifts_for_fit
    procedure, private                  :: write_polynomial
    procedure, private                  :: plot_shifts
    procedure, private                  :: frameweights_callback
    procedure, private                  :: motion_patched_callback
    procedure, private                  :: motion_patchedfit_callback
    procedure, private                  :: pix2polycoords
    procedure, private                  :: get_patched_polyn
    procedure                           :: set_frameweights
    procedure                           :: set_fitshifts
    procedure                           :: new             => motion_patched_new
    procedure                           :: correct         => motion_patched_correct
    procedure                           :: kill            => motion_patched_kill
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
        res =       c( 1) * t      + c( 2) * t2      + c( 3) * t3
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
                    call self%pix2polycoords(real(self%patch_centers(i,j,1),dp), real(self%patch_centers(i,j,2),dp),x(1,idx),x(2,idx))
                    x(3,idx) = real(iframe,dp) - 0.5_dp
                end do
            end do
        end do
        sig = 1.
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
    end subroutine fit_polynomial

    ! write the polynomials to disk for debugging purposes
    subroutine write_polynomial( self, p, name, ind )
        class(motion_patched),    intent(inout) :: self
        real(dp),                 intent(in)    :: p(PATCH_PDIM)
        character(len=*),         intent(in)    :: name
        integer, intent(in) :: ind
        integer :: i, cnt
        logical :: exist
        inquire(file="polynomial.txt", exist=exist)
        if (exist) then
            open(123, file="polynomial.txt", status="old", position="append", action="write")
        else
            open(123, file="polynomial.txt", status="new", action="write")
        end if
        !write (123,*) 'POLYNOMIAL, ' // name
        cnt = (ind-1)*PATCH_PDIM-1
        do i = 1, PATCH_PDIM
            cnt = cnt + 1
            write (123,'(A)') 'c(' // trim(int2str(cnt)) // ')=' // trim(dbl2str(p(i)))
        end do
        close(123)
    end subroutine write_polynomial

    subroutine plot_shifts(self)
        class(motion_patched), intent(inout) :: self
        real, parameter       :: SCALE = 40.
        real                  :: shift_scale
        type(str4arr)         :: title
        type(CPlot2D_type)    :: plot2D
        type(CDataSet_type)   :: dataSetStart, dataSet, dataSetglob        !!!!!! todo: we don't need this
        type(CDataSet_type)   :: fit, obs, obsglob
        type(CDataSet_type)   :: patch_start
        type(CDataPoint_type) :: point2, p_obs, p_fit, point, p_obsglob
        real                  :: xcenter, ycenter
        integer               :: ipx, ipy, iframe, j
        real                  :: loc_shift(2)
        shift_scale = SCALE
        call CPlot2D__new(plot2D, self%shift_fname)
        call CPlot2D__SetXAxisSize(plot2D, 600._c_double)
        call CPlot2D__SetYAxisSize(plot2D, 600._c_double)
        call CPlot2D__SetDrawLegend(plot2D, C_FALSE)
        call CPlot2D__SetFlipY(plot2D, C_TRUE)
        if (self%has_global_shifts) then
            call CDataSet__new(dataSet)
            call CDataSet__SetDrawMarker(dataSet, C_FALSE)
            call CDataSet__SetDatasetColor(dataSet, 0.0_c_double, 0.0_c_double, 1.0_c_double)
            xcenter = real(self%ldim(1))/2.
            ycenter = real(self%ldim(2))/2.
            do j = 1, self%nframes
                call CDataPoint__new2(&
                    real(xcenter + SCALE * self%global_shifts(j, 1), c_double), &
                    real(ycenter + SCALE * self%global_shifts(j, 2), c_double), &
                    point)
                call CDataSet__AddDataPoint(dataSet, point)
                call CDataPoint__delete(point)
            end do
            call CPlot2D__AddDataSet(plot2D, dataset)
            call CDataSet__delete(dataset)
        end if
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
                !call CDataSet__new(obsglob)
                call CDataSet__SetDrawMarker(fit, C_FALSE)
                call CDataSet__SetDatasetColor(fit, 0.0_c_double,0.0_c_double,0.0_c_double)
                call CDataSet__SetDrawMarker(obs, C_FALSE)
                call CDataSet__SetDatasetColor(obs, 0.5_c_double,0.5_c_double,0.5_c_double)
                !call CDataSet__SetDrawMarker(obsglob, C_FALSE)
                !call CDataSet__SetDatasetColor(obsglob, 0.5_c_double,0.5_c_double,0.0_c_double)
                do iframe = 1, self%nframes
                    call CDataPoint__new2(&
                        real(self%patch_centers(ipx, ipy, 1) + &
                        SCALE * self%shifts_patches_for_fit(2, iframe, ipx, ipy), c_double), &
                        real(self%patch_centers(ipx, ipy, 2) + &
                        SCALE * self%shifts_patches_for_fit(3, iframe, ipx, ipy), c_double), &
                        p_obs)
                    call CDataSet__AddDataPoint(obs, p_obs)
                    !call CDataPoint__new2(&
                    !    real(self%patch_centers(ipx, ipy, 1) + &
                    !    SCALE * (self%global_shifts(iframe, 1)+self%shifts_patches_for_fit(2, iframe, ipx, ipy)), c_double), &
                    !    real(self%patch_centers(ipx, ipy, 2) + &
                    !    SCALE * (self%global_shifts(iframe, 2)+self%shifts_patches_for_fit(3, iframe, ipx, ipy)), c_double), p_obsglob)
                    !call CDataSet__AddDataPoint(obsglob, p_obsglob)
                    call self%get_local_shift(iframe, self%patch_centers(ipx, ipy, 1), &
                        self%patch_centers(ipx, ipy, 2), loc_shift)
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
                    !call CDataPoint__delete(p_obsglob)
                end do
                call CPlot2D__AddDataSet(plot2D, obs)
                !call CPlot2D__AddDataSet(plot2D, obsglob)
                call CPlot2D__AddDataSet(plot2D, fit)
                call CPlot2D__AddDataSet(plot2D, patch_start)
                call CDataSet__delete(patch_start)
                call CDataSet__delete(fit)
                call CDataSet__delete(obs)
                !call CDataSet__delete(obsglob)
            end do
        end do
        title%str = 'X (in pixels; trajectory scaled by ' // trim(real2str(SHIFT_SCALE)) // ')' // C_NULL_CHAR
        call CPlot2D__SetXAxisTitle(plot2D, title%str)
        title%str(1:1) = 'Y'
        call CPlot2D__SetYAxisTitle(plot2D, title%str)
        call CPlot2D__OutputPostScriptPlot(plot2D, self%shift_fname)
        call CPlot2D__delete(plot2D)
    end subroutine plot_shifts

    elemental subroutine pix2polycoords( self, xin, yin, x, y )
        class(motion_patched), intent(in)  :: self
        real(dp),              intent(in)  :: xin, yin
        real(dp),              intent(out) :: x, y
        x = (xin-1.d0) / real(self%ldim(1)-1,dp) - 0.5d0
        y = (yin-1.d0) / real(self%ldim(2)-1,dp) - 0.5d0
    end subroutine pix2polycoords

    subroutine get_local_shift( self, iframe, x, y, shift )
        class(motion_patched), intent(inout) :: self
        integer,               intent(in)  :: iframe
        real,                  intent(in)  :: x, y
        real,                  intent(out) :: shift(2)
        real(dp) :: t, xx, yy
        t  = real(iframe-1, dp)
        call self%pix2polycoords(real(x,dp),real(y,dp), xx,yy)
        shift(1) = apply_patch_poly(self%poly_coeffs(:,1), xx,yy,t)
        shift(2) = apply_patch_poly(self%poly_coeffs(:,2), xx,yy,t)
    end subroutine get_local_shift

    subroutine apply_polytransfo( self, frames, frames_output )
        class(motion_patched),    intent(inout) :: self
        type(image), allocatable, intent(inout) :: frames(:)
        type(image), allocatable, intent(inout) :: frames_output(:)
        integer  :: i, j, iframe
        real(dp) :: x, y, t
        real     :: x_trafo, y_trafo
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
                    t = real(iframe - 1,dp)
                    call self%pix2polycoords(real(i,dp),real(j,dp), x,y)
                    x_trafo = real(i-1) - apply_patch_poly(self%poly_coeffs(:,1), x,y,t)
                    y_trafo = real(j-1) - apply_patch_poly(self%poly_coeffs(:,2), x,y,t)
                    x_trafo = x_trafo + 1.
                    y_trafo = y_trafo + 1.
                    rmat_outs(iframe)%rmat_ptr(i,j,1) = interp_bilin(x_trafo, y_trafo, iframe, rmat_ins )
                end do
            end do
        end do
        !$omp end parallel do
    contains

        pure real function interp_bilin( xval, yval, iiframe, rmat_ins2 )
            real,                intent(in)  :: xval, yval
            integer,             intent(in)  :: iiframe
            type(rmat_ptr_type), intent(in) :: rmat_ins2(self%nframes)
            integer  :: x1_h,  x2_h,  y1_h,  y2_h
            real     :: y1, y2, y3, y4, t, u
            logical :: outside
            outside = .false.
            x1_h = floor(xval)
            x2_h = x1_h + 1
            if( x1_h<1 .or. x2_h<1 )then
                x1_h    = 1
                outside = .true.
            endif
            if( x1_h>self%ldim(1) .or. x2_h>self%ldim(1) )then
                x1_h    = self%ldim(1)
                outside = .true.
            endif
            y1_h = floor(yval)
            y2_h = y1_h + 1
            if( y1_h<1 .or. y2_h<1 )then
                y1_h    = 1
                outside = .true.
            endif
            if( y1_h>self%ldim(2) .or. y2_h>self%ldim(2) )then
                y1_h    = self%ldim(2)
                outside = .true.
            endif
            if( outside )then
                interp_bilin = rmat_ins2(iiframe)%rmat_ptr(x1_h, y1_h, 1)
                return
            endif
            y1 = rmat_ins2(iiframe)%rmat_ptr(x1_h, y1_h, 1)
            y2 = rmat_ins2(iiframe)%rmat_ptr(x2_h, y1_h, 1)
            y3 = rmat_ins2(iiframe)%rmat_ptr(x2_h, y2_h, 1)
            y4 = rmat_ins2(iiframe)%rmat_ptr(x1_h, y2_h, 1)
            t   = xval - x1_h
            u   = yval - y1_h
            interp_bilin =  (1. - t) * (1. - u) * y1 + &
                        &t  * (1. - u) * y2 + &
                        &t  *       u  * y3 + &
                        &(1. - t) * u  * y4
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
        integer :: i, j
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
                self%frame_patches(NX_PATCHED, NY_PATCHED), stat=alloc_stat )
            if (alloc_stat /= 0) call allocchk('allocate_fields 1; simple_motion_patched')
            self%shifts_patches         = 0.
            self%shifts_patches_for_fit = 0.
            do i = 1, NX_PATCHED
                do j = 1, NY_PATCHED
                    allocate( self%frame_patches(i, j)%stack(self%nframes), stat=alloc_stat )
                    if (alloc_stat /= 0) call allocchk('allocate_fields 2; simple_motion_patched')
                end do
            end do
        end if
    end subroutine allocate_fields

    subroutine deallocate_fields( self )
        class(motion_patched), intent(inout) :: self
        integer :: iframe, i, j
        if (allocated(self%shifts_patches)) deallocate(self%shifts_patches)
        if (allocated(self%shifts_patches_for_fit)) deallocate(self%shifts_patches_for_fit)
        if (allocated(self%frame_patches)) then
            do j = 1, NY_PATCHED
                do i = 1, NX_PATCHED
                    do iframe = 1, self%nframes
                        call self%frame_patches(i,j)%stack(iframe)%kill()
                    end do
                    deallocate(self%frame_patches(i,j)%stack)
                end do
            end do
            deallocate(self%frame_patches)
        end if
    end subroutine deallocate_fields

    subroutine set_size_frames_ref( self )
        class(motion_patched), intent(inout) :: self
        integer :: i,j
        real    :: cen, dist
        self%ldim_patch(1) = round2even(real(self%ldim(1)) / real(NX_PATCHED))
        self%ldim_patch(2) = round2even(real(self%ldim(2)) / real(NY_PATCHED))
        self%ldim_patch(3) = 1
        ! along X
        ! limits & center first patches
        self%lims_patches(1,:,1,1) = 1
        self%lims_patches(1,:,1,2) = self%ldim_patch(1)
        self%patch_centers(1,:,1)  = sum(self%lims_patches(1,:,1,1:2),dim=2) / 2.
        ! limits & center last patches
        self%lims_patches(NX_PATCHED,:,1,1) = self%ldim(1)-self%ldim_patch(1)+1
        self%lims_patches(NX_PATCHED,:,1,2) = self%ldim(1)
        self%patch_centers(NX_PATCHED,:,1)  = sum(self%lims_patches(NX_PATCHED,:,1,1:2),dim=2) / 2.
        ! adjust other patch centers to be evenly spread
        dist = real(self%patch_centers(NX_PATCHED,1,1)-self%patch_centers(1,1,1)+1) / real(NX_PATCHED-1)
        do i=2,NX_PATCHED-1
            cen = self%patch_centers(1,1,1) + real(i-1)*dist
            self%lims_patches(i,:,1,1) = ceiling(cen) - self%ldim_patch(1)/2
            self%lims_patches(i,:,1,2) = self%lims_patches(i,:,1,1) + self%ldim_patch(1) - 1
            self%patch_centers(i,:,1)  = sum(self%lims_patches(i,:,1,1:2),dim=2) / 2.
        enddo
        ! along Y
        self%lims_patches(:,1,2,1) = 1
        self%lims_patches(:,1,2,2) = self%ldim_patch(2)
        self%patch_centers(:,1,2)  = sum(self%lims_patches(:,1,2,1:2),dim=2) / 2.
        self%lims_patches(:,NY_PATCHED,2,1) = self%ldim(2)-self%ldim_patch(2)+1
        self%lims_patches(:,NY_PATCHED,2,2) = self%ldim(2)
        self%patch_centers(:,NY_PATCHED,2)  = sum(self%lims_patches(:,NY_PATCHED,2,1:2),dim=2) / 2.
        dist = real(self%patch_centers(1,NY_PATCHED,2)-self%patch_centers(1,1,2)+1) / real(NY_PATCHED-1)
        do j=2,NY_PATCHED-1
            cen = self%patch_centers(1,1,2) + real(j-1)*dist
            self%lims_patches(:,j,2,1) = ceiling(cen) - self%ldim_patch(2)/2
            self%lims_patches(:,j,2,2) = self%lims_patches(:,j,2,1) + self%ldim_patch(2) - 1
            self%patch_centers(:,j,2)  = sum(self%lims_patches(:,j,2,1:2),dim=2) /2.
        enddo
    end subroutine set_size_frames_ref

    subroutine set_patches( self, stack )
        class(motion_patched),          intent(inout) :: self
        type(image),       allocatable, intent(inout) :: stack(:)
        real, allocatable :: res(:)
        integer :: i, j, iframe, k, l, kk, ll
        integer :: ip, jp           ! ip, jp: i_patch, j_patch
        integer :: lims_patch(2,2)
        type(rmat_ptr_type) :: rmat_ptrs(self%nframes)
        real, pointer :: rmat_patch(:,:,:)
        ! init
        do j = 1, NY_PATCHED
            do i = 1, NX_PATCHED
                do iframe=1,self%nframes
                    call self%frame_patches(i,j)%stack(iframe)%new(self%ldim_patch, params_glob%smpd)
                end do
            end do
        end do
        ! initialize transfer matrix to correct dimensions
        call ftexp_transfmat_init(self%frame_patches(1,1)%stack(1))
        ! fill patches
        do iframe=1,self%nframes
            call stack(iframe)%get_rmat_ptr(rmat_ptrs(iframe)%rmat_ptr)
        end do
        !$omp parallel do collapse(3) default(shared) private(iframe,j,i,lims_patch,rmat_patch,k,l,kk,ll,ip,jp) proc_bind(close) schedule(static)
        do iframe=1,self%nframes
            do j = 1, NY_PATCHED
                do i = 1, NX_PATCHED
                    call self%frame_patches(i,j)%stack(iframe)%get_rmat_ptr(rmat_patch)
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
                end do
            end do
        end do
        !$omp end parallel do
        ! updates high-pass according to new dimensions
        res = self%frame_patches(1,1)%stack(1)%get_res()
        self%hp = min(self%hp,res(1))
        deallocate(res)
        write(logfhandle,'(A,F6.1)')'>>> PATCH HIGH-PASS: ',self%hp
    end subroutine set_patches

    subroutine det_shifts( self )
        class(motion_patched), target, intent(inout) :: self
        real, allocatable :: opt_shifts(:,:)
        real    :: corr_avg
        integer :: iframe, i, j, alloc_stat
        self%shifts_patches = 0.
        allocate( self%align_iso(NX_PATCHED, NY_PATCHED), stat=alloc_stat )
        if (alloc_stat /= 0) call allocchk('det_shifts 1; simple_motion_patched')
        !$omp parallel do collapse(2) default(shared) private(j,i) proc_bind(close) schedule(static)
        do i = 1, NX_PATCHED
            do j = 1, NY_PATCHED
                call self%align_iso(i,j)%new
                call self%align_iso(i,j)%set_frames(self%frame_patches(i,j)%stack, self%nframes)
                if( self%has_frameweights )then
                    call self%align_iso(i,j)%set_frameweights_callback(frameweights_callback_wrapper)
                end if
                call self%align_iso(i,j)%set_mitsref(50)
                call self%align_iso(i,j)%set_smallshift(1.)
                call self%align_iso(i,j)%set_rand_init_shifts(.true.)
                call self%align_iso(i,j)%set_hp_lp(self%hp, self%lp(i,j))
                call self%align_iso(i,j)%set_trs(self%trs)
                call self%align_iso(i,j)%set_ftol_gtol(TOL, TOL)
                call self%align_iso(i,j)%set_shsrch_tol(TOL)
                call self%align_iso(i,j)%set_maxits(100)
                call self%align_iso(i,j)%set_coords(i,j)
                call self%align_iso(i,j)%set_fitshifts(self%fitshifts)
                call self%align_iso(i,j)%set_callback(motion_patched_callback_wrapper)
                call self%align_iso(i,j)%align(self)
            end do
        end do
        !$omp end parallel do
        corr_avg = 0.
        do i = 1, NX_PATCHED
            do j = 1, NY_PATCHED
                corr_avg = corr_avg + self%align_iso(i,j)%get_corr()
            enddo
        enddo
        corr_avg = corr_avg / real(NX_PATCHED*NY_PATCHED)
        write(logfhandle,'(A,F6.3)')'>>> AVERAGE PATCH & FRAMES CORRELATION: ', corr_avg
        ! Set the first shift to 0.
        do i = 1, NX_PATCHED
            do j = 1, NY_PATCHED
                call self%align_iso(i,j)%get_opt_shifts(opt_shifts)
                do iframe = 1, self%nframes
                    self%shifts_patches(2:3,iframe,i,j) = opt_shifts(iframe, 1:2)
                end do
            end do
        end do
        do iframe = self%nframes, 1, -1
            self%shifts_patches(:,iframe,:,:) = self%shifts_patches(:,iframe,:,:)-self%shifts_patches(:,1,:,:)
        enddo
        do iframe = 1, self%nframes
            self%shifts_patches_for_fit(2,iframe,:,:) = self%shifts_patches(2,iframe,:,:) + 0.5*self%shifts_patches(2,1,:,:)
            self%shifts_patches_for_fit(3,iframe,:,:) = self%shifts_patches(3,iframe,:,:) + 0.5*self%shifts_patches(3,1,:,:)
        enddo
        ! cleanup
        do i = 1, NX_PATCHED
            do j = 1, NY_PATCHED
                call self%align_iso(i,j)%kill
            end do
        end do
        deallocate(self%align_iso)
    end subroutine det_shifts

    subroutine get_patched_polyn( self, patched_polyn )
        class(motion_patched), intent(inout) :: self
        real(dp), allocatable, intent(out)   :: patched_polyn(:)
        allocate( patched_polyn(2*PATCH_PDIM), source=0._dp )
        patched_polyn(           1:  PATCH_PDIM) = self%poly_coeffs(1:PATCH_PDIM, 1)
        patched_polyn(PATCH_PDIM+1:2*PATCH_PDIM) = self%poly_coeffs(1:PATCH_PDIM, 2)
    end subroutine get_patched_polyn

    subroutine set_frameweights( self, frameweights )
        class(motion_patched), intent(inout) :: self
        real, allocatable, intent(in) :: frameweights(:)
        integer :: nlen
        nlen = size(frameweights)
        if (allocated(self%frameweights)) deallocate(self%frameweights)
        allocate(self%frameweights(nlen), source=frameweights)
        self%has_frameweights = .true.
    end subroutine set_frameweights

    subroutine set_fitshifts( self, fitshifts )
        class(motion_patched), intent(inout) :: self
        logical,                  intent(in) :: fitshifts
        self%fitshifts = fitshifts
    end subroutine set_fitshifts

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
        allocate(self%lp(NX_PATCHED,NY_PATCHED),&
            &self%updateres(NX_PATCHED,NY_PATCHED))
        self%updateres = 0
        self%lp      = -1.
        self%hp      = -1.
        self%resstep = -1.
    end subroutine motion_patched_new

    subroutine motion_patched_correct( self, hp, resstep, frames, frames_output, shift_fname, &
        global_shifts, patched_polyn )
        class(motion_patched),           intent(inout) :: self
        real,                            intent(in)    :: hp, resstep
        type(image),        allocatable, intent(inout) :: frames(:)
        type(image),        allocatable, intent(inout) :: frames_output(:)
        character(len=:),   allocatable, intent(in)    :: shift_fname
        real,     optional, allocatable, intent(in)    :: global_shifts(:,:)
        real(dp), optional, allocatable, intent(out)   :: patched_polyn(:)
        integer :: ldim_frames(3)
        integer :: i
        ! prep
        self%hp          = hp
        self%lp          = params_glob%lpstart
        self%resstep     = resstep
        self%updateres   = 0
        self%shift_fname = shift_fname // C_NULL_CHAR
        if (allocated(self%global_shifts)) deallocate(self%global_shifts)
        if (present(global_shifts)) then
            allocate(self%global_shifts(size(global_shifts, 1), size(global_shifts, 2)))
            self%global_shifts = global_shifts
            self%has_global_shifts = .true.
        else
            self%has_global_shifts = .false.
        end if
        self%nframes = size(frames,dim=1)
        self%ldim   = frames(1)%get_ldim()
        do i = 1,self%nframes
            ldim_frames = frames(i)%get_ldim()
            if (any(ldim_frames(1:2) /= self%ldim(1:2))) then
                THROW_HARD('error in motion_patched_correct: frame dimensions do not match reference dimension; simple_motion_patched')
            end if
        end do
        call self%allocate_fields()
        call self%set_size_frames_ref()
        ! divide the reference into patches & updates high-pass accordingly
        call self%set_patches(frames)
        ! determine shifts for patches
        call self%det_shifts()
        ! fit the polynomial model against determined shifts
        call self%fit_polynomial()
        ! apply transformation
        call self%apply_polytransfo(frames, frames_output)
        ! report visual results
        call self%plot_shifts()
        ! output polynomial
        if ( present(patched_polyn) ) call self%get_patched_polyn(patched_polyn)
    end subroutine motion_patched_correct

    subroutine motion_patched_kill( self )
        class(motion_patched), intent(inout) :: self
        call self%deallocate_fields()
        if (allocated(self%frameweights)) deallocate(self%frameweights)
        if (allocated(self%updateres)) deallocate(self%updateres)
        if (allocated(self%lp)) deallocate(self%lp)
        self%has_frameweights = .false.
        self%existence = .false.
        call ftexp_transfmat_kill
    end subroutine motion_patched_kill

    ! callback with correlation criterion only
    subroutine motion_patchedfit_callback(self, align_iso, converged)
        class(motion_patched),   intent(inout) :: self
        class(motion_align_iso), intent(inout) :: align_iso
        logical,                 intent(out)   :: converged
        integer :: i, j
        integer :: iter
        real    :: corrfrac
        logical :: didupdateres
        call align_iso%get_coords(i, j)
        corrfrac      = align_iso%get_corrfrac()
        iter          = align_iso%get_iter()
        didupdateres  = .false.
        select case(self%updateres(i,j))
        case(0)
            call update_res( 0.99, self%updateres(i,j) )
        case(1)
            call update_res( 0.995, self%updateres(i,j) )
        case(2)
            call update_res( 0.999, self%updateres(i,j) )
        case DEFAULT
            ! nothing to do
        end select
        if( self%updateres(i,j) > 2 .and. .not. didupdateres )then ! at least one iteration with new lim
            if( iter > 10 .and. corrfrac > 0.9999 )  converged = .true.
        else
            converged = .false.
        end if

    contains
        subroutine update_res( thres_corrfrac, which_update )
            real,    intent(in) :: thres_corrfrac
            integer, intent(in) :: which_update
            if( corrfrac > thres_corrfrac .and. self%updateres(i,j) == which_update )then
                self%lp(i,j) = self%lp(i,j) - self%resstep
                call align_iso%set_hp_lp(self%hp, self%lp(i,j))
                write(logfhandle,'(A,I2,A,I2,A,F8.3)')'>>> LOW-PASS LIMIT ',i,'-',j,' UPDATED TO: ', self%lp(i,j)
                ! need to indicate that we updated resolution limit
                self%updateres(i,j)  = self%updateres(i,j) + 1
                ! indicate that reslim was updated
                didupdateres = .true.
            endif
        end subroutine update_res
    end subroutine motion_patchedfit_callback

    !>  callback with correlation & # of improving frames
    subroutine motion_patched_callback(self, align_iso, converged)
        class(motion_patched),   intent(inout) :: self
        class(motion_align_iso), intent(inout) :: align_iso
        logical,                 intent(out)   :: converged
        integer :: i, j
        integer :: nimproved, iter
        real    :: corrfrac, frac_improved
        logical :: didupdateres
        call align_iso%get_coords(i, j)
        corrfrac      = align_iso%get_corrfrac()
        frac_improved = align_iso%get_frac_improved()
        nimproved     = align_iso%get_nimproved()
        iter          = align_iso%get_iter()
        didupdateres  = .false.
        select case(self%updateres(i,j))
        case(0)
            call update_res( 0.96, 40., self%updateres(i,j) )
        case(1)
            call update_res( 0.97, 30., self%updateres(i,j) )
        case(2)
            call update_res( 0.98, 20., self%updateres(i,j) )
        case DEFAULT
            ! nothing to do
        end select
        if( self%updateres(i,j) > 2 .and. .not. didupdateres )then ! at least one iteration with new lim
            if( nimproved == 0 .and. iter > 2 )     converged = .true.
            if( iter > 10 .and. corrfrac > 0.9999 )  converged = .true.
        else
            converged = .false.
        end if

    contains

        subroutine update_res( thres_corrfrac, thres_frac_improved, which_update )
            real,    intent(in) :: thres_corrfrac, thres_frac_improved
            integer, intent(in) :: which_update
            if( corrfrac > thres_corrfrac .and. frac_improved <= thres_frac_improved&
                .and. self%updateres(i,j) == which_update )then
                self%lp(i,j) = self%lp(i,j) - self%resstep
                call align_iso%set_hp_lp(self%hp, self%lp(i,j))
                write(logfhandle,'(a,1x,f7.4)') '>>> LOW-PASS LIMIT UPDATED TO:', self%lp(i,j)
                ! need to indicate that we updated resolution limit
                self%updateres(i,j)  = self%updateres(i,j) + 1
                ! indicate that reslim was updated
                didupdateres = .true.
            endif
        end subroutine update_res

    end subroutine motion_patched_callback

    subroutine motion_patched_callback_wrapper(aptr, align_iso, converged)
        class(*),                intent(inout) :: aptr
        class(motion_align_iso), intent(inout) :: align_iso
        logical,                 intent(out)   :: converged
        select type(aptr)
        class is (motion_patched)
            if( aptr%fitshifts )then
                call aptr%motion_patchedfit_callback(align_iso, converged)
            else
                call aptr%motion_patched_callback(align_iso, converged)
            endif
        class default
            THROW_HARD('error in motion_patched_callback_wrapper: unknown type; simple_motion_patched')
        end select
    end subroutine motion_patched_callback_wrapper

    subroutine frameweights_callback( self, align_iso )
        class(motion_patched),   intent(inout) :: self
        class(motion_align_iso), intent(inout) :: align_iso
        if (self%has_frameweights) then
            call align_iso%set_weights(self%frameweights)
        end if
    end subroutine frameweights_callback

    subroutine frameweights_callback_wrapper( aptr, align_iso )
        class(*),                intent(inout) :: aptr
        class(motion_align_iso), intent(inout) :: align_iso
        select type(aptr)
        class is (motion_patched)
            call aptr%frameweights_callback(align_iso)
        class default
            THROW_HARD('error in frameweights_callback_wrapper: unknown type; simple_motion_patched')
        end select
    end subroutine frameweights_callback_wrapper

end module simple_motion_patched

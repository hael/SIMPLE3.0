module simple_motion_align_hybrid
!$ use omp_lib
!$ use omp_lib_kinds
include 'simple_lib.f08'
use simple_error
use simple_image,        only: image
use simple_parameters,   only: params_glob
use simple_ft_expanded,  only: ft_expanded
use simple_ftexp_shsrch, only: ftexp_shsrch
implicit none
public :: motion_align_hybrid
private
#include "simple_local_flags.inc"

real,    parameter :: SMALLSHIFT    = 1.
real,    parameter :: SRCH_TOL      = 1.e-6
integer, parameter :: MINITS_DCORR  = 5, MAXITS_DCORR  = 15
integer, parameter :: MINITS_CORR   = 2, MAXITS_CORR   = 5
integer, parameter :: POLYDIM       = 4
integer, parameter :: NRESUPDATES   = 3

type :: motion_align_hybrid
    private
    type(image),           pointer :: frames_orig(:)                    !< pointer to stack of frames
    type(image),       allocatable :: frames(:)                         !< cropped frames
    type(image),       allocatable :: frames_sh(:)                      !< shifted cropped frames
    type(image)                    :: reference                         !< reference image
    real,              allocatable :: weights(:,:)                      !< weight matrix (b-factor*band-pass)
    type(ft_expanded), allocatable :: frames_ftexp(:)                   !< ft expanded of frames
    type(ft_expanded), allocatable :: frames_ftexp_sh(:)                !< ft expanded of shifted frames
    type(ft_expanded), allocatable :: references_ftexp(:)               !< ft expanded of references
    real,              allocatable :: shifts_toplot(:,:)                !< for plotting
    real,              allocatable :: opt_shifts(:,:)                   !< shifts identified
    real,              allocatable :: frameweights(:)                   !< array of frameweights
    real,              allocatable :: corrs(:)                          !< per-frame correlations
    real(dp)                       :: polyx(POLYDIM), polyy(POLYDIM)    !< polynomial coefficients
    real                           :: ftol=1.e-6,  gtol=1.e-6           !< tolerance parameters for minimizer
    real                           :: hp=-1.,      lp=-1.               !< high/low pass value
    real                           :: lpstart=-1., lpstop=-1.           !< resolutions limits
    real                           :: bfactor = -1.                     !< b-factor for alignment weights
    real                           :: resstep        = 0.               !< resolution step
    real                           :: corr           = -1.              !< correlation
    real                           :: shsrch_tol     = SRCH_TOL         !< tolerance parameter for continuous srch update
    real                           :: smpd = 0.                         !< sampling distance
    real                           :: scale_factor   = 1.               !< local frame scaling
    real                           :: trs            = 10.              !< half correlation disrete search bound
    integer                        :: ldim(3) = 0, ldim_sc(3) = 0       !< frame dimensions
    integer                        :: maxits_dcorr   = MAXITS_DCORR     !< maximum number of iterations for discrete search
    integer                        :: maxits_corr    = MAXITS_CORR      !< maximum number of iterations for continuous search
    integer                        :: nframes        = 0                !< number of frames
    integer                        :: fixed_frame    = 1                !< fixed (non-shifted) frame
    integer                        :: px=0 , py=0                       !< patch x/y id
    integer                        :: lp_updates       = 1              !< # of resolution updates performed [0;3]
    logical                        :: l_bfac           = .false.        !< whether to use b-factor weights
    logical                        :: group_frames     = .false.        !< whether to group frames
    logical                        :: fitshifts        = .false.        ! whether to perform iterative incremental shifts fitting
    logical                        :: rand_init_shifts = .false.        !< randomize initial condition?
    logical                        :: existence        = .false.

contains
    ! Constructor
    procedure          :: new
    ! Frames & memory management
    procedure, private :: init_images
    procedure, private :: dealloc_images
    procedure, private :: init_ftexps
    procedure, private :: dealloc_ftexps
    ! Doers
    procedure, private :: calc_corr2ref
    procedure, private :: calc_shifts
    procedure, private :: shift_frames_gen_ref
    procedure          :: align
    procedure, private :: align_dcorr
    procedure, private :: align_corr
    procedure, private :: shift_wsum_and_calc_corrs
    procedure, private :: gen_weights
    procedure, private :: gen_frames_group
    procedure, private :: calc_group_weight
    procedure, private :: recenter_shifts
    procedure, private :: calc_rmsd
    ! Trajectory fitting related
    procedure, private :: fit_polynomial
    procedure, private :: polynomial2shift
    ! Getters & setters
    procedure          :: set_shsrch_tol
    procedure          :: set_reslims
    procedure          :: set_trs
    procedure          :: set_weights
    procedure          :: get_weights
    procedure          :: set_rand_init_shifts
    procedure          :: get_corr
    procedure          :: get_corrs
    procedure          :: get_opt_shifts
    procedure          :: get_shifts_toplot
    procedure          :: set_fixed_frame
    procedure          :: set_fitshifts
    procedure          :: set_coords
    procedure          :: get_coords
    procedure          :: is_fitshifts
    procedure          :: set_bfactor
    procedure          :: set_group_frames
    ! Destructor
    procedure          :: kill
end type motion_align_hybrid

contains

    subroutine new( self, frames_ptr )
        class(motion_align_hybrid),       intent(inout) :: self
        type(image), allocatable, target, intent(in)    :: frames_ptr(:)
        call self%kill
        self%trs            = params_glob%trs
        self%ftol           = params_glob%motion_correctftol
        self%gtol           = params_glob%motion_correctgtol
        self%fixed_frame    = 1
        self%lp_updates     = 1
        self%maxits_dcorr   = MAXITS_DCORR
        self%maxits_corr    = MAXITS_CORR
        self%shsrch_tol     = SRCH_TOL
        self%bfactor        = -1.
        self%nframes        =  size(frames_ptr, 1)
        if ( self%nframes < 2 ) then
            THROW_HARD('nframes < 2; simple_motion_align_hybrid: align')
        end if
        self%frames_orig => frames_ptr
        self%smpd    = self%frames_orig(1)%get_smpd()
        self%ldim    = self%frames_orig(1)%get_ldim()
        self%hp      = min((real(minval(self%ldim(1:2))) * self%smpd)/4.,2000.)
        self%hp      = min(params_glob%hp, self%hp)
        self%lp      = params_glob%lpstart
        self%lpstart = params_glob%lpstart
        self%lpstop  = params_glob%lpstop
        self%resstep = (self%lpstart-self%lpstop) / real(NRESUPDATES-1)
        allocate(self%frames_sh(self%nframes),self%frames(self%nframes),&
                &self%shifts_toplot(self%nframes,2), self%opt_shifts(self%nframes,2),&
                &self%corrs(self%nframes), self%frameweights(self%nframes), stat=alloc_stat )
        if(alloc_stat.ne.0)call allocchk('new; simple_motion_align_hybrid')
        self%shifts_toplot    = 0.
        self%opt_shifts       = 0.
        self%corrs            = -1.
        self%frameweights     = 1./real(self%nframes)
        self%fitshifts        = .false.
        self%group_frames     = .false.
        self%rand_init_shifts = .false.
        self%l_bfac           = .false.
        self%existence        = .true.
    end subroutine new

    subroutine init_images( self )
        class(motion_align_hybrid), intent(inout) :: self
        real    :: smpd_sc
        integer :: cdim(3), iframe,box,ind,maxldim
        call self%dealloc_images
        ! works out dimensions for Fourier cropping
        maxldim           = maxval(self%ldim(1:2))
        ind               = calc_fourier_index(self%lpstop, maxldim, self%smpd)
        self%scale_factor = min(1., real(2*(ind+3))/real(maxldim))
        box               = round2even(self%scale_factor*real(maxldim))
        self%scale_factor = min(1.,real(box)/real(maxldim))
        smpd_sc           = self%smpd / self%scale_factor
        if( 2.*smpd_sc > self%lpstop )then
            smpd_sc           = self%lpstop/2.
            self%scale_factor = min(1.,self%smpd/smpd_sc)
            box               = round2even(self%scale_factor*real(maxldim))
        endif
        if( self%ldim(1) > self%ldim(2) )then
            self%ldim_sc = [box, round2even(self%scale_factor*real(self%ldim(2))), 1]
        else
            self%ldim_sc = [round2even(self%scale_factor*real(self%ldim(1))), box, 1]
        endif
        self%trs = self%scale_factor*self%trs
        ! allocate & set
        call self%reference%new(self%ldim_sc,self%smpd,wthreads=.false.)
        call self%reference%zero_and_flag_ft
        cdim = self%reference%get_array_shape()
        allocate(self%weights(cdim(1),cdim(2)),self%frames(self%nframes),&
            &self%frames_sh(self%nframes))
        self%weights = 0.
        !$omp parallel do default(shared) private(iframe) proc_bind(close)
        do iframe = 1,self%nframes
            call self%frames_orig(iframe)%fft
            call self%frames(iframe)%new(self%ldim_sc,self%smpd,wthreads=.false.)
            call self%frames_sh(iframe)%new(self%ldim_sc,self%smpd,wthreads=.false.)
            call self%frames(iframe)%zero_and_flag_ft
            call self%frames_sh(iframe)%zero_and_flag_ft
            call self%frames_orig(iframe)%clip(self%frames(iframe))
        enddo
        !$omp end parallel do
    end subroutine init_images

    subroutine dealloc_images( self )
        class(motion_align_hybrid), intent(inout) :: self
        integer :: iframe
        if(allocated(self%frames_sh))then
            do iframe=1,self%nframes
                call self%frames(iframe)%kill
                call self%frames_sh(iframe)%kill
            enddo
            deallocate(self%frames_sh,self%frames)
        endif
        call self%reference%kill
        if( allocated(self%weights) )deallocate(self%weights)
    end subroutine dealloc_images

    subroutine init_ftexps( self )
        class(motion_align_hybrid), intent(inout) :: self
        integer :: iframe
        real    :: w,w1,sumw
        call self%dealloc_ftexps
        allocate(self%frames_ftexp(self%nframes),self%frames_ftexp_sh(self%nframes),self%references_ftexp(self%nframes))
        w1 = self%calc_group_weight()
        !$omp parallel default(shared) private(iframe,sumw,w) proc_bind(close)
        !$omp do schedule(static)
        do iframe=1,self%nframes
            call self%frames_ftexp(iframe)%new(self%frames_orig(iframe), self%hp, self%lp, .true., bfac=self%bfactor)
            call self%references_ftexp(iframe)%new(self%frames_orig(iframe), self%hp, self%lp, .false.)
        end do
        !$omp end do
        !$omp do schedule(static)
        do iframe=1,self%nframes
            call self%frames_ftexp_sh(iframe)%new(self%frames_orig(iframe), self%hp, self%lp, .false.)
            if( .not.self%group_frames ) cycle
            sumw = 1.
            call self%frames_ftexp_sh(iframe)%add(self%frames_ftexp(iframe))
            if( iframe > 1 )then
                w = w1
                if( iframe == self%nframes ) w = 2.*w
                sumw = sumw + w
                call add_shifted_frame(iframe,iframe-1,w)
            endif
            if( iframe < self%nframes )then
                w = w1
                if( iframe == 1 ) w = 2.*w
                sumw = sumw + w
                call add_shifted_frame(iframe,iframe+1,w1)
            endif
            call self%frames_ftexp_sh(iframe)%div(sumw)
            call self%frames_ftexp(iframe)%copy(self%frames_ftexp_sh(iframe))
        enddo
        !$omp end do
        !$omp end parallel
        contains

            subroutine add_shifted_frame(i, j, w)
                integer, intent(in) :: i,j
                real,    intent(in) :: w
                real :: shvec(2)
                if( w < 1.e-8 )return
                shvec = self%opt_shifts(i,:) - self%opt_shifts(j,:)
                call self%frames_ftexp(j)%shift_and_add(-shvec, w, self%frames_ftexp_sh(i))
            end subroutine add_shifted_frame
    end subroutine init_ftexps

    subroutine dealloc_ftexps( self )
        class(motion_align_hybrid), intent(inout) :: self
        integer :: iframe
        if( allocated(self%frames_ftexp) )then
            do iframe=1,self%nframes
                call self%frames_ftexp(iframe)%kill
                call self%frames_ftexp_sh(iframe)%kill
                call self%references_ftexp(iframe)%kill
            end do
            deallocate(self%references_ftexp,self%frames_ftexp_sh,self%frames_ftexp)
        endif
    end subroutine dealloc_ftexps

    ! Alignment routines

    subroutine align( self, ini_shifts, frameweights )
        class(motion_align_hybrid), intent(inout) :: self
        real,             optional, intent(in)    :: ini_shifts(self%nframes,2), frameweights(self%nframes)
        if ( .not. self%existence ) then
            THROW_HARD('not instantiated; simple_motion_align_hybrid: align')
        end if
        if (( self%hp < 0. ) .or. ( self%lp < 0.)) then
            THROW_HARD('hp or lp < 0; simple_motion_align_hybrid: align')
        end if
        write(logfhandle,'(A,2I3)') '>>> PERFORMING OPTIMIZATION FOR PATCH',self%px,self%py
        ! discrete correlation search
        call self%init_images
        call self%align_dcorr( ini_shifts, frameweights )
        call self%dealloc_images
        self%opt_shifts = self%opt_shifts / self%scale_factor
        ! correlation continuous search
        call self%init_ftexps
        call self%align_corr( frameweights )
        call self%dealloc_ftexps
        ! the end
        self%shifts_toplot = self%opt_shifts
    end subroutine align

    ! semi-discrete correlation based alignment
    subroutine align_dcorr( self, ini_shifts, frameweights )
        class(motion_align_hybrid), intent(inout) :: self
        real,             optional, intent(in)    :: ini_shifts(self%nframes,2), frameweights(self%nframes)
        real    :: opt_shifts_prev(self%nframes, 2), rmsd
        integer :: iter, iframe
        logical :: l_calc_frameweights
        ! frameweights
        l_calc_frameweights = .not.present(frameweights)
        self%frameweights   = 1./real(self%nframes)
        if( .not.l_calc_frameweights ) self%frameweights = frameweights
        ! resolution related
        self%lp         = self%lpstart
        self%lp_updates = 1
        ! init shifts & generate groups
        self%opt_shifts = 0.
        call self%gen_frames_group
        if( present(ini_shifts) ) self%opt_shifts = ini_shifts
        if ( self%rand_init_shifts ) then
            ! random initialization
            do iframe = 1, self%nframes
                if( iframe == self%fixed_frame ) cycle
                self%opt_shifts(iframe,1) = self%opt_shifts(iframe,1) + (ran3()-.5)*SMALLSHIFT*self%scale_factor
                self%opt_shifts(iframe,2) = self%opt_shifts(iframe,2) + (ran3()-.5)*SMALLSHIFT*self%scale_factor
            end do
        end if
        ! init weights matrix
        call self%gen_weights
        ! shift frames, generate reference & calculates correlation
        call self%shift_frames_gen_ref
        ! main loop
        do iter=1,self%maxits_dcorr
            opt_shifts_prev = self%opt_shifts
            ! individual optimizations
            !$omp parallel do schedule(static) default(shared) private(iframe) proc_bind(close)
            do iframe = 1,self%nframes
                call self%calc_shifts(iframe)
            end do
            !$omp end parallel do
            ! recenter shifts
            call self%recenter_shifts(self%opt_shifts)
            ! shift frames, generate reference & calculates correlations
            call self%shift_frames_gen_ref
            ! updates weights
            if( l_calc_frameweights ) self%frameweights = corrs2weights(self%corrs, params_glob%wcrit_enum)
            ! convergence
            rmsd = self%calc_rmsd(opt_shifts_prev, self%opt_shifts)
            if( iter > 1 .and. rmsd < 0.5 )then
                self%lp_updates = self%lp_updates+1
                if( self%fitshifts )then
                    ! optional shifts fitting
                    call self%fit_polynomial(self%opt_shifts)
                    do iframe = 1,self%nframes
                        call self%polynomial2shift(iframe, self%opt_shifts(iframe,:))
                    enddo
                    call self%recenter_shifts(self%opt_shifts)
                endif
                if( self%lp_updates > NRESUPDATES .and. iter >= MINITS_DCORR )then
                    self%lp_updates = NRESUPDATES
                    exit
                endif
                ! resolution & weights update
                if( self%group_frames )then
                    call self%gen_frames_group
                    call self%shift_frames_gen_ref
                endif
                self%lp = max(self%lp-self%resstep, params_glob%lpstop)
                call self%gen_weights
            endif
        enddo
    end subroutine align_dcorr

    ! continuous search
    subroutine align_corr( self, frameweights )
        class(motion_align_hybrid), intent(inout) :: self
        real, optional,             intent(in)    :: frameweights(self%nframes)
        type(ftexp_shsrch), allocatable :: ftexp_srch(:)
        real    :: opt_shifts_saved(self%nframes,2), opt_shifts_prev(self%nframes, 2), corrfrac
        real    :: frameweights_saved(self%nframes), cxy(3), rmsd, corr_prev, corr_saved, trs
        integer :: iter, iframe
        logical :: l_calc_frameweights
        ! frameweights
        l_calc_frameweights = .not.present(frameweights)
        if( .not.l_calc_frameweights ) self%frameweights = frameweights
        frameweights_saved = self%frameweights
        ! shift boundaries
        trs = 5.*params_glob%scale
        ! search object allocation
        allocate(ftexp_srch(self%nframes))
        do iframe=1,self%nframes
            call ftexp_srch(iframe)%new(self%references_ftexp(iframe),&
                self%frames_ftexp_sh(iframe),trs, motion_correct_ftol=self%ftol, motion_correct_gtol=self%gtol)
            call ftexp_srch(iframe)%set_shsrch_tol(self%shsrch_tol)
            ftexp_srch(iframe)%ospec%maxits = 100
        end do
        ! generate movie sum for refinement
        opt_shifts_saved = self%opt_shifts
        call self%shift_wsum_and_calc_corrs
        corr_saved = self%corr
        ! main loop
        do iter=1,self%maxits_corr
            opt_shifts_prev = self%opt_shifts
            corr_prev       = self%corr
            ! individual optimizations
            !$omp parallel do schedule(static) default(shared) private(iframe,cxy) proc_bind(close)
            do iframe = 1,self%nframes
                call self%frames_ftexp(iframe)%shift([-self%opt_shifts(iframe,1), -self%opt_shifts(iframe,2)],self%frames_ftexp_sh(iframe))
                cxy = ftexp_srch(iframe)%minimize(self%corrs(iframe))
                self%opt_shifts(iframe,:) = self%opt_shifts(iframe,:) + cxy(2:3)
                self%corrs(iframe) = cxy(1)
            end do
            !$omp end parallel do
            ! recenter shifts
            call self%recenter_shifts(self%opt_shifts)
            ! updates weights
            if( l_calc_frameweights ) self%frameweights = corrs2weights(self%corrs, params_glob%wcrit_enum)
            ! build new reference
            call self%shift_wsum_and_calc_corrs
            ! convergence
            rmsd = self%calc_rmsd(opt_shifts_prev, self%opt_shifts)
            if( self%corr >= corr_saved ) then
                ! save the local optimum
                corr_saved         = self%corr
                frameweights_saved = self%frameweights
                opt_shifts_saved   = self%opt_shifts
            endif
            corrfrac = corr_prev / self%corr
            if( iter >= MINITS_CORR .and. corrfrac > 0.999 .and. rmsd < 0.1 ) exit
        end do
        ! best local optimum
        self%corr          = corr_saved
        self%opt_shifts    = opt_shifts_saved
        self%frameweights  = frameweights_saved
        ! cleanup
        do iframe = 1, self%nframes
            call ftexp_srch(iframe)%kill
        end do
        deallocate(ftexp_srch)
    end subroutine align_corr

    ! shifts frames, generate reference and calculates correlations
    subroutine shift_frames_gen_ref( self )
        class(motion_align_hybrid), intent(inout) :: self
        complex, allocatable :: cmat_sum(:,:,:)
        complex,     pointer :: pcmat(:,:,:)
        integer :: iframe
        cmat_sum = self%reference%get_cmat()
        cmat_sum = cmplx(0.,0.)
        !$omp parallel default(shared) private(iframe,pcmat) proc_bind(close)
        !$omp do schedule(static) reduction(+:cmat_sum)
        do iframe=1,self%nframes
            call self%frames_sh(iframe)%set_cmat(self%frames(iframe))
            call self%frames_sh(iframe)%shift([-self%opt_shifts(iframe,1),-self%opt_shifts(iframe,2),0.])
            call self%frames_sh(iframe)%get_cmat_ptr(pcmat)
            cmat_sum = cmat_sum + pcmat * self%frameweights(iframe)
        enddo
        !$omp end do
        !$omp single
        call self%reference%set_cmat(cmat_sum)
        !$omp end single
        !$omp do schedule(static)
        do iframe = 1,self%nframes
            self%corrs(iframe) = self%calc_corr2ref(self%frames_sh(iframe), self%frameweights(iframe))
        end do
        !$omp end do
        !$omp end parallel
        self%corr = sum(self%corrs) / real(self%nframes)
    end subroutine shift_frames_gen_ref

    ! shifts frames, generate reference and calculates correlations
    subroutine gen_frames_group( self )
        class(motion_align_hybrid), intent(inout) :: self
        real    :: w,w1,sumw
        integer :: iframe
        if( .not.self%group_frames ) return
        w1 = self%calc_group_weight()
        !$omp parallel do default(shared) private(iframe,sumw,w) proc_bind(close) schedule(static)
        do iframe = 1,self%nframes
            sumw = 1.
            call self%frames_orig(iframe)%clip(self%frames(iframe))
            if( iframe > 1 )then
                w = w1
                if( iframe == self%nframes ) w = 2.*w
                sumw = sumw + w
                call add_shifted_weighed_frame(iframe, iframe-1, w)
            endif
            if( iframe < self%nframes )then
                w = w1
                if( iframe == 1 ) w = 2.*w
                sumw = sumw + w
                call add_shifted_weighed_frame(iframe, iframe+1, w)
            endif
            call self%frames(iframe)%div(sumw)
        enddo
        !$omp end parallel do
        contains

            subroutine add_shifted_weighed_frame(i,j,w)
                integer, intent(in) :: i,j
                real,    intent(in) :: w
                real :: dsh(2)
                if( w < 1.e-8 )return
                call self%frames_orig(j)%clip(self%frames_sh(i))
                dsh = self%opt_shifts(i,:) - self%opt_shifts(j,:)
                call self%frames_sh(i)%shift(-[dsh(1),dsh(2),0.])
                call self%frames(i)%add(self%frames_sh(i),w)
            end subroutine add_shifted_weighed_frame
    end subroutine gen_frames_group

    ! band-passed correlation to frame-subtracted reference
    real function calc_corr2ref( self, frame, weight )
        class(motion_align_hybrid), intent(inout) :: self
        class(image),               intent(inout) :: frame
        real,                       intent(in)    :: weight
        complex :: cref, cframe
        real    :: rw,w,num,sumsq_ref,sumsq_frame
        integer :: h,k,nrflims(3,2),phys(3)
        nrflims = self%reference%loop_lims(2)
        num         = 0.
        sumsq_ref   = 0.
        sumsq_frame = 0.
        do h = nrflims(1,1),nrflims(1,2)
            rw = merge(1., 2., h==0) ! redundancy weight
            do k = nrflims(2,1),nrflims(2,2)
                phys = self%reference%comp_addr_phys(h,k,0)
                w    = self%weights(phys(1),phys(2))
                if( w < 1.e-12 ) cycle
                cref   = self%reference%get_cmat_at(phys)
                cframe = frame%get_cmat_at(phys)
                cref   = cref - weight*cframe
                w      = w*rw
                num         = num         + w * real(cref*conjg(cframe))
                sumsq_ref   = sumsq_ref   + w * csq(cref)
                sumsq_frame = sumsq_frame + w * csq(cframe)
            enddo
        enddo
        calc_corr2ref = 0.
        if( sumsq_ref > TINY .and. sumsq_frame > TINY )then
             calc_corr2ref = num / sqrt(sumsq_ref*sumsq_frame)
        endif
    end function calc_corr2ref

    ! identifies interpolated shifts within search range, frame destroyed on exit
    subroutine calc_shifts( self, iframe )
        class(motion_align_hybrid), intent(inout) :: self
        integer,                    intent(inout) :: iframe
        real, pointer :: pcorrs(:,:,:)
        complex  :: cref, cframe
        real(dp) :: sqsum_ref,sqsum_frame
        real     :: dshift(2),alpha,beta,gamma,weight,w,rw
        integer  :: pos(2),center(2),trs,h,k,phys(3),nrflims(3,2)
        weight = self%frameweights(iframe)
        trs    = max(1, min(floor(self%trs),minval(self%ldim_sc(1:2)/2)))
        ! correlations
        sqsum_ref   = 0.d0
        sqsum_frame = 0.d0
        nrflims = self%reference%loop_lims(2)
        do h = nrflims(1,1),nrflims(1,2)
            rw = merge(1., 2., h==0) ! redundancy
            do k = nrflims(2,1),nrflims(2,2)
                phys = self%reference%comp_addr_phys(h,k,0)
                w    = self%weights(phys(1),phys(2))
                if( w < 1.e-12 )then
                    call self%frames_sh(iframe)%set_cmat_at(phys, cmplx(0.,0.))
                    cycle
                endif
                cref   = self%reference%get_cmat_at(phys)
                cframe = self%frames_sh(iframe)%get_cmat_at(phys)
                cref   = cref - weight*cframe
                call self%frames_sh(iframe)%set_cmat_at(phys, w*cref*conjg(cframe))
                sqsum_ref   = sqsum_ref   + real(rw*w*csq(cref),dp)
                sqsum_frame = sqsum_frame + real(rw*w*csq(cframe),dp)
            enddo
        enddo
        if( sqsum_ref<1.d-6 .or. sqsum_frame<1.d-6 )then
            ! most likely corrupted frame
        else
            call self%frames_sh(iframe)%ifft
            call self%frames_sh(iframe)%div(sqrt(real(sqsum_ref*sqsum_frame)))
            ! find peak
            call self%frames_sh(iframe)%get_rmat_ptr(pcorrs)
            center = self%ldim_sc(1:2)/2+1
            pos    = maxloc(pcorrs(center(1)-trs:center(1)+trs, center(2)-trs:center(2)+trs, 1))-trs-1
            dshift = real(pos)
            ! interpolate
            beta  = pcorrs(pos(1)+center(1), pos(2)+center(2), 1)
            alpha = pcorrs(pos(1)+center(1)-1,pos(2)+center(2),1)
            gamma = pcorrs(pos(1)+center(1)+1,pos(2)+center(2),1)
            if( alpha<beta .and. gamma<beta ) dshift(1) = dshift(1) + interp_peak()
            alpha = pcorrs(pos(1)+center(1),pos(2)+center(2)-1,1)
            gamma = pcorrs(pos(1)+center(1),pos(2)+center(2)+1,1)
            if( alpha<beta .and. gamma<beta ) dshift(2) = dshift(2) + interp_peak()
            ! update shift
            self%opt_shifts(iframe,:) = self%opt_shifts(iframe,:) + dshift
        endif
        ! cleanup
        call self%frames_sh(iframe)%zero_and_flag_ft
        contains

            real function interp_peak()
                real :: denom
                interp_peak = 0.
                denom = alpha+gamma-2.*beta
                if( abs(denom) < TINY )return
                interp_peak = 0.5 * (alpha-gamma) / denom
            end function interp_peak
    end subroutine calc_shifts

    ! generates weights and mask matrix
    subroutine gen_weights( self )
        class(motion_align_hybrid), intent(inout) :: self
        integer, parameter :: BPWIDTH = 3
        real    :: w, bfacw, rsh, rhplim, rlplim, width, spafreqsq,spafreqh,spafreqk
        integer :: phys(3),nr_lims(3,2), bphplimsq,hplimsq,bplplimsq,lplimsq, shsq, h,k, hplim,lplim
        self%weights = 0.
        width   = real(BPWIDTH)
        nr_lims = self%reference%loop_lims(2)
        hplim     = max(1,calc_fourier_index(self%hp,minval(self%ldim(1:2)),self%smpd))
        rhplim    = real(hplim)
        hplimsq   = hplim*hplim
        bphplimsq = max(0,hplim+BPWIDTH)**2
        lplim     = calc_fourier_index(self%lp,minval(self%ldim(1:2)),self%smpd)
        rlplim    = real(lplim)
        lplimsq   = lplim*lplim
        bplplimsq = min(minval(nr_lims(1:2,2)),lplim-BPWIDTH)**2
        !$omp parallel do collapse(2) schedule(static) default(shared) proc_bind(close)&
        !$omp private(h,k,shsq,phys,rsh,bfacw,w,spafreqsq,spafreqh,spafreqk)
        do h = nr_lims(1,1),nr_lims(1,2)
            do k = nr_lims(2,1),nr_lims(2,2)
                shsq = h*h+k*k
                if( shsq < hplimsq ) cycle
                if( shsq > lplimsq ) cycle
                if( shsq == 0 )      cycle
                phys = self%reference%comp_addr_phys([h,k,0])
                ! B-factor weight
                spafreqh  = real(h) / real(self%ldim(1)) / self%smpd
                spafreqk  = real(k) / real(self%ldim(2)) / self%smpd
                spafreqsq = spafreqh*spafreqh + spafreqk*spafreqk
                bfacw     = max(0.,exp(-spafreqsq*self%bfactor/4.))
                ! filter weight
                w = 1.
                if( shsq < bphplimsq )then
                    ! high-pass
                    rsh = sqrt(real(shsq))
                    w   = 0.5 * (1.-cos(PI*(rsh-rhplim)/width))
                else if( shsq > bplplimsq )then
                    ! low_pass
                    rsh = sqrt(real(shsq))
                    w   = 0.5*(1.+cos(PI*(rsh-(rlplim-width))/width))
                endif
                self%weights(phys(1),phys(2)) = bfacw*bfacw * w*w
            end do
        end do
        !$omp end parallel do
    end subroutine gen_weights

    ! center shifts with respect to fixed_frame
    subroutine recenter_shifts( self, shifts )
        class(motion_align_hybrid), intent(inout) :: self
        real,                       intent(inout) :: shifts(self%nframes,2)
        integer :: iframe
        do iframe=1,self%nframes
            shifts(iframe,:) = shifts(iframe,:) - shifts(self%fixed_frame,:)
            if( abs(shifts(iframe,1)) < 1.e-6 ) shifts(iframe,1) = 0.
            if( abs(shifts(iframe,2)) < 1.e-6 ) shifts(iframe,2) = 0.
        end do
    end subroutine recenter_shifts

    real function calc_rmsd( self, prev_shifts, shifts )
        class(motion_align_hybrid), intent(in) :: self
        real,                       intent(in) :: prev_shifts(self%nframes,2), shifts(self%nframes,2)
        integer :: iframe
        calc_rmsd = 0.
        do iframe = 1,self%nframes
            calc_rmsd = calc_rmsd + sum((shifts(iframe,:)-prev_shifts(iframe,:))**2.)
        enddo
        calc_rmsd = sqrt(calc_rmsd/real(self%nframes))
    end function calc_rmsd

    real function calc_group_weight( self )
        class(motion_align_hybrid), intent(in)  :: self
        integer :: lp_update
        if( self%px == 0 .and. self%py == 0 )then
            ! iso
            calc_group_weight = 0.0
        else
            ! aniso
            lp_update = min(self%lp_updates,NRESUPDATES)
            calc_group_weight = 0.25*exp(-real(lp_update))
        endif
    end function calc_group_weight

    ! Continuous search routines

    ! shifts frames, generate references, substracts self from references and calculates correlations
    subroutine shift_wsum_and_calc_corrs( self )
        class(motion_align_hybrid), intent(inout) :: self
        complex, allocatable :: cmat_sum(:,:)
        complex,     pointer :: pcmat(:,:)
        integer :: iframe, flims(3,2)
        flims = self%references_ftexp(1)%get_flims()
        allocate(cmat_sum(flims(1,1):flims(1,2),flims(2,1):flims(2,2)),source=cmplx(0.,0.))
        !$omp parallel default(shared) private(iframe,pcmat) proc_bind(close)
        ! accumulate shifted sum
        !$omp do schedule(static) reduction(+:cmat_sum)
        do iframe=1,self%nframes
            call self%frames_ftexp(iframe)%shift([-self%opt_shifts(iframe,1),-self%opt_shifts(iframe,2)],self%frames_ftexp_sh(iframe))
            call self%frames_ftexp_sh(iframe)%get_cmat_ptr(pcmat)
            cmat_sum = cmat_sum + pcmat * self%frameweights(iframe)
        end do
        !$omp end do
        !$omp do schedule(static)
        do iframe=1,self%nframes
            ! set references
            call self%references_ftexp(iframe)%set_cmat(cmat_sum)
            ! subtract frame
            call self%references_ftexp(iframe)%subtr(self%frames_ftexp_sh(iframe),w=self%frameweights(iframe))
            ! calc corr
            self%corrs(iframe) = self%references_ftexp(iframe)%corr(self%frames_ftexp_sh(iframe))
        end do
        !$omp end do
        !$omp end parallel
        self%corr = sum(self%corrs)/real(self%nframes)
        deallocate(cmat_sum)
        nullify(pcmat)
    end subroutine shift_wsum_and_calc_corrs

    ! Getters/setters

    subroutine set_reslims( self, hp, lpstart, lpstop )
        class(motion_align_hybrid), intent(inout) :: self
        real,                       intent(in)    :: hp, lpstart, lpstop
        if (.not. self%existence) then
            THROW_HARD('not instantiated; simple_motion_align_hybrid: set_reslims')
        end if
        if( hp<0. .or. lpstart<0. .or. lpstop<0. .or. lpstop>lpstart .or. hp<lpstart)then
            THROW_HARD('inconsistent resolutions limits; simple_motion_align_hybrid: set_reslims')
        endif
        self%hp      = hp
        self%lpstart = max(2.*self%smpd, lpstart)
        self%lpstop  = max(2.*self%smpd, lpstop)
        self%resstep = (self%lpstart-self%lpstop) / real(NRESUPDATES-1)
        self%lp      = self%lpstart
    end subroutine set_reslims

    subroutine set_trs( self, trs )
        class(motion_align_hybrid), intent(inout) :: self
        real,                    intent(in)    :: trs
        self%trs = trs
    end subroutine set_trs

    subroutine set_weights( self, frameweights )
        class(motion_align_hybrid), intent(inout) :: self
        real, allocatable,          intent(in)    :: frameweights(:)
        if (size(frameweights) /= self%nframes) then
            THROW_HARD('inconsistency; simple_motion_align_hybrid: set_weights')
        end if
        self%frameweights(:) = frameweights(:)
    end subroutine set_weights

    subroutine get_weights( self, frameweights )
        class(motion_align_hybrid), intent(inout) :: self
        real, allocatable,          intent(out)   :: frameweights(:)
        allocate(frameweights(self%nframes), source=self%frameweights)
    end subroutine get_weights

    subroutine set_rand_init_shifts( self, rand_init_shifts )
        class(motion_align_hybrid), intent(inout) :: self
        logical,                    intent(in)    :: rand_init_shifts
        self%rand_init_shifts = rand_init_shifts
    end subroutine set_rand_init_shifts

    real function get_corr( self )
        class(motion_align_hybrid), intent(in) :: self
        get_corr = self%corr
    end function get_corr

    subroutine get_corrs( self, corrs )
        class(motion_align_hybrid), intent(inout) :: self
        real, allocatable,          intent(out)   :: corrs(:)
        allocate( corrs(self%nframes), source=self%corrs )
    end subroutine get_corrs

    subroutine get_opt_shifts( self, opt_shifts )
        class(motion_align_hybrid), intent(inout) :: self
        real, allocatable,          intent(out)   :: opt_shifts(:,:)
        allocate( opt_shifts(self%nframes, 2), source=self%opt_shifts )
    end subroutine get_opt_shifts

    subroutine get_shifts_toplot( self, shifts_toplot )
        class(motion_align_hybrid), intent(inout) :: self
        real, allocatable,          intent(out)   :: shifts_toplot(:,:)
        allocate( shifts_toplot(self%nframes, 2), source=self%shifts_toplot )
    end subroutine get_shifts_toplot

    subroutine set_fixed_frame( self, fixed_frame )
        class(motion_align_hybrid), intent(inout) :: self
        integer,                    intent(in)    :: fixed_frame
        self%fixed_frame = fixed_frame
    end subroutine set_fixed_frame

    subroutine set_fitshifts( self, fitshifts )
        class(motion_align_hybrid), intent(inout) :: self
        logical,                    intent(in)    :: fitshifts
        self%fitshifts = fitshifts
    end subroutine set_fitshifts

    subroutine set_shsrch_tol( self, shsrch_tol )
        class(motion_align_hybrid), intent(inout) :: self
        real, intent(in) :: shsrch_tol
        self%shsrch_tol = shsrch_tol
    end subroutine set_shsrch_tol

    subroutine set_maxits( self, maxits1, maxits2 )
        class(motion_align_hybrid), intent(inout) :: self
        integer,                    intent(in)    :: maxits1,maxits2
        self%maxits_dcorr = maxits1
        self%maxits_corr  = maxits2
    end subroutine set_maxits

    subroutine set_coords( self, x, y )
        class(motion_align_hybrid), intent(inout) :: self
        integer, intent(in) :: x, y
        self%px = x
        self%py = y
    end subroutine set_coords

    subroutine get_coords(self, x, y )
        class(motion_align_hybrid), intent(inout) :: self
        integer, intent(out) :: x, y
        x = self%px
        y = self%py
    end subroutine get_coords

    logical function is_fitshifts( self )
        class(motion_align_hybrid), intent(in) :: self
        is_fitshifts = self%fitshifts
    end function is_fitshifts

    subroutine set_bfactor( self, bfac )
        class(motion_align_hybrid), intent(inout) :: self
        real,                       intent(in)    :: bfac
        self%l_bfac = bfac > 1.e-6
        if( self%l_bfac ) self%bfactor = bfac
    end subroutine set_bfactor

    subroutine set_group_frames( self, group_frames )
        class(motion_align_hybrid), intent(inout) :: self
        logical,                    intent(in)    :: group_frames
        self%group_frames = group_frames
    end subroutine set_group_frames

    ! FITTING RELATED

    ! fit shifts to 2 polynomials
    subroutine fit_polynomial( self, shifts )
        class(motion_align_hybrid), intent(inout) :: self
        real     :: shifts(self%nframes,2)
        real(dp) :: x(self%nframes), y(self%nframes,2), sig(self%nframes)
        real(dp) :: v(POLYDIM,POLYDIM), w(POLYDIM), chisq
        integer  :: iframe
        x      = (/(real(iframe-self%fixed_frame,dp),iframe=1,self%nframes)/)
        y(:,1) = real(shifts(:,1),dp)
        y(:,2) = real(shifts(:,2),dp)
        sig    = 1.d0
        call svdfit(x, y(:,1), sig, self%polyx, v, w, chisq, poly)
        call svdfit(x, y(:,2), sig, self%polyy, v, w, chisq, poly)
    end subroutine fit_polynomial

    ! evaluate fitted shift
    subroutine polynomial2shift( self, t, shvec )
        class(motion_align_hybrid), intent(inout) :: self
        integer,                    intent(in)    :: t
        real,                       intent(out)   :: shvec(2)
        real(dp) :: rt
        rt = real(t-self%fixed_frame,dp)
        shvec(1) = poly2val(self%polyx,rt)
        shvec(2) = poly2val(self%polyy,rt)
        contains
            real function poly2val(p,x)
                real(dp), intent(in) :: p(POLYDIM), x
                poly2val = real(dot_product(p, [1.d0, x, x*x, x*x*x]))
            end function poly2val
    end subroutine polynomial2shift

    function poly(p,n) result( res )
        real(dp), intent(in) :: p
        integer,  intent(in) :: n
        real(dp) :: res(n)
        res = [1.d0, p, p*p, p*p*p]
    end function poly

    ! Destructor
    subroutine kill( self )
        class(motion_align_hybrid), intent(inout) :: self
        nullify(self%frames_orig)
        self%ftol    =1.e-6
        self%gtol    =1.e-6
        self%hp      =-1.
        self%lp      =-1.
        self%lpstart =-1.
        self%lpstop  =-1.
        self%resstep = 0.
        self%bfactor = -1.
        self%smpd    = 0.
        self%ldim    = 0
        self%ldim_sc = 0
        call self%dealloc_images
        call self%dealloc_ftexps
        if( allocated(self%opt_shifts) )    deallocate(self%opt_shifts)
        if( allocated(self%shifts_toplot) ) deallocate(self%shifts_toplot)
        if( allocated(self%corrs) )         deallocate(self%corrs)
        if( allocated(self%frameweights) )  deallocate(self%frameweights)
        self%l_bfac    = .false.
        self%fitshifts = .false.
        self%existence = .false.
    end subroutine kill

end module simple_motion_align_hybrid

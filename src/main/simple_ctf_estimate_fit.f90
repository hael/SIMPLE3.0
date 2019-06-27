module simple_ctf_estimate_fit
include 'simple_lib.f08'
use simple_oris,              only: oris
use simple_image,             only: image
use simple_ctf,               only: ctf
use simple_ctf_estimate_cost, only: ctf_estimate_cost1D,ctf_estimate_cost2D
use simple_starfile_wrappers
use simple_timer
use CPlot2D_wrapper_module

implicit none

public :: ctf_estimate_fit
private
#include "simple_local_flags.inc"

character(len=STDLEN), parameter :: SPECKIND = 'sqrt'
real,                  parameter :: TOL      = 1.e-4, TOL_REFINE = 1.e-6
integer,               parameter :: NPATCH   = 5, IARES = 5, NSTEPS = 200, POLYDIM = 6

type ctf_estimate_fit
    private
    class(image),    pointer  :: micrograph
    type(image), allocatable  :: tiles(:,:)              ! for storing all tiles used to build power spectra
    type(image)               :: pspec_patch(NPATCH,NPATCH)   ! patches micrograph powerspec
    type(image)               :: pspec                   ! all micrograph powerspec
    type(image)               :: pspec_ctf               ! CTF powerspec
    type(image)               :: pspec_ctf_roavg         ! rotationally averaged CTF powerspec
    type(image)               :: pspec_roavg             ! rotationally averaged all micrograph powerspec
    type(ctf)                 :: tfun                    ! transfer function object
    type(ctfparams)           :: parms                   ! for storing ctf parameters
    type(ctfparams)           :: parms_patch(NPATCH,NPATCH) ! for storing patch ctf parameters
    type(ctf_estimate_cost1D) :: ctf_cost1D              ! optimization object for whole micrograph
    type(ctf_estimate_cost2D) :: ctf_cost_patch(NPATCH,NPATCH) ! patch optimization objects
    type(ctf_estimate_cost2D) :: ctf_cost2D              ! 2D optimization object
    real,    allocatable      :: roavg_spec1d(:)         ! 1D rotational average spectrum
    integer, allocatable      :: inds_msk(:,:)           ! indices of pixels within resolution mask
    integer, allocatable      :: tiles_centers(:,:,:)
    logical, allocatable      :: cc_msk(:,:,:)           ! redundant (including Friedel symmetry) resolution mask
    real                      :: polyx(POLYDIM), polyy(POLYDIM)
    integer                   :: centers(NPATCH,NPATCH,2)
    real                      :: smpd         = 0.
    real                      :: df_lims(2)   = [0.3,5.0]! defocus range
    real                      :: df_step      = 0.05     ! defocus step for grid search
    real                      :: astigtol     = 0.05     ! tolerated astigmatism
    real                      :: hp           = 0.       ! high-pass limit
    real                      :: lp           = 0.       ! low-pass limit
    real                      :: cc_fit       = -1.
    real                      :: ctfscore     = -1.
    real                      :: ctfres       = -1.
    integer                   :: box          = 0        ! box size
    integer                   :: ntiles(2)      = 0        ! # tiles along x/y
    integer                   :: npatch       = NPATCH*NPATCH
    integer                   :: flims(3,2)   = 0        ! fourier dimensions
    integer                   :: flims1d(2)   = 0        ! fourier dimensions
    integer                   :: freslims1d(2)= 0        ! fourier dimensions
    integer                   :: ldim_box(3)  = 0        ! box logical dimensions
    integer                   :: ldim_mic(3)  = 0        ! logical dimensions
    integer                   :: npix_msk     = 0        ! # pixels in non-redudant resolution mask
    logical                   :: exists       = .false.
contains
    ! constructor
    procedure          :: new
    procedure          :: read_doc
    ! getters
    procedure          :: get_ccfit
    procedure          :: get_ctfscore
    procedure          :: get_pspec
    procedure          :: get_ctfres
    ! CTF fitting
    procedure, private :: gen_centers
    procedure, private :: gen_resmsk
    procedure, private :: gen_tiles
    procedure          :: fit
    procedure, private :: mic2spec
    procedure, private :: grid_srch
    procedure, private :: refine
    procedure          :: fit_patches
    procedure, private :: mic2spec_patch
    procedure, private :: norm_pspec
    procedure, private :: gen_roavspec1d
    ! scoring, display & output
    procedure          :: plot_parms
    procedure          :: write_doc
    procedure          :: write_star
    procedure, private :: calc_ctfscore
    procedure, private :: calc_ctfres
    procedure, private :: gen_ctf_extrema
    procedure          :: write_diagnostic
    procedure          :: write_diagnostic_patch
    procedure, private :: ctf2pspecimg
    ! polynomial fitting
    procedure, private :: fit_polynomial
    procedure, private :: pix2poly
    procedure          :: pix2polyvals
    ! destructor
    procedure          :: kill
end type ctf_estimate_fit

contains

    subroutine new( self, micrograph, box, parms, dfrange, resrange, astigtol_in)
        class(ctf_estimate_fit), intent(inout) :: self
        class(image), target, intent(inout) :: micrograph       !< all micrograph powerspec
        integer,              intent(in)    :: box
        class(ctfparams),     intent(in)    :: parms
        real,                 intent(in)    :: dfrange(2)  !< defocus range, [30.0,5.0] default
        real,                 intent(in)    :: resrange(2) !< resolution range, [30.0,5.0] default
        real,                 intent(in)    :: astigtol_in !< tolerated astigmatism, 0.05 microns default
        integer :: i,j
        call self%kill
        ! set constants
        self%parms%smpd         = parms%smpd
        self%parms%cs           = parms%Cs
        self%parms%kv           = parms%kV
        self%parms%fraca        = parms%fraca
        self%parms%l_phaseplate = parms%l_phaseplate
        self%micrograph => micrograph
        call self%micrograph%ifft
        self%smpd     = self%micrograph%get_smpd()
        self%ldim_mic = self%micrograph%get_ldim()
        if( resrange(1) > resrange(2) )then
            self%hp = resrange(1)
            self%lp = resrange(2)
        else
            THROW_HARD('invalid resolution range; new')
        endif
        ! power spectrum
        self%box      = box
        self%ldim_box = [self%box,self%box,1]
        call self%pspec%new(self%ldim_box, self%smpd)
        call self%pspec_roavg%new(self%ldim_box, self%smpd)
        call self%pspec_ctf%new(self%ldim_box, self%smpd)
        call self%pspec_ctf_roavg%new(self%ldim_box, self%smpd)
        self%flims      = self%pspec%loop_lims(3) ! redundant
        self%flims1d    = [0,minval(abs(self%flims(1:2,:)))]
        self%freslims1d = [self%pspec%get_find(self%hp),self%pspec%get_find(self%lp)]
        allocate(self%roavg_spec1d(self%flims1d(1):self%flims1d(2)),source=0.)
        ! init patches power spectra images
        call self%gen_centers
        do i=1,NPATCH
            do j=1,NPATCH
                call self%pspec_patch(i,j)%new(self%ldim_box, self%smpd)
            enddo
        enddo
        ! generate windows
        call self%gen_tiles
        ! search related
        if( dfrange(1) < dfrange(2) )then
            self%df_lims = dfrange
            self%df_step = (self%df_lims(2)-self%df_lims(1)) / real(NSTEPS)
        else
            THROW_HARD('invalid defocus range; ctf_estimate_init')
        endif
        self%astigtol = astigtol_in
        ! construct CTF objects
        self%tfun = ctf(self%parms%smpd, self%parms%kV, self%parms%Cs, self%parms%fraca)
        ! generate correlation mask
        call self%gen_resmsk
        ! random seed
        call seed_rnd
        self%exists = .true.
    end subroutine new

    ! constructor for reading and evaluating the polynomials only
    ! with routine pix2polyvals
    subroutine read_doc( self, fname )
        class(ctf_estimate_fit), intent(inout) :: self
        character(len=*),        intent(in)    :: fname
        type(oris)            :: os
        character(len=STDLEN) :: phaseplate
        integer               :: i
        if( nlines(fname) /= 3 ) THROW_HARD('Invalid document; read_doc')
        call os%new(3)
        call os%read(fname)
        self%parms%smpd    = os%get(1,'smpd')
        self%parms%cs      = os%get(1,'cs')
        self%parms%kv      = os%get(1,'kv')
        self%parms%fraca   = os%get(1,'fraca')
        self%parms%dfx     = os%get(1,'dfx')
        self%parms%dfy     = os%get(1,'dfy')
        self%parms%angast  = os%get(1,'angast')
        self%parms%fraca   = os%get(1,'fraca')
        self%parms%phshift = os%get(1,'phshift')
        phaseplate         = os%get_static(1,'phaseplate')
        self%parms%l_phaseplate = trim(phaseplate).eq.'yes'
        ! micrograph dimensions
        self%ldim_mic(1) = nint(os%get(1,'xdim'))
        self%ldim_mic(2) = nint(os%get(1,'ydim'))
        self%ldim_mic(3) = 1
        ! polynomes
        do i = 1,POLYDIM
            self%polyx(i) = os%get(2,'px'//int2str(i))
            self%polyy(i) = os%get(3,'py'//int2str(i))
        enddo
        ! clean
        call os%kill
    end subroutine read_doc

    ! stores tiled windows
    subroutine gen_tiles( self )
        class(ctf_estimate_fit), intent(inout) :: self
        type(image) :: tmp
        integer     :: xind,yind, i,j, firstx,lastx, firsty,lasty
        logical     :: outside
        call tmp%new(self%ldim_box, self%smpd)
        self%ntiles(1) = floor(real(self%ldim_mic(1))/real(self%box/2))
        self%ntiles(2) = floor(real(self%ldim_mic(2))/real(self%box/2))
        allocate(self%tiles(self%ntiles(1),self%ntiles(2)),&
            &self%tiles_centers(self%ntiles(1),self%ntiles(2),2))
        firstx = 1
        lastx  = self%ldim_mic(1)-self%box+1
        firsty = 1
        lasty  = self%ldim_mic(2)-self%box+1
        do i = 1,self%ntiles(1)
            do j = 1,self%ntiles(2)
                xind = firstx + floor(real((i-1)*(lastx-firstx))/real(self%ntiles(1)-1)) - 1
                yind = firsty + floor(real((j-1)*(lasty-firsty))/real(self%ntiles(2)-1)) - 1
                self%tiles_centers(i,j,:) = [xind,yind]+self%box/2+1
                call self%tiles(i,j)%new(self%ldim_box, self%smpd)
                call self%micrograph%window_slim([xind,yind],self%box,tmp,outside)
                call tmp%norm
                call tmp%zero_edgeavg
                call tmp%fft
                call tmp%ft2img(SPECKIND, self%tiles(i,j))
                call tmp%zero_and_unflag_ft
            enddo
        enddo
        call tmp%kill
    end subroutine gen_tiles

    ! GETTERS

    real function get_ctfres( self )
        class(ctf_estimate_fit), intent(inout) :: self
        get_ctfres = self%ctfres
    end function get_ctfres

    real function get_ccfit(self)
        class(ctf_estimate_fit), intent(inout) :: self
        get_ccfit = self%cc_fit
    end function get_ccfit

    real function get_ctfscore(self)
        class(ctf_estimate_fit), intent(inout) :: self
        get_ctfscore = self%ctfscore
    end function get_ctfscore

    subroutine get_pspec(self, pspec_out)
        class(ctf_estimate_fit), intent(inout) :: self
        class(image),            intent(inout) :: pspec_out
        ! self%pspec may have gone through arbitrary normalization
        call pspec_out%copy(self%pspec)
    end subroutine get_pspec

    ! DOERS

    !>  Performs initial grid search & 2D refinement, calculate stats
    subroutine fit( self, parms, spec )
        class(ctf_estimate_fit), intent(inout) :: self
        type(ctfparams),         intent(inout) :: parms
        class(image),  optional, intent(inout) :: spec
        if( present(spec) )then
            ! use provided spectrum
            if( .not. (self%pspec.eqdims.spec) )then
                THROW_HARD('Spectrums have incomnpatible dimensions! fit')
            endif
            call self%pspec%copy(spec)
        else
            ! generate spectrum from tiles
            call self%mic2spec(self%pspec)
        endif
        ! generate & normalize 1D spectrum
        call self%gen_roavspec1d
        ! prepare rotationally averaged power spectra & CTF power spectrum
        call self%pspec%roavg(IARES, self%pspec_roavg, 180)
        ! normalize 2D spectrum with respect to resolution range
        call self%norm_pspec(self%pspec)
        ! 1D grid search with rotational average
        call self%grid_srch
        ! 3/4D refinement of grid solution
        call self%refine
        call self%tfun%apply_convention(self%parms%dfx,self%parms%dfy,self%parms%angast)
        ! calculate CTF scores
        call self%calc_ctfscore
        call self%calc_ctfres
        ! output
        parms%dfx          = self%parms%dfx
        parms%dfy          = self%parms%dfy
        parms%angast       = self%parms%angast
        parms%phshift      = self%parms%phshift
        parms%l_phaseplate = self%parms%l_phaseplate
    end subroutine fit

    !>  Performs patch based refinement
    subroutine fit_patches( self )
        class(ctf_estimate_fit), intent(inout) :: self
        real    :: limits(2,2), cc, cc_sum
        integer :: pi,pj
        limits(1,1) = max(self%df_lims(1),self%parms%dfx-0.5)
        limits(1,2) = min(self%df_lims(2),self%parms%dfx+0.5)
        limits(2,1) = max(self%df_lims(1),self%parms%dfy-0.5)
        limits(2,2) = min(self%df_lims(2),self%parms%dfy+0.5)
        ! generate spectrum
        call self%mic2spec_patch
        ! normalize, minimize, clean
        cc_sum = 0.
        !$omp parallel do collapse(2) default(shared) private(pi,pj,cc) &
        !$omp schedule(static) proc_bind(close) reduction(+:cc_sum)
        do pi=1,NPATCH
            do pj=1,NPATCH
                ! init
                self%parms_patch(pi,pj)%kv      = self%parms%kv
                self%parms_patch(pi,pj)%cs      = self%parms%cs
                self%parms_patch(pi,pj)%fraca   = self%parms%fraca
                self%parms_patch(pi,pj)%smpd    = self%parms%smpd
                self%parms_patch(pi,pj)%dfx     = self%parms%dfx
                self%parms_patch(pi,pj)%dfy     = self%parms%dfy
                self%parms_patch(pi,pj)%angast  = self%parms%angast
                self%parms_patch(pi,pj)%phshift = self%parms%phshift
                self%parms_patch(pi,pj)%l_phaseplate = self%parms%l_phaseplate
                call self%norm_pspec(self%pspec_patch(pi,pj))
                call self%ctf_cost_patch(pi,pj)%init(self%pspec_patch(pi,pj), self%parms_patch(pi,pj),&
                    &self%inds_msk, 2, limits, self%astigtol, TOL_REFINE)
                ! optimization
                call self%ctf_cost_patch(pi,pj)%minimize(self%parms_patch(pi,pj), cc)
                cc_sum = cc_sum + cc
                ! cleanup
                call self%ctf_cost_patch(pi,pj)%kill
            enddo
        enddo
        !$omp end parallel do
        self%cc_fit = cc_sum/real(self%npatch)
        ! polynomial fit
        call self%fit_polynomial
    end subroutine fit_patches

    !> mic2spec calculates the average powerspectrum over a micrograph
    !!          the resulting spectrum has dampened central cross and subtracted background
    subroutine mic2spec( self, spec )
        class(ctf_estimate_fit), intent(inout) :: self
        class(image),            intent(inout) :: spec
        integer     :: i,j,n, ldim(3)
        ldim = spec%get_ldim()
        if( ldim(1)/=self%box .or. ldim(2)/= self%box .or. ldim(3)/=1 )then
            THROW_HARD('Incorrect dimensions; mic2spec')
        endif
        spec = 0.
        do i = 1,self%ntiles(1)
            do j = 1,self%ntiles(2)
                call spec%add(self%tiles(i,j))
            end do
        end do
        n = product(self%ntiles)
        call spec%div(real(n))
        call spec%dampen_pspec_central_cross
        call spec%subtr_backgr(self%hp)
    end subroutine mic2spec

    subroutine gen_centers( self )
        class(ctf_estimate_fit), intent(inout) :: self
        integer :: lims_patches(NPATCH,NPATCH,2,2)
        integer :: i,j, ldim_patch(2)
        real    :: cen, dist
        ldim_patch(1) = round2even(real(self%ldim_mic(1))/real(NPATCH))
        ldim_patch(2) = round2even(real(self%ldim_mic(2))/real(NPATCH))
        ! along X
        ! limits & center first patches
        lims_patches(1,:,1,1) = 1
        lims_patches(1,:,1,2) = ldim_patch(1)
        self%centers(1,:,1)  = sum(lims_patches(1,:,1,1:2),dim=2) / 2
        ! limits & center last patches
        lims_patches(NPATCH,:,1,1) = self%ldim_mic(1)-ldim_patch(1)+1
        lims_patches(NPATCH,:,1,2) = self%ldim_mic(1)
        self%centers(NPATCH,:,1)   = sum(lims_patches(NPATCH,:,1,1:2),dim=2) / 2
        ! adjust other patch centers to be evenly spread
        dist = real(self%centers(NPATCH,1,1)-self%centers(1,1,1)+1) / real(NPATCH-1)
        do i=2,NPATCH-1
            cen = self%centers(1,1,1) + real(i-1)*dist
            lims_patches(i,:,1,1) = ceiling(cen) - ldim_patch(1)/2
            lims_patches(i,:,1,2) = lims_patches(i,:,1,1) + ldim_patch(1) - 1
            self%centers(i,:,1)   = sum(lims_patches(i,:,1,1:2),dim=2) / 2
        enddo
        ! along Y
        lims_patches(:,1,2,1) = 1
        lims_patches(:,1,2,2) = ldim_patch(2)
        self%centers(:,1,2)  = sum(lims_patches(:,1,2,1:2),dim=2) / 2
        lims_patches(:,NPATCH,2,1) = self%ldim_mic(2)-ldim_patch(2)+1
        lims_patches(:,NPATCH,2,2) = self%ldim_mic(2)
        self%centers(:,NPATCH,2)  = sum(lims_patches(:,NPATCH,2,1:2),dim=2) / 2
        dist = real(self%centers(1,NPATCH,2)-self%centers(1,1,2)+1) / real(NPATCH-1)
        do j=2,NPATCH-1
            cen = self%centers(1,1,2) + real(j-1)*dist
            lims_patches(:,j,2,1) = ceiling(cen) - ldim_patch(2)/2
            lims_patches(:,j,2,2) = lims_patches(:,j,2,1) + ldim_patch(2) - 1
            self%centers(:,j,2)  = sum(lims_patches(:,j,2,1:2),dim=2) /2
        enddo
    end subroutine gen_centers

    !> mic2spec calculates the average powerspectrum over a micrograph
    !!          the resulting spectrum has dampened central cross and subtracted background
    subroutine mic2spec_patch( self )
        class(ctf_estimate_fit), intent(inout) :: self
        real        :: dist, w, sumw
        integer     :: pi,pj, i,j, cnt
        !$omp parallel do collapse(2) default(shared) schedule(static) proc_bind(close) &
        !$omp private(i,j,pi,pj,w,sumw,dist)
        do pi = 1,NPATCH
            do pj = 1,NPATCH
                sumw = 0.
                self%pspec_patch(pi,pj) = 0.
                do i = 1,self%ntiles(1)
                    do j = 1,self%ntiles(2)
                        dist = sqrt(real(sum((self%centers(pi,pj,:)-self%tiles_centers(i,j,:))**2.)))
                        w    = exp(-0.5 *(dist/self%box)**2.)
                        if( w < 1.e-4 ) cycle
                        sumw = sumw + w
                        call self%pspec_patch(pi,pj)%add(self%tiles(i,j),w)
                    enddo
                enddo
                !print *,pi,pj,w
                call self%pspec_patch(pi,pj)%div(sumw)
                call self%pspec_patch(pi,pj)%dampen_pspec_central_cross
            enddo
        enddo
        !$omp end parallel do
        cnt = 0
        do pi = 1,NPATCH
            do pj = 1,NPATCH
                cnt = cnt+1
                call self%pspec_patch(pi,pj)%subtr_backgr(self%hp)
                !call self%pspec_patch(pi,pj)%write('patches.mrc',cnt)
            enddo
        enddo
    end subroutine mic2spec_patch

    !>  \brief  Normalize to zero mean and unit variance the reference power spectrum
    !>  within the relevent resolution range
    subroutine norm_pspec( self, img )
        class(ctf_estimate_fit), intent(inout) :: self
        class(image),            intent(inout) :: img
        real, pointer :: prmat(:,:,:)
        real(dp)      :: avg, sdev, val
        integer       :: i,j,k, mh,mk
        call img%get_rmat_ptr(prmat)
        mh   = abs(self%flims(1,1))
        mk   = abs(self%flims(2,1))
        sdev = 0.d0
        avg  = 0.d0
        do i=1,self%npix_msk
            j = min(max(1,self%inds_msk(1,i)+mh+1),self%ldim_box(1))
            k = min(max(1,self%inds_msk(2,i)+mk+1),self%ldim_box(2))
            avg = avg + real(prmat(j,k,1),dp)
        enddo
        avg = avg / real(self%npix_msk,dp)
        do i=1,self%npix_msk
            j = min(max(1,self%inds_msk(1,i)+mh+1),self%ldim_box(1))
            k = min(max(1,self%inds_msk(2,i)+mk+1),self%ldim_box(2))
            val  = real(prmat(j,k,1),dp) - avg
            sdev = sdev + val*val
        enddo
        sdev = dsqrt(sdev/real(self%npix_msk,dp))
        if(sdev <= TINY) sdev = 1.d0
        prmat(1:self%box,1:self%box,1) = real((real(prmat(1:self%box,1:self%box,1),dp) - avg)/sdev)
        nullify(prmat)
    end subroutine norm_pspec

    !>  \brief  Generates and normalize 1D rotational average spectrum
    subroutine gen_roavspec1d( self )
        class(ctf_estimate_fit), intent(inout) :: self
        real, pointer :: prmat(:,:,:)
        real          :: cnt(self%flims1d(1):self%flims1d(2)),avg,sdev
        integer       :: i,j,h,k, mh,mk, sh, shlim
        call self%pspec%get_rmat_ptr(prmat)
        ! spectrum 1D
        self%roavg_spec1d = 0.
        mh    = abs(self%flims(1,1))
        mk    = abs(self%flims(2,1))
        cnt   = 0
        shlim = nint(sqrt(real(self%flims1d(1)**2+self%flims1d(2)**2)))
        do h=self%flims(1,1),self%flims(1,2)
            do k=self%flims(2,1),self%flims(2,2)
                sh = nint(sqrt(real(h*h+k*k)))
                if( sh > shlim ) cycle
                i = min(max(1,h+mh+1),self%ldim_box(1))
                j = min(max(1,k+mk+1),self%ldim_box(2))
                self%roavg_spec1d(sh) = self%roavg_spec1d(sh)+prmat(i,j,1)
                cnt(sh) = cnt(sh)+1
            enddo
        enddo
        where( cnt > 0 ) self%roavg_spec1d = self%roavg_spec1d / real(cnt)
        ! pre_normalization
        avg = sum(self%roavg_spec1d(self%freslims1d(1):self%freslims1d(2)))&
            &/real(self%freslims1d(2)-self%freslims1d(1)+1)
        sdev = sum((self%roavg_spec1d(self%freslims1d(1):self%freslims1d(2))-avg)**2.)
        sdev = sqrt(sdev/real(self%freslims1d(2)-self%freslims1d(1)))
        if( sdev > TINY ) self%roavg_spec1d = (self%roavg_spec1d-avg) / sdev
        nullify(prmat)
    end subroutine gen_roavspec1d

    ! builds resolution dependent mask and indices for correlation calculation
    subroutine gen_resmsk( self )
        class(ctf_estimate_fit), intent(inout) :: self
        type(image) :: imgmsk
        integer :: h,k, i,j, cnt, mh,mk
        ! resolution mask
        call imgmsk%new(self%ldim_box, self%smpd)
        call imgmsk%resmsk(self%hp, self%lp)
        self%cc_msk = imgmsk%bin2logical()
        mh = abs(self%flims(1,1))
        mk = abs(self%flims(2,1))
        ! builds mask indices
        self%npix_msk = count(self%cc_msk)
        allocate(self%inds_msk(2,self%npix_msk))
        cnt = 0
        do h=self%flims(1,1),self%flims(1,2)
            do k=self%flims(2,1),self%flims(2,2)
                i = min(max(1,h+mh+1),self%ldim_box(1))
                j = min(max(1,k+mk+1),self%ldim_box(2))
                if( self%cc_msk(i,j,1) )then
                    cnt = cnt + 1
                    self%inds_msk(:,cnt) = [h,k]
                endif
            enddo
        enddo
        ! cleanup
        call imgmsk%kill
    end subroutine gen_resmsk

    ! calculate CTF score diagnostic
    subroutine calc_ctfscore( self )
        class(ctf_estimate_fit), intent(inout) :: self
        real, allocatable :: corrs(:)
        real              :: df_avg
        integer           :: filtsz, hpfind, lpfind
        df_avg = (self%parms%dfx + self%parms%dfy) / 2.0
        call self%ctf2pspecimg(self%pspec_ctf_roavg, df_avg, df_avg, 0.)
        hpfind = self%pspec_roavg%get_find(self%hp)
        lpfind = self%pspec_roavg%get_find(2.5)
        filtsz = self%pspec_roavg%get_filtsz()
        call self%pspec_roavg%mask(real(lpfind), 'soft', inner=real(hpfind))
        call self%pspec_ctf_roavg%mask(real(lpfind), 'soft', inner=real(hpfind))
        call self%pspec_roavg%norm_bin
        call self%pspec_ctf_roavg%norm_bin
        allocate(corrs(filtsz))
        call self%pspec_roavg%frc_pspec(self%pspec_ctf_roavg, corrs)
        self%ctfscore = real(count(corrs(hpfind:lpfind) > 0.)) / real(lpfind - hpfind + 1)
    end subroutine calc_ctfscore

    ! make & write half-n-half diagnostic
    subroutine write_diagnostic( self, diagfname )
        class(ctf_estimate_fit), intent(inout) :: self
        character(len=*),          intent(in)    :: diagfname
        type(image) :: pspec_half_n_half
        if( self%parms%l_phaseplate )then
            call self%ctf2pspecimg(self%pspec_ctf, self%parms%dfx, self%parms%dfy, self%parms%angast, add_phshift=self%parms%phshift)
        else
            call self%ctf2pspecimg(self%pspec_ctf, self%parms%dfx, self%parms%dfy, self%parms%angast)
        endif
        call self%pspec_ctf%norm()
        call self%pspec%norm()
        call self%pspec%before_after(self%pspec_ctf, pspec_half_n_half, self%cc_msk)
        call pspec_half_n_half%scale_pspec4viz
        call pspec_half_n_half%write_jpg(trim(diagfname), norm=.true.)
        call pspec_half_n_half%kill
    end subroutine write_diagnostic

    ! make & write half-n-half diagnostic
    subroutine write_diagnostic_patch( self, diagfname )
        class(ctf_estimate_fit), intent(inout) :: self
        character(len=*),          intent(in)    :: diagfname
        type(image) :: pspec_half_n_half, tmp
        integer     :: pi,pj
        call tmp%new(self%ldim_box,self%parms%smpd)
        self%pspec_ctf = 0.
        do pi = 1,NPATCH
            do pj = 1,NPATCH
                tmp = 0.
                if( self%parms%l_phaseplate )then
                    call self%ctf2pspecimg(tmp, self%parms_patch(pi,pj)%dfx, self%parms_patch(pi,pj)%dfy, self%parms_patch(pi,pj)%angast, add_phshift=self%parms_patch(pi,pj)%phshift)
                else
                    call self%ctf2pspecimg(tmp, self%parms_patch(pi,pj)%dfx, self%parms_patch(pi,pj)%dfy, self%parms_patch(pi,pj)%angast)
                endif
                call self%pspec_ctf%add(tmp)
            enddo
        enddo
        call self%pspec_ctf%norm()
        call self%pspec%norm()
        call self%pspec%before_after(self%pspec_ctf, pspec_half_n_half, self%cc_msk)
        call pspec_half_n_half%scale_pspec4viz
        call pspec_half_n_half%write_jpg(trim(diagfname), norm=.true.)
        call pspec_half_n_half%kill
        call tmp%kill
    end subroutine write_diagnostic_patch

    ! 1D brute force over rotational average
    subroutine grid_srch( self )
        class(ctf_estimate_fit), intent(inout) :: self
        type(ctf_estimate_cost1D) :: ctf_costs(NSTEPS)
        real    :: dfs(NSTEPS), costs(NSTEPS), df_best
        integer :: i, loc
        ! no astigmatism
        self%parms%phshift = 0.
        if( self%parms%l_phaseplate ) self%parms%phshift = PIO2
        !$omp parallel do default(shared) private(i) schedule(static) proc_bind(close)
        do i = 1,NSTEPS
            call ctf_costs(i)%init(self%pspec_roavg,self%flims1d,self%freslims1d,self%roavg_spec1d,self%parms)
            dfs(i)   = self%df_lims(1) + real(i-1)*self%df_step
            costs(i) = ctf_costs(i)%cost(dfs(i))
            call ctf_costs(i)%kill
        enddo
        !$omp end parallel do
        loc     = minloc(costs,dim=1)
        df_best = dfs(loc)
        self%cc_fit        = -costs(loc)
        self%parms%dfx     = df_best
        self%parms%dfy     = df_best
        self%parms%angast  = 0.
        self%parms%phshift = 0.
        if( self%parms%l_phaseplate )self%parms%phshift = PIO2
    end subroutine grid_srch

    ! 2D search over whole spectrum
    subroutine refine( self )
        class(ctf_estimate_fit), intent(inout) :: self
        real :: limits(4,2), half_range
        ! re-init limits for local search
        half_range  = 2.*max(self%astigtol, self%df_step)
        limits      = 0.
        limits(1,1) = max(self%df_lims(1),self%parms%dfx - half_range)
        limits(2,1) = max(self%df_lims(1),self%parms%dfy - half_range)
        limits(1,2) = min(self%df_lims(2),self%parms%dfx + half_range)
        limits(2,2) = min(self%df_lims(2),self%parms%dfy + half_range)
        limits(3,:) = [0., 180.] ! degrees
        limits(4,:) = [0.,3.142] ! radians
        ! good solution
        if( self%parms%l_phaseplate )then
            call self%ctf_cost2D%init(self%pspec, self%parms, self%inds_msk, 4, limits,        self%astigtol, TOL)
        else
            call self%ctf_cost2D%init(self%pspec, self%parms, self%inds_msk, 3, limits(1:3,:), self%astigtol, TOL)
        endif
        call self%ctf_cost2D%minimize(self%parms, self%cc_fit)
        ! refined solution & without circular issue
        limits(1,1) = max(self%df_lims(1),self%parms%dfx - half_range)
        limits(2,1) = max(self%df_lims(1),self%parms%dfy - half_range)
        limits(1,2) = min(self%df_lims(2),self%parms%dfx + half_range)
        limits(2,2) = min(self%df_lims(2),self%parms%dfy + half_range)
        limits(3,1) = self%parms%angast - 30.       ! degrees
        limits(3,2) = self%parms%angast + 30.
        limits(4,1) = self%parms%phshift - PI/6.    ! radians
        limits(4,2) = self%parms%phshift + PI/6
        if( self%parms%l_phaseplate )then
            call self%ctf_cost2D%init(self%pspec, self%parms, self%inds_msk, 4, limits,        self%astigtol, TOL_REFINE)
        else
            call self%ctf_cost2D%init(self%pspec, self%parms, self%inds_msk, 3, limits(1:3,:), self%astigtol, TOL_REFINE)
        endif
        call self%ctf_cost2D%minimize(self%parms, self%cc_fit)
        call self%ctf_cost2D%kill
    end subroutine refine

    !>  \brief  is for making a |CTF| spectrum image
    subroutine ctf2pspecimg( self, img, dfx, dfy, angast, add_phshift )
        class(ctf_estimate_fit), intent(inout) :: self
        class(image),   intent(inout) :: img         !< image (output)
        real,           intent(in)    :: dfx         !< defocus x-axis
        real,           intent(in)    :: dfy         !< defocus y-axis
        real,           intent(in)    :: angast      !< angle of astigmatism
        real, optional, intent(in)    :: add_phshift !< aditional phase shift (radians), for phase plate
        real, pointer :: prmat(:,:,:)
        real    :: ang, tval, spaFreqSq, hinv, aadd_phshift, kinv, inv_ldim(3)
        integer :: lims(3,2),h,mh,k,mk,ldim(3), i,j
        ! initialize
        aadd_phshift = 0.
        if( present(add_phshift) ) aadd_phshift = add_phshift
        call self%tfun%init(dfx, dfy, angast)
        call img%get_rmat_ptr(prmat)
        prmat    = 0.
        lims     = img%loop_lims(3)
        mh       = abs(lims(1,1))
        mk       = abs(lims(2,1))
        ldim     = img%get_ldim()
        inv_ldim = 1./real(ldim)
        !$omp parallel do collapse(2) default(shared) private(h,hinv,k,kinv,i,j,spaFreqSq,ang,tval) &
        !$omp schedule(static) proc_bind(close)
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                i         = min(max(1,h+mh+1),ldim(1))
                j         = min(max(1,k+mk+1),ldim(2))
                hinv      = real(h) * inv_ldim(1)
                kinv      = real(k) * inv_ldim(2)
                spaFreqSq = hinv * hinv + kinv * kinv
                ang       = atan2(real(k),real(h))
                tval      = self%tfun%eval(spaFreqSq, ang, aadd_phshift)
                tval      = min(1.,max(tval * tval,0.0001))
                prmat(i,j,1) = sqrt(tval)
            end do
        end do
        !$omp end parallel do
    end subroutine ctf2pspecimg

    ! as per CTFFIND4.1.9
    subroutine calc_ctfres( self )
        class(ctf_estimate_fit), intent(inout) :: self
        real,     parameter  :: min_angdist = 10.
        type(image)          :: extrema, ctf, specimg
        real,    allocatable :: spec1d(:), spec1d_fit(:), spec1d_rank(:)
        real,    allocatable :: ctf1d(:), nextrema1d(:), frc(:), frc_sig(:)
        integer, allocatable :: nvals1d(:)
        real    :: mid_angast,mid_angast_rad,hinv, angdist_axes, spaFreqSq, phshift
        integer :: ish, ldim(3),nrlims(3,2),rlims(3,2), mh,mk, sh, n, h,k, i,j, nshells, mhr
        ! init
        ldim = [self%box,self%box,1]
        call ctf%new(ldim,self%smpd)
        call extrema%new(ldim,self%smpd)
        call specimg%new(ldim,self%smpd)
        nrlims  = ctf%loop_lims(2) ! non-redundant limits
        rlims   = ctf%loop_lims(3) ! redundant limits
        mhr     = abs(rlims(1,1))  ! redundant
        mh      = abs(nrlims(1,1)) ! non-redundant
        mk      = abs(nrlims(2,1)) ! non-redundant
        nshells = floor(sqrt(real(maxval(abs(rlims(1,:)))**2.+maxval(abs(rlims(2,:))**2.)))) ! shell of furthest pixel in corner
        phshift = merge(self%parms%phshift, 0. ,self%parms%l_phaseplate)
        allocate(spec1d(0:nshells),spec1d_fit(0:nshells),frc(0:nshells),frc_sig(0:nshells),&
            &spec1d_rank(0:nshells),ctf1d(0:nshells),nextrema1d(0:nshells), source=0.)
        allocate(nvals1d(0:nshells),source=0)
        ! normalize spectrum
        call self%mic2spec(specimg) ! should become un-necessary
        call norm2dspec
        ! calculate number of extrema & ctf values
        call self%gen_ctf_extrema(ctf, extrema)
        ! midway astigmatism & ensuring it has not been zeroed by central cross dampening
        mid_angast   = self%parms%angast + 45.
        ! convention has to be enforced before this !!!
        angdist_axes = mod(mid_angast, 90.)
        if( abs(angdist_axes) <     min_angdist ) mid_angast = sign(min_angdist ,angdist_axes)
        if( abs(angdist_axes) > 90.-min_angdist ) mid_angast = sign(90.-min_angdist, angdist_axes)
        mid_angast_rad = deg2rad(mid_angast)
        ! theoretical 1D spectrum & number of extrema
        do h = 0,nshells
            hinv          = real(h) / real(self%box)
            spaFreqSq     = hinv * hinv
            ctf1d(h)      = -self%tfun%eval(spaFreqSq, mid_angast_rad, add_phshift=phshift)
            nextrema1d(h) = real(self%tfun%nextrema(spaFreqSq, mid_angast_rad, phshift))
        enddo
        ! 1D spectrum
        do k=rlims(2,1),rlims(2,2)
            j = min(max(1,k+mk+1),ldim(2))
            do h=rlims(1,1),rlims(1,2)
                i  = min(max(1,h+mhr+1),ldim(1))
                sh = get_shell(ctf%get([i,j,1]), extrema%get([i,j,1])) ! ReturnSpectrumBinNumber
                nvals1d(sh) = nvals1d(sh)+ 1
                spec1d(sh)  = spec1d(sh) + specimg%get([i,j,1])
            end do
        end do
        where( nvals1d > 0 ) spec1d = spec1d / real(nvals1d)
        spec1d_fit  = abs(ctf1d)
        spec1d_rank = spec1d
        ! 1D spectrum ranking
        call rank_spec
        ! FRC
        call calc_frc
        ! skip aliasing identification
        ! abracadabra
        sh = ctfres_shell()
        self%ctfres = specimg%get_lp(sh)
        ! cleanup
        call extrema%kill
        call ctf%kill
        call specimg%kill
        contains

            subroutine calc_frc
                integer, allocatable :: winhalfwidth(:)
                real    :: spec_avg,spec_sdev,fit_avg,fit_sdev,product
                integer :: nh,h,sh,sh_prev,lefth,righth,min_winhalfwidth
                allocate(winhalfwidth(0:nshells),source=0)
                ! FRC window sizes
                min_winhalfwidth = nint(real(nshells)/40.)
                sh_prev = 0
                do sh = 1,nshells
                    if( .not.is_equal(nextrema1d(sh),nextrema1d(sh-1)) )then
                        do ish = sh_prev,sh-1
                            winhalfwidth(ish) = nint((1.+0.1*real(nextrema1d(sh))) * real((sh-sh_prev+1)))
                            winhalfwidth(ish) = max(winhalfwidth(ish), min_winhalfwidth)
                            winhalfwidth(ish) = min(winhalfwidth(ish), nint(real(nshells)/2.)-1)
                        enddo
                        sh_prev = sh
                    endif
                enddo
                winhalfwidth(0) = winhalfwidth(1)
                winhalfwidth(sh_prev:nshells) = winhalfwidth(sh_prev-1) ! check for sh_prev here
                ! FRC
                frc(:) = 1.
                do h = self%freslims1d(1),nshells
                    spec_avg  = 0.
                    spec_sdev = 0.
                    fit_avg   = 0.
                    fit_sdev  = 0.
                    lefth  = h-winhalfwidth(h)
                    righth = h+winhalfwidth(h)
                    if( lefth < self%freslims1d(1) )then
                        lefth  = self%freslims1d(1)
                        righth = lefth + 2*winhalfwidth(h)+1
                    endif
                    if( righth > nshells )then
                        righth = nshells
                        lefth  = righth - 2*winhalfwidth(h)-1
                    endif
                    nh        = 2*winhalfwidth(h)+1
                    spec_avg  = sum(spec1d_rank(lefth:righth))/ real(nh)
                    fit_avg   = sum(spec1d_fit(lefth:righth)) / real(nh)
                    product   = dot_product(spec1d_rank(lefth:righth)-spec_avg, spec1d_fit(lefth:righth)-fit_avg) / real(nh)
                    spec_sdev = sum((spec1d_rank(lefth:righth)-spec_avg)**2.)
                    fit_sdev  = sum((spec1d_fit(lefth:righth) -fit_avg )**2.)
                    if( spec_sdev>TINY .and. fit_sdev>TINY )then
                        spec_sdev = sqrt(spec_sdev/real(nh))
                        fit_sdev  = sqrt(fit_sdev /real(nh))
                        frc(h)    = product / (spec_sdev*fit_sdev)
                    else
                        frc(h) = 0.
                    endif
                    frc_sig(h) = 2./real(nh)
                enddo
            end subroutine

            subroutine norm2dspec
                integer       :: h,k,i,j
                real, pointer :: prmat(:,:,:)
                real          :: avg, sdev
                call specimg%get_rmat_ptr(prmat)
                ! zero edges
                call specimg%zero_edgeavg
                ! stats
                avg  = sum(prmat(:self%box,:self%box,1:1),mask=self%cc_msk) / real(self%npix_msk)
                sdev = sqrt( sum((prmat(:self%box,:self%box,1:1)-avg)**2.,mask=self%cc_msk) / real(self%npix_msk) )
                ! zero center
                do h = rlims(1,1),rlims(1,2)
                    do k = rlims(2,1),rlims(2,2)
                        i = min(max(1,h+mhr+1),self%box)
                        j = min(max(1,k+mk+1),self%box)
                        sh = nint(sqrt(real(h*h+k*k)))
                        if( sh <= self%freslims1d(1) ) prmat(i,j,1) = 0 ! to update to s<self%freslims1d(1)
                    enddo
                enddo
                ! dampens central cross again
                do h = rlims(1,1),rlims(1,2)
                    do k = rlims(2,1),rlims(2,2)
                        if( h/=0 .and. k/=0 ) cycle
                        i = min(max(1,h+mhr+1),ldim(1))
                        j = min(max(1,k+mk+1),ldim(2))
                        prmat(i,j,1) = min(prmat(i,j,1), avg)
                    enddo
                enddo
                ! threshold
                where( prmat >  avg+4.*sdev ) prmat  =  avg+4.*sdev
                where( prmat <  avg-4.*sdev ) prmat  =  avg-4.*sdev
                ! stats encore
                avg  = sum(prmat(:self%box,:self%box,1:1),mask=self%cc_msk) / real(self%npix_msk)
                sdev = sqrt( sum((prmat(:self%box,:self%box,1:1)-avg)**2.,mask=self%cc_msk) / real(self%npix_msk) )
                ! normalize
                call specimg%subtr(avg)
                call specimg%div(sdev)
                call specimg%add(avg)
            end subroutine norm2dspec

            subroutine rank_spec
                real,    allocatable :: vec(:), rankvec(:)
                integer, allocatable :: inds(:)
                real    :: rmin, rmax, areal
                integer :: sh, sh_prev, h, sh_zero, ind
                allocate(rankvec(0:nshells),vec(0:nshells), source=0.)
                allocate(inds(0:nshells),source=0)
                sh_prev = 0
                sh      = 0
                do h=1,nshells
                    if( nextrema1d(h)-nextrema1d(h-1) >= 0.9) then
                        sh = h-1 ! extremum at h-1
                        if( sh_prev > 0 )then
                            if( nextrema1d(h) < 7. )then
                                ! identify zero
                                sh_zero = sh_prev + nint(real(sh-sh_prev)/2.)
                                do ish = sh_prev,sh-1
                                    if( (spec1d_fit(ish)<spec1d_fit(ish-1)) .and. (spec1d_fit(ish)<spec1d_fit(ish+1)) ) sh_zero = ish
                                enddo
                                ! downslope ranking
                                n   = sh_zero-sh_prev+1
                                vec = -huge(areal)
                                inds = 0
                                inds(sh_prev:sh_zero) = (/(ish,ish=sh_prev,sh_zero)/)
                                vec(sh_prev:sh_zero)  = spec1d_rank(sh_prev:sh_zero)
                                rankvec(nshells-n+1:nshells) = sin(PIO2*(/(real(ish)/real(n-1),ish=0,n-1)/))
                                call hpsort(vec,inds)
                                do ind = nshells,nshells-n+1,-1
                                    ish = inds(ind)
                                    spec1d_rank(ish) = rankvec(ind)
                                enddo
                                ! upslope ranking
                                n    = sh-sh_zero
                                vec  = -huge(areal)
                                inds = 0
                                inds(sh_zero+1:sh-1) = (/(ish,ish=sh_zero+1,sh-1)/)
                                vec(sh_zero+1:sh-1)  = spec1d_rank(sh_zero+1:sh-1)
                                rankvec(nshells-n+1:nshells) = sin(PIO2*(/(real(ish)/real(n),ish=0,n-1)/))
                                call hpsort(vec,inds)
                                do ind = nshells,nshells-n+1,-1
                                    ish = inds(ind)
                                    spec1d_rank(ish) = rankvec(ind)
                                enddo
                            else
                                rmin = minval(spec1d_rank(sh_prev:sh-1))
                                rmax = maxval(spec1d_rank(sh_prev:sh-1))
                                spec1d_rank(sh_prev:sh-1) = spec1d_rank(sh_prev:sh-1) - rmin
                                if( rmax-rmin > 1.e-4 )then
                                    spec1d_rank(sh_prev:sh-1) = spec1d_rank(sh_prev:sh-1) / (rmax-rmin)
                                endif
                            endif
                        endif
                        sh_prev = sh
                    endif
                enddo
            end subroutine rank_spec

            integer function get_shell(ctf2d, extremum2d)
                real, intent(in) :: ctf2d, extremum2d
                real    :: diff, diff_prev, diff_next, ctf_diff, ctf_diff_saved
                integer :: ih
                get_shell = -1
                ctf_diff  = huge(ctf_diff)
                do ih=0,nshells
                    diff = abs(extremum2d-real(nextrema1d(ih)))
                    if( ih == 0 )then
                        diff_prev = huge(diff_prev)
                    else
                        diff_prev = abs(extremum2d-nextrema1d(ih-1))
                    endif
                    if( ih == nshells )then
                        diff_next = huge(diff_next)
                    else
                        diff_next = abs(extremum2d-nextrema1d(ih+1))
                    endif
                    if( extremum2d > nextrema1d(nshells) )then
                        get_shell = nshells
                    else
                        if( (diff <= 0.01) .or.((diff < diff_prev).and.(diff <= diff_next).and.&
                            &(.not.is_equal(nextrema1d(max(0,ih-1)),nextrema1d(min(ih+1,nshells))))) )then
                            ctf_diff_saved = ctf_diff
                            ctf_diff       = abs(ctf2d-ctf1d(ih))
                            if( ctf_diff < ctf_diff_saved ) get_shell = ih
                        endif
                    endif
                enddo
                if( get_shell < 0 )THROW_HARD('no shell found')
            end function get_shell

            integer function ctfres_shell()
                ! empirical thesholds
                real, parameter :: low_threshold  = 0.1
                real, parameter :: high_threshold = 0.66
                real, parameter :: significance_threshold = 0.5
                integer :: h, n_abovelow, n_abovehigh, n_abovesig
                logical :: whereitsat
                n_abovelow   = 0
                n_abovehigh  = 0
                n_abovesig   = 0
                ctfres_shell = -1
                do h = 0,nshells
                    whereitsat = (n_abovelow>3) .and. (frc(h)<low_threshold) .and. (n_abovehigh>3) .and. (frc(h)<significance_threshold)
                    if( whereitsat )then
                        ctfres_shell = h
                        exit
                    endif
                    if( frc(h) > low_threshold )          n_abovelow  = n_abovelow+1
                    if( frc(h) > significance_threshold ) n_abovesig  = n_abovesig+1
                    if( frc(h) > high_threshold )         n_abovehigh = n_abovehigh+1
                enddo
                n_abovesig = min(n_abovesig,nshells)
                if( n_abovesig == 0 ) ctfres_shell = 1
                ctfres_shell = max(0,min(ctfres_shell,nshells))
            end function ctfres_shell

    end subroutine calc_ctfres

    !>  \brief  is for making a CTF & calculate #of astigmatism extrema
    subroutine gen_ctf_extrema( self, ctf, extrema )
        class(ctf_estimate_fit), intent(inout) :: self
        class(image),            intent(inout) :: ctf, extrema
        real, pointer :: pctf(:,:,:), pextr(:,:,:)
        real    :: ang, spaFreqSq, hinv, phshift, kinv, inv_ldim(3)
        integer :: lims(3,2),h,mh,k,mk,ldim(3), i,j
        call ctf%get_rmat_ptr(pctf)
        call extrema%get_rmat_ptr(pextr)
        pctf     = 0.
        pextr    = 0.
        ldim     = ctf%get_ldim()
        lims     = ctf%loop_lims(3)
        mh       = abs(lims(1,1))
        mk       = abs(lims(2,1))
        inv_ldim = 1./real(ldim)
        call self%tfun%init(self%parms%dfx, self%parms%dfy, self%parms%angast)
        phshift = 0.
        if( self%parms%l_phaseplate ) phshift = self%parms%phshift
        !$omp parallel do collapse(2) default(shared) private(h,hinv,k,kinv,i,j,spaFreqSq,ang) &
        !$omp schedule(static) proc_bind(close)
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                i         = min(max(1,h+mh+1),ldim(1))
                j         = min(max(1,k+mk+1),ldim(2))
                ang       = atan2(real(k),real(h))
                hinv      = real(h) * inv_ldim(1)
                kinv      = real(k) * inv_ldim(2)
                spaFreqSq = hinv * hinv + kinv * kinv
                pextr(i,j,1) = real(self%tfun%nextrema(spaFreqSq, ang, phshift))
                pctf(i,j,1)  = -self%tfun%eval(spaFreqSq, ang, phshift) ! dbl check sign change
            end do
        end do
        !$omp end parallel do
    end subroutine gen_ctf_extrema

    ! fit dfx/y to 2 polynomials
    subroutine fit_polynomial( self )
        class(ctf_estimate_fit), intent(inout) :: self
        real    :: x(2,self%npatch), yx(self%npatch), yy(self%npatch), sig(self%npatch)
        real    :: v(POLYDIM,POLYDIM), w(POLYDIM), chi_sq
        integer :: pi,pj, cnt
        cnt = 0
        do pi=1,NPATCH
            do pj = 1,NPATCH
                cnt = cnt + 1
                call self%pix2poly(real(self%centers(pi,pj,1)),real(self%centers(pi,pj,2)), x(1,cnt),x(2,cnt))
                yx(cnt) = self%parms_patch(pi,pj)%dfx
                yy(cnt) = self%parms_patch(pi,pj)%dfy
            enddo
        enddo
        sig = 1.
        call svd_multifit(x,yx,sig,self%polyx,v,w,chi_sq,poly)
        call svd_multifit(x,yy,sig,self%polyy,v,w,chi_sq,poly)
    end subroutine fit_polynomial

    function poly(p,n) result( res )
        real,    intent(in)  :: p(:)
        integer, intent(in)  :: n
        real :: res(n), x,y
        x = p(1)
        y = p(2)
        res = [1., x, x*x, y, y*y, x*y]
    end function poly

    ! real space coordinates to polynomial coordinates
    subroutine pix2poly( self, xin, yin, xout, yout )
        class(ctf_estimate_fit), intent(inout) :: self
        real,                    intent(in)    :: xin,yin
        real,                    intent(out)   :: xout,yout
        xout = (xin-1.) / real(self%ldim_mic(1)-1) - 0.5
        yout = (yin-1.) / real(self%ldim_mic(2)-1) - 0.5
    end subroutine pix2poly

    ! evaluate fitted defocus
    subroutine pix2polyvals( self, xin, yin, dfx, dfy )
        class(ctf_estimate_fit), intent(inout) :: self
        real,                    intent(in)    :: xin,yin
        real,                    intent(out)   :: dfx,dfy
        real :: xp,yp
        call self%pix2poly(real(xin),real(yin), xp,yp)
        dfx = poly2val(self%polyx,xp,yp)
        dfy = poly2val(self%polyy,xp,yp)
        contains

            real function poly2val(p,x,y)
                real, intent(in) :: p(POLYDIM),x,y
                poly2val = dot_product(p, [1., x, x*x, y, y*y, x*y])
            end function poly2val

    end subroutine pix2polyvals

    subroutine plot_parms( self, fname )
        class(ctf_estimate_fit), intent(inout) :: self
        character(len=*),        intent(in)    :: fname
        real, parameter       :: SCALE = 200.
        type(str4arr)         :: title
        type(CPlot2D_type)    :: plot2D
        type(CDataSet_type)   :: calc, fit, center
        type(CDataPoint_type) :: p1
        real                  :: cx,cy,dfx,dfy,avgdfx,avgdfy,dfxmin,dfxmax,dfymin,dfymax
        integer               :: pi,pj
        avgdfx = 0.
        avgdfy = 0.
        dfxmin = huge(dfxmin)
        dfxmax = -huge(dfxmax)
        dfymin = huge(dfymin)
        dfymax = -huge(dfymax)
        do pi = 1, NPATCH
            do pj = 1, NPATCH
                avgdfx = avgdfx + self%parms_patch(pi,pj)%dfx
                avgdfy = avgdfy + self%parms_patch(pi,pj)%dfy
                dfxmin = min(dfxmin, self%parms_patch(pi,pj)%dfx)
                dfxmax = max(dfxmax, self%parms_patch(pi,pj)%dfx)
                dfymin = min(dfymin, self%parms_patch(pi,pj)%dfy)
                dfymax = max(dfymax, self%parms_patch(pi,pj)%dfy)
            enddo
        enddo
        avgdfx = avgdfx / real(self%npatch)
        avgdfy = avgdfy / real(self%npatch)
        call CPlot2D__new(plot2D, fname)
        call CPlot2D__SetDrawXAxisGridLines(plot2D, C_FALSE)
        call CPlot2D__SetDrawYAxisGridLines(plot2D, C_FALSE)
        call CPlot2D__SetXAxisSize(plot2D, 600._c_double)
        call CPlot2D__SetYAxisSize(plot2D, 600._c_double)
        call CPlot2D__SetDrawLegend(plot2D, C_FALSE)
        call CPlot2D__SetFlipY(plot2D, C_TRUE)
        do pi = 1, NPATCH
            do pj = 1, NPATCH
                ! center
                cx = real(self%centers(pi,pj,1))
                cy = real(self%centers(pi,pj,2))
                call CDataSet__new(center)
                call CDataSet__SetDrawMarker(center, C_TRUE)
                call CDataSet__SetMarkerSize(center, real(5., c_double))
                call CDataSet__SetDatasetColor(center, 1.0_c_double,0.0_c_double,0.0_c_double)
                call CDataPoint__new2(real(cx, c_double), real(cy, c_double), p1)
                call CDataSet__AddDataPoint(center, p1)
                call CDataPoint__delete(p1)
                call CPlot2D__AddDataSet(plot2D, center)
                call CDataSet__delete(center)
                ! calculated
                call CDataSet__new(calc)
                call CDataSet__SetDrawMarker(calc, C_FALSE)
                call CDataSet__SetDatasetColor(calc, 0.0_c_double,0.0_c_double,1.0_c_double)
                call CDataPoint__new2(real(cx, c_double), real(cy, c_double), p1)
                call CDataSet__AddDataPoint(calc, p1)
                call CDataPoint__delete(p1)
                dfx = SCALE * (self%parms_patch(pi,pj)%dfx-dfxmin)/(dfxmax-dfxmin)
                dfy = SCALE * (self%parms_patch(pi,pj)%dfy-dfymin)/(dfymax-dfymin)
                call CDataPoint__new2(real(cx+dfx, c_double), real(cy+dfy, c_double), p1)
                call CDataSet__AddDataPoint(calc, p1)
                call CDataPoint__delete(p1)
                call CPlot2D__AddDataSet(plot2D, calc)
                call CDataSet__delete(calc)
                ! fit
                call CDataSet__new(fit)
                call CDataSet__SetDrawMarker(fit, C_FALSE)
                call CDataSet__SetDatasetColor(fit, 0.0_c_double,0.0_c_double,0.0_c_double)
                call CDataPoint__new2(real(cx, c_double), real(cy, c_double), p1)
                call CDataSet__AddDataPoint(fit, p1)
                call CDataPoint__delete(p1)
                call self%pix2polyvals(cx,cy,dfx,dfy)
                dfx = SCALE * (dfx-dfxmin)/(dfxmax-dfxmin)
                dfy = SCALE * (dfy-dfymin)/(dfymax-dfymin)
                call CDataPoint__new2(real(cx+dfx, c_double), real(cy+dfy, c_double), p1)
                call CDataSet__AddDataPoint(fit, p1)
                call CDataPoint__delete(p1)
                call CPlot2D__AddDataSet(plot2D, fit)
                call CDataSet__delete(fit)
            end do
        end do
        title%str = 'Need to simplify. Blue: calculated; black: interpolated'//C_NULL_CHAR
        call CPlot2D__SetXAxisTitle(plot2D, title%str)
        call CPlot2D__OutputPostScriptPlot(plot2D, fname)
        call CPlot2D__delete(plot2D)
    end subroutine plot_parms

    subroutine write_doc( self, moviename, fname )
        class(ctf_estimate_fit), intent(inout) :: self
        character(len=*),        intent(in)    :: moviename, fname
        type(oris) :: os
        integer    :: i
        call os%new(3)
        call os%set(1,'smpd',   self%parms%smpd)
        call os%set(1,'cs',     self%parms%cs)
        call os%set(1,'kv',     self%parms%kv)
        call os%set(1,'fraca',  self%parms%fraca)
        call os%set(1,'dfx',    self%parms%dfx)
        call os%set(1,'dfy',    self%parms%dfy)
        call os%set(1,'angast', self%parms%angast)
        call os%set(1,'phshift',self%parms%phshift)
        call os%set(1,'forctf', moviename)
        call os%set(1,'xdim',   real(self%ldim_mic(1)))
        call os%set(1,'ydim',   real(self%ldim_mic(2)))
        if( self%parms%l_phaseplate )then
            call os%set(1,'phaseplate','yes')
        else
            call os%set(1,'phaseplate','no')
        endif
        do i = 1, POLYDIM
            call os%set(2,'px'//int2str(i),self%polyx(i))
            call os%set(3,'py'//int2str(i),self%polyy(i))
        enddo
        call os%write(fname)
        call os%kill
    end subroutine write_doc

    subroutine write_star( self, fname )
        class(ctf_estimate_fit), intent(inout) :: self
        character(len=*),        intent(in)    :: fname
        type(starfile_table_type) :: mc_starfile
        integer :: i
        call starfile_table__new( mc_starfile )
        call starfile_table__open_ofile(mc_starfile, fname)
        call starfile_table__addObject(mc_starfile)
        call starfile_table__setIsList(mc_starfile, .true.)
        call starfile_table__setname(mc_starfile, "general")
        call starfile_table__setValue_int(mc_starfile, EMDL_IMAGE_SIZE_X, self%ldim_mic(1))
        call starfile_table__setValue_int(mc_starfile, EMDL_IMAGE_SIZE_Y, self%ldim_mic(2))
        call starfile_table__setValue_int(mc_starfile, EMDL_IMAGE_SIZE_Z, self%ldim_mic(3))
        call starfile_table__setValue_string(mc_starfile, EMDL_MICROGRAPH_NAME, simple_abspath(fname))
        call starfile_table__setValue_double(mc_starfile, EMDL_MICROGRAPH_ORIGINAL_PIXEL_SIZE, real(self%parms%smpd, dp))
        ! whole micrograph model
        call starfile_table__setValue_double(mc_starfile, EMDL_CTF_CS,            real(self%parms%cs, dp))
        call starfile_table__setValue_double(mc_starfile, EMDL_CTF_VOLTAGE,       real(self%parms%kv, dp))
        call starfile_table__setValue_double(mc_starfile, EMDL_CTF_Q0,            real(self%parms%fraca, dp))
        call starfile_table__setValue_double(mc_starfile, EMDL_CTF_DEFOCUSU,      real(self%parms%dfx*10000., dp))
        call starfile_table__setValue_double(mc_starfile, EMDL_CTF_DEFOCUSV,      real(self%parms%dfy*10000., dp))
        call starfile_table__setValue_double(mc_starfile, EMDL_CTF_DEFOCUS_ANGLE, real(self%parms%angast,dp))
        call starfile_table__setValue_double(mc_starfile, EMDL_CTF_PHASESHIFT,    real(self%parms%phshift,dp))
        call starfile_table__write_ofile(mc_starfile)
        call starfile_table__clear(mc_starfile)
        ! local model
        call starfile_table__setIsList(mc_starfile, .false.)
        call starfile_table__setName(mc_starfile, "local_ctf_model")
        do i = 1, POLYDIM
            call starfile_table__addObject(mc_starfile)
            call starfile_table__setValue_double(mc_starfile, EMDL_CTF_MODEL_DEFOCUSU, real(self%polyx(i)*10000.,dp))
            call starfile_table__setValue_double(mc_starfile, EMDL_CTF_MODEL_DEFOCUSV, real(self%polyy(i)*10000.,dp))
        end do
        call starfile_table__write_ofile(mc_starfile)
        call starfile_table__clear(mc_starfile)
        ! close & clean
        call starfile_table__close_ofile(mc_starfile)
        call starfile_table__delete(mc_starfile)
    end subroutine write_star

    ! DESTRUCTOR

    subroutine kill( self )
        class(ctf_estimate_fit), intent(inout) :: self
        integer :: i,j
        self%cc_fit       = -1.
        self%ctfscore     = -1.
        self%ctfres       = -1.
        nullify(self%micrograph)
        call self%pspec%kill
        call self%pspec_ctf%kill
        call self%pspec_ctf_roavg%kill
        call self%pspec_roavg%kill
        call self%ctf_cost1D%kill
        call self%ctf_cost2D%kill
        if( allocated(self%roavg_spec1d) ) deallocate(self%roavg_spec1d)
        if( allocated(self%cc_msk) )       deallocate(self%cc_msk)
        if( allocated(self%inds_msk) )     deallocate(self%inds_msk)
        if( allocated(self%tiles) )then
            do i=1,self%ntiles(1)
                do j=1,self%ntiles(2)
                    call self%tiles(i,j)%kill
                enddo
            enddo
            deallocate(self%tiles,self%tiles_centers)
        endif
        do i = 1,NPATCH
            do j = 1,NPATCH
                call self%pspec_patch(i,j)%kill
                call self%ctf_cost_patch(i,j)%kill
            enddo
        enddo
        self%exists = .false.
    end subroutine kill

end module simple_ctf_estimate_fit

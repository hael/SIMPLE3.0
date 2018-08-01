! defines the Contrast Transfer Function (CTF) of the electron microscope
! based on a class used in CTFFIND4, developed by Alexis Rohou and Nikolaus
! Grigorieff at Janelia Farm. The below copyright statement therefore
! needs to be included here:
! Copyright 2014 Howard Hughes Medical Institute
! All rights reserved
! Use is subject to Janelia Farm Research Campus Software Copyright 1.1
! license terms ( http://license.janelia.org/license/jfrc_copyright_1_1.html )
module simple_ctf
!$ use omp_lib
!$ use omp_lib_kinds
include 'simple_lib.f08'
implicit none

public :: ctf
private

type ctf
    private
    real    :: smpd        = 0.    !< sampling distance (input unit: A)
    real    :: kV          = 0.    !< acceleration voltage of the electron microscope (input unit: kV)
    real    :: Cs          = 0.    !< spherical aberration (input unit: mm)
    real    :: wl          = 0.    !< wavelength (input unit: A)
    real    :: amp_contr   = 0.07  !< fraction of amplitude contrast ([0.07,0.15] see Mindell 03)
    real    :: dfx         = 0.    !< underfocus x-axis, underfocus is positive; larger value = more underfocus (input unit: microns)
    real    :: dfy         = 0.    !< underfocus y-axis (input unit: microns)
    real    :: angast      = 0.    !< azimuth of x-axis 0.0 means axis is at 3 o'clock (input unit: degrees)
    real    :: phaseq      = 0.    !< phase constrast weight (derived constant)
    real    :: ampliq      = 0.    !< amplitude contrast weight (derived constant)
  contains
    procedure          :: init
    procedure, private :: eval_1
    procedure, private :: eval_2
    procedure, private :: eval_3
    procedure, private :: eval_4
    generic            :: eval => eval_1, eval_2, eval_3, eval_4
    procedure, private :: evalPhSh
    procedure, private :: eval_df
    procedure          :: apply
    procedure          :: ctf2img
    procedure          :: apply_serial
    procedure          :: phaseflip_and_shift_serial
    procedure          :: apply_and_shift
    procedure          :: kV2wl
end type ctf

interface ctf
    module procedure constructor
end interface

contains

    function constructor( smpd, kV, Cs, amp_contr ) result( self )
        real, intent(in) :: smpd      !< sampling distance
        real, intent(in) :: kV        !< accelleration voltage
        real, intent(in) :: Cs        !< constant
        real, intent(in) :: amp_contr !< amplitude contrast
        type(ctf) :: self
        ! set constants
        self%kV        = kV
        self%wl        = self%kV2wl() / smpd
        self%Cs        = (Cs*1.0e7) / smpd
        self%amp_contr = amp_contr
        self%smpd      = smpd
        ! compute derived constants (phase and amplitude contrast weights)
        self%phaseq    = sqrt(1. - amp_contr * amp_contr)
        self%ampliq    = amp_contr
    end function constructor

    !>  \brief  initialise a CTF object with defocus/astigmatism params
    subroutine init( self, dfx, dfy, angast )
        class(ctf), intent(inout) :: self   !< instance
        real,       intent(in)    :: dfx    !< defocus x-axis (um)
        real,       intent(in)    :: dfy    !< defocus y-axis (um)
        real,       intent(in)    :: angast !< astigmatism (degrees)
        self%dfx    = (dfx*1.0e4)/self%smpd
        self%dfy    = (dfy*1.0e4)/self%smpd
        self%angast = deg2rad(angast)
    end subroutine init

    !>  \brief Returns the CTF, based on CTFFIND3 subroutine (see Mindell 2003)
    !
    ! How to use eval:
    !
    !            lFreqSq = tfun%getLowFreq4Fit**2
    !            hFreqSq = tfun%getHighFreq4Fit**2
    !            do k=-ydim,ydim
    !                kinv = inv_logical_kdim*real(k)
    !                kinvsq = kinv*kinv
    !                do h=-xdim,xdim
    !                   hinv = inv_logical_hdim*real(h)
    !                    hinvsq = hinv*hinv
    !                    spaFreqSq = kinvsq+hinvsq
    !                    if( spaFreqSq .gt. lFreqSq .and. spaFreqSq .le. hFreqSq )then
    !                        if( spaFreqSq .gt. 0. )then
    !                            ang = atan2(k,h)
    !                        else
    !                            ang = 0.
    !                        endif
    function eval_1( self, spaFreqSq, dfx, dfy, angast, ang ) result ( val )
        class(ctf), intent(inout) :: self      !< instance
        real,       intent(in)    :: spaFreqSq !< squared reciprocal pixels
        real,       intent(in)    :: dfx       !< Defocus along first axis (micrometers)
        real,       intent(in)    :: dfy       !< Defocus along second axis (for astigmatic CTF, dfx .ne. dfy) (micrometers)
        real,       intent(in)    :: angast    !< Azimuth of first axis. 0.0 means axis is at 3 o'clock. (radians)
        real,       intent(in)    :: ang       !< Angle at which to compute the CTF (radians)
        real :: val, phshift
        ! initialize the CTF object, using the input parameters
        call self%init(dfx, dfy, angast)
        ! compute phase shift
        phshift = self%evalPhSh(spaFreqSq, ang, 0.)
        ! compute value of CTF, assuming white particles
        val = (self%phaseq * sin(phshift) + self%ampliq * cos(phshift))
    end function eval_1

    function eval_2( self, spaFreqSq, dfx, dfy, angast, ang, add_phshift ) result ( val )
        class(ctf), intent(inout) :: self        !< instance
        real,       intent(in)    :: spaFreqSq   !< squared reciprocal pixels
        real,       intent(in)    :: dfx         !< Defocus along first axis (micrometers)
        real,       intent(in)    :: dfy         !< Defocus along second axis (for astigmatic CTF, dfx .ne. dfy) (micrometers)
        real,       intent(in)    :: angast      !< Azimuth of first axis. 0.0 means axis is at 3 o'clock. (radians)
        real,       intent(in)    :: ang         !< Angle at which to compute the CTF (radians)
        real,       intent(in)    :: add_phshift !< aditional phase shift (radians), for phase plate
        real :: val, phshift
        ! initialize the CTF object, using the input parameters
        call self%init(dfx, dfy, angast)
        ! compute phase shift
        phshift = self%evalPhSh(spaFreqSq, ang, add_phshift)
        ! compute value of CTF, assuming white particles
        val = (self%phaseq * sin(phshift) + self%ampliq * cos(phshift))
    end function eval_2

    !>  \brief Returns the CTF with pre-initialize parameters
    pure elemental real function eval_3( self, spaFreqSq, ang )
        class(ctf), intent(in) :: self        !< instance
        real,       intent(in) :: spaFreqSq   !< squared reciprocal pixels
        real,       intent(in) :: ang         !< Angle at which to compute the CTF (radians)
        real :: df, phshift
        ! compute DOUBLE the effective defocus
        df = (self%dfx + self%dfy + cos(2.0 * (ang - self%angast)) * (self%dfx - self%dfy))
        !! compute the ctf argument
        phshift = 0.5 * pi * self%wl * spaFreqSq * (df - self%wl * self%wl * spaFreqSq * self%Cs)
        ! compute value of CTF, assuming white particles
        eval_3 = (self%phaseq * sin(phshift) + self%ampliq * cos(phshift))
    end function eval_3

    !>  \brief Returns the CTF with pre-initialize parameters
    pure elemental real function eval_4( self, spaFreqSq, ang, add_phshift )
        class(ctf), intent(in) :: self        !< instance
        real,       intent(in) :: spaFreqSq   !< squared reciprocal pixels
        real,       intent(in) :: ang         !< Angle at which to compute the CTF (radians)
        real,       intent(in) :: add_phshift !< aditional phase shift (radians), for phase plate
        real :: df, phshift
        ! compute DOUBLE the effective defocus
        df      = (self%dfx + self%dfy + cos(2.0 * (ang - self%angast)) * (self%dfx - self%dfy))
        ! compute the ctf argument
        phshift = 0.5 * pi * self%wl * spaFreqSq * (df - self%wl * self%wl * spaFreqSq * self%Cs) + add_phshift
        ! compute value of CTF, assuming white particles
        eval_4  = (self%phaseq * sin(phshift) + self%ampliq * cos(phshift))
    end function eval_4

    !>  \brief returns the argument (radians) to the sine and cosine terms of the ctf
    !!
    !!  We follow the convention, like the rest of the cryo-EM/3DEM field, that underfocusing the objective lens
    !!  gives rise to a positive phase shift of scattered electrons, whereas the spherical aberration gives a
    !!  negative phase shift of scattered electrons
    pure elemental real function evalPhSh( self, spaFreqSq, ang, add_phshift ) result( phshift )
        class(ctf), intent(in) :: self        !< instance
        real,       intent(in) :: spaFreqSq   !< square of spatial frequency at which to compute the ctf (1/pixels^2)
        real,       intent(in) :: ang         !< angle at which to compute the ctf (radians)
        real,       intent(in) :: add_phshift !< aditional phase shift (radians), for phase plate
        real :: df                            !< defocus at point at which we're evaluating the ctf
        !! compute the defocus
        df = self%eval_df(ang)
        !! compute the ctf argument
        phshift = pi * self%wl * spaFreqSq * (df - 0.5 * self%wl * self%wl * spaFreqSq * self%Cs) + add_phshift
    end function evalPhSh

    !>  \brief  Return the effective defocus given the pre-set CTF parameters (from CTFFIND4)
    pure elemental real function eval_df( self, ang ) result (df)
        class(ctf), intent(in) :: self !< instance
        real,       intent(in) :: ang  !< angle at which to compute the defocus (radians)
        df = 0.5 * (self%dfx + self%dfy + cos(2.0 * (ang - self%angast)) * (self%dfx - self%dfy))
    end function eval_df

    !>  \brief  is for applying CTF to an image
    subroutine apply( self, img, dfx, mode, dfy, angast, bfac, add_phshift )
        use simple_image, only: image
        class(ctf),       intent(inout) :: self        !< instance
        class(image),     intent(inout) :: img         !< image (output)
        real,             intent(in)    :: dfx         !< defocus x-axis
        character(len=*), intent(in)    :: mode        !< abs, ctf, flip, flipneg, neg, square
        real, optional,   intent(in)    :: dfy         !< defocus y-axis
        real, optional,   intent(in)    :: angast      !< angle of astigmatism
        real, optional,   intent(in)    :: bfac        !< bfactor
        real, optional,   intent(in)    :: add_phshift !< aditional phase shift (radians), for phase plate
        integer         :: ldim(3), ldim_pd(3)
        type(ctfparams) :: ctfvars
        type(image)     :: img_pd
        ldim = img%get_ldim()
        if( img%is_3d() )then
            print *, 'ldim: ', ldim
            stop 'Only 4 2D images; apply; simple_ctf'
        endif
        ctfvars%smpd = self%smpd
        ctfvars%dfx  = dfx
        if(present(dfy))         ctfvars%dfy     = dfy
        if(present(angast))      ctfvars%angast  = angast
        if(present(add_phshift)) ctfvars%phshift = add_phshift
        if( img%is_ft() )then
            call self%apply_serial(img, mode, ctfvars)
        else
            ldim_pd(1:2) = 2*ldim(1:2)
            ldim_pd(3)   = 1
            call img_pd%new(ldim_pd, self%smpd)
            call img%pad_mirr(img_pd)
            call img_pd%fft()
            call self%apply_serial(img_pd, mode, ctfvars)
            call img_pd%ifft()
            call img_pd%clip(img)
            call img_pd%kill()
        endif
        if( present(bfac) ) call img%apply_bfac(bfac)
    end subroutine apply

    !>  \brief  is for generating an image of CTF
    subroutine ctf2img( self, img, dfx, dfy, angast, phshift )
        use simple_image, only: image
        class(ctf),       intent(inout) :: self  !< instance
        class(image),     intent(inout) :: img   !< image (output)
        real,             intent(in)    :: dfx, dfy, angast
        real,   optional, intent(in)    :: phshift
        integer :: lims(3,2),h,k,phys(3),ldim(3)
        real    :: ang,tval,spaFreqSq,hinv,kinv,inv_ldim(3),pphshift
        pphshift = 0.
        if( present(phshift) ) pphshift = phshift
        ! flag image as FT
        call img%set_ft(.true.)
        ! init object
        call self%init(dfx, dfy, angast)
        ! initialize
        lims     = img%loop_lims(2)
        ldim     = img%get_ldim()
        inv_ldim = 1./real(ldim)
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                hinv      = real(h) * inv_ldim(1)
                kinv      = real(k) * inv_ldim(2)
                spaFreqSq = hinv * hinv + kinv * kinv
                ang       = atan2(real(k),real(h))
                tval      = self%eval(spaFreqSq, ang, pphshift)
                phys      = img%comp_addr_phys([h,k,0])
                call img%set_cmat_at(phys(1),phys(2),phys(3), cmplx(tval,0.))
            end do
        end do
    end subroutine ctf2img

    !>  \brief  is for optimised serial application of CTF
    !!          modes: abs, ctf, flip, flipneg, neg, square
    subroutine apply_serial( self, img, mode, ctfparms )
        use simple_image, only: image
        class(ctf),       intent(inout) :: self        !< instance
        class(image),     intent(inout) :: img         !< image (output)
        character(len=*), intent(in)    :: mode        !< abs, ctf, flip, flipneg, neg, square
        type(ctfparams),  intent(in)    :: ctfparms    !< CTF parameters
        integer :: lims(3,2),h,k,phys(3),ldim(3)
        real    :: ang,tval,spaFreqSq,hinv,kinv,inv_ldim(3)
        ! init object
        call self%init(ctfparms%dfx, ctfparms%dfy, ctfparms%angast)
        ! initialize
        lims     = img%loop_lims(2)
        ldim     = img%get_ldim()
        inv_ldim = 1./real(ldim)
        select case(mode)
            case('abs')
                do h=lims(1,1),lims(1,2)
                    do k=lims(2,1),lims(2,2)
                        hinv      = real(h) * inv_ldim(1)
                        kinv      = real(k) * inv_ldim(2)
                        spaFreqSq = hinv * hinv + kinv * kinv
                        ang       = atan2(real(k),real(h))
                        tval      = self%eval(spaFreqSq, ang, ctfparms%phshift)
                        phys      = img%comp_addr_phys([h,k,0])
                        call img%mul_cmat_at(phys(1),phys(2),phys(3), abs(tval))
                    end do
                end do
            case('ctf')
                do h=lims(1,1),lims(1,2)
                    do k=lims(2,1),lims(2,2)
                        hinv      = real(h) * inv_ldim(1)
                        kinv      = real(k) * inv_ldim(2)
                        spaFreqSq = hinv * hinv + kinv * kinv
                        ang       = atan2(real(k),real(h))
                        tval      = self%eval(spaFreqSq, ang, ctfparms%phshift)
                        phys      = img%comp_addr_phys([h,k,0])
                        call img%mul_cmat_at(phys(1),phys(2),phys(3), tval)
                    end do
                end do
            case('flip')
                do h=lims(1,1),lims(1,2)
                    do k=lims(2,1),lims(2,2)
                        hinv      = real(h) * inv_ldim(1)
                        kinv      = real(k) * inv_ldim(2)
                        spaFreqSq = hinv * hinv + kinv * kinv
                        ang       = atan2(real(k),real(h))
                        tval      = self%eval(spaFreqSq, ang, ctfparms%phshift)
                        phys      = img%comp_addr_phys([h,k,0])
                        call img%mul_cmat_at(phys(1),phys(2),phys(3), sign(1.,tval))
                    end do
                end do
            case('flipneg')
                do h=lims(1,1),lims(1,2)
                    do k=lims(2,1),lims(2,2)
                        hinv      = real(h) * inv_ldim(1)
                        kinv      = real(k) * inv_ldim(2)
                        spaFreqSq = hinv * hinv + kinv * kinv
                        ang       = atan2(real(k),real(h))
                        tval      = self%eval(spaFreqSq, ang, ctfparms%phshift)
                        phys      = img%comp_addr_phys([h,k,0])
                        call img%mul_cmat_at(phys(1),phys(2),phys(3), -sign(1.,tval))
                    end do
                end do
            case('neg')
                do h=lims(1,1),lims(1,2)
                    do k=lims(2,1),lims(2,2)
                        hinv      = real(h) * inv_ldim(1)
                        kinv      = real(k) * inv_ldim(2)
                        spaFreqSq = hinv * hinv + kinv * kinv
                        ang       = atan2(real(k),real(h))
                        tval      = self%eval(spaFreqSq, ang, ctfparms%phshift)
                        phys      = img%comp_addr_phys([h,k,0])
                        call img%mul_cmat_at( phys(1),phys(2),phys(3), -tval)
                    end do
                end do
            case('square')
                do h=lims(1,1),lims(1,2)
                    do k=lims(2,1),lims(2,2)
                        hinv      = real(h) * inv_ldim(1)
                        kinv      = real(k) * inv_ldim(2)
                        spaFreqSq = hinv * hinv + kinv * kinv
                        ang       = atan2(real(k),real(h))
                        tval      = self%eval(spaFreqSq, ang, ctfparms%phshift)
                        phys      = img%comp_addr_phys([h,k,0])
                        call img%mul_cmat_at( phys(1),phys(2),phys(3), min(1.,max(tval**2.,0.001)))
                    end do
                end do
            case DEFAULT
                write(*,*) 'mode:', mode
                stop 'unsupported in ctf2img; simple_ctf'
        end select
    end subroutine apply_serial

    !>  \brief  is for optimised serial phase-flipping & shifting for use in prepimg4align
    subroutine phaseflip_and_shift_serial( self, img, x, y, ctfparms )
        use simple_image, only: image
        class(ctf),       intent(inout) :: self        !< instance
        class(image),     intent(inout) :: img         !< image (output)
        real,             intent(in)    :: x, y        !< defocus x/y-axis
        type(ctfparams),  intent(in)    :: ctfparms
        integer :: lims(3,2),h,k,phys(3),ldim(3), logi(3)
        real    :: ang,tval,spaFreqSq,hinv,kinv,inv_ldim(3)
        ! init object
        call self%init(ctfparms%dfx, ctfparms%dfy, ctfparms%angast)
        ! initialize
        lims     = img%loop_lims(2)
        ldim     = img%get_ldim()
        inv_ldim = 1./real(ldim)
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                hinv      = real(h) * inv_ldim(1)
                kinv      = real(k) * inv_ldim(2)
                spaFreqSq = hinv * hinv + kinv * kinv
                ang       = atan2(real(k),real(h))
                tval      = self%eval(spaFreqSq, ang, ctfparms%phshift)
                logi      = [h, k, 0]
                phys      = img%comp_addr_phys(logi)
                call img%mul_cmat_at(phys, sign(1.,tval))
                call img%mul_cmat_at(phys, img%oshift(real(logi),[x,y,0.]))
            end do
        end do
    end subroutine phaseflip_and_shift_serial

    !>  \brief  is for applying CTF to an image and shifting it (used in classaverager)
    !!          KEEP THIS ROUTINE SERIAL
    subroutine apply_and_shift( self, img, imode, lims, rho, x, y, dfx, dfy, angast, add_phshift, bfac)
        use simple_image, only: image
        class(ctf),     intent(inout) :: self        !< instance
        class(image),   intent(inout) :: img         !< modified image (output)
        integer,        intent(in)    :: imode       !< 1=abs 2=ctf 3=no
        integer,        intent(in)    :: lims(3,2)   !< loop limits
        real,           intent(out)   :: rho(lims(1,1):lims(1,2),lims(2,1):lims(2,2))
        real,           intent(in)    :: x, y        !< rotational origin shift
        real,           intent(in)    :: dfx         !< defocus x-axis
        real,           intent(in)    :: dfy         !< defocus y-axis
        real,           intent(in)    :: angast      !< angle of astigmatism
        real,           intent(in)    :: add_phshift !< aditional phase shift (radians), for phase plate
        real, optional, intent(in)    :: bfac        !< ctf b-factor weighing
        integer :: ldim(3),logi(3),h,k,phys(3)
        real    :: ang,tval,spaFreqSq,hinv,kinv,inv_ldim(3)
        real    :: rnyq_sq,bfacw_nyq,rh,rk,sh_sq,bfac_sc
        logical :: do_bfac
        do_bfac = present(bfac)
        ! initialize
        call self%init(dfx, dfy, angast)
        ldim     = img%get_ldim()
        inv_ldim = 1./real(ldim)
        rnyq_sq  = real(img%get_nyq()**2)
        if( do_bfac )then
            if(bfac > TINY)then
                bfac_sc   = bfac/4.
                bfacw_nyq = exp(-bfac_sc)
            else
                do_bfac = .false.
            endif
        endif
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                rh    = real(h)
                rk    = real(k)
                sh_sq = real(h*h+k*k)
                ! calculate CTF and CTF**2.0 values
                hinv      = rh * inv_ldim(1)
                kinv      = rk * inv_ldim(2)
                spaFreqSq = hinv*hinv + kinv*kinv
                ang       = atan2(rh,rk)
                tval      = 1.0
                if( imode <  3 ) tval = self%eval(spaFreqSq, ang, add_phshift)
                ! rho
                rho(h,k) = tval * tval
                if( imode == 1 ) tval = abs(tval)
                ! multiply image with tval & weight
                logi   = [h,k,0]
                phys   = img%comp_addr_phys(logi)
                if( do_bfac )then
                    if( sh_sq > rnyq_sq )then
                        tval = tval * bfacw_nyq
                    else
                        tval = tval * exp(-bfac_sc*sh_sq/rnyq_sq)
                    endif
                endif
                call img%mul_cmat_at(phys(1),phys(2),phys(3), tval)
                ! shift image
                call img%mul_cmat_at(phys(1),phys(2),phys(3), img%oshift(logi,[x,y,0.]))
            end do
        end do
    end subroutine apply_and_shift

    pure elemental real function kV2wl( self ) result (wavelength)
        class(ctf), intent(in) :: self
        wavelength = 12.26 / sqrt((1000.0 * self%kV) + (0.9784*(1000.0 * self%kV)**2)/(10.0**6.0))
    end function kV2wl

end module simple_ctf

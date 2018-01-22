module simple_ctffit
#include "simple_lib.f08"
use simple_image,       only: image
use simple_ctf,         only: ctf
use simple_opt_spec,    only: opt_spec
use simple_de_opt,      only: de_opt
use simple_simplex_opt, only: simplex_opt
implicit none

public :: ctffit_init, ctffit_srch, ctffit_validate, ctffit_kill
private

type(image)           :: pspec_ref               ! micrograph powerspec
type(image)           :: pspec_ctf               ! CTF powerspec
type(image)           :: imgmsk                  ! mask image
type(ctf)             :: tfun                    ! transfer function object
type(opt_spec)        :: ospec_de                ! optimiser specification differential evolution (DE)
type(opt_spec)        :: ospec_simplex           ! optimiser specification Nelder-Mead (N-M)
type(de_opt)          :: diffevol                ! DE search object
type(simplex_opt)     :: simplexsrch             ! N-M search object
logical, allocatable  :: cc_msk(:,:,:)           ! corr mask
logical               :: l_phaseplate = .false.  ! Volta phase-plate flag
integer               :: ndim         = 3        ! # optimisation dims
integer               :: ldim(3)      = [0,0,0]  ! logical dimension of powerspec
real                  :: df_min       = 0.5      ! close 2 focus limit
real                  :: df_max       = 5.0      ! far from focus limit
real                  :: hp           = 30.0     ! high-pass limit
real                  :: lp           = 5.0      ! low-pass limit
real                  :: sxx          = 0.       ! memoized corr term
real                  :: fny                     ! Nyqvist frequency
real                  :: dfx_glob                ! dfx,     global
real                  :: dfy_glob                ! dfy,     global
real                  :: angast_glob             ! angast,  global
real                  :: phshift_glob            ! phshift, global

contains

    subroutine ctffit_init( pspec, smpd, kV, Cs, amp_contr, dfrange, resrange, phaseplate )
        class(image),     intent(in) :: pspec       !< powerspectrum
        real,             intent(in) :: smpd        !< sampling distance
        real,             intent(in) :: kV          !< acceleration voltage
        real,             intent(in) :: Cs          !< constant
        real,             intent(in) :: amp_contr   !< amplitude contrast
        real,             intent(in) :: dfrange(2)  !< defocus range, [30.0,5.0] default
        real,             intent(in) :: resrange(2) !< resolution range, [30.0,5.0] default
        character(len=*), intent(in) :: phaseplate  !< Volta phase-plate images (yes|no)
        real :: limits(4,2)
        ! set constants
        if( dfrange(1) < dfrange(2) )then
            df_min = dfrange(1)
            df_max = dfrange(2)
        else
            stop 'invalid defocus range; simple_ctffit :: new'
        endif
        if( resrange(1) > resrange(2) )then
            hp = resrange(1)
            lp = resrange(2)
        else
            stop 'invalid resolution range; simple_ctffit :: new'
        endif
        select case(trim(phaseplate))
            case('yes')
                l_phaseplate = .true.
                ndim         = 4
            case DEFAULT
                l_phaseplate = .false.
                ndim         = 3
        end select
        ! construct CTF object
        tfun = ctf(smpd, kV, Cs, amp_contr)
        fny  = smpd * 2
        ! prepare powerspectra
        pspec_ref = pspec
        ldim = pspec_ref%get_ldim()
        call pspec_ref%dampen_central_cross
        call pspec_ref%subtr_backgr(hp)
        call pspec_ctf%new(ldim, smpd)
        ! generate correlation mask
        call imgmsk%new(ldim, smpd)
        call imgmsk%resmsk(hp, lp)
        cc_msk = imgmsk%bin2logical()
        ! memoize reference corr components
        call pspec_ref%prenorm4real_corr(sxx, cc_msk)
        ! contruct optimiser
        call seed_rnd
        limits        = 0.
        limits(1:2,1) = df_min
        limits(1:2,2) = df_max
        limits(3,1)   = 0.
        limits(3,2)   = twopi ! miminise in radians so that the df:s are roughly on the same scale
        if( l_phaseplate )then
            limits(4,1)   = 0.
            limits(4,2)   = 3.15 ! little over pi as max lim
        endif
        call ospec_de%specify('de', ndim, limits=limits(1:ndim,:), maxits=400)
        call ospec_simplex%specify('simplex', ndim, limits=limits(1:ndim,:), maxits=80, nrestarts=5)
        if( l_phaseplate )then
            call ospec_de%set_costfun(ctffit_cost_phaseplate)
            call ospec_simplex%set_costfun(ctffit_cost_phaseplate)
        else
            call ospec_de%set_costfun(ctffit_cost)
            call ospec_simplex%set_costfun(ctffit_cost)
        endif
        call diffevol%new(ospec_de)
        call simplexsrch%new(ospec_de)
    end subroutine ctffit_init

    subroutine ctffit_srch( dfx, dfy, angast, phshift, cc, diagfname )
        real,             intent(out) :: dfx, dfy, angast, phshift, cc
        character(len=*), intent(in)  :: diagfname
        real              :: cost, df, df_step, cost_lowest, dfstep
        real, allocatable :: frc(:)
        type(image)       :: pspec_half_n_half
        integer           :: find, hpind, nyq, k
        class(*), pointer :: fun_self => null()
        dfstep = (df_max - df_min) / 100.
        if( l_phaseplate )then
            ! do a first grid search assuming no astigmatism
            ! and pi half phase shift
            df = df_min
            cost_lowest = ctffit_cost_phaseplate(fun_self, [df,df,0.,PIO2], ndim)
            do while( df <= df_max )
                cost = ctffit_cost_phaseplate(fun_self, [df,df,0.,PIO2], ndim)
                if( cost < cost_lowest )then
                    cost_lowest = cost
                    ospec_de%x  = [df,df,0.,PIO2]
                endif
                df = df + dfstep
            end do
        else
            ! do a first grid search assuming no astigmatism
            df = df_min
            cost_lowest = ctffit_cost(fun_self, [df,df,0.], ndim)
            do while( df <= df_max )
                cost = ctffit_cost(fun_self, [df,df,0.], ndim)
                if( cost < cost_lowest )then
                    cost_lowest = cost
                    ospec_de%x  = [df,df,0.]
                endif
                df = df + dfstep
            end do
        endif
        ! refinement by DE (Differential Evolution)
        call diffevol%minimize(ospec_de, fun_self, cost)
        dfx     = ospec_de%x(1)
        dfy     = ospec_de%x(2)
        angast  = rad2deg(ospec_de%x(3))
        cc      = -cost
        phshift = 0.
        if( l_phaseplate ) phshift = ospec_de%x(4)
        ! additional refinement with unconstrained Nelder-Mead: critical to accuracy
        ospec_simplex%x = ospec_de%x
        call simplexsrch%minimize(ospec_simplex, fun_self, cost)
        ! report solution
        dfx     = ospec_simplex%x(1)
        dfy     = ospec_simplex%x(2)
        angast  = rad2deg(ospec_simplex%x(3))
        cc      = -cost
        phshift = 0.
        if( l_phaseplate ) phshift = ospec_simplex%x(4)
        dfx_glob     = dfx
        dfy_glob     = dfy
        angast_glob  = angast
        phshift_glob = phshift
        ! make a half-n-half diagnostic
        call pspec_ctf%norm
        call pspec_ref%norm
        call pspec_ctf%mul(imgmsk)
        call pspec_ref%mul(imgmsk)
        pspec_half_n_half = pspec_ref%before_after(pspec_ctf)
        call pspec_half_n_half%write(trim(diagfname), 1)
        call pspec_half_n_half%kill
    end subroutine ctffit_srch

    subroutine ctffit_validate( even_imgs, odd_imgs, ccvalid )
        class(image), intent(inout) :: even_imgs(:), odd_imgs(:)
        real,         intent(out)   :: ccvalid
        real, allocatable :: corrs(:), res(:)
        type(image) :: even_sum, odd_sum, tmp
        integer     :: filtsz, ldim(3), i, neven, nodd
        real        :: smpd
        neven = size(even_imgs)
        nodd  = size(odd_imgs)
        ldim  = even_imgs(1)%get_ldim()
        smpd  = even_imgs(1)%get_smpd()
        call even_sum%new(ldim, smpd)
        call odd_sum%new(ldim, smpd)
        ! calculate even power-spectrum without applying phase flipping
        do i=1,neven
            call even_imgs(i)%fwd_ft
            call even_imgs(i)%ft2img('sqrt', tmp)
            call even_sum%add(tmp)
        end do
        ! calculate odd power-spectrum applying phase flipping with the estimated CTF params
        do i=1,nodd
            call tfun%apply(odd_imgs(i), dfx_glob, 'flip', dfy_glob, angast_glob, phshift_glob)
            call odd_imgs(i)%ft2img('sqrt', tmp)
            call odd_sum%add(tmp)
        end do
        ! calculate correlation for validation of both image quality and CTF fit
        call even_sum%norm
        call odd_sum%norm
        ccvalid = even_sum%real_corr(odd_sum, cc_msk)
    end subroutine ctffit_validate

    ! cost function is real-space correlation within resolution mask between the CTF
    ! powerspectrum (the model) and the pre-processed micrograph powerspectrum (the data)
    function ctffit_cost( fun_self, vec, D ) result( cost )
        class(*), intent(inout) :: fun_self
        integer,  intent(in)    :: D
        real,     intent(in)    :: vec(D)
        real                    :: cost
        call tfun%ctf2pspecimg(pspec_ctf, vec(1), vec(2), rad2deg(vec(3)))
        cost = -pspec_ref%real_corr_prenorm(pspec_ctf, sxx, cc_msk)
    end function ctffit_cost

    ! cost function is real-space correlation within resolution mask between the CTF
    ! powerspectrum (the model) and the pre-processed micrograph powerspectrum (the data)
    function ctffit_cost_phaseplate( fun_self, vec, D ) result( cost )
        class(*), intent(inout) :: fun_self
        integer,  intent(in)    :: D
        real,     intent(in)    :: vec(D)
        real :: cost
        ! vec(4) is additional phase shift (in radians)
        call tfun%ctf2pspecimg(pspec_ctf, vec(1), vec(2), rad2deg(vec(3)), vec(4))
        cost = -pspec_ref%real_corr_prenorm(pspec_ctf, sxx, cc_msk)
    end function ctffit_cost_phaseplate

    subroutine ctffit_kill
        call pspec_ref%kill
        call pspec_ctf%kill
        call ospec_de%kill
        call ospec_simplex%kill
        call diffevol%kill
        call simplexsrch%kill
        call imgmsk%kill
        if( allocated(cc_msk) ) deallocate(cc_msk)
    end subroutine ctffit_kill

end module simple_ctffit

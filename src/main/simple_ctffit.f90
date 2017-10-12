module simple_ctffit
#include "simple_lib.f08"
use simple_image,       only: image
use simple_ctf,         only: ctf
use simple_opt_spec,    only: opt_spec
use simple_de_opt,      only: de_opt
use simple_simplex_opt, only: simplex_opt
implicit none

public :: ctffit_init, ctffit_srch, ctffit_kill
private

type(image)          :: pspec_ref
type(image)          :: pspec_ctf
type(image)          :: imgmsk
type(ctf)            :: tfun
type(opt_spec)       :: ospec_de
type(opt_spec)       :: ospec_simplex
type(de_opt)         :: diffevol
type(simplex_opt)    :: simplexsrch
logical, allocatable :: cc_msk(:,:,:)
integer              :: ldim(3) = [0,0,0]
real                 :: df_min  = 0.5
real                 :: df_max  = 5.0
real                 :: hp      = 30.0
real                 :: lp      = 5.0
real                 :: sxx     = 0. 

contains

  	subroutine ctffit_init( pspec, smpd, kV, Cs, amp_contr, dfrange, resrange )
        class(image),   intent(in) :: pspec       !< powerspectrum
        real,           intent(in) :: smpd        !< sampling distance
        real,           intent(in) :: kV          !< acceleration voltage
        real,           intent(in) :: Cs          !< constant
        real,           intent(in) :: amp_contr   !< amplitude contrast
        real, optional, intent(in) :: dfrange(2)  !< defocus range, [30.0,5.0] default
        real, optional, intent(in) :: resrange(2) !< resolution range, [30.0,5.0] default
        
        real        :: limits(3,2)
        ! set constants
        if( present(dfrange) )then
            if( dfrange(1) < dfrange(2) )then
        		df_min = dfrange(1)
        		df_max = dfrange(2)
            else
                stop 'invalid defocuis range; simple_ctffit :: new'
            endif
        endif
        if( present(resrange) )then
          	if( resrange(1) > resrange(2) )then
          		hp = resrange(1)
          		lp = resrange(2)
          	else
          		stop 'invalid resolution range; simple_ctffit :: new'
          	endif
        endif
        ! construct CTF object
        tfun = ctf(smpd, kV, Cs, amp_contr)
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
        limits(1:2,1) = df_min
        limits(1:2,2) = df_max
        limits(3,1)   = 0.
        limits(3,2)   = twopi ! miminise in radians so that the df:s are roughly on the same scale
        call ospec_de%specify('de', 3, limits=limits, maxits=400)
        call ospec_de%set_costfun(ctffit_cost)
        call diffevol%new(ospec_de)
        call ospec_simplex%specify('simplex', 3, limits=limits, maxits=60, nrestarts=3)
        call ospec_simplex%set_costfun(ctffit_cost)
        call simplexsrch%new(ospec_de)
  	end subroutine ctffit_init

  	subroutine ctffit_srch( dfx, dfy, angast, cc, diagfname )
		real,             intent(out) :: dfx, dfy, angast, cc
        character(len=*), intent(in)  :: diagfname
		real        :: cost, df, cost_lowest
        type(image) :: pspec_half_n_half



        ! do a grid search assuming no astigmatism
        df = df_min

        cost_lowest =  ctffit_cost([df,df,0.], 3)
        do while( df <= df_max )
            cost = ctffit_cost([df,df,0.], 3)
            if( cost < cost_lowest )then
                cost_lowest = cost
                ospec_de%x  = [df,df,0.]
            endif
            df = df + 0.05
        end do


        ! optimisation by DE (Differential Evolution)
		call diffevol%minimize(ospec_de, cost)

        dfx    = ospec_de%x(1)
        dfy    = ospec_de%x(2)
        angast = rad2deg(ospec_de%x(3))
        cc     = -cost

        ! refinement with unconstrained Nelder-Mead
        ! ospec_simplex%x = ospec_de%x
        ! call simplexsrch%minimize(ospec_simplex, cost)
        ! ! report solution
        ! dfx    = ospec_simplex%x(1)
        ! dfy    = ospec_simplex%x(2)
        ! angast = rad2deg(ospec_simplex%x(3))
        ! cc     = -cost
        ! make a half-n-half diagnostic
        call tfun%ctf2pspecimg(pspec_ctf, dfx, dfy, angast)
        call pspec_ctf%norm
        call pspec_ref%norm
        call pspec_ctf%mul(imgmsk)
        call pspec_ref%mul(imgmsk)
        pspec_half_n_half = pspec_ref%before_after(pspec_ctf)
        call pspec_half_n_half%write(trim(diagfname), 1)
        call pspec_half_n_half%kill
  	end subroutine ctffit_srch

    ! cost function is real-space correlation within resolution mask between the CTF
    ! powerspectrum (the model) and the pre-processed micrograph powerspectrum (the data)
  	function ctffit_cost( vec, D ) result( cost )
		integer, intent(in) :: D
		real,    intent(in) :: vec(D)
		real :: cost
		call tfun%ctf2pspecimg(pspec_ctf, vec(1), vec(2), rad2deg(vec(3)))
		cost = -pspec_ref%real_corr_prenorm(pspec_ctf, sxx, cc_msk)
  	end function ctffit_cost

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
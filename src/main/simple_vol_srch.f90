! Cartesian volume-volume alignment based on band-pass limited cross-correlation
module simple_vol_srch
include 'simple_lib.f08'
use simple_image,       only: image
use simple_opt_spec,    only: opt_spec
use simple_opt_simplex, only: opt_simplex
use simple_projector,   only: projector
implicit none

public :: vol_srch_init, vol_shsrch_minimize
private

type(opt_spec)        :: ospec           !< optimizer specification object
type(opt_simplex)     :: nlopt           !< optimizer object
integer               :: nrestarts = 3   !< simplex restarts (randomized bounds)
real                  :: hp, lp, trs     !< srch ctrl params
class(image), pointer :: vref => null()  !< reference volume
class(image), pointer :: vtarg => null() !< target volume (subjected to shift)

contains

    subroutine vol_srch_init( vol_ref, vol_target, hp_in, lp_in, trs_in, nrestarts_in )
        use simple_ori, only: ori
        class(image), target, intent(inout) :: vol_ref, vol_target
        real,                 intent(in)    :: hp_in, lp_in, trs_in
        integer, optional, intent(in)       :: nrestarts_in
        integer :: ldim(3), ldim_pd(3), boxpd
        real    :: smpd, lims(3,2), eul(3)
        hp  = hp_in
        lp  = lp_in
        trs = max(3.,trs_in)
        nrestarts = 3
        if( present(nrestarts_in) ) nrestarts = nrestarts_in
        vref  => vol_ref
        vtarg => vol_target
        lims(1:3,1) = -trs
        lims(1:3,2) =  trs
        call ospec%specify('simplex', 3, ftol=1e-4,&
        &gtol=1e-4, limits=lims, nrestarts=nrestarts, maxits=30)
        call ospec%set_costfun(vol_shsrch_costfun)
        call nlopt%new(ospec)
    end subroutine vol_srch_init

    function vol_shsrch_costfun( fun_self, vec, D ) result( cost )
        class(*), intent(inout) :: fun_self
        integer,  intent(in)    :: D
        real,     intent(in)    :: vec(D)
        real :: cost
        cost = - vref%corr_shifted(vtarg, vec(1:3), lp, hp)
    end function vol_shsrch_costfun

    function vol_shsrch_minimize( ) result( cxyz )
        real              :: cost_init, cost, cxyz(4)
        class(*), pointer :: fun_self => null()
        ospec%x   = 0. ! assumed that vol is shifted to previous centre
        cost_init = vol_shsrch_costfun(fun_self, ospec%x, ospec%ndim)
        call nlopt%minimize(ospec, fun_self, cost)
        if( cost < cost_init )then
            cxyz(1)  = -cost    ! correlation
            cxyz(2:) =  ospec%x ! shift
        else
            cxyz(1)  = -1.      ! to indicate that better solution wasn't found
            cxyz(2:) =  0.
        endif
    end function vol_shsrch_minimize

end module simple_vol_srch
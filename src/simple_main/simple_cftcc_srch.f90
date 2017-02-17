module simple_cftcc_srch
use simple_opt_factory,     only: opt_factory
use simple_opt_spec,        only: opt_spec
use simple_optimizer,       only: optimizer
use simple_cartft_corrcalc, only: cartft_corrcalc
use simple_image,           only: image
use simple_ori,             only: ori
use simple_sym,             only: sym
use simple_defs
implicit none

public :: cftcc_srch_init, cftcc_srch_set_state, cftcc_srch_minimize
private

type(opt_factory)               :: ofac              !< optimizer factory
type(opt_spec)                  :: ospec             !< optimizer specification object
class(optimizer), pointer       :: nlopt=>null()     !< pointer to nonlinear optimizer
class(cartft_corrcalc), pointer :: cftcc_ptr=>null() !< pointer to cftcc object
class(image), pointer           :: pimg=>null()      !< pointer to image
integer                         :: state=1           !< state to evaluate
type(ori)                       :: o_glob            !< global orientation

contains

    subroutine cftcc_srch_init( cftcc, img, opt_str, lims, nrestarts, syme )
        class(cartft_corrcalc), target, intent(in) :: cftcc
        class(image),           target, intent(in) :: img
        character(len=*),               intent(in) :: opt_str
        real,                           intent(in) :: lims(5,2)
        integer,                        intent(in) :: nrestarts
        class(sym),           optional, intent(inout) :: syme
        real :: lims_here(5,2)
        ! make optimizer spec
        if( present(syme) )then
            lims_here(1:3,:) = syme%srchrange()
            lims_here(4:5,:) = lims(4:5,:)
        else
            lims_here = lims
        endif
        call ospec%specify(opt_str, 5, ftol=1e-4, gtol=1e-4, limits=lims_here, nrestarts=nrestarts)
        ! set optimizer cost function
        call ospec%set_costfun(cftcc_srch_cost)
        ! generate optimizer object with the factory
        call ofac%new(ospec, nlopt)
        ! set pointers
        cftcc_ptr => cftcc
        pimg      => img
    end subroutine cftcc_srch_init
    
    subroutine cftcc_srch_set_state( state_in )
        integer, intent(in) :: state_in
        state = state_in
    end subroutine cftcc_srch_set_state
    
    function cftcc_srch_get_nevals() result( nevals )
        integer :: nevals
        nevals = ospec%nevals
    end function cftcc_srch_get_nevals
    
    function cftcc_srch_cost( vec, D ) result( cost )
        use simple_ori, only: ori
        integer, intent(in) :: D
        real,    intent(in) :: vec(D)
        type(ori) :: o
        real      :: cost, shvec(3)
        integer   :: i
        ! enforce the barrier constraint for the shifts
        do i=4,5
            if( vec(i) < ospec%limits(i,1) .or. vec(i) > ospec%limits(i,2) )then
                cost = 1.
                return
            endif
        end do
        ! calculate cost
        o = o_glob
        call o%set_euler(vec(1:3))
        shvec(1) = vec(4)
        shvec(2) = vec(5)
        shvec(3) = 0.0
        call o%set('state', real(state))
        call cftcc_ptr%project(o, 1)
        cost = -cftcc_ptr%correlate(pimg, 1, shvec)
    end function cftcc_srch_cost
    
    subroutine cftcc_srch_minimize( o )
        use simple_math, only: rad2deg, rotmat2d
        class(ori), intent(inout) :: o
        real :: corr, cost, x_prev, y_prev, dist, corr_prev
        real :: rotmat(2,2), shvec(2), prev_shvec(2)
        prev_shvec = o%get_shift()
        call o%e3set( 360. - o%e3get() )
        ! copy the input orientation
        o_glob = o
        ! initialise optimiser
        ospec%x = 0.
        ospec%x(1:3) = o%get_euler()
        ! search
        call nlopt%minimize(ospec, cost)
        ! report
        corr = -cost
        call o%set('corr', corr)
        call o%set_euler(ospec%x(1:3))
        call o%e3set( 360. - o%e3get() )
        ! shifts must be obtained by vector addition after in-plane rotation
        shvec  = -ospec%x(4:5)
        rotmat = rotmat2d(ospec%x(3)) 
        shvec  = prev_shvec + matmul(shvec, rotmat)
        call o%set_shift( shvec )
        ! distance
        dist = 0.5*rad2deg(o_glob.euldist.o)+0.5*o_glob%get('dist')
        call o%set('dist',dist)
    end subroutine cftcc_srch_minimize

end module simple_cftcc_srch

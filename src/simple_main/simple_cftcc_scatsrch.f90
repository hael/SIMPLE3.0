!------------------------------------------------------------------------------!
! SIMPLE v2.5         Elmlund & Elmlund Lab          simplecryoem.com          !
!------------------------------------------------------------------------------!
!> Simple CTF module: scattered search 
module simple_cftcc_scatsrch
use simple_scatter_orisrch, only: scatter_orisrch
use simple_cartft_corrcalc, only: cartft_corrcalc
use simple_oris,            only: oris
use simple_ori,             only: ori
use simple_image,           only: image
use simple_defs
implicit none

public :: cftcc_scatsrch_init, cftcc_scatsrch_set_state, cftcc_scatsrch_minimize
private

class(cartft_corrcalc), pointer :: cftcc_ptr=>null() !< pointer to cftcc object
type(scatter_orisrch)           :: oscat             !< scatter search object
type(oris)                      :: pool              !< pool of orientations
class(image), pointer           :: pimg=>null()      !< pointer to image
integer                         :: state=1           !< state to evaluate
integer                         :: nevals=0          !< nr of score fun evals

contains
    !< Initialise search
    subroutine cftcc_scatsrch_init( cftcc, img, opt_str, lims, nrestarts )
        class(cartft_corrcalc), intent(in), target :: cftcc
        class(image), intent(in), target           :: img
        character(len=*), intent(in)               :: opt_str
        real, intent(in)                           :: lims(5,2)
        integer, intent(in)                        :: nrestarts
        ! make optimizer spec
        call ospec%specify(opt_str, 5, ftol=1e-4, gtol=1e-4, limits=lims, nrestarts=nrestarts)
        ! set optimizer cost function
        call ospec%set_costfun(cftcc_srch_cost)
        ! generate optimizer object with the factory
        call ofac%new(ospec, nlopt)
        ! set pointers
        cftcc_ptr => cftcc
        pimg      => img
    end subroutine cftcc_scatsrch_init
    
    subroutine cftcc_scatsrch_set_state( state_in )
        integer, intent(in) :: state_in
        state = state_in
    end subroutine cftcc_scatsrch_set_state
    
    function cftcc_scatsrch_get_nevals() result( nevals_out )
        integer :: nevals
        nevals_out = nevals
    end function cftcc_scatsrch_get_nevals
    !< Scattered search cost function
    function cftcc_scatsrch_cost( vec, D ) result( cost )
        use simple_ori, only: ori
        integer, intent(in) :: D
        real, intent(in)    :: vec(D)
        type(ori)           :: o
        real                :: cost, shvec(3)
        integer             :: i
        ! enfoce the barrier constraint for the shifts
        do i=4,5
            if( vec(i) < ospec%limits(i,1) .or. vec(i) > ospec%limits(i,2) )then
                cost = 1.
                return
            endif
        end do
        ! calculate cost
        call o%new 
        call o%set_euler(vec(1:3))
        shvec(1) = vec(4)
        shvec(2) = vec(5)
        shvec(3) = 0.0
        call o%set('state', real(state))
        call cftcc_ptr%project(o, 1)
        cost = -cftcc_ptr%correlate(pimg, 1, shvec)
    end function cftcc_scatsrch_cost
    !< Scattered search minimize
    subroutine cftcc_scatsrch_minimize( o )
        use simple_ori,  only: ori
        use simple_math, only: rad2deg
        class(ori), intent(inout) :: o
        type(ori)                 :: o_prev
        real                      :: corr, cost, x_prev, y_prev, dist
        ! copy the input orientation
        x_prev = o%get('x')
        y_prev = o%get('y')
        o_prev  = o
        ! initialise optimiser
        ospec%x = 0.
        ospec%x(1:3) = o%get_euler()
        ! search
        call nlopt%minimize(ospec, cost)
        ! report
        corr = -cost
        call o%set('corr', corr)
        call o%set_euler(ospec%x(1:3))
        ! shifts must be obtained by vector addition
        call o%set('x', ospec%x(4)+x_prev)
        call o%set('y', ospec%x(5)+y_prev)
        dist = 0.5*rad2deg(o_prev.euldist.o)+0.5*o_prev%get('dist')
        call o%set('dist',dist)
    end subroutine cftcc_scatsrch_minimize

end module simple_cftcc_scatsrch

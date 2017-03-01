module simple_cftcc_srch
use simple_opt_factory,     only: opt_factory
use simple_opt_spec,        only: opt_spec
use simple_optimizer,       only: optimizer
use simple_cartft_corrcalc, only: cartft_corrcalc
use simple_image,           only: image
use simple_ori,             only: ori
use simple_oris,            only: oris
use simple_sym,             only: sym
use simple_defs
implicit none

public :: cftcc_srch_init, cftcc_srch_set_state, cftcc_srch_minimize
private

type(opt_factory)               :: ofac              !< optimizer factory
type(opt_spec)                  :: ospec             !< optimizer specification object
class(optimizer), pointer       :: nlopt    =>null() !< pointer to nonlinear optimizer
class(cartft_corrcalc), pointer :: cftcc_ptr=>null() !< pointer to cftcc object
class(image), pointer           :: pimg     =>null() !< pointer to image
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
        use simple_math, only: rad2deg
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
        shvec(1:2) = vec(4:5)
        shvec(3)   = 0.0
        call o%set('state', real(state))
        call cftcc_ptr%project(o, 1)     
        cost = -cftcc_ptr%correlate(pimg, 1, shvec)
    end function cftcc_srch_cost
    
    subroutine cftcc_srch_minimize( o, os )
        use simple_math, only: rad2deg
        class(ori),  intent(inout) :: o
        class(oris), intent(inout) :: os
        real, allocatable :: vertices(:,:), costs(:)
        type(ori) :: o_new
        real      :: corr, cost, dist, prev_shvec(2), wcorr
        integer   :: i
        prev_shvec = o%get_shift()
        ! copy the input orientation
        o_glob = o
        ! initialise optimiser to current projdir & in-plane rotation
        ospec%x = 0.
        ospec%x(1:3) = o%get_euler()
        ! search
        call nlopt%minimize(ospec, cost)
        if( ospec%str_opt.eq.'simplex')then
            ! soft matching
            o_new = o
            call nlopt%get_vertices( ospec, vertices, costs )
            call os%new(6)
            do i = 1,6
                o_new = o
                call o_new%set('corr', -costs(i))
                call o_new%set_euler(vertices(i,1:3))
                call o_new%set_shift(prev_shvec-vertices(i,4:5))
                call os%set_ori(i, o_new)
            enddo
            call prep_soft_oris( wcorr, os )
            corr = wcorr
            call o%set('ow', os%get(1,'ow'))
            deallocate(vertices, costs)
        else
            ! hard matching
            corr = -cost
            call o%set('ow', 1.)
        endif
        ! report
        call o%set('corr', corr)
        call o%set_euler(ospec%x(1:3))
        ! shifts must be obtained by vector addition
        ! the reference is rotated upon projection
        ! the ptcl is shifted only: no need to rotate the shift
        call o%set_shift( prev_shvec - ospec%x(4:5) )
        ! distance
        dist = 0.5*rad2deg(o_glob.euldist.o)+0.5*rad2deg(o_glob.inpldist.o)
        call o%set('dist',dist)
        ! set the overlaps
        call o%set('mi_class', 1.)
        call o%set('mi_inpl',  1.) ! todo
        call o%set('mi_state', 1.)
        call o%set('mi_joint', 1.)  !todo
        call o%set('dist_inpl', 0.) ! todo
        ! all the other stuff
        call o%set( 'frac',  100. ) ! todo
        call o%set( 'mirr',  0. )
        call o%set( 'sdev',  0. ) !todo
    end subroutine cftcc_srch_minimize

    subroutine prep_soft_oris( wcorr, os )
        type(oris), intent(inout) :: os
        real,       intent(out)   :: wcorr
        real              :: ws(3)
        real, allocatable :: corrs(:)
        integer           :: i
        if( os%get_noris() /= 6 )stop 'invalid number of orientations; simple_cftcc_srch::prep_soft_oris'
        ws    = 0.
        wcorr = 0.
        ! get unnormalised correlations
        corrs = os%get_all('corr')
        ! calculate normalised weights and weighted corr
        where( corrs > TINY ) ws = exp(corrs) ! ignore invalid corrs
        ws    = ws/sum(ws)
        wcorr = sum(ws*corrs) 
        ! update npeaks individual weights
        do i=1,6
            call os%set(i,'ow',ws(i))
        enddo
        deallocate(corrs)
    end subroutine prep_soft_oris

end module simple_cftcc_srch

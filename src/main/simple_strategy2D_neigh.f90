module simple_strategy2D_neigh
use simple_strategy2D_alloc  ! use all in there
use simple_strategy2D,       only: strategy2D
use simple_strategy2D_srch,  only: strategy2D_srch, strategy2D_spec
implicit none

public :: strategy2D_neigh
private

logical, parameter :: DEBUG = .false.

type, extends(strategy2D) :: strategy2D_neigh
    type(strategy2D_srch) :: s
    type(strategy2D_spec) :: spec
contains
    procedure :: new  => new_neigh
    procedure :: srch => srch_neigh
    procedure :: kill => kill_neigh
end type strategy2D_neigh

contains

    subroutine new_neigh( self, spec )
        class(strategy2D_neigh), intent(inout) :: self
        class(strategy2D_spec),  intent(inout) :: spec
        call self%s%new( spec )
        self%spec = spec
    end subroutine new_neigh

    subroutine srch_neigh( self )
        class(strategy2D_neigh), intent(inout) :: self
        integer :: iref,loc(1),inpl_ind,inn
        real    :: corrs(self%s%nrots),inpl_corr,corr
        if( .not. associated(self%spec%nnmat) )&
        &stop 'nnmat need to be associated in self%spec; strategy2D_neigh :: srch_neigh'
        if( nint(self%s%a_ptr%get(self%s%iptcl,'state')) > 0 )then
            call self%s%prep4srch
            corr = -1.
            ! evaluate neighbors (greedy selection)
            do inn=1,self%s%nnn
                iref      = self%spec%nnmat(self%s%prev_class,inn)
                if( cls_pops(iref) == 0 )cycle
                call self%s%pftcc_ptr%gencorrs(iref, self%s%iptcl, corrs)
                loc       = maxloc(corrs)
                inpl_ind  = loc(1)
                inpl_corr = corrs(inpl_ind)
                if( inpl_corr >= corr )then
                    corr              = inpl_corr
                    self%s%best_class = iref
                    self%s%best_corr  = inpl_corr
                    self%s%best_rot   = inpl_ind
                endif
            end do
            self%s%nrefs_eval = self%s%nrefs
            call self%s%inpl_srch
            call self%s%fit_bfac
            call self%s%store_solution
        else
            call self%s%a_ptr%reject(self%s%iptcl)
        endif
        if( DEBUG ) print *, '>>> STRATEGY2D_NEIGH :: SRCH_NEIGH; FINISHED NEAREST-NEIGHBOR SEARCH'
    end subroutine srch_neigh

    subroutine kill_neigh( self )
        class(strategy2D_neigh), intent(inout) :: self
        call self%s%kill
    end subroutine kill_neigh

end module simple_strategy2D_neigh

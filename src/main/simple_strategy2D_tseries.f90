module simple_strategy2D_tseries
include 'simple_lib.f08'
use simple_strategy2D_alloc
use simple_strategy2D,       only: strategy2D
use simple_strategy2D_srch,  only: strategy2D_srch, strategy2D_spec
use simple_builder,          only: build_glob
use simple_polarft_corrcalc, only: pftcc_glob
implicit none

public :: strategy2D_tseries
private

#include "simple_local_flags.inc"

type, extends(strategy2D) :: strategy2D_tseries
    type(strategy2D_srch) :: s
    type(strategy2D_spec) :: spec
contains
    procedure :: new  => new_greedy
    procedure :: srch => srch_greedy
    procedure :: kill => kill_greedy
end type strategy2D_tseries

contains

    subroutine new_greedy( self, spec )
        class(strategy2D_tseries), intent(inout) :: self
        class(strategy2D_spec),   intent(inout) :: spec
        call self%s%new( spec )
        self%spec = spec
    end subroutine new_greedy

    subroutine srch_greedy( self )
        class(strategy2D_tseries), intent(inout) :: self
        integer :: iref,inpl_ind
        real    :: corrs(self%s%nrots),inpl_corr,corr
        if( build_glob%spproj_field%get_state(self%s%iptcl) > 0 )then
            call self%s%prep4srch
            corr = -huge(corr)
            do iref=1,self%s%nrefs
                if( s2D%cls_chunk(iref) /= self%s%chunk_id )cycle
                if( s2D%cls_pops(iref) == 0 )cycle
                call pftcc_glob%gencorrs(iref, self%s%iptcl, corrs)
                inpl_ind  = maxloc(corrs, dim=1)
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
            call self%s%store_solution
        else
            call build_glob%spproj_field%reject(self%s%iptcl)
        endif
        DebugPrint  '>>> strategy2D_tseries :: FINISHED STOCHASTIC SEARCH'
    end subroutine srch_greedy

    subroutine kill_greedy( self )
        class(strategy2D_tseries), intent(inout) :: self
        call self%s%kill
    end subroutine kill_greedy

end module simple_strategy2D_tseries
module simple_strategy2D_stochastic
include 'simple_lib.f08'
use simple_strategy2D_alloc  ! singleton
use simple_strategy2D,       only: strategy2D
use simple_strategy2D_srch,  only: strategy2D_srch, strategy2D_spec
use simple_builder,          only: build_glob
use simple_polarft_corrcalc, only: pftcc_glob
use simple_parameters,       only: params_glob
implicit none

public :: strategy2D_stochastic
private

#include "simple_local_flags.inc"

type, extends(strategy2D) :: strategy2D_stochastic
    type(strategy2D_srch) :: s
    type(strategy2D_spec) :: spec
contains
    procedure :: new  => new_stochastic
    procedure :: srch => srch_stochastic
    procedure :: kill => kill_stochastic
end type strategy2D_stochastic

contains

    subroutine new_stochastic( self, spec )
        class(strategy2D_stochastic), intent(inout) :: self
        class(strategy2D_spec),       intent(inout) :: spec
        call self%s%new( spec )
        self%spec = spec
    end subroutine new_stochastic

    subroutine srch_stochastic( self )
        class(strategy2D_stochastic), intent(inout) :: self
        integer :: iref, loc(1), isample, inpl_ind, nptcls, class_glob, inpl_glob
        real    :: corrs(self%s%nrots), inpl_corr, cc_glob
        logical :: found_better, do_inplsrch, glob_best_set, do_shc
        DebugPrint ' in stochastic srch '
        if( build_glob%spproj_field%get_state(self%s%iptcl) > 0 )then
            do_inplsrch   = .true.
            cc_glob       = -1.
            glob_best_set = .false.
            call self%s%prep4srch
            ! objective function based logics for performing extremal search
            if( params_glob%cc_objfun == OBJFUN_RES )then
                ! based on b-factor for objfun=ccres (the lower the better)
                do_shc = (self%spec%extr_bound < 0.) .or. (self%s%prev_bfac < self%spec%extr_bound)
            else
                ! based on correlation for objfun=cc (the higher the better)
                do_shc = (self%spec%extr_bound < 0.) .or. (self%s%prev_corr > self%spec%extr_bound)
            endif
            if( do_shc )then
                ! SHC move
                found_better      = .false.
                self%s%nrefs_eval = 0
                do isample=1,self%s%nrefs
                    iref = s2D%srch_order(self%s%iptcl_map, isample)
                    ! keep track of how many references we are evaluating
                    self%s%nrefs_eval = self%s%nrefs_eval + 1
                    ! passes empty classes
                    if( s2D%cls_pops(iref) == 0 )cycle
                    ! shc update
                    call pftcc_glob%gencorrs(iref, self%s%iptcl, corrs)
                    inpl_ind  = shcloc(self%s%nrots, corrs, self%s%prev_corr)
                    if( inpl_ind == 0 )then
                        ! update inpl_ind & inpl_corr to greedy best
                        loc       = maxloc(corrs)
                        inpl_ind  = loc(1)
                        inpl_corr = corrs(inpl_ind)
                    else
                        ! use the parameters selected by SHC condition
                        inpl_corr         = corrs(inpl_ind)
                        self%s%best_class = iref
                        self%s%best_corr  = inpl_corr
                        self%s%best_rot   = inpl_ind
                        found_better      = .true.
                    endif
                    ! keep track of global best
                    if( inpl_corr > cc_glob )then
                        cc_glob       = inpl_corr
                        class_glob    = iref
                        inpl_glob     = inpl_ind
                        glob_best_set = .true.
                    endif
                    ! first improvement heuristic
                    if( found_better ) exit
                end do
            else
                ! random move
                self%s%nrefs_eval = 1 ! evaluate one random ref
                isample           = 1 ! random .ne. prev
                iref              = s2D%srch_order(self%s%iptcl_map, isample)
                if( self%s%dyncls )then
                    ! all good
                else
                    ! makes sure the ptcl does not land in an empty class
                    ! such that a search is performed
                    do while( s2D%cls_pops(iref) == 0 )
                        isample = isample + 1
                        iref    = s2D%srch_order(self%s%iptcl_map, isample)
                        if( isample.eq.self%s%nrefs )exit
                    enddo
                endif
                if( s2D%cls_pops(iref) == 0 )then
                    ! empty class
                    do_inplsrch = .false.                 ! no in-plane search
                    inpl_ind    = irnd_uni(self%s%nrots)  ! random in-plane
                    nptcls      = build_glob%spproj_field%get_noris()
                    inpl_corr   = -1.
                    do while( inpl_corr < TINY )
                        inpl_corr = build_glob%spproj_field%get(irnd_uni(nptcls), 'corr') ! random correlation
                    enddo
                else
                    ! populated class
                    call pftcc_glob%gencorrs(iref, self%s%iptcl, corrs)
                    loc       = maxloc(corrs)
                    inpl_ind  = loc(1)
                    inpl_corr = corrs(inpl_ind)
                endif
                self%s%best_class = iref
                self%s%best_corr  = inpl_corr
                self%s%best_rot   = inpl_ind
                found_better      = .true.
            endif
            if( found_better )then
                ! best ref has already been updated
            else
                if( glob_best_set )then
                    ! use the globally best parameters
                    self%s%best_class = class_glob
                    self%s%best_corr  = cc_glob
                    self%s%best_rot   = inpl_glob
                else
                    ! keep the old parameters
                    self%s%best_class = self%s%prev_class
                    self%s%best_corr  = self%s%prev_corr
                    self%s%best_rot   = self%s%prev_rot
                endif
            endif
            if( do_inplsrch )then
                call self%s%inpl_srch
            endif
            if( .not. is_a_number(self%s%best_corr) )then
                print *, 'FLOATING POINT EXCEPTION ALARM; simple_strategy2D_srch :: stochastic_srch'
                print *, self%s%iptcl, self%s%best_class, self%s%best_corr, self%s%best_rot
                print *, 'do_shc: ', do_shc
            endif
            call self%s%store_solution
        else
            call build_glob%spproj_field%reject(self%s%iptcl)
        endif
        if( debug ) print *, '>>> strategy2D_srch::FINISHED STOCHASTIC SEARCH'
    end subroutine srch_stochastic

    subroutine kill_stochastic( self )
        class(strategy2D_stochastic), intent(inout) :: self
        call self%s%kill
    end subroutine kill_stochastic

end module simple_strategy2D_stochastic

! continuous function optimisation by differential evolution
module simple_de_opt
#include "simple_lib.f08"
use simple_optimizer, only: optimizer
use simple_opt_spec,  only: opt_spec
implicit none

public :: de_opt
private

integer, parameter :: N_GENERAL = 136,    N_VALLEY = 126,    N_MULTIMODAL = 103,    N_FLAT = 106
real,    parameter :: F_GENERAL = 0.2790, F_VALLEY = 0.4027, F_MULTIMODAL = 0.3976, F_FLAT = 0.5860
real,    parameter :: X_GENERAL = 0.9813, X_VALLEY = 0.9211, X_MULTIMODAL = 0.9794, X_FLAT = 0.3345
#include "simple_local_flags.inc"

type, extends(optimizer) :: de_opt
    private
    real, allocatable :: pop(:,:)          !< solution vector population
    real, allocatable :: costs(:)          !< costs
    integer           :: best              !< index of best population member
    real              :: F  = F_MULTIMODAL !< amplification factor
    real              :: CR = X_MULTIMODAL !< cross-over rate
    logical           :: exists = .false.  !< to indicate existence
  contains
    procedure :: new      => new_de
    procedure :: minimize => de_minimize
    procedure :: kill     => kill_de
end type de_opt

contains

    !> \brief  is a constructor
    subroutine new_de( self, spec )
        use simple_syslib, only: alloc_errchk
        class(de_opt),   intent(inout) :: self !< instance
        class(opt_spec), intent(inout) :: spec !< specification
        ! destruct if exists
        call self%kill
        ! adjust control parameters according to mode
        select case(trim(spec%str_mode))
            case('general')
                spec%npop = N_GENERAL
                self%F    = F_GENERAL
                self%CR   = X_GENERAL
            case('valley')
                spec%npop = N_VALLEY
                self%F    = F_VALLEY
                self%CR   = X_VALLEY
            case('multimodal')
                spec%npop = N_MULTIMODAL
                self%F    = F_MULTIMODAL
                self%CR   = X_MULTIMODAL
            case('flat')
                spec%npop = N_FLAT
                self%F    = F_FLAT
                self%CR   = X_FLAT
            case DEFAULT
                spec%npop = N_MULTIMODAL
                self%F    = F_MULTIMODAL
                self%CR   = X_MULTIMODAL
        end select
        ! allocate
        allocate(self%pop(spec%npop,spec%ndim), self%costs(spec%npop), stat=alloc_stat)
        allocchk("In: new_de; simple_de_opt")
        self%exists = .true. ! indicates existence
        if( spec%DEBUG ) write(*,*) 'created new differential evolution population'
    end subroutine new_de

    !> \brief  is the differential evolution minimization routine
    subroutine de_minimize( self, spec, fun_self, lowest_cost )
        class(de_opt),   intent(inout) :: self        !< instance     
        class(opt_spec), intent(inout) :: spec        !< specification
        class(*),        intent(inout) :: fun_self    !< self-pointer for cost function
        real,            intent(out)   :: lowest_cost !< lowest cost
        real    :: trial_costs(spec%npop)!, ran3s(spec%npop,spec%ndim)
        real    :: trials(spec%npop,spec%ndim)
        real    :: trial(spec%ndim), cost_trial, L
        ! integer :: am(spec%npop), bm(spec%npop), rbm(spec%npop)
        integer :: a, rb, b, i, j, X, t, npeaks, loc(1), nworse
        if( .not. associated(spec%costfun) )then
            stop 'cost function not associated in opt_spec; de_minimize; simple_de_opt'
        endif
        ! obtain initial solutions by randomized bounds
        do i=1,spec%npop
            do j=1,spec%ndim
                L = spec%limits(j,2) - spec%limits(j,1)
                self%pop(i,j) = spec%limits(j,1) + ran3() * L
            end do
            if( i == 1 )then
                if( .not. all(spec%x == 0.) )then ! set one point in the swarm to best point in spec
                    self%pop(1,:)= spec%x
                endif
            endif
        end do
        ! calculate initial costs
        do i=1,spec%npop
            self%costs(i) = spec%costfun(fun_self, self%pop(i,:), spec%ndim)
        end do
        loc = minloc(self%costs)
        self%best = loc(1)
        ! initialize the remains
        npeaks    = 0
        nworse    = 0
        do t=1,spec%maxits ! generations loop
            ! select solution to modify
            X  = irnd_uni(spec%npop)
            ! select random disjoint pair
            a  = irnd_uni(spec%npop)
            rb = irnd_uni(spec%npop - 1)
            b  = a + rb
            if( b <= spec%npop )then
            else
                b = a + rb - spec%npop
            endif
            ! create a trial solution
            do i=1,spec%ndim
                if( i == X .or. ran3() < self%CR )then
                    trial(i) = self%pop(self%best,i) + self%F * (self%pop(a,i) - self%pop(b,i))
                    ! enforce limits
                    trial(i) = min(spec%limits(i,2),trial(i))
                    trial(i) = max(spec%limits(i,1),trial(i))
                else
                    trial(i) = self%pop(X,i)
                endif
            end do
            ! calculate cost
            cost_trial = spec%costfun(fun_self, trial, spec%ndim)
            ! update pop if better solution is found
            if( cost_trial < self%costs(X) )then
                nworse = 0
                self%pop(X,:) = trial
                self%costs(X) = cost_trial
                ! update global best if needed
                if( cost_trial < self%costs(self%best) ) self%best = X
                if( spec%npeaks > 0 )then
                    ! we will output local optima
                    if( cost_trial < spec%yb )then
                        npeaks = npeaks + 1
                        spec%peaks(npeaks,:spec%ndim)  = trial
                        spec%peaks(npeaks,spec%ndim+1) = cost_trial
                    endif
                endif
            else
                nworse = nworse + 1
            endif
            if( spec%npeaks > 0 )then
                ! exit when we have identified spec%npeaks local optima
                if( npeaks == spec%npeaks ) exit
            endif
            if( nworse > spec%npop ) exit
        end do
        lowest_cost = self%costs(self%best)
        spec%x = self%pop(self%best,:)
    end subroutine de_minimize

    ! GETTERS

    !> \brief  is a destructor
    subroutine kill_de( self )
        class(de_opt), intent(inout) :: self !< instance
        if( self%exists )then
            deallocate(self%pop,self%costs)
            self%exists = .false.
        endif
    end subroutine kill_de

end module simple_de_opt

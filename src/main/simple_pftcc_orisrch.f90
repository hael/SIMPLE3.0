module simple_pftcc_orisrch
#include "simple_lib.f08"
!$ use omp_lib
!$ use omp_lib_kinds
use simple_opt_spec,          only: opt_spec
use simple_polarft_corrcalc,  only: polarft_corrcalc
use simple_opt_factory,       only: opt_factory
use simple_optimizer,         only: optimizer
use simple_build,             only: build
use simple_ori,               only: ori
implicit none

public :: pftcc_orisrch
private

type :: pftcc_orisrch
    private
    type(opt_spec)                   :: ospec                  !< optimizer specification object
    class(optimizer),        pointer :: nlopt                  !< optimizer object
    class(build),            pointer :: bp          => null()  !< pointer to build
    class(polarft_corrcalc), pointer :: pftcc_ptr   => null()  !< pointer to pftcc object
    type(ori), allocatable           :: e_trials(:)            !< trial orientations (one per thread)
    integer                          :: particle    =  0       !< particle pft
    integer                          :: nrots       =  0       !< # rotations
    integer                          :: irot        =  0       !< index of rotation
    integer                          :: maxits      =  100     !< max # iterations
    integer                          :: nrestarts   =  3       !< simplex restarts (randomized bounds)
    logical                          :: shbarr      =  .true.  !< shift barrier constraint or not
  contains
    procedure :: new
    procedure :: set_particle
    procedure :: minimize
    procedure :: costfun
end type pftcc_orisrch

contains

    !> constructor
    subroutine new( self, pftcc, b, lims, lims_init, shbarrier, nrestarts, maxits )
        use simple_projector, only: projector
        class(pftcc_orisrch),            intent(inout) :: self           !< instance
        class(polarft_corrcalc), target, intent(in)    :: pftcc          !< correlator
        class(build),            target, intent(in)    :: b              !< builder
        real,                            intent(in)    :: lims(:,:)      !< limits for barrier constraint
        real,             optional,      intent(in)    :: lims_init(:,:) !< limits for simplex initialisation by randomised bounds
        character(len=*), optional,      intent(in)    :: shbarrier      !< shift barrier constraint or not
        integer,          optional,      intent(in)    :: nrestarts      !< simplex restarts (randomized bounds)
        integer,          optional,      intent(in)    :: maxits         !< maximum iterations
        type(opt_factory) :: opt_fact
        integer           :: ithr, i
        ! kill allocatables
        if( allocated(self%e_trials) )then
            do i=1,size(self%e_trials)
                call self%e_trials(i)%kill
            end do
            deallocate(self%e_trials)
        endif
        ! flag the barrier constraint
        self%shbarr = .true.
        if( present(shbarrier) )then
            if( shbarrier .eq. 'no' ) self%shbarr = .false.
        endif
        self%nrestarts = 3
        if( present(nrestarts) ) self%nrestarts = nrestarts
        self%maxits = 100
        if( present(maxits) ) self%maxits = maxits
        ! make optimizer spec
        if( present(lims_init) )then
            call self%ospec%specify('simplex', 4, ftol=1e-4, gtol=1e-4, limits=lims,&
                &limits_init=lims_init, nrestarts=self%nrestarts, maxits=self%maxits)
        else
            call self%ospec%specify('simplex', 4, ftol=1e-4, gtol=1e-4,&
                &limits=lims, nrestarts=self%nrestarts, maxits=self%maxits)
        endif
        ! generate the optimizer object
        call opt_fact%new(self%ospec, self%nlopt)
        ! set pointer to corrcalc object
        self%pftcc_ptr => pftcc
        ! set pointer to build
        self%bp => b
        ! get # rotations
        self%nrots = pftcc%get_nrots()
        ! make trial orientations (one per thread)
        allocate(self%e_trials(nthr_glob))
        do ithr=1,nthr_glob
            call self%e_trials(ithr)%new_ori_clean
        end do
        ! associate costfun
        self%ospec%costfun => costfun_wrapper
    end subroutine new

    !> set particle index for search
    subroutine set_particle( self, ptcl )
        class(pftcc_orisrch), intent(inout) :: self
        integer,              intent(in)    :: ptcl
        self%particle  = ptcl
    end subroutine set_particle

    !> wrapper for cost function (gcc7+)
    function costfun_wrapper(self, vec, D) result( cost )
        class(*), intent(inout) :: self
        integer,  intent(in)    :: D
        real,     intent(in)    :: vec(D)
        real :: cost
        select type (self)
            class is (pftcc_orisrch)
                cost = self%costfun(vec, D)
            class default
                write (*,*) 'error in simple_pftcc_orisrch, costfun_wrapper: unknown type'
                stop
        end select
    end function costfun_wrapper

    !> cost function
    function costfun( self, vec, D ) result( cost )
        class(pftcc_orisrch), intent(inout) :: self
        integer,              intent(in)    :: D
        real,                 intent(in)    :: vec(D)
        real      :: cost, corrs(self%nrots)
        integer   :: loc(1), ithr
        type(ori) :: e
        ! enforce barrier constraint
        if( self%shbarr )then
            if( any(vec(:) < self%ospec%limits(:,1)) .or.&
                &any(vec(:) > self%ospec%limits(:,2)) )then
                cost = 1.
                return
            endif
        endif
        ! thread-safe extraction of projection
        ithr = omp_get_thread_num() + 1
        call self%e_trials(ithr)%set_euler([vec(1),vec(2),0.])
        if( self%pftcc_ptr%ptcl_iseven(self%particle) )then
            call self%bp%vol%fproject_polar(ithr, self%e_trials(ithr), self%pftcc_ptr, iseven=.true.)
        else
            call self%bp%vol_odd%fproject_polar(ithr, self%e_trials(ithr), self%pftcc_ptr, iseven=.false.)
        endif
        ! correlate
        call self%pftcc_ptr%gencorrs(ithr, self%particle, vec(3:4), corrs)
        loc       = maxloc(corrs)
        self%irot = loc(1)
        cost      = -corrs(self%irot)
    end function costfun

    !> minimisation
    function minimize( self, o_inout, irot ) result( cxy )
        use simple_ori, only: ori
        class(pftcc_orisrch), intent(inout) :: self
        class(ori),           intent(inout) :: o_inout
        integer,              intent(out)   :: irot
        type pftcc_ref
            complex, allocatable :: pft_ref_even(:,:), pft_ref_odd(:,:)
        end type pftcc_ref
        type(pftcc_ref), allocatable :: pftcc_refs(:)
        real,            allocatable :: cxy(:)
        real    :: cost, cost_init, corrs(self%nrots)
        integer :: loc(1), ithr
        ! copy nthr_glob pftcc references so we can put them back after minimization is done
        allocate(pftcc_refs(nthr_glob), cxy(3))
        do ithr=1,nthr_glob
            pftcc_refs(ithr)%pft_ref_even = self%pftcc_ptr%get_ref_pft(ithr, iseven=.true.)
            pftcc_refs(ithr)%pft_ref_odd  = self%pftcc_ptr%get_ref_pft(ithr, iseven=.false.)
        end do
        ! minimisation
        self%ospec%x(1)   = o_inout%e1get()
        self%ospec%x(2)   = o_inout%e2get()
        self%ospec%x(3)   = 0.
        self%ospec%x(4)   = 0.
        self%ospec%nevals = 0
        cost_init = self%costfun(self%ospec%x, self%ospec%ndim)
        call self%nlopt%minimize(self%ospec, self, cost)
        if( cost <= cost_init )then
            ! call the costfun to get the rotation index
            cost = self%costfun(self%ospec%x, self%ospec%ndim)
            irot = self%irot
            ! set output
            cxy(1)  = -cost ! correlation
            ! rotate the shift vector to the frame of reference
            cxy(2:) = matmul(self%ospec%x(3:4), rotmat2d(self%pftcc_ptr%get_rot(irot)))
            ! set Euler
            call o_inout%set_euler([self%ospec%x(1),self%ospec%x(2),360. - self%pftcc_ptr%get_rot(irot)])
            ! set shift
            call o_inout%set_shift(cxy(2:))
        else
            irot    = 0
            cxy(1)  = -cost_init ! correlation
            cxy(2:) = 0.
        endif
        ! put back references & deallocate
        do ithr=1,nthr_glob
            call self%pftcc_ptr%set_ref_pft(ithr, pftcc_refs(ithr)%pft_ref_even, iseven=.true.)
            call self%pftcc_ptr%set_ref_pft(ithr, pftcc_refs(ithr)%pft_ref_odd,  iseven=.false.)
            deallocate(pftcc_refs(ithr)%pft_ref_even, pftcc_refs(ithr)%pft_ref_odd)
        end do
        deallocate(pftcc_refs)
    end function minimize

    function get_nevals( self ) result( nevals )
        class(pftcc_orisrch), intent(inout) :: self
        integer :: nevals
        nevals = self%ospec%nevals
    end function get_nevals

end module simple_pftcc_orisrch
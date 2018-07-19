! common strategy3D methods and type specification for polymorphic strategy3D object creation are delegated to this class
module simple_strategy3D_srch
include 'simple_lib.f08'
use simple_oris,               only: oris
use simple_ori,                only: ori
use simple_sym,                only: sym
use simple_pftcc_shsrch_grad,  only: pftcc_shsrch_grad  ! gradient-based in-plane angle and shift search
use simple_pftcc_orisrch_grad, only: pftcc_orisrch_grad ! gradient-based search over all df:s
use simple_polarft_corrcalc,   only: pftcc_glob
use simple_parameters,         only: params_glob
use simple_builder,            only: build_glob
use simple_strategy3D_alloc    ! singleton s3D
implicit none

public :: strategy3D_srch, strategy3D_spec
private
#include "simple_local_flags.inc"

logical, parameter :: DOCONTINUOUS = .false.

type strategy3D_spec
    integer, pointer :: grid_projs(:) => null()
    integer, pointer :: symmat(:,:)   => null()
    integer :: iptcl=0, szsn=0
    logical :: do_extr=.false.
    real    :: extr_score_thresh=0.
end type strategy3D_spec

type strategy3D_srch
    type(pftcc_shsrch_grad)  :: grad_shsrch_obj           !< origin shift search object, L-BFGS with gradient
    type(pftcc_orisrch_grad) :: grad_orisrch_obj          !< obj 4 search over all df:s, L-BFGS with gradient
    integer, allocatable     :: nnvec(:)                  !< nearest neighbours indices
    integer                  :: iptcl         = 0         !< global particle index
    integer                  :: ithr          = 0         !< thread index
    integer                  :: nrefs         = 0         !< total # references (nstates*nprojs)
    integer                  :: nnnrefs       = 0         !< total # neighboring references (nstates*nnn)
    integer                  :: nstates       = 0         !< # states
    integer                  :: nprojs        = 0         !< # projections
    integer                  :: nrots         = 0         !< # in-plane rotations in polar representation
    integer                  :: npeaks        = 0         !< # peaks (nonzero orientation weights)
    integer                  :: npeaks_eff    = 0         !< effective # peaks
    integer                  :: npeaks_grid   = 0         !< # peaks after coarse search
    integer                  :: nsym          = 0         !< symmetry order
    integer                  :: nbetter       = 0         !< # better orientations identified
    integer                  :: nrefs_eval    = 0         !< # references evaluated
    integer                  :: nnn_static    = 0         !< # nearest neighbors (static)
    integer                  :: nnn           = 0         !< # nearest neighbors (dynamic)
    integer                  :: prev_roind    = 0         !< previous in-plane rotation index
    integer                  :: prev_state    = 0         !< previous state index
    integer                  :: prev_ref      = 0         !< previous reference index
    integer                  :: prev_proj     = 0         !< previous projection direction index
    real                     :: prev_corr     = 1.        !< previous best correlation
    real                     :: specscore     = 0.        !< spectral score
    real                     :: prev_shvec(2) = 0.        !< previous origin shift vector
    logical                  :: neigh         = .false.   !< nearest neighbour refinement flag
    logical                  :: doshift       = .true.    !< 2 indicate whether 2 serch shifts
    logical                  :: dowinpl       = .true.    !< 2 indicate weights over in-planes as well as projection dirs
    logical                  :: exists        = .false.   !< 2 indicate existence
  contains
    procedure :: new
    procedure :: prep4srch
    procedure :: greedy_subspace_srch
    procedure :: inpl_srch
    procedure :: store_solution
    procedure :: kill
end type strategy3D_srch

contains

    subroutine new( self, spec, npeaks )
        class(strategy3D_srch), intent(inout) :: self
        class(strategy3D_spec), intent(in)    :: spec
        integer,                intent(in)    :: npeaks
        integer, parameter :: MAXITS = 60
        integer :: nstates_eff
        real    :: lims(2,2), lims_init(2,2)
        ! set constants
        self%iptcl      = spec%iptcl
        self%nstates    = params_glob%nstates
        self%nprojs     = params_glob%nspace
        self%nrefs      = self%nprojs*self%nstates
        self%nrots      = round2even(twopi*real(params_glob%ring2))
        self%npeaks     = npeaks
        self%nbetter    = 0
        self%nrefs_eval = 0
        self%nsym       = build_glob%pgrpsyms%get_nsym()
        self%doshift    = params_glob%l_doshift
        self%neigh      = params_glob%neigh == 'yes'
        self%nnn_static = params_glob%nnn
        self%nnn        = params_glob%nnn
        self%nnnrefs    = self%nnn*self%nstates
        self%dowinpl    = npeaks /= 1
        ! multiple states
        if( self%nstates == 1 )then
            self%npeaks_grid = GRIDNPEAKS
        else
            ! number of populated states
            nstates_eff = count(s3D%state_exists)
            select case(trim(params_glob%refine))
            case('cluster','clustersym')
                    self%npeaks_grid = 1
                case DEFAULT
                    ! "-(nstates_eff-1)" because all states share the same previous orientation
                    self%npeaks_grid = GRIDNPEAKS * nstates_eff - (nstates_eff - 1)
            end select
        endif
        if( self%neigh )then
            self%npeaks_grid = min(self%npeaks_grid,self%nnnrefs)
        else
            self%npeaks_grid = min(self%npeaks_grid,self%nrefs)
        endif
        ! create in-plane search object
        lims(:,1)      = -params_glob%trs
        lims(:,2)      =  params_glob%trs
        lims_init(:,1) = -SHC_INPL_TRSHWDTH
        lims_init(:,2) =  SHC_INPL_TRSHWDTH
        call self%grad_shsrch_obj%new(lims, lims_init=lims_init,&
            &shbarrier=params_glob%shbarrier, maxits=MAXITS, opt_angle=.not. self%dowinpl)
        ! create all df:s search object
        call self%grad_orisrch_obj%new
        self%exists = .true.
        DebugPrint  '>>> STRATEGY3D_SRCH :: CONSTRUCTED NEW STRATEGY3D_SRCH OBJECT'
    end subroutine new

    subroutine prep4srch( self, nnmat, target_projs )
        use simple_combinatorics, only: merge_into_disjoint_set
        class(strategy3D_srch), intent(inout) :: self
        integer, optional,      intent(in)    :: nnmat(self%nprojs,self%nnn_static), target_projs(self%npeaks_grid)
        integer   :: i, istate
        type(ori) :: o_prev
        real      :: corrs(self%nrots), corr, bfac
        if( self%neigh )then
            if( .not. present(nnmat) )&
            &stop 'need optional nnmat to be present for refine=neigh modes :: prep4srch (strategy3D_srch)'
            if( .not. present(target_projs) )&
            &stop 'need optional target_projs to be present for refine=neigh modes :: prep4srch (strategy3D_srch)'
        endif
        ! previous parameters
        o_prev          = build_glob%spproj_field%get_ori(self%iptcl)
        self%prev_state = o_prev%get_state()                                ! state index
        self%prev_roind = pftcc_glob%get_roind(360.-o_prev%e3get())         ! in-plane angle index
        self%prev_shvec = o_prev%get_2Dshift()                              ! shift vector
        self%prev_proj  = build_glob%eulspace%find_closest_proj(o_prev)     ! previous projection direction
        self%prev_ref   = (self%prev_state-1)*self%nprojs + self%prev_proj  ! previous reference
        ! init threaded search arrays
        call prep_strategy3D_thread(self%ithr)
        ! search order
        if( self%neigh )then
            do istate = 0, self%nstates - 1
                i = istate * self%nnn + 1
                s3D%srch_order(self%ithr,i:i+self%nnn-1) = build_glob%nnmat(self%prev_proj,:) + istate*self%nprojs
            enddo
            call s3D%rts(self%ithr)%shuffle(s3D%srch_order(self%ithr,:))
        else
            call s3D%rts(self%ithr)%ne_ran_iarr(s3D%srch_order(self%ithr,:))
        endif
        call put_last(self%prev_ref, s3D%srch_order(self%ithr,:))
        ! sanity check
        if( self%prev_state > 0 )then
            if( self%prev_state > self%nstates ) stop 'previous best state outside boundary; prep4srch; simple_strategy3D_srch'
            if( .not. s3D%state_exists(self%prev_state) ) stop 'empty previous state; prep4srch; simple_strategy3D_srch'
        endif
        if( self%neigh )then
            ! disjoint nearest neighbour set
            self%nnvec = merge_into_disjoint_set(self%nprojs, self%nnn_static, nnmat, target_projs)
        endif
        ! B-factor memoization
        if( params_glob%l_bfac_static )then
            bfac = params_glob%bfac_static
        else
            bfac = pftcc_glob%fit_bfac(self%prev_ref, self%iptcl, self%prev_roind, [0.,0.])
        endif
        if( params_glob%cc_objfun == OBJFUN_RES ) call pftcc_glob%memoize_bfac(self%iptcl, bfac)
        call build_glob%spproj_field%set(self%iptcl, 'bfac', bfac)
        ! calc specscore
        self%specscore = pftcc_glob%specscore(self%prev_ref, self%iptcl, self%prev_roind)
        ! prep corr
        call pftcc_glob%gencorrs(self%prev_ref, self%iptcl, corrs)
        corr = max(0.,maxval(corrs))
        if( corr - 1.0 > 1.0e-5 .or. .not. is_a_number(corr) )then
            print *, 'FLOATING POINT EXCEPTION ALARM; simple_strategy3D_srch :: prep4srch'
            print *, 'corr > 1. or isNaN'
            print *, 'corr = ', corr
            if( corr > 1. )               corr = 1.
            if( .not. is_a_number(corr) ) corr = 0.
            call o_prev%print_ori()
        endif
        self%prev_corr = corr
        DebugPrint  '>>> STRATEGY3D_SRCH :: PREPARED FOR SIMPLE_STRATEGY3D_SRCH'
    end subroutine prep4srch

    subroutine greedy_subspace_srch( self, grid_projs, target_projs )
        class(strategy3D_srch), intent(inout) :: self
        integer,                intent(in)    :: grid_projs(:)
        integer,                intent(inout) :: target_projs(:)
        real      :: inpl_corrs(self%nrots), corrs(self%nrefs)
        integer   :: iref, isample, nrefs, ntargets, cnt, istate
        integer   :: state_cnt(self%nstates), iref_state
        if( build_glob%spproj_field%get_state(self%iptcl) > 0 )then
            ! initialize
            call prep_strategy3D_thread(self%ithr)
            target_projs   = 0
            nrefs          = size(grid_projs)
            self%prev_proj = build_glob%eulspace%find_closest_proj(build_glob%spproj_field%get_ori(self%iptcl))
            ! search
            do isample = 1, nrefs
                do istate = 1, self%nstates
                    iref = grid_projs(isample)           ! set the projdir reference index
                    iref = (istate-1)*self%nprojs + iref ! set the state reference index
                    call per_ref_srch                    ! actual search
                end do
            end do
            ! sort in correlation projection direction space
            corrs = s3D%proj_space_corrs(self%ithr,:,1) ! 1 is the top ranking in-plane corr
            call hpsort(corrs, s3D%proj_space_refinds(self%ithr,:))
            ! return target points
            ntargets = size(target_projs)
            cnt      = 1
            target_projs( cnt ) = self%prev_proj ! previous always part of the targets
            if( self%nstates == 1 )then
                ! Single state
                do isample=self%nrefs,self%nrefs - ntargets + 1,-1
                    if( target_projs(1) == s3D%proj_space_refinds(self%ithr,isample) )then
                        ! direction is already in target set
                    else
                        cnt = cnt + 1
                        target_projs(cnt) = s3D%proj_space_refinds(self%ithr,isample)
                        if( cnt == ntargets ) exit
                    endif
                end do
            else
                ! Multiples states
                state_cnt = 1                                                   ! previous always part of the targets
                do isample = self%nrefs, 1, -1
                    if( cnt >= self%npeaks_grid )exit                           ! all that we need
                    iref_state = s3D%proj_space_refinds(self%ithr,isample) ! reference index to multi-state space
                    istate     = ceiling(real(iref_state)/real(self%nprojs))
                    iref       = iref_state - (istate-1)*self%nprojs            ! reference index to single state space
                    if( .not.s3D%state_exists(istate) )cycle
                    if( any(target_projs == iref) )cycle                        ! direction is already set
                    if( state_cnt(istate) >= GRIDNPEAKS )cycle                  ! state is already filled
                    cnt = cnt + 1
                    target_projs(cnt) = iref
                    state_cnt(istate) = state_cnt(istate) + 1
                end do
            endif
        else
            call build_glob%spproj_field%reject(self%iptcl)
        endif
        DebugPrint  '>>> STRATEGY3D_SRCH :: FINISHED GREEDY SUBSPACE SEARCH'

        contains

            subroutine per_ref_srch
                integer :: loc(3)
                if( s3D%state_exists(istate) )then
                    ! calculate in-plane correlations
                    call pftcc_glob%gencorrs(iref, self%iptcl, inpl_corrs)
                    ! identify the 3 top scoring in-planes
                    loc = max3loc(inpl_corrs)
                    ! stash in-plane correlations for sorting
                    s3D%proj_space_corrs(self%ithr,iref,:) = [inpl_corrs(loc(1)),inpl_corrs(loc(2)),inpl_corrs(loc(3))]
                    ! stash the reference index for sorting
                    s3D%proj_space_refinds(self%ithr,iref) = iref
                    ! stash the in-plane indices
                    s3D%proj_space_inplinds(self%ithr,iref,:) = loc
                endif
            end subroutine per_ref_srch

    end subroutine greedy_subspace_srch

    subroutine inpl_srch( self )
        class(strategy3D_srch), intent(inout) :: self
        type(ori) :: o
        real      :: cxy(3)
        integer   :: i, j, ref, irot, cnt
        logical   :: found_better
        if( DOCONTINUOUS )then
            ! BFGS over all df:s
            call o%new
            cnt = 0
            do i=self%nrefs,self%nrefs-self%npeaks+1,-1
                cnt = cnt + 1
                ref = s3D%proj_space_refinds(self%ithr, i)
                if( cnt <= CONTNPEAKS )then
                    ! continuous refinement over all df:s
                    call o%set_euler(s3D%proj_space_euls(self%ithr,ref,1,:))
                    call o%set_shift([0.,0.])
                    call self%grad_orisrch_obj%set_particle(self%iptcl)
                    cxy = self%grad_orisrch_obj%minimize(o, NPEAKSATHRES/2.0, params_glob%trs, found_better)
                    if( found_better )then
                        s3D%proj_space_euls(self%ithr, ref, 1,:) = o%get_euler()
                        s3D%proj_space_corrs(self%ithr,ref, 1)   = cxy(1)
                        s3D%proj_space_shift(self%ithr,ref, 1,:) = cxy(2:3)
                    endif
                else
                    ! refinement of in-plane rotation (discrete) & shift (continuous)
                    call self%grad_shsrch_obj%set_indices(ref, self%iptcl)
                    cxy = self%grad_shsrch_obj%minimize(irot=irot)
                    if( irot > 0 )then
                        ! irot > 0 guarantees improvement found, update solution
                        s3D%proj_space_euls(self%ithr, ref,1, 3) = 360. - pftcc_glob%get_rot(irot)
                        s3D%proj_space_corrs(self%ithr,ref,1)    = cxy(1)
                        s3D%proj_space_shift(self%ithr,ref,1,:)  = cxy(2:3)
                    endif
                endif
            end do
        else
            if( self%doshift )then
                if( self%dowinpl )then
                    ! BFGS over shifts only
                    do i=self%nrefs,self%nrefs-self%npeaks+1,-1
                        ref = s3D%proj_space_refinds(self%ithr, i)
                        call self%grad_shsrch_obj%set_indices(ref, self%iptcl)
                        do j=1,MAXNINPLPEAKS
                            irot = s3D%proj_space_inplinds(self%ithr, ref, j)
                            cxy  = self%grad_shsrch_obj%minimize(irot=irot)
                            if( irot > 0 )then
                                ! irot > 0 guarantees improvement found, update solution
                                s3D%proj_space_euls( self%ithr,ref,j,3) = 360. - pftcc_glob%get_rot(irot)
                                s3D%proj_space_corrs(self%ithr,ref,j)   = cxy(1)
                                s3D%proj_space_shift(self%ithr,ref,j,:) = cxy(2:3)
                            endif
                        end do
                    end do
                else
                    ! BFGS over shifts with in-plane rot exhaustive callback
                    do i=self%nrefs,self%nrefs-self%npeaks+1,-1
                        ref = s3D%proj_space_refinds(self%ithr, i)
                        call self%grad_shsrch_obj%set_indices(ref, self%iptcl)
                        cxy = self%grad_shsrch_obj%minimize(irot=irot)
                        if( irot > 0 )then
                            ! irot > 0 guarantees improvement found, update solution
                            s3D%proj_space_euls( self%ithr,ref,1,3) = 360. - pftcc_glob%get_rot(irot)
                            s3D%proj_space_corrs(self%ithr,ref,1)   = cxy(1)
                            s3D%proj_space_shift(self%ithr,ref,1,:) = cxy(2:3)
                        endif
                    end do
                endif
            endif
            DebugPrint  '>>> STRATEGY3D_SRCH :: FINISHED INPL SEARCH'
        endif
    end subroutine inpl_srch

    subroutine store_solution( self, ind, ref, inpl_inds, corrs )
        class(strategy3D_srch), intent(inout) :: self
        integer,                intent(in)    :: ind, ref, inpl_inds(MAXNINPLPEAKS)
        real,                   intent(in)    :: corrs(MAXNINPLPEAKS)
        integer :: inpl
        s3D%proj_space_refinds(self%ithr,ind)    = ref
        s3D%proj_space_inplinds(self%ithr,ref,:) = inpl_inds
        do inpl=1,MAXNINPLPEAKS
            s3D%proj_space_euls(self%ithr,ref,inpl,3) = 360. - pftcc_glob%get_rot(inpl_inds(inpl))
        end do
        s3D%proj_space_corrs(self%ithr,ref,:) = corrs
    end subroutine store_solution

    subroutine kill( self )
        class(strategy3D_srch), intent(inout) :: self
        if(allocated(self%nnvec))deallocate(self%nnvec)
        call self%grad_shsrch_obj%kill
    end subroutine kill

end module simple_strategy3D_srch

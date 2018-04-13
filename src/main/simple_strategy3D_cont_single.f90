! concrete strategy3D: continuous single-state refinement
module simple_strategy3D_cont_single
use simple_strategy3D_alloc  ! use all in there
use simple_strategy3D_utils  ! use all in there
use simple_strategy3D,       only: strategy3D
use simple_strategy3D_srch,  only: strategy3D_srch, strategy3D_spec
use simple_pftcc_orisrch,    only: pftcc_orisrch
use simple_ori,              only: ori
implicit none

public :: strategy3D_cont_single
private

#include "simple_local_flags.inc"

type, extends(strategy3D) :: strategy3D_cont_single
    type(strategy3D_srch) :: s
    type(strategy3D_spec) :: spec
    type(pftcc_orisrch)   :: cont_srch
    type(ori)             :: o
    integer               :: irot
    real                  :: corr
contains
    procedure :: new         => new_cont_single
    procedure :: srch        => srch_cont_single
    procedure :: oris_assign => oris_assign_cont_single
    procedure :: kill        => kill_cont_single
end type strategy3D_cont_single

contains

    subroutine new_cont_single( self, spec, npeaks )
        class(strategy3D_cont_single), intent(inout) :: self
        class(strategy3D_spec),        intent(inout) :: spec
        integer,                       intent(in)    :: npeaks
        integer, parameter :: MAXITS = 60
        real :: lims(4,2), lims_init(4,2)
        call self%s%new( spec, npeaks )
        self%spec        = spec
        lims(1:2,:)      = spec%pp%eullims(1:2,:)
        lims(3:4,1)      = -spec%pp%trs
        lims(3:4,2)      =  spec%pp%trs
        lims_init        = lims
        lims_init(3:4,1) = -SHC_INPL_TRSHWDTH
        lims_init(3:4,2) =  SHC_INPL_TRSHWDTH
        call self%cont_srch%new(spec%ppftcc, spec%pb, lims,&
        &lims_init=lims_init, shbarrier=spec%pp%shbarrier, maxits=MAXITS)
    end subroutine new_cont_single

    subroutine srch_cont_single( self )
        class(strategy3D_cont_single), intent(inout) :: self
        real, allocatable :: cxy(:)
        ! execute search
        if( self%s%a_ptr%get_state(self%s%iptcl) > 0 )then
            ! initialize
            call self%s%prep4srch()
            call self%cont_srch%set_particle(self%s%iptcl)
            self%o    = self%s%a_ptr%get_ori(self%s%iptcl)
            cxy       = self%cont_srch%minimize(self%o, self%irot)
            self%corr = cxy(1)
            ! prepare weights and orientations
            call self%oris_assign_cont_single
        else
            call self%s%a_ptr%reject(self%s%iptcl)
        endif
        DebugPrint  '>>> STRATEGY3D_CONT_SINGLE :: FINISHED STOCHASTIC SEARCH'
    end subroutine srch_cont_single

    !>  \brief retrieves and preps npeaks orientations for reconstruction
    subroutine oris_assign_cont_single( self )
        use simple_ori,  only: ori
        class(strategy3D_cont_single), intent(inout) :: self
        type(ori) :: osym
        real      :: ws(1), dist_inpl, euldist, mi_proj, mi_inpl, mi_joint, frac
        ! B factors
        ws = 1.0
        call fit_bfactors(self%s, ws)
        ! angular standard deviation
        ang_sdev = 0.
        ! angular distances
        call self%s%se_ptr%sym_dists(self%s%a_ptr%get_ori(self%s%iptcl), self%o, osym, euldist, dist_inpl)
        ! generate convergence stats
        mi_proj  = 0.
        mi_inpl  = 0.
        mi_joint = 0.
        if( euldist < 0.5 )then
            mi_proj  = 1.
            mi_joint = mi_joint + 1.
        endif
        if( self%irot == 0 .or. s%prev_roind == self%irot )then
            mi_inpl  = 1.
            mi_joint = mi_joint + 1.
        endif
        mi_joint = mi_joint / 2.
        call s%a_ptr%set(s%iptcl, 'mi_proj',   mi_proj)
        call s%a_ptr%set(s%iptcl, 'mi_inpl',   mi_inpl)
        call s%a_ptr%set(s%iptcl, 'mi_state',  1.)
        call s%a_ptr%set(s%iptcl, 'mi_joint',  mi_joint)
        ! fraction of search space scanned
        frac = 100.
        ! set the distances before we update the orientation
        if( self%s%a_ptr%isthere(self%s%iptcl,'dist') )then
            call self%s%a_ptr%set(self%s%iptcl, 'dist', 0.5*euldist + 0.5*self%s%a_ptr%get(self%s%iptcl,'dist'))
        else
            call self%s%a_ptr%set(self%s%iptcl, 'dist', euldist)
        endif
        call self%s%a_ptr%set(self%s%iptcl, 'dist_inpl', dist_inpl)
        call self%s%a_ptr%set_euler(self%s%iptcl, self%o%get_euler())
        call self%s%a_ptr%set_shift(self%s%iptcl, self%o%get_2Dshift())
        call self%s%a_ptr%set(self%s%iptcl, 'frac',      frac)
        call self%s%a_ptr%set(self%s%iptcl, 'state',     1.)
        call self%s%a_ptr%set(self%s%iptcl, 'corr',      self%corr)
        call self%s%a_ptr%set(self%s%iptcl, 'specscore', self%s%specscore)
        call self%s%a_ptr%set(self%s%iptcl, 'ow',        1.0)
        call self%s%a_ptr%set(self%s%iptcl, 'sdev',      0.)
        call self%s%a_ptr%set(self%s%iptcl, 'npeaks',    1.)
        DebugPrint   '>>> STRATEGY3D_CONT_SINGLE :: EXECUTED ORIS_ASSIGN_cont_single'
    end subroutine oris_assign_cont_single

    subroutine kill_cont_single( self )
        class(strategy3D_cont_single),   intent(inout) :: self
        call self%s%kill
    end subroutine kill_cont_single

end module simple_strategy3D_cont_single

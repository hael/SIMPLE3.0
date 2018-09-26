! concrete strategy3D: probabilistic single-state refinement with hard orientation assignment
module simple_strategy3D_hard_single
include 'simple_lib.f08'
use simple_strategy3D_alloc       ! use all in there
use simple_strategy3D_utils,      only: prob_select_peak
use simple_strategy3D_hard_multi, only: strategy3D_hard_multi
use simple_parameters,            only: params_glob
use simple_builder,               only: build_glob
implicit none

public :: strategy3D_hard_single
private

#include "simple_local_flags.inc"

type, extends(strategy3D_hard_multi) :: strategy3D_hard_single
contains
    procedure :: oris_assign => oris_assign_hard_single
end type strategy3D_hard_single

contains

    subroutine oris_assign_hard_single( self )
        use simple_ori,  only: ori
        use simple_strategy3D_utils, only: estimate_shift_increment
        class(strategy3D_hard_single), intent(inout) :: self
        type(ori) :: osym
        real      :: dist_inpl, euldist, updatecnt
        real      :: shwmean, shwstdev
        integer   :: best_loc(1)
        ! extract peak info
        updatecnt = build_glob%spproj_field%get(self%s%iptcl, 'updatecnt')
        call prob_select_peak(self%s, updatecnt)
        best_loc(1) = 1 ! by definition
        call estimate_shift_increment(self%s, shwmean, shwstdev)
        ! angular distances
        call build_glob%pgrpsyms%sym_dists( build_glob%spproj_field%get_ori(self%s%iptcl),&
            &s3D%o_peaks(self%s%iptcl)%get_ori(best_loc(1)), osym, euldist, dist_inpl )
        ! set the distances before we update the orientation
        if( build_glob%spproj_field%isthere(self%s%iptcl,'dist') )then
            call build_glob%spproj_field%set(self%s%iptcl, 'dist', 0.5*euldist + 0.5*build_glob%spproj_field%get(self%s%iptcl,'dist'))
        else
            call build_glob%spproj_field%set(self%s%iptcl, 'dist', euldist)
        endif
        call build_glob%spproj_field%set(self%s%iptcl, 'dist_inpl', dist_inpl)
        ! all the other stuff
        call build_glob%spproj_field%set_euler(self%s%iptcl, s3D%o_peaks(self%s%iptcl)%get_euler(best_loc(1)))
        call build_glob%spproj_field%set_shift(self%s%iptcl, s3D%o_peaks(self%s%iptcl)%get_2Dshift(best_loc(1)))
        call build_glob%spproj_field%set(self%s%iptcl, 'state',     s3D%o_peaks(self%s%iptcl)%get(best_loc(1),'state'))
        call build_glob%spproj_field%set(self%s%iptcl, 'frac',      100.)
        call build_glob%spproj_field%set(self%s%iptcl, 'corr',      s3D%o_peaks(self%s%iptcl)%get(best_loc(1),'corr'))
        call build_glob%spproj_field%set(self%s%iptcl, 'specscore', self%s%specscore)
        call build_glob%spproj_field%set(self%s%iptcl, 'ow',        1.0)
        call build_glob%spproj_field%set(self%s%iptcl, 'proj',      s3D%o_peaks(self%s%iptcl)%get(best_loc(1),'proj'))
        call build_glob%spproj_field%set(self%s%iptcl, 'inpl',      s3D%o_peaks(self%s%iptcl)%get(best_loc(1),'inpl'))
        call build_glob%spproj_field%set(self%s%iptcl, 'spread',    0.0)
        call build_glob%spproj_field%set(self%s%iptcl, 'shwmean',   shwmean)
        call build_glob%spproj_field%set(self%s%iptcl, 'shwstdev',  shwstdev)       
        call build_glob%spproj_field%set(self%s%iptcl, 'npeaks',    1.0)
        DebugPrint   '>>> strategy3D_hard_multi :: EXECUTED oris_assign_hard_single'
    end subroutine oris_assign_hard_single

end module simple_strategy3D_hard_single

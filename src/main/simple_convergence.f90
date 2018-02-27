! for checking convergence
module simple_convergence
#include "simple_lib.f08"

use simple_oris,     only: oris
use simple_params,   only: params
use simple_cmdline,  only: cmdline
use simple_defs_conv ! use all in there
implicit none

public :: convergence
private

type convergence
    private
    class(oris),    pointer :: bap    => null() !< pointer to alignment oris object (a) part of build (b)
    class(params),  pointer :: pp     => null() !< pointer to parameters object
    class(cmdline), pointer :: pcline => null() !< pointer to command line object
    real :: corr      = 0.                      !< average correlation
    real :: dist      = 0.                      !< average angular distance
    real :: dist_inpl = 0.                      !< average in-plane angular distance
    real :: npeaks    = 0.                      !< average # peaks
    real :: frac      = 0.                      !< average fraction of search space scanned
    real :: mi_joint  = 0.                      !< joint parameter distribution overlap
    real :: mi_class  = 0.                      !< class parameter distribution overlap
    real :: mi_proj   = 0.                      !< projection parameter distribution overlap
    real :: mi_inpl   = 0.                      !< in-plane parameter distribution overlap
    real :: mi_state  = 0.                      !< state parameter distribution overlap
    real :: sdev      = 0.                      !< angular standard deviation of model
    real :: bfac      = 0.                      !< average per-particle B-factor
  contains
    procedure :: check_conv2D
    procedure :: check_conv3D
    procedure :: check_conv_cluster
    procedure :: get
    procedure :: kill
end type convergence

interface convergence
    module procedure constructor
end interface convergence

contains

    function constructor( ba, p, cline ) result( self )
        class(oris),    target, intent(in) :: ba    !< alignment oris object (a) part of build (b)
        class(params),  target, intent(in) :: p     !< parameters object
        class(cmdline), target, intent(in) :: cline !< command line object
        type(convergence) :: self
        self%bap    => ba
        self%pp     => p
        self%pcline => cline
    end function constructor

    function check_conv2D( self, ncls ) result( converged )
        class(convergence), intent(inout) :: self
        integer, optional,  intent(in)    :: ncls
        real,    allocatable :: updatecnts(:)
        logical, allocatable :: mask(:)
        logical :: converged
        integer :: nncls
        if( present(ncls) )then
            nncls = ncls
        else
            nncls = self%pp%ncls
        endif
        if( self%pp%l_frac_update )then
            ! fractional particle update
            updatecnts     = self%bap%get_all('updatecnt')
            allocate(mask(size(updatecnts)), source=updatecnts > 0.5)
            self%corr      = self%bap%get_avg('corr',      mask=mask)
            self%dist_inpl = self%bap%get_avg('dist_inpl', mask=mask)
            self%frac      = self%bap%get_avg('frac',      mask=mask)
            self%bfac      = self%bap%get_avg('bfac',      mask=mask)
            self%mi_joint  = self%bap%get_avg('mi_joint',  mask=mask)
            self%mi_inpl   = self%bap%get_avg('mi_inpl',   mask=mask)
            self%mi_class  = self%bap%get_avg('mi_class',  mask=mask)
        else
            self%corr      = self%bap%get_avg('corr')
            self%dist_inpl = self%bap%get_avg('dist_inpl')
            self%frac      = self%bap%get_avg('frac')
            self%bfac      = self%bap%get_avg('bfac')
            self%mi_joint  = self%bap%get_avg('mi_joint')
            self%mi_class  = self%bap%get_avg('mi_class')
            self%mi_inpl   = self%bap%get_avg('mi_inpl')
        endif
        write(*,'(A,1X,F7.4)') '>>> JOINT    DISTRIBUTION OVERLAP:     ', self%mi_joint
        write(*,'(A,1X,F7.4)') '>>> CLASS    DISTRIBUTION OVERLAP:     ', self%mi_class
        write(*,'(A,1X,F7.4)') '>>> IN-PLANE DISTRIBUTION OVERLAP:     ', self%mi_inpl
        write(*,'(A,1X,F7.1)') '>>> AVERAGE IN-PLANE ANGULAR DISTANCE: ', self%dist_inpl
        write(*,'(A,1X,F7.1)') '>>> AVERAGE PER-PARTICLE B-FACTOR:     ', self%bfac
        write(*,'(A,1X,F7.1)') '>>> PERCENTAGE OF SEARCH SPACE SCANNED:', self%frac
        write(*,'(A,1X,F7.4)') '>>> CORRELATION:                       ', self%corr
        ! dynamic shift search range update
        if( self%frac >= FRAC_SH_LIM )then
            if( .not. self%pcline%defined('trs') .or. self%pp%trs <  MINSHIFT )then
                ! determine shift bounds
                self%pp%trs = MSK_FRAC*real(self%pp%msk)
                self%pp%trs = max(MINSHIFT,self%pp%trs)
                self%pp%trs = min(MAXSHIFT,self%pp%trs)
                ! set shift search flag
                self%pp%l_doshift = .true.
            endif
        endif
        ! determine convergence
        if( nncls > 1 )then
            converged = .false.
            if( self%pp%l_frac_update )then
                if( self%mi_joint > MI_CLASS_LIM_2D_FRAC .and. self%frac > FRAC_LIM_FRAC )converged = .true.
            else
                if( self%mi_class > MI_CLASS_LIM_2D .and. self%frac > FRAC_LIM )converged = .true.
            endif
            if( converged )then
                write(*,'(A)') '>>> CONVERGED: .YES.'
            else
                write(*,'(A)') '>>> CONVERGED: .NO.'
            endif
        else
            if( self%mi_inpl > MI_INPL_LIM .or. self%dist_inpl < 0.5 )then
                write(*,'(A)') '>>> CONVERGED: .YES.'
                converged = .true.
            else
                write(*,'(A)') '>>> CONVERGED: .NO.'
                converged = .false.
            endif
        endif
    end function check_conv2D

    function check_conv3D( self, update_res ) result( converged )
        class(convergence), intent(inout) :: self
        logical, optional,  intent(inout) :: update_res
        real,    allocatable :: state_mi_joint(:), statepops(:), updatecnts(:)
        logical, allocatable :: mask(:)
        real    :: min_state_mi_joint
        logical :: converged
        integer :: iptcl, istate
        if( self%bap%isthere('updatecnt') )then
            ! fractional particle update
            updatecnts     = self%bap%get_all('updatecnt')
            allocate(mask(size(updatecnts)), source=updatecnts > 0.5)
            self%corr      = self%bap%get_avg('corr',      mask=mask)
            self%dist      = self%bap%get_avg('dist',      mask=mask)
            self%dist_inpl = self%bap%get_avg('dist_inpl', mask=mask)
            self%npeaks    = self%bap%get_avg('npeaks',    mask=mask)
            self%frac      = self%bap%get_avg('frac',      mask=mask)
            self%mi_joint  = self%bap%get_avg('mi_joint',  mask=mask)
            self%mi_proj   = self%bap%get_avg('mi_proj',   mask=mask)
            self%mi_inpl   = self%bap%get_avg('mi_inpl',   mask=mask)
            self%mi_state  = self%bap%get_avg('mi_state',  mask=mask)
            self%sdev      = self%bap%get_avg('sdev',      mask=mask)
            self%bfac      = self%bap%get_avg('bfac',      mask=mask)
        else
            self%corr      = self%bap%get_avg('corr')
            self%dist      = self%bap%get_avg('dist')
            self%dist_inpl = self%bap%get_avg('dist_inpl')
            self%npeaks    = self%bap%get_avg('npeaks')
            self%frac      = self%bap%get_avg('frac')
            self%mi_joint  = self%bap%get_avg('mi_joint')
            self%mi_proj   = self%bap%get_avg('mi_proj')
            self%mi_inpl   = self%bap%get_avg('mi_inpl')
            self%mi_state  = self%bap%get_avg('mi_state')
            self%sdev      = self%bap%get_avg('sdev')
            self%bfac      = self%bap%get_avg('bfac')
        endif
        if( self%pp%athres==0. )then
            ! required for distributed mode
            self%pp%athres = rad2deg( atan(max(self%pp%fny, self%pp%lp)/(self%pp%moldiam/2.)) )
        endif
        write(*,'(A,1X,F7.1)') '>>> ANGLE OF FEASIBLE REGION:          ', self%pp%athres
        write(*,'(A,1X,F7.4)') '>>> JOINT    DISTRIBUTION OVERLAP:     ', self%mi_joint
        write(*,'(A,1X,F7.4)') '>>> PROJ     DISTRIBUTION OVERLAP:     ', self%mi_proj
        write(*,'(A,1X,F7.4)') '>>> IN-PLANE DISTRIBUTION OVERLAP:     ', self%mi_inpl
        if( self%pp%nstates > 1 )&
        write(*,'(A,1X,F7.4)') '>>> STATE DISTRIBUTION OVERLAP:        ', self%mi_state
        write(*,'(A,1X,F7.1)') '>>> AVERAGE ANGULAR DISTANCE BTW ORIS: ', self%dist
        write(*,'(A,1X,F7.1)') '>>> AVERAGE IN-PLANE ANGULAR DISTANCE: ', self%dist_inpl
        write(*,'(A,1X,F7.1)') '>>> AVERAGE # PEAKS:                   ', self%npeaks
        write(*,'(A,1X,F7.1)') '>>> AVERAGE PER-PARTICLE B-FACTOR:     ', self%bfac
        write(*,'(A,1X,F7.1)') '>>> PERCENTAGE OF SEARCH SPACE SCANNED:', self%frac
        write(*,'(A,1X,F7.4)') '>>> CORRELATION:                       ', self%corr
        write(*,'(A,1X,F7.2)') '>>> ANGULAR SDEV OF MODEL:             ', self%sdev
        ! automatic resolution stepping
        if( present(update_res) )then
            if( update_res )then
                ! the previous round updated the resolution limit, so
                ! don't update this round
                update_res = .false.
            else
                update_res = .false.
                if(       self%pp%dynlp .eq. 'yes'  .and. &
                    .not. self%pcline%defined('lp') .and. &
                          self%dist <= self%pp%athres/2. )then
                    update_res = .true.
                endif
            endif
            if( update_res )then
                write(*,'(A)') '>>> UPDATE LOW-PASS LIMIT: .YES.'
            else
                write(*,'(A)') '>>> UPDATE LOW-PASS LIMIT: .NO.'
            endif
        else
            if( self%pcline%defined('find') .and. self%dist <= self%pp%athres/2. )then
                write(*,'(A)') '>>> UPDATE LOW-PASS LIMIT: .YES.'
            else
                write(*,'(A)') '>>> UPDATE LOW-PASS LIMIT: .NO.'
            endif
        endif
        ! dynamic shift search range update
        if( self%frac >= FRAC_SH_LIM )then
            if( .not. self%pcline%defined('trs') .or. self%pp%trs <  MINSHIFT )then
                ! determine shift bounds
                self%pp%trs = MSK_FRAC*real(self%pp%msk)
                self%pp%trs = max(MINSHIFT,self%pp%trs)
                self%pp%trs = min(MAXSHIFT,self%pp%trs)
                ! set shift search flag
                self%pp%l_doshift = .true.
            endif
        endif
        ! determine convergence
        if( self%pp%nstates == 1 )then
            if( self%dist < self%pp%athres/5. .and.&
                self%frac > FRAC_LIM          .and.&
                self%mi_proj > MI_CLASS_LIM_3D )then
                write(*,'(A)') '>>> CONVERGED: .YES.'
                converged = .true.
            else
                write(*,'(A)') '>>> CONVERGED: .NO.'
                converged = .false.
            endif
        else
            ! provides convergence stats for multiple states
            ! by calculating mi_joint for individual states
            allocate( state_mi_joint(self%pp%nstates), statepops(self%pp%nstates) )
            state_mi_joint = 0.
            statepops      = 0.
            do iptcl=1,self%bap%get_noris()
                istate = nint(self%bap%get(iptcl,'state'))
                if( istate==0 )cycle
                ! it doesn't make sense to include the state overlap here
                ! as the overall state overlap is already provided above
                state_mi_joint(istate) = state_mi_joint(istate) + self%bap%get(iptcl,'mi_proj')
                state_mi_joint(istate) = state_mi_joint(istate) + self%bap%get(iptcl,'mi_inpl')
                ! 2.0 because we include two mi-values
                statepops(istate)      = statepops(istate) + 2.0
            end do
            ! normalise the overlap
            forall( istate=1:self%pp%nstates, statepops(istate)>0. )&
                &state_mi_joint(istate) = state_mi_joint(istate)/statepops(istate)
            ! bring back the correct statepops
            statepops = statepops/2.0
            ! the minumum overlap is in charge of convergence
            min_state_mi_joint = minval(state_mi_joint, MASK=statepops>0.)
            ! print the overlaps and pops for the different states
            do istate=1,self%pp%nstates
                write(*,'(A,1X,I3,1X,A,1X,F7.4,1X,A,1X,I8)') '>>> STATE', istate,&
                'DISTRIBUTION OVERLAP:', state_mi_joint(istate), 'POPULATION:', nint(statepops(istate))
            end do
            if( min_state_mi_joint > MI_STATE_LIM      .and.&
                self%mi_state      > MI_STATE_LIM      .and.&
                self%dist          < self%pp%athres/5. .and.&
                self%frac          > FRAC_LIM                )then
                write(*,'(A)') '>>> CONVERGED: .YES.'
                converged = .true.
            else
                write(*,'(A)') '>>> CONVERGED: .NO.'
                converged = .false.
            endif
            deallocate( state_mi_joint, statepops )
        endif
    end function check_conv3D

    function check_conv_cluster( self ) result( converged )
        class(convergence), intent(inout) :: self
        real, allocatable :: statepops(:)
        logical           :: converged
        integer           :: iptcl, istate
        self%frac      = self%bap%get_avg('frac')
        self%mi_state  = self%bap%get_avg('mi_state')
        write(*,'(A,1X,F7.4)') '>>> STATE DISTRIBUTION OVERLAP:        ', self%mi_state
        write(*,'(A,1X,F7.1)') '>>> PERCENTAGE OF SEARCH SPACE SCANNED:', self%frac
        ! provides convergence stats for multiple states
        ! by calculating mi_joint for individual states
        allocate( statepops(self%pp%nstates) )
        statepops      = 0.
        do iptcl=1,self%bap%get_noris()
            istate = nint(self%bap%get(iptcl,'state'))
            if( istate==0 )cycle
            statepops(istate) = statepops(istate) + 1.0
        end do
        if( self%bap%isthere('bfac') )then
            self%bfac = self%bap%get_avg('bfac')
            write(*,'(A,1X,F7.1)') '>>> AVERAGE PER-PARTICLE B-FACTOR: ', self%bfac
        endif
        self%corr = self%bap%get_avg('corr')
        write(*,'(A,1X,F7.4)') '>>> CORRELATION                  :', self%corr
        ! print the overlaps and pops for the different states
        do istate=1,self%pp%nstates
            write(*,'(A,I2,1X,A,1X,I8)') '>>> STATE ',istate,'POPULATION:', nint(statepops(istate))
        end do
        if( self%mi_state > HET_MI_STATE_LIM .and.&
            self%frac     > HET_FRAC_LIM     )then
            write(*,'(A)') '>>> CONVERGED: .YES.'
            converged = .true.
        else
            write(*,'(A)') '>>> CONVERGED: .NO.'
            converged = .false.
        endif
        deallocate( statepops )
    end function check_conv_cluster

    !>  \brief  is a getter
    real function get( self, which )
        class(convergence), intent(in) :: self
        character(len=*),   intent(in) :: which
        select case(which)
            case('corr')
                get = self%corr
            case('dist')
                get = self%dist
            case('dist_inpl')
                get = self%dist_inpl
            case('frac')
                get = self%frac
            case('mi_joint')
                get = self%mi_joint
            case('mi_class')
                get = self%mi_class
            case('mi_proj')
                get = self%mi_proj
            case('mi_inpl')
                get = self%mi_inpl
            case('mi_state')
                get = self%mi_state
            case('sdev')
                get = self%sdev
            case('bfac')
                get = self%bfac
            case DEFAULT
        end select
    end function get

    subroutine kill( self )
        class(convergence), intent(inout) :: self
        self%bap    => null()
        self%pp     => null()
        self%pcline => null()
    end subroutine kill

end module simple_convergence

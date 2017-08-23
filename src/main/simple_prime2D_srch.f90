! PRIME2D stochastic search routines
module simple_prime2D_srch
use simple_polarft_corrcalc, only: polarft_corrcalc
use simple_pftcc_inplsrch,   only: pftcc_inplsrch
use simple_oris,             only: oris
use simple_defs              ! use all in there
use simple_math              ! use all in there
implicit none

public :: prime2D_srch
private
#include "simple_local_flags.inc"

type prime2D_srch
    private
    type(pftcc_inplsrch)  :: inplsrch_obj         !< in-plane search object
    integer               :: nrefs         =  0   !< number of references
    integer               :: nrots         =  0   !< number of in-plane rotations in polar representation
    integer               :: nrefs_eval    =  0   !< nr of references evaluated
    integer               :: prev_class    =  0   !< previous class index
    integer               :: best_class    =  0   !< best class index found by search
    integer               :: prev_rot      =  0   !< previous in-plane rotation index
    integer               :: best_rot      =  0   !< best in-plane rotation found by search
    integer               :: nthr          =  0   !< number of threads
    integer               :: fromp         =  1   !< from particle index
    integer               :: top           =  1   !< to particle index
    integer               :: nnn           =  0   !< # nearest neighbors
    real                  :: trs           =  0.  !< shift range parameter [-trs,trs]
    real                  :: prev_shvec(2) =  0.  !< previous origin shift vector
    real                  :: best_shvec(2) =  0.  !< best shift vector found by search
    real                  :: prev_corr     = -1.  !< previous best correlation
    real                  :: best_corr     = -1.  !< best corr found by search
    real                  :: specscore     =  0.  !< spectral score
    integer, allocatable  :: srch_order(:)        !< stochastic search order
    character(len=STDLEN) :: refine        = ''   !< refinement flag
    logical               :: doshift = .true.     !< origin shift search indicator
    logical               :: exists  = .false.    !< 2 indicate existence
  contains
    ! CONSTRUCTOR
    procedure          :: new
    ! GETTERS
    procedure          :: get_nrots
    procedure          :: update_best
    ! PREPARATION ROUTINE
    procedure          :: prep4srch
    ! CALCULATION ROUTINES
    procedure, private :: calc_specscore
    ! SEARCH ROUTINES
    procedure          :: exec_prime2D_srch
    procedure          :: greedy_srch
    procedure          :: stochastic_srch
    procedure          :: nn_srch
    procedure, private :: inpl_srch
    ! DESTRUCTOR
    procedure          :: kill
end type prime2D_srch

contains

    ! CONSTRUCTOR
    
    !>  \brief  is a constructor
    subroutine new( self, p, pftcc )
        use simple_params, only: params
        class(prime2D_srch),     intent(inout) :: self
        class(params),           intent(in)    :: p
        class(polarft_corrcalc), intent(inout) :: pftcc
        integer :: alloc_stat, i
        real    :: lims(2,2)
        ! destroy possibly pre-existing instance
        call self%kill
        ! set constants
        self%nrefs       =  p%ncls
        self%nrots       =  round2even(twopi*real(p%ring2))
        self%nrefs_eval  =  0
        self%trs         =  p%trs
        self%doshift     =  p%doshift
        self%refine      =  p%refine
        self%nthr        =  p%nthr
        self%fromp       =  p%fromp
        self%top         =  p%top
        self%nnn         =  p%nnn
        ! construct composites
        lims(1,1)        = -self%trs
        lims(1,2)        =  self%trs
        lims(2,1)        = -self%trs
        lims(2,2)        =  self%trs
        call self%inplsrch_obj%new(pftcc, lims, nrestarts=3, maxits=30)
        ! the instance now exists
        self%exists = .true.
        DebugPrint '>>> PRIME2D_SRCH::CONSTRUCTED NEW SIMPLE_PRIME2D_SRCH OBJECT'
    end subroutine new

    ! GETTERS

    !>  \brief nrots getter
    pure integer function get_nrots( self )
        class(prime2D_srch), intent(in) :: self
        get_nrots = self%nrots
    end function get_nrots
    
    !>  \brief  to get the class
    subroutine update_best( self, pftcc, iptcl, a )
        use simple_math, only: myacos, rotmat2d, rad2deg
        use simple_ori,  only: ori
        class(prime2D_srch),     intent(in)    :: self
        class(polarft_corrcalc), intent(inout) :: pftcc
        integer,                 intent(in)    :: iptcl
        class(oris),             intent(inout) :: a
        type(ori) :: o_new, o_old
        real      :: euls(3), mi_class, mi_inpl, mi_joint
        ! get previous orientation
        o_old = a%get_ori(iptcl)
        o_new = o_old
        ! get in-plane angle
        euls     = 0.
        euls(3)  = 360.-pftcc%get_rot(self%best_rot) ! change sgn to fit convention
        if( euls(3) == 360. ) euls(3) = 0.
        call o_new%set_euler(euls)
        ! calculate overlap between distributions
        mi_class = 0.
        mi_inpl  = 0.
        mi_joint = 0.
        if( self%prev_class == self%best_class )then
            mi_class = mi_class + 1.
            mi_joint = mi_joint + 1.
        endif
        if( self%prev_rot ==  self%best_rot )then
            mi_inpl  = mi_inpl  + 1.
            mi_joint = mi_joint + 1.
        endif 
        mi_joint = mi_joint / 2.
        ! updates parameters
        call o_new%set_shift(self%prev_shvec + self%best_shvec) ! shifts must be obtained by vector addition
        call o_new%set('class',     real(self%best_class))
        call o_new%set('corr',      self%best_corr)
        call o_new%set('specscore', self%specscore)
        call o_new%set('dist_inpl', rad2deg( o_old.inplrotdist.o_new ))
        call o_new%set('mi_class',  mi_class)
        call o_new%set('mi_inpl',   mi_inpl)
        call o_new%set('mi_joint',  mi_joint)
        call o_new%set('frac',      100.*(real(self%nrefs_eval)/real(self%nrefs)))
        ! updates orientation
        call a%set_ori(iptcl, o_new)
        ! cleanup
        call o_old%kill
        call o_new%kill
        DebugPrint '>>> PRIME2D_SRCH::GOT BEST ORI'
    end subroutine update_best

    ! PREPARATION ROUTINES

    !>  \brief  prepares for the search
    subroutine prep4srch( self, pftcc, iptcl, a )
        use simple_ran_tabu, only: ran_tabu
        class(prime2D_srch),     intent(inout) :: self
        class(polarft_corrcalc), intent(inout) :: pftcc
        integer,                 intent(in)    :: iptcl
        class(oris),             intent(inout) :: a
        type(ran_tabu)    :: rt
        ! find previous discrete alignment parameters
        self%prev_class = nint(a%get(iptcl,'class'))           ! class index
        self%prev_rot   = pftcc%get_roind(360.-a%e3get(iptcl)) ! in-plane angle index
        self%prev_shvec = [a%get(iptcl,'x'),a%get(iptcl,'y')]  ! shift vector
        ! set best to previous best by default
        self%best_class = self%prev_class         
        self%best_rot   = self%prev_rot
        ! calculate previous best corr (treshold for better)
        self%prev_corr  = max( 0., pftcc%corr(self%prev_class, iptcl, self%prev_rot) )
        self%best_corr  = self%prev_corr
        if( self%prev_class > 0 )then
            ! calculate previous best corr (treshold for better)
            self%prev_corr  = max( 0., pftcc%corr(self%prev_class, iptcl, self%prev_rot) )
            self%best_corr  = self%prev_corr
        else
            self%prev_corr = 0.
            self%best_corr = 0.
        endif
        ! make random reference direction order
        rt = ran_tabu(self%nrefs)
        if( allocated(self%srch_order) ) deallocate(self%srch_order)
        allocate(self%srch_order(self%nrefs))
        call rt%ne_ran_iarr(self%srch_order)
        ! put prev_best last to avoid cycling
        call put_last(self%prev_class, self%srch_order)
        call rt%kill
        if( any(self%srch_order == 0) ) stop 'Invalid index in srch_order; simple_prime2D_srch :: prep4srch'
        DebugPrint '>>> PRIME2D_SRCH::PREPARED FOR SIMPLE_PRIME2D_SRCH'
    end subroutine prep4srch

    ! CALCULATION ROUTINES

    subroutine calc_specscore( self, pftcc, iptcl )
        class(prime2D_srch),     intent(inout) :: self
        class(polarft_corrcalc), intent(inout) :: pftcc
        integer,                 intent(in)    :: iptcl
        real, allocatable :: frc(:)
        if( self%best_class <= 0 )stop 'Invalid class index in simple_prime2D_srch%calc_specscore'
        frc = pftcc%genfrc(self%best_class, iptcl, self%best_rot)
        self%specscore = max(0.,median_nocopy(frc))
    end subroutine calc_specscore

    ! SEARCH ROUTINES

    !>  \brief the master prime search routine
    subroutine exec_prime2D_srch( self, pftcc, iptcl, a, greedy, extr_bound )
        class(prime2D_srch),     intent(inout) :: self
        class(polarft_corrcalc), intent(inout) :: pftcc
        integer,                 intent(in)    :: iptcl
        class(oris),             intent(inout) :: a
        logical, optional,       intent(in)    :: greedy
        real,    optional,       intent(in)    :: extr_bound
        logical :: ggreedy
        if( self%refine .eq. 'yes' )then
            ggreedy = .true.
        else
            ggreedy = .false.
            if( present(greedy) ) ggreedy = greedy
        endif
        if( ggreedy )then
            call self%greedy_srch(pftcc, iptcl, a)
        else
            call self%stochastic_srch(pftcc, iptcl, a, extr_bound)
        endif
        ! memory management (important for ompenMP distr over arrays of prime2D_srch objects)
        if( allocated(self%srch_order) ) deallocate(self%srch_order)
        DebugPrint '>>> PRIME2D_SRCH::EXECUTED PRIME2D_SRCH'
    end subroutine exec_prime2D_srch

    !>  \brief  executes greedy rotational search (for initialisation)
    subroutine greedy_srch( self, pftcc, iptcl, a )
        class(prime2D_srch),     intent(inout) :: self
        class(polarft_corrcalc), intent(inout) :: pftcc
        integer,                 intent(in)    :: iptcl
        class(oris),             intent(inout) :: a
        integer :: iref,loc(1),inpl_ind
        real    :: corrs(self%nrots),inpl_corr,corr
        if( nint(a%get(iptcl,'state')) > 0 )then
            call self%prep4srch( pftcc, iptcl, a )
            corr = self%prev_corr
            do iref=1,self%nrefs
                corrs     = pftcc%gencorrs(iref, iptcl) 
                loc       = maxloc(corrs)
                inpl_ind  = loc(1)
                inpl_corr = corrs(inpl_ind)         
                if( inpl_corr >= corr )then
                    corr            = inpl_corr
                    self%best_class = iref
                    self%best_corr  = inpl_corr
                    self%best_rot   = inpl_ind
                endif    
            end do
            self%nrefs_eval = self%nrefs
            call self%inpl_srch(pftcc, iptcl)
            call self%calc_specscore(pftcc, iptcl)
            call self%update_best(pftcc, iptcl, a)
        else
            call a%reject(iptcl)
        endif
        DebugPrint '>>> PRIME2D_SRCH::FINISHED STOCHASTIC SEARCH'
    end subroutine greedy_srch

    !>  \brief  executes stochastic rotational search
    subroutine stochastic_srch( self, pftcc, iptcl, a, extr_bound )
        use simple_rnd,  only: shcloc
        class(prime2D_srch),     intent(inout) :: self
        class(polarft_corrcalc), intent(inout) :: pftcc
        integer,                 intent(in)    :: iptcl
        class(oris),             intent(inout) :: a
        real, optional,          intent(in)    :: extr_bound
        integer :: iref,loc(1),isample,inpl_ind
        real    :: corrs(self%nrots), inpl_corr
        logical :: found_better
        real    :: corr_bound
        if( nint(a%get(iptcl,'state')) > 0 )then
            corr_bound = -1.0
            if( present(extr_bound) ) corr_bound = extr_bound
            call self%prep4srch( pftcc, iptcl, a )
            if( corr_bound < 0. .or. self%prev_corr > corr_bound )then
                found_better = .false.
                self%nrefs_eval = 0
                do isample=1,self%nrefs
                    iref = self%srch_order( isample )
                    ! keep track of how many references we are evaluating
                    self%nrefs_eval = self%nrefs_eval + 1
                    ! shc update
                    corrs     = pftcc%gencorrs(iref, iptcl) 
                    inpl_ind  = shcloc(self%nrots, corrs, self%prev_corr)
                    inpl_corr = 0.
                    if( inpl_ind > 0 ) inpl_corr = corrs(inpl_ind)             
                    if( inpl_ind > 0 .and. inpl_corr >= self%prev_corr )then
                        self%best_class = iref
                        self%best_corr  = inpl_corr
                        self%best_rot   = inpl_ind
                        found_better    = .true.
                        exit ! first-improvement heuristic
                    endif    
                end do
            else
                self%nrefs_eval = 1 ! evaluate one random ref
                iref            = self%srch_order(1) ! random .ne. prev
                corrs           = pftcc%gencorrs(iref, iptcl) 
                loc             = maxloc(corrs)
                inpl_ind        = loc(1)
                inpl_corr       = corrs(inpl_ind)
                self%best_class = iref
                self%best_corr  = inpl_corr
                self%best_rot   = inpl_ind
                found_better    = .true.
            endif
            if( found_better )then
                ! best ref has already been updated
            else
                ! keep the old parameters
                self%best_class = self%prev_class 
                self%best_corr  = self%prev_corr
                self%best_rot   = self%prev_rot
            endif
            call self%inpl_srch(pftcc, iptcl)
            call self%calc_specscore(pftcc, iptcl)
            call self%update_best(pftcc, iptcl, a)
        else
            call a%reject(iptcl)
        endif
        DebugPrint '>>> PRIME2D_SRCH::FINISHED STOCHASTIC SEARCH'
    end subroutine stochastic_srch

    !>  \brief  executes nearest-neighbor rotational search
    subroutine nn_srch( self, pftcc, iptcl, a, nnmat )
        use simple_rnd,  only: shcloc
        class(prime2D_srch),     intent(inout) :: self
        class(polarft_corrcalc), intent(inout) :: pftcc
        integer,                 intent(in)    :: iptcl
        class(oris),             intent(inout) :: a
        integer,                 intent(in)    :: nnmat(self%nrefs,self%nnn)
        real, allocatable :: frc(:)
        integer           :: iref,loc(1),inpl_ind,inn
        real              :: corrs(self%nrots),inpl_corr,corr
        if( nint(a%get(iptcl,'state')) > 0 )then
            ! find previous discrete alignment parameters
            self%prev_class = nint(a%get(iptcl,'class'))                  ! class index
            self%prev_rot   = pftcc%get_roind(360.-a%e3get(iptcl)) ! in-plane angle index
            self%prev_shvec = [a%get(iptcl,'x'),a%get(iptcl,'y')]         ! shift vector
            ! set best to previous best by default
            self%best_class = self%prev_class         
            self%best_rot   = self%prev_rot
            ! calculate spectral score
            frc             = pftcc%genfrc(self%prev_class, iptcl, self%prev_rot)
            self%specscore  = max(0.,median_nocopy(frc))
            corr            = -1.
            ! evaluate neighbors (greedy selection)
            do inn=1,self%nnn
                iref      = nnmat(self%prev_class,inn)
                corrs     = pftcc%gencorrs(iref, iptcl) 
                loc       = maxloc(corrs)
                inpl_ind  = loc(1)
                inpl_corr = corrs(inpl_ind)         
                if( inpl_corr >= corr )then
                    corr            = inpl_corr
                    self%best_class = iref
                    self%best_corr  = inpl_corr
                    self%best_rot   = inpl_ind
                endif    
            end do
            self%nrefs_eval = self%nrefs
            call self%inpl_srch(pftcc, iptcl)
            call self%calc_specscore(pftcc, iptcl)
            call self%update_best(pftcc, iptcl, a)
        else
            call a%reject(iptcl)
        endif
        DebugPrint '>>> PRIME2D_SRCH::FINISHED NEAREST-NEIGHBOR SEARCH'
    end subroutine nn_srch

    !>  \brief  executes the shift search over the best matching reference
    subroutine inpl_srch( self, pftcc, iptcl )
        class(prime2D_srch),     intent(inout) :: self
        class(polarft_corrcalc), intent(inout) :: pftcc
        integer,                 intent(in)    :: iptcl
        real, allocatable :: crxy(:)
        real :: corr_before, corr_after
        self%best_shvec = [0.,0.]
        if( self%doshift )then
            corr_before = self%best_corr
            call self%inplsrch_obj%set_indices(self%best_class, iptcl)
            crxy = self%inplsrch_obj%minimize(irot=self%best_rot)
            corr_after = crxy(1)
            if( corr_after > corr_before )then
                self%best_corr = crxy(1)
                ! no negation of angle here, see pftcc_inplsrch class
                self%best_rot  = pftcc%get_roind( crxy(2) ) 
                self%best_shvec = crxy(3:4)
            endif
        endif
        if( DEBUG ) write(*,'(A)') '>>> PRIME2D_SRCH::FINISHED SHIFT SEARCH'
    end subroutine inpl_srch

    ! DESTRUCTOR

    !>  \brief  is a destructor
    subroutine kill( self )
        class(prime2D_srch), intent(inout) :: self !< instance
        if( self%exists )then
            if( allocated(self%srch_order) ) deallocate(self%srch_order)
            self%exists = .false.
        endif
    end subroutine kill

end module simple_prime2D_srch

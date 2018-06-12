! fast cross-correlation calculation between Fourier volumes using the icosahedral group
! as a sampling space

module simple_volpft_corrcalc
!$ use omp_lib
!$ use omp_lib_kinds
include 'simple_lib.f08'
use simple_projector, only: projector
use simple_sym,       only: sym
use simple_ori,       only: ori
implicit none

type :: volpft_corrcalc
    private
    class(projector), pointer :: vol_ref=>null()          !< pointer to reference volume
    class(projector), pointer :: vol_target=>null()       !< pointer to target volume
    type(sym)                 :: ico                      !< defines the icosahedral group
    integer                   :: nspace          = 0      !< number of vec:s in representation
    integer                   :: kfromto_vpft(2) = 0      !< Fourier index range
    real                      :: hp                       !< high-pass limit
    real                      :: lp                       !< low-pass limit
    real                      :: sqsum_ref                !< memoized square sum 4 corrcalc (ref)
    real                      :: sqsum_target             !< memoized square sum 4 corrcalc (target)
    complex, allocatable      :: vpft_ref(:,:)            !< reference lines 4 matching
    complex, allocatable      :: vpft_target(:,:)         !< target lines 4 matching
    real,    allocatable      :: locs_ref(:,:,:)          !< nspace x nk x 3 matrix of positions (reference)
    logical                   :: existence_vpft = .false. !< to indicate existence
  contains
    ! CONSTRUCTOR
    procedure          :: new
    ! GETTERS
    procedure          :: get_nspace
    procedure          :: get_kfromto
    procedure          :: get_target
    ! INTERPOLATION METHODS
    procedure, private :: extract_ref
    procedure, private :: extract_target_1
    procedure, private :: extract_target_2
    procedure, private :: extract_target_3
    generic            :: extract_target => extract_target_1, extract_target_2, extract_target_3
    ! CORRELATORS
    procedure, private :: corr_1
    procedure, private :: corr_2
    procedure, private :: corr_3
    procedure, private :: corr_4
    procedure, private :: corr_5
    generic            :: corr => corr_1, corr_2, corr_3, corr_4, corr_5
    ! DESTRUCTOR
    procedure          :: kill
end type volpft_corrcalc

contains

    !>  \brief  is a constructor
    subroutine new( self, vol_ref, vol_target, hp, lp, alpha )
        class(volpft_corrcalc),    intent(inout) :: self
        class(projector), target , intent(in)    :: vol_ref, vol_target
        real,                      intent(in)    :: hp, lp, alpha
        integer    :: isym, k
        real       :: vec(3)
        type(ori)  :: e
        call self%kill
        if( vol_ref.eqdims.vol_target )then
            ! all good
        else
            call simple_stop('The volumes to be matched are not of the same dimension; simple_volpft_corrcalc :: new')
        endif
        ! set pointers
        ! we assume that the volumes have been masked and prepared with prep4cgrid
        self%vol_ref    => vol_ref
        self%vol_target => vol_target
        self%hp         =  hp
        self%lp         =  lp
        ! make the icosahedral group
        call self%ico%new('ico')
        self%nspace = self%ico%get_nsym()
        ! set other stuff
        self%kfromto_vpft(1) = vol_ref%get_find(hp)
        self%kfromto_vpft(2) = vol_ref%get_find(lp)
        allocate( self%vpft_ref(self%kfromto_vpft(1):self%kfromto_vpft(2),self%nspace),&
                  self%vpft_target(self%kfromto_vpft(1):self%kfromto_vpft(2),self%nspace),&
                  self%locs_ref(self%kfromto_vpft(1):self%kfromto_vpft(2),self%nspace,3), stat=alloc_stat)
        if(alloc_stat.ne.0)call allocchk("In: simple_volpft_corrcalc :: new",alloc_stat)
        ! generate sampling space
        do isym=1,self%nspace
            ! get symmetry rotation matrix
            e = self%ico%get_symori(isym)
            ! loop over resolution shells
            do k=self%kfromto_vpft(1),self%kfromto_vpft(2)
                ! calculate sampling location
                vec(1) = 0.
                vec(2) = 0.
                vec(3) = real(k)
                self%locs_ref(k,isym,:) = matmul(vec,e%get_mat())
            end do
        end do
        ! prepare for fast interpolation
        call self%vol_ref%fft()
        call self%vol_ref%expand_cmat(alpha)
        call self%vol_target%fft()
        call self%vol_target%expand_cmat(alpha)
        ! extract the reference lines
        call self%extract_ref
        self%existence_vpft = .true.
    end subroutine new

    ! GETTERS

    pure function get_nspace( self ) result( nspace )
        class(volpft_corrcalc), intent(in) :: self
        integer :: nspace
        nspace = self%nspace
    end function get_nspace

    pure function get_kfromto( self ) result( kfromto )
        class(volpft_corrcalc), intent(in) :: self
        integer :: kfromto(2)
        kfromto(1) = self%kfromto_vpft(1)
        kfromto(2) = self%kfromto_vpft(2)
    end function get_kfromto

    pure subroutine get_target( self, target_out )
        class(volpft_corrcalc), intent(in) :: self
        complex,                intent(out) :: target_out(self%kfromto_vpft(1):self%kfromto_vpft(2),self%nspace)
        target_out = self%vpft_target
    end subroutine get_target

    ! INTERPOLATION METHODS

    !>  \brief  extracts the lines defined by the icosahedral group from the reference
    subroutine extract_ref( self )
        class(volpft_corrcalc), intent(inout) :: self
        integer :: ispace, k
        !$omp parallel do collapse(2) schedule(static) default(shared)&
        !$omp private(ispace,k) proc_bind(close)
        do ispace=1,self%nspace
            do k=self%kfromto_vpft(1),self%kfromto_vpft(2)
                self%vpft_ref(k,ispace) =&
                self%vol_ref%interp_fcomp(self%locs_ref(k,ispace,:))
            end do
        end do
        !$omp end parallel do
        self%sqsum_ref = sum(csq(self%vpft_ref))
    end subroutine extract_ref

    !>  \brief  extracts the lines required for matchiing
    !!          from the reference
    subroutine extract_target_1( self, e )
        class(volpft_corrcalc), intent(inout) :: self
        class(ori),             intent(in)    :: e
        real    :: loc(3), mat(3,3)
        integer :: ispace, k
        mat = e%get_mat()
        do ispace=1,self%nspace
            do k=self%kfromto_vpft(1),self%kfromto_vpft(2)
                loc  = matmul(self%locs_ref(k,ispace,:),mat)
                self%vpft_target(k,ispace) = self%vol_target%interp_fcomp(loc)
            end do
        end do
        self%sqsum_target = sum(csq(self%vpft_target))
    end subroutine extract_target_1

    !>  \brief  extracts the lines required for matchiing
    !!          from the reference
    subroutine extract_target_2( self, e, shvec )
        class(volpft_corrcalc), intent(inout) :: self
        class(ori),             intent(in)    :: e
        real,                   intent(in)    :: shvec(3)
        real    :: loc(3), mat(3,3)
        integer :: ispace, k
        mat = e%get_mat()
        do ispace=1,self%nspace
            do k=self%kfromto_vpft(1),self%kfromto_vpft(2)
                loc  = matmul(self%locs_ref(k,ispace,:),mat)
                self%vpft_target(k,ispace) =&
                    &self%vol_target%interp_fcomp(loc) * self%vol_target%oshift(loc, shvec)
            end do
        end do
        self%sqsum_target = sum(csq(self%vpft_target))
    end subroutine extract_target_2

    !>  \brief  extracts the lines required for matchiing
    !!          from the reference
    subroutine extract_target_3( self, rmat )
        class(volpft_corrcalc), intent(inout) :: self
        real,                   intent(in)    :: rmat(3,3)
        real    :: loc(3)
        integer :: ispace, k
        do ispace=1,self%nspace
            do k=self%kfromto_vpft(1),self%kfromto_vpft(2)
                loc  = matmul(self%locs_ref(k,ispace,:),rmat)
                self%vpft_target(k,ispace) = self%vol_target%interp_fcomp(loc)
            end do
        end do
        self%sqsum_target = sum(csq(self%vpft_target))
    end subroutine extract_target_3

    !>  \brief  continous rotational correlator
    function corr_1( self, e ) result( cc )
        class(volpft_corrcalc), intent(inout) :: self
        class(ori),             intent(in)    :: e
        real :: cc
        call self%extract_target_1(e)
        cc = sum(real(self%vpft_ref*conjg(self%vpft_target)))
        cc = cc/sqrt(self%sqsum_target*self%sqsum_ref)
    end function corr_1

    !>  \brief  continous rotational correlator
    function corr_2( self, euls ) result( cc )
        class(volpft_corrcalc), intent(inout) :: self
        real,                   intent(in)    :: euls(3)
        real      :: cc
        type(ori) :: e
        call e%new
        call e%set_euler(euls)
        cc = self%corr_1(e)
    end function corr_2

    !>  \brief  continous rotational correlator
    function corr_3( self, e, shvec ) result( cc )
        class(volpft_corrcalc), intent(inout) :: self
        class(ori),             intent(in)    :: e
        real,                   intent(in)    :: shvec(3)
        real :: cc
        call self%extract_target_2(e, shvec)
        cc = sum(real(self%vpft_ref*conjg(self%vpft_target)))
        cc = cc/sqrt(self%sqsum_target*self%sqsum_ref)
    end function corr_3

    !>  \brief  continous rotational correlator
    function corr_4( self, euls, shvec ) result( cc )
        class(volpft_corrcalc), intent(inout) :: self
        real,                   intent(in)    :: euls(3)
        real,                   intent(in)    :: shvec(3)
        real      :: cc
        type(ori) :: e
        call e%new
        call e%set_euler(euls)
        cc = self%corr_3(e, shvec)
    end function corr_4

    !>  \brief  continous rotational correlator
    function corr_5( self ) result( cc )
        class(volpft_corrcalc), intent(inout) :: self
        real :: cc
        cc = sum(real(self%vpft_ref*conjg(self%vpft_target)))
        cc = cc/sqrt(self%sqsum_target*self%sqsum_ref)
    end function corr_5

    !>  \brief  is a destructor
    subroutine kill( self )
        class(volpft_corrcalc), intent(inout) :: self
        if( self%existence_vpft )then
            self%vol_ref    => null()
            self%vol_target => null()
            call self%ico%kill
            deallocate(self%vpft_ref,self%vpft_target,self%locs_ref)
            self%existence_vpft = .false.
        endif
    end subroutine kill

end module simple_volpft_corrcalc

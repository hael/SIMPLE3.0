module simple_ft_expanded
!$ use omp_lib
!$ use omp_lib_kinds
use simple_defs
use simple_image,  only: image
use simple_jiffys, only: alloc_err
implicit none

public :: ft_expanded
private

type :: ft_expanded
    private
    integer              :: lims(3,2)          !< physical limits for the Fourier transform
    integer              :: flims(3,2)         !< shifted limits (2 make transfer 2 GPU painless)
    integer              :: ldim(3)=[1,1,1]    !< logical dimension of originating image
    real                 :: shconst(3)         !< shift constant
    real                 :: hp                 !< high-pass limit
    real                 :: lp                 !< low-pass limit
    real                 :: smpd=0.            !< sampling distance of originating image
    real, allocatable    :: transfmat(:,:,:,:) !< shift transfer matrix
    complex, allocatable :: cmat(:,:,:)        !< Fourier components
    logical              :: existence=.false.  !< existence
  contains
    ! constructors
    procedure          :: new_1
    procedure          :: new_2
    procedure          :: new_3
    generic            :: new => new_1, new_2, new_3
    procedure          :: copy
    ! checkers
    procedure          :: exists
    procedure, private :: same_dims
    generic            :: operator(.eqdims.) => same_dims
    ! getters
    procedure          :: get_ldim
    procedure          :: get_flims
    procedure          :: get_lims
    ! arithmetics
    procedure, private :: assign
    generic            :: assignment(=) => assign
    procedure          :: add
    procedure          :: subtr
    ! modifiers
    procedure          :: shift
    ! calculators
    procedure          :: corr
    procedure          :: corr_shifted
    ! destructor
    procedure          :: kill
end type ft_expanded

contains

    ! CONSTRUCTORS

    !>  \brief  is a constructor
    subroutine new_1( self, img, hp, lp )
        use simple_math, only: is_even
        class(ft_expanded), intent(inout) :: self
        class(image),       intent(inout) :: img
        real,               intent(in)    :: hp, lp
        integer :: alloc_stat,h,k,l,i,hcnt,kcnt,lcnt
        integer :: lplim,hplim,hh,kk,ll,sqarg,phys(3)
        logical :: didft
        ! kill pre-existing object
        call self%kill
        ! set constants
        self%ldim = img%get_ldim()
        if( self%ldim(3) > 1 ) stop 'only 4 2D images; simple_ft_expanded::new_1'
        self%smpd = img%get_smpd()
        self%hp   = hp
        self%lp   = lp
        self%lims = img%loop_lims(1,lp)
        ! shift the limits 2 make transfer 2 GPU painless
        self%flims = 1
        do i=1,3
            self%flims(i,2) = self%lims(i,2)-self%lims(i,1)+1
        end do
        ! set the squared filter limits
        hplim = img%get_find(hp)
        hplim = hplim*hplim
        lplim = img%get_find(lp)
        lplim = lplim*lplim
        ! set shift constant (shconst)
        do i=1,3
            if( self%ldim(i) == 1 )then
                self%shconst(i) = 0.
                cycle
            endif
            if( is_even(self%ldim(i)) )then
                self%shconst(i) = PI/real(self%ldim(i)/2.)
            else
                self%shconst(i) = PI/real((self%ldim(i)-1)/2.)
            endif
        end do
        ! prepare image
        didft = .false.
        if( .not. img%is_ft() )then
            call img%fwd_ft
            didft = .true.
        endif
        ! allocate instance variables
        allocate(    self%cmat(  self%flims(1,1):self%flims(1,2),&
                                 self%flims(2,1):self%flims(2,2),&
                                 self%flims(3,1):self%flims(3,2)),&
                  self%transfmat(self%flims(1,1):self%flims(1,2),&
                                 self%flims(2,1):self%flims(2,2),&
                                 self%flims(3,1):self%flims(3,2), 3), stat=alloc_stat)
        call alloc_err("In: new_1; simple_ft_expanded, 2", alloc_stat)
        self%cmat      = cmplx(0.,0.)
        self%transfmat = 0.
        hcnt = 0
        do h=self%lims(1,1),self%lims(1,2)
            hh   = h * h
            hcnt = hcnt + 1
            kcnt = 0
            do k=self%lims(2,1),self%lims(2,2)
                kk   = k * k
                kcnt = kcnt + 1
                lcnt = 0
                do l=self%lims(3,1),self%lims(3,2)
                    ll = l * l
                    lcnt = lcnt+1
                    sqarg = hh + kk + ll
                    if( sqarg <= lplim .and. sqarg >= hplim  )then
                        phys = img%comp_addr_phys([h,k,l])
                        self%transfmat(hcnt,kcnt,lcnt,:) = real([h,k,l])*self%shconst
                        self%cmat(hcnt,kcnt,lcnt) = img%get_fcomp([h,k,l],phys)
                     endif
                end do
            end do
        end do
        if( didft ) call img%bwd_ft
        self%existence = .true.
    end subroutine new_1
    
    !>  \brief  is a constructor
    subroutine new_2( self, ldim, smpd, hp, lp )
        use simple_jiffys, only: alloc_err
        class(ft_expanded), intent(inout) :: self
        integer,            intent(in)    :: ldim(3)
        real,               intent(in)    :: smpd
        real,               intent(in)    :: hp
        real,               intent(in)    :: lp
        type(image) :: img
        call img%new(ldim,smpd)
        img = cmplx(0.,0.)
        call self%new_1(img, hp, lp)
        call img%kill
    end subroutine new_2

    !>  \brief  is a constructor 
    subroutine new_3( self, self_in )
        class(ft_expanded), intent(inout) :: self
        class(ft_expanded), intent(in)    :: self_in
        if( self_in%existence )then
            call self%new_2(self_in%ldim, self_in%smpd, self_in%hp, self_in%lp)
            self%cmat = cmplx(0.,0.)
        else
            stop 'self_in does not exists; simple_ft_expanded::new_3'
        endif
    end subroutine new_3
    
    !>  \brief  is a constructor that copies the input object
    subroutine copy( self, self_in )
        class(ft_expanded), intent(inout) :: self
        class(ft_expanded), intent(in)    :: self_in
        if( self_in%existence )then
            call self%new_2(self_in%ldim, self_in%smpd, self_in%hp, self_in%lp)
            self%cmat = self_in%cmat
        else
            stop 'self_in does not exists; simple_ft_expanded::copy'
        endif
    end subroutine copy
    
    ! CHECKERS
    
    !>  \brief  checks if an instance exists
    pure function exists( self ) result( yep )
        class(ft_expanded), intent(in) :: self
        logical :: yep
        yep = self%existence
    end function exists
    
    !>  \brief  checks for same dimensions, overloaded as (.eqdims.)
    pure function same_dims( self1, self2 ) result( yep )
        class(ft_expanded), intent(in) :: self1, self2
        logical :: yep
        yep = all(self1%lims == self2%lims)
    end function same_dims

    ! GETTERS

    !>  \brief  is a getter
    pure function get_ldim( self ) result( ldim )
        class(ft_expanded), intent(in) :: self
        integer :: ldim(3)
        ldim = self%ldim
    end function get_ldim

    !>  \brief  is a getter
    pure function get_flims( self ) result( flims)
        class(ft_expanded), intent(in) :: self
        integer :: flims(3,2)
        flims = self%flims
    end function get_flims

    !>  \brief  is a getter
    pure function get_lims( self ) result( lims)
        class(ft_expanded), intent(in) :: self
        integer :: lims(3,2)
        lims = self%lims
    end function get_lims
    
    ! ARITHMETICS

    !>  \brief  polymorphic assignment (=)
    subroutine assign( selfout, selfin )
        class(ft_expanded), intent(inout) :: selfout
        class(ft_expanded), intent(in)    :: selfin
        call selfout%copy(selfin)
    end subroutine assign
    
    !>  \brief  is for ft_expanded summation
    subroutine add( self, self2add, w )
        class(ft_expanded), intent(inout) :: self
        class(ft_expanded), intent(in)    :: self2add
        real, optional,     intent(in)    :: w
        real :: ww
        ww =1.0
        if( present(w) ) ww = w
        if( self%existence )then
            if( self.eqdims.self2add )then
                !$omp parallel workshare proc_bind(close)
                self%cmat = self%cmat + self2add%cmat*ww
                !$omp end parallel workshare
            else
                stop 'cannot sum ft_expanded objects of different dims; add; simple_ft_expanded'
            endif
        else
            call self%copy(self2add)
            self%cmat = self%cmat*ww
        endif
    end subroutine add

    !>  \brief is for image subtraction,  not overloaded
    subroutine subtr( self, self2subtr, w )
        class(ft_expanded), intent(inout) :: self
        class(ft_expanded), intent(in)    :: self2subtr
        real, optional,     intent(in)    :: w
        real :: ww
        ww = 1.0
        if( present(w) ) ww = w
        if( self%existence )then
            if( self.eqdims.self2subtr )then
                !$omp parallel workshare proc_bind(close)
                self%cmat = self%cmat-ww*self2subtr%cmat
                !$omp end parallel workshare
            else
                stop 'cannot subtract ft_expanded objects of different dims; subtr; simple_ft_expanded'
            endif
        else
            stop 'the object to subtract from does not exist; subtr; simple_ft_expanded'
        endif
    end subroutine subtr
    
    ! MODIFIERS
    
    !>  \brief  is 4 shifting an ft_expanded instance
    subroutine shift( self, shvec, self_out )
        class(ft_expanded), intent(in)    :: self
        real,               intent(in)    :: shvec(3)
        class(ft_expanded), intent(inout) :: self_out
        integer :: hind,kind,lind
        real    :: shvec_here(3), arg
        if( self%existence )then
            if( self_out%existence )then
                if( self.eqdims.self_out )then
                    shvec_here = shvec
                    if( self%ldim(3) == 1 ) shvec_here(3) = 0.
                    !$omp parallel do collapse(3) schedule(static) default(shared) &
                    !$omp private(hind,kind,lind,arg) proc_bind(close)
                    do hind=self%flims(1,1),self%flims(1,2)
                        do kind=self%flims(2,1),self%flims(2,2)
                            do lind=self%flims(3,1),self%flims(3,2)
                                arg                           = sum(shvec_here*self%transfmat(hind,kind,lind,:))
                                self_out%cmat(hind,kind,lind) = self%cmat(hind,kind,lind)*cmplx(cos(arg),sin(arg))
                            end do
                        end do
                    end do
                    !$omp end parallel do
                else
                    write(*,*) 'self     lims: ', self%lims
                    write(*,*) 'self_out lims: ', self_out%lims
                    stop 'input/output objects have nonconforming dims; simple_ft_expanded::shift'
                endif
            else
                stop 'output object does not exist; simple_ft_expanded::shift'
            endif
        else
            stop 'cannot shift non-existent object; simple_ft_expanded::shift'
        endif
    end subroutine shift
    
    ! CALCULATORS

    !>  \brief  is a correlation calculator
    function corr( self1, self2 ) result( r )
        use simple_math, only: csq, calc_corr
        class(ft_expanded), intent(in) :: self1, self2
        real :: r,sumasq,sumbsq
        ! corr is real part of the complex mult btw 1 and 2*
        r = sum(real(self1%cmat*conjg(self2%cmat)))
        ! normalisation terms
        sumasq = sum(csq(self1%cmat))
        sumbsq = sum(csq(self2%cmat))
        ! finalise the correlation coefficient
        r = calc_corr(r,sumasq*sumbsq)
    end function corr

    !>  \brief  is a correlation calculator with origin shift of self2
    function corr_shifted( self1, self2, shvec ) result( r )
        use simple_math, only: csq, calc_corr
        class(ft_expanded), intent(in) :: self1, self2 !< instances
        real,               intent(in) :: shvec(3)
        complex, allocatable :: shmat(:,:,:), cmat2sh(:,:,:)
        real     :: r,sumasq,sumbsq,arg,shvec_here(3)
        integer  :: alloc_stat,hind,kind,lind
        if( self1.eqdims.self2 )then
            allocate(   shmat( self1%flims(1,1):self1%flims(1,2),   &
                               self1%flims(2,1):self1%flims(2,2),   &
                               self1%flims(3,1):self1%flims(3,2)  ),&
                      cmat2sh( self1%flims(1,1):self1%flims(1,2),   &
                               self1%flims(2,1):self1%flims(2,2),   &
                               self1%flims(3,1):self1%flims(3,2)),  &
                               stat=alloc_stat                      )
            call alloc_err("In: corr_shifted; simple_ft_expanded", alloc_stat)
            shvec_here = shvec
            if( self1%ldim(3) == 1 ) shvec_here(3) = 0.
            !$omp parallel do collapse(3) schedule(static) default(shared) &
            !$omp private(hind,kind,lind,arg) proc_bind(close)
            do hind=self1%flims(1,1),self1%flims(1,2)
                do kind=self1%flims(2,1),self1%flims(2,2)
                    do lind=self1%flims(3,1),self1%flims(3,2)
                        arg = sum(shvec_here(:)*self1%transfmat(hind,kind,lind,:))
                        shmat(hind,kind,lind) = cmplx(cos(arg),sin(arg))
                    end do
                end do
            end do
            !$omp end parallel do
            ! shift self2
            cmat2sh = self2%cmat*shmat
            ! corr is real part of the complex mult btw 1 and 2*
            r = sum(real(self1%cmat*conjg(cmat2sh)))
            ! normalisation terms
            sumasq = sum(csq(self1%cmat))
            sumbsq = sum(csq(cmat2sh))
            ! finalise the correlation coefficient
            r = calc_corr(r,sumasq*sumbsq)
            deallocate(shmat,cmat2sh)
        else
            write(*,*) 'self1 flims: ', self1%flims(1,1), self1%flims(1,2), self1%flims(2,1),&
            self1%flims(2,2), self1%flims(3,1), self1%flims(3,2)
            write(*,*) 'self2 flims: ', self2%flims(1,1), self2%flims(1,2), self2%flims(2,1),&
            self2%flims(2,2), self2%flims(3,1), self2%flims(3,2)
            stop 'cannot correlate expanded_ft:s with different dims; ft_expanded::corr_shifted'
        endif ! end of if( self1.eqdims.self2 ) statement
    end function corr_shifted
    
    ! DESTRUCTOR

    !>  \brief  is a destructor
    subroutine kill( self )
        class(ft_expanded), intent(inout) :: self
        if( self%existence )then
            deallocate(self%cmat, self%transfmat)
            self%existence = .false.
        endif
    end subroutine kill

end module simple_ft_expanded

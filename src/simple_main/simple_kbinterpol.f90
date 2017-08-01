!------------------------------------------------------------------------------!
! SIMPLE v3.0         Elmlund & Elmlund Lab          simplecryoem.com          !
!------------------------------------------------------------------------------!
!> Simple Kaiser-Bessel interpolation module
module simple_kbinterpol
use simple_defs
implicit none

public :: kbinterpol
private

type :: kbinterpol
    private
    double precision :: ps(7) = 0.d0
    double precision :: qs(9) = 0.d0
    double precision :: thresh = 0d0
    real :: alpha, beta, betasq, oneoW, piW, twooW, W, Whalf
  contains
    procedure          :: new
    procedure          :: get_winsz
    procedure          :: get_alpha
    procedure          :: apod
    procedure          :: instr
    procedure, private :: bessi0
end type kbinterpol

interface kbinterpol
    module procedure constructor
end interface

contains

    function constructor( Whalf_in, alpha_in ) result( self )
        real, intent(in) :: Whalf_in, alpha_in
        type(kbinterpol) :: self
        call self%new(Whalf_in, alpha_in)
    end function constructor

    subroutine new( self, Whalf_in, alpha_in )
        class(kbinterpol), intent(inout) :: self
        real,              intent(in)    :: Whalf_in, alpha_in
        self%ps = [1.0d0,3.5156229d0,3.0899424d0,1.2067492d0,0.2659732d0,0.360768d-1,0.45813d-2]
        self%qs = [0.39894228d0,0.1328592d-1,0.225319d-2,-0.157565d-2,0.916281d-2,&
                                      &-0.2057706d-1,0.2635537d-1,-0.1647633d-1,0.392377d-2]
        self%thresh = 3.75d0
        self%Whalf  = Whalf_in
        self%alpha  = alpha_in
        self%W      = 2.0 * self%Whalf
        self%piW    = pi * self%W
        if( self%Whalf <= 1.5 )then
            self%beta = 7.4
        else
            self%beta = pi * sqrt((self%W**2.0 / self%alpha**2.0) * (self%alpha - 0.5)**2.0 - 0.8)
        endif
        self%betasq = self%beta * self%beta
        self%twooW  = 2.0 / self%W
        self%oneoW  = 1.0 / self%W 
    end subroutine new

    real function get_winsz( self )
        class(kbinterpol), intent(in) :: self
        get_winsz = self%Whalf
    end function get_winsz

    real function get_alpha( self )
        class(kbinterpol), intent(in) :: self
        get_alpha = self%alpha
    end function get_alpha

    !>  \brief  is the Kaiser-Bessel apodization function, abs(x) <= Whalf
    function apod( self, x ) result( r )
        class(kbinterpol), intent(in) :: self
        real,              intent(in) :: x
        real :: r, arg
        if( abs(x) > self%Whalf )then
            r = 0.
            return
        endif
        arg = self%twooW * x
        arg = 1. - arg * arg
        r   = self%oneoW * self%bessi0(self%beta * sqrt(arg))
    end function apod

    !>  \brief  is the Kaiser-Bessel instrument function
    function instr( self, x ) result( r )
        class(kbinterpol), intent(in) :: self
        real,              intent(in) :: x
        real :: r, arg1, arg2
        arg1 = self%piW * x
        arg1 = self%betasq - arg1 * arg1
        if( arg1 > 0. )then
            arg2 = sqrt(arg1)
            if( abs(arg2) <= TINY ) then
                r = 1.0
            else
                r = sinh(arg2) / (arg2)
            endif
        else
            r = 1.0
        endif
    end function instr

    !>  \brief returns the modified Bessel function I0(x) for any real x
    function bessi0( self, x ) result( bess )
        class(kbinterpol), intent(in) :: self
        real,              intent(in) :: x
        real :: bess
        double precision :: y, ax !< accumulate polynomials in double precision
        if( abs(x) .lt. self%thresh)then
            y = x/self%thresh
            y = y*y
            bess = real(self%ps(1)+y*(self%ps(3)+y*(self%ps(4)+y*(self%ps(5)+y*(self%ps(6)+y*self%ps(7))))))
        else
            ax = dble(abs(x))
            y = self%thresh/ax
            bess = real(exp(ax)/sqrt(ax))*(self%qs(1)+y*(self%qs(2)+y*(self%qs(3)+&
                &y*(self%qs(4)+y*(self%qs(5)+y*(self%qs(6)+y*(self%qs(7)+y*(self%qs(8)+y*self%qs(9)))))))))
        endif
    end function bessi0

end module simple_kbinterpol

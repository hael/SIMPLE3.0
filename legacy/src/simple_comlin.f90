! for calculation of common-line correlations
module simple_comlin
include 'simple_lib.f08'
use simple_image,  only: image
use simple_oris,   only: oris
implicit none

public :: comlin
private

type comlin
    private
    integer               :: nptcls=0        !< nr of ptcls
    integer               :: xdim=0          !< Fourier dim
    integer               :: lims(2)         !< Fourier index limits
    class(oris),  pointer :: a=>null()       !< orientations pointer
    class(image), pointer :: fpls(:)=>null() !< Fourier planes pointer
  contains
    procedure          :: new
    procedure          :: corr
    procedure          :: pcorr
    procedure, private :: extr_comlin
    procedure          :: kill
end type comlin

interface comlin
    module procedure constructor
end interface comlin

contains

    !>  \brief  is a constructor
    function constructor( a, fpls, lp ) result( self )
        class(oris),  target, intent(in) :: a       !< orientations
        class(image), target, intent(in) :: fpls(:) !< Fourier planes
        real,                 intent(in) :: lp      !< low-pass limit
        type(comlin) :: self                        !< object
        call self%new( a, fpls, lp )
    end function constructor

    !>  \brief  is a constructor
    subroutine new( self, a, fpls, lp )
        class(comlin),        intent(inout) :: self    !< object
        class(oris),  target, intent(in)    :: a       !< orientations
        class(image), target, intent(in)    :: fpls(:) !< Fourier planes
        real,                 intent(in)    :: lp      !< low-pass limit
        integer :: j, ld_here(3)
        call self%kill
        do j=1,self%nptcls
            if(.not. fpls(j)%square_dims()) stop 'square dims assumed; new; simple_comlin'
            if(.not. fpls(j)%even_dims()  ) stop 'even dims assumed; new; simple_comlin'
        end do
        self%nptcls = a%get_noris()
        self%a      => a
        self%fpls   => fpls
        ld_here     = self%fpls(1)%get_ldim()
        self%xdim   = ld_here(1)/2
        self%lims   = self%fpls(1)%get_clin_lims(lp) ! <-- as above
    end subroutine new

    !>  \brief  is for calculating the joint common line correlation
    function corr( self ) result( cc )
        !$ use omp_lib
        !$ use omp_lib_kinds
        class(comlin), intent(inout) :: self
        real    :: cc,corrs(self%nptcls),sums1(self%nptcls),sums2(self%nptcls),ccarr(self%nptcls)
        real    :: sum1, sum2, r
        integer :: i,j
        logical :: foundlines(self%nptcls)
        !$omp parallel do default(shared) private(i,j,corrs,sums1,sums2,foundlines,sum1,sum2,r)&
        !$omp schedule(static) proc_bind(close)
        do i=1,self%nptcls
            do j=1,self%nptcls
                call self%extr_comlin(i, j, corrs(j), sums1(j), sums2(j), foundlines(j))
            end do
            if(any(foundlines)) then
                sum1 = sum(sums1,mask=foundlines)
                sum2 = sum(sums2,mask=foundlines)
                r    = sum(corrs,mask=foundlines)
                if( sum1 > 0. .and. sum2 > 0. )then
                    ccarr(i) = r / sqrt(sum1 * sum2)
                else
                    ccarr(i) = 0.
                endif
            else
                ccarr(i) = -1.
            endif
        end do
        !$omp end parallel do
        cc = sum(ccarr)/real(self%nptcls)
    end function corr

    !>  \brief  is for interpolating the common line between a pair of images
    !!          and calculating the common line correlation
    function pcorr( self, iptcl, jptcl ) result( corr )
        class(comlin), intent(inout) :: self
        integer,       intent(in)    :: iptcl, jptcl
        real    :: corr, sums1, sums2
        logical :: foundline
        corr  = 0.
        sums1 = 0.
        sums2 = 0.
        call self%extr_comlin( iptcl, jptcl, corr, sums1, sums2, foundline )
        if( foundline )then
            if( sums1 > 0. .and. sums2 > 0. )then
                corr = corr / sqrt(sums1 * sums2)
            else
                corr = 0.
            endif
        else
            corr = -1.
        endif
    end function pcorr

    ! PRIVATE STUFF

    !>  \brief  calculates common line algebra, interpolates the
    !!          complex vectors, and calculates corr precursors
    !! \param pind,j  indecies to normals
    !! \param corr,sumasq,sumbsq output statistics
    subroutine extr_comlin( self, pind, j, corr, sumasq, sumbsq, foundline )
        class(comlin), intent(inout) :: self
        integer,       intent(in)    :: pind,j
        real,          intent(out)   :: corr,sumasq,sumbsq
        logical,       intent(inout) :: foundline          !< output success
        integer            :: k
        real               :: h1,k1,h2,k2,px,py,jx,jy,scalprod,abscom,line(2,2)
        real, dimension(3) :: comlin,tmp1,tmpb1,norm1,norm2
        complex            :: cline(self%lims(1):self%lims(2),2)
        ! init
        corr      = 0.
        sumasq    = 0.
        sumbsq    = 0.
        foundline = .false.
        if( pind == j )then
            ! no self common lines
            return
        endif
        norm1    = self%a%get_normal(pind)
        norm2    = self%a%get_normal(j)
        scalprod = dot_product(norm1, norm2)
        if( scalprod > 0.99 ) then
            ! identical planes have no common line
            return
        endif
        ! find intersection in 3D
        comlin(1) = norm1(2)*norm2(3)-norm1(3)*norm2(2)
        comlin(2) = norm1(3)*norm2(1)-norm1(1)*norm2(3)
        comlin(3) = norm1(1)*norm2(2)-norm1(2)*norm2(1)
        abscom    = sqrt(dot_product(comlin, comlin))
        if( abscom >= 0.0001 ) then
            ! normalize
            comlin(:) = comlin(:)/abscom
        else
            ! identical planes have no common line
            return
        endif
        ! comlin is the intersection in 3D, map to the
        ! respective coordinate systems
        ! first map onto the target
        tmp1 = matmul( self%a%get_mat(pind), comlin )
        call projz( tmp1, line(:,1) )
        ! then map onto the reference:
        tmpb1 = matmul( self%a%get_mat(j), comlin )
        call projz( tmpb1, line(:,2) )
        px = self%a%get(pind, 'x')
        py = self%a%get(pind, 'y')
        jx = self%a%get(j, 'x')
        jy = self%a%get(j, 'y')
        do k=self%lims(1),self%lims(2)
            h1 = real(k)*line(1,1)
            k1 = real(k)*line(2,1)
            h2 = real(k)*line(1,2)
            k2 = real(k)*line(2,2)
            cline(k,1) = self%fpls(pind)%extr_fcomp(h1,k1,px,py)
            cline(k,2) = self%fpls(j   )%extr_fcomp(h2,k2,jx,jy)
            corr = corr + dot_product([real(cline(k,1)), aimag(cline(k,1))],&
                &[real(cline(k,2)), aimag(cline(k,2))])
            sumasq = sumasq+csq(cline(k,1))
            sumbsq = sumbsq+csq(cline(k,2))
        end do
        foundline = .true.
    end subroutine extr_comlin

    ! DESTRUCTOR

    !>  \brief  is a destructor
    subroutine kill( self )
        class(comlin), intent(inout) :: self
        self%a    => null()
        self%fpls => null()
    end subroutine kill

end module simple_comlin
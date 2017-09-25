! 3D reconstruction from projections using convolution interpolation (gridding)

module simple_reconstructor
!$ use omp_lib
!$ use omp_lib_kinds
use, intrinsic :: iso_c_binding
#include "simple_lib.f08"

!!import functions
use simple_fftw3,      only: fftwf_alloc_real, fftwf_free
use simple_imghead,    only: find_ldim_nptcls
use simple_timer,      only: tic, toc, timer_int_kind
!! import classes
use simple_ctf,        only: ctf
use simple_ori,        only: ori
use simple_oris,       only: oris
use simple_params,     only: params
use simple_sym,        only: sym
use simple_kbinterpol, only: kbinterpol
use simple_image,      only: image
implicit none

public :: reconstructor
private
 !! CTF flag type
    enum, bind(c) 
        enumerator :: CTFFLAG_NO = 0, CTFFLAG_YES = 1, CTFFLAG_MUL = 2,  CTFFLAG_FLIP=3
    end enum

    type :: CTFFLAGTYPE
        private
        integer(kind(CTFFLAG_NO)) :: flag=CTFFLAG_NO
    end type CTFFLAGTYPE

type, extends(image) :: reconstructor
    private
    type(kbinterpol)            :: kbwin                        !< window function object
    type(c_ptr)                 :: kp                           !< c pointer for fftw allocation
    type(ctf)                   :: tfun                         !< CTF object
    real(kind=c_float), pointer :: rho(:,:,:)=>null()           !< sampling+CTF**2 density
    complex, allocatable        :: cmat_exp(:,:,:)              !< Fourier components of expanded reconstructor
    real,    allocatable        :: rho_exp(:,:,:)               !< sampling+CTF**2 density of expanded reconstructor
    real,    allocatable        :: w(:,:,:)
    real                        :: winsz         = 1.           !< window half-width
    real                        :: alpha         = 2.           !< oversampling ratio
    real                        :: dens_const    = 1.           !< density estimation constant, old val: 1/nptcls
    integer                     :: lfny          = 0            !< Nyqvist Fourier index
    integer                     :: ldim_img(3)   = 0            !< logical dimension of the original image
    !character(len=STDLEN)       :: ctfflag       = ''           !< ctf flag <yes|no|mul|flip>
 !   integer(sp)                 :: wdim                         !< logical dimension of window
!    integer(sp)                 :: dimplus                      !< logical dimension of image plus half window
    integer, allocatable        :: physmat(:,:,:,:)
    type(CTFFLAGTYPE)           :: ctf                          !< ctf flag <yes|no|mul|flip>
    logical                     :: tfneg              = .false. !< invert contrast or not
    logical                     :: tfastig            = .false. !< astigmatic CTF or not
    logical                     :: rho_allocated      = .false. !< existence of rho matrix
    logical                     :: rho_exp_allocated  = .false. !< existence of rho expanded matrix
    logical                     :: cmat_exp_allocated = .false. !< existence of Fourier components expanded matrix
  contains
    ! CONSTRUCTORS 
    procedure          :: alloc_rho
    ! SETTERS
    procedure          :: reset
    ! GETTER
    procedure          :: get_kbwin
    ! I/O
    procedure          :: write_rho
    procedure          :: read_rho
    ! INTERPOLATION
    procedure, private :: inout_fcomp
    procedure, private :: calc_tfun_vals
    procedure          :: inout_fplane
    procedure          :: sampl_dens_correct
    procedure          :: sampl_dens_correct_old
    procedure          :: compress_exp
    ! SUMMATION
    procedure          :: sum
    ! RECONSTRUCTION
    procedure          :: rec
    ! DESTRUCTORS
    procedure          :: dealloc_exp
    procedure          :: dealloc_rho
end type reconstructor

real            :: dfx=0., dfy=0., angast=0.
real, parameter :: SHTHRESH=0.0001
#include "simple_local_flags.inc"
contains

    ! CONSTRUCTOR

    subroutine alloc_rho( self, p, expand )
        class(reconstructor), intent(inout) :: self  !< this instance
        class(params),        intent(in)    :: p     !< parameters object
        logical, optional,    intent(in)    :: expand !< expand flag
        character(len=:), allocatable :: ikind_tmp
        integer :: rho_shape(3), rho_lims(3,2), lims(3,2), rho_exp_lims(3,2), ldim_exp(3,2)
        integer ::  dim, maxlims,h,k,m,logi(3),phys(3)
        logical :: l_expand
        l_expand = .true.
        if(.not. self%exists() ) stop 'construct image before allocating rho; alloc_rho; simple_reconstructor'
        if(      self%is_2d()  ) stop 'only for volumes; alloc_rho; simple_reconstructor'
        if( present(expand) )l_expand = expand
        self%ldim_img = self%get_ldim()
        if( self%ldim_img(3) < 2 ) stop 'reconstructor need to be 3D 4 now; alloc_rho; simple_reconstructor'
        call self%dealloc_rho
        self%dens_const = 1./real(p%nptcls)
        self%winsz      = p%winsz
        self%alpha      = p%alpha
        select case(p%ctf)
        case('no')
            self%ctf%flag    =CTFFLAG_NO
        case('yes')
            self%ctf%flag    =CTFFLAG_YES
        case('mul')
            self%ctf%flag    =CTFFLAG_MUL
        case('flip')
            self%ctf%flag    =CTFFLAG_FLIP
        end select
        self%tfneg      = .false.
        if( p%neg .eq. 'yes' ) self%tfneg = .true.
        self%tfastig = .false.
        if( p%tfplan%mode .eq. 'astig' ) self%tfastig = .true.
        self%kbwin = kbinterpol(self%winsz,self%alpha)
        ! Work out dimensions of the rho array
        rho_shape(1)   = fdim(self%ldim_img(1))
        rho_shape(2:3) = self%ldim_img(2:3)
        ! Letting FFTW do the allocation in C ensures that we will be using aligned memory
        self%kp = fftwf_alloc_real(int(product(rho_shape),c_size_t))
        ! Set up the rho array which will point at the allocated memory
        call c_f_pointer(self%kp,self%rho,rho_shape)
        self%rho_allocated = .true.
        if( l_expand )then
            ! setup expanded matrices
            lims    = self%loop_lims(2)
            maxlims = maxval(abs(lims))
            dim     = ceiling(sqrt(2.)*maxlims + self%winsz)
            ldim_exp(1,:) = [-dim, dim]
            ldim_exp(2,:) = [-dim, dim]
            ldim_exp(3,:) = [-dim, dim]
            rho_exp_lims  = ldim_exp
            allocate(self%cmat_exp( ldim_exp(1,1):ldim_exp(1,2),&
                &ldim_exp(2,1):ldim_exp(2,2),&
                &ldim_exp(3,1):ldim_exp(3,2)), stat=alloc_stat)
            if(alloc_stat /= 0) allocchk("In: alloc_rho; simple_reconstructor cmat_exp")
  
            allocate(self%rho_exp( rho_exp_lims(1,1):rho_exp_lims(1,2),&
                &rho_exp_lims(2,1):rho_exp_lims(2,2),&
                &rho_exp_lims(3,1):rho_exp_lims(3,2)), stat=alloc_stat)
            if(alloc_stat /= 0) allocchk("In: alloc_rho; simple_reconstructor rho_exp")
            self%cmat_exp           = cmplx(0.,0.)
            self%rho_exp            = 0.
            self%cmat_exp_allocated = .true.
            self%rho_exp_allocated  = .true.
        end if
        ! allocate(self%physmat( ldim_exp(1,1):ldim_exp(1,2),&
        !     &ldim_exp(2,1):ldim_exp(2,2),&
        !     &ldim_exp(3,1):ldim_exp(3,2),3), stat=alloc_stat)
        ! if(alloc_stat /= 0) allocchk("In: alloc_rho; simple_reconstructor physmat")
        !     ! ! parallel do collapse(3) default(shared) schedule(static)&
        !     ! ! private(h,k,m,logi,phys) proc_bind(close)
        !     do h = -dim, dim
        !         do k = -dim, dim
        !             do m = -dim, dim
        !                 logi  = [h, k, m]
        !                 phys = self%comp_addr_phys(logi)
        !                 self%physmat(h+dim+1,k+dim+1,m+dim+1,1:3) = phys(1:3)
        !             end do
        !         end do
        !     end do
        !     ! ! end parallel do
       
        call self%reset
    end subroutine alloc_rho

    ! SETTERS

    ! resets the reconstructor object before reconstruction
    subroutine reset( self )
        class(reconstructor), intent(inout) :: self !< this instance
        self     = cmplx(0.,0.)
        self%rho = 0.
    end subroutine reset

    ! GETTERS
    !> get the kbintpol window
    function get_kbwin( self ) result( wf )
        class(reconstructor), intent(inout) :: self !< this instance
        type(kbinterpol) :: wf   !< return kbintpol window
        wf = kbinterpol(self%winsz,self%alpha)
    end function get_kbwin

    ! I/O
    !>Write reconstructed image
    subroutine write_rho( self, kernam )
        class(reconstructor), intent(in) :: self   !< this instance
        character(len=*),     intent(in) :: kernam !< kernel name
        integer :: filnum, ierr
        call del_file(trim(kernam))
        call fopen(filnum, trim(kernam), status='NEW', action='WRITE', access='STREAM', iostat=ierr)
        call fileio_errmsg( 'simple_reconstructor ; write rho '//trim(kernam), ierr)
        write(filnum, pos=1, iostat=ierr) self%rho
        if( ierr .ne. 0 ) &
            call fileio_errmsg('read_rho; simple_reconstructor writing '//trim(kernam), ierr)
        call fclose(filnum,errmsg='simple_reconstructor ; write rho  fclose ')
    end subroutine write_rho

    !> Read sampling density matrix
    subroutine read_rho( self, kernam )
        class(reconstructor), intent(inout) :: self !< this instance
        character(len=*),     intent(in)    :: kernam !< kernel name
        integer :: filnum, ierr
        call fopen(filnum, file=trim(kernam), status='OLD', action='READ', access='STREAM', iostat=ierr)
        call fileio_errmsg('read_rho; simple_reconstructor opening '//trim(kernam), ierr)
        read(filnum, pos=1, iostat=ierr) self%rho
        if( ierr .ne. 0 ) &
            call fileio_errmsg('simple_reconstructor::read_rho; simple_reconstructor reading '&
            &// trim(kernam), ierr)
        call fclose(filnum,errmsg='read_rho; simple_reconstructor closing '//trim(kernam))
    end subroutine read_rho

    ! INTERPOLATION

    subroutine inout_fcomp( self, h, k, e, inoutmode, comp, oshift, pwght)
        class(reconstructor), intent(inout) :: self      !< this object
        integer,              intent(in)    :: h, k      !< Fourier indices
        class(ori),           intent(inout) :: e         !< orientation
        logical,              intent(in)    :: inoutmode !< add = .true., subtract = .false.
        complex,              intent(in)    :: comp      !< input component, if not given only sampling density calculation
        complex,              intent(in)    :: oshift    !< origin shift
        real, optional,       intent(in)    :: pwght     !< external particle weight (affects both fplane and rho)
        real, allocatable :: w(:,:,:)
        real              :: vec(3), loc(3), tval, tvalsq
        integer           :: i, win(3,2), wdim
        if(comp == cmplx(0.,0.)) return
        ! calculate non-uniform sampling location
        vec = [real(h), real(k), 0.]
        loc = matmul(vec, e%get_mat())
        ! evaluate the transfer function
        call self%calc_tfun_vals(vec, tval, tvalsq)
        ! initiate kernel matrix
        win  = sqwin_3d(loc(1), loc(2), loc(3), self%winsz)
        wdim = 2*ceiling(self%winsz) + 1
        allocate(w(wdim, wdim, wdim))
        ! (weighted) kernel values
        if(present(pwght))then
            w = self%dens_const*pwght
        else
            w = self%dens_const
        endif
        do i=1,wdim
            where(w(i,:,:)>0.)w(i,:,:) = w(i,:,:) * self%kbwin%apod(real(win(1,1)+i-1)-loc(1))
            where(w(:,i,:)>0.)w(:,i,:) = w(:,i,:) * self%kbwin%apod(real(win(2,1)+i-1)-loc(2))
            where(w(:,:,i)>0.)w(:,:,i) = w(:,:,i) * self%kbwin%apod(real(win(3,1)+i-1)-loc(3))
        enddo
        ! expanded matrices update
        if( inoutmode )then
            ! addition
            ! CTF and w modulates the component before origin shift
            self%cmat_exp(win(1,1):win(1,2), win(2,1):win(2,2), win(3,1):win(3,2)) =&
            &self%cmat_exp(win(1,1):win(1,2), win(2,1):win(2,2), win(3,1):win(3,2)) + (comp*tval*w)*oshift
            self%rho_exp(win(1,1):win(1,2), win(2,1):win(2,2), win(3,1):win(3,2)) =&
            &self%rho_exp(win(1,1):win(1,2), win(2,1):win(2,2), win(3,1):win(3,2)) + tvalsq*w
        else
            ! substraction
            ! CTF and w modulates the component before origin shift
            self%cmat_exp(win(1,1):win(1,2), win(2,1):win(2,2), win(3,1):win(3,2)) =&
            &self%cmat_exp(win(1,1):win(1,2), win(2,1):win(2,2), win(3,1):win(3,2)) - (comp*tval*w)*oshift
            self%rho_exp(win(1,1):win(1,2), win(2,1):win(2,2), win(3,1):win(3,2)) =&
            &self%rho_exp(win(1,1):win(1,2), win(2,1):win(2,2), win(3,1):win(3,2)) - tvalsq*w
        endif
        deallocate(w)
    end subroutine inout_fcomp

    subroutine calc_tfun_vals( self, vec, tval, tvalsq )
        class(reconstructor), intent(inout) :: self         !< instance
        real,                 intent(in)    :: vec(3)       !< nonuniform sampling location
        real,                 intent(out)   :: tval, tvalsq !< CTF and CTF**2.
        real    :: sqSpatFreq,ang,inv1,inv2
        integer :: ldim(3)
        if( self%ctf%flag /= CTFFLAG_NO )then
            ldim       = self%get_ldim()
            inv1       = vec(1)*(1./real(ldim(1)))
            inv2       = vec(2)*(1./real(ldim(2)))
            sqSpatFreq = inv1*inv1+inv2*inv2
            ang        = atan2(vec(2), vec(1))
            ! calculate CTF and CTF**2 values
            ! dfx, dfy, angast are class vars that are set by inout fplane
            tval   = self%tfun%eval(sqSpatFreq, dfx, dfy, angast, ang) ! no bfactor 4 now
            tvalsq = tval * tval
            if( self%ctf%flag == CTFFLAG_FLIP ) tval = abs(tval)
            if( self%ctf%flag == CTFFLAG_MUL  ) tval = 1.
            if( self%tfneg ) tval = -tval
        else
            tval   = 1.
            tvalsq = tval
            if( self%tfneg ) tval = -tval
        endif
    end subroutine calc_tfun_vals

    !> insert or uninsert Fourier plane
    subroutine inout_fplane( self, o, inoutmode, fpl, pwght, mul )
        class(reconstructor), intent(inout) :: self      !< instance
        class(ori),           intent(inout) :: o         !< orientation
        logical,              intent(in)    :: inoutmode !< add = .true., subtract = .false.
        class(image),         intent(inout) :: fpl       !< Fourier plane
        real,    optional,    intent(in)    :: pwght     !< external particle weight (affects both fplane and rho)
        real,    optional,    intent(in)    :: mul       !< shift weight multiplier
        integer :: h, k, lims(3,2), sh, lfny, logi(3), phys(3)
        complex :: oshift
        real    :: x, y, xtmp, ytmp, pw
        logical :: pwght_present
        if( .not. fpl%is_ft() )       stop 'image need to be FTed; inout_fplane; simple_reconstructor'
        if( .not. (self.eqsmpd.fpl) ) stop 'scaling not yet implemented; inout_fplane; simple_reconstructor'
        pwght_present = present(pwght)
        if( self%ctf%flag /= CTFFLAG_NO )then ! make CTF object & get CTF info
            self%tfun = ctf(self%get_smpd(), o%get('kv'), o%get('cs'), o%get('fraca'))
            dfx  = o%get('dfx')
            if( self%tfastig )then ! astigmatic CTF model
                dfy = o%get('dfy')
                angast = o%get('angast')
            else ! non-astigmatic CTF model
                dfy = dfx
                angast = 0.
            endif
        endif
        oshift = cmplx(1.,0.)
        lims   = self%loop_lims(2)
        x      = o%get('x')
        y      = o%get('y')
        xtmp   = 0.
        ytmp   = 0.
        if( abs(x) > SHTHRESH .or. abs(y) > SHTHRESH )then ! shift the image prior to insertion
            if( present(mul) )then
                x = x*mul
                y = y*mul
            endif
            xtmp = x
            ytmp = y
            if( abs(x) < 1e-6 ) xtmp = 0.
            if( abs(y) < 1e-6 ) ytmp = 0.
        endif
        !$omp parallel do collapse(2) default(shared) schedule(static)&
        !$omp private(h,k,oshift,logi,phys) proc_bind(close)
        do k=lims(1,1),lims(1,2)
            do h=lims(1,1),lims(1,2)
                logi   = [h,k,0]
                oshift = fpl%oshift(logi, [-xtmp,-ytmp,0.], ldim=2)
                phys   = fpl%comp_addr_phys(logi)
                call self%inout_fcomp(h,k,o,inoutmode,fpl%get_fcomp(logi,phys),oshift,pwght)
            end do
        end do
        !$omp end parallel do
    end subroutine inout_fplane

    !>  is for uneven distribution of orientations correction 
    !>  from Pipe & Menon 1999
    subroutine sampl_dens_correct( self, maxits )
        use simple_gridding,   only: mul_w_instr
        class(reconstructor), intent(inout) :: self
        integer,    optional, intent(in)    :: maxits
        type(kbinterpol)   :: kbwin 
        type(image)        :: W_img, Wprev_img
        complex            :: comp
        real               :: Wnorm, val_prev, val, Wnorm_prev, invrho
        integer            :: h, k, m, lims(3,2), logi(3), phys(3), iter
        integer            :: maxits_here
        complex, parameter :: zero = cmplx(0.,0.), one = cmplx(1.,0.)
        real,    parameter :: winsz  = 2.
        maxits_here = GRIDCORR_MAXITS
        if( present(maxits) )maxits_here = maxits
        lims = self%loop_lims(2)
        call W_img%new(self%ldim_img, self%get_smpd())
        call Wprev_img%new(self%ldim_img, self%get_smpd())
        call W_img%set_ft(.true.)
        call Wprev_img%set_ft(.true.)
        ! kernel
        kbwin = kbinterpol(winsz, self%alpha)
        ! weights init to 1.
        W_img = one
        Wnorm = SMALL
        do iter = 1, maxits_here
            Wnorm_prev = Wnorm
            Wprev_img  = W_img 
            ! W <- W * rho
            !$omp parallel do collapse(3) default(shared) schedule(static)&
            !$omp private(h,k,m,logi,phys) proc_bind(close)
            do h = lims(1,1),lims(1,2)
                do k = lims(2,1),lims(2,2)
                    do m = lims(3,1),lims(3,2)
                        logi  = [h, k, m]                      
                        phys  = W_img%comp_addr_phys(logi)
                        call W_img%mul(logi, self%rho(phys(1),phys(2),phys(3)), phys_in=phys)
                    end do
                end do
            end do
            !$omp end parallel do
            ! W <- (Wprev / rho) x kernel
            call W_img%bwd_ft
            call mul_w_instr(W_img, kbwin)
            call W_img%fwd_ft
            ! W <- Wprev / ((Wprev / rho) x kernel)
            Wnorm = 0.
            !$omp parallel do collapse(3) default(shared) schedule(static)&
            !$omp private(h,k,m,logi,phys,val,val_prev) proc_bind(close)&
            !$omp reduction(+:Wnorm)
            do h = lims(1,1),lims(1,2)
                do k = lims(2,1),lims(2,2)
                    do m = lims(3,1),lims(3,2)
                        logi     = [h, k, m]
                        phys     = W_img%comp_addr_phys(logi)
                        val      = mycabs(W_img%get_fcomp(logi, phys))
                        val_prev = real(Wprev_img%get_fcomp(logi, phys))
                        val      = min(val_prev/val, 1.e20)
                        call W_img%set_fcomp(logi, phys, cmplx(val, 0.)) 
                        Wnorm    = Wnorm + val ! values are positive, no need to square (numerical stability)
                    end do
                end do
            end do
            !$omp end parallel do
            Wnorm = log10(1. + Wnorm / sqrt(real(product(lims(:,2) - lims(:,1)))))
            if( Wnorm/Wnorm_prev < 1.05 ) exit
        enddo
        call Wprev_img%kill
        ! Fourier comps / rho
        !$omp parallel do collapse(3) default(shared) schedule(static)&
        !$omp private(h,k,m,logi,phys,invrho) proc_bind(close)
        do h = lims(1,1),lims(1,2)
            do k = lims(2,1),lims(2,2)
                do m = lims(3,1),lims(3,2)
                    logi   = [h, k, m]
                    phys   = W_img%comp_addr_phys(logi)
                    invrho = real(W_img%get_fcomp(logi, phys))
                    call self%mul(logi,invrho,phys_in=phys)
                end do
            end do
        end do
        !$omp end parallel do
        ! cleanup
        call W_img%kill
    end subroutine sampl_dens_correct

    ! OLD ROUTINE
    !> sampl_dens_correct Correct sample density
    !! \param self_out corrected image output
    !!
    subroutine sampl_dens_correct_old( self, self_out )
        class(reconstructor),   intent(inout) :: self !< this instance
        class(image), optional, intent(inout) :: self_out  !< output image instance
        integer :: h, k, l, lims(3,2), phys(3)
        logical :: self_out_present
        self_out_present = present(self_out)
        ! set constants
        lims = self%loop_lims(2)
        if( self_out_present ) call self_out%copy(self)
        !$omp parallel do collapse(3) default(shared) private(h,k,l,phys)&
        !$omp schedule(static) proc_bind(close)
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                do l=lims(3,1),lims(3,2)
                    phys = self%comp_addr_phys([h,k,l])
                    if( self_out_present )then
                        call self_out%div([h,k,l],self%rho(phys(1),phys(2),phys(3)),phys_in=phys)
                    else
                        call self%div([h,k,l],self%rho(phys(1),phys(2),phys(3)),phys_in=phys)
                    endif
                end do
            end do
        end do
        !$omp end parallel do
    end subroutine sampl_dens_correct_old

    subroutine compress_exp( self )
        class(reconstructor), intent(inout) :: self !< this instance
        complex :: comp, zero
        integer :: lims(3,2), logi(3), phys(3), h, k, m
        if(.not. self%cmat_exp_allocated .or. .not.self%rho_allocated)then
            stop 'expanded complex or rho matrices do not exist; simple_reconstructor::compress_exp'
        endif
        call self%reset
        lims = self%loop_lims(3)
        zero = cmplx(0.,0.)
        ! Fourier components & rho matrices compression
        ! Can't be threaded because of add_fcomp
        do h = lims(1,1),lims(1,2)
            do k = lims(2,1),lims(2,2)
                if(any(self%cmat_exp(h,k,:).ne.zero))then
                    do m = lims(3,1),lims(3,2)
                        comp = self%cmat_exp(h,k,m)
                        if(comp .eq. zero)cycle
                        logi = [h, k, m]
                        phys = self%comp_addr_phys(logi)
                        ! addition because FC and its Friedel mate must be summed
                        ! as the expansion updates one or the other
                        call self%add_fcomp(logi, phys, comp)
                        self%rho(phys(1),phys(2),phys(3)) = &
                            &self%rho(phys(1),phys(2),phys(3)) + self%rho_exp(h,k,m)
                    end do
                endif
            end do
        end do
    end subroutine compress_exp

    ! SUMMATION

    !> for summing reconstructors generated by parallel execution
    subroutine sum( self, self_in )
         class(reconstructor), intent(inout) :: self !< this instance
         class(reconstructor), intent(in)    :: self_in !< other instance
         call self%add(self_in)
         !$omp parallel workshare proc_bind(close)
         self%rho = self%rho+self_in%rho
         !$omp end parallel workshare
    end subroutine sum

    ! RECONSTRUCTION
    !> reconstruction routine
    subroutine rec( self, fname, p, o, se, state, mul, part )
        class(reconstructor), intent(inout) :: self      !< this object
        character(len=*),     intent(inout) :: fname     !< spider/MRC stack filename
        class(params),        intent(in)    :: p         !< parameters
        class(oris),          intent(inout) :: o         !< orientations
        class(sym),           intent(inout) :: se        !< symmetry element
        integer,              intent(in)    :: state     !< state to reconstruct
        real,    optional,    intent(in)    :: mul       !< shift multiplication factor
        integer, optional,    intent(in)    :: part      !< partition (4 parallel rec)
        type(image) :: img, img_pd
        real        :: skewness
        integer     :: statecnt(p%nstates), i, cnt, n, ldim(3)
        integer     :: state_here, state_glob
        integer(timer_int_kind) :: trec, tsamp
        verbose=.false.
        if(verbose) trec=tic()
        call find_ldim_nptcls(fname, ldim, n)
        if( n /= o%get_noris() ) stop 'inconsistent nr entries; rec; simple_reconstructor'
        ! stash global state index
        state_glob = state
        ! make random number generator
        ! make the images
        call img_pd%new([p%boxpd,p%boxpd,1],self%get_smpd())
        call img%new([p%box,p%box,1],self%get_smpd())
        ! population balancing logics
        if( p%balance > 0 )then
            call o%balance( p%balance, NSPACE_BALANCE, p%nsym, p%eullims, skewness )
            write(*,'(A,F8.2)') '>>> PROJECTION DISTRIBUTION SKEWNESS(%):', 100. * skewness
        else
            call o%set_all2single('state_balance', 1.0)
        endif
        ! zero the Fourier volume and rho
        call self%reset
        write(*,'(A)') '>>> KAISER-BESSEL INTERPOLATION'
        statecnt = 0
        cnt      = 0
        do i=1,p%nptcls
            call progress(i, p%nptcls)
            if( i <= p%top .and. i >= p%fromp )then
                cnt = cnt+1
                state_here = nint(o%get(i,'state'))
                if( state_here > 0 .and. (state_here == state) )then
                    statecnt(state) = statecnt(state)+1
                    call rec_dens
                endif
            endif
        end do
        if(verbose)write(*,'(A,1x,1ES20.5)') '>>> KAISER-BESSEL INTERPOLATION TIME ', toc(trec)
        if( present(part) )then
            return
        else
            if(verbose)tsamp=tic()
            write(*,'(A)') '>>> SAMPLING DENSITY (RHO) CORRECTION & WIENER NORMALIZATION'
            call self%compress_exp
            if(verbose)write(*,'(A,1x,1ES20.5)') '>>> RHO COMPRESSION EXPANDED ', toc()
            call self%sampl_dens_correct
           if(verbose) write(*,'(A,1x,1ES20.5)') '>>>  UNEVEN DISTRIBUTION OF ORIENTATIONS CORRECTION  ', toc()
        endif
        if(verbose)write(*,'(A,1x,1ES20.5)') '>>> SAMPLING DENSITY (RHO) CORRECTION & WIENER NORMALIZATION  TOTALTIME ', toc(tsamp)
        call self%bwd_ft
        call img%kill
        call img_pd%kill
        ! report how many particles were used to reconstruct each state
        if( p%nstates > 1 )then
            write(*,'(a,1x,i3,1x,a,1x,i6)') '>>> NR OF PARTICLES INCLUDED IN STATE:', state, 'WAS:', statecnt(state)
        endif
        if(verbose)write(*,'(A,1x,1ES20.5)') '>>> RECONSTRUCTIONN  TOTALTIME ', toc(trec)
        contains

            !> \brief  the density reconstruction functionality
            subroutine rec_dens
                use simple_gridding,  only: prep4cgrid
                type(ori) :: orientation, o_sym
                integer   :: j, state, state_balance
                real      :: pw
!                state         = nint(o%get(i, 'state'))
                state_balance = nint(o%get(i, 'state_balance'))
                if( state_balance == 0 ) return
                pw = 1.
                if( p%frac < 0.99 ) pw = o%get(i, 'w')
                if( pw > 0. )then
                    orientation = o%get_ori(i)
                    if( p%l_distr_exec )then
                        call img%read(p%stk_part, cnt)
                    else
                        call img%read(fname, i)
                    endif
                    call prep4cgrid(img, img_pd, p%msk, self%kbwin)
                    if( p%pgrp == 'c1' )then
                        call self%inout_fplane(orientation, .true., img_pd, pwght=pw, mul=mul)
                    else
                        do j=1,se%get_nsym()
                            o_sym = se%apply(orientation, j)
                            call self%inout_fplane(o_sym, .true., img_pd, pwght=pw, mul=mul)
                        end do
                    endif
                endif
            end subroutine rec_dens

    end subroutine rec

    ! DESTRUCTORS

    !>  \brief  is the expanded destructor
    subroutine dealloc_exp( self )
        class(reconstructor), intent(inout) :: self !< this instance
        if(allocated(self%rho_exp))then
            deallocate(self%rho_exp,stat=alloc_stat)
            if(alloc_stat /= 0) allocchk(" simple_reconstructor:: dealloc_exp; rho_exp ;")
        endif
        if(allocated(self%cmat_exp))then
           deallocate(self%cmat_exp,stat=alloc_stat)
            if(alloc_stat /= 0) allocchk(" simple_reconstructor:: dealloc_exp; cmat_exp ;")
        endif

        self%rho_exp_allocated  = .false.
        self%cmat_exp_allocated = .false.
    end subroutine dealloc_exp

    !>  \brief  is a destructor
    subroutine dealloc_rho( self )
        class(reconstructor), intent(inout) :: self !< this instance
        if(allocated(self%physmat))then
            deallocate(self%physmat,stat=alloc_stat)
            if(alloc_stat /= 0) allocchk(" simple_reconstructor:: dealloc_exp; physmat ;")
        endif
        call self%dealloc_exp
        if( self%rho_allocated )then
            call fftwf_free(self%kp)
            self%rho => null()
            self%rho_allocated = .false.
        endif
    end subroutine dealloc_rho

end module simple_reconstructor

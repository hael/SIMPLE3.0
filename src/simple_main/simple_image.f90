!>  \brief  SIMPLE image class
module simple_image
use simple_ftiter, only: ftiter
use simple_jiffys, only: alloc_err
use simple_fftw3
use simple_math
use gnufor2
use simple_rnd
use simple_stat
use simple_defs
implicit none

public :: image, test_image
private

! CLASS PARAMETERS/VARIABLES
logical, parameter :: shift_to_phase_origin=.true.
logical, parameter :: debug=.false.

type :: image
    private
    logical                                :: ft=.false.           !< FTed or not
    integer                                :: ldim(3)=[1,1,1]      !< logical image dimensions
    integer                                :: nc                   !< number of F-comps
    real                                   :: smpd                 !< sampling distance
    type(ftiter)                           :: fit                  !< Fourier iterator object
    type(c_ptr)                            :: p                    !< c pointer for fftw allocation
    real(kind=c_float), pointer            :: rmat(:,:,:)=>null()  !< image pixels/voxels (in data)
    complex(kind=c_float_complex), pointer :: cmat(:,:,:)=>null()  !< Fourier components
    real                                   :: shconst(3)           !< shift constant
    type(c_ptr)                            :: plan_fwd             !< fftw plan for the image (fwd)
    type(c_ptr)                            :: plan_bwd             !< fftw plan for the image (bwd)
    integer                                :: array_shape(3)       !< shape of complex array
    integer                                :: lims(3,2)            !< physical limits for the XFEL patterns
    character(len=STDLEN)                  :: imgkind='em'         !< indicates image kind (different representation 4 EM/XFEL)
    logical                                :: existence=.false.    !< indicates existence
  contains
    ! CONSTRUCTORS
    procedure          :: new
    procedure          :: disc
    procedure          :: copy
    procedure          :: mic2spec
    procedure          :: boxconv
    procedure          :: window
    procedure          :: window_slim
    procedure          :: win2arr
    procedure          :: extr_pixels
    procedure          :: corner
    ! I/O
    procedure          :: open
    procedure          :: read
    procedure          :: write
    procedure, private :: write_emkind
    ! GETTERS/SETTERS
    procedure          :: get_array_shape
    procedure          :: get_ldim
    procedure          :: get_smpd
    procedure          :: get_nyq
    procedure          :: get_filtsz
    procedure          :: get_imgkind
    procedure          :: get_cmat_lims
    procedure          :: cyci
    procedure          :: get
    procedure          :: get_rmat
    procedure          :: get_cmat
    procedure          :: expand_ft
    procedure          :: set
    procedure          :: set_rmat
    procedure          :: set_ldim
    procedure          :: get_slice
    procedure          :: set_slice
    procedure          :: get_npix
    procedure          :: get_lfny
    procedure          :: get_lhp
    procedure          :: get_lp
    procedure          :: get_spat_freq
    procedure          :: get_find
    procedure          :: get_clin_lims
    procedure          :: rmat_associated
    procedure          :: cmat_associated
    procedure          :: serialize
    procedure          :: winserialize
    procedure          :: zero2one
    procedure          :: get_fcomp
    procedure          :: set_fcomp
    procedure          :: add_fcomp
    procedure          :: subtr_fcomp
    procedure          :: vis
    procedure          :: set_ft
    procedure          :: extr_fcomp
    procedure          :: packer
    ! CHECKUPS
    procedure          :: exists
    procedure          :: is_2d
    procedure          :: is_3d
    procedure          :: even_dims
    procedure          :: square_dims
    procedure, private :: same_dims_1
    generic            :: operator(.eqdims.) => same_dims_1
    procedure          :: same_dims
    procedure          :: same_smpd
    procedure          :: same_kind
    generic            :: operator(.eqsmpd.) => same_smpd
    procedure          :: is_ft
    ! ARITHMETICS
    procedure, private :: assign
    procedure, private :: assign_r2img
    procedure, private :: assign_c2img
    generic :: assignment(=) => assign, assign_r2img, assign_c2img
    procedure, private :: subtraction
    generic :: operator(-) => subtraction
    procedure, private :: addition
    generic :: operator(+) => addition
    procedure, private :: multiplication
    generic :: operator(*) => multiplication
    procedure, private :: division
    generic :: operator(/) => division
    procedure, private :: l1norm_1
    procedure, private :: l1norm_2
    generic :: operator(.lone.) => l1norm_1
    generic :: operator(.lonesum.) => l1norm_2
    procedure          :: l1weights
    procedure, private :: add_1
    procedure, private :: add_2
    procedure, private :: add_3
    procedure, private :: add_4
    procedure, private :: add_5
    generic            :: add => add_1, add_2, add_3, add_4, add_5
    procedure, private :: subtr_1
    procedure, private :: subtr_2
    procedure, private :: subtr_3
    procedure, private :: subtr_4
    generic            :: subtr => subtr_1, subtr_2, subtr_3, subtr_4
    procedure, private :: div_1
    procedure, private :: div_2
    procedure, private :: div_3
    procedure, private :: div_4
    generic            :: div => div_1, div_2, div_3, div_4
    procedure          :: ctf_dens_correct
    procedure, private :: mul_1
    procedure, private :: mul_2
    procedure, private :: mul_3
    procedure, private :: mul_4
    generic            :: mul => mul_1, mul_2, mul_3, mul_4
    procedure, private :: conjugate
    generic            :: conjg => conjugate
    procedure          :: sqpow
    procedure          :: signswap_aimag
    procedure          :: signswap_real
    ! BINARY IMAGE METHODS
    procedure          :: nforeground
    procedure          :: nbackground
    procedure, private :: bin_1
    procedure, private :: bin_2
    procedure, private :: bin_3
    generic            :: bin => bin_1, bin_2, bin_3
    procedure          :: bin_filament
    procedure          :: masscen
    procedure          :: center
    procedure          :: bin_inv
    procedure          :: grow_bin
    procedure          :: grow_bin2
    procedure          :: cos_edge
    procedure          :: increment
    ! FILTERS
    procedure          :: acf
    procedure          :: ccf
    procedure          :: guinier_bfac
    procedure          :: guinier
    procedure          :: spectrum
    procedure          :: shellnorm
    procedure          :: apply_bfac
    procedure          :: bp
    procedure          :: gen_lpfilt
    procedure, private :: apply_filter_1
    procedure, private :: apply_filter_2
    generic            :: apply_filter => apply_filter_1, apply_filter_2
    procedure          :: phase_rand
    procedure          :: hannw
    ! CALCULATORS
    procedure          :: square_root
    procedure          :: maxcoord
    procedure          :: minmax
    procedure          :: rmsd
    procedure          :: stats
    procedure          :: noisesdev
    procedure          :: est_noise_pow
    procedure          :: est_noise_pow_norm
    procedure          :: mean
    procedure          :: median_pixel
    procedure          :: contains_nans
    procedure          :: checkimg4nans
    procedure, private :: cure_1
    procedure, private :: cure_2
    generic            :: cure => cure_1, cure_2
    procedure          :: loop_lims
    procedure          :: comp_addr_phys
    procedure          :: corr
    procedure          :: corr_shifted
    procedure          :: real_corr
    procedure          :: prenorm4real_corr
    procedure          :: real_corr_prenorm
    procedure          :: rank_corr
    procedure          :: real_dist
    procedure          :: fsc
    procedure          :: get_nvoxshell
    procedure          :: get_res
    procedure, private :: oshift_1
    procedure, private :: oshift_2
    generic            :: oshift => oshift_1, oshift_2
    procedure, private :: gen_argtransf_comp
    procedure          :: gen_argtransf_mats
    ! MODIFIERS
    procedure          :: insert
    procedure          :: inv
    procedure          :: ran
    procedure          :: gauran
    procedure          :: add_gauran
    procedure          :: dead_hot_positions
    procedure          :: taper_edges
    procedure          :: salt_n_pepper
    procedure          :: square
    procedure          :: corners
    procedure          :: before_after
    procedure          :: gauimg
    procedure          :: fwd_ft
    procedure          :: em2xfel
    procedure          :: ft2img
    procedure          :: fwd_logft
    procedure          :: mask
    procedure, private :: fmaskv_1
    procedure, private :: fmaskv_2
    generic            :: fmaskv => fmaskv_1, fmaskv_2
    procedure          :: neg
    procedure          :: pad
    procedure          :: resize_nn
    procedure          :: resize_bilin
    procedure          :: clip
    procedure          :: clip_inplace
    procedure          :: mirror
    procedure          :: norm
    procedure          :: norm_ext
    procedure          :: radius_norm
    procedure          :: noise_norm
    procedure          :: norm_bin
    procedure          :: roavg
    procedure          :: rtsq
    procedure          :: shift_phorig
    procedure          :: bwd_ft
    procedure          :: bwd_logft
    procedure          :: shift
    procedure          :: cure_outliers
    ! DESTRUCTOR
    procedure :: kill
end type

interface image
    module procedure constructor
end interface

contains

    ! CONSTRUCTORS

    !>  \brief  is a constructor
    function constructor( ldim, smpd, imgkind, backgr ) result( self ) !(FAILS W PRESENT GFORTRAN)
        integer,                    intent(in) :: ldim(:)
        real,                       intent(in) :: smpd
        character(len=*), optional, intent(in) :: imgkind
        real,             optional, intent(in) :: backgr
        type(image) :: self
        call self%new( ldim, smpd, imgkind, backgr )
    end function constructor

    !>  \brief  is a constructor
    subroutine new( self, ldim, smpd, imgkind, backgr )
    ! have to have a type-bound constructor here because we get a sigbus error with the function construct
    ! "program received signal sigbus: access to an undefined portion of a memory object."
    ! this seems to be related to how the cstyle-allocated matrix is referenced by the gfortran compiler
        class(image),               intent(inout) :: self
        integer,                    intent(in)    :: ldim(3)
        real,                       intent(in)    :: smpd
        character(len=*), optional, intent(in)    :: imgkind
        real,             optional, intent(in)    :: backgr
        integer(kind=c_int) :: rc
        integer :: i
        call self%kill
        self%ldim = ldim
        self%smpd = smpd
        self%imgkind = 'em'
        if( present(imgkind) ) self%imgkind = imgkind
        ! Make Fourier iterator
        call self%fit%new(ldim, smpd, self%imgkind)
        ! Work out dimensions of the complex array
        self%array_shape(1)   = fdim(self%ldim(1))
        self%array_shape(2:3) = self%ldim(2:3)
        if( self%imgkind .eq. 'xfel' )then
            if( self%even_dims() )then
                self%lims(1,1) = -self%ldim(1)/2
                self%lims(1,2) = self%ldim(1)/2-1
                self%lims(2,1) = -self%ldim(2)/2
                self%lims(2,2) = self%ldim(2)/2-1
                self%lims(3,1) = 0
                self%lims(3,2) = 0
                if( self%ldim(3) > 1 )then
                    self%lims(3,1) = -self%ldim(3)/2
                    self%lims(3,2) = self%ldim(3)/2-1
                endif
                allocate(self%cmat(self%lims(1,1):self%lims(1,2),self%lims(2,1):self%lims(2,2),self%lims(3,1):self%lims(3,2)))
            else
                stop 'even dimensions assumed for xfel images; smple_image::new'
            endif
            self%ft = .true.
        else
            self%nc = int(product(self%array_shape)) ! nr of components
            ! Letting FFTW do the allocation in C ensures that we will be using aligned memory
            self%p = fftwf_alloc_complex(int(product(self%array_shape),c_size_t))
            ! Set up the complex array which will point at the allocated memory
            call c_f_pointer(self%p,self%cmat,self%array_shape)
            ! Work out the shape of the real array
            self%array_shape(1) = 2*(self%array_shape(1))
            ! Set up the real array
            call c_f_pointer(self%p,self%rmat,self%array_shape)
            ! put back the shape of the complex array
            self%array_shape(1) = fdim(self%ldim(1))
            if( present(backgr) )then
                self%rmat = backgr
            else
                self%rmat = 0.
            endif
            self%ft = .false.
        endif
        ! make fftw plans
        if( (any(ldim > 500) .or. ldim(3) > 200) .and. nthr_glob > 1 )then
            rc = fftwf_init_threads()
            call fftwf_plan_with_nthreads(nthr_glob)
        endif
        if(self%ldim(3) > 1)then
            self%plan_fwd = fftwf_plan_dft_r2c_3d(self%ldim(3), self%ldim(2), self%ldim(1), self%rmat, self%cmat, fftw_estimate )
            self%plan_bwd = fftwf_plan_dft_c2r_3d(self%ldim(3), self%ldim(2), self%ldim(1), self%cmat, self%rmat, fftw_estimate )
        else
            self%plan_fwd = fftwf_plan_dft_r2c_2d(self%ldim(2), self%ldim(1), self%rmat, self%cmat, fftw_estimate )
            self%plan_bwd = fftwf_plan_dft_c2r_2d(self%ldim(2), self%ldim(1), self%cmat, self%rmat, fftw_estimate )
        endif
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
        self%existence = .true.
    end subroutine new

    !>  \brief  constructs a binary disc of given radius and returns the number of 1:s
    subroutine disc( self, ldim, smpd, radius, npix )
        class(image),      intent(inout) :: self
        integer,           intent(in)    :: ldim(3)
        real,              intent(in)    :: smpd, radius
        integer, optional, intent(inout) :: npix
        call self%new(ldim, smpd)
        self%rmat = 1.
        call self%mask(radius, 'hard')
        if( present(npix) )npix = nint(sum(self%rmat(:ldim(1),:ldim(2),:ldim(3))))
    end subroutine disc

    !>  \brief  is a constructor that copies the input object
    subroutine copy( self, self_in )
        class(image), intent(inout) :: self
        class(image), intent(in)    :: self_in
        if( self_in%exists() )then
            if( self%exists() )then
                if( (self.eqsmpd.self_in) .and. (self.eqdims.self_in) )then
                else
                    call self%new(self_in%ldim, self_in%smpd, imgkind=self_in%imgkind)
                endif
            else
                call self%new(self_in%ldim, self_in%smpd, imgkind=self_in%imgkind)
            endif
            if( self_in%imgkind .eq. 'xfel' )then
                self%cmat = self_in%cmat
            else
                self%rmat = self_in%rmat
            endif
            self%ft = self_in%ft
        else
            stop 'cannot copy nonexistent image; copy; simple_image'
        endif
    end subroutine copy
    
    !>  \brief  calculates the average powerspectrum over a micrograph
    function mic2spec( self, box, speckind ) result( img_out )
        class(image),     intent(inout) :: self
        integer,          intent(in)    :: box
        character(len=*), intent(in)    :: speckind
        type(image) :: img_out, tmp, tmp2
        integer     :: xind, yind, cnt
        logical     :: didft
        if( self%ldim(3) /= 1 ) stop 'only for 2D images; mic2spec; simple_image'
        if( self%ldim(1) <= box .or. self%ldim(2) <= box )then
            stop 'cannot boxconvolute using a box larger than the image; mic2spec; simple_image'
        endif
        didft = .false.
        if( self%ft )then
            call self%bwd_ft
            didft = .true.
        endif
        call img_out%new([box,box,1], self%smpd)
        cnt = 0
        do xind=0,self%ldim(1)-box,box/2
            do yind=0,self%ldim(2)-box,box/2
                call self%window([xind,yind],box,tmp)
                call tmp%taper_edges
                call tmp%fwd_ft
                call tmp%ft2img(speckind, tmp2)
                call img_out%add(tmp2)
                cnt = cnt+1
                call tmp%kill
                call tmp2%kill
            end do
        end do
        call img_out%div(real(cnt))
        if( didft ) call self%fwd_ft
    end function mic2spec
    
    !>  \brief  calculates the average powerspectrum over a micrograph
    function boxconv( self, box ) result( img_out )
        class(image), intent(inout) :: self
        integer,      intent(in)    :: box
        type(image) :: img_out, tmp
        integer     :: xind, yind, cnt
        logical     :: didft
        if( self%ldim(3) /= 1 ) stop 'only for 2D images; boxconvolute; simple_image'
        if( self%ldim(1) <= box .or. self%ldim(2) <= box )then
            stop 'cannot boxconvolute using a box larger than the image; boxconvolute; simple_image'
        endif
        didft = .false.
        if( self%ft )then
            call self%bwd_ft
            didft = .true.
        endif
        call img_out%new([box,box,1], self%smpd)
        cnt = 0
        do xind=0,self%ldim(1)-box,box/2
            do yind=0,self%ldim(2)-box,box/2
                call self%window([xind,yind],box,tmp)
                call img_out%add(tmp)
                cnt = cnt+1
                call tmp%kill
            end do
        end do
        call img_out%div(real(cnt))
        if( didft ) call self%fwd_ft
    end function boxconv

    !>  \brief  extracts a particle image from a box as defined by EMAN 1.9
    subroutine window( self_in, coord, box, self_out, noutside )
        class(image),      intent(in)    :: self_in
        integer,           intent(in)    :: coord(2), box
        class(image),      intent(inout) :: self_out
        integer, optional, intent(inout) :: noutside
        integer :: fromc(2), toc(2), xoshoot, yoshoot, xushoot, yushoot, xboxrange(2), yboxrange(2)
        if( self_in%ldim(3) > 1 ) stop 'only 4 2D images; window; simple_image'
        if( self_in%is_ft() )     stop 'only 4 real images; window; simple_image'
        if( self_out%exists() )then
            if( self_out%is_ft() ) stop 'only 4 real images; window; simple_image'
            if( self_out%ldim(1) == box .and. self_out%ldim(2) == box .and. self_out%ldim(3) == 1 )then
                ! go ahead
            else
                call self_out%new([box,box,1], self_in%smpd)
            endif
        else
            call self_out%new([box,box,1], self_in%smpd)
        endif
        fromc = coord+1       ! compensate for the c-range that starts at 0
        toc   = fromc+(box-1) ! the lower left corner is 1,1
        if( any(fromc < 1) .or. toc(1) > self_in%ldim(1) .or. toc(2) > self_in%ldim(2) )then
            if( present(noutside) )then
                noutside = noutside+1
            else
                write(*,*) 'WARNING! Box extends outside micrograph; window; simple_image'
            endif
        endif
        xoshoot = 0
        yoshoot = 0
        xushoot = 0
        yushoot = 0
        if( toc(1)   > self_in%ldim(1) ) xoshoot =  toc(1)   - self_in%ldim(1)
        if( toc(2)   > self_in%ldim(2) ) yoshoot =  toc(2)   - self_in%ldim(2)
        if( fromc(1) < 1               ) xushoot = -fromc(1) + 1
        if( fromc(2) < 1               ) yushoot = -fromc(2) + 1
        toc(1)        = toc(1)   - xoshoot
        toc(2)        = toc(2)   - yoshoot
        fromc(1)      = fromc(1) + xushoot
        fromc(2)      = fromc(2) + yushoot
        xboxrange(1)  = xushoot  + 1
        xboxrange(2)  = box      - xoshoot
        yboxrange(1)  = yushoot  + 1
        yboxrange(2)  = box      - yoshoot
        self_out%rmat = 0.
        self_out%rmat(xboxrange(1):xboxrange(2),yboxrange(1):yboxrange(2),1) = self_in%rmat(fromc(1):toc(1),fromc(2):toc(2),1)
    end subroutine window

    !>  \brief  extracts a particle image from a box as defined by EMAN 1.9
    subroutine window_slim( self_in, coord, box, self_out, noutside )
        class(image),      intent(in)    :: self_in
        integer,           intent(in)    :: coord(2), box
        class(image),      intent(inout) :: self_out
        integer, optional, intent(inout) :: noutside
        integer :: fromc(2), toc(2)
        fromc = coord + 1         ! compensate for the c-range that starts at 0
        toc   = fromc + (box - 1) ! the lower left corner is 1,1
        self_out%rmat = 0.
        self_out%rmat(1:box,1:box,1) = self_in%rmat(fromc(1):toc(1),fromc(2):toc(2),1)
    end subroutine window_slim

    !>  \brief  extracts a small window into an array (circular indexing)
    function win2arr( self, i, j, k, winsz ) result( pixels )
        use simple_math, only: cyci_1d
        class(image), intent(inout) :: self
        integer,      intent(in)    :: i, j, k, winsz
        real, allocatable :: pixels(:)
        integer :: s, ss, t, tt, u, uu, cnt, npix, alloc_stat
        if( self%is_ft() ) stop 'only 4 real images; win2arr; simple_image'
        if( self%is_3d() )then
            npix = (2*winsz+1)**3
        else
            npix = (2*winsz+1)**2
        endif
        allocate(pixels(npix), stat=alloc_stat)
        call alloc_err('In: win2arr; simple_image', alloc_stat)
        cnt = 1
        do s=i-winsz,i+winsz
            ss = cyci_1d([1,self%ldim(1)], s)
            do t=j-winsz,j+winsz
                tt = cyci_1d([1,self%ldim(2)], t)
                if( self%is_3d() )then
                    do u=k-winsz,k+winsz
                        uu          = cyci_1d([1,self%ldim(3)], u)
                        pixels(cnt) = self%rmat(ss,tt,uu)
                        cnt         = cnt+1
                    end do
                else
                    pixels(cnt) = self%rmat(ss,tt,1)
                    cnt         = cnt+1
                endif
            end do
        end do
    end function win2arr

    !>  \brief  extracts the pixels under the mask
    function extr_pixels( self, mskimg ) result( pixels )
        class(image), intent(in) :: self
        class(image), intent(in) :: mskimg
        real, allocatable :: pixels(:)
        if( self%is_ft() ) stop 'only 4 real images; extr_pixels; simple_image'
        if( self.eqdims.mskimg )then
            ! pixels = self%packer(mskimg) ! Intel hickup
            pixels = pack( self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)),&
                &mskimg%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3))>0.5 )
        else
            stop 'mask and image of different dims; extr_pixels; simple_image'
        endif
    end function extr_pixels

    !>  \brief  extracts a corner of a volume with size box
    subroutine corner( self_in, box, self_out )
        class(image), intent(in)    :: self_in
        integer,      intent(in)    :: box
        type(image),  intent(inout) :: self_out
        if( self_in%ldim(3) <= 1 ) stop 'only 4 3D images; corner; simple_image'
        if( self_in%is_ft() )      stop 'only 4 real images; corner; simple_image'
        call self_out%new([box,box,box], self_in%smpd)
        self_out%rmat(:box,:box,:box) = self_in%rmat(:box,:box,:box)
    end subroutine corner

    ! I/O

    !>  \brief  for reading 2D images from stack or volumes from volume files
    subroutine open( self, fname, ioimg, formatchar, readhead, rwaction )
        use simple_imgfile,      only: imgfile
        use simple_jiffys,       only: read_raw_image
        use simple_filehandling, only: fname2format, file_exists
        class(image),               intent(inout) :: self
        character(len=*),           intent(in)    :: fname
        class(imgfile),             intent(inout) :: ioimg
        character(len=1), optional, intent(in)    :: formatchar
        logical,          optional, intent(in)    :: readhead
        character(len=*), optional, intent(in)    :: rwaction
        character(len=1) :: form
        integer          :: mode
        logical          :: debug=.false.
        if( self%existence )then
            if( .not. file_exists(fname) )then
                stop 'The file you are trying to open does not exists; open; simple_image'
            endif
            if( present(formatchar) )then
                form = formatchar
            else
                form = fname2format(fname)
            endif
            self%ft = .false.
            select case(form)
                case('M')
                    call ioimg%open(fname, self%ldim, self%smpd, formatchar=formatchar, readhead=readhead, rwaction=rwaction)
                    if( debug )then
                        write(*,*) '**** DEBUG **** file info right after opening the file'
                        call ioimg%print
                    endif
                    ! data type: 0 image: signed 8-bit bytes rante -128 to 127
                    !            1 image: 16-bit halfwords
                    !            2 image: 32-bit reals (DEFAULT MODE)
                    !            3 transform: complex 16-bit integers
                    !            4 transform: complex 32-bit reals (THIS WOULD BE THE DEFAULT FT MODE)
                    mode = ioimg%getMode()
                    if( mode == 3 .or. mode == 4 ) self%ft = .true.
                case('F')
                    call ioimg%open(fname, self%ldim, self%smpd, formatchar=formatchar, readhead=readhead, rwaction=rwaction)
                    if( debug )then
                        write(*,*) '**** DEBUG **** file info right after opening the file'
                        call ioimg%print
                    endif
                case('S')
                    call ioimg%open(fname, self%ldim, self%smpd, formatchar=formatchar, readhead=readhead, rwaction=rwaction)
                    if( debug )then
                        write(*,*) '**** DEBUG **** file info right after opening the file'
                        call ioimg%print
                    endif
            end select
        else
            stop 'ERROR, image need to be constructed before read/write; open; simple_image'
        endif
    end subroutine open

    !>  \brief  for reading 2D images from stack or volumes from volume files
    subroutine read( self, fname, i, ioimg, isxfel, formatchar, readhead, rwaction, read_failure )
        use simple_imgfile,      only: imgfile
        use simple_jiffys,       only: read_raw_image
        use simple_filehandling, only: fname2format, file_exists
        class(image),               intent(inout) :: self
        character(len=*),           intent(in)    :: fname
        integer,          optional, intent(in)    :: i
        class(imgfile),   optional, intent(inout) :: ioimg 
        logical,          optional, intent(in)    :: isxfel
        character(len=1), optional, intent(in)    :: formatchar
        logical,          optional, intent(in)    :: readhead
        character(len=*), optional, intent(in)    :: rwaction
        logical,          optional, intent(out)   :: read_failure
        type(imgfile)         :: ioimg_local
        character(len=1)      :: form
        integer               :: ldim(3), iform, first_slice, mode
        integer               :: last_slice, ii, alloc_stat
        real                  :: smpd
        logical               :: isvol, err, iisxfel, ioimg_present
        logical, parameter    :: DEBUG=.false.
        real(dp), allocatable :: tmpmat1(:,:,:)
        real(sp), allocatable :: tmpmat2(:,:,:)
        ldim          = self%ldim
        smpd          = self%smpd
        ioimg_present = present(ioimg)
        iisxfel       = .false.
        if( present(isxfel) ) iisxfel = isxfel
        if( iisxfel )then
            ! always assume EM-kind images on disk
            if( debug ) print *, 'ldim: ', ldim
            if( debug ) print *, 'smpd: ', smpd
            call self%new(ldim, smpd)
        endif
        isvol = .true. ! assume volume by default
        ii    = 1      ! default location
        if( present(i) )then
            ! we are reading from a stack & in SIMPLE volumes are not allowed
            ! to be stacked so the image object must be 2D
            isvol = .false.
            ii = i ! replace default location
        endif
        if( present(formatchar) )then
            form = formatchar
        else
            form = fname2format(fname)
        endif
        if( ioimg_present )then
            call exception_handler(ioimg)
            call read_local(ioimg)
        else
            select case(form)
                case('M','F','S')
                    call self%open(fname, ioimg_local, formatchar, readhead, rwaction)
                case('D')
                    if( self%even_dims())then
                        allocate(tmpmat1(self%ldim(1),self%ldim(2),self%ldim(3)),&
                        tmpmat2(self%ldim(1),self%ldim(2),self%ldim(3)), stat=alloc_stat)
                        call alloc_err('In: simple_image::read, tmpmat1 & tmpmat2', alloc_stat)
                        call read_raw_image(fname, tmpmat1, 1)
                        self%ft = .true.
                        tmpmat2 = 0.
                        self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)) = real(tmpmat1)
                        call self%em2xfel
                        deallocate(tmpmat1,tmpmat2)
                        return
                    else
                        stop 'mode: D, code for odd dimensions not yet implemented'
                    endif
                case DEFAULT
                    write(*,*) 'Trying to read from file: ', fname
                    stop 'ERROR, unsupported file format; read; simple_image'
            end select
            call exception_handler(ioimg_local)
            call read_local(ioimg_local)
        endif

        contains

            subroutine read_local( ioimg )
                class(imgfile) :: ioimg
                ! work out the slice range
                if( isvol )then
                    if( ii .gt. 1 ) stop 'ERROR, stacks of volumes not supported; read; simple_image'
                    first_slice = 1
                    last_slice = ldim(3)
                else
                    first_slice = ii
                    last_slice = ii
                endif
                call ioimg%rwSlices('r',first_slice,last_slice,self%rmat,&
                &self%ldim,self%ft,self%smpd,read_failure=read_failure)
                if( .not. ioimg_present ) call ioimg%close
                ! normalize if volume
                if( self%is_3d() .and. .not. iisxfel )then
                    err = .false.
                    if( .not. self%ft ) call self%norm(err=err)
                    if( err )then
                        write(*,*) 'Normalization error, trying to read: ', fname
                        stop
                    endif
                endif
                if( iisxfel ) call self%em2xfel
            end subroutine read_local

            subroutine exception_handler( ioimg )
                class(imgfile) :: ioimg
                if( form .eq. 'S' ) call spider_exception_handler(ioimg)
                if( form .ne. 'F' )then
                    ! make sure that the logical image dimensions of self are consistent with the overall header
                    ldim = ioimg%getDims()
                    if( .not. all(ldim(1:2) == self%ldim(1:2)) )then
                        write(*,*) 'ldim of image object: ', self%ldim
                        write(*,*) 'ldim in ioimg (fhandle) object: ', ldim
                        stop 'ERROR, logical dimensions of overall header & image object do not match; read; simple_image'
                    endif
                endif
            end subroutine exception_handler

            subroutine spider_exception_handler(ioimg)
                class(imgfile) :: ioimg
                iform = ioimg%getIform()
                ! iform file type specifier:
                !   1 = 2D image
                !   3 = 3D volume
                ! -11 = 2D Fourier odd
                ! -12 = 2D Fourier even
                ! -21 = 3D Fourier odd
                ! -22 = 3D Fourier even
                select case(iform)
                    case(1,-11,-12)
                        ! we are processing a stack of 2D images (single 2D images not allowed in SIMPLE)
                        if( present(i) )then
                            ! all good
                        else
                            stop 'ERROR, optional argument i required for reading from stack; read; simple_image'
                        endif
                        if( self%ldim(3) == 1 )then
                            ! all good
                        else if( self%ldim(3) > 1 )then
                            stop 'ERROR, trying to read from a stack into a volume; read; simple_image'
                        else
                            stop 'ERROR, nonconforming logical dimension of image; read; simple_image'
                        endif
                        if( iform == -11 .or. iform == -12 ) self%ft = .true.
                    case(3,-21,-22)
                        ! we are processing a 3D image (stacks of 3D volumes not allowed in SIMPLE)
                        if( present(i) )then
                            stop 'ERROR, optional argument i should not be present when reading volumes; read; simple_image'
                        endif
                        if( self%ldim (3) > 1 )then
                            ! all good
                        else if( self%ldim(3) == 1)then
                            stop 'ERROR, trying to read from a volume into a 2D image; read; simple_image'
                        else
                            stop 'ERROR, nonconforming logical dimension of image; read; simple_image'
                        endif
                        if( iform == -21 .or. iform == -22 ) self%ft = .true.
                    case DEFAULT
                        write(*,*) 'iform = ', iform
                        stop 'Unsupported iform flag; simple_image :: read'
                end select
            end subroutine spider_exception_handler

    end subroutine read

    !>  \brief  for writing any kind of images to stack or volumes to volume files
    subroutine write( self, fname, i, del_if_exists, formatchar, rmsd )
        class(image),               intent(inout) :: self
        character(len=*),           intent(in)    :: fname
        integer,          optional, intent(in)    :: i
        logical,          optional, intent(in)    :: del_if_exists
        character(len=1), optional, intent(in)    :: formatchar
        real,             optional, intent(in)    :: rmsd
        type(image) :: tmpimg
        if( self%imgkind .eq. 'xfel' )then
             call self%ft2img('real', tmpimg)
             call tmpimg%write_emkind(fname, i, del_if_exists, formatchar=formatchar, rmsd=rmsd)
             call tmpimg%kill
        else
            call self%write_emkind(fname, i, del_if_exists, formatchar=formatchar, rmsd=rmsd)
        endif
    end subroutine write

    !>  \brief  for writing emkind images to stack or volumes to volume files
    subroutine write_emkind( self, fname, i, del_if_exists, formatchar, rmsd )
        use simple_imgfile,      only: imgfile
        use simple_filehandling, only: fname2format
        class(image),               intent(inout) :: self
        character(len=*),           intent(in)    :: fname
        integer,          optional, intent(in)    :: i
        logical,          optional, intent(in)    :: del_if_exists
        character(len=1), optional, intent(in)    :: formatchar
        real,             optional, intent(in)    :: rmsd
        type(imgfile)     :: ioimg
        character(len=1)  :: form
        integer           :: first_slice, last_slice, iform, ii
        logical           :: isvol, die
        if( self%existence )then
            die = .false.
            if( present(del_if_exists) ) die = del_if_exists
            if( self%is_2d() )then
                isvol = .false.
            else if( self%is_3d() )then
                isvol = .true.
            endif
            ii = 1 ! default location
            if( present(i) )then
                ! we are writing to a stack & in SIMPLE volumes are not allowed
                ! to be stacked so the image object must be 2D
                if( isvol )then
                    stop 'ERROR, trying to write 3D image to stack, which is not allowed in SIMPLE ; write; simple_image'
                endif
                ii = i ! replace default location
            endif
            ! find format
            if( present(formatchar) )then
                form = formatchar
            else
                form = fname2format(fname)
            endif
            select case(form)
                case('M','F')
                    ! pixel size of object overrides pixel size in header
                    call ioimg%open(fname, self%ldim, self%smpd, del_if_exists=die,&
                    formatchar=formatchar, readhead=.false.)
                    ! data type: 0 image: signed 8-bit bytes rante -128 to 127
                    !            1 image: 16-bit halfwords
                    !            2 image: 32-bit reals (DEFAULT MODE)
                    !            3 transform: complex 16-bit integers
                    !            4 transform: complex 32-bit reals (THIS WOULD BE THE DEFAULT FT MODE)
                    if( self%ft )then
                        call ioimg%setMode(4)
                    else
                        call ioimg%setMode(2)
                    endif
                    if( present(rmsd) ) call ioimg%setRMSD(rmsd)
                case('S')
                    ! pixel size of object overrides pixel size in header
                    call ioimg%open(fname, self%ldim, self%smpd, del_if_exists=die,&
                    formatchar=formatchar, readhead=.false.)
                    ! iform file type specifier:
                    !   1 = 2D image
                    !   3 = 3D volume
                    ! -11 = 2D Fourier odd
                    ! -12 = 2D Fourier even
                    ! -21 = 3D Fourier odd
                    ! -22 = 3D Fourier even
                    if( self%is_2d() )then
                        if( self%ft )then
                            if( self%even_dims() )then
                                iform = -12
                            else
                                iform = -11
                            endif
                        else
                            iform = 1
                        endif
                    else
                        if( self%ft )then
                            if( self%even_dims() )then
                                iform = -22
                            else
                                iform = -21
                            endif
                        else
                            iform = 3
                        endif
                    endif
                    call ioimg%setIform(iform)
                case DEFAULT
                    write(*,*) 'format descriptor: ', form
                    stop 'ERROR, unsupported file format; write; simple_image'
            end select
            ! work out the slice range
            if( isvol )then
                if( ii .gt. 1 ) stop 'ERROR, stacks of volumes not supported; write; simple_image'
                first_slice = 1
                last_slice = self%ldim(3)
            else
                first_slice = ii
                last_slice = ii
            endif
            ! write slice(s) to disk
            call ioimg%rwSlices('w',first_slice,last_slice,self%rmat,self%ldim,self%ft,self%smpd)
            call ioimg%close
        else
            stop 'ERROR, nonexisting image cannot be written to disk; write; simple_image'
        endif
    end subroutine write_emkind

    ! GETTERS/SETTERS

    !>  \brief  is a getter
    pure function get_array_shape( self ) result( shape)
        class(image), intent(in) :: self
        integer :: shape(3)
        shape = self%array_shape
    end function get_array_shape

    !>  \brief  is a getter
    pure function get_ldim( self ) result( ldim )
        class(image), intent(in) :: self
        integer :: ldim(3)
        ldim = self%ldim
    end function get_ldim

    !>  \brief  is a getter
    pure function get_smpd( self ) result( smpd )
        class(image), intent(in) :: self
        real :: smpd
        smpd = self%smpd
    end function get_smpd

    !>  \brief  to get the Nyquist Fourier index
    pure function get_nyq( self ) result( nyq )
        class(image), intent(in) :: self
        integer :: nyq
        nyq = fdim(self%ldim(1))
    end function get_nyq
    
    !>  \brief  to get the size of the filters
    pure function get_filtsz( self ) result( n )
        class(image), intent(in) :: self
        integer :: n
        n = fdim(self%ldim(1))
    end function get_filtsz

    !>  \brief  to get the image kind (em/xfel)
    pure function get_imgkind( self ) result( imgkind )
        class(image), intent(in)      :: self
        character(len=:), allocatable :: imgkind
        allocate(imgkind, source=self%imgkind)
    end function get_imgkind

    !>  \brief  to get the bounds of the cmat for xfel-kind images
    function get_cmat_lims( self ) result( lims )
        class(image), intent(in) :: self
        integer :: lims(3,2)
        if( self%imgkind .eq. 'xfel' )then
            lims = self%lims
        else
            stop 'only xfel-kind images have lims defined; simple_image::get_cmat_lims'
        endif
    end function get_cmat_lims

    !> \brief  cyclic index generation
    function cyci( self, logi ) result( inds )
        class(image), intent(in) :: self
        integer,      intent(in) :: logi(3)
        integer                  :: inds(3), lims(3,2)
        if( self%is_ft() )then
            lims = self%loop_lims(3)
        else
            lims = 1
            lims(1,2) = self%ldim(1)
            lims(2,2) = self%ldim(2)
            lims(3,2) = self%ldim(3)
        endif
        inds(1) = cyci_1d(lims(1,:), logi(1))
        inds(2) = cyci_1d(lims(2,:), logi(2))
        inds(3) = cyci_1d(lims(3,:), logi(3))
    end function cyci

    !>  \brief  is a getter
    function get( self, logi ) result( val )
        class(image), intent(inout) :: self
        integer,      intent(in)    :: logi(3)
        real :: val
        if( self%imgkind .eq. 'xfel' ) stop 'rmat not allocated for xfel-kind images; simple_image::get'
        if( logi(1) > self%ldim(1) .or. logi(1) < 1 )then
            val = 0.
            return
        endif
        if( logi(2) > self%ldim(2) .or. logi(2) < 1 )then
            val = 0.
            return
        endif
        if( logi(3) > self%ldim(3) .or. logi(3) < 1 )then
            val = 0.
            return
        endif
        val = self%rmat(logi(1),logi(2),logi(3))
    end function get

    !>  \brief  is a getter
    function get_rmat( self ) result( rmat )
        class(image), intent(in) :: self
        real, allocatable :: rmat(:,:,:)
        integer :: ldim(3)
        ldim = self%ldim
        allocate(rmat(ldim(1),ldim(2),ldim(3)), source=self%rmat(:ldim(1),:ldim(2),:ldim(3)))
    end function get_rmat

    !>  \brief  is a getter
    function get_cmat( self ) result( cmat )
        class(image), intent(in) :: self
        integer :: array_shape(3)
        complex, allocatable :: cmat(:,:,:)
        array_shape(1)   = fdim(self%ldim(1))
        array_shape(2:3) = self%ldim(2:3)
        allocate(cmat(array_shape(1),array_shape(2),array_shape(3)), source=self%cmat)
    end function get_cmat

    !>  \brief  is for getting a Fourier plane using the old SIMPLE logics
    function expand_ft( self ) result( fplane )
         class(image), intent(in) :: self
         complex, allocatable :: fplane(:,:)
         integer :: xdim, ydim, h, k, phys(3)
         if( self%imgkind .eq. 'xfel' ) stop 'not implemented for xfel-kind images; simple_image :: expand_ft'
         if(is_even(self%ldim(1)))then
             xdim = self%ldim(1)/2
             ydim = self%ldim(2)/2
         else
             xdim = (self%ldim(1)-1)/2
             ydim = (self%ldim(2)-1)/2
         endif
         allocate(fplane(-xdim:xdim,-ydim:ydim))
         fplane = cmplx(0.,0.)
         do h=-xdim,xdim
             do k=-ydim,ydim
                phys = self%comp_addr_phys([h,k,0])
                fplane(h,k) = self%get_fcomp([h,k,0],phys)
            end do
        end do
    end function expand_ft

    !>  \brief  is a setter
    subroutine set( self, logi, val )
        class(image), intent(inout) :: self
        integer,      intent(in)    :: logi(3)
        real,         intent(in)    :: val
        if( self%imgkind .eq. 'xfel' ) stop 'rmat not allocated for xfel-kind images; simple_image::set'
        if( logi(1) <= self%ldim(1) .and. logi(1) >= 1 .and. logi(2) <= self%ldim(2)&
        .and. logi(2) >= 1 .and. logi(3) <= self%ldim(3) .and. logi(3) >= 1 )then
            self%rmat(logi(1),logi(2),logi(3)) = val
        endif
    end subroutine set

    !>  \brief  is a setter
    subroutine set_rmat( self, rmat )
        class(image), intent(inout) :: self
        real,         intent(in)    :: rmat(:,:,:)
        integer :: ldim(3)
        ldim(1) = size(rmat,1)
        ldim(2) = size(rmat,2)
        ldim(3) = size(rmat,3)
        if( all(self%ldim .eq. ldim) )then
            self%ft   = .false.
            self%rmat = 0.
            self%rmat(:ldim(1),:ldim(2),:ldim(3)) = rmat
        else
            write(*,*) 'ldim(rmat): ', ldim
            write(*,*) 'ldim(img): ', self%ldim
            stop 'nonconforming dims; simple_image :: set_rmat'
        endif
    end subroutine set_rmat

    !>  \brief  for setting ldim
    subroutine set_ldim( self, ldim )
        class(image), intent(inout) :: self
        integer,      intent(in)    :: ldim(3)
        self%ldim = ldim
    end subroutine set_ldim

    !>  \brief is for getting a slice from a volume
    function get_slice( self3d, slice ) result( self2d )
        class(image), intent(in) :: self3d
        integer,      intent(in) :: slice
        type(image)              :: self2d
        if( self3d%imgkind .eq. 'xfel' .or. self2d%imgkind .eq. 'xfel' )&
        stop 'not intended for&xfel-kind images; simple_image::get_slice'
        call self2d%new([self3d%ldim(1),self3d%ldim(2),1],self3d%smpd)
        self2d%rmat(:,:,1) = self3d%rmat(:,:,slice)
    end function get_slice
    
    !>  \brief is for putting a slice into a volume
    subroutine set_slice( self3d, slice, self2d )
        class(image), intent(in)    :: self2d
        integer,      intent(in)    :: slice
        class(image), intent(inout) :: self3d
        if( self3d%imgkind .eq. 'xfel' .or. self2d%imgkind .eq. 'xfel' )&
        stop 'not intended for&xfel-kind images; simple_image::set_slice'
        self3d%rmat(:,:,slice) = self2d%rmat(:,:,1) 
    end subroutine set_slice

    !>  \brief is for getting the number of pixels for serialization
    function get_npix( self, mskrad ) result( npix )
        class(image), intent(in) :: self
        real,         intent(in) :: mskrad
        real                     :: ci, cj, ck, e
        integer                  :: npix, i, j, k
        npix = 0
        ci = -real(self%ldim(1))/2.
        do i=1,self%ldim(1)
            cj = -real(self%ldim(2))/2.
            do j=1,self%ldim(2)
                ck = -real(self%ldim(3))/2.
                do k=1,self%ldim(3)
                    if( self%ldim(3) > 1 )then
                        e = hardedge(ci,cj,ck,mskrad)
                    else
                        e = hardedge(ci,cj,mskrad)
                    endif
                    if( e > 0.5 )then
                        npix = npix+1
                    endif
                    ck = ck+1
                end do
                cj = cj+1.
            end do
            ci = ci+1.
        end do
    end function get_npix

    !>  \brief  is a getter
    pure function get_lfny( self, which ) result( fnyl )
        class(image), intent(in) :: self
        integer,      intent(in) :: which
        integer :: fnyl
        fnyl = self%fit%get_lfny(which)
    end function get_lfny

    !>  \brief  is a getter
    pure function get_lhp( self, which ) result( hpl )
        class(image), intent(in) :: self
        integer,      intent(in) :: which
        integer :: hpl
        hpl = self%fit%get_lhp(which)
    end function get_lhp

    !>  \brief  is a getter
    pure function get_lp( self, ind ) result( lp )
        class(image), intent(in) :: self
        integer,      intent(in) :: ind
        real                     :: lp
        lp = self%fit%get_lp(1, ind)
    end function get_lp

    !>  \brief  is a getter
    pure function get_spat_freq( self, ind ) result( spat_freq )
        class(image), intent(in) :: self
        integer,      intent(in) :: ind
        real                     :: spat_freq
        spat_freq = self%fit%get_spat_freq(1, ind)
    end function get_spat_freq

    !>  \brief  is a getter
    pure function get_find( self, res ) result( ind )
        class(image), intent(in) :: self
        real,         intent(in) :: res
        integer :: ind
        ind = self%fit%get_find(1, res)
    end function get_find

    !>  \brief  is a getter
    function get_clin_lims( self, lp_dyn ) result( lims )
        class(image), intent(in) :: self
        real,         intent(in) :: lp_dyn
        integer                  :: lims(2)
        lims = self%fit%get_clin_lims(lp_dyn)
    end function get_clin_lims

    !>  \brief  check rmat association
    function rmat_associated( self ) result( assoc )
        class(image), intent(in) :: self
        logical :: assoc
        assoc = associated(self%rmat)
    end function rmat_associated

    !>  \brief  check cmat association
    function cmat_associated( self ) result( assoc )
        class(image), intent(in) :: self
        logical :: assoc
        assoc = associated(self%cmat)
    end function cmat_associated

    !>  \brief is for packing/unpacking a serialized image vector for pca analysis
    subroutine serialize( self, pcavec, mskrad )
        class(image),      intent(inout) :: self
        real, allocatable, intent(inout) :: pcavec(:)
        real, optional,    intent(in)    :: mskrad
        integer                          :: i, j, k, npix, alloc_stat
        real                             :: ci, cj, ck, e
        logical                          :: pack, usemsk = .false.
        if( present(mskrad) )usemsk=.true.
        if( self%ft ) stop 'ERROR, serialization not yet implemented for Fourier transforms; serialize; simple_image'
        if( usemsk )then
            npix = self%get_npix(mskrad)
        else
            npix = self%ldim(1)*self%ldim(2)*self%ldim(3)
        endif
        if( allocated(pcavec) )then
            if( size(pcavec) /= npix ) stop 'size mismatch mask/npix; serialize; simple_image'
            pack = .false.
        else
            pack = .true.
            allocate( pcavec(npix), stat=alloc_stat )
            call alloc_err('serialize; simple_image', alloc_stat)
            pcavec = 0.
        endif
        npix = 0
        ci = -real(self%ldim(1))/2.
        do i=1,self%ldim(1)
            cj = -real(self%ldim(2))/2.
            do j=1,self%ldim(2)
                ck = -real(self%ldim(3))/2.
                do k=1,self%ldim(3)
                    if( usemsk )then
                        if( self%ldim(3) > 1 )then
                            e = hardedge(ci,cj,ck,mskrad)
                        else
                            e = hardedge(ci,cj,mskrad)
                        endif
                    endif
                    if( (e>0.5).or.(.not.usemsk) )then
                        npix = npix+1
                        if( pack )then
                            pcavec(npix) = self%rmat(i,j,k)
                        else
                            self%rmat(i,j,k) = pcavec(npix)
                        endif
                    endif
                    ck = ck+1
                end do
                cj = cj+1.
            end do
            ci = ci+1.
        end do
    end subroutine serialize

    !>  \brief  is for packing/unpacking a serialized image vector for convolutional pca analysis
    subroutine winserialize( self, coord, winsz, pcavec )
        class(image),      intent(inout) :: self
        real, allocatable, intent(inout) :: pcavec(:)
        integer,           intent(in)    :: coord(:), winsz
        integer :: i, j, k, cnt, npix, alloc_stat
        logical :: pack
        if( self%ft ) stop 'ERROR, winserialization not yet implemented for Fourier transforms; winserialize; simple_image'
        if( self%is_2d() )then
            npix = winsz**2
            call set_action
            cnt = 0
            do i=coord(1),coord(1)+winsz-1
                do j=coord(2),coord(2)+winsz-1
                    cnt = cnt+1
                    if( pack )then
                        if( i > self%ldim(1) .or. j > self%ldim(2) )then
                            pcavec(cnt) = 0.
                        else
                            pcavec(cnt) = self%rmat(i,j,1)
                        endif
                    else
                        if( i > self%ldim(1) .or. j > self%ldim(2) )then
                        else
                            self%rmat(i,j,1) = self%rmat(i,j,1)+pcavec(cnt)
                        endif
                    endif
                end do
            end do
        else
            if( size(coord) < 3 ) stop 'need a 3D coordinate for a 3D image; winserialize; simple_imgae'
            npix = winsz**3
            call set_action
            cnt = 0
            do i=coord(1),coord(1)+winsz-1
                do j=coord(2),coord(2)+winsz-1
                    do k=coord(3),coord(3)+winsz-1
                        cnt = cnt+1
                        if( pack )then
                            if( i > self%ldim(1) .or. j > self%ldim(2) .or. k > self%ldim(3) )then
                                pcavec(cnt) = 0.
                            else
                                pcavec(cnt) = self%rmat(i,j,k)
                            endif
                        else
                            if( i > self%ldim(1) .or. j > self%ldim(2) .or. k > self%ldim(3) )then
                            else
                                self%rmat(i,j,k) = self%rmat(i,j,k)+pcavec(cnt)
                            endif
                        endif
                    end do
                end do
            end do
        endif

        contains

            subroutine set_action
                if( allocated(pcavec) )then
                    if( size(pcavec) /= npix ) stop 'size mismatch mask/npix; winserialize; simple_image'
                    pack = .false.
                else
                    pack = .true.
                    allocate( pcavec(npix), stat=alloc_stat )
                    call alloc_err('winserialize; simple_image', alloc_stat)
                    pcavec = 0.
                endif
            end subroutine set_action

    end subroutine winserialize

    !>  \brief  for swapping all zeroes in image with ones
    subroutine zero2one( self )
        class(image), intent(inout) :: self
        integer :: i, j, k
        if( self%imgkind .eq. 'xfel' ) stop 'rmat not allocated for xfel-kind images; simple_image::zero2one'
        do i=1,self%ldim(1)
            do j=1,self%ldim(2)
                do k=1,self%ldim(3)
                    if( self%rmat(i,j,k) == 0. ) self%rmat(i,j,k) = 1.
                end do
            end do
        end do
    end subroutine zero2one

    !>  \brief  for getting a Fourier component from the compact representation
    function get_fcomp( self, logi, phys ) result( comp )
        class(image), intent(in)  :: self
        integer,      intent(in)  :: logi(3), phys(3)
        complex :: comp
        comp = self%cmat(phys(1),phys(2),phys(3))
        if( self%imgkind .ne. 'xfel' )then
            if( logi(1) < 0 ) comp = conjg(comp)
        endif
    end function get_fcomp

    !>  \brief  for setting a Fourier component in the compact representation
    subroutine set_fcomp( self, logi, phys, comp )
        class(image), intent(inout) :: self
        integer,      intent(in)    :: logi(3), phys(3)
        complex,      intent(in)    :: comp
        complex :: comp_here
        if( logi(1) < 0 .and. self%imgkind .ne. 'xfel' )then
            comp_here = conjg(comp)
        else
            comp_here = comp
        endif
        self%cmat(phys(1),phys(2),phys(3)) = comp_here
    end subroutine set_fcomp

    !>  \brief  is for componentwise summation
    subroutine add_fcomp( self, logi, phys, comp)
        class(image), intent(inout) :: self
        integer,      intent(in)    :: logi(3), phys(3)
        complex,      intent(in)    :: comp
        complex :: comp_here
        if( logi(1) < 0 .and. self%imgkind .ne. 'xfel' )then
            comp_here = conjg(comp)
        else
            comp_here = comp
        endif
        self%cmat(phys(1),phys(2),phys(3)) = self%cmat(phys(1),phys(2),phys(3)) + comp_here
    end subroutine add_fcomp

    !>  \brief  is for componentwise summation
    subroutine subtr_fcomp( self, logi, phys, comp )
        class(image), intent(inout) :: self
        integer,      intent(in)    :: logi(3), phys(3)
        complex,      intent(in)    :: comp
        complex :: comp_here
        if( logi(1) < 0 .and. self%imgkind .ne. 'xfel' )then
            comp_here = conjg(comp)
        else
            comp_here = comp
        endif
        self%cmat(phys(1),phys(2),phys(3)) = self%cmat(phys(1),phys(2),phys(3)) - comp_here
    end subroutine subtr_fcomp

    !>  \brief  is for plotting an image
    subroutine vis( self, sect )
        class(image),      intent(in) :: self
        integer, optional, intent(in) :: sect
        complex, allocatable :: fplane(:,:)
        integer              :: sect_here
        if( self%imgkind .eq. 'xfel' )then
            sect_here = 0
            if( present(sect) ) sect_here = sect
            call gnufor_image(real(self%cmat(:,:,sect_here)), palette='gray')
        else
            sect_here = 1
            if( present(sect) ) sect_here = sect
            if( self%ft )then
                if( self%ldim(3) == 1 ) sect_here = 0
                fplane = self%expand_ft()
                call gnufor_image(real(fplane), palette='gray')
                call gnufor_image(aimag(fplane), palette='gray')
                deallocate(fplane)
            else
                if( self%ldim(3) == 1 ) sect_here = 1
                call gnufor_image(self%rmat(:self%ldim(1),:self%ldim(2),sect_here), palette='gray')
            endif
        endif
    end subroutine vis

    !>  \brief  sets image ft state
    subroutine set_ft( self, is )
        class(image), intent(inout) :: self
        logical,      intent(in)    :: is
        self%ft = is
    end subroutine set_ft

    !>  \brief  is for extracting a Fourier component at arbitrary
    !!          position in a 2D transform using windowed sinc interpolation
    function extr_fcomp( self, h, k, x, y ) result( comp )
        class(image), intent(inout) :: self
        real,         intent(in)    :: h, k, x, y
        complex :: comp
        integer :: win(2,2), i, j, phys(3)
        if( self%ldim(3) > 1 )         stop 'only 4 2D images; extr_fcomp; simple_image'
        if( .not. self%ft )            stop 'image need to be FTed; extr_fcomp; simple_image'
        if( self%imgkind .eq. 'xfel' ) stop 'this method not intended for xfel-kind images; simple_image::extr_fcomp'
        ! evenness and squareness are checked in the comlin class
        win = recwin_2d(h,k,1.)
        comp = cmplx(0.,0.)
        do i=win(1,1),win(1,2)
            do j=win(2,1),win(2,2)
                phys = self%comp_addr_phys([i,j,0])
                comp = comp+sinc(h-real(i))*sinc(k-real(j))*self%get_fcomp([i,j,0],phys)
            end do
        end do
        ! origin shift
        if( x == 0. .and. y == 0. )then
        else
            comp = comp*oshift_here(self%ldim(1)/2, h, k, x, y)
        endif

        contains

            pure function oshift_here( xdim, x, y, dx, dy ) result( comp )
                integer, intent(in)  :: xdim
                real, intent(in)     :: x, y, dx, dy
                complex              :: comp
                real                 :: arg
                arg = (pi/real(xdim))*(dx*x+dy*y)
                comp = cmplx(cos(arg),sin(arg))
            end function oshift_here

    end function extr_fcomp

    !>  \brief  replaces the pack intrinsic because the Intel compiler bugs out
    function packer( self, mskimg ) result( pixels )
        class(image),           intent(in) :: self
        class(image), optional, intent(in) :: mskimg
        real, allocatable :: pixels(:)
        integer :: nsel,i,j,k,cnt
        if( present(mskimg) )then
            nsel = count(mskimg%rmat<0.5)
            allocate(pixels(nsel))
            cnt = 0
            do i=1,self%ldim(1)
                do j=1,self%ldim(2)
                    do k=1,self%ldim(3)
                        if( mskimg%rmat(i,j,k) > 0.5 )then
                            cnt = cnt + 1
                            pixels(cnt) = self%rmat(i,j,k)
                        endif
                    end do
                end do
            end do
        else
            nsel = product(self%ldim)
            allocate(pixels(nsel))
            cnt = 0
            do i=1,self%ldim(1)
                do j=1,self%ldim(2)
                    do k=1,self%ldim(3)
                        cnt = cnt + 1
                        pixels(cnt) = self%rmat(i,j,k)
                    end do
                end do
            end do
        endif
        
    end function packer

    ! CHECKUPS

    !>  \brief  Checks for existence
    pure function exists( self ) result( is )
        class(image), intent(in) :: self
        logical :: is
        is = self%existence
    end function exists

    !>  \brief  Checks whether the image is 2D
    pure logical function is_2d(self)
        class(image), intent(in)  ::  self
        is_2d = count(self%ldim .eq. 1) .eq. 1
    end function is_2d

    !>  \brief  Checks whether the image is 3D
    pure logical function is_3d(self)
        class(image), intent(in)  ::  self
        is_3d = .not. any(self%ldim .eq. 1)
    end function is_3d

    !>  \brief  checks for even dimensions
    pure function even_dims( self ) result( yep )
        class(image), intent(in) :: self
        logical :: yep, test(2)
        test = .false.
        test(1) = is_even(self%ldim(1))
        test(2) = is_even(self%ldim(2))
        yep = all(test)
    end function even_dims

    !>  \brief  checks for square dimensions
    pure function square_dims( self ) result( yep )
        class(image), intent(in) :: self
        logical :: yep
        yep = self%ldim(1) == self%ldim(2)
        if( self%ldim(3) == 1 .and. yep )then
        else
            yep = self%ldim(3) == self%ldim(1)
        endif
    end function square_dims

    !>  \brief  checks for same dimensions, overloaded as (.eqdims.)
    pure function same_dims_1( self1, self2 ) result( yep )
        class(image), intent(in) :: self1, self2
        logical :: yep, test(3)
        test = .false.
        test(1) = self1%ldim(1) == self2%ldim(1)
        test(2) = self1%ldim(2) == self2%ldim(2)
        test(3) = self1%ldim(3) == self2%ldim(3)
        yep = all(test)
    end function same_dims_1

    !>  \brief  checks for same dimensions
    pure function same_dims( self1, ldim ) result( yep )
        class(image), intent(in) :: self1
        integer,      intent(in) :: ldim(3)
        logical :: yep, test(3)
        test = .false.
        test(1) = self1%ldim(1) == ldim(1)
        test(2) = self1%ldim(2) == ldim(2)
        test(3) = self1%ldim(3) == ldim(3)
        yep = all(test)
    end function same_dims

    !>  \brief  checks for same sampling distance, overloaded as (.eqsmpd.)
    pure  function same_smpd( self1, self2 ) result( yep )
        class(image), intent(in) :: self1, self2
        logical :: yep
        if( abs(self1%smpd-self2%smpd) < 0.0001 )then
            yep = .true.
        else
            yep = .false.
        endif
    end function same_smpd

    !>  \brief  checks if image are of the same kind
    pure function same_kind( self1, self2 ) result( yep )
        class(image), intent(in) :: self1, self2
        logical :: yep
        yep = self1%imgkind .eq. self2%imgkind
    end function same_kind

    !>  \brief  checks if image is ft
    pure function is_ft( self ) result( is )
        class(image), intent(in) :: self
        logical :: is
        is = self%ft
    end function is_ft

    ! ARITHMETICS

    !>  \brief  polymorphic assignment (=)
    subroutine assign( selfout, selfin )
        class(image), intent(inout) :: selfout
        class(image), intent(in)    :: selfin
        call selfout%copy(selfin)
    end subroutine assign

    !>  \brief  real constant to image assignment(=) operation
    subroutine assign_r2img( self, realin )
        class(image), intent(inout) :: self
        real,         intent(in)    :: realin
        if( self%imgkind .eq. 'xfel' ) stop 'rmat not allocated for xfel-kind images; simple_image::assign_r2img'
        self%rmat = realin
        self%ft = .false.
    end subroutine assign_r2img

    !>  \brief  complex constant to image assignment(=) operation
    subroutine assign_c2img( self, compin )
        class(image), intent(inout) :: self
        complex,      intent(in)    :: compin
        self%cmat = compin
        self%ft = .true.
    end subroutine assign_c2img

    !>  \brief  is for image addition(+)
    function addition( self1, self2 ) result( self )
        class(image), intent(in) :: self1, self2
        type(image) :: self
        if( self1.eqdims.self2 )then
            call self%new(self1%ldim, self1%smpd)
            if( self1%ft .neqv. self2%ft )then
                stop 'cannot add images of different FT state; addition(+); simple_image'
            endif
            if( .not. self1%same_kind(self2) )then
                stop 'cannot add images of different kind em/xfel; addition(+); simple_image'
            endif
            if( self1%imgkind .eq. 'xfel' )then
                self%cmat = self1%cmat+self2%cmat
            else
                self%rmat = self1%rmat+self2%rmat
            endif
        else
            stop 'cannot add images of different dims; addition(+); simple_image'
        endif
        self%ft = self1%ft
    end function addition

    !>  \brief  is for l1 norm calculation
    function l1norm_1( self1, self2 ) result( self )
        class(image), intent(in) :: self1, self2
        type(image) :: self
        if( self1.eqdims.self2 )then
            call self%new(self1%ldim, self1%smpd)
            if( self1%ft .neqv. self2%ft )then
                stop 'cannot process images of different FT state; l1norm_1; simple_image'
            endif
            if( .not. self1%same_kind(self2) )then
                stop 'cannot process images of different kind em/xfel; l1norm_1; simple_image'
            endif
            if( self1%ft )then
                self%cmat = cabs(self1%cmat-self2%cmat)
            else
                self%rmat = abs(self1%rmat-self2%rmat)
            endif
        else
            stop 'cannot process images of different dims; l1norm_1; simple_image'
        endif
    end function l1norm_1

    !>  \brief  is for l1 norm calculation
    function l1norm_2( self1, self2 ) result( l1 )
        class(image), intent(in) :: self1, self2
        real :: l1
        if( self1%ft .or. self2%ft ) stop 'not impemented for FTs; l1norm_2; simple_image'
        if( self1.eqdims.self2 )then
            l1 = sum(abs(self1%rmat-self2%rmat))
        else
            stop 'cannot process images of different dims; l1norm; simple_image'
        endif
    end function l1norm_2

    !>  \brief  is for l1 norm weight generation
    function l1weights( self1, self2, nvar ) result( self )
        class(image),   intent(in) :: self1, self2
        real, optional, intent(in) :: nvar
        type(image) :: self
        integer :: i, j, k
        real :: sumw, nnvar
        if( self1%ft .or. self2%ft ) stop 'not impemented for FTs; l1weights; simple_image'
        nnvar = 1.
        if( present(nvar) ) nnvar = nvar
        self = self1.lone.self2
        sumw = 0.
        do i=1,self1%ldim(1)
            do j=1,self1%ldim(2)
                do k=1,self1%ldim(3)
                    self%rmat(i,j,k) = exp(-self%rmat(i,j,k)/nvar)
                    sumw = sumw+self%rmat(i,j,k)
                end do
            end do
        end do
        call self%div(sumw)
    end function l1weights

    !>  \brief  is for image summation, not overloaded
    subroutine add_1( self, self_to_add, w )
        class(image),   intent(inout) :: self
        class(image),   intent(in)    :: self_to_add
        real, optional, intent(in)    :: w
        real :: ww=1.0
        if( present(w) ) ww = w
        if( self%exists() )then
            if( self.eqdims.self_to_add )then
                if( self%ft .eqv. self_to_add%ft )then
                    if( self%ft )then
                        !$omp parallel workshare
                        self%cmat = self%cmat+ww*self_to_add%cmat
                        !$omp end parallel workshare
                    else
                        !$omp parallel workshare
                        self%rmat = self%rmat+ww*self_to_add%rmat
                        !$omp end parallel workshare
                    endif
                else
                    stop 'cannot sum images with different FT status; add_1; simple_image'
                endif
            else
                stop 'cannot sum images of different dims; add_1; simple_image'
            endif
        else
            self = self_to_add
        endif
    end subroutine add_1

    !>  \brief  is for componentwise summation, not overloaded
    subroutine add_2( self, logi, comp, phys_in, phys_out )
        class(image),      intent(inout) :: self
        integer,           intent(in)    :: logi(3)
        complex,           intent(in)    :: comp
        integer, optional, intent(in)   :: phys_in(3)
        integer, optional, intent(out)   :: phys_out(3)
        integer :: phys(3)
        complex :: comp_here
        if( .not. self%ft ) stop 'cannot add complex number to real image; add_2; simple_image'
        if( present(phys_in) )then
            phys = phys_in
        else
            phys = self%fit%comp_addr_phys(logi)
        endif
        if( logi(1) < 0 .and. self%imgkind .ne. 'xfel' )then
            comp_here = conjg(comp)
        else
            comp_here = comp
        endif
        self%cmat(phys(1),phys(2),phys(3)) = self%cmat(phys(1),phys(2),phys(3))+comp_here
        if( present(phys_out) ) phys_out = phys
    end subroutine add_2

    !>  \brief  is for componentwise summation, not overloaded
    subroutine add_3( self, rcomp, i, j, k )
        class(image), intent(inout) :: self
        real,         intent(in)    :: rcomp
        integer,      intent(in)    :: i, j, k
        if(  self%ft ) stop 'cannot add real number to transform; add_3; simple_image'
        self%rmat(i,j,k) = self%rmat(i,j,k)+rcomp
    end subroutine add_3

    !>  \brief  is for componentwise weighted summation with kernel division, not overloaded
    subroutine add_4( self, logi, comp, w, k )
        class(image), intent(inout) :: self
        integer,      intent(in)    :: logi(3)
        complex,      intent(in)    :: comp
        real,         intent(in)    :: w, k(:,:,:)
        integer :: phys(3)
        complex :: comp_here
        if( .not. self%ft ) stop 'cannot add complex number to real image; add_2; simple_image'
        phys = self%fit%comp_addr_phys(logi)
        if( logi(1) < 0 .and. self%imgkind .ne. 'xfel' )then
            comp_here = conjg(comp)
        else
            comp_here = comp
        endif
        if( abs(k(phys(1),phys(2),phys(3))) > 1e-6 )then
            self%cmat(phys(1),phys(2),phys(3)) = self%cmat(phys(1),phys(2),phys(3))+(comp_here/k(phys(1),phys(2),phys(3)))*w
        endif
    end subroutine add_4

    !>  \brief  is for adding a constant
    subroutine add_5( self, c )
        class(image), intent(inout) :: self
        real,         intent(in)    :: c
        if( self%ft )then
            self%cmat = self%cmat+cmplx(c,0.)
        else
            self%rmat = self%rmat+c
        endif
    end subroutine add_5

    !>  \brief  is for image subtraction(-)
    function subtraction( self_from, self_to ) result( self )
        class(image), intent(in) :: self_from, self_to
        type(image) :: self
        if( self_from.eqdims.self_to )then
            call self%new(self_from%ldim, self_from%smpd)
            if( self_from%ft .neqv. self_to%ft )then
                stop 'cannot subtract images of different FT state; subtraction(+); simple_image'
            endif
            if( .not. self_from%same_kind(self_to) )then
                stop 'cannot subtract images of different kind em/xfel; subtraction; simple_image'
            endif
            if( self_from%imgkind .eq. 'xfel' )then
                self%cmat = self_from%cmat-self_to%cmat
            else
                self%rmat = self_from%rmat-self_to%rmat
            endif
        else
            stop 'cannot subtract images of different dims; subtraction(-); simple_image'
        endif
    end function subtraction

    !>  \brief  is for image subtraction,  not overloaded
    subroutine subtr_1( self, self_to_subtr, w )
        class(image),   intent(inout) :: self
        class(image),   intent(in)    :: self_to_subtr
        real, optional, intent(in)    :: w
        real :: ww
        ww = 1.0 
        if( present(w) ) ww = w
        if( self.eqdims.self_to_subtr )then
            if( self%ft .eqv. self_to_subtr%ft )then
                if( self%ft )then
                    !$omp parallel workshare
                    self%cmat = self%cmat-ww*self_to_subtr%cmat
                    !$omp end parallel workshare
                else
                    !$omp parallel workshare
                    self%rmat = self%rmat-ww*self_to_subtr%rmat
                    !$omp end parallel workshare
                endif
            else
                stop 'cannot subtract images with different FT status; subtr_1; simple_image'
            endif
        else
            stop 'cannot subtract images of different dims; subtr_1; simple_image'
        endif
    end subroutine subtr_1

    !>  \brief  is for componentwise subtraction, not overloaded
    subroutine subtr_2( self, logi, comp, phys_in, phys_out )
        class(image),      intent(inout) :: self
        integer,           intent(in)    :: logi(3)
        complex,           intent(in)    :: comp
        integer, optional, intent(out)   :: phys_in(3)
        integer, optional, intent(out)   :: phys_out(3)
        integer :: phys(3)
        complex :: comp_here
        if( .not. self%ft ) stop 'cannot subtract complex number from real image; subtr_2; simple_image'
        if( present(phys_in) )then
            phys = phys_in
        else
            phys = self%fit%comp_addr_phys(logi)
        endif
        if( logi(1) < 0 .and. self%imgkind .ne. 'xfel' )then
            comp_here = conjg(comp)
        else
            comp_here = comp
        endif
        self%cmat(phys(1),phys(2),phys(3)) = self%cmat(phys(1),phys(2),phys(3))-comp_here
        if( present(phys_out) ) phys_out = phys
    end subroutine subtr_2

    !>  \brief  is for componentwise weighted subtraction with kernel division, not overloaded
    subroutine subtr_3( self, logi, comp, w, k )
        class(image), intent(inout) :: self
        integer,      intent(in)    :: logi(3)
        complex,      intent(in)    :: comp
        real,         intent(in)    :: w, k(:,:,:)
        integer :: phys(3)
        complex :: comp_here
        if( .not. self%ft ) stop 'cannot subtract complex number from real image; subtr_3; simple_image'
        phys = self%fit%comp_addr_phys(logi)
        if( logi(1) < 0 .and. self%imgkind .ne. 'xfel' )then
            comp_here = conjg(comp)
        else
            comp_here = comp
        endif
        if( abs(k(phys(1),phys(2),phys(3))) /= 0.)then
            self%cmat(phys(1),phys(2),phys(3)) = self%cmat(phys(1),phys(2),phys(3))-(comp_here/k(phys(1),phys(2),phys(3)))*w
        endif
    end subroutine subtr_3

    !>  \brief  is for subtracting a constant from a real image, not overloaded
    subroutine subtr_4( self, c )
        class(image), intent(inout) :: self
        real,         intent(in)    :: c
        if( self%imgkind .eq. 'xfel' ) stop 'rmat not allocated for xfel-kind images; simple_image::subtr_4'
        self%rmat = self%rmat-c
    end subroutine subtr_4

    !>  \brief  is for image multiplication(*)
    function multiplication( self1, self2 ) result( self )
        class(image), intent(in) :: self1, self2
        type(image) :: self
        if( self1.eqdims.self2 )then
            call self%new(self1%ldim, self1%smpd)
            if( self1%ft .and. self2%ft )then
                self%cmat = self1%cmat*self2%cmat
                self%ft = .true.
            else if( self1%ft .eqv. self2%ft )then
                if( self1%imgkind .eq. 'xfel' .or. self2%imgkind .eq. 'xfel' )&
                stop 'rmat not allocated for xfel-kind images; simple_image::multiplication'
                self%rmat = self1%rmat*self2%rmat
                self%ft = .false.
            else if(self1%ft)then
                if( self2%imgkind .eq. 'xfel' )&
                stop 'rmat not allocated for xfel-kind images; simple_image::multiplication'
                self%cmat = self1%cmat*self2%rmat
                self%ft = .true.
            else
                if( self1%imgkind .eq. 'xfel' )&
                stop 'rmat not allocated for xfel-kind images; simple_image::multiplication'
                self%cmat = self1%rmat*self2%cmat
                self%ft = .true.
            endif
        else
            stop 'cannot multiply images of different dims; multiplication(*); simple_image'
        endif
    end function multiplication

    !>  \brief  is for component-wise multiplication of an image with a real constant
    subroutine mul_1( self, logi, rc, phys_in, phys_out )
         class(image),      intent(inout) :: self
         integer,           intent(in)    :: logi(3)
         real,              intent(in)    :: rc
         integer, optional, intent(in)    :: phys_in(3)
         integer, optional, intent(out)   :: phys_out(3)
         integer :: phys(3)
         if( self%is_ft() )then
            if( present(phys_in) )then
                phys = phys_in
            else
                phys = self%fit%comp_addr_phys(logi)
            endif
            if( present(phys_out) ) phys_out = phys
            self%cmat(phys(1),phys(2),phys(3)) = self%cmat(phys(1),phys(2),phys(3))*rc
         else
            if( self%imgkind .eq. 'xfel' ) stop 'rmat not allocated for xfel-kind images; simple_image::mul_1'
            self%rmat(logi(1),logi(2),logi(3)) = self%rmat(logi(1),logi(2),logi(3))*rc
         endif
    end subroutine mul_1

    !>  \brief  is for  multiplication of an image with a real constant
    subroutine mul_2( self, rc )
        class(image), intent(inout) :: self
        real,         intent(in)    :: rc
        if( self%is_ft() )then
            !$omp parallel workshare
            self%cmat = self%cmat*rc
            !$omp end parallel workshare
        else
            if( self%imgkind .eq. 'xfel' ) stop 'rmat not allocated for xfel-kind images; simple_image::mul_2'
            !$omp parallel workshare
            self%rmat = self%rmat*rc
            !$omp end parallel workshare
        endif
    end subroutine mul_2

    !>  \brief  is for multiplication of images
    subroutine mul_3( self, self2mul )
        class(image), intent(inout) :: self
        class(image), intent(in)    :: self2mul
        if( self.eqdims.self2mul )then
            if( self%ft .and. self2mul%ft )then
                !$omp parallel workshare
                self%cmat = self%cmat*self2mul%cmat
                !$omp end parallel workshare
            else if( self%ft .eqv. self2mul%ft )then
                if( self%imgkind .eq. 'xfel' .or. self2mul%imgkind .eq. 'xfel' )&
                stop 'rmat not allocated for xfel-kind images; simple_image::mul_3'
                !$omp parallel workshare
                self%rmat = self%rmat*self2mul%rmat
                !$omp end parallel workshare
                self%ft = .false.
            else if(self%ft)then
                if( self2mul%imgkind .eq. 'xfel' )&
                stop 'rmat not allocated for xfel-kind images; simple_image::mul_3'
                !$omp parallel workshare
                self%cmat = self%cmat*self2mul%rmat
                !$omp end parallel workshare
            else
                if( self%imgkind .eq. 'xfel' )&
                stop 'rmat not allocated for xfel-kind images; simple_image::mul_3'
                !$omp parallel workshare
                self%cmat = self%rmat*self2mul%cmat
                !$omp end parallel workshare
                self%ft = .true.
            endif
        else
           stop 'cannot multiply images of different dims; mul_3; simple_image'
        endif
    end subroutine mul_3

    !>  \brief  is for low-pass limited multiplication of images
    subroutine mul_4( self, self2mul, lp )
        class(image), intent(inout) :: self
        class(image), intent(in)    :: self2mul
        real,         intent(in)    :: lp
        integer                     :: lims(3,2),sqlim,h,k,l,phys(3)
        if( .not. self%is_ft() )     stop 'low-pass limited multiplication requires self to be FT'
        if( .not. self2mul%is_ft() ) stop 'low-pass limited multiplication requires self2mul to be FT'
        if( self.eqdims.self2mul )then
            lims = self%fit%loop_lims(1,lp)
            sqlim = (maxval(lims(:,2)))**2
            !$omp parallel do collapse(3) default(shared) private(h,k,l,phys) schedule(auto)
            do h=lims(1,1),lims(1,2)
                do k=lims(2,1),lims(2,2)
                    do l=lims(3,1),lims(3,2)
                        if( h * h + k * k + l * l <= sqlim )then
                            phys = self%fit%comp_addr_phys([h,k,l])
                            self%cmat(phys(1),phys(2),phys(3)) = self%cmat(phys(1),phys(2),phys(3))*&
                            self2mul%cmat(phys(1),phys(2),phys(3))
                        endif
                    end do
                end do
            end do
            !$omp end parallel do
        else
           stop 'cannot multiply images of different dims; mul_3; simple_image'
        endif
    end subroutine mul_4

    !>  \brief  is for image division(/)
    function division( self1, self2 ) result( self )
        class(image), intent(in) :: self1, self2
        type(image) :: self
        integer :: lims(3,2), h, k, l, phys(3)
        if( self1%same_kind(self2) )then
            if( self1.eqdims.self2 )then
                call self%new(self1%ldim, self1%smpd)
                if( self1%ft .and. self2%ft )then
                    lims = self1%loop_lims(2)
                    !$omp parallel default(shared) private(h,k,l,phys)                    
                    !$omp do collapse(3) schedule(auto)
                    do h=lims(1,1),lims(1,2)
                        do k=lims(2,1),lims(2,2)
                            do l=lims(3,1),lims(3,2)
                                phys = self%fit%comp_addr_phys([h,k,l])
                                if( mycabs(self2%cmat(phys(1),phys(2),phys(3))) < 1e-6 )then
                                    self1%cmat(phys(1),phys(2),phys(3)) = cmplx(0.,0.)
                                else
                                    self1%cmat(phys(1),phys(2),phys(3)) =&
                                    self1%cmat(phys(1),phys(2),phys(3))/self2%cmat(phys(1),phys(2),phys(3))
                                endif
                            end do
                        end do
                    end do
                    !$omp end do nowait
                    !$omp workshare
                    self%cmat = self1%cmat/self2%cmat
                    !$omp end workshare
                    !$omp end parallel
                    self%ft = .true.
                else if( self1%ft .eqv. self2%ft )then
                    if( self1%imgkind .eq. 'xfel' .or. self2%imgkind .eq. 'xfel' )&
                    stop 'rmat not allocated for xfel-kind images; simple_image::division(/)'
                    !$omp parallel workshare
                    self%rmat = self1%rmat/self2%rmat
                    !$omp end parallel workshare
                    self%ft = .false.
                else if(self1%ft)then
                    if( self2%imgkind .eq. 'xfel' )&
                    stop 'rmat not allocated for xfel-kind images; simple_image::division(/)'
                    !$omp parallel workshare
                    self%cmat = self1%cmat/self2%rmat
                    !$omp end parallel workshare
                    self%ft = .true.
                else
                    if( self1%imgkind .eq. 'xfel' )&
                    stop 'rmat not allocated for xfel-kind images; simple_image::division(/)'
                    !$omp parallel workshare
                    self%cmat = self1%rmat/self2%cmat
                    !$omp end parallel workshare
                    self%ft = .true.
                endif
            else
                stop 'cannot divide images of different dims; division(/); simple_image'
            endif
        else
            stop 'cannot divide images of different kind em/xfel; division(/); simple_image'
        endif
    end function division

    !>  \brief  is for dividing image with real constant, not overloaded
    subroutine div_1( self, c )
        class(image), intent(inout) :: self
        real,         intent(in)    :: c
        if( abs(c) < 1e-6 )then
            stop 'division with zero; div; simple_image'
        else
            if( self%ft )then
                self%cmat = self%cmat/c
            else
                self%rmat = self%rmat/c
            endif
        endif
    end subroutine div_1

    !>  \brief  is for component-wise matrix division of a Fourier transform with a real matrix, k
    subroutine div_2( self, logi, k, square )
        class(image), intent(inout) :: self
        integer,      intent(in)    :: logi(3)
        real,         intent(in)    :: k(:,:,:)
        logical,      intent(in)    :: square
        integer :: phys(3)
        if( self%ft )then
            phys = self%fit%comp_addr_phys(logi)
            if( abs(k(phys(1),phys(2),phys(3))) > 1e-6 )then
                if( square )then
                    self%cmat(phys(1),phys(2),phys(3)) = self%cmat(phys(1),phys(2),phys(3))/(k(phys(1),phys(2),phys(3))**2.)
                else
                    self%cmat(phys(1),phys(2),phys(3)) = self%cmat(phys(1),phys(2),phys(3))/k(phys(1),phys(2),phys(3))
                endif
            else
                self%cmat(phys(1),phys(2),phys(3)) = cmplx(0.,0.) ! this is desirable for kernel division
            endif
        else
            stop 'Image need to be Fourier transformed; simple_image::div_2'
        endif
    end subroutine div_2

    !>  \brief  is for component-wise division of an image with a real number
    subroutine div_3( self, logi, k, phys_in )
        class(image),      intent(inout) :: self
        integer,           intent(in)    :: logi(3)
        real,              intent(in)    :: k
        integer, optional, intent(in)    :: phys_in(3)
        integer :: phys(3)
        if( self%is_ft() )then
            if( present(phys_in) )then
                phys = phys_in
            else
                phys = self%fit%comp_addr_phys(logi)
            endif
            if( abs(k) > 1e-6 )then
                self%cmat(phys(1),phys(2),phys(3)) = self%cmat(phys(1),phys(2),phys(3))/k
            else
                self%cmat(phys(1),phys(2),phys(3)) = cmplx(0.,0.) ! this is desirable for kernel division
            endif
        else
            if( abs(k) > 1e-6 )then
                self%rmat(logi(1),logi(2),logi(3)) = self%rmat(logi(1),logi(2),logi(3))/k
            endif
        endif
    end subroutine div_3

    !>  \brief  is for division of images
    subroutine div_4( self, self2div )
        class(image), intent(inout) :: self
        class(image), intent(in)    :: self2div
        if( self.eqdims.self2div )then
            if( self%ft .and. self2div%ft )then
                self%cmat = self%cmat/self2div%cmat
            else if( self%ft .eqv. self2div%ft )then
                if( self%imgkind .eq. 'xfel' .or. self2div%imgkind .eq. 'xfel' )&
                stop 'rmat not allocated for xfel-kind images; simple_image::div_4'
                self%rmat = self%rmat/self2div%rmat
                self%ft = .false.
            else if(self%ft)then
                if( self2div%imgkind .eq. 'xfel' )&
                stop 'rmat not allocated for xfel-kind images; simple_image::div_4'
                self%cmat = self%cmat/self2div%rmat
            else
                if( self%imgkind .eq. 'xfel' )&
                stop 'rmat not allocated for xfel-kind images; simple_image::div_4'
                self%cmat = self%rmat/self2div%cmat
                self%ft = .true.
            endif
        else
           stop 'cannot divide images of different dims; div_4; simple_image'
        endif
    end subroutine div_4
    
    !> \brief  for sampling density compensation & Wiener normalization
    subroutine ctf_dens_correct( self_sum, self_rho, self_out )
        class(image),           intent(inout) :: self_sum
        class(image),           intent(inout) :: self_rho
        class(image), optional, intent(inout) :: self_out
        integer :: h, k, l, lims(3,2), phys(3)
        ! set constants
        lims = self_sum%loop_lims(2)
        if( present(self_out) ) self_out = self_sum
        !$omp parallel do collapse(3) default(shared) private(h,k,l,phys) schedule(auto)
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                do l=lims(3,1),lims(3,2)
                    phys = self_sum%comp_addr_phys([h,k,l])
                    if( abs(real(self_rho%cmat(phys(1),phys(2),phys(3)))) > 1e-6 )then                 
                        if( present(self_out) )then
                            call self_out%div([h,k,l],&
                            real(self_rho%cmat(phys(1),phys(2),phys(3))),phys_in=phys)
                        else
                            call self_sum%div([h,k,l],&
                            real(self_rho%cmat(phys(1),phys(2),phys(3))),phys_in=phys) 
                        endif
                    else
                        if( present(self_out) )then
                            self_out%cmat(phys(1),phys(2),phys(3)) = cmplx(0.,0.)
                        else
                            self_sum%cmat(phys(1),phys(2),phys(3)) = cmplx(0.,0.)
                        endif
                    endif
                end do
            end do
        end do
        !$omp end parallel do
    end subroutine ctf_dens_correct

    !>  \brief  is for complex conjugation of a FT
    function conjugate( self ) result ( self_out )
        class(image), intent(in) :: self
        type(image) :: self_out
        if( self%is_ft() )then
            if( self%imgkind .eq. 'xfel' )then
                stop 'cannot conjugate xfel-kind images; simple_image::conjugate'
            endif
            call self_out%copy(self)
            self%cmat = conjg(self%cmat)
        else
            write(*,'(a)') "WARNING! Cannot conjugate real image"
        endif
    end function conjugate

    !>  \brief  is for calculating the square power of an image
    subroutine sqpow( self )
        class(image), intent(inout) :: self
        if( self%is_ft() )then
            self%cmat = (self%cmat*conjg(self%cmat))**2.
        else
            self%rmat = self%rmat*self%rmat
        endif
    end subroutine sqpow

    !>  \brief  is changing the sign of the imaginary part of the Fourier transform
    subroutine signswap_aimag( self )
        class(image), intent(inout) :: self
        if( self%ft )then
            self%cmat = cmplx(real(self%cmat),-aimag(self%cmat))
        else
            call self%fwd_ft
            self%cmat = cmplx(real(self%cmat),-aimag(self%cmat))
            call self%bwd_ft
        endif
    end subroutine signswap_aimag

    !>  \brief  is changing the sign of the real part of the Fourier transform
    subroutine signswap_real( self )
        class(image), intent(inout) :: self
        if( self%ft )then
            self%cmat = cmplx(-real(self%cmat),aimag(self%cmat))
        else
            call self%fwd_ft
            self%cmat = cmplx(-real(self%cmat),aimag(self%cmat))
            call self%bwd_ft
        endif
    end subroutine signswap_real

    ! BINARY IMAGE METHODS

    !>  \brief  counts the number of foreground (white) pixels in a binary image
    function nforeground( self ) result( n )
        class(image), intent(in) :: self
        integer :: n, i, j, k
        if( self%imgkind .eq. 'xfel' )then
            stop 'xfel-kind images cannot be binary; simple_image::nforeground'
        endif
        n = count(self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)) > 0.5)
    end function nforeground

    !>  \brief  counts the number of background (black) pixels in a binary image
    function nbackground( self ) result( n )
        class(image), intent(in) :: self
        integer :: n
        if( self%imgkind .eq. 'xfel' )then
            stop 'xfel-kind images cannot be binary; simple_image::nbackground'
        endif
        n = product(self%ldim)-self%nforeground()
    end function nbackground

    !>  \brief  is for binarizing an image with given threshold value
    !!          binary normalization (norm_bin) assumed
    subroutine bin_1( self, thres )
        class(image), intent(inout) :: self
        real,         intent(in)    :: thres
        if( self%ft ) stop 'only for real images; bin_1; simple image'
        where( self%rmat >= thres )
            self%rmat = 1.
        elsewhere
            self%rmat = 0.
        end where
    end subroutine bin_1

    !>  \brief  is for binarizing an image using nr of pixels/voxels threshold
    subroutine bin_2( self, npix )
        class(image), intent(inout) :: self
        integer, intent(in)         :: npix
        real, allocatable           :: forsort(:)
        real                        :: thres
        integer                     :: npixtot
        if( self%ft ) stop 'only for real images; bin_2; simple image'
        npixtot = product(self%ldim)
        ! forsort = self%packer() ! Intel hickup
        forsort = pack( self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)), .true.)
        call hpsort( npixtot, forsort)
        thres = forsort(npixtot-npix-1) ! everyting above this value 1 else 0
        call self%bin( thres )
        deallocate( forsort )
    end subroutine bin_2

    !>  \brief  is for binarizing an image using k-means to identify the background/
    !!          foreground distributions for the image or within a spherical mask
    subroutine bin_3( self, which, mskrad )
        class(image),     intent(inout) :: self
        character(len=*), intent(in)    :: which
        real, optional,   intent(in)    :: mskrad
        real, allocatable :: forsort(:)
        type(image)       :: maskimg
        real              :: cen1, cen2, sum1, sum2, val1, val2, sumvals
        integer           :: cnt1, cnt2, i, l, npix, halfnpix
        if( self%ft ) stop 'only for real images; bin_3; simple image'
        ! sort the pixels to initialize k-means
        select case(which)
            case('msk')
                if(.not.present(mskrad))stop 'missing radius; bin_3; simple image'
                call maskimg%new(self%ldim, self%smpd)
                maskimg%rmat = 1.
                call maskimg%mask(mskrad, 'hard')
                forsort = pack(self%rmat(:self%ldim(1), :self%ldim(2), :self%ldim(3)),&
                    &maskimg%rmat(:self%ldim(1), :self%ldim(2), :self%ldim(3)) > 0.5 )
            case('full', 'nomsk')
                forsort = pack(self%rmat(:self%ldim(1), :self%ldim(2), :self%ldim(3)), .true.)
                ! forsort = self%packer() ! Intel hickup
            case DEFAULT
                stop 'Unknown argument which ; bin_3; simple image'
        end select
        npix = size(forsort)
        call hpsort(npix, forsort)
        halfnpix = nint(real(npix)/2.)
        cen1     = sum(forsort(1:halfnpix)) / real(halfnpix)
        cen2     = sum(forsort(halfnpix+1:npix)) / real(npix-halfnpix)
        sumvals  = sum(forsort)
        ! do 100 iterations of k-means to identify background/forground distributions
        do l=1,100
            sum1 = 0.
            cnt1 = 0
            do i=1,npix
                if( (cen1-forsort(i))**2. < (cen2-forsort(i))**2. )then
                    cnt1 = cnt1 + 1
                    sum1 = sum1 + forsort(i)
                endif
            end do
            cnt2 = npix - cnt1
            sum2 = sumvals - sum1
            cen1 = sum1 / real(cnt1)
            cen2 = sum2 / real(cnt2)
        end do
        ! assign values to the centers
        if( cen1 > cen2 )then
            val1 = 1.
            val2 = 0.
        else
            val1 = 0.
            val2 = 1.
        endif
        ! last pass to binarize the image
        where( (cen1-self%rmat)**2. < (cen2-self%rmat)**2. )
            self%rmat = val1
        elsewhere
            self%rmat = val2
        end where
        if(which .eq. 'msk')call self%mul(maskimg)
        deallocate(forsort)
        call maskimg%kill
    end subroutine bin_3

    !>  \brief  is for creating a binary filament
    subroutine bin_filament( self, width_A )
        class(image), intent(inout) :: self
        real, intent(in)            :: width_A
        real    :: halfwidth_pix, cen_xdim
        integer :: xstart, xstop
        if( self%ldim(3) > 1 ) stop 'only for 2D images; simple_imge :: bin_filament '
        halfwidth_pix = (width_A/self%smpd)/2.
        cen_xdim      = real(self%ldim(1))/2.
        xstart        = floor(cen_xdim-halfwidth_pix)
        xstop         = ceiling(cen_xdim+halfwidth_pix)
        if( self%ft ) self%ft = .false.
        self%rmat = 0.
        self%rmat(xstart:xstop,:,1) = 1.
    end subroutine bin_filament

    !>  \brief  is for determining the center of mass of binarised image
    !!          only use this function for integer pixels shifting
    function masscen( self ) result( xyz )
        class(image), intent(inout) :: self
        real    :: xyz(3), spix, pix, ci, cj, ck
        integer :: i, j, k
        if( self%imgkind .eq. 'xfel' ) stop 'masscen not implemented for xfel patterns; masscen; simple_image'
        if( self%ft )                  stop 'masscen not implemented for FTs; masscen; simple_image'
        spix = 0.
        xyz  = 0.
        ci   = -real(self%ldim(1)-1)/2.
        do i=1,self%ldim(1)
            cj = -real(self%ldim(2)-1)/2.
            do j=1,self%ldim(2)
                ck = -real(self%ldim(3)-1)/2.
                do k=1,self%ldim(3)
                    pix  = self%get([i,j,k])
                    xyz  = xyz + pix * [ci, cj, ck]
                    spix = spix+pix
                    ck   = ck+1.
                end do
                cj = cj + 1.
            end do
            ci = ci + 1.
        end do
        xyz = xyz / spix
        if(self%is_2d()) xyz(3) = 0.
    end function masscen

    !>  \brief  is for centering an image based on center of mass
    function center( self, lp, neg, msk, thres, doshift ) result( xyz )
        class(image),     intent(inout) :: self
        real,             intent(in)    :: lp
        character(len=*), intent(in)    :: neg
        real,    intent(in), optional   :: msk, thres
        logical, intent(in), optional   :: doshift
        type(image) :: tmp
        real        :: xyz(3), rmsk
        integer     :: dims(3)
        logical     :: l_doshift
        if( self%imgkind .eq. 'xfel' ) stop 'centering not implemented for xfel patterns; center; simple_image'
        l_doshift = .true.
        if( present(doshift) )l_doshift = doshift
        tmp = self
        dims = tmp%get_ldim()
        if( present(msk) )then
            rmsk = msk
        else
            rmsk = real( dims(1) )/2. - 5. ! 5 pixels outer width
        endif
        if(neg .eq. 'yes') call tmp%neg
        call tmp%bp(0., lp)
        if( present(thres) )then
            call tmp%mask(rmsk, 'soft')
            call tmp%norm_bin
            call tmp%bin(thres)
        else
            !call tmp%mask(rmsk, 'soft')    ! the old fashioned way
            !call tmp%bin('nomsk')          ! the old fashioned way
            call tmp%bin('msk', rmsk)
        endif
        xyz = tmp%masscen()
        if( l_doshift )then
            if( self%is_2d() )then
                call self%shift(xyz(1),xyz(2))
            else
                call self%shift(xyz(1),xyz(2),xyz(3))
            endif
        endif
    end function center

    !>  \brief  inverts a binary image
    subroutine bin_inv( self )
        class(image), intent(inout) :: self
        if( self%imgkind .eq. 'xfel' )then
            stop 'xfel-kind images cannot be binary; simple_image::bin_inv'
        endif
        self%rmat = -1.*(self%rmat-1.)
    end subroutine bin_inv

    !>  \brief  adds one layer of pixels bordering the background in a binary image
    subroutine grow_bin( self )
        class(image), intent(inout) :: self
        integer                     :: i,j,k,alloc_stat
        integer                     :: il,ir,jl,jr,kl,kr
        logical, allocatable        :: add_pixels(:,:,:)
        if( self%ft ) stop 'only for real images; grow_bin; simple image'
        allocate( add_pixels(self%ldim(1),self%ldim(2),self%ldim(3)), stat=alloc_stat )
        call alloc_err('grow_bin; simple_image', alloc_stat)
        ! Figure out which pixels to add
        add_pixels = .false.
        if( self%ldim(3) == 1 )then
            do i=1,self%ldim(1)
                il = max(1,i-1)
                ir = min(self%ldim(1),i+1)
                do j=1,self%ldim(2)
                    if (self%rmat(i,j,1)==0.) then
                        jl = max(1,j-1)
                        jr = min(self%ldim(2),j+1)
                        if( any(self%rmat(il:ir,jl:jr,1)==1.) )add_pixels(i,j,1) = .true.
                    end if
                end do
            end do
            ! add
            forall( i=1:self%ldim(1), j=1:self%ldim(2), add_pixels(i,j,1) )self%rmat(i,j,1) = 1.
        else
            do i=1,self%ldim(1)
                il = max(1,i-1)
                ir = min(self%ldim(1),i+1)
                do j=1,self%ldim(2)
                    jl = max(1,j-1)
                    jr = min(self%ldim(2),j+1)
                    do k=1,self%ldim(3)
                        if (self%rmat(i,j,k)==0.) then
                            kl = max(1,k-1)
                            kr = min(self%ldim(3),k+1)
                            if( any(self%rmat(il:ir,jl:jr,kl:kr)==1.) )add_pixels(i,j,k) = .true.
                        end if
                    end do
                end do
            end do
            ! add
            forall( i=1:self%ldim(1), j=1:self%ldim(2), k=1:self%ldim(3), add_pixels(i,j,k) ) &
                & self%rmat(i,j,k) = 1.
        endif
        deallocate( add_pixels )
    end subroutine grow_bin

    !>  \brief  adds one layer of pixels bordering the background in a binary image
    ! DEV ONLY
    subroutine grow_bin2( self )
        class(image), intent(inout) :: self
        integer                     :: alloc_stat, x, y, z
        logical, allocatable        :: lmat(:,:,:), imat(:,:,:)
        if( self%ft ) stop 'only for real images; grow_bin; simple image'
        x = self%ldim(1)
        y = self%ldim(2)
        z = self%ldim(3)
        allocate(imat(x, y, z), stat=alloc_stat)
        call alloc_err('grow_bin; simple_image', alloc_stat)
        lmat = (self%rmat(:x, :y, :z) > 0.5)
        imat = lmat
        if(self%is_2d())then
            imat( :x-1, :y,   :z) = imat( :x-1, :y,   :z) .or. lmat(2:x,   :y,   :z)
            imat(2:x,   :y,   :z) = imat(2:x,   :y,   :z) .or. lmat( :x-1, :y,   :z)
            imat( :x,   :y-1, :z) = imat( :,    :y-1, :z) .or. lmat( :x,  2:y,   :z)
            imat( :x,  2:y,   :z) = imat( :,   2:y,   :z) .or. lmat( :x,   :y-1, :z)
            ! ...TBC
        else


        endif
        where(imat) self%rmat = 1.
        deallocate(imat,lmat)
    end subroutine grow_bin2

    !>  \brief  applies cosine edge to a binary image
    subroutine cos_edge( self, falloff )
        use simple_math, only: cosedge
        class(image), intent(inout) :: self
        integer, intent(in)         :: falloff
        real, allocatable           :: rmat(:,:,:)
        real                        :: rfalloff, scalefactor
        integer                     :: i, j, k, is, js, ks, ie, je, ke
        integer                     :: il, ir, jl, jr, kl, kr, falloff_sq
        if( self%imgkind .eq. 'xfel' ) stop 'xfel-kind images cannot be low-pass filtered in real space; simple_image::cos_edge'
        if( falloff<=0 ) stop 'stictly positive values for edge fall-off allowed; simple_image::cos_edge'
        if( self%ft )    stop 'not intended for FTs; simple_image :: cos_edge'
        self%rmat   = self%rmat/maxval(self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)))
        rfalloff    = real( falloff )
        falloff_sq  = falloff**2
        scalefactor = PI / (2.*rfalloff)
        allocate( rmat(self%ldim(1),self%ldim(2),self%ldim(3)) )
        rmat = self%rmat(1:self%ldim(1),:,:)
        do i=1,self%ldim(1)
            is = max(1,i-1)                  ! left neighbour
            ie = min(i+1,self%ldim(1))       ! right neighbour
            il = max(1,i-falloff)            ! left bounding box limit
            ir = min(i+falloff,self%ldim(1)) ! right bounding box limit
            if(.not. any(rmat(i,:,:)==1.))cycle
            do j=1,self%ldim(2)
                js = max(1,j-1)
                je = min(j+1,self%ldim(2))
                jl = max(1,j-falloff)
                jr = min(j+falloff,self%ldim(2))
                if( self%ldim(3)==1 )then
                    ! 2d
                    if( rmat(i,j,1)/=1. )cycle
                    ! within mask region
                    ! update if has a masked neighbour 
                    if( any( rmat(is:ie,js:je,1) < 1.) )call update_mask_2d
                else
                    ! 3d
                    if(.not. any(rmat(i,j,:)==1.))cycle
                    do k=1,self%ldim(3)
                        if( rmat(i,j,k)/=1. )cycle
                        ! within mask region
                        ks = max(1,k-1)
                        ke = min(k+1,self%ldim(3))
                        if( any( rmat(is:ie,js:je,ks:ke) < 1.) )then
                            ! update since has a masked neighbour                            
                            kl = max(1,k-falloff)
                            kr = min(k+falloff,self%ldim(3))
                            call update_mask_3d
                        endif
                    end do
                endif
            end do
        end do
        self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)) = rmat
        deallocate(rmat)
        contains

            ! updates neighbours with cosine weight
            subroutine update_mask_2d
                integer :: ii, jj, di_sq, dist_sq
                do ii=il,ir
                    di_sq = (ii-i)**2                 ! 1D squared distance in x dim
                    do jj=jl,jr
                        dist_sq = di_sq + (jj-j)**2   ! 2D squared distance in x & y dim
                        if(dist_sq > falloff_sq)cycle
                        ! masked neighbour
                        if( rmat(ii,jj,1)<1. )&
                        &rmat(ii,jj,1) = max(local_versine(real(dist_sq)), rmat(ii,jj,1))
                    enddo
                enddo
            end subroutine update_mask_2d

            ! updates neighbours with cosine weight
            subroutine update_mask_3d
                integer :: ii, jj, kk, di_sq, dij_sq, dist_sq
                do ii=il,ir
                    di_sq = (ii-i)**2
                    do jj=jl,jr
                        dij_sq = di_sq+(jj-j)**2
                        do kk=kl,kr
                            dist_sq = dij_sq + (kk-k)**2
                            if(dist_sq > falloff_sq)cycle
                            if( rmat(ii,jj,kk)<1. )&
                            &rmat(ii,jj,kk) = max(local_versine(real(dist_sq)), rmat(ii,jj,kk))
                        enddo
                    enddo
                enddo
            end subroutine update_mask_3d

            ! Local elemental cosine edge function
            ! this is not a replacement of math%cosedge, which is not applicable here
            elemental real function local_versine( r_sq )result( c )
                real, intent(in) :: r_sq
                c = 1. - cos(scalefactor * (sqrt(r_sq)-rfalloff))
            end function local_versine

    end subroutine cos_edge

    !>  \brief  increments the logi pixel value with incr
    subroutine increment( self, logi, incr )
        class(image), intent(inout) :: self
        integer, intent(in)         :: logi(3)
        real, intent(in)            :: incr
        if( self%imgkind .eq. 'xfel' )then
            stop 'rmat not allocated for xfel-kind images; simple_image::increment'
        endif
        self%rmat(logi(1),logi(2),logi(3)) = self%rmat(logi(1),logi(2),logi(3))+incr
    end subroutine increment

    ! FILTERS

    !>  \brief  calculates the autocorrelation function of an image
    subroutine acf( self )
        class(image), intent(inout) :: self
        if( .not. self%is_ft() )then
            call self%fwd_ft
        endif
        self%cmat = self%cmat*conjg(self%cmat)
        call self%bwd_ft
    end subroutine acf
    
    !>  \brief  calculates thecross-correlation function between two images
    function ccf( self1, self2 ) result( cc )
        class(image), intent(inout) :: self1, self2
        type(image) :: cc
        if( .not. self1%is_ft() )then
            call self1%fwd_ft
        endif
        if( .not. self2%is_ft() )then
            call self2%fwd_ft
        endif
        cc      = self1
        cc%cmat = cc%cmat*conjg(self2%cmat)
        call cc%bwd_ft
    end function ccf

    !>  \brief generates the bfactor from the Guinier plot of the unfiltered volume
    function guinier_bfac( self, hp, lp ) result( bfac )
        class(image), intent(inout) :: self
        real, intent(in)            :: hp, lp
        real, allocatable           :: plot(:,:)
        integer                     :: fromk, tok, nk
        real                        :: slope, intercept, corr, bfac
        plot  = self%guinier()
        fromk = self%get_find(hp)
        tok   = self%get_find(lp)
        nk    = tok-fromk+1
        call fit_straight_line(nk, plot(fromk:tok,:), slope, intercept, corr)
        bfac=4.*slope
        deallocate(plot)
    end function guinier_bfac

    !>  \brief generates the Guinier plot for a volume, which should be unfiltered
    function guinier( self ) result( plot )
        class(image), intent(inout) :: self
        real, allocatable :: spec(:), plot(:,:)
        integer           :: lfny, k, alloc_stat
        if( .not. self%is_3d() ) stop 'Only for 3D images; guinier; simple_image'
        spec = self%spectrum('absreal')
        lfny = self%get_lfny(1)
        allocate( plot(lfny,2), stat=alloc_stat )
        call alloc_err("In: guinier; simple_image", alloc_stat)
        do k=1,lfny
            plot(k,1) = 1./(self%get_lp(k)**2.)
            plot(k,2) = log(spec(k))
            write(*,'(A,1X,F8.4,1X,A,1X,F7.3)') '>>> RECIPROCAL SQUARE RES:', plot(k,1), '>>> LOG(ABS(REAL(F))):', plot(k,2)
        end do
        deallocate(spec)
    end function guinier

    !>  \brief generates the rotationally averaged spectrum of an image
    function spectrum( self, which, norm ) result( spec )
        class(image),      intent(inout) :: self
        character(len=*),  intent(in)    :: which
        logical, optional, intent(in)    :: norm
        real, allocatable :: spec(:)
        real, allocatable :: counts(:)
        integer :: lfny, h, k, l
        integer :: alloc_stat, sh, lims(3,2), phys(3)
        logical :: didft, nnorm
        nnorm = .true.
        if( present(norm) ) nnorm = norm
        if( self%imgkind .eq. 'xfel' )then
            if( which .eq. 'real' .or. which .eq. 'count' )then
                ! acceptable for xfel images
            else
                stop 'this which parameter is not compatible with the xfel image kind; simple_image :: spectrum'
            endif
        endif
        didft = .false.
        if( which .ne. 'count' )then
            if( .not. self%ft )then
                call self%fwd_ft
                didft = .true.
            endif
        endif
        lfny = self%get_lfny(1)
        allocate( spec(lfny), counts(lfny), stat=alloc_stat )
        call alloc_err('spectrum; simple_image', alloc_stat)
        spec   = 0.
        counts = 0.
        lims   = self%fit%loop_lims(2)
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                do l=lims(3,1),lims(3,2)
                    ! compute physical address
                    phys = self%fit%comp_addr_phys([h,k,l])
                    ! find shell
                    sh = nint(hyp(real(h),real(k),real(l)))
                    if( sh == 0 .or. sh > lfny ) cycle
                    select case(which)
                        case('real')
                            spec(sh) = spec(sh) + real(self%cmat(phys(1),phys(2),phys(3)))
                        case('power')
                            spec(sh) = spec(sh) + real(self%cmat(phys(1),phys(2),phys(3))&
                                                  *conjg(self%cmat(phys(1),phys(2),phys(3))))
                        case('absreal')
                            spec(sh) = spec(sh) + abs(real(self%cmat(phys(1),phys(2),phys(3))))
                        case('absimag')
                            spec(sh) = spec(sh) + abs(aimag(self%cmat(phys(1),phys(2),phys(3))))
                        case('abs')
                            spec(sh) = spec(sh) + cabs(self%cmat(phys(1),phys(2),phys(3)))
                        case('phase')
                            spec(sh) = spec(sh) + phase_angle(self%cmat(phys(1),phys(2),phys(3)))
                        case('count')
                            spec(sh) = spec(sh) + 1.
                        case DEFAULT
                            write(*,*) 'Spectrum kind: ', trim(which)
                            stop 'Unsupported spectrum kind; simple_image; spectrum'
                    end select
                    counts(sh) = counts(sh)+1.
                end do
            end do
        end do
        if( which .ne. 'count' .and. nnorm )then
            where(counts > 0.)
                spec = spec/counts
            end where
        endif
        if( didft ) call self%bwd_ft
    end function spectrum
    
    !>  \brief for normalising each shell to uniform (=1) power
    subroutine shellnorm( self )
        class(image), intent(inout) :: self
        real, allocatable           :: expec_pow(:)
        logical                     :: didbwdft
        integer                     :: sh, h, k, l, phys(3), lfny, lims(3,2)
        real                        :: icomp, avg
        ! subtract average in real space
        didbwdft = .false.
        if( self%ft )then
            call self%bwd_ft
            didbwdft = .true.
        endif
        avg = sum(self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)))/real(product(self%ldim))
        self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)) =&
        self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3))-avg
        call self%fwd_ft
        lfny  = self%get_lfny(1)
        lims  = self%fit%loop_lims(2)
        ! calculate the expectation value of the signal power in each shell
        expec_pow = self%spectrum('power')
        ! normalise
        !$omp parallel do collapse(3) default(shared) private(h,k,l,sh,phys) schedule(auto)
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                do l=lims(3,1),lims(3,2)
                    sh = nint(hyp(real(h),real(k),real(l)))
                    phys = self%fit%comp_addr_phys([h,k,l])
                    if( sh > lfny )then
                        self%cmat(phys(1),phys(2),phys(3)) = cmplx(0.,0.)
                    else
                        if( sh == 0 ) cycle
                        if( expec_pow(sh) > 0. )then
                            self%cmat(phys(1),phys(2),phys(3)) = self%cmat(phys(1),phys(2),phys(3))/sqrt(expec_pow(sh))
                        endif
                    endif
                end do
            end do
        end do
        !$omp end parallel do
        ! take care of the central spot
        phys  = self%fit%comp_addr_phys([0,0,0])
        icomp = aimag(self%cmat(phys(1),phys(2),phys(3)))
        self%cmat(phys(1),phys(2),phys(3)) = cmplx(1.,icomp)
        if( didbwdft )then
            ! return in Fourier space
        else
            ! return in real space
            call self%bwd_ft
        endif
    end subroutine shellnorm

    !>  \brief  is for applying bfactor to an image
    subroutine apply_bfac( self, b )
        !$ use omp_lib
        !$ use omp_lib_kinds
        class(image), intent(inout) :: self
        real, intent(in)            :: b
        integer                     :: i,j,k,phys(3),lims(3,2)
        real                        :: wght, res
        logical                     :: didft
        didft = .false.
        if( .not. self%ft )then
            call self%fwd_ft
            didft = .true.
        endif
        lims = self%fit%loop_lims(2)
        !$omp parallel do collapse(3) default(shared) private(k,j,i,res,phys,wght) schedule(auto)
        do k=lims(3,1),lims(3,2)
            do j=lims(2,1),lims(2,2)
                do i=lims(1,1),lims(1,2)
                    res = sqrt(real(k*k+j*j+i*i))/(self%ldim(1)*self%smpd) ! assuming square dimensions
                    phys = self%fit%comp_addr_phys([i,j,k])
                    wght = max(0.,exp(-(b/4.)*res*res))
                    self%cmat(phys(1),phys(2),phys(3)) = self%cmat(phys(1),phys(2),phys(3))*wght
                end do
            end do
        end do
        !$omp end parallel do
        if( b < 0. ) call self%bp(0., 2.*self%smpd, 4.)
        if( didft ) call self%bwd_ft
    end subroutine apply_bfac

    !>  \brief  is for band-pass filtering an image
    subroutine bp( self, hplim, lplim, width )
        class(image), intent(inout) :: self
        real, intent(in)            :: hplim, lplim
        real, intent(in), optional  :: width
        integer                     :: h, k, l, lims(3,2)
        logical                     :: didft
        real                        :: freq, hplim_freq, lplim_freq, wwidth, w
        wwidth = 5.
        if( present(width) ) wwidth = width
        didft = .false.
        if( .not. self%ft )then
            call self%fwd_ft
            didft = .true.
        endif
        lims = self%fit%loop_lims(2)
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                do l=lims(3,1),lims(3,2)
                    freq = hyp(real(h),real(k),real(l))
                    if(hplim .ne. 0.)then ! Apply high-pass
                        hplim_freq = self%fit%get_find(1,hplim) ! assuming square 4 now
                        if(freq .lt. hplim_freq) then
                            call self%mul([h,k,l], 0.)
                        else if(freq .le. hplim_freq+wwidth) then
                            w = (1.-cos(((freq-hplim_freq)/wwidth)*pi))/2.
                            call self%mul([h,k,l], w)
                        endif
                    endif
                    if(lplim .ne. 0.)then ! Apply low-pass
                        lplim_freq = self%fit%get_find(1,lplim) ! assuming square 4 now
                        if(freq .gt. lplim_freq)then
                            call self%mul([h,k,l], 0.)
                        else if(freq .ge. lplim_freq-wwidth)then
                            w = (cos(((freq-(lplim_freq-wwidth))/wwidth)*pi)+1.)/2.
                            call self%mul([h,k,l], w)
                        endif
                    endif
                end do
            end do
        end do
        if( didft ) call self%bwd_ft
    end subroutine bp

    !>  \brief  is for generating low-pass filter weights
    function gen_lpfilt( self, lplim, width ) result( filter )
        class(image),   intent(inout) :: self
        real,           intent(in)    :: lplim
        real, optional, intent(in)    :: width
        integer                       :: nyq, alloc_stat, k
        real                          :: wwidth, lplim_freq, freq
        real, allocatable             :: filter(:)
        wwidth = 5.
        if( present(width) ) wwidth = width
        nyq = self%get_nyq()
        allocate( filter(nyq), stat=alloc_stat )
        lplim_freq = self%fit%get_find(1,lplim)
        filter = 1.
        do k=1,nyq
            freq = real(k)
            if(freq .gt. lplim_freq)then
                filter(k) = 0.
            else if(freq .ge. lplim_freq-wwidth)then
                filter(k) = (cos(((freq-(lplim_freq-wwidth))/wwidth)*pi)+1.)/2.
            endif
        end do
    end function gen_lpfilt

    !>  \brief  is for application of an arbitrary 1D filter function
    subroutine apply_filter_1( self, filter )
        class(image), intent(inout) :: self
        real,         intent(in)    :: filter(:)
        integer                     :: nyq, sh, h, k, l, lims(3,2)
        logical                     :: didft
        real                        :: fwght, wzero
        nyq = size(filter)
        didft = .false.
        if( .not. self%is_ft() )then
            call self%fwd_ft
            didft = .true.
        endif
        wzero = maxval(filter)
        lims = self%fit%loop_lims(2)
        !$omp parallel do collapse(3) default(shared) private(h,k,l,sh,fwght) schedule(auto)
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                do l=lims(3,1),lims(3,2)
                    ! find shell
                    sh = nint(hyp(real(h),real(k),real(l)))
                    ! set filter weight
                    if( sh > nyq )then
                        fwght = 0.
                    else if( sh == 0 )then
                        fwght = wzero
                    else
                        fwght = filter(sh)
                    endif
                    ! multiply with the weight
                    call self%mul([h,k,l], fwght)
                end do
            end do
        end do
        !$omp end parallel do
        if( didft ) call self%bwd_ft
    end subroutine apply_filter_1

    !>  \brief  is for application of an arbitrary 2D filter function
    subroutine apply_filter_2( self, filter )
        class(image), intent(inout) :: self, filter
        real    :: fwght
        integer :: phys(3), lims(3,2), h, k, l
        complex :: comp
        if( self.eqdims.filter )then
            if( filter%ft )then
                if( .not. self%ft )then
                    stop 'assumed that image 2 be filtered is in the Fourier domain; apply_filter_2; simple_image'
                endif
                lims = self%fit%loop_lims(2)
                !$omp parallel do collapse(3) default(shared) private(h,k,l,comp,fwght,phys) schedule(auto)
                do h=lims(1,1),lims(1,2)
                    do k=lims(2,1),lims(2,2)
                        do l=lims(3,1),lims(3,2)
                            phys  = self%comp_addr_phys([h,k,l])
                            comp  = filter%get_fcomp([h,k,l],phys)
                            fwght = real(comp)
                            call self%mul([h,k,l],fwght,phys_in=phys)
                        end do
                    end do
                end do
                !$omp end parallel do
            else
                stop 'assumed that the inputted filter is in the Fourier domain; apply_filter_2; simple_image'
            endif
        else
            stop 'equal dims assumed; apply_filter_2; simple_image'
        endif
    end subroutine apply_filter_2

    !>  \brief  is for randomzing the phases of the FT of an image from lp and out
    subroutine phase_rand( self, lp )
        use simple_sll,      only: sll
        use simple_ran_tabu, only: ran_tabu
        class(image), intent(inout) :: self
        real, intent(in)            :: lp
        integer                     :: h,k,l,phys(3),lims(3,2)
        logical                     :: didft
        real                        :: freq,lp_freq,sgn1,sgn2,sgn3
        real, parameter             :: errfrac=0.5
        if( self%imgkind .eq. 'xfel' )then
            stop 'phase_rand not applicable to xfel-kind images; simple_image::phase_rand'
        endif
        didft = .false.
        if( .not. self%ft )then
            call self%fwd_ft
            didft = .true.
        endif
        lims = self%fit%loop_lims(2)
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                do l=lims(3,1),lims(3,2)
                    freq = hyp(real(h),real(k),real(l))
                    lp_freq = self%fit%get_find(1,lp) ! assuming square 4 now
                    if(freq .gt. lp_freq)then
                        phys = self%fit%comp_addr_phys([h,k,l])
                        sgn1 = 1.
                        sgn2 = 1.
                        sgn3 = 1.
                        if( ran3() > 0.5 ) sgn1 = -1.
                        if( ran3() > 0.5 ) sgn2 = -1.
                        if( ran3() > 0.5 ) sgn3 = -1.
                        self%cmat(phys(1),phys(2),phys(3)) = self%cmat(phys(1),phys(2),phys(3))*&
                        self%oshift([h,k,l],[sgn1*ran3()*errfrac*self%ldim(1),&
                        sgn2*ran3()*errfrac*self%ldim(2),sgn3*ran3()*errfrac*self%ldim(3)])
                    endif
                end do
            end do
        end do
        if( didft ) call self%bwd_ft
    end subroutine phase_rand

    !>  \brief is a constructor that constructs an antialiasing Hann window
    function hannw( self, oshoot_in ) result( w )
        use simple_winfuns, only: winfuns
        class(image), intent(inout) :: self
        real, intent(in), optional  :: oshoot_in
        integer                     :: alloc_stat, lims(3,2), k, kmax, maxl
        type(winfuns)               :: wfuns
        character(len=STDLEN)       :: wstr
        real, allocatable           :: w(:)
        real                        :: oshoot
        oshoot = 0.3
        if( present(oshoot_in) ) oshoot = oshoot_in
        lims = self%loop_lims(2)
        maxl = maxval(lims)
        kmax = maxl+int(oshoot*real(maxl))
        allocate( w(kmax), stat=alloc_stat )
        call alloc_err("In: hannw; simple_image", alloc_stat)
        wstr = 'hann'
        wfuns = winfuns(wstr, real(kmax), 2.)
        do k=1,kmax
            w(k) = wfuns%eval_apod(real(k))
        end do
    end function hannw

    ! CALCULATORS
    
    !>  \brief  is for calculating the square root of an image
    subroutine square_root( self )
        class(image), intent(inout) :: self
        if( self%ft )then
            !$omp parallel workshare
            where(real(self%cmat) > 0. )
                self%cmat = sqrt(real(self%cmat))
            end where
            !$omp end parallel workshare
        else
            !$omp parallel workshare
            where(self%rmat > 0. )
                self%rmat = sqrt(self%rmat)
            end where
            !$omp end parallel workshare          
        endif 
    end subroutine square_root

    !>  \brief  is for providing location of the maximum pixel value
    function maxcoord(self) result(loc)
        class(image), intent(inout) :: self
        integer                     :: loc(3)
        if( self%ft )then
            stop 'maxloc not implemented 4 FTs! simple_image'
        else
            loc = maxloc(self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)))
        endif
    end function maxcoord

    !>  \brief  is for providing foreground/background statistics
    subroutine stats( self, which, ave, sdev, var, msk, med, errout )
        class(image), intent(inout)    :: self
        character(len=*), intent(in)   :: which
        real, intent(out)              :: ave, sdev, var
        real, intent(in), optional     :: msk
        real, intent(out), optional    :: med
        logical, intent(out), optional :: errout
        integer                        :: i, j, k, npix, alloc_stat, minlen
        real                           :: ci, cj, ck, mskrad, e
        logical                        :: err, didft, background
        real, allocatable              :: pixels(:)
        ! FT
        didft = .false.
        if( self%ft )then
            call self%bwd_ft
            didft = .true.
        endif
        ! 2d/3d
        if( self%ldim(3) > 1 )then
            minlen = minval(self%ldim)
        else
            minlen = minval(self%ldim(1:2))
        endif
        ! mask
        if( present(msk) )then
            mskrad = msk
        else
            mskrad = real(minlen)/2.
        endif
        ! back/foreground
        if( which.eq.'background' )then
            background = .true.
        else if( which.eq.'foreground' )then
            background = .false.
        else
            stop 'unrecognized parameter: which; stats; simple_image'
        endif
        if( self%imgkind .eq. 'xfel' )then
            call moment( real(self%cmat), ave, sdev, var, err )
            med = ave
        else
            allocate( pixels(product(self%ldim)), stat=alloc_stat )
            call alloc_err('backgr; simple_image', alloc_stat)
            pixels = 0.
            npix = 0
            if( self%ldim(3) > 1 )then
                ! 3d
                ci = -real(self%ldim(1))/2.
                do i=1,self%ldim(1)
                    cj = -real(self%ldim(2))/2.
                    do j=1,self%ldim(2)
                        ck = -real(self%ldim(3))/2.
                        do k=1,self%ldim(3)
                            e = hardedge(ci,cj,ck,mskrad)
                            if( background )then
                                if( e < 0.5 )then
                                    npix = npix+1
                                    pixels(npix) = self%rmat(i,j,k)
                                endif
                            else
                                if( e > 0.5 )then
                                    npix = npix+1
                                    pixels(npix) = self%rmat(i,j,k)
                                endif
                            endif
                            ck = ck+1
                        end do
                        cj = cj+1.
                    end do
                    ci = ci+1.
                end do
            else
                ! 2d
                ci = -real(self%ldim(1))/2.
                do i=1,self%ldim(1)
                    cj = -real(self%ldim(2))/2.
                    do j=1,self%ldim(2)
                        e = hardedge(ci,cj,mskrad)
                        if( background )then
                            if( e < 0.5 )then
                                npix = npix+1
                                pixels(npix) = self%rmat(i,j,1)
                            endif
                        else
                            if( e > 0.5 )then
                                npix = npix+1
                                pixels(npix) = self%rmat(i,j,1)
                            endif
                        endif
                        cj = cj+1.
                    end do
                    ci = ci+1.
                end do
            endif
            call moment( pixels(:npix), ave, sdev, var, err )
            if( present(med) ) med  = median_nocopy(pixels(:npix))
            deallocate( pixels )
        endif
        if( present(errout) )then
            errout = err
        else
            if( err ) write(*,'(a)') 'WARNING: variance zero; stats; simple_image'
        endif
        if( didft ) call self%fwd_ft
    end subroutine stats
    
    !>  \brief  to get the minimum and maximum values in an image
    function minmax( self )result( mm )
        class(image), intent(in) :: self
        real :: mm(2)
        mm(1) = minval(self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)))
        mm(2) = maxval(self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)))
    end function minmax

    !>  \brief  for calculating the RMSD of a map
    function rmsd( self ) result( dev )
        class(image), intent(inout) :: self
        real :: devmat(self%ldim(1),self%ldim(2),self%ldim(3)), dev, avg
        if( self%ft ) stop 'rmsd not intended for Fourier transforms; simple_image :: rmsd'
        avg    = self%mean()
        devmat = self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)) - avg
        dev    = sum(devmat**2.0)/real(product(self%ldim))
        if( dev > 0. )then
            dev = sqrt(dev)
        else
            dev = 0.
        endif
    end function rmsd

    !>  \brief  is for estimating the noise variance of an image
    !!          by online estimation of the variance of the background pixels
    function noisesdev( self, msk ) result( sdev )
        use simple_online_var, only: online_var
        class(image), intent(inout) :: self
        real, intent(in)            :: msk
        type(online_var)            :: ovar
        integer                     :: i, j, k
        real                        :: ci, cj, ck, e, sdev, mv(2)
        logical                     :: didft
        if( self%imgkind .eq. 'xfel' ) stop 'routine not implemented for xfel-kind images; simple_image::noisesdev'
        ovar = online_var( )
        didft = .false.
        if( self%ft )then
            call self%bwd_ft
            didft = .true.
        endif
        ci = -real(self%ldim(1))/2.
        do i=1,self%ldim(1)
            cj = -real(self%ldim(2))/2.
            do j=1,self%ldim(2)
                ck = -real(self%ldim(3))/2.
                do k=1,self%ldim(3)
                    if( self%ldim(3) > 1 )then
                        e = hardedge(ci,cj,ck,msk)
                    else
                        e = hardedge(ci,cj,msk)
                    endif
                    if( e < 0.5 )then
                        call ovar%add(self%rmat(i,j,k))
                    endif
                    ck = ck+1
                end do
                cj = cj+1.
            end do
            ci = ci+1.
        end do
        call ovar%finalize
        mv = ovar%get_mean_var()
        sdev = 0.
        if( mv(2) > 0. ) sdev = sqrt(mv(2))
        if( didft ) call self%fwd_ft
    end function noisesdev

    !>  \brief  is for estimating the noise power of an image by
    !!          (1) online estimation of the noise variance from background pixels (outside mask)
    !!          (2) generation of a noise image from the estimated distribution
    !!          (3) taking the median of the power spectrum as an estimate of the noise power
    !!              (assumption of white nosie=constant power)
    function est_noise_pow( self, msk ) result( pow )
        class(image), intent(inout) :: self
        real, intent(in)            :: msk
        real                        :: sdev, pow
        type(image)                 :: tmp
        real, allocatable           :: spec(:)
        if( self%imgkind .eq. 'xfel' ) stop 'routine not implemented for xfel-kind images; simple_image::est_noise_pow'
        sdev = self%noisesdev(msk)
        call tmp%new(self%ldim, self%smpd)
        call tmp%gauran(0., sdev)
        spec = tmp%spectrum('power')
        pow = median_nocopy(spec)
        deallocate(spec)
        call tmp%kill
    end function est_noise_pow

    !>  \brief  is for estimating the noise power of an noise normalized image (noise sdev=1)
    function est_noise_pow_norm( self ) result( pow )
        class(image), intent(inout) :: self
        real                        :: pow
        type(image)                 :: tmp
        real, parameter             :: sdev = 1.
        real, allocatable           :: spec(:)
        if( self%imgkind .eq. 'xfel' ) stop 'routine not implemented for xfel-kind images; simple_image::est_noise_pow_norm'
        call tmp%new(self%ldim, self%smpd)
        call tmp%gauran(0., sdev)
        spec = tmp%spectrum('power')
        pow = median_nocopy(spec)
        deallocate(spec)
        call tmp%kill
    end function est_noise_pow_norm

    !>  \brief  is for calculating the mean of an image
    function mean( self ) result( avg )
        class(image), intent(inout) :: self
        real :: avg
        logical :: didft
        if( self%imgkind .eq. 'xfel' ) stop 'routine not implemented for xfel-kind images; simple_image::mean'
        didft = .false.
        if( self%ft )then
            call self%bwd_ft
            didft = .true.
        endif
        avg = sum(self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)))/real(product(self%ldim))
        if( didft ) call self%bwd_ft
    end function mean

    !>  \brief  is for calculating the median of an image
    function median_pixel( self ) result( med )
        class(image), intent(inout) :: self
        real, allocatable           :: pixels(:)
        real :: med
        if( self%ft ) stop 'not for FTs; simple_image::median'
        pixels = pack(self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)), mask=.true.)
        med = median_nocopy(pixels)
    end function median_pixel

    !>  \brief  is for checking the numerical soundness of an image
    logical function contains_nans( self )
        class(image), intent(in) :: self
        integer :: i, j, k
        if( self%imgkind .eq. 'xfel' ) stop 'routine not implemented for xfel-kind images; simple_image::contains_nans'
        contains_nans = .false.
        do i=1,size(self%rmat,1)
            do j=1,size(self%rmat,2)
                do k=1,size(self%rmat,3)
                    if( .not. is_a_number(self%rmat(i,j,k)) )then
                        contains_nans = .true.
                        return
                    endif
                end do
            end do
        end do
    end function contains_nans
    
    !>  \brief  is for checking the numerical soundness of an image
    subroutine checkimg4nans( self )
        class(image), intent(in) :: self
        if( self%ft )then
            call check4nans3D(self%cmat)
        else
            call check4nans3D(self%rmat)
        endif
    end subroutine checkimg4nans
    
    !>  \brief  is for checking the numerical soundness of an image and curing it if necessary
    subroutine cure_1( self )
        class(image), intent(inout) :: self
        integer                     :: i, j, k, npix, n_nans
        real                        :: ave
        if( self%ft )then
            write(*,*) 'WARNING: Cannot cure FTs; cure_1; simple_image'
            return
        endif
        if( self%imgkind .eq. 'xfel' ) stop 'routine not implemented for xfel-kind images; simple_image::cure'
        npix   = product(self%ldim)
        n_nans = 0
        ave    = 0.
        do i=1,self%ldim(1)
            do j=1,self%ldim(2)
                do k=1,self%ldim(3)
                    if( is_a_number(self%rmat(i,j,k)) )then
                        ! alles gut
                    else
                        n_nans = n_nans+1
                    endif
                    ave = ave+self%rmat(i,j,k)
                end do
            end do
        end do
        if( n_nans > 0 )then
            write(*,*) 'found NaNs in simple_image; cure_1:', n_nans
        endif
        ave = ave/real(npix)
        ! cure
        do i=1,self%ldim(1)
            do j=1,self%ldim(2)
                do k=1,self%ldim(3)
                    if( is_a_number(self%rmat(i,j,k)) )then
                        ! alles gut
                    else
                       self%rmat(i,j,k) = ave
                    endif
                end do
            end do
        end do
    end subroutine cure_1

    !>  \brief  is for checking the numerical soundness of an image and curing it if necessary
    subroutine cure_2( self, maxv, minv, ave, sdev, n_nans )
        class(image), intent(inout) :: self
        real,         intent(out)   :: maxv, minv, ave, sdev
        integer,      intent(out)   :: n_nans
        integer                     :: i, j, k, npix
        real                        :: var, ep, dev
        if( self%ft )then
            write(*,*) 'WARNING: Cannot cure FTs; cure; simple_image'
            return
        endif
        if( self%imgkind .eq. 'xfel' ) stop 'routine not implemented for xfel-kind images; simple_image::cure'
        npix   = product(self%ldim)
        n_nans = 0
        ave    = 0.
        do i=1,self%ldim(1)
            do j=1,self%ldim(2)
                do k=1,self%ldim(3)
                    if( .not. is_a_number(self%rmat(i,j,k)) )then
                        n_nans = n_nans+1
                    else
                        ave = ave+self%rmat(i,j,k)
                    endif
                end do
            end do
        end do
        if( n_nans > 0 )then
            write(*,*) 'found NaNs in simple_image; cure:', n_nans
        endif
        ave = ave/real(npix)
        maxv = maxval( self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)) )
        minv = minval( self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)) )        
        self%rmat = self%rmat - ave
        ! calc sum of devs and sum of devs squared
        ep = 0.
        var = 0.
        do i=1,self%ldim(1)
            do j=1,self%ldim(2)
                do k=1,self%ldim(3)
                    dev = self%rmat(i,j,k)
                    ep  = ep+dev
                    var = var+dev*dev
                end do
            end do
        end do
        var  = (var-ep**2./real(npix))/(real(npix)-1.) ! corrected two-pass formula
        sdev = sqrt(var)
        if( sdev > 0. ) self%rmat = self%rmat/sdev
    end subroutine cure_2

    !>  \brief is for determining loop limits for transforms
    function loop_lims( self, mode, lp_dyn ) result( lims )
        class(image), intent(in)   :: self
        integer, intent(in)        :: mode
        real, intent(in), optional :: lp_dyn
        integer                    :: lims(3,2)
        if( present(lp_dyn) )then
            lims = self%fit%loop_lims(mode, lp_dyn)
        else
            lims = self%fit%loop_lims(mode)
        endif
    end function loop_lims

    !>  \brief  Convert logical address to physical address. Complex image.
    function comp_addr_phys(self,logi) result(phys)
        class(image), intent(in)  :: self
        integer,       intent(in) :: logi(3) !<  Logical address
        integer                   :: phys(3) !<  Physical address
        phys = self%fit%comp_addr_phys(logi)
    end function comp_addr_phys

    !>  \brief is for correlating two images
    function corr( self1, self2, lp_dyn, hp_dyn ) result( r )
        class(image), intent(inout) :: self1, self2
        real, intent(in), optional  :: lp_dyn, hp_dyn
        real                        :: r, sumasq, sumbsq
        integer                     :: h, hh, k, kk, l, ll, phys(3), lims(3,2), sqarg, sqlp, sqhp
        logical                     :: didft1, didft2
        if( self1.eqdims.self2 )then
            didft1 = .false.
            if( .not. self1%ft )then
                call self1%fwd_ft
                didft1 = .true.
            endif
            didft2 = .false.
            if( .not. self2%ft )then
                call self2%fwd_ft
                didft2 = .true.
            endif
            r = 0.
            sumasq = 0.
            sumbsq = 0.
            if( present(lp_dyn) )then
                lims = self1%fit%loop_lims(1,lp_dyn)
            else
                lims = self1%fit%loop_lims(2) ! Nyqvist default low-pass limit
            endif
            sqlp = (maxval(lims(:,2)))**2
            if( present(hp_dyn) )then
                sqhp = max(2,self1%get_find(hp_dyn))**2
            else
                sqhp = 2 ! index 2 default high-pass limit
            endif
            !$omp parallel do default(shared) private(h,hh,k,kk,l,ll,sqarg,phys) &
            !$omp reduction(+:r,sumasq,sumbsq) schedule(auto)
            do h=lims(1,1),lims(1,2)
                hh = h*h
                do k=lims(2,1),lims(2,2)
                    kk = k*k
                    do l=lims(3,1),lims(3,2)
                        ll = l*l
                        sqarg = hh+kk+ll
                        if( sqarg <= sqlp .and. sqarg >= sqhp  )then
                            phys = self1%fit%comp_addr_phys([h,k,l])
                            ! real part of the complex mult btw 1 and 2*
                            r = r+real(self1%cmat(phys(1),phys(2),phys(3))*conjg(self2%cmat(phys(1),phys(2),phys(3))))
                            sumasq = sumasq+csq(self2%cmat(phys(1),phys(2),phys(3)))
                            sumbsq = sumbsq+csq(self1%cmat(phys(1),phys(2),phys(3)))
                         endif
                    end do
                end do
            end do
            !$omp end parallel do
            r = calc_corr(r,sumasq*sumbsq)
            if( didft1 ) call self1%bwd_ft
            if( didft2 ) call self2%bwd_ft
        else
            write(*,*) 'self1%ldim:', self1%ldim
            write(*,*) 'self2%ldim:', self2%ldim
            stop 'images to be correlated need to have same dimensions; corr; simple_image'
        endif
    end function corr
     
    !>  \brief is for highly optimized correlation between 2D images, particle is shifted by shvec
    !!         so remember to take care of this properly in the calling module
    function corr_shifted( self_ref, self_ptcl, shvec, lp_dyn, hp_dyn ) result( r )
        class(image),   intent(inout) :: self_ref, self_ptcl
        real,           intent(in)    :: shvec(3)
        real, optional, intent(in)    :: lp_dyn, hp_dyn
        real                          :: r, sumasq, sumbsq
        complex                       :: shcomp
        integer                       :: h, hh, k, kk, l, ll, phys(3), lims(3,2), sqarg, sqlp, sqhp
        ! this is for highly optimised code, so we assume that images are always Fourier transformed beforehand
        if( .not. self_ref%is_ft()  ) stop 'self_ref not FTed;  corr_shifted; simple_image'
        if( .not. self_ptcl%is_ft() ) stop 'self_ptcl not FTed; corr_shifted; simple_image'    
        r = 0.
        sumasq = 0.
        sumbsq = 0.
        if( present(lp_dyn) )then
            lims = self_ref%fit%loop_lims(1,lp_dyn)
        else
            lims = self_ref%fit%loop_lims(2) ! Nyqvist default low-pass limit
        endif
        sqlp = (maxval(lims(:,2)))**2
        if( present(hp_dyn) )then
            sqhp = max(2,self_ref%get_find(hp_dyn))**2
        else
            sqhp = 2 ! index 2 default high-pass limit
        endif
        !$omp parallel do collapse(3) default(shared) private(h,k,l,sqarg,phys,shcomp) &
        !$omp reduction(+:r,sumasq,sumbsq) schedule(auto)
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                do l=lims(3,1),lims(3,2)
                    sqarg = h*h + k*k + l*l
                    if( sqarg <= sqlp .and. sqarg >= sqhp  )then
                        phys = self_ref%fit%comp_addr_phys([h,k,l])
                        ! shift particle
                        shcomp = self_ptcl%cmat(phys(1),phys(2),phys(3))*&
                                &self_ptcl%oshift([h,k,l], shvec)
                        ! real part of the complex mult btw 1 and 2*
                        r = r+real(self_ref%cmat(phys(1),phys(2),phys(3))*conjg(shcomp))
                        sumasq = sumasq+csq(shcomp)
                        sumbsq = sumbsq+csq(self_ref%cmat(phys(1),phys(2),phys(3)))
                     endif
                end do
            end do
        end do
        !$omp end parallel do        
        r = calc_corr(r,sumasq*sumbsq)
    end function corr_shifted

    !>  \brief is for calculating a real-space correlation coefficient between images
    function real_corr( self1, self2 ) result( r )
        class(image), intent(inout) :: self1, self2
        real, allocatable           :: diffmat1(:,:,:), diffmat2(:,:,:)
        real                        :: r,ax,ay,sxx,syy,sxy,npix 
        if( self1%ft .or. self2%ft ) stop 'cannot real-space correlate FTs; real_corr; simple_image'
        if( .not. (self1.eqdims.self2) )then
            write(*,*) 'ldim self1: ', self1%ldim
            write(*,*) 'ldim self2: ', self2%ldim
            stop 'images to be correlated need to have same dims; real_corr; simple_image'
        endif       
        allocate(diffmat1(self1%ldim(1),self1%ldim(2),self1%ldim(3)),&
                 diffmat2(self2%ldim(1),self2%ldim(2),self2%ldim(3)))
        npix     = real(product(self1%ldim))
        ax       = sum(self1%rmat(:self1%ldim(1),:self1%ldim(2),:self1%ldim(3)))/npix
        ay       = sum(self2%rmat(:self2%ldim(1),:self2%ldim(2),:self2%ldim(3)))/npix
        diffmat1 = self1%rmat(:self1%ldim(1),:self1%ldim(2),:self1%ldim(3))-ax
        diffmat2 = self2%rmat(:self2%ldim(1),:self2%ldim(2),:self2%ldim(3))-ay
        sxx      = sum(diffmat1**2.)
        syy      = sum(diffmat2**2.)
        sxy      = sum(diffmat1*diffmat2)
        deallocate(diffmat1,diffmat2)
        r = calc_corr(sxy,sxx*syy)
    end function real_corr

    !>  \brief is pre-normalise the reference in preparation for real_corr_prenorm
    subroutine prenorm4real_corr( self, sxx )
        class(image), intent(inout) :: self
        real,         intent(out)   :: sxx
        real :: npix, ax
        npix = real(product(self%ldim))
        ax   = sum(self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)))/npix
        self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)) = self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3))-ax
        sxx  = sum(self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3))**2.)
    end subroutine prenorm4real_corr

    !>  \brief is for calculating a real-space correlation coefficient between images (reference is pre-normalised)
    function real_corr_prenorm( self_ref, self_ptcl, sxx_ref ) result( r )
        class(image), intent(inout) :: self_ref, self_ptcl
        real,         intent(in)    :: sxx_ref
        real, allocatable           :: diffmat(:,:,:)
        real                        :: r,ay,syy,sxy,npix 
        if( self_ref%ft .or. self_ptcl%ft ) stop 'cannot real-space correlate FTs; real_corr_prenorm; simple_image'
        if( .not. (self_ref.eqdims.self_ptcl) )then
            write(*,*) 'ldim self_ref: ', self_ref%ldim
            write(*,*) 'ldim self_ptcl: ', self_ptcl%ldim
            stop 'images to be correlated need to have same dims; real_corr_prenorm; simple_image'
        endif       
        allocate(diffmat(self_ptcl%ldim(1),self_ptcl%ldim(2),self_ptcl%ldim(3)))
        npix    = real(product(self_ptcl%ldim))
        ay      = sum(self_ptcl%rmat(:self_ptcl%ldim(1),:self_ptcl%ldim(2),:self_ptcl%ldim(3)))/npix
        diffmat = self_ptcl%rmat(:self_ptcl%ldim(1),:self_ptcl%ldim(2),:self_ptcl%ldim(3))-ay
        syy     = sum(diffmat**2.)
        sxy     = sum(self_ref%rmat(:self_ref%ldim(1),:self_ref%ldim(2),:self_ref%ldim(3))*diffmat)
        deallocate(diffmat)
        r = calc_corr(sxy,sxx_ref*syy)
    end function real_corr_prenorm

    !>  \brief is for calculating a rank correlation coefficient between 'rankified' images
    function rank_corr( self1, self2 ) result( r )
        class(image), intent(inout) :: self1, self2
        integer                     :: i,j,k,npix
        real                        :: sqsum,npixr, r
        if( self1%ft .or. self2%ft ) stop 'cannot rank correlate FTs; rank_corr; simple_image'
        if( .not. (self1.eqdims.self2) ) stop 'images to be correlated need to have same dims; rank_corr; simple_image'
        npix  = product(self1%ldim)
        npixr = real(npix)
        sqsum = 0.
        !$omp parallel do default(shared) private(i,j,k) &
        !$omp reduction(+:sqsum) schedule(auto)
        do i=1,self1%ldim(1)
            do j=1,self1%ldim(2)
                do k=1,self1%ldim(3)
                    sqsum = sqsum+(self1%rmat(i,j,k)-self2%rmat(i,j,k))**2.
                end do
            end do
        end do
        !$omp end parallel do
        r = 1.-(6.*sqsum)/(npixr**3.-npixr)
    end function rank_corr

    !>  \brief is for calculate a real-space distance between images within a mask
    !!         assumes that images are normalized
    function real_dist( self1, self2, msk ) result( r )
        class(image), intent(inout) :: self1, self2, msk
        integer                     :: i, j, k
        real                        :: r
        if( self1%ft .or. self2%ft ) stop 'cannot calculate distance between FTs; real_dist; simple_image'
        if( .not. (self1.eqdims.self2) ) stop 'images to be analyzed need to have same dims; real_dist; simple_image'
        r = 0.
        !$omp parallel do default(shared) private(i,j,k) &
        !$omp reduction(+:r) schedule(auto)
        do i=1,self1%ldim(1)
            do j=1,self1%ldim(2)
                do k=1,self1%ldim(3)
                    if( msk%rmat(i,j,k) > 0.5 )then
                        r = r+(self1%rmat(i,j,k)-self2%rmat(i,j,k))**2
                    endif
                end do
            end do
        end do
        !$omp end parallel do
        r = sqrt(r)
    end function real_dist

    !>  \brief is for calculation of Fourier ring/shell correlation
    subroutine fsc( self1, self2, res, corrs )
        class(image),      intent(inout) :: self1, self2
        real, allocatable, intent(inout) :: res(:), corrs(:)
        real, allocatable                :: sumasq(:), sumbsq(:)
        integer                          :: n, lims(3,2), alloc_stat, phys(3), sh, h, k, l
        logical                          :: didft1, didft2
        if( self1.eqdims.self2 )then
        else
            stop 'images of same dimension only! fsc; simple_image'
        endif
        if( .not. square_dims(self1) .or. .not. square_dims(self2) ) stop 'square dimensions only! fsc; simple_image'
        didft1 = .false.
        if( .not. self1%is_ft() )then
            call self1%fwd_ft
            didft1 = .true.
        endif
        didft2 = .false.
        if( .not. self2%is_ft() )then
            call self2%fwd_ft
            didft2 = .true.
        endif
        n = fdim(self1%ldim(1))
        if( allocated(corrs) ) deallocate(corrs)
        if( allocated(res) )   deallocate(res)
        allocate( corrs(n), res(n), sumasq(n), sumbsq(n), stat=alloc_stat )
        call alloc_err('In: fsc, module: simple_image', alloc_stat)
        corrs  = 0.
        res    = 0.
        sumasq = 0.
        sumbsq = 0.
        lims   = self1%fit%loop_lims(2)
        !$omp parallel do collapse(3) default(shared) private(h,k,l,phys,sh) schedule(auto)
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                do l=lims(3,1),lims(3,2)
                    ! compute physical address
                    phys = self1%fit%comp_addr_phys([h,k,l])
                    ! find shell
                    sh = nint(hyp(real(h),real(k),real(l)))
                    if( sh == 0 .or. sh > n ) cycle
                    ! real part of the complex mult btw self1 and targ*
                    corrs(sh) = corrs(sh)+&
                    real(self1%cmat(phys(1),phys(2),phys(3))*conjg(self2%cmat(phys(1),phys(2),phys(3))))
                    sumasq(sh) = sumasq(sh)+real(abs(self2%cmat(phys(1),phys(2),phys(3))))**2.
                    sumbsq(sh) = sumbsq(sh)+real(abs(self1%cmat(phys(1),phys(2),phys(3))))**2.
                end do
            end do
        end do
        !$omp end parallel do
        ! normalize correlations and compute resolutions
        do k=1,n
            corrs(k) = calc_corr(corrs(k),sumasq(k)*sumbsq(k))
            res(k)   = self1%fit%get_lp(1,k)
        end do
        deallocate(sumasq, sumbsq)
        if( didft1 ) call self1%bwd_ft
        if( didft2 ) call self2%bwd_ft
    end subroutine fsc

    !>  \brief is for calculation of voxels per Fourier shell
    subroutine get_nvoxshell( self, voxs )
        class(image)     , intent(inout) :: self
        real, allocatable, intent(inout) :: voxs(:)
        integer                          :: n, lims(3,2), alloc_stat, sh, h, k, l
        logical                          :: didft
        if( .not. square_dims(self) ) stop 'square dimensions only! fsc; simple_image'
        didft = .false.
        if( .not. self%is_ft() )then
            call self%fwd_ft
            didft = .true.
        endif
        n = fdim(self%ldim(1))
        if( allocated(voxs) )deallocate(voxs)
        allocate( voxs(n), stat=alloc_stat )
        call alloc_err('In: get_nvoxshell, module: simple_image', alloc_stat)
        voxs = 0.
        lims = self%fit%loop_lims(2)
        !$omp parallel do collapse(3) default(shared) private(h,k,l,sh) schedule(auto)
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                do l=lims(3,1),lims(3,2)
                    ! find shell
                    sh = nint(hyp(real(h),real(k),real(l)))
                    if( sh == 0 .or. sh > n ) cycle
                    voxs( sh ) = voxs( sh )+1.
                end do
            end do
        end do
        !$omp end parallel do
        if( didft ) call self%bwd_ft
    end subroutine get_nvoxshell

    !>  \brief get array of resolution steps
    function get_res( self ) result( res )
        class(image), intent(in) :: self
        real, allocatable        :: res(:)
        integer                  :: n, k, alloc_stat
        n = fdim(self%ldim(1))
        allocate( res(n), stat=alloc_stat )
        call alloc_err('In: get_res, module: simple_image', alloc_stat)
        do k=1,n
            res(k) = self%fit%get_lp(1,k)
        end do
    end function get_res

    !>  \brief  returns the real and imaginary parts of the phase shift at point
    !!          logi in a Fourier transform caused by the origin shift in shvec
    function oshift_1( self, logi, shvec, ldim ) result( comp )
        class(image), intent(in)      :: self
        real, intent(in)              :: logi(3)
        real, intent(in)              :: shvec(3)
        integer, intent(in), optional :: ldim
        complex                       :: comp
        real                          :: arg, shvec_here(3)
        shvec_here = shvec
        if( self%ldim(3) == 1 ) shvec_here(3) = 0.
        if( present(ldim) )then
            arg = sum(logi(:ldim)*shvec_here(:ldim)*self%shconst(:ldim))
        else  
            arg = sum(logi*shvec_here*self%shconst)
        endif
        comp = cmplx(cos(arg),sin(arg))
    end function oshift_1

    !>  \brief  returns the real and imaginary parts of the phase shift at point
    !!          logi in a Fourier transform caused by the origin shift in shvec
    function oshift_2( self, logi, shvec, ldim ) result( comp )
        class(image), intent(in)      :: self
        integer, intent(in)           :: logi(3)
        real, intent(in)              :: shvec(3)
        integer, intent(in), optional :: ldim
        complex                       :: comp
        comp = self%oshift_1(real(logi), shvec, ldim)
    end function oshift_2

    !>  \brief  returns the real argument transfer matrix components at point logi in a Fourier transform
    function gen_argtransf_comp( self, logi, ldim ) result( arg )
        class(image), intent(in)      :: self
        real, intent(in)              :: logi(3)
        integer, intent(in), optional :: ldim
        real                          :: arg(3)
        integer                       :: lstop, i
        lstop = 2
        if( self%ldim(3) > 1 ) lstop = 3
        if( present(ldim) )    lstop = ldim
        arg = 0.
        do i=1,lstop
            if( self%ldim(i) == 1 )then
                cycle
            else
                if( is_even(self%ldim(i)) )then
                    arg = arg+logi(i)*(PI/real(self%ldim(i)/2.))
                else
                    arg = arg+logi(i)*(PI/real((self%ldim(i)-1)/2.))
                endif
            endif
        end do
    end function gen_argtransf_comp

    !>  \brief  is for generating the argument transfer matrix for fast shifting of a FT
    subroutine gen_argtransf_mats( self, transfmats )
        class(image), intent(inout) :: self, transfmats(3)
        integer                     :: h, k, l, lims(3,2), phys(3)
        real                        :: arg(3)
        call transfmats(1)%new(self%ldim,self%smpd)
        call transfmats(2)%new(self%ldim,self%smpd)
        call transfmats(3)%new(self%ldim,self%smpd)
        lims = self%fit%loop_lims(2)
        !$omp parallel do collapse(3) default(shared) private(arg,phys,h,k,l) schedule(auto)
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                do l=lims(3,1),lims(3,2)
                    arg = self%gen_argtransf_comp(real([h,k,l]))
                    phys = self%fit%comp_addr_phys([h,k,l])
                    transfmats(1)%cmat(phys(1),phys(2),phys(3)) = cmplx(arg(1),0.)
                    transfmats(2)%cmat(phys(1),phys(2),phys(3)) = cmplx(arg(2),0.)
                    transfmats(3)%cmat(phys(1),phys(2),phys(3)) = cmplx(arg(3),0.)
                end do
            end do
        end do
        !$omp end parallel do
    end subroutine gen_argtransf_mats

    ! MODIFIERS

    !>  \brief  inserts a box*box particle image into a micrograph
    subroutine insert(self_in, coord, self_out )
        class(image), intent(in)   :: self_in
        integer, intent(in)        :: coord(2)
        type(image), intent(inout) :: self_out
        integer :: xllim, xulim, yllim, yulim
        if( self_in%ldim(3) > 1 )       stop 'only 4 2D images; insert; simple_image'
        if( self_in%is_ft() )           stop 'only 4 real images; insert; simple_image'
        if( .not. self_in%even_dims() ) stop 'only 4 even particle dims; insert; simple_image'
        if( self_out%exists() )then
            if( self_out%ldim(3) > 1 )  stop 'only 4 2D images; insert; simple_image'
            if( self_out%is_ft() )      stop 'only 4 real images; insert; simple_image'
            if( self_out%ldim(1) > self_in%ldim(1) .and. self_out%ldim(2) > self_in%ldim(2) .and. self_out%ldim(3) == 1 )then
                if( (coord(1) < self_in%ldim(1)/2+1 .or. coord(1) > self_out%ldim(1)-self_in%ldim(1)/2-1) .or.&
                 (coord(2) < self_in%ldim(2)/2+1 .or. coord(2) > self_out%ldim(2)-self_in%ldim(2)/2-1) )then
                    stop 'particle outside micrograph area; insert; simple_image'
                endif
            else
                stop 'micrograph (self_out) need to have dimensions larger than the particle (self_in); insert; simple_image'
            endif
        else
            stop 'micrograph (self_out) does not exist; insert; simple_image'
        endif
        ! set range
        xllim = coord(1)-self_in%ldim(1)/2
        xulim = coord(1)+self_in%ldim(1)/2-1
        yllim = coord(2)-self_in%ldim(2)/2
        yulim = coord(2)+self_in%ldim(2)/2-1
        ! insert particle image matrix into micrograph image matrix
        self_out%rmat(xllim:xulim,yllim:yulim,1) = self_in%rmat(1:self_in%ldim(1),1:self_in%ldim(2),1)
    end subroutine insert

    !>  \brief  is for inverting an image
    subroutine inv( self )
        class(image), intent(inout) :: self
        if( self%imgkind .eq. 'xfel' ) stop 'not intended for xfel-kind images; simple_image::inv'
        self%rmat = -1.*self%rmat
    end subroutine inv

    !>  \brief  is for making a random image (0,1)
    subroutine ran( self )
        class(image), intent(inout) :: self
        integer :: i, j, k
        if( self%imgkind .eq. 'xfel' ) stop 'not intended for xfel-kind images; simple_image::ran'
        do i=1,self%ldim(1)
            do j=1,self%ldim(2)
                do k=1,self%ldim(3)
                    self%rmat(i,j,k) = ran3()
                end do
            end do
        end do
        self%ft = .false.
    end subroutine ran

    !>  \brief  is for making a Gaussian random image (0,1)
    subroutine gauran( self, mean, sdev )
        class(image), intent(inout) :: self
        real, intent(in) :: mean, sdev
        integer :: i, j, k
        if( self%imgkind .eq. 'xfel' ) stop 'not intended for xfel-kind images; simple_image::gauran'
        do i=1,self%ldim(1)
            do j=1,self%ldim(2)
                do k=1,self%ldim(3)
                    self%rmat(i,j,k) = gasdev( mean, sdev )
                end do
            end do
        end do
        self%ft = .false.
    end subroutine gauran

    !>  \brief  is for adding Gaussian noise to an image
    subroutine add_gauran( self, snr, noiseimg )
        class(image), intent(inout)        :: self
        real, intent(in)                   :: snr
        type(image), intent(out), optional :: noiseimg
        real    :: noisesdev, ran
        integer :: i, j, k
        if( self%imgkind .eq. 'xfel' ) stop 'not intended for xfel-kind images; simple_image::add_gauran'
        call self%norm
        if( present(noiseimg) ) call noiseimg%new(self%ldim, self%smpd)
        noisesdev = sqrt(1/snr)
        do i=1,self%ldim(1)
            do j=1,self%ldim(2)
                do k=1,self%ldim(3)
                    ran = gasdev(0., noisesdev)
                    self%rmat(i,j,k) = self%rmat(i,j,k)+ran
                    if( present(noiseimg) ) call noiseimg%set([i,j,k], ran)
                end do
            end do
        end do
    end subroutine add_gauran
    
    !>  \brief  is for generating dead/hot pixel positions in an image
    function dead_hot_positions( self, frac ) result( pos )
        class(image), intent(in) :: self
        real, intent(in)         :: frac
        logical, allocatable     :: pos(:,:)
        integer :: ipix, jpix, cnt
        allocate(pos(self%ldim(1),self%ldim(2)))
        pos = .false.
        cnt = 0
        do ipix=1,self%ldim(1)
            do jpix=1,self%ldim(2)
                if( ran3() <= frac )then
                    pos(ipix,jpix) = .true.
                    cnt = cnt+1
                endif
            end do
        end do
    end function dead_hot_positions
    
    !>  \brief  Taper edges of image so that there are no sharp discontinuities in real space
    !!          This is a re-implementation of the MRC program taperedgek.for (Richard Henderson, 1987)
    !!          I stole it from CTFFIND4 (thanks Alexis for the beautiful re-implementation)
    subroutine taper_edges(self)
        class(image), intent(inout) :: self
        real, allocatable  :: avg_curr_edge_start(:,:)
        real, allocatable  :: avg_curr_edge_stop(:,:)
        real, allocatable  :: avg_curr_edge_avg(:,:)
        real, allocatable  :: smooth_avg_curr_edge_start(:,:)
        real, allocatable  :: smooth_avg_curr_edge_stop(:,:)
        integer            :: curr_dim, ndims
        integer            :: dim2, dim3
        integer            :: i,j,k
        integer            :: j_shift,k_shift
        integer            :: jj,kk
        integer            :: nvals_runnavg
        integer, parameter :: avg_strip_width(3)   = 100
        integer, parameter :: taper_strip_width(3) = 500
        integer, parameter :: smooth_half_width(3) = 1
        ndims = 2
        if (self%is_3d()) ndims = 3
        do curr_dim=1,ndims
            ! take care of dimensions
            select case (curr_dim)
                case (1)
                    dim2 = 2
                    dim3 = 3
                case (2)
                    dim2 = 1
                    dim3 = 3
                case (3)
                    dim2 = 1
                    dim3 = 2
            end select
            ! take care of allocation & initialisation
            if(allocated(avg_curr_edge_start))        deallocate(avg_curr_edge_start)
            if(allocated(avg_curr_edge_stop))         deallocate(avg_curr_edge_stop)
            if(allocated(avg_curr_edge_avg))          deallocate(avg_curr_edge_avg)
            if(allocated(smooth_avg_curr_edge_start)) deallocate(smooth_avg_curr_edge_start)
            if(allocated(smooth_avg_curr_edge_stop))  deallocate(smooth_avg_curr_edge_stop)
            allocate( avg_curr_edge_start(self%ldim(dim2),self%ldim(dim3)),&
                      avg_curr_edge_stop (self%ldim(dim2),self%ldim(dim3)),&
                      avg_curr_edge_avg(self%ldim(dim2),self%ldim(dim3)),&
                      smooth_avg_curr_edge_start(self%ldim(dim2),self%ldim(dim3)),&
                      smooth_avg_curr_edge_stop (self%ldim(dim2),self%ldim(dim3)))
            avg_curr_edge_start        = 0.0e0
            avg_curr_edge_stop         = 0.0e0
            avg_curr_edge_avg          = 0.0e0
            smooth_avg_curr_edge_start = 0.0e0
            smooth_avg_curr_edge_stop  = 0.0e0
            ! Deal with X=0 and X=self%ldim(1) edges
            i=1
            do k=1,self%ldim(dim3)
                do j=1,self%ldim(dim2)
                    select case (curr_dim)
                        case (1)
                            avg_curr_edge_start(j,k) =&
                            sum(self%rmat(1:avg_strip_width(curr_dim),j,k))&
                            /avg_strip_width(curr_dim)
                            avg_curr_edge_stop(j,k)  =&
                            sum(self%rmat(self%ldim(curr_dim)-avg_strip_width(1)+1:self%ldim(curr_dim),j,k))&
                            /avg_strip_width(curr_dim)
                        case (2)
                            avg_curr_edge_start(j,k) =&
                            sum(self%rmat(j,1:avg_strip_width(curr_dim),k))&
                            /avg_strip_width(curr_dim)
                            avg_curr_edge_stop(j,k) =&
                            sum(self%rmat(j,self%ldim(curr_dim)-avg_strip_width(1)+1:self%ldim(curr_dim),k))&
                            /avg_strip_width(curr_dim)
                        case (3)
                            avg_curr_edge_start(j,k) =&
                            sum(self%rmat(j,k,1:avg_strip_width(curr_dim)))&
                            /avg_strip_width(curr_dim)
                            avg_curr_edge_stop(j,k) =&
                            sum(self%rmat(j,k,self%ldim(curr_dim)-avg_strip_width(1)+1:self%ldim(curr_dim)))&
                            /avg_strip_width(curr_dim)
                    end select
                enddo
            enddo
            avg_curr_edge_avg   = 0.5e0*(avg_curr_edge_stop+avg_curr_edge_start)
            avg_curr_edge_start = avg_curr_edge_start-avg_curr_edge_avg
            avg_curr_edge_stop  = avg_curr_edge_stop-avg_curr_edge_avg
            ! Apply smoothing parallel to edge in the form of a running average
            do k=1,self%ldim(dim3)
                do j=1,self%ldim(dim2)
                    nvals_runnavg = 0
                    ! Loop over neighbourhood of non-smooth arrays
                    do k_shift=-smooth_half_width(dim3),smooth_half_width(dim3)
                        kk = k+k_shift
                        if (kk .lt. 1 .or. kk .gt. self%ldim(dim3)) cycle
                        do j_shift=-smooth_half_width(dim2),smooth_half_width(dim2)
                            jj = j+j_shift
                            if (jj .lt. 1 .or. jj .gt. self%ldim(dim2)) cycle
                            nvals_runnavg = nvals_runnavg + 1
                            smooth_avg_curr_edge_start (j,k) =&
                            smooth_avg_curr_edge_start(j,k)+avg_curr_edge_start(jj,kk)
                            smooth_avg_curr_edge_stop(j,k)   =&
                            smooth_avg_curr_edge_stop(j,k)+avg_curr_edge_stop(jj,kk)
                        enddo
                    enddo
                    ! Now we can compute the average
                    smooth_avg_curr_edge_start(j,k) = smooth_avg_curr_edge_start(j,k)/nvals_runnavg
                    smooth_avg_curr_edge_stop(j,k)   = smooth_avg_curr_edge_stop(j,k)/nvals_runnavg
                enddo
            enddo
            ! Taper the image
            do i=1,self%ldim(curr_dim)
                if (i .le. taper_strip_width(curr_dim)) then
                    select case (curr_dim)
                        case (1)
                            self%rmat(i,:,:) = self%rmat(i,:,:)&
                            - smooth_avg_curr_edge_start (:,:)&
                            * (taper_strip_width(curr_dim)-i+1)&
                            / taper_strip_width(curr_dim)
                        case (2)
                            self%rmat(1:self%ldim(1),i,:) = self%rmat(1:self%ldim(1),i,:)&
                            - smooth_avg_curr_edge_start(:,:)&
                            * (taper_strip_width(curr_dim)-i+1)&
                            / taper_strip_width(curr_dim)
                        case (3)
                            self%rmat(1:self%ldim(1),:,i) = self%rmat(1:self%ldim(1),:,i)&
                            - smooth_avg_curr_edge_start (:,:)&
                            * (taper_strip_width(curr_dim)-i+1)&
                            / taper_strip_width(curr_dim)
                    end select
                else if (i .ge. self%ldim(curr_dim)-taper_strip_width(curr_dim)+1) then
                    select case (curr_dim)
                        case (1)
                            self%rmat(i,:,:) = self%rmat(i,:,:)&
                            - smooth_avg_curr_edge_stop(:,:)&
                            * (taper_strip_width(curr_dim)+i&
                            - self%ldim(curr_dim))&
                            / taper_strip_width(curr_dim)
                        case (2)
                            self%rmat(1:self%ldim(1),i,:) = self%rmat(1:self%ldim(1),i,:)&
                            - smooth_avg_curr_edge_stop(:,:)&
                            * (taper_strip_width(curr_dim)+i&
                            - self%ldim(curr_dim))&
                            / taper_strip_width(curr_dim)
                        case (3)
                            self%rmat(1:self%ldim(1),:,i) = self%rmat(1:self%ldim(1),:,i)&
                            - smooth_avg_curr_edge_stop(:,:)&
                            * (taper_strip_width(curr_dim)+i&
                            - self%ldim(curr_dim))&
                            / taper_strip_width(curr_dim)
                    end select
                endif
            enddo
        enddo
        if(allocated(avg_curr_edge_start))        deallocate(avg_curr_edge_start)
        if(allocated(avg_curr_edge_stop))         deallocate(avg_curr_edge_stop)
        if(allocated(avg_curr_edge_avg))          deallocate(avg_curr_edge_avg)
        if(allocated(smooth_avg_curr_edge_start)) deallocate(smooth_avg_curr_edge_start)
        if(allocated(smooth_avg_curr_edge_stop))  deallocate(smooth_avg_curr_edge_stop)
    end subroutine taper_edges

    !>  \brief  is for adding salt and pepper noise to an image
    subroutine salt_n_pepper( self, pos )
        class(image), intent(inout) :: self
        logical, intent(in)         :: pos(:,:)
        integer :: ipix, jpix
        if( self%imgkind .eq. 'xfel' ) stop 'not intended for xfel-kind images; simple_image::salt_n_pepper'
        if( .not. self%is_2d() ) stop 'only for 2D images; salt_n_pepper; simple_image'
        call self%norm('sigm')
        do ipix=1,self%ldim(1)
            do jpix=1,self%ldim(2)
                if( pos(ipix,jpix) )then
                    if( ran3() < 0.5 )then
                        self%rmat(ipix,jpix,1) = 0.
                    else
                        self%rmat(ipix,jpix,1) = 1.
                    endif
                endif
            end do
        end do
    end subroutine salt_n_pepper

    !>  \brief  just a binary square for testing purposes
    subroutine square( self, sqrad )
        class(image), intent(inout) :: self
        integer,      intent(in)    :: sqrad
        integer :: i, j, k
        if( self%imgkind .eq. 'xfel' ) stop 'not intended for xfel-kind images; simple_image::square'
        self%rmat = 0.
        if( all(self%ldim(1:2) .gt. sqrad) .and. self%ldim(3) == 1 ) then
            do i=self%ldim(1)/2-sqrad+1,self%ldim(1)/2+sqrad
                do j=self%ldim(2)/2-sqrad+1,self%ldim(2)/2+sqrad
                    self%rmat(i,j,1) = 1.
                end do
            end do
        else if( all(self%ldim .gt. sqrad) .and. self%ldim(3) > 1 )then
            do i=self%ldim(1)/2-sqrad+1,self%ldim(1)/2+sqrad
                do j=self%ldim(2)/2-sqrad+1,self%ldim(2)/2+sqrad
                    do k=self%ldim(3)/2-sqrad+1,self%ldim(3)/2+sqrad
                        self%rmat(i,j,k) = 1.
                    end do
                end do
            end do
        else
            stop 'image is to small to fit the square; square; simple_image'
        endif
        self%ft = .false.
    end subroutine square

    !>  \brief  just a corner filling fun for testing purposes
    subroutine corners( self, sqrad )
        class(image), intent(inout) :: self
        integer, intent(in)         :: sqrad
        integer :: i, j
        if( self%imgkind .eq. 'xfel' ) stop 'not intended for xfel-kind images; simple_image::corners'
        self%rmat = 0.
        do i=self%ldim(1)-sqrad+1,self%ldim(1)
            do j=self%ldim(2)-sqrad+1,self%ldim(2)
                self%rmat(i,j,1) = 1.
            end do
        end do
        do i=1,sqrad
            do j=1,sqrad
                self%rmat(i,j,1) = 1.
            end do
        end do
        do i=self%ldim(1)-sqrad+1,self%ldim(1)
            do j=1,sqrad
                self%rmat(i,j,1) = 1.
            end do
        end do
        do i=1,sqrad
            do j=self%ldim(2)-sqrad+1,self%ldim(2)
                self%rmat(i,j,1) = 1.
            end do
        end do
        self%ft = .false.
    end subroutine corners
    
    !>  \brief  to generate a before (left) and after (right) image
    function before_after( left, right ) result( ba )
        class(image), intent(in) :: left, right
        integer     :: ldim(3)
        type(image) :: ba
        if( left.eqdims.right )then
            if( left.eqsmpd.right )then
                if( left%ft .or. right%ft ) stop 'not for FTs; before_after; simple_image'
                if( left%is_3d() .or. right%is_3d() ) stop 'not for 3D imgs; before_after; simple_image'
                ldim = left%ldim
                call ba%new(ldim, left%smpd)
                ba%rmat(:ldim(1)/2,:ldim(2),1)   = left%rmat(:ldim(1)/2,:ldim(2),1)
                ba%rmat(ldim(1)/2+1:,:ldim(2),1) = right%rmat(ldim(1)/2+1:,:ldim(2),1)
            else
                 stop 'before (left) and after (right) not of same smpd; before_after; simple_image'
            endif
        else
            stop 'before (left) and after (right) not of same dim; before_after; simple_image'
        endif
    end function before_after

    !>  \brief  just a Gaussian fun for testing purposes
    subroutine gauimg( self, wsz)
        class(image), intent(inout) :: self
        integer, intent(in) :: wsz
        real    :: x, y, z, xw, yw, zw
        integer :: i, j, k
        if( self%imgkind .eq. 'xfel' ) stop 'not intended for xfel-kind images; simple_image::gauimg'
        x = -real(self%ldim(1))/2.
        do i=1,self%ldim(1)
            xw = gauwfun(x, 0.5*real(wsz))
            y = -real(self%ldim(2))/2.
            do j=1,self%ldim(2)
                yw = gauwfun(y, 0.5*real(wsz))
                z = -real(self%ldim(3))/2.
                do k=1,self%ldim(3)
                    if( self%ldim(3) > 1 )then
                        zw = gauwfun(z, 0.5*real(wsz))
                    else
                        zw = 1.
                    endif
                    self%rmat(i,j,k) = xw*yw*zw
                    z = z+1.
                end do
                y = y+1.
            end do
            x = x+1.
        end do
        self%ft = .false.
    end subroutine gauimg

    !>  \brief  forward Fourier transform
    subroutine fwd_ft( self )
        class(image), intent(inout) :: self
        if( self%imgkind .eq. 'xfel' ) stop 'Fourier transformation of XFEL patterns not allowed; simple_image::fwd_ft'
        if( self%ft ) return
        if( shift_to_phase_origin ) call self%shift_phorig
        call fftwf_execute_dft_r2c(self%plan_fwd,self%rmat,self%cmat)
        ! now scale the values so that a bwd_ft of the output yields the
        ! original image back, rather than a scaled version
        self%cmat = self%cmat/real(product(self%ldim))
        self%ft = .true.
    end subroutine fwd_ft

    !>  \brief  backward Fourier transform
    subroutine bwd_ft( self )
        class(image), intent(inout) :: self
        if( self%imgkind .eq. 'xfel' ) stop 'Back fourier transformation of XFEL patterns not allowed; simple_image::bwd_ft'
        if( self%ft )then
            call fftwf_execute_dft_c2r(self%plan_bwd,self%cmat,self%rmat)
            self%ft = .false.
            if( shift_to_phase_origin ) call self%shift_phorig
        endif
    end subroutine bwd_ft

    !>  \brief  converts a em-kind image into a xfel pattern
    subroutine em2xfel( self )
        class(image), intent(inout) :: self
        type(image) :: tmp
        real, allocatable :: zeroes(:,:,:)
        integer :: alloc_stat
        if( self%imgkind .eq. 'xfel' ) return
        ! make a temporary copy of the image
        tmp = self
        ! make the XFEL pattern
        call self%new(tmp%ldim,tmp%smpd,imgkind='xfel')
        allocate(zeroes(tmp%ldim(1),tmp%ldim(2),tmp%ldim(3)), stat=alloc_stat)
        call alloc_err("In: simple_image::img2xfel", alloc_stat)
        zeroes = 0.
        self%cmat(self%lims(1,1):self%lims(1,2),self%lims(2,1):self%lims(2,2),&
        self%lims(3,1):self%lims(3,2)) = cmplx(tmp%rmat(:tmp%ldim(1),:tmp%ldim(2),:tmp%ldim(3)),zeroes)
        self%rmat => null()
        call tmp%kill
        deallocate(zeroes)
    end subroutine em2xfel

    !>  \brief  generates images for visualization of a Fourier transform
    subroutine ft2img( self, which, img )
        class(image),     intent(inout) :: self
        character(len=*), intent(in)    :: which
        class(image),     intent(out)   :: img
        integer :: h,mh,k,mk,l,ml,lims(3,2),inds(3),phys(3)
        logical :: didft
        complex :: comp
        if( self%imgkind .eq. 'xfel' )then
            if( which .eq. 'real' )then
                ! all ok
            else
                stop 'this which parameter is not applicable to xfel-kind images; simple_image::ft2img'
            endif
        endif
        didft = .false.
        if( self%ft )then
        else
            call self%fwd_ft
            didft = .true.
        endif
        if( img%exists() )then
            if( .not.(self.eqdims.img) )then
                call img%new(self%ldim, self%smpd)
            else
                img = 0.
            endif
        else
            call img%new(self%ldim, self%smpd)
        end if
        lims = self%loop_lims(3)
        mh = maxval(lims(1,:))
        mk = maxval(lims(2,:))
        ml = maxval(lims(3,:))
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                do l=lims(3,1),lims(3,2)
                    phys = self%comp_addr_phys([h,k,l])
                    comp = self%get_fcomp([h,k,l],phys)
                    inds(1) = min(max(1,h+mh+1),self%ldim(1))
                    inds(2) = min(max(1,k+mk+1),self%ldim(2))
                    inds(3) = min(max(1,l+ml+1),self%ldim(3))
                    select case(which)
                        case ('amp')
                            call img%set(inds,cabs(comp))
                        case('square')
                            call img%set(inds,cabs(comp)**2.)
                        case('phase')
                            call img%set(inds,phase_angle(comp))
                        case('real')
                            call img%set(inds,real(comp))
                        case ('log')
                            call img%set(inds,log10(cabs(comp)))
                        case ('sqrt')
                            call img%set(inds,sqrt(cabs(comp)))
                        case DEFAULT
                            write(*,*) 'Usupported mode: ', trim(which)
                            stop 'simple_image :: ft2img'
                    end select
                end do
            end do
        end do
        if( didft ) call self%bwd_ft
    end subroutine ft2img

    !>  \brief  forward log Fourier transform
    subroutine fwd_logft( self )
        class(image), intent(inout) :: self
        integer :: lims(3,2), h, k, l, phys(3)
        if( self%imgkind .eq. 'xfel' ) stop 'Fourier transformation of XFEL patterns not allowed; simple_image::fwd_logft'
        call self%fwd_ft
        lims = self%fit%loop_lims(2)
        do h=lims(1,1),lims(1,2)
            do k=lims(2,1),lims(2,2)
                do l=lims(3,1),lims(3,2)
                    phys = self%fit%comp_addr_phys([h,k,l])
                    if( cabs(self%cmat(phys(1),phys(2),phys(3))) /= 0. )then
                        self%cmat(phys(1),phys(2),phys(3)) = clog(self%cmat(phys(1),phys(2),phys(3)))
                    endif
                end do
            end do
        end do
    end subroutine fwd_logft

    !>  \brief  forward log Fourier transform
    subroutine bwd_logft( self )
        class(image), intent(inout) :: self
        integer :: lims(3,2), h, k, l, phys(3)
        if( self%imgkind .eq. 'xfel' ) stop 'Fourier transformation of XFEL patterns not allowed; simple_image::bwd_logft'
        if( self%ft )then
            lims = self%fit%loop_lims(2)
            do h=lims(1,1),lims(1,2)
                do k=lims(2,1),lims(2,2)
                    do l=lims(3,1),lims(3,2)
                        phys = self%fit%comp_addr_phys([h,k,l])
                        self%cmat(phys(1),phys(2),phys(3)) = cexp(self%cmat(phys(1),phys(2),phys(3)))
                    end do
                end do
            end do
            call self%bwd_ft
        endif
    end subroutine bwd_logft

    !>  \brief  an image shifter to prepare for Fourier transformation
    subroutine shift_phorig( self )
        class(image), intent(inout) :: self
        integer :: i, j, k
        real    :: rswap
        integer :: kfrom,kto
        if( self%ft ) stop 'ERROR, this method is intended for real images; shift_phorig; simple_image'
        if( self%even_dims() )then
            if( self%ldim(3) == 1 )then
                kfrom = 1
                kto   = 1
            else
                kfrom = 1
                kto   = self%ldim(3)/2
            endif
            do i=1,self%ldim(1)/2
                do j=1,self%ldim(2)/2
                    do k=kfrom,kto
                        if( self%ldim(3) > 1 )then
                            !(1)
                            rswap = self%rmat(i,j,k)
                            self%rmat(i,j,k) = self%rmat(self%ldim(1)/2+i,self%ldim(2)/2+j,self%ldim(3)/2+k)
                            self%rmat(self%ldim(1)/2+i,self%ldim(2)/2+j,self%ldim(3)/2+k) = rswap
                            !(2)
                            rswap = self%rmat(i,self%ldim(2)/2+j,self%ldim(3)/2+k)
                            self%rmat(i,self%ldim(2)/2+j,self%ldim(3)/2+k) = self%rmat(self%ldim(1)/2+i,j,k)
                            self%rmat(self%ldim(1)/2+i,j,k) = rswap
                            !(3)
                            rswap = self%rmat(self%ldim(1)/2+i,j,self%ldim(3)/2+k)
                            self%rmat(self%ldim(1)/2+i,j,self%ldim(3)/2+k) = self%rmat(i,self%ldim(2)/2+j,k)
                            self%rmat(i,self%ldim(2)/2+j,k) = rswap
                            !(4)
                            rswap = self%rmat(i,j,self%ldim(3)/2+k)
                            self%rmat(i,j,self%ldim(3)/2+k) = self%rmat(self%ldim(1)/2+i,self%ldim(2)/2+j,k)
                            self%rmat(self%ldim(1)/2+i,self%ldim(2)/2+j,k) = rswap
                        else
                            !(1)
                            rswap = self%rmat(i,j,1)
                            self%rmat(i,j,1) = self%rmat(self%ldim(1)/2+i,self%ldim(2)/2+j,1)
                            self%rmat(self%ldim(1)/2+i,self%ldim(2)/2+j,1) = rswap
                            !(2)
                            rswap = self%rmat(i,self%ldim(2)/2+j,1)
                            self%rmat(i,self%ldim(2)/2+j,1) = self%rmat(self%ldim(1)/2+i,j,1)
                            self%rmat(self%ldim(1)/2+i,j,1) = rswap
                        endif
                    end do
                end do
            end do
        else
            write(*,*) 'ldim: ', self%ldim
            stop 'even dimensions assumed; shift_phorig; simple_image'
        endif
    end subroutine shift_phorig

    !>  \brief  is for origin shifting an image
    subroutine shift( self, x, y, z, lp_dyn, imgout )
        class(image),           intent(inout) :: self
        real,                   intent(in)    :: x, y
        real,         optional, intent(in)    :: z, lp_dyn
        class(image), optional, intent(inout) :: imgout
        integer                               :: h, k, l, lims(3,2), phys(3)
        real                                  :: zz
        logical                               :: didft
        if( self%imgkind .eq. 'xfel' )then
            write(*,*) 'WARNING! shifting of xfel patterns not yet implemented; simple_image::shift'
            return
        endif
        if( present(z) )then
            if( x == 0. .and. y == 0. .and. z == 0. )then
                if( present(imgout) ) imgout = self
                return
            endif
            if( self%ldim(1) == 1 ) stop 'cannot shift 2D FT in 3D; shift; simple_image'
            zz = z
        else
            if( x == 0. .and. y == 0. )then
                if( present(imgout) ) imgout = self
                return
            endif
            zz = 0.
        endif
        didft = .false.
        if( .not. self%ft )then
            call self%fwd_ft
            didft = .true.
        endif
        if( present(lp_dyn) )then
            lims = self%fit%loop_lims(1,lp_dyn)
        else
            lims = self%fit%loop_lims(2)
        endif
        if( present(imgout) )then
            imgout%ft = .true.
            !$omp parallel do collapse(3) default(shared) private(phys,h,k,l) schedule(auto)
            do h=lims(1,1),lims(1,2)
                do k=lims(2,1),lims(2,2)
                    do l=lims(3,1),lims(3,2)
                        phys = self%fit%comp_addr_phys([h,k,l])
                        imgout%cmat(phys(1),phys(2),phys(3)) = self%cmat(phys(1),phys(2),phys(3))*&
                        self%oshift([h,k,l], [x,y,zz])
                    end do
                end do
            end do
            !$omp end parallel do
        else
            !$omp parallel do collapse(3) default(shared) private(phys,h,k,l) schedule(auto)
            do h=lims(1,1),lims(1,2)
                do k=lims(2,1),lims(2,2)
                    do l=lims(3,1),lims(3,2)
                        phys = self%fit%comp_addr_phys([h,k,l])
                        self%cmat(phys(1),phys(2),phys(3)) = self%cmat(phys(1),phys(2),phys(3))*&
                        self%oshift([h,k,l], [x,y,zz])
                    end do
                end do
            end do
            !$omp end parallel do
        endif
        if( didft )then
            call self%bwd_ft
            if( present(imgout) ) call imgout%bwd_ft
        endif
    end subroutine shift

    !>  \brief  is for spherical masking
    subroutine mask( self, mskrad, which, inner, width, msksum )
        class(image),     intent(inout) :: self
        real,             intent(in)    :: mskrad
        character(len=*), intent(in)    :: which
        real, optional,   intent(in)    :: inner, width
        real, optional,   intent(out)   :: msksum
        real    :: ci, cj, ck, e, wwidth
        real    :: cis(self%ldim(1)), cjs(self%ldim(2)), cks(self%ldim(3))
        integer :: i, j, k, minlen, ir, jr, kr, vec(3)
        logical :: didft, doinner, soft, domsksum
        if( self%imgkind .eq. 'xfel' ) stop 'masking of xfel-kind images not allowed; simple_image::mask'
        ! width
        wwidth = 10.
        if( present(width) ) wwidth = width
        ! inner
        doinner = .false.
        if( present(inner) ) doinner = .true.
        ! soft/hard
        if( which=='soft' )then
            soft = .true.
        else if( which=='hard' )then
            soft = .false. !!
        else
            stop 'undefined which parameter; mask; simple_image'
        endif
        ! msksum
        domsksum = .false.
        if( present(msksum) )then
            msksum   = 0.
            domsksum = .true.
        endif
        ! FT
        didft = .false.
        if( self%ft )then
            call self%bwd_ft
            didft = .true.
        endif
        ! minlen
        if( self%is_3d() )then
            minlen = minval(self%ldim)
        else
            minlen = minval(self%ldim(1:2))
        endif
        ! init center as origin
        forall(i=1:self%ldim(1)) cis(i) = -real(self%ldim(1)-1)/2. + real(i-1)
        forall(i=1:self%ldim(2)) cjs(i) = -real(self%ldim(2)-1)/2. + real(i-1)
        if(self%is_3d())forall(i=1:self%ldim(3)) cks(i) = -real(self%ldim(3)-1)/2. + real(i-1)
        ! Main loops
        if( .not.domsksum )then
            ! MASKING
            if( soft )then
                ! Soft masking
                if( self%is_3d() )then
                    ! 3d
                    do i=1,self%ldim(1)/2
                        ir = self%ldim(1)+1-i
                        do j=1,self%ldim(2)/2
                            jr = self%ldim(2)+1-j
                            do k=1,self%ldim(3)/2
                                kr = self%ldim(3)+1-k
                                e = cosedge(cis(i),cjs(j),cks(k),minlen,mskrad)
                                if( doinner )e = e * cosedge_inner(cis(i),cjs(j),cks(k),wwidth,inner)
                                if(e > 0.9999)cycle
                                self%rmat(i,j,k)    = e * self%rmat(i,j,k)
                                self%rmat(i,j,kr)   = e * self%rmat(i,j,kr)
                                self%rmat(i,jr,k)   = e * self%rmat(i,jr,k)
                                self%rmat(i,jr,kr)  = e * self%rmat(i,jr,kr)
                                self%rmat(ir,j,k)   = e * self%rmat(ir,j,k)
                                self%rmat(ir,j,kr)  = e * self%rmat(ir,j,kr)
                                self%rmat(ir,jr,k)  = e * self%rmat(ir,jr,k)
                                self%rmat(ir,jr,kr) = e * self%rmat(ir,jr,kr)
                            enddo
                        enddo
                    enddo
                else
                    ! 2d
                    do i=1,self%ldim(1)/2
                        ir = self%ldim(1)+1-i
                        do j=1,self%ldim(2)/2
                            jr = self%ldim(2)+1-j
                            e = cosedge(cis(i),cjs(j),minlen,mskrad)
                            if( doinner )e = e * cosedge_inner(cis(i),cjs(j),wwidth,inner)
                            if(e > 0.9999)cycle
                            self%rmat(i,j,1)   = e * self%rmat(i,j,1)
                            self%rmat(i,jr,1)  = e * self%rmat(i,jr,1)
                            self%rmat(ir,j,1)  = e * self%rmat(ir,j,1)
                            self%rmat(ir,jr,1) = e * self%rmat(ir,jr,1)
                        enddo
                    enddo                
                endif
            else
                ! Hard masking
                if( self%is_3d() )then
                    ! 3d
                    do i=1,self%ldim(1)/2
                        ir = self%ldim(1)+1-i
                        do j=1,self%ldim(2)/2
                            jr = self%ldim(2)+1-j
                            do k=1,self%ldim(3)/2
                                kr = self%ldim(3)+1-k
                                e = hardedge(cis(i),cjs(j),cks(k),mskrad)
                                if( doinner )e = e * hardedge_inner(cis(i),cjs(j),cks(k),inner)
                                self%rmat(i,j,k)    = e * self%rmat(i,j,k)
                                self%rmat(i,j,kr)   = e * self%rmat(i,j,kr)
                                self%rmat(i,jr,k)   = e * self%rmat(i,jr,k)
                                self%rmat(i,jr,kr)  = e * self%rmat(i,jr,kr)
                                self%rmat(ir,j,k)   = e * self%rmat(ir,j,k)
                                self%rmat(ir,j,kr)  = e * self%rmat(ir,j,kr)
                                self%rmat(ir,jr,k)  = e * self%rmat(ir,jr,k)
                                self%rmat(ir,jr,kr) = e * self%rmat(ir,jr,kr)
                            enddo
                        enddo
                    enddo
                else
                    ! 2d
                    do i=1,self%ldim(1)/2
                        ir = self%ldim(1)+1-i
                        do j=1,self%ldim(2)/2
                            jr = self%ldim(2)+1-j
                            e = hardedge(cis(i),cjs(j),mskrad)
                            if( doinner )e = e * hardedge_inner(cis(i),cjs(j),inner)
                            self%rmat(i,j,1)   = e * self%rmat(i,j,1)
                            self%rmat(i,jr,1)  = e * self%rmat(i,jr,1)
                            self%rmat(ir,j,1)  = e * self%rmat(ir,j,1)
                            self%rmat(ir,jr,1) = e * self%rmat(ir,jr,1)
                        enddo
                    enddo
                endif
            endif
        else
            ! MASK SUM
            do i=1,self%ldim(1)
                ci = cis(i)
                do j=1,self%ldim(2)
                    cj = cjs(j)
                    if( self%is_3d() )then
                        ! 3D
                        do k=1,self%ldim(3)
                            ck = cks(k)
                            if( soft )then ! soft
                                e = cosedge(ci,cj,ck,minlen,mskrad)
                                if( doinner )e = e*cosedge_inner(ci,cj,ck,wwidth,inner)
                            else ! hard
                                e = hardedge(ci,cj,ck,mskrad)
                                if( doinner )e = e*hardedge_inner(ci,cj,ck,inner)
                            endif
                            msksum = msksum+e**2.
                        end do
                    else
                        ! 2D
                        if( soft )then ! soft
                            e = cosedge(ci,cj,minlen,mskrad)
                            if( doinner )e = e*cosedge_inner(ci,cj,wwidth,inner)
                        else ! hard
                            e = hardedge(ci,cj,mskrad)
                            if( doinner )e = e*hardedge_inner(ci,cj,inner)
                        endif
                        msksum = msksum+e**2.
                    endif
                end do
            end do
        endif
        if( didft ) call self%fwd_ft
    end subroutine mask

    !>  \brief  is for calculating the fractional area/volume of the mask
    function fmaskv_1( self, mskrad, which, inner, width ) result( frac )
        class(image), intent(inout) :: self
        real, intent(in)            :: mskrad
        character(len=*)            :: which
        real, intent(in), optional  :: inner, width
        real                        :: frac, sum_masked, sum_unmasked
        if( self%imgkind .eq. 'xfel' ) stop 'masking of xfel-kind images not allowed; simple_image::fmaskv_1'
        sum_unmasked = product( self%get_ldim() )
        call self%mask(mskrad, which, inner=inner, width=width, msksum=sum_masked)
        frac = sum_masked/sum_unmasked
    end function fmaskv_1

    !>  \brief  is for calculating the fractional area/volume of the mask
    function fmaskv_2( self ) result( frac )
        class(image), intent(inout) :: self
        real                        :: frac, sum_masked, sum_unmasked
        if( self%imgkind .eq. 'xfel' ) stop 'masking of xfel-kind images not allowed; simple_image::fmaskv_2'
        if( self%ft ) stop 'need real-valued mask; fmaskv_2; simple_image'
        sum_unmasked = product(self%ldim)
        sum_masked = sum(self%rmat(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3))**2.)
        frac = sum_masked/sum_unmasked
    end function fmaskv_2

    !>  \brief  is for inverting the contrast
    subroutine neg( self )
        class(image), intent(inout) :: self
        logical :: didft
        didft = .false.
        if( self%ft )then
        else
            call self%fwd_ft
            didft = .true.
        endif
        call self%mul(-1.)
        if( didft ) call self%bwd_ft
    end subroutine neg

    !>  \brief for image resizing using nearest neighbor interpolation
    subroutine resize_nn( self_in, self_out )
        class(image), intent(inout) :: self_in, self_out
        real    :: tx, ty, tz
        integer :: i, j, k, x, y, z
        logical :: didft
        if( self_in%imgkind .eq. 'xfel' .or. self_out%imgkind .eq. 'xfel' )&
        stop 'not implemented for xfel-kind images; simple_image::resize_nn'
        didft = .false.
        if( self_in%ft )then
            call self_in%bwd_ft
            didft = .true.
        endif
        tx = real(self_in%ldim(1))/real(self_out%ldim(1))
        ty = real(self_in%ldim(2))/real(self_out%ldim(2))
        tz = real(self_in%ldim(3))/real(self_out%ldim(3))
        do i=1,self_out%ldim(1)
            do j=1,self_out%ldim(2)
                do k=1,self_out%ldim(3)
                    x = ceiling(real(i)*tx)
                    y = ceiling(real(j)*ty)
                    z = ceiling(real(k)*tz)
                    self_out%rmat(i,j,k) = self_in%rmat(x,y,z)
                end do
            end do
        end do
        if( didft ) call self_in%fwd_ft
        self_out%ft = .false.
    end subroutine resize_nn

    !>  \brief for image resizing using bilinear interpolation
    subroutine resize_bilin( self_in, self_out )
        class(image), intent(inout) :: self_in, self_out
        real    :: tx, ty, x_diff, y_diff !, maxpix, minpix
        integer :: i, j, x, y
        logical :: didft
        if( self_in%imgkind .eq. 'xfel' .or.  self_out%imgkind .eq. 'xfel' )&
        stop 'not implemented for xfel-kind images; simple_image::resize_bilin'
        if( self_in%is_2d() .and. self_out%is_2d() )then
        else
            stop 'only 4 2D images; resize_bilin; simple_image'
        endif
        didft = .false.
        if( self_in%ft )then
            call self_in%bwd_ft
            didft = .true.
        endif
        tx = real(self_in%ldim(1))/real(self_out%ldim(1))
        ty = real(self_in%ldim(2))/real(self_out%ldim(2))
        do i=1,self_out%ldim(1)
            do j=1,self_out%ldim(2)
                x = int(real(i)*tx)
                y = int(real(j)*ty)
                x_diff = real(i)*tx-real(x)
                y_diff = real(j)*ty-real(y)
                self_out%rmat(i,j,1) = self_in%rmat(x,y,1)*(1.-x_diff)*(1.-y_diff)+&
                self_in%rmat(x+1,y,1)*(1.-y_diff)*x_diff+&
                self_in%rmat(x,y+1,1)*y_diff*(1.-x_diff)+&
                self_in%rmat(x+1,y+1,1)*x_diff*y_diff
                if( is_a_number(self_out%rmat(i,j,1)) )then
                else
                    x = ceiling(real(i)*tx)
                    y = ceiling(real(j)*ty)
                    self_out%rmat(i,j,1) = self_in%rmat(x,y,1)
                endif
            end do
        end do
        if( didft ) call self_in%fwd_ft
        self_out%ft = .false.
    end subroutine resize_bilin

    !>  \brief is a constructor that pads the input image to input ldim
    subroutine pad( self_in, self_out, backgr )
        use simple_winfuns, only: winfuns
        class(image), intent(inout)   :: self_in, self_out
        real, intent(in), optional    :: backgr
        real                          :: w, ratio
        integer                       :: starts(3), stops(3), lims(3,2)
        integer                       :: h, k, l, phys_in(3), phys_out(3)
        real, allocatable             :: antialw(:)
        if( .not. self_in%same_kind(self_out) )then
            stop 'images not of same kind (xfel/em); simple_image::pad'
        endif
        if( self_in.eqdims.self_out )then
            self_out = self_in
            return
        endif
        if( self_out%ldim(1) >= self_in%ldim(1) .and. self_out%ldim(2) >= self_in%ldim(2)&
        .and. self_out%ldim(3) >= self_in%ldim(3) )then
            if( self_in%ft )then
                self_out = cmplx(0.,0.)
                if( self_in%imgkind .eq. 'xfel' )then
                    lims = self_in%fit%loop_lims(2)
                    !$omp parallel do collapse(3) schedule(auto) default(shared) private(h,k,l,w,phys_out,phys_in)
                    do h=lims(1,1),lims(1,2)
                        do k=lims(2,1),lims(2,2)
                            do l=lims(3,1),lims(3,2)
                                self_out%cmat(h,k,l)=self_in%cmat(h,k,l)
                            end do
                        end do
                    end do
                    !$omp end parallel do
                    self_out%ft = .true.
                else
                    antialw = self_in%hannw()
                    lims = self_in%fit%loop_lims(2)
                    !$omp parallel do collapse(3) schedule(auto) default(shared) private(h,k,l,w,phys_out,phys_in)
                    do h=lims(1,1),lims(1,2)
                        do k=lims(2,1),lims(2,2)
                            do l=lims(3,1),lims(3,2)
                                w = antialw(max(1,abs(h)))*antialw(max(1,abs(k)))*antialw(max(1,abs(l)))
                                phys_out = self_out%fit%comp_addr_phys([h,k,l])
                                phys_in  = self_in%fit%comp_addr_phys([h,k,l])
                                self_out%cmat(phys_out(1),phys_out(2),phys_out(3))=&
                                self_in%cmat(phys_in(1),phys_in(2),phys_in(3))*w
                            end do
                        end do
                    end do
                    !$omp end parallel do
                    deallocate(antialw)
                    ratio = real(self_in%ldim(1))/real(self_out%ldim(1))
                    self_out%smpd = self_in%smpd*ratio ! padding Fourier transform, so sampling is finer
                    self_out%ft = .true.
                endif
            else
                starts = (self_out%ldim-self_in%ldim)/2+1
                stops  = self_out%ldim-starts+1
                if( self_in%ldim(3) == 1 )then
                    starts(3) = 1
                    stops(3)  = 1
                endif
                if( present(backgr) )then
                    self_out%rmat = backgr
                else
                    self_out%rmat = 0.
                endif
                !$omp parallel workshare
                self_out%rmat(starts(1):stops(1),starts(2):stops(2),starts(3):stops(3)) =&
                self_in%rmat(:self_in%ldim(1),:self_in%ldim(2),:self_in%ldim(3))
                !$omp end parallel workshare
                self_out%ft = .false.
            endif
        endif
    end subroutine pad

    !>  \brief is a constructor that clips the input image to input ldim
    subroutine clip( self_in, self_out )
        use simple_winfuns, only: winfuns
        class(image), intent(inout) :: self_in, self_out
        real                        :: ratio
        integer                     :: starts(3), stops(3), lims(3,2)
        integer                     :: phys_out(3), phys_in(3), h, k, l
        if( .not. self_in%same_kind(self_out) )then
            stop 'images not of same kind (xfel/em); simple_image::clip'
        endif
        if( self_in.eqdims.self_out )then
            self_out = self_in
            return
        endif
        if( self_out%ldim(1) <= self_in%ldim(1) .and. self_out%ldim(2) <= self_in%ldim(2)&
        .and. self_out%ldim(3) <= self_in%ldim(3) )then
            if( self_in%ft )then
                lims = self_out%fit%loop_lims(2)
                !$omp parallel do collapse(3) schedule(auto) default(shared) private(h,k,l,phys_out,phys_in)
                do h=lims(1,1),lims(1,2)
                    do k=lims(2,1),lims(2,2)
                        do l=lims(3,1),lims(3,2)
                            phys_out = self_out%fit%comp_addr_phys([h,k,l])
                            phys_in = self_in%fit%comp_addr_phys([h,k,l])
                            self_out%cmat(phys_out(1),phys_out(2),phys_out(3)) =&
                            self_in%cmat(phys_in(1),phys_in(2),phys_in(3))
                        end do
                    end do
                end do
                !$omp end parallel do
                if( self_in%imgkind .eq. 'xfel' )then
                    self_out%smpd = self_in%smpd
                else
                    ratio = real(self_in%ldim(1))/real(self_out%ldim(1))
                    self_out%smpd = self_in%smpd*ratio ! clipping Fourier transform, so sampling is coarser
                endif
                self_out%ft = .true.
            else
                starts = (self_in%ldim-self_out%ldim)/2+1
                stops  = self_in%ldim-starts+1
                if( self_in%ldim(3) == 1 )then
                    starts(3) = 1
                    stops(3)  = 1
                endif
                !$omp parallel workshare
                self_out%rmat(:self_out%ldim(1),:self_out%ldim(2),:self_out%ldim(3))&
                = self_in%rmat(starts(1):stops(1),starts(2):stops(2),starts(3):stops(3))
                !$omp end parallel workshare
                self_out%ft = .false.
            endif
        endif
    end subroutine clip

    !>  \brief is a constructor that clips the input image to input ldim
    subroutine clip_inplace( self, ldim )
        class(image), intent(inout) :: self
        integer, intent(in)         :: ldim(3)
        type(image)                 :: tmp
        call tmp%new(ldim, self%smpd)
        call self%clip(tmp)
        self = tmp
        call tmp%kill
    end subroutine clip_inplace

    !>  \brief  is for mirroring an image
    !!          mirror('x') corresponds to mirror2d
    subroutine mirror( self, md )
        class(image), intent(inout) :: self
        character(len=*), intent(in) :: md
        integer :: i, j
        logical :: didft
        if( self%imgkind .eq. 'xfel' ) stop 'not implemented for xfel-kind images; simple_image::mirror'
        didft = .false.
        if( self%ft )then
            call self%bwd_ft
            didft = .true.
        endif
        if( md == 'x' )then
            do i=1,self%ldim(2)
                do j=1,self%ldim(3)
                    call reverse(self%rmat(1:self%ldim(1),i,j))
                end do
            end do
        else if( md == 'y' )then
            do i=1,self%ldim(1)
                do j=1,self%ldim(3)
                    call reverse(self%rmat(i,1:self%ldim(2),j))
                end do
            end do
        else if( md == 'z' )then
            do i=1,self%ldim(1)
                do j=1,self%ldim(2)
                    call reverse(self%rmat(i,j,1:self%ldim(3)))
                end do
            end do
        else
            write(*,'(a)') 'Mode needs to be either x, y or z; mirror; simple_image'
        endif
        if( didft ) call self%fwd_ft
    end subroutine mirror

    !>  \brief  is for statistical normalization of an image
    subroutine norm( self, hfun, err )
        class(image), intent(inout)            :: self
        character(len=*), intent(in), optional :: hfun
        logical, intent(out), optional         :: err
        integer :: n_nans
        real    :: maxv, minv, ave, sdev
        if( self%ft )then
            write(*,*) 'WARNING: Cannot normalize FTs; norm; simple_image'
            return
        endif
        call self%cure(maxv, minv, ave, sdev, n_nans)
        if( self%ldim(3) > 1 )then
            if( present(hfun) ) call normalize_sigm(self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)))
        else
            if( present(hfun) ) call normalize_sigm(self%rmat(:self%ldim(1),:self%ldim(2),1))
        endif
        if( sdev > 0. )then
            if( present(err) ) err = .false.
        else
            write(*,'(a)') 'WARNING, undefined variance; norm; simple_image'
            if( present(err) ) err = .true.
        endif
    end subroutine norm

    !>  \brief  is for normalization of an image using inputted average and standard deviation
    subroutine norm_ext( self, avg, sdev )
        class(image), intent(inout) :: self
        real, intent(in)            :: avg, sdev
        if( self%ft )then
            write(*,*) 'WARNING: Cannot normalize FTs; norm_ext; simple_image'
            return
        endif
        self%rmat = (self%rmat-avg)/sdev
    end subroutine norm_ext

    !>  \brief  normalizes the image according to the background noise
    subroutine noise_norm( self, msk, errout )
        class(image),      intent(inout) :: self
        real,              intent(in)    :: msk
        logical, optional, intent(out)   :: errout
        type(image)       :: maskimg
        integer           :: npix,nbackgr,npix_tot
        real              :: med,ave,sdev,var
        real, allocatable :: pixels(:)
        logical           :: err
        if( self%ft )then
            write(*,*) 'WARNING: Cannot normalize FTs; noise_norm; simple_image'
            return
        endif
        call maskimg%disc(self%ldim, self%smpd, msk, npix)
        npix_tot = product(self%ldim)
        nbackgr = npix_tot-npix
        pixels = pack( self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)),&
            &maskimg%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)) < 0.5 )
        med = median_nocopy(pixels)
        call moment(pixels, ave, sdev, var, err)
        deallocate(pixels)
        if( err )then
            call self%norm
        else
            ! we subtract the pixel values with this ruboust estimate of the background average
            self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)) =&
            (self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3))-med)
            if( present(errout) )then
                errout = err
            else
                if( err ) write(*,'(a)') 'WARNING: variance zero; noise_norm; simple_image'
            endif
            if( sdev > 1e-6 )then
                self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)) =&
                self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3))/sdev
            endif
        endif
    end subroutine noise_norm

    !>  \brief  normalizes the image based on a central sphere of input radius
    subroutine radius_norm( self, radius, errout )
        class(image),      intent(inout) :: self
        real,    optional, intent(in)    :: radius
        logical, optional, intent(out)   :: errout
        type(image)       :: maskimg
        integer           :: npix
        real              :: ave,sdev,var,irad
        real, allocatable :: pixels(:)
        logical           :: err
        if( self%ft )then
            write(*,*) 'WARNING: Cannot normalize FTs; noise_norm; simple_image'
            return
        endif
        if( .not.present(radius) )then
            irad = real(self%ldim(1)+1)/2.
        else
            irad = radius
        endif
        if( irad<=0. )stop 'Invalid radius value in rad_norm'
        call maskimg%disc(self%ldim, self%smpd, irad, npix)
        ! pixels = self%packer(maskimg) ! Intel hickup
        pixels = pack( self%rmat, maskimg%rmat > 0.5 )
        call moment( pixels, ave, sdev, var, err )
        deallocate(pixels)
        if( err )then
            call self%norm
        else
            self%rmat = self%rmat - ave
            if( present(errout) )then
                errout = err
            else
                if( err ) write(*,'(a)') 'WARNING: variance zero; rad_norm; simple_image'
            endif
            if( sdev > 1e-6 )self%rmat = self%rmat / sdev
        endif
    end subroutine radius_norm

    !>  \brief  is for [0,1] interval normalization of an image
    subroutine norm_bin( self )
        class(image), intent(inout) :: self
        real                        :: smin, smax
        logical                     :: didft
        if( self%imgkind .eq. 'xfel' ) stop 'not implemented for xfel-kind images; simple_image::norm_bin'
        didft = .false.
        if( self%ft )then
            call self%bwd_ft
            didft = .true.
        endif
        ! find minmax
        smin  = minval(self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)))
        smax  = maxval(self%rmat(:self%ldim(1),:self%ldim(2),:self%ldim(3)))
        ! create [0,1]-normalized image
        self%rmat = (self%rmat - smin)  / (smax-smin)
        self%rmat = (exp(self%rmat)-1.) / (exp(1.)-1.)
        if( didft ) call self%fwd_ft
    end subroutine norm_bin

    !>  \brief  is for creating a rotation average of self
    subroutine roavg(self, angstep, avg)
        class(image), intent(inout) :: self
        real, intent(in)            :: angstep
        class(image), intent(inout) :: avg
        type(image)                 :: rotated
        real                        :: ang, div
        if( self%imgkind .eq. 'xfel' ) stop 'not implemented for xfel-kind images; simple_image::roavg'
        call rotated%copy(self)
        call avg%copy(self)
        rotated = 0.
        avg     = 0.
        ang     = 0.
        div     = 0.
        do while(ang < 359.99 )
            call self%rtsq(ang, 0., 0., rotated)
            avg = avg+rotated
            ang = ang+angstep
            div = div+1.
        end do
        call avg%div(div)
        call rotated%kill
    end subroutine roavg

    !>  \brief  rotation of image by quadratic interpolation (from spider)
    subroutine rtsq(self_in, ang, shxi, shyi, self_out)
        class(image),           intent(inout) :: self_in
        real,                   intent(in)    :: ang,shxi,shyi
        class(image), optional, intent(inout) :: self_out
        type(image) :: self_here
        real    :: shx,shy,ry1,rx1,ry2,rx2,cod,sid,xi
        real    :: fixcenmshx,fiycenmshy
        real    :: rye2,rye1,rxe2,rxe1,yi
        real    :: ycod,ysid,yold,xold
        integer :: iycen,ixcen,ix,iy
        real    :: mat_in(self_in%ldim(1),self_in%ldim(2))
        real    :: mat_out(self_in%ldim(1),self_in%ldim(2))
        logical :: didft
        if( self_in%imgkind .eq. 'xfel' ) stop 'not implemented for xfel-kind images; simple_image::rtsq'
        if( self_in%ldim(3) > 1 ) stop 'only for 2D images; rtsq; simple_image'
        if( .not. self_in%square_dims() ) stop 'only for square dims (need to sort shifts out); rtsq; simple_image'
        call self_here%new(self_in%ldim, self_in%smpd)
        didft = .false.
        if( self_in%ft )then
            call self_in%bwd_ft
            didft = .true.
        endif
        mat_out = 0. ! this is necessary, because it bugs out if I try to use the 3D matrix
        mat_in = self_in%rmat(:self_in%ldim(1),:self_in%ldim(2),1)
        ! shift within image boundary
        shx = amod(shxi,float(self_in%ldim(1)))
        shy = amod(shyi,float(self_in%ldim(2)))
        ! spider image center
        iycen = self_in%ldim(1)/2+1
        ixcen = self_in%ldim(2)/2+1
        ! image dimensions around origin
        rx1 = -self_in%ldim(1)/2
        rx2 =  self_in%ldim(1)/2
        ry1 = -self_in%ldim(2)/2
        ry2 =  self_in%ldim(2)/2
        if(mod(self_in%ldim(1),2) == 0)then
            rx2  =  rx2-1.0
            rxe1 = -self_in%ldim(1)
            rxe2 =  self_in%ldim(1)
        else
            rxe1 = -self_in%ldim(1)-1
            rxe2 =  self_in%ldim(1)+1
        endif
        if(mod(self_in%ldim(2),2) == 0)then
            ry2  =  ry2-1.0
            rye1 = -self_in%ldim(2)
            rye2 =  self_in%ldim(2)
        else
            ry2  = -self_in%ldim(2)-1
            rye2 =  self_in%ldim(2)+1
        endif
        ! create transformation matrix
        cod = cos(deg2rad(ang))
        sid = sin(deg2rad(ang))
        !-(center plus shift)
        fixcenmshx = -ixcen-shx
        fiycenmshy = -iycen-shy
        !$omp parallel do default(shared) private(iy,yi,ycod,ysid,ix,xi,xold,yold) schedule(auto)
        do iy=1,self_in%ldim(2)
            yi = iy+fiycenmshy
            if(yi < ry1) yi = min(yi+rye2, ry2)
            if(yi > ry2) yi = max(yi+rye1, ry1)
            ycod =  yi*cod+iycen
            ysid = -yi*sid+ixcen
            do ix=1,self_in%ldim(1)
                xi = ix+fixcenmshx
                if(xi < rx1) xi = min(xi+rxe2, rx2)
                if(xi > rx2) xi = max(xi+rxe1, rx1)
                yold = xi*sid+ycod
                xold = xi*cod+ysid
                mat_out(ix,iy) = quadri(xold,yold,mat_in,self_in%ldim(1),self_in%ldim(2))
            enddo
        enddo
        !$omp end parallel do
        self_here%rmat(:self_here%ldim(1),:self_here%ldim(2),1) = mat_out
        self_here%ft = .false.
        if( present(self_out) )then
            self_out = self_here
        else
            self_in = self_here
        endif
        call self_here%kill
        if( didft )then
            call self_in%bwd_ft
        endif
    end subroutine rtsq

    !>  \brief  for replacing extreme outliers with median of a 13x13 neighbourhood window
    !!          only done on negative values, assuming white ptcls on black bkgr
    subroutine cure_outliers( self, ncured, nsigma, deadhot, outliers )
        !$ use omp_lib
        !$ use omp_lib_kinds
        use simple_stat, only: moment
        class(image),      intent(inout) :: self
        integer,           intent(inout) :: ncured
        real,              intent(in)    :: nsigma
        integer,           intent(out)   :: deadhot(2)
        logical, optional, allocatable   :: outliers(:,:) 
        real, allocatable :: win(:,:), rmat_pad(:,:)
        real    :: ave, sdev, var, lthresh, uthresh
        integer :: i, j, alloc_stat, hwinsz, winsz
        logical :: was_fted, err, present_outliers
        if( self%ldim(3)>1 )stop 'for images only; simple_image::cure_outliers'
        if( was_fted )stop 'for real space images only; simple_image::cure_outliers'
        present_outliers = present(outliers)
        ncured   = 0
        hwinsz   = 6
        was_fted = self%is_ft()        
        if( allocated(outliers) ) deallocate(outliers)
        allocate( outliers(self%ldim(1),self%ldim(2)) )
        outliers = .false.
        call moment( self%rmat, ave, sdev, var, err )
        if( sdev<TINY )return
        lthresh = ave - nsigma * sdev
        uthresh = ave + nsigma * sdev
        if( any(self%rmat<=lthresh) .or. any(self%rmat>=uthresh) )then
            winsz = 2*hwinsz+1
            deadhot = 0
            allocate(rmat_pad(1-hwinsz:self%ldim(1)+hwinsz,1-hwinsz:self%ldim(2)+hwinsz),&
                &win(winsz,winsz), stat=alloc_stat)
            call alloc_err('In: cure_outliers; simple_image 1', alloc_stat)
            rmat_pad(:,:) = median( reshape(self%rmat(:,:,1), (/(self%ldim(1)*self%ldim(2))/)) )
            rmat_pad(1:self%ldim(1), 1:self%ldim(2)) = &
                &self%rmat(1:self%ldim(1),1:self%ldim(2),1)
            !$omp parallel do schedule(auto) default(shared) private(i,j,win)&
            !$omp reduction(+:ncured)
            do i=1,self%ldim(1)
                do j=1,self%ldim(2)
                    if( self%rmat(i,j,1)<lthresh .or. self%rmat(i,j,1)>uthresh )then
                        if( present_outliers )then
                            outliers(i,j)=.true.
                            if (self%rmat(i,j,1)<lthresh) deadhot(1) = deadhot(1) + 1
                            if (self%rmat(i,j,1)>uthresh) deadhot(2) = deadhot(2) + 1
                        else
                            win = rmat_pad( i-hwinsz:i+hwinsz, j-hwinsz:j+hwinsz )
                            self%rmat(i,j,1) = median( reshape(win,(/winsz**2/)) )
                            ncured = ncured + 1
                        endif
                    endif
                enddo
            enddo
            !$omp end parallel do
            deallocate( win, rmat_pad )
        endif
    end subroutine cure_outliers

    !>  \brief  is the image class unit test
    subroutine test_image( doplot )
        logical, intent(in)  :: doplot
        write(*,'(a)') '**info(simple_image_unit_test): testing square dimensions'
        call test_image_local( 100, 100, 100, doplot )
        write(*,'(a)') '**info(simple_image_unit_test): testing non-square dimensions'
        call test_image_local( 120, 90, 80, doplot )
        write(*,'(a)') 'SIMPLE_IMAGE_UNIT_TEST COMPLETED SUCCESSFULLY ;-)'

        contains

            subroutine test_image_local( ld1, ld2, ld3, doplot )
                integer, intent(in)  :: ld1, ld2, ld3
                logical, intent(in)  :: doplot
                type(image)          :: img, img_2, img_3, img_4, img3d
                type(image)          :: imgs(20)
                complex, allocatable :: fplane_simple(:,:), fplane_frealix(:,:)
                integer              :: i, j, k, cnt, lfny, ldim(3)
                real                 :: input, msk, ave, sdev, var, med, xyz(3), pow
                real                 :: imcorr, recorr, corr, corr_lp
                real, allocatable    :: pcavec1(:), pcavec2(:), spec(:), res(:)
                real                 :: smpd=2.
                logical              :: passed, test(6)

                write(*,'(a)') '**info(simple_image_unit_test, part 1): testing basal constructors'
                !img = image([ld1,ld2], 1.)     ! Program received signal SIGSEGV: Segmentation fault - invalid memory reference. Need to update gfortran.
                !img3d = image([ld1,ld2,ld3], 1.) ! Program received signal SIGBUS: Access to an undefined portion of a memory object. Need to update gfortran.
                call img%new([ld1,ld2,1], 1.)
                call img_3%new([ld1,ld2,1], 1.)
                call img3d%new([ld1,ld2,ld3], 1.)
                if( .not. img%exists() ) stop 'ERROR, in constructor or in exists function, 1'
                if( .not. img3d%exists() ) stop 'ERROR, in constructor or in exists function, 2'

                write(*,'(a)') '**info(simple_image_unit_test, part 2): testing getters/setters'
                passed = .true.
                cnt = 1
                do i=1,ld1
                    do j=1,ld2
                        input = real(cnt)
                        call img%set([i,j,1], input)
                        if( img%get([i,j,1]) /= input) passed = .false.
                        do k=1,ld3
                            input = real(cnt)
                            call img3d%set([i,j,k],input)
                            if( img3d%get([i,j,k]) /= input) passed = .false.
                            cnt = cnt+1
                        end do
                    end do
                end do
                if( .not. passed )  stop 'getters/setters test failed'

                write(*,'(a)') '**info(simple_image_unit_test, part 3): testing serialization'
                passed = .false.
                msk = 50.
                img_2 = img
                call img%ran
                if( doplot ) call img%vis
                call img%serialize(pcavec1, msk)
                img = 0.
                call img%serialize(pcavec1, msk)
                if( doplot ) call img%vis
                call img_2%serialize(pcavec1, msk)
                call img_2%serialize(pcavec2, msk)
                if( pearsn(pcavec1, pcavec2) > 0.99 ) passed = .true.
                if( .not. passed ) stop 'serialization test failed'

                write(*,'(a)') '**info(simple_image_unit_test, part 4): testing checkups'
                test(1) = img%even_dims()
                if( ld1 == ld2 )then
                    test(2) = img%square_dims()
                else
                    test(2) = .not. img%square_dims()
                endif
                test(3) = img.eqdims.img_2
                test(4) = img.eqsmpd.img_2
                test(5) = img%is_2d()
                test(6) = .not. img%is_3d()
                passed = all(test)
                if( .not. passed ) stop 'checkups test failed'

                write(*,'(a)') '**info(simple_image_unit_test, part 5): testing arithmetics'
                if( allocated(pcavec1) ) deallocate(pcavec1)
                if( allocated(pcavec2) ) deallocate(pcavec2)
                passed = .false.
                msk = 50.
                call img%ran
                call img%serialize(pcavec1, msk)
                img_2 = img
                call img_2%serialize(pcavec2, msk)
                if( pearsn(pcavec1, pcavec2) > 0.99 ) passed = .true.
                if( .not. passed ) stop 'polymorphic assignment test 1 failed'
                passed = .false.
                img = 5.
                img_2 = 10.
                img_3 = img_2-img
                call img%serialize(pcavec1, msk)
                call img_3%serialize(pcavec2, msk)
                if( euclid(pcavec1, pcavec2) < 0.0001 ) passed = .true.
                if( .not. passed ) stop 'overloaded subtraction test failed'
                passed = .false.
                if( allocated(pcavec1) ) deallocate(pcavec1)
                if( allocated(pcavec2) ) deallocate(pcavec2)
                img = 5.
                img_2 = 10.
                img_3 = 15.
                img_4 = img + img_2
                call img_3%serialize(pcavec1, msk)
                call img_4%serialize(pcavec2, msk)
                if( euclid(pcavec1, pcavec2) < 0.0001 ) passed = .true.
                if( .not. passed ) stop 'overloaded addition test failed'
                passed = .false.
                if( allocated(pcavec1) ) deallocate(pcavec1)
                if( allocated(pcavec2) ) deallocate(pcavec2)
                img = 5.
                img_2 = 2.
                img_3 = 10.
                img_4 = img*img_2
                call img_3%serialize(pcavec1, msk)
                call img_4%serialize(pcavec2, msk)
                if( euclid(pcavec1, pcavec2) < 0.0001 ) passed = .true.
                if( .not. passed ) stop 'overloaded multiplication test failed'
                passed = .false.
                if( allocated(pcavec1) ) deallocate(pcavec1)
                if( allocated(pcavec2) ) deallocate(pcavec2)
                img_4 = img_3/img_2
                call img%serialize(pcavec1, msk)
                call img_4%serialize(pcavec2, msk)
                if( euclid(pcavec1, pcavec2) < 0.0001 ) passed = .true.
                if( .not. passed ) stop 'overloaded division test failed'
                passed = .false.
                if( allocated(pcavec1) ) deallocate(pcavec1)
                if( allocated(pcavec2) ) deallocate(pcavec2)
                img = 0.
                img_2 = 5.
                img_3 = 1.
                do i=1,5
                    call img%add(img_3 )
                end do
                call img_2%serialize(pcavec1, msk)
                call img%serialize(pcavec2, msk)
                if( euclid(pcavec1, pcavec2) < 0.0001 ) passed = .true.
                if( .not. passed ) stop 'summation test failed'
                passed = .false.
                if( allocated(pcavec1) ) deallocate(pcavec1)
                if( allocated(pcavec2) ) deallocate(pcavec2)
                do i=1,5
                    call img%subtr(img_3)
                end do
                img_2 = 0.
                call img_2%serialize(pcavec1, msk)
                call img%serialize(pcavec2, msk)
                if( euclid(pcavec1, pcavec2) < 0.0001 ) passed = .true.
                if( .not. passed ) stop 'subtraction test failed'
                passed = .false.
                if( allocated(pcavec1) ) deallocate(pcavec1)
                if( allocated(pcavec2) ) deallocate(pcavec2)
                img_2 = 5.
                img_3 = 1.
                call img_2%div(5.)
                call img_2%serialize(pcavec1, msk)
                call img_3%serialize(pcavec2, msk)
                if( euclid(pcavec1, pcavec2) < 0.0001 ) passed = .true.
                if( .not. passed ) stop 'constant division test failed'

                write(*,'(a)') '**info(simple_image_unit_test, part 6): testing stats'
                passed = .false.
                call img%gauran( 5., 15. )
                call img%stats( 'foreground', ave, sdev, var, 40., med )
                if( ave >= 4. .and. ave <= 6. .and. sdev >= 14. .and.&
                sdev <= 16. .and. med >= 4. .and. med <= 6. ) passed = .true.
                if( .not. passed )  stop 'stats test failed'

                write(*,'(a)') '**info(simple_image_unit_test, part 7): testing noise power estimation'
                passed = .false.
                call img%new([ld1,ld2,1], 1.)
                call img%gauran(0., 2.)
                spec = img%spectrum('power')
                lfny = size(spec)
                allocate(res(lfny))
                do k=1,lfny
                    res(k) = (img%get_smpd())/img%get_lp(k)
                end do
                spec = sum(spec)/real(lfny)
                write(*,*) 'correct noise power:', spec(1)
                pow = img%est_noise_pow(40.)
                write(*,*) 'estimated noise power:', pow
                if( abs(spec(1)-pow) < 1e-4 ) passed = .true.
                if( .not. passed )  stop 'noise power estimation test failed'

                write(*,'(a)') '**info(simple_image_unit_test, part 7): testing origin shift'
                if( allocated(pcavec1) ) deallocate(pcavec1)
                if( allocated(pcavec2) ) deallocate(pcavec2)
                passed = .false.
                msk=50
                call img%gauimg(10)
                if( doplot ) call img%vis
                call img%serialize(pcavec1, msk)
                call img%shift(-9.345,-5.786)
                if( doplot ) call img%vis
                call img%shift(9.345,5.786)
                call img%serialize(pcavec2, msk)
                if( doplot ) call img%vis
                if( pearsn(pcavec1, pcavec2) > 0.99 ) passed = .true.
                if( .not. passed )  stop 'origin shift test failed'

                write(*,'(a)') '**info(simple_image_unit_test, part 8): testing masscen'
                passed = .false.
                msk = 50
                if( allocated(pcavec1) ) deallocate(pcavec1)
                if( allocated(pcavec2) ) deallocate(pcavec2)
                call img%square( 10 )
                if( doplot ) call img%vis
                call img%serialize(pcavec1, msk)
                call img%shift( 10., 5. )
                if( doplot ) call img%vis
                xyz = img%masscen()
                call img%shift(real(int(xyz(1))),real(int(xyz(2))))
                if( doplot ) call img%vis
                call img%serialize(pcavec2, msk)
                if( pearsn(pcavec1, pcavec2) > 0.9 ) passed = .true.
                if( .not. passed ) stop 'masscen test failed'

                write(*,'(a)') '**info(simple_image_unit_test, part 9): testing lowpass filter'
                call img%square( 10 )
                if( doplot ) call img%vis
                call img%bp(0., 5.)
                if( doplot ) call img%vis
                call img%bp(0., 10.)
                if( doplot ) call img%vis
                call img%bp(0., 20.)
                if( doplot ) call img%vis
                call img%bp(0., 30.)
                if( doplot ) call img%vis

                write(*,'(a)') '**info(simple_image_unit_test, part 10): testing spherical mask'
                call img%ran
                if( doplot ) call img%vis
                call img%mask(35.,'hard')
                if( doplot ) call img%vis
                call img%ran
                call img%mask(35.,'soft')
                if( doplot ) call img%vis

                write(*,'(a)') '**info(simple_image_unit_test, part 11): testing padding/clipping'
                passed = .false.
                msk = 50
                if( allocated(pcavec1) ) deallocate(pcavec1)
                if( allocated(pcavec2) ) deallocate(pcavec2)
                call img%ran
                call img%serialize(pcavec1, msk)
                if( doplot ) call img%vis
                call img_2%new([2*ld1,2*ld2,1],1.)
                call img%pad(img_2)
                if( doplot ) call img_2%vis
                call img_3%new([ld1,ld2,1],1.)
                call img%clip(img_3)
                call img_3%serialize(pcavec2, msk)
                if( doplot ) call img_3%vis
                if( pearsn(pcavec1, pcavec2) > 0.99 ) passed = .true.
                if( .not. passed ) stop 'padding/clipping test failed'
                call img%square(10)
                if( doplot ) call img%vis
                call img%fwd_ft
                call img%pad(img_2)
                call img_2%bwd_ft
                if( doplot ) call img_2%vis
                call img_2%square(20)
                if( doplot ) call img_2%vis
                call img_2%fwd_ft
                call img_2%clip(img)
                call img%bwd_ft
                if( doplot ) call img%vis

                write(*,'(a)') '**info(simple_image_unit_test, part 13): testing bicubic rots'
                cnt = 0
                call img_3%square(20)
                if( ld1 == ld2 )then
                    call img_4%new([ld1,ld2,1], 1.)
                    do i=0,360,30
                        call img_3%rtsq(real(i), 0., 0., img_4)
                        cnt = cnt+1
                        if( doplot ) call img_4%vis
                    end do
                endif

                write(*,'(a)') '**info(simple_image_unit_test, part 14): testing binary imgproc routines'
                passed = .false.
                call img%gauimg(20)
                call img%norm_bin
                if( doplot ) call img%vis
                call img%bin(0.5)
                if( doplot ) call img%vis
                call img%gauimg(20)
                call img%bin(500)
                if( doplot ) call img%vis
                do i=1,10
                    call img%grow_bin
                end do
                if( doplot ) call img%vis

                write(*,'(a)') '**info(simple_image_unit_test, part 15): testing auto correlation function'
                call img%square( 10 )
                if( doplot ) call img%vis
                call img%acf
                if( doplot ) call img%vis
                call img%square( 10 )
                call img%shift( 5., -5. )
                if( doplot ) call img%vis
                call img%acf
                if( doplot ) call img%vis

                write(*,'(a)') '**info(simple_image_unit_test, part 16): testing correlation functions'
                passed = .false.
                ldim = [100,100,1]
                call img%new(ldim, smpd)
                call img_2%new(ldim, smpd)
                call img%gauimg(10)
                call img%fwd_ft
                call img_2%gauimg(13)
                call img_2%fwd_ft
                corr = img%corr(img_2)
                corr_lp = img%corr(img_2,20.)
                if( corr > 0.96 .and. corr < 0.98 .and. corr_lp > 0.96 .and. corr_lp < 0.98 ) passed = .true.
                if( .not. passed ) stop 'corr test failed'

                write(*,'(a)') '**info(simple_image_unit_test, part 17): testing downscaling'
                if( ld1 == ld2 )then
                    call img%gauimg(20)
                    if( doplot )  call img%vis
                    if( doplot ) call img_2%vis
                endif

                write(*,'(a)') '**info(simple_image_unit_test, part 18): testing logft'
                call img%square( 10 )
                if( doplot ) call img%vis
                call img%fwd_ft
                if( doplot ) call img%vis
                call img%square( 10 )
                call img%fwd_logft
                if( doplot ) call img%vis
                call img%bwd_logft
                if( doplot ) call img%vis

                if( img%square_dims() )then
                    write(*,'(a)') '**info(simple_image_unit_test, part 19): testing rotational averager'
                    call img%square( 10 )
                    if( doplot ) call img%vis
                    call img%roavg(5.,img_2)
                    if( doplot ) call img_2%vis
                endif

                write(*,'(a)') '**info(simple_image_unit_test, part 20): testing the read/write capabilities'
                ! create a square
                ldim = [120,120,1]
                call img%new(ldim, smpd)
                call img%square(20)
                ! write stacks of 5 squares
                do i=1,5
                    call img%write('squares_spider.spi',i)
                    call img%write('squares_mrc.mrc',i)
                end do
                ! convert the squares from SPIDER to MRC & vice versa
                do i=1,5
                    call img%read('squares_spider.spi',i)
                    call img%write('squares_spider_converted.mrc',i)
                    call img%read('squares_mrc.mrc',i)
                    call img%write('squares_mrc_converted.spi',i)
                end do
                ! test SPIDER vs. MRC & converted vs. nonconverted
                do i=1,20
                    call imgs(i)%new(ldim, smpd)
                end do
                cnt = 0
                do i=1,5
                    cnt = cnt+1
                    call imgs(cnt)%read('squares_spider.spi',i)
                end do
                do i=1,5
                    cnt = cnt+1
                    call imgs(cnt)%read('squares_spider_converted.mrc',i)
                end do
                do i=1,5
                    cnt = cnt+1
                    call imgs(cnt)%read('squares_mrc.mrc',i)
                end do
                do i=1,5
                    cnt = cnt+1
                    call imgs(cnt)%read('squares_mrc_converted.spi',i)
                end do
                do i=1,19
                    do j=i+1,20
                        corr = imgs(i)%corr(imgs(j))
                        if( corr < 0.99999 )then
                            stop 'SPIDER vs. MRC & converted vs. nonconverted test failed'
                        endif
                    end do
                end do
                ! create a cube
                ldim = [120,120,120]
                call img%new(ldim, smpd)
                call img%square(20)
                ! write volume files
                do i=1,5
                    call img%write('cube_spider.spi')
                    call img%write('cube_mrc.mrc')
                end do
                ! convert the cubes from SPIDER to MRC & vice versa
                do i=1,5
                    call img%read('cube_spider.spi')
                    call img%write('cube_spider_converted.mrc')
                    call img%read('cube_mrc.mrc')
                    call img%write('cube_mrc_converted.spi')
                end do
                ! test SPIDER vs. MRC & converted vs. nonconverted
                do i=1,4
                    call imgs(i)%new(ldim, smpd)
                    call imgs(i)%read('cube_spider.spi')
                    call imgs(i)%read('cube_spider_converted.mrc')
                    call imgs(i)%read('cube_mrc.mrc')
                    call imgs(i)%read('cube_mrc_converted.spi')
                end do
                do i=1,3
                    do j=i+1,4
                        corr = imgs(i)%corr(imgs(j))
                        if( corr < 0.99999 )then
                            stop 'SPIDER vs. MRC & converted vs. nonconverted test failed'
                        endif
                    end do
                end do

                write(*,'(a)') '**info(simple_image_unit_test, part 21): testing destructor'
                passed = .false.
                call img%kill
                call img3d%kill
                test(1) = .not. img%exists()
                test(2) = .not. img3d%exists()
                passed = all(test)
                if( .not. passed )  stop 'destructor test failed'
            end subroutine test_image_local

    end subroutine test_image

    !>  \brief  is a destructor
    subroutine kill( self )
        class(image), intent(inout) :: self
        if( self%existence )then
            if( self%imgkind .eq. 'xfel' )then
                deallocate(self%cmat)
            else
                call fftwf_free(self%p)
            endif
            self%rmat=>null()
            self%cmat=>null()
            call fftwf_destroy_plan(self%plan_fwd)
            call fftwf_destroy_plan(self%plan_bwd)
            self%existence = .false.
        endif
    end subroutine kill

end module simple_image

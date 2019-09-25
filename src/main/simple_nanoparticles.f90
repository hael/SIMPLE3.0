!USAGE 1: simple_exec prg=detect_atoms smpd=0.358 vol1='particle1.mrc'
!USAGE 2: simple_exec prg=compare_nano vol1=vol_c1_aligned2_c3axis.mrc vol2=particle1_c3.mrc
module simple_nanoparticles_mod
!$ use omp_lib
!$ use omp_lib_kinds
include 'simple_lib.f08'
use simple_image,         only : image
use simple_atoms,         only : atoms
implicit none

private
public :: nanoparticle

#include "simple_local_flags.inc"

! module global constants
real,    parameter :: MAX_INTERAT_DIST      = 3.    !atoms for which the interatomic distance is > MAX_INTERAT_DIST are considered outliers and disregarded in the stats
real               :: THEORETICAL_RADIUS    = 1.1   !Default platinum, theoretical atom radius
integer, parameter :: N_THRESH              = 20    !number of thresholds for binarization
logical, parameter :: DEBUG_HERE            = .false.!for debugging purposes

type :: nanoparticle
    private
    type(atoms) :: centers_pdb
    type(image) :: img, img_bin, img_cc
    integer     :: ldim(3)           = 0
    real        :: smpd              = 0.
    real        :: nanop_mass_cen(3) = 0.!coordinates of the center of mass of the nanoparticle
    real        :: avg_dist_atoms    = 0.
    integer     :: n_cc              = 0 !number of atoms (connected components
    real,    allocatable  :: centers(:,:)
    real,    allocatable  :: ratios(:)
    real,    allocatable  :: ang_var(:)
    real,    allocatable  :: dists(:)
    integer, allocatable  :: loc_longest_dist(:,:)   !for indentific of the vxl that determins the longest dim of the atom
    character(len=2)      :: element     = ' '
    character(len=4)      :: atom_name   = '    '
    character(len=STDLEN) :: partname    = ''     !fname
    character(len=STDLEN) :: fbody       = ''     !fbody
    character(len=STDLEN) :: output_dir  = ''

  contains
    ! constructor
    procedure          :: new => new_nanoparticle
    ! getters/setters
    procedure          :: get_img
    procedure          :: get_ldim
    procedure          :: set_img
    procedure          :: set_partname
    ! segmentation and statistics
    procedure          :: binarize => nano_bin
    procedure          :: find_centers
    procedure, private :: nanopart_masscen
    procedure          :: calc_aspect_ratio
    procedure          :: discard_outliers
    procedure          :: radial_dependent_stats
    procedure, private :: distances_distribution
    procedure          :: atom_intensity_stats
    procedure          :: validate_atomic_positions
    ! phase correlation
    procedure          :: phasecorrelation_nano_gaussian
    ! clustering
    procedure          :: cluster => nanopart_cluster
    procedure, private :: affprop_cluster_ar
    procedure, private :: affprop_cluster_ang
    procedure, private :: affprop_cluster_dist_distr
    procedure          :: search_polarization
    ! execution
    procedure          :: identify_atomic_pos
    procedure          :: detect_atoms
    ! comparison
    procedure          :: compare_atomic_models
    ! visualization and output
    procedure          :: write_centers
    procedure          :: print_asym_unit
    ! others
    procedure          :: make_soft_mask
    procedure, private :: update_self_ncc
    procedure          :: keep_atomic_pos_at_radius
    ! kill
    procedure          :: kill => kill_nanoparticle
end type nanoparticle

contains

    !constructor
    subroutine new_nanoparticle(self, fname, cline_smpd, element)
        use simple_syslib
        class(nanoparticle),      intent(inout) :: self
        character(len=*),         intent(in)    :: fname
        real,                     intent(in)    :: cline_smpd
        character(len=2),optional,intent(in)    :: element
        integer :: nptcls
        real    :: smpd
        call self%kill
        call simple_getcwd(self%output_dir)
        call self%set_partname(fname)
        self%fbody = get_fbody(trim(fname), trim(fname2ext(fname)))
        self%smpd  = cline_smpd
        if(.not. present(element)) then
            self%element = 'pt'
            self%atom_name = ' pt '
        else !default is pt
            select case(element)
            case('pt')
                self%element       = 'pt'
                self%atom_name     = ' pt '
                ! thoretical radius is already set
            case('pd')
                self%element       = 'pd'
                self%atom_name     = ' pd '
                THEORETICAL_RADIUS = 1.12
            case('fe')
                self%element       = 'fe'
                self%atom_name     = ' fe '
                THEORETICAL_RADIUS = 1.02
            case('au')
                self%element       = 'au'
                self%atom_name     = ' au '
                THEORETICAL_RADIUS = 1.23
            case default
                THROW_HARD('Unknown atom element; new_nanoparticle')
           end select
        endif
        !self%sigma = 0.8*THEORETICAL_RADIUS/(2.*sqrt(2.*log(2.))*self%smpd) !0.8 not to have it too big (avoid connecting atoms)
        call find_ldim_nptcls(self%partname,  self%ldim, nptcls, smpd)
        call self%img%new         (self%ldim, self%smpd)
        call self%img_bin%new     (int(real(self%ldim)), self%smpd)
        call self%img%read(fname)
    end subroutine new_nanoparticle

     !get one of the images of the nanoparticle type
     subroutine get_img( self, img, which )
         class(nanoparticle), intent(in)    :: self
         type(image),         intent(inout) :: img
         character(len=*),    intent(in)    :: which
         integer :: ldim(3)
         ldim = img%get_ldim()
         if(self%ldim(1) .ne. ldim(1) .or. self%ldim(2) .ne. ldim(2) .or. self%ldim(3) .ne. ldim(3)) THROW_HARD('Wrong dimension in input img; get_img')
         select case(which)
         case('img')
             img = self%img
         case('img_bin')
             img = self%img_bin
         case('img_cc')
             img = self%img_cc
         case DEFAULT
             THROW_HARD('Wrong input parameter img type; get_img')
     end select
     end subroutine get_img

     subroutine get_ldim(self,ldim)
       class(nanoparticle), intent(in)  :: self
       integer,             intent(out) :: ldim(3)
       ldim = self%img%get_ldim()
     end subroutine get_ldim

     !set one of the images of the nanoparticle type
     subroutine set_img( self, img, which )
         class(nanoparticle), intent(inout)    :: self
         type(image),         intent(inout) :: img
         character(len=*),    intent(in)    :: which
         integer :: ldim(3)
         ldim = img%get_ldim()
         if(self%ldim(1) .ne. ldim(1) .or. self%ldim(2) .ne. ldim(2) .or. self%ldim(3) .ne. ldim(3)) THROW_HARD('Wrong dimension in input img;   set_img')
         select case(which)
         case('img')
             self%img = img
         case('img_bin')
             self%img_bin = img
         case('img_cc')
             self%img_cc = img
         case DEFAULT
            THROW_HARD('Wrong input parameter img type; set_img')
        end select
    end subroutine set_img

    ! set particle name (name of the input volume)
    subroutine set_partname( self, name )
        class(nanoparticle), intent(inout) :: self
        character(len=*),    intent(in)    :: name
        self%partname = name
    end subroutine set_partname

    subroutine update_self_ncc(self, img_cc)
        class(nanoparticle),   intent(inout) :: self
        type(image), optional, intent(in)    :: img_cc
        real, pointer :: rmat_cc(:,:,:)
        if(present(img_cc)) then
            call img_cc%get_rmat_ptr(rmat_cc)
        else
            call self%img_cc%get_rmat_ptr(rmat_cc)
        endif
        self%n_cc = nint(maxval(rmat_cc))
        rmat_cc => null()
    end subroutine update_self_ncc

    ! This subroutine has visualization purpose only.
    ! It prints out the 3 asymmetric units in a nanoparticle
    ! with c3 symmetry.
    subroutine print_asym_unit(self,nb_asym_units)
        class(nanoparticle), intent(inout) :: self
        integer,             intent(in)    :: nb_asym_units
        real, allocatable :: rmat1(:,:,:), rmat2(:,:,:), rmat3(:,:,:)
        type(image)   :: img_asym
        integer       :: i, j
        integer       :: x, y
        real :: vec(2), vec1(2)
        real :: ang1, ang2
        rmat1 = self%img%get_rmat()
        rmat2 = self%img%get_rmat()
        rmat3 = self%img%get_rmat()
        x = self%ldim(1)/2 !x-coords of the center
        y = self%ldim(2)/2 !y-coords of the center
        vec1(:)= [0.,1.]   !fixed 2D vector
        !$omp do collapse(2) schedule(static) private(i,j)
        do i = 1, self%ldim(1)
            do j = 1, self%ldim(2)
                vec(:) = real([i-x,j-y])  !translate the vector in the origin
                ang1 = ang2D_vecs(vec1,vec)
                if(ang1 > 360./real(nb_asym_units) .or. i <= x) then
                    rmat1(i,j,:) = 0.    !set to 0 the all line
                endif
                if(ang1 > 360./real(nb_asym_units) .or. i > x) then
                    rmat2(i,j,:) = 0.    !set to 0 the all line
                endif
                if(ang1 < 360./real(nb_asym_units)) rmat3(i,j,:) = 0.
             enddo
        enddo
        !$omp end do
        call img_asym%new(self%ldim, self%smpd)
        call img_asym%set_rmat(rmat1)
        call img_asym%write(basename(trim(self%fbody))//'FirstAsymUnit.mrc')
        call img_asym%set_rmat(rmat2)
        call img_asym%write(basename(trim(self%fbody))//'SecondAsymUnit.mrc')
        call img_asym%set_rmat(rmat3)
        call img_asym%write(basename(trim(self%fbody))//'ThirdAsymUnit.mrc')
        call img_asym%kill
        deallocate(rmat1,rmat2,rmat3)
    end subroutine print_asym_unit

    ! Find the centers coordinates of the atoms in the particle
    ! and save it in the global variable centers.
    ! If coords is present, it saves it also in coords.
    subroutine find_centers(self, img_bin, img_cc, coords)
       use simple_atoms, only: atoms
       class(nanoparticle),          intent(inout) :: self
       type(image), optional,        intent(inout) :: img_bin, img_cc
       real, optional, allocatable,  intent(out)   :: coords(:,:)
       integer :: i
       ! sanity check
       if(present(img_bin) .and. .not. present(img_cc)) THROW_HARD('img_bin and img_cc have to be both present in input')
       ! global variables allocation
       if(allocated(self%centers)) deallocate(self%centers)
       allocate(self%centers(3,self%n_cc),source = 0.)     !global variable
       !$omp do collapse(1) schedule(static) private(i)
       do i=1,self%n_cc
           if(present(img_bin)) then
               self%centers(:,i) = atom_masscen(self,i,img_cc)
           else
               self%centers(:,i) = atom_masscen(self,i)
           endif
       enddo
       !$omp end do
       ! saving centers coordinates, optional
       if(present(coords)) allocate(coords(3,self%n_cc), source = self%centers)
    contains

       !This function calculates the centers of mass of an
       !atom. It takes in input the image, its connected
       !component (cc) image and the label of the cc that
       !identifies the atom whose center of mass is to be
       !calculated. The result is stored in m.
       function atom_masscen(self, label, img_cc) result(m)
           type(nanoparticle),    intent(inout) :: self
           integer,               intent(in)    :: label
           type(image), optional, intent(inout) :: img_cc
           logical, allocatable :: mask(:,:,:)
           real, pointer        :: rmat_cc_in(:,:,:)
           real    :: m(3)  !mass center coords
           integer :: i, j, k
           integer :: sz !sz of the cc identified by label
           if(present(img_cc)) then
               allocate(mask(self%ldim(1),self%ldim(2),self%ldim(3)), source = .true.)
               call img_cc%get_rmat_ptr(rmat_cc_in)
           else
               call self%img_cc%get_rmat_ptr(rmat_cc_in)
               allocate(mask(self%ldim(1),self%ldim(2),self%ldim(3)), source = .true.)
           endif
           where(     abs(rmat_cc_in(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3))-real(label)) > TINY) mask = .false.
           sz = count(abs(rmat_cc_in-real(label)) < TINY)
           m = 0.
           !$omp do collapse(3) schedule(static) reduction(+:m) private(i,j,k)
           do i = 1, self%ldim(1)
               do j = 1, self%ldim(2)
                   do k = 1, self%ldim(3)
                       if(mask(i,j,k)) m = m + real([i,j,k])
                   enddo
               enddo
           enddo
           !$omp end do
           m = m/real(sz)
       end function atom_masscen
    end subroutine find_centers

    subroutine write_centers(self, fname, coords)
        class(nanoparticle),        intent(inout) :: self
        character(len=*), optional, intent(in)    :: fname
        real,             optional, intent(in)    :: coords(:,:)
        integer :: cc
        if(present(coords)) then
            call self%centers_pdb%new(size(coords, dim = 2), dummy=.true.)
            !$omp parallel do schedule(static) private(cc)
            do cc=1,size(coords, dim = 2)
                call self%centers_pdb%set_name(cc,self%atom_name)
                call self%centers_pdb%set_element(cc,self%element)
                call self%centers_pdb%set_coord(cc,(coords(:,cc)-1.)*self%smpd)
            enddo
            !$omp end parallel do
        else
            call self%centers_pdb%new(self%n_cc, dummy=.true.)
            !$omp parallel do schedule(static) private(cc)
            do cc=1,self%n_cc
                call self%centers_pdb%set_name(cc,self%atom_name)
                call self%centers_pdb%set_element(cc,self%element)
                call self%centers_pdb%set_coord(cc,(self%centers(:,cc)-1.)*self%smpd)
            enddo
            !$omp end parallel do
        endif
        if(present(fname)) then
            call self%centers_pdb%writepdb(fname)
        else
            call self%centers_pdb%writepdb(trim(self%fbody)//'_atom_centers')
        endif
    end subroutine write_centers

    ! calc the avg of the centers coords
     function nanopart_masscen(self) result(m)
         class(nanoparticle), intent(inout) :: self
         real    :: m(3)  !mass center coords
         integer :: i, j, k
         m = 0.
         !$omp parallel do schedule(static) reduction(+:m) private(i)
         do i = 1, self%n_cc
              m = m + 1.*self%centers(:,i)
         enddo
         !$omp end parallel do
         m = m/real(self%n_cc)
     end function nanopart_masscen

    ! This subroutine takes in input 2 2D vectors, centered in the origin
    ! and it gives as an output the angle between them, IN DEGREES.
    function ang2D_vecs(vec1, vec2) result(ang)
        real, intent(inout) :: vec1(2), vec2(2)
        real :: ang        !output angle
        real :: ang_rad    !angle in radians
        real :: mod1, mod2
        real :: dot_prod
        mod1 = sqrt(vec1(1)**2+vec1(2)**2)
        mod2 = sqrt(vec2(1)**2+vec2(2)**2)
        ! normalise
        vec1 = vec1/mod1
        vec2 = vec2/mod2
        ! dot product
        dot_prod = vec1(1)*vec2(1)+vec1(2)*vec2(2)
        ! sanity check
        if(dot_prod > 1. .or. dot_prod< -1.) then
            THROW_WARN('Out of the domain of definition of arccos; ang2D_vecs')
            ang_rad = 0.
        else
            ang_rad = acos(dot_prod)
        endif
        if(DEBUG_HERE) then
            write(logfhandle,*)'>>>>>>>>>>>>>>>>>>>>>>'
            write(logfhandle,*)'mod_1     = ', mod1
            write(logfhandle,*)'mod_2     = ', mod2
            write(logfhandle,*)'dot_prod  = ', dot_prod
            write(logfhandle,*)'ang in radians', acos(dot_prod)
        endif
        !output angle
        ang = rad2deg(ang_rad)
    end function ang2D_vecs

    ! This subroutine takes in input 2 3D vectors, centered in the origin
    ! and it gives as an output the angle between them, IN DEGREES.
    function ang3D_vecs(vec1, vec2) result(ang)
        real, intent(inout) :: vec1(3), vec2(3)
        real :: ang        !output angle
        real :: ang_rad    !angle in radians
        real :: mod1, mod2
        real :: dot_prod
        mod1 = sqrt(vec1(1)**2+vec1(2)**2+vec1(3)**2)
        mod2 = sqrt(vec2(1)**2+vec2(2)**2+vec2(3)**2)
        ! normalise
        vec1 = vec1/mod1
        vec2 = vec2/mod2
        ! dot product
        dot_prod = (vec1(1)*vec2(1))+(vec1(2)*vec2(2))+(vec1(3)*vec2(3))
        ! sanity check
        if(dot_prod > 1. .or. dot_prod < -1.) then
            THROW_WARN('Out of the domain of definition of arccos; ang3D_vecs')
            ang_rad = 0.
        else
            ang_rad = acos(dot_prod)
        endif
        if(DEBUG_HERE) then
            write(logfhandle,*)'>>>>>>>>>>>>>>>>>>>>>>'
            write(logfhandle,*)'mod_1     = ', mod1
            write(logfhandle,*)'mod_2     = ', mod2
            write(logfhandle,*)'dot_prod  = ', dot_prod
            write(logfhandle,*)'ang in radians', acos(dot_prod)
        endif
        ang = rad2deg(ang_rad)
    end function ang3D_vecs

    ! FORMULA: phasecorr = ifft2(fft2(field).*conj(fft2(reference)));
    subroutine phasecorrelation_nano_gaussian(self,otsu_thresh)
        use simple_segmentation
        class(nanoparticle), intent(inout) :: self
        real,                intent(out)   :: otsu_thresh
        type(image) :: one_atom
        type(image) :: phasecorr
        type(atoms) :: atom
        real :: cutoff, o_t
        call phasecorr%new(self%ldim, self%smpd)
        call phasecorr%set_ft(.true.)
        call one_atom%new(self%ldim,self%smpd)
        cutoff = 8.*self%smpd
        call atom%new(1)
        call atom%set_element(1,self%element)
        call atom%set_coord(1,self%smpd*(real(self%ldim)/2.)) !DO NOT NEED THE +1
        call atom%convolve(one_atom, cutoff)
        call one_atom%fft()
        call self%img%fft()
        call self%img%phase_corr(one_atom,phasecorr,1.)
        if(DEBUG_HERE) call phasecorr%write(PATH_HERE//basename(trim(self%fbody))//'PhaseCorrOneAtom.mrc')
        call self%img%copy(phasecorr)
        call otsu_nano(self%img,o_t)
        otsu_thresh = o_t
        call one_atom%kill()
    contains
        !Otsu binarization for nanoparticle maps
        !It considers the gray level value just in the positive range.
        !It doesn't threshold the map. It just returns the ideal threshold.
        ! This is based on the implementation of 1D otsu
         subroutine otsu_nano(img, scaled_thresh)
             use simple_math, only : otsu
             type(image),    intent(inout) :: img
             real,           intent(out)   :: scaled_thresh !returns the threshold in the correct range
             real, pointer     :: rmat(:,:,:)
             real, allocatable :: x(:)
             call img%get_rmat_ptr(rmat)
             x = pack(rmat(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)), rmat(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)) > 0.)
             call otsu(x, scaled_thresh)
         end subroutine otsu_nano
    end subroutine phasecorrelation_nano_gaussian

    ! This subrotuine takes in input a nanoparticle and
    ! binarizes it by thresholding. The gray level histogram is split
    ! in 20 parts, which corrispond to 20 possible threshold.
    ! Among those threshold, the selected one is the for which
    ! tha correlation between the raw map and a simulated distribution
    ! obtained with that threshold reaches the maximum value.
    subroutine nano_bin( self, otsu_thresh )
        class(nanoparticle), intent(inout) :: self
        real,                intent(in)    :: otsu_thresh !staring point for threshold refinement
        type(image)       :: img_bin_thresh(N_THRESH/2-1)
        type(image)       :: img_ccs_thresh(N_THRESH/2-1)
        type(image)       :: pc(N_THRESH/2-1)
        type(atoms)       :: atom
        type(image)       :: simulated_distrib
        integer, allocatable :: imat_t(:,:,:)
        real,    allocatable :: x_mat(:)  !vectorization of the volume
        real,    allocatable :: coords(:,:)
        real,    allocatable :: rmat(:,:,:)
        integer ::  i, cc, t
        real    :: x_thresh(N_THRESH/2-1)
        real    :: step, maximum, mm(2)
        write(logfhandle,*) '****binarization, init'
        rmat = self%img%get_rmat()
        x_mat = pack(rmat(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)), rmat(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)) >= 0.)
        allocate(imat_t(self%ldim(1), self%ldim(2), self%ldim(3)), source = 0)
        step = (maxval(x_mat)-otsu_thresh )/real(N_THRESH)
        deallocate(x_mat)
        call simulated_distrib%new(self%ldim,self%smpd)
        call self%img%fft ! for pc calculation
        !$omp do collapse(1) schedule(static) private(i)
        do i = 1, N_THRESH/2-1
            call progress(i, N_THRESH/2-1)
            call img_bin_thresh(i)%new(self%ldim, self%smpd)
            if(i == 1) then
                x_thresh(i) = otsu_thresh
            else
                x_thresh(i) = x_thresh(i-1) + step
            endif
            where(rmat(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)) > x_thresh(i))
                imat_t = 1
            elsewhere
                imat_t = 0
            endwhere
            ! Generate binary image and cc image
            call img_bin_thresh(i)%set_rmat(real(imat_t))
            call img_bin_thresh(i)%find_connected_comps(img_ccs_thresh(i))
            ! Find atom centers in the generated distributions
            call self%update_self_ncc(img_ccs_thresh(i)) !self%n_cc is needed in find_centers
            call self%find_centers(img_bin_thresh(i), img_ccs_thresh(i), coords)
            ! Generate a simulated distribution based on those center
            call self%write_centers('centers_'//trim(int2str(i))//'_iteration', coords)
            call atom%new          ('centers_'//trim(int2str(i))//'_iteration.pdb')
            call atom%convolve(simulated_distrib, cutoff = 8.*self%smpd)
            call del_file('centers_'//trim(int2str(i))//'_iteration.pdb')
            if(DEBUG_HERE) call simulated_distrib%write('simulated_'//trim(int2str(i))//'_iteration.mrc')
            call atom%kill
            ! Take care of Fourier status, for phase_corr calculation
            call simulated_distrib%fft
            call pc(i)%new(self%ldim,self%smpd)
            call pc(i)%zero_and_flag_ft
            ! Correlation volume generation
            call self%img%phase_corr(simulated_distrib, pc(i), lp=3.)
            if(DEBUG_HERE) call pc(i)%write('phasecorr_'//trim(int2str(i))//'_iteration.mrc')
            ! Calculation and update of the maxval the correlation reaches
            mm = pc(i)%minmax()
            if(mm(2) > maximum) then
                maximum = mm(2)
                t       = i
            endif
            call simulated_distrib%ifft
        enddo
        !$omp end do
        call self%img%ifft ! To remove
        write(logfhandle,*) 'Selected threshold: ', x_thresh(t)
        ! Update img_bin and img_cc
        call self%img_bin%copy(img_bin_thresh(t))
        if(DEBUG_HERE) call self%img_bin%write('AlternativeBin.mrc')
        call self%img_cc%copy(img_ccs_thresh(t))
        !$omp parallel do schedule(static) private(i)
        do i = 1,  N_THRESH/2-1
            call img_bin_thresh(i)%kill
            call img_ccs_thresh(i)%kill
        enddo
        !$omp end parallel do
        ! deallocate and kill
        if(allocated(rmat))   deallocate(rmat)
        if(allocated(imat_t)) deallocate(imat_t)
        if(allocated(coords)) deallocate(coords)
        call simulated_distrib%kill
        write(logfhandle,*) '****binarization, completed'
    end subroutine nano_bin

    ! This subroutine calculates the histogram of the within-atoms
    ! distances distribution within the nanoparticle nano.
    ! To each atom the distance assigned is the min distance
    ! to the other atoms. There is a threshols (3A) for
    ! outliers discarding.
    ! If coords in input, then it considers just the atom-to-atom
    ! distance between the atoms with centers in coords.
    subroutine distances_distribution(self,coords,volume)
        use simple_atoms, only : atoms
        use simple_stat,  only : mad_gau
        class(nanoparticle), intent(inout) :: self
        real,    optional,   intent(in)    :: coords(:,:)
        integer, optional,   intent(in)    :: volume
        real, allocatable :: dist(:)
        real    :: stdev, med, robust_stdev
        integer :: i, j, n_discard
        logical :: mask(self%n_cc)
        ! Initialisations
        mask = .true.
        stdev      = 0.
        n_discard  = 0
        if(present(coords)) then
            allocate(dist(size(coords,dim=2)), source = 0.)
            do i = 1, size(coords,dim=2)
                dist(i) =  pixels_dist(coords(:,i), self%centers(:,:), 'min', mask=mask) !I have to use all the atoms when
                mask(:) = .true. ! restore
                !Discard outliers
                if(dist(i)*self%smpd > MAX_INTERAT_DIST ) then !2.5 is the average interatomic distance
                    dist(i) = 0.
                    n_discard = n_discard + 1
                endif
            enddo
            self%avg_dist_atoms = sum(dist)/real(size(coords,dim=2)-n_discard)
            !$omp parallel do schedule(static) private(i) reduction(+:stdev)
            do i = 1, size(coords,dim=2)
                if(dist(i)*self%smpd <=MAX_INTERAT_DIST) stdev = stdev + (dist(i)-self%avg_dist_atoms)**2
            enddo
            !$omp end parallel do
            stdev = sqrt(stdev/real(size(coords,dim=2)-1-n_discard))
            med = median(dist)
            robust_stdev = mad_gau(dist,med)
            if(present(volume)) then
                write(unit = 11, fmt = '(a,a,a,f6.3,a)') 'Average dist atoms vol ', trim(int2str(volume)),':', self%avg_dist_atoms*self%smpd, ' A'
                write(unit = 11, fmt = '(a,a,a,f6.3,a)') 'StDev   dist atoms vol ', trim(int2str(volume)),':', stdev*self%smpd, ' A'
                write(unit = 11, fmt = '(a,a,a,f6.3,a)') 'Median  dist atoms vol ', trim(int2str(volume)),':', med*self%smpd, ' A'
                write(unit = 11, fmt = '(a,a,a,f6.3,a)') 'MadGau  dist atoms vol ', trim(int2str(volume)),':', robust_stdev*self%smpd, ' A'
            else
                write(unit = 11, fmt = '(a,f6.3,a)') 'Average dist atoms: ', self%avg_dist_atoms*self%smpd, ' A'
                write(unit = 11, fmt = '(a,f6.3,a)') 'StDev   dist atoms: ', stdev*self%smpd, ' A'
                write(unit = 11, fmt = '(a,f6.3,a)') 'Median  dist atoms: ', med*self%smpd, ' A'
                write(unit = 11, fmt = '(a,f6.3,a)') 'MadGau  dist atoms: ', robust_stdev*self%smpd,  ' A'
            endif
            deallocate(dist)
        else
            ! Report statistics and images in dedicated directory
            !come back to root folder
            call simple_chdir(trim(self%output_dir),errmsg="simple_nanoparticles :: distances_distribution, simple_chdir; ")
            call simple_mkdir(trim(self%output_dir)//'/ClusterDistDistr',errmsg="simple_nanoparticles :: distances_distribution, simple_mkdir; ")
            call simple_chdir(trim(self%output_dir)//'/ClusterDistDistr',errmsg="simple_nanoparticles :: distances_distribution, simple_chdir; ")
            open(15, file='DistancesDistr')
            allocate(self%dists(size(self%centers, dim = 2)), source = 0.)
            do i = 1, size(self%centers, dim = 2)
                self%dists(i) =  pixels_dist(self%centers(:,i), self%centers(:,:), 'min', mask=mask) !Use all the atoms
                mask(:) = .true. ! restore
                !Discard outliers
                if(self%dists(i)*self%smpd > MAX_INTERAT_DIST ) then !2.5 is the average interatomic distance
                    self%dists(i) = 0.
                    n_discard = n_discard + 1
                endif
            enddo
            self%avg_dist_atoms = sum(self%dists)/real(size(self%centers, dim = 2)-n_discard)
            !$omp parallel do schedule(static) private(i) reduction(+:stdev)
            do i = 1, size(self%centers, dim = 2)
                if(self%dists(i)*self%smpd <=MAX_INTERAT_DIST) stdev = stdev + (self%dists(i)-self%avg_dist_atoms)**2
            enddo
            !$omp end parallel do
            stdev = sqrt(stdev/real(size(self%centers, dim = 2)-1-n_discard))
            med = median(self%dists)
            robust_stdev = mad_gau(self%dists,med)
            write(unit = 15, fmt = '(a,f6.3,a)') 'Average dist atoms: ', self%avg_dist_atoms*self%smpd, ' A'
            write(unit = 15, fmt = '(a,f6.3,a)') 'StDev   dist atoms: ', stdev*self%smpd, ' A'
            write(unit = 15, fmt = '(a,f6.3,a)') 'Median  dist atoms: ', med*self%smpd, ' A'
            write(unit = 15, fmt = '(a,f6.3,a)') 'MadGau  dist atoms: ', robust_stdev*self%smpd, ' A'
            !write on pdb file
            call self%centers_pdb%new(self%n_cc, dummy=.true.)
            do i = 1,self%n_cc
                call self%centers_pdb%set_beta(i, self%dists(i)*self%smpd)
            enddo
            call self%centers_pdb%writepdb('DistancesDistr')
        endif
        close(15)
    end subroutine distances_distribution


    ! This subroutine discard outliers that resisted binarization.
    ! It calculates the contact score of each atom and discards the bottom
    ! PERCENT_DISCARD% of the atoms according to the contact score.
    ! It modifies the img_bin and img_cc instances deleting the
    ! identified outliers.
    ! Contact score: fix a radius and an atom A. Count the number N of atoms
    ! in the sphere centered in A of that radius. Define contact score of A
    ! equal to N. Do it for each atom.
    subroutine discard_outliers(self)
        class(nanoparticle), intent(inout) :: self
        real, pointer      :: rmat(:,:,:), rmat_cc(:,:,:)
        integer, parameter :: PERCENT_DISCARD = 5/100
        integer, allocatable :: contact_scores(:)
        logical, allocatable :: mask(:)
        real    :: dist
        real    :: radius  !radius of the sphere to consider
        integer :: cc
        integer :: cnt     !contact_score
        integer :: loc(1)
        integer :: n_discard
        integer :: label(1)
        ! Size filter.
        !call self%size_filtering()
        write(logfhandle, *) '****outliers discarding, init'
        ! Outliers removal using contact score
        radius = 2.*self%avg_dist_atoms
        allocate(mask(self%n_cc), source = .true.)
        allocate(contact_scores(self%n_cc), source = 0)
        do cc = 1, self%n_cc !fix the atom
            dist = 0.
            mask = .true.
            cnt = 0
            mask(cc)  = .false.
            do while(dist < radius)
                dist = pixels_dist(self%centers(:,cc), self%centers,'min', mask, loc)
                mask(loc) = .false.
                cnt = cnt + 1
            enddo
            contact_scores(cc) = cnt - 1 !-1 because while loop counts one extra before exiting
        enddo
        n_discard = self%n_cc*PERCENT_DISCARD ! discard bottom 10 instead%??
        mask(1:self%n_cc) = .true.
        call self%img_cc%get_rmat_ptr(rmat_cc)
        call self%img_bin%get_rmat_ptr(rmat)
        ! Removing outliers from the binary image and the connected components image
        ! TO PARALLELISE
        !omp parallel do schedule(static) private(cc,label,rmat,mask) !not sure about mask
        do cc = 1, n_discard
            label = minloc(contact_scores, mask)
            where(abs(rmat_cc-real(label(1))) < TINY)
               rmat = 0.   ! discard atom corresponding to label_discard(i)
            endwhere
            mask(label(1)) = .false.
            self%centers(:,label) = -1. !identify to discard them
        enddo
        !omp end parallel do
        call self%img_bin%find_connected_comps(self%img_cc)
        call self%img_cc%get_rmat_ptr(rmat_cc)
        self%n_cc = nint(maxval(rmat_cc)) !update
        call self%find_centers()
        call self%write_centers()
        !root folder
        call simple_chdir(trim(self%output_dir),errmsg="simple_nanoparticles :: radial_dependent_stats, simple_chdir; ")
        call self%img_bin%write(PATH_HERE//basename(trim(self%fbody))//'BIN.mrc')
        write(logfhandle, *) '****outliers discarding, completed'
    end subroutine discard_outliers

    subroutine validate_atomic_positions(self)
        class(nanoparticle), intent(inout) :: self
        integer, allocatable :: imat(:,:,:)
        real,    allocatable :: x(:)
        real,    pointer     :: rmat_pc(:,:,:), rmat_cc(:,:,:)
        integer, parameter   :: RANK_THRESH = 5
        integer :: n_cc, cnt
        integer :: rank, m(1)
        real    :: new_centers(3,2*self%n_cc)   !will pack it afterwards if it has too many elements
        real    :: pc
        call self%img%get_rmat_ptr(rmat_pc)    !now img contains the phase correlation
        imat = nint(self%img_cc%get_rmat())
        call self%img_cc%get_rmat_ptr(rmat_cc) !to pass to the subroutine split_atoms
        if(DEBUG_HERE) call self%img_cc%write(PATH_HERE//basename(trim(self%fbody))//'OldImgCc.mrc')
        cnt = 0
        ! Remember to update the centers
        do n_cc =1, self%n_cc !for each cc check if the center corresponds with the local max of the phase corr
            pc = rmat_pc(nint(self%centers(1,n_cc)),nint(self%centers(2,n_cc)),nint(self%centers(3,n_cc)))
            !calculate the rank
            x = pack(rmat_pc(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)), imat(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)) == n_cc)
            call hpsort(x)
            m(:) = minloc(abs(x-pc))
            rank = size(x)-m(1)
            deallocate(x)
            if(rank > RANK_THRESH) then
                call split_atom(rmat_pc,rmat_cc,imat,n_cc,new_centers,cnt)
            else
                cnt = cnt + 1 !new number of centers deriving from splitting
                new_centers(:,cnt) = self%centers(:,n_cc)
            endif
        enddo
        deallocate(self%centers)
        allocate(self%centers(3,cnt), source = 0.)
        !update centers
        do n_cc =1, cnt
            self%centers(:,n_cc) = new_centers(:,n_cc)
        enddo
        self%n_cc = cnt !update
        call self%write_centers()
        call self%img_cc%write(PATH_HERE//basename(trim(self%fbody))//'NewImgCc.mrc') !if(DEBUG_HERE)
    contains
        subroutine split_atom(rmat_pc, rmat_cc, imat,n_cc,new_centers,cnt)
            real,    intent(in)    :: rmat_pc(:,:,:)
            real,    intent(inout) :: rmat_cc(:,:,:)
            integer, intent(in)    :: imat(:,:,:)
            integer, intent(in)    :: n_cc
            real,    intent(inout) :: new_centers(:,:)
            integer, intent(inout) :: cnt   !atom counter, to update the center coords
            integer :: new_center1(3),new_center2(3)
            integer :: i, j, k
            logical :: mask(self%ldim(1),self%ldim(2),self%ldim(3)) !false in the layer of connection of the atom to be split
            mask = .false.  !initialization
            ! Identify first new center
            new_center1 = maxloc(rmat_pc(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)), imat(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)) == n_cc)
            cnt = cnt + 1
            new_centers(:,cnt) = real(new_center1)
            do i = 1, self%ldim(1)
                do j = 1, self%ldim(2)
                    do k = 1, self%ldim(3)
                        if(((real(i)-real(new_center1(1)))**2 + (real(j)-real(new_center1(2)))**2 + &
                        &   (real(k)-real(new_center1(3)))**2)*self%smpd - THEORETICAL_RADIUS**2 < TINY) then
                            if(imat(i,j,k) == n_cc) mask(i,j,k) = .true.
                        endif
                    enddo
                enddo
            enddo
            ! Second likely center.
                new_center2 = maxloc(rmat_pc(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)), &
                & (imat(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)) == n_cc) .and. .not. mask(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)))
                if(any(new_center2 > 0)) then !if anything was found
                    !Validate second center (check if it's 2 merged atoms, or one pointy one)
                    if(sqrt(real(new_center2(1)-new_center1(1))**2+real(new_center2(2)-new_center1(2))**2+real(new_center2(3)-new_center1(3))**2)*self%smpd <= 1.2*THEORETICAL_RADIUS) then
                        ! Set the merged cc back to 0
                        where((abs(rmat_cc(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3))-real(n_cc))<TINY) .and. (.not.mask(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)))) rmat_cc(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)) = 0.
                        return
                    endif
                    cnt = cnt + 1
                    new_centers(:,cnt) = real(new_center2)
                    !In the case two merged atoms, build the second atom
                    do i = 1, self%ldim(1)
                        do j = 1, self%ldim(2)
                            do k = 1, self%ldim(3)
                                if(((real(i)-real(new_center2(1)))**2 + (real(j)-real(new_center2(2)))**2 + (real(k)-real(new_center2(3)))**2)*self%smpd - THEORETICAL_RADIUS**2 < TINY) then
                                    if(imat(i,j,k) == n_cc)   mask(i,j,k) = .true.
                                endif
                            enddo
                        enddo
                    enddo
                endif
            ! Set the merged cc back to 0
            where((abs(rmat_cc(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3))-real(n_cc))<TINY) .and. (.not.mask(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)))) rmat_cc(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)) = 0.
        end subroutine split_atom
    end subroutine validate_atomic_positions

    subroutine radial_dependent_stats(self,volume)
        class(nanoparticle), intent(inout) :: self
        integer, optional,   intent(in)    :: volume !volume identifier, when input is more than one map
        type(atoms)        :: radial_atoms5A_all,  radial_atoms7A_all,  radial_atoms9A_all, radial_atoms12A_all  !full shell
        type(atoms)        :: radial_atoms5A_just, radial_atoms7A_just, radial_atoms9A_just,radial_atoms12A_just !empty shell
        real, allocatable  :: coords(:,:) !coordinates of the centers of the atoms according to radial distances
        real    :: m(3)    !mass center of c3 map
        real    :: d       !distance atoms from the center
        real    :: radius  !radius of the sphere to consider
        ! integer :: N       !number of atoms c3 map
        integer :: cc
        integer :: cnt
        integer :: cnt5_all,  cnt7_all,  cnt9_all,  cnt12_all  ! number of atoms in radial shells, full shell
        integer :: cnt5_just, cnt7_just, cnt9_just, cnt12_just ! number of atoms in radial shells, only in rad indicated, empty shell
        write(logfhandle, *) '****radial atom-to-atom distances estimation, init'
        ! Radial dependent statistics
        cnt5_all   = 0
        cnt7_all   = 0
        cnt9_all   = 0
        cnt12_all  = 0
        cnt5_just  = 0
        cnt7_just  = 0
        cnt9_just  = 0
        cnt12_just = 0
        m = self%nanopart_masscen()
        do cc = 1, self%n_cc
            d = euclid(self%centers(:,cc), m)*self%smpd
           if(d<=5.) then
               cnt5_just = cnt5_just+1
               cnt5_all  = cnt5_all+1
               cnt7_all  = cnt7_all +1
               cnt9_all  = cnt9_all +1
               cnt12_all = cnt12_all+1
           elseif(d>5. .and. d<=7.) then
               cnt7_just = cnt7_just+1
               cnt7_all  = cnt7_all +1
               cnt9_all  = cnt9_all +1
               cnt12_all = cnt12_all+1
           elseif(d>7. .and. d<=9.) then
               cnt9_just = cnt9_just+1
               cnt9_all  = cnt9_all +1
               cnt12_all = cnt12_all+1
           elseif(d>9. .and. d<=12.) then
               cnt12_just = cnt12_just+1
               cnt12_all  = cnt12_all+1
           endif
        enddo
        call radial_atoms5A_all%new (cnt5_all ,  dummy=.true.)
        call radial_atoms7A_all%new (cnt7_all ,  dummy=.true.)
        call radial_atoms9A_all%new (cnt9_all ,  dummy=.true.)
        call radial_atoms12A_all%new(cnt12_all,  dummy=.true.)
        call radial_atoms5A_just%new (cnt5_just , dummy=.true.)
        call radial_atoms7A_just%new (cnt7_just , dummy=.true.)
        call radial_atoms9A_just%new (cnt9_just , dummy=.true.)
        call radial_atoms12A_just%new(cnt12_just, dummy=.true.)
        cnt5_all   = 0
        cnt7_all   = 0
        cnt9_all   = 0
        cnt12_all  = 0
        cnt5_just  = 0
        cnt7_just  = 0
        cnt9_just  = 0
        cnt12_just = 0
        ! Save coords
        do cc = 1, self%n_cc
            d = euclid(self%centers(:,cc), m)*self%smpd
           if(d<=5.) then
               cnt5_just = cnt5_just+1
               cnt5_all  = cnt5_all +1
               cnt7_all  = cnt7_all +1
               cnt9_all  = cnt9_all +1
               cnt12_all = cnt12_all+1
               call radial_atoms5A_just%set_name(cnt5_just,self%atom_name)
               call radial_atoms5A_just%set_element(cnt5_just,self%element)
               call radial_atoms5A_just%set_coord(cnt5_just,(self%centers(:,cc)-1.)*self%smpd)
               call radial_atoms5A_all%set_name(cnt5_all,self%atom_name)
               call radial_atoms5A_all%set_element(cnt5_all,self%element)
               call radial_atoms5A_all%set_coord(cnt5_all,(self%centers(:,cc)-1.)*self%smpd)
               call radial_atoms7A_all%set_name(cnt7_all,self%atom_name)
               call radial_atoms7A_all%set_element(cnt7_all,self%element)
               call radial_atoms7A_all%set_coord(cnt7_all,(self%centers(:,cc)-1.)*self%smpd)
               call radial_atoms9A_all%set_name(cnt9_all,self%atom_name)
               call radial_atoms9A_all%set_element(cnt9_all,self%element)
               call radial_atoms9A_all%set_coord(cnt9_all,(self%centers(:,cc)-1.)*self%smpd)
               call radial_atoms12A_all%set_name(cnt12_all,self%atom_name)
               call radial_atoms12A_all%set_element(cnt12_all,self%element)
               call radial_atoms12A_all%set_coord(cnt12_all,(self%centers(:,cc)-1.)*self%smpd)
           elseif(d>5. .and. d<=7.) then
               cnt7_just = cnt7_just+1
               cnt7_all  = cnt7_all +1
               cnt9_all  = cnt9_all +1
               cnt12_all = cnt12_all+1
               call radial_atoms7A_just%set_name(cnt7_just,self%atom_name)
               call radial_atoms7A_just%set_element(cnt7_just,self%element)
               call radial_atoms7A_just%set_coord(cnt7_just,(self%centers(:,cc)-1.)*self%smpd)
               call radial_atoms7A_all%set_name(cnt7_all,self%atom_name)
               call radial_atoms7A_all%set_element(cnt7_all,self%element)
               call radial_atoms7A_all%set_coord(cnt7_all,(self%centers(:,cc)-1.)*self%smpd)
               call radial_atoms9A_all%set_name(cnt9_all,self%atom_name)
               call radial_atoms9A_all%set_element(cnt9_all,self%element)
               call radial_atoms9A_all%set_coord(cnt9_all,(self%centers(:,cc)-1.)*self%smpd)
               call radial_atoms12A_all%set_name(cnt12_all,self%atom_name)
               call radial_atoms12A_all%set_element(cnt12_all,self%element)
               call radial_atoms12A_all%set_coord(cnt12_all,(self%centers(:,cc)-1.)*self%smpd)
           elseif(d>7. .and. d<=9.) then
               cnt9_just = cnt9_just+1
               cnt9_all  = cnt9_all +1
               cnt12_all = cnt12_all+1
               call radial_atoms9A_just%set_name(cnt9_just,self%atom_name)
               call radial_atoms9A_just%set_element(cnt9_just,self%element)
               call radial_atoms9A_just%set_coord(cnt9_just,(self%centers(:,cc)-1.)*self%smpd)
               call radial_atoms9A_all%set_name(cnt9_all,self%atom_name)
               call radial_atoms9A_all%set_element(cnt9_all,self%element)
               call radial_atoms9A_all%set_coord(cnt9_all,(self%centers(:,cc)-1.)*self%smpd)
               call radial_atoms12A_all%set_name(cnt12_all,self%atom_name)
               call radial_atoms12A_all%set_element(cnt12_all,self%element)
               call radial_atoms12A_all%set_coord(cnt12_all,(self%centers(:,cc)-1.)*self%smpd)
           elseif(d>9. .and. d<=12.) then
               cnt12_just = cnt12_just+1
               cnt12_all  = cnt12_all+1
               call radial_atoms12A_just%set_name(cnt12_just,self%atom_name)
               call radial_atoms12A_just%set_element(cnt12_just,self%element)
               call radial_atoms12A_just%set_coord(cnt12_just,(self%centers(:,cc)-1.)*self%smpd)
               call radial_atoms12A_all%set_name(cnt12_all,self%atom_name)
               call radial_atoms12A_all%set_element(cnt12_all,self%element)
               call radial_atoms12A_all%set_coord(cnt12_all,(self%centers(:,cc)-1.)*self%smpd)
           endif
        enddo
        ! Report statistics in dedicated directory
        !coma back to root folder
        call simple_chdir(trim(self%output_dir),errmsg="simple_nanoparticles :: radial_dependent_stats, simple_chdir; ")
        call simple_mkdir(trim(self%output_dir)//'/RadialDependentStat',errmsg="simple_nanoparticles :: radial_dependent_stats, simple_mkdir; ")
        call simple_chdir(trim(self%output_dir)//'/RadialDependentStat',errmsg="simple_nanoparticles :: radial_dependent_stats, simple_chdir; ")
        open(11, file='RadialDependentStat', position= 'append')
        if(present(volume)) then
            call radial_atoms5A_just%writepdb('vol'//int2str(volume)//'_radial_atoms5A_just')
            call radial_atoms7A_just%writepdb('vol'//int2str(volume)//'_radial_atoms7A_just')
            call radial_atoms9A_just%writepdb('vol'//int2str(volume)//'_radial_atoms9A_just')
            call radial_atoms12A_just%writepdb('vol'//int2str(volume)//'_radial_atoms12A_just')
            call radial_atoms5A_all%writepdb('vol'//int2str(volume)//'_radial_atoms5A_all')
            call radial_atoms7A_all%writepdb('vol'//int2str(volume)//'_radial_atoms7A_all')
            call radial_atoms9A_all%writepdb('vol'//int2str(volume)//'_radial_atoms9A_all')
            call radial_atoms12A_all%writepdb('vol'//int2str(volume)//'_radial_atoms12A_all')
        else
            call radial_atoms5A_just%writepdb('radial_atoms5A_just')
            call radial_atoms7A_just%writepdb('radial_atoms7A_just')
            call radial_atoms9A_just%writepdb('radial_atoms9A_just')
            call radial_atoms12A_just%writepdb('radial_atoms12A_just')
            call radial_atoms5A_all%writepdb('radial_atoms5A_all')
            call radial_atoms7A_all%writepdb('radial_atoms7A_all')
            call radial_atoms9A_all%writepdb('radial_atoms9A_all')
            call radial_atoms12A_all%writepdb('radial_atoms12A_all')
        endif
        ! Estimation of avg distance and stdev among atoms in radial dependent shells
        if(present(volume)) then
            write(unit = 11, fmt = '(a,a)') 'Estimation of atom-to-atom statistics in 5A radius shell vol', trim(int2str(volume))
        else
            write(unit = 11, fmt = '(a)') 'Estimation of atom-to-atom statistics in 5A radius shell'
        endif
        allocate(coords(3,cnt5_all), source = 0.)
        cnt = 0
        do cc = 1, self%n_cc
            d = euclid(self%centers(:,cc), m)*self%smpd
            if(d<=5.) then
                cnt = cnt + 1
                coords(:3,cnt) = self%centers(:,cc)
            endif
        enddo
        if(present(volume)) then
            call self%distances_distribution(coords, volume)
        else
            call self%distances_distribution(coords)
        endif
        deallocate(coords)
        if(present(volume)) then
            write(unit = 11, fmt = '(a,a)') 'Estimation of atom-to-atom statistics in 7A radius shell vol', trim(int2str(volume))
        else
            write(unit = 11, fmt = '(a)') 'Estimation of atom-to-atom statistics in 7A radius shell'
        endif
        allocate(coords(3,cnt7_all), source = 0.)
        cnt = 0
        do cc = 1, self%n_cc
            d = euclid(self%centers(:,cc), m)*self%smpd
            if(d<=7.) then
                cnt = cnt + 1
                coords(:3,cnt) = self%centers(:,cc)
            endif
        enddo
        if(present(volume)) then
            call self%distances_distribution(coords, volume)
        else
            call self%distances_distribution(coords)
        endif
        deallocate(coords)
        if(present(volume)) then
            write(unit = 11, fmt = '(a,a)') 'Estimation of atom-to-atom statistics in 9A radius shell vol', trim(int2str(volume))
        else
            write(unit = 11, fmt = '(a)') 'Estimation of atom-to-atom statistics in 9A radius shell'
        endif
        allocate(coords(3,cnt9_all), source = 0.)
        cnt = 0
        do cc = 1, self%n_cc
            d = euclid(self%centers(:,cc), m)*self%smpd
            if(d<=9.) then
                cnt = cnt + 1
                coords(:3,cnt) = self%centers(:,cc)
            endif
        enddo
        if(present(volume)) then
            call self%distances_distribution(coords, volume)
        else
            call self%distances_distribution(coords)
        endif
        deallocate(coords)
        if(present(volume)) then
            write(unit = 11, fmt = '(a,a)') 'Estimation of atom-to-atom statistics in 12A radius shell vol', trim(int2str(volume))
        else
            write(unit = 11, fmt = '(a)') 'Estimation of atom-to-atom statistics in 12A radius shell'
        endif
        allocate(coords(3,cnt12_all), source = 0.)
        cnt = 0
        do cc = 1, self%n_cc
            d = euclid(self%centers(:,cc), m)*self%smpd
            if(d<=12.) then
                cnt = cnt + 1
                coords(:3,cnt) = self%centers(:,cc)
            endif
        enddo
        if(present(volume)) then
            call self%distances_distribution(coords, volume)
        else
            call self%distances_distribution(coords)
        endif
        deallocate(coords)
        close(11)
        call radial_atoms5A_all%kill
        call radial_atoms7A_all%kill
        call radial_atoms9A_all%kill
        call radial_atoms12A_all%kill
        call radial_atoms5A_just%kill
        call radial_atoms7A_just%kill
        call radial_atoms9A_just%kill
        call radial_atoms12A_just%kill
        ! Come back to root directory
        call simple_chdir(trim(self%output_dir),errmsg="simple_nanoparticles :: radial_dependent_stats, simple_chdir; ")
        write(logfhandle, *) '****radial atom-to-atom distances estimation, completed'
   end subroutine radial_dependent_stats

   subroutine calc_aspect_ratio(self, print_ar)
       use gnufor2
       class(nanoparticle), intent(inout) :: self
       logical, optional,   intent(in)    :: print_ar !print longest/shortest dim and ratio
       real, pointer     :: rmat_cc(:,:,:)
       real, allocatable :: longest_dist(:)
       integer       :: label
       real :: avg_diameter, median_diameter, min_diameter, max_diameter, stdev_diameter
       call self%img_bin%find_connected_comps(self%img_cc) ! TO REMOVE??
       call self%img_cc%get_rmat_ptr(rmat_cc)
       self%n_cc = int(maxval(rmat_cc))
       allocate(self%ratios (self%n_cc),             source = 0.)
       allocate(longest_dist(self%n_cc),             source = 0.)
       allocate(self%loc_longest_dist(3,self%n_cc),  source = 0 )
       call self%find_centers() !TO KEEP
       !$omp parallel do schedule(static) private(label)
       do label = 1, self%n_cc
           call calc_aspect_ratio_private(label, self%ratios(label), ld=longest_dist(label), print_ar=print_ar)
       enddo
       !$omp end parallel do
       longest_dist = 2.*longest_dist ! radius --> diameter
       min_diameter = minval(longest_dist(1:self%n_cc))
       max_diameter = maxval(longest_dist(1:self%n_cc))
       median_diameter = median(longest_dist(1:self%n_cc))
       avg_diameter    = sum(longest_dist(1:self%n_cc))/real(self%n_cc)
       stdev_diameter = 0.
       do label = 1, self%n_cc
           stdev_diameter = stdev_diameter + (avg_diameter-longest_dist(label))**2
       enddo
       stdev_diameter = sqrt(stdev_diameter/real(self%n_cc-1))
       print *, 'minimum  value diameter ', min_diameter, 'A'
       print *, 'maximum  value diameter ', max_diameter, 'A'
       print *, 'median   value diameter ', median_diameter, 'A'
       print *, 'average  value diameter ', avg_diameter, 'A'
       print *, 'stdev    value diameter ', stdev_diameter, 'A'
       call hist(self%ratios, 20)
       ! To dump some of the analysis on aspect ratios on file compatible
       ! with Matlab.
        ! open(123, file='AspectRatios')
        ! write (123,*) 'AR=[...'
        ! do label = 1, size(self%ratios)
        !     write (123,'(A)', advance='no') trim(real2str(self%ratios(label)))
        !     if(label < size(self%ratios)) write (123,'(A)', advance='no') ', '
        ! end do
        ! write (123,*) '];'
        ! close(123)
        deallocate(longest_dist)
        write(logfhandle,*)'**aspect ratios calculations completed'
    contains
        ! This subroutine takes in input a connected component (cc) image
        ! and the label of one of its ccs and calculates its aspect ratio, which
        ! is defined as the ratio of the width and the height.
        ! The idea behind this is that the center of the cc is calculated,
        ! than everything is deleted except the borders of the cc. Finally,
        ! in order to calculate the width and the height, the min/max
        ! distances between the center and the borders are calculated. The
        ! aspect ratio is the ratio of those 2 distances.
        subroutine calc_aspect_ratio_private(label,ratio,ld,print_ar)
            integer,             intent(in)    :: label
            real,                intent(out)   :: ratio
            real   , optional,   intent(out)   :: ld ! longest dist
            logical, optional,   intent(in)    :: print_ar
            integer, allocatable :: pos(:,:)
            integer, allocatable :: imat_cc(:,:,:)
            logical, allocatable :: border(:,:,:)
            logical, allocatable :: mask_dist(:) !for min and max dist calculation
            integer :: location(1) !location of the farest vxls of the atom from its center
            integer :: i
            real    :: shortest_dist, longest_dist
            imat_cc = int(self%img_cc%get_rmat())
            call self%img_cc%border_mask(border, label, .true.) !use 4neigh instead of 8neigh
            where(border .eqv. .true.)
                imat_cc = 1
            elsewhere
                imat_cc = 0
            endwhere
            call get_pixel_pos(imat_cc,pos)   !pxls positions of the shell
            if(allocated(mask_dist)) deallocate(mask_dist)
            allocate(mask_dist(size(pos, dim = 2)), source = .true. )
            shortest_dist = pixels_dist(self%centers(:,label), real(pos),'min', mask_dist, location)
            if(size(pos,2) == 1) then !if the connected component has size 1 (just 1 vxl)
                shortest_dist = 0.
                longest_dist = shortest_dist
                ratio = 1.
                self%loc_longest_dist(:3, label) = self%centers(:,label)
            else
                longest_dist  = pixels_dist(self%centers(:,label), real(pos),'max', mask_dist, location)
                self%loc_longest_dist(:3, label) =  pos(:3,location(1))
            endif
            if(abs(longest_dist) > TINY .and. size(pos,2) > 1) then
                ratio = shortest_dist/longest_dist
            else
                ratio = 0.
                if(DEBUG_HERE) write(logfhandle,*) 'cc ', label, 'LONGEST DIST = 0'
            endif
            longest_dist  = longest_dist*self%smpd  !in A
            shortest_dist = shortest_dist*self%smpd
           if(present(print_ar) .and. (print_ar .eqv. .true.)) then
                write(logfhandle,*) 'ATOM #          ', label
                write(logfhandle,*) 'shortest dist = ', shortest_dist
                write(logfhandle,*) 'longest  dist = ', longest_dist
                write(logfhandle,*) 'RATIO         = ', ratio
           endif
           if(present(ld)) ld=longest_dist
           deallocate(imat_cc, border, pos, mask_dist)
        end subroutine calc_aspect_ratio_private
   end subroutine calc_aspect_ratio


    ! This subroutine calculates some statistics (min,max,avg,stdev)
    ! in the intensity gray level value of the nanoparticle
    ! map in each atom. It is likely that these statistics
    ! are going to be able to distinguish between the different
    ! atom compositions in heterogeneous nanoparticles.
    subroutine atom_intensity_stats(self)
        class(nanoparticle), intent(inout) :: self
        logical, allocatable :: mask(:,:,:)
        real,    pointer     :: rmat(:,:,:)
        real,    pointer     :: rmat_cc(:,:,:)
        integer :: n_atom
        integer :: i, j, k
        real    :: max_intensity(self%n_cc), avg_intensity(self%n_cc), stdev_intensity(self%n_cc)
        real    :: avg_int, stdev_int, max_int
        write(logfhandle,*)'**atoms intensity statistics calculations init'
        call self%img%get_rmat_ptr(rmat)
        call self%img_cc%get_rmat_ptr(rmat_cc)
        allocate(mask(self%ldim(1),self%ldim(2),self%ldim(3)), source = .false.)
        if(nint(maxval(rmat_cc)) .ne. self%n_cc) THROW_HARD('To check self%n_cc and self%img_cc; atom_intensity_stats')
        ! initialise
        max_intensity(:)   = 0.
        avg_intensity(:)   = 0.
        stdev_intensity(:) = 0.
        ! debugging
        ! Write on a file
        open(13, file = trim(self%output_dir)//'/IntensityStats.txt')
        do n_atom = 1, self%n_cc
            write(unit = 13, fmt = '(a,i3)') 'ATOM ', n_atom
            where(abs(rmat_cc(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)) - real(n_atom)) < TINY) mask = .true.
            max_intensity(n_atom) = maxval(rmat(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)),mask)
            avg_intensity(n_atom) = sum(rmat(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3)),mask)
            avg_intensity(n_atom) = avg_intensity(n_atom)/real(count(mask))
            do i = 1, self%ldim(1)
                do j = 1, self%ldim(2)
                    do k = 1, self%ldim(3)
                        if(mask(i,j,k)) stdev_intensity(n_atom) = stdev_intensity(n_atom) + (rmat(i,j,k)-avg_intensity(n_atom))**2
                    enddo
                enddo
            enddo
            stdev_intensity(n_atom) = sqrt(stdev_intensity(n_atom)/real(count(mask)-1))
            write(unit = 13, fmt = '(a,f6.5,a,f6.5,a,f6.5)') 'maxval ', max_intensity(n_atom), '   avg ', avg_intensity(n_atom), '   stdev ', stdev_intensity(n_atom)
            mask = .false. !Reset
        enddo
        avg_int   = sum(avg_intensity)/real(self%n_cc)
        max_int   = maxval(max_intensity)
        stdev_int = 0.
        do n_atom= 1, self%n_cc
            stdev_int = stdev_int + (avg_intensity(n_atom)-avg_int)**2
        enddo
        stdev_int = sqrt(stdev_int/real(self%n_cc-1))
        write(unit = 13, fmt = '(a,f6.5,a,f6.5,a,f6.5)') 'maxval_general ', max_int, '   avg_general ', avg_int, '   stdev_general ', stdev_int
        close(13)
        write(logfhandle,*)'**atoms intensity statistics calculations completed'
    end subroutine atom_intensity_stats

    ! Polarization search via angle variance. The considered angle is
    ! the angle between the vector [0,0,1] and the direction of the
    ! longest dim of the atom.
    ! This is done for each of the atoms and then there is a search
    ! of the similarity between the calculated angles.
    subroutine search_polarization(self)
        class(nanoparticle), intent(inout) :: self
        real    :: loc_ld_real(3,self%n_cc)
        real    :: vec_fixed(3)     !vector indentifying z direction
        real    :: theta, mod_1, mod_2, dot_prod
        integer :: k, i
        if(allocated(self%ang_var)) deallocate(self%ang_var)
           allocate (self%ang_var(self%n_cc), source = 0.)
        loc_ld_real(:3,:) = real(self%loc_longest_dist(:3,:))
        !consider fixed vector [0,0,1] (z direction)
        vec_fixed(1) = 0.
        vec_fixed(2) = 0.
        vec_fixed(3) = 1.
        write(logfhandle,*)'>>>>>>>>>>>>>>>> calculating angles wrt the vector [0,0,1]'
        !$omp parallel do schedule(static) private(k)
        do k = 1, self%n_cc
            self%ang_var(k) = ang3D_vecs(vec_fixed(:),loc_ld_real(:,k))
            if(DEBUG_HERE) write(logfhandle,*) 'ATOM ', k, 'angle between direction longest dim and vec [0,0,1] ', self%ang_var(k)
        enddo
        !$omp end parallel do
        ! Matlab compatible File
        ! open(129, file='AnglesLongestDims')
        ! write (129,*) 'ang=[...'
        ! do k = 1, self%n_cc
        !     write (129,'(A)', advance='no') trim(int2str(k))
        !     write (129,'(A)', advance='no') ', '
        !     write (129,'(A)', advance='no') trim(real2str(self%ang_var(k)))
        !     write (129,'(A)')'; ...'
        ! end do
        ! write (129,*) '];'
        ! close(129)
    end subroutine search_polarization

    ! Affinity propagation clustering based on teh distribuition of
    ! the atom distances within the nanoparticle.
    ! I want to study the dustribuition of the atom distances within the nanoparticle.
    ! For example, I would expect to have atoms close to eachother in the center
    ! and far apart in the surface.
    subroutine affprop_cluster_dist_distr(self)
        use simple_aff_prop
        use simple_atoms, only : atoms
        class(nanoparticle), intent(inout) :: self
        type(aff_prop)       :: ap_nano
        type(image), allocatable :: img_clusters(:)
        real, pointer            :: rmat_cc(:,:,:)
        real, allocatable        :: simmat(:,:)
        real                     :: simsum
        integer, allocatable     :: centers_ap(:), labels_ap(:)
        integer, allocatable     :: centers_merged(:), labels_merged(:)
        integer                  :: i, j, ncls, nerr
        integer                  :: dim
        integer, allocatable     :: imat_onecls(:,:,:,:)
        ! dim = self%n_cc ! TO FIX HERE. I SHOULD HAVE SELF%N_CC = SIZE(SELF%DISTS)
        dim = size(self%dists)
        allocate(simmat(dim, dim), source = 0.)
        write(logfhandle,*) '****clustering wrt distances distribution, init'
        do i=1,dim-1
            do j=i+1,dim
                simmat(i,j) = -sqrt((self%dists(i)-self%dists(j))**2)
                simmat(j,i) = simmat(i,j)
            end do
        end do
        call ap_nano%new(dim, simmat)
        call ap_nano%propagate(centers_ap, labels_ap, simsum)
        ncls = size(centers_ap)
        ! Report clusters on images in dedicated directory
        call simple_chdir(trim(self%output_dir),errmsg="simple_nanoparticles :: affprop_cluster_dist_distr, simple_chdir1; ")
        call simple_mkdir(trim(self%output_dir)//'/ClusterDistDistr',errmsg="simple_nanoparticles :: affprop_cluster_dist_distr, simple_mkdir; ")
        call simple_chdir(trim(self%output_dir)//'/ClusterDistDistr',errmsg="simple_nanoparticles :: affprop_cluster_dist_distr, simple_chdir; ")
        call self%img_cc%get_rmat_ptr(rmat_cc)
        allocate(imat_onecls(self%ldim(1),self%ldim(2),self%ldim(3), ncls), source = 0)
        allocate(img_clusters(ncls))
        !$omp do collapse(2) schedule(static) private(i,j)
        do i = 1, dim
            do j = 1, ncls
                call img_clusters(j)%new(self%ldim,self%smpd)
                if(labels_ap(i) == j) then
                    where(abs(rmat_cc(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3))-real(i))<TINY) imat_onecls(:,:,:,j) = 1
                endif
            enddo
        enddo
        !$omp end do
        !$omp parallel do schedule(static) private(j)
        do j = 1, ncls
            call img_clusters(j)%set_rmat(real(imat_onecls(:,:,:,j)))
            call img_clusters(j)%write(int2str(j)//'ClusterDistDistr.mrc')
            call img_clusters(j)%kill
        enddo
        !$omp end parallel do
        if(allocated(img_clusters)) deallocate(img_clusters)
        if(allocated(imat_onecls))  deallocate(imat_onecls)
        open(125, file = 'ClusterDistDistr')
        write(unit = 125, fmt = '(a,i2)') 'NR OF CLUSTERS FOUND DISTS DISTR:', ncls
        do i = 1, dim
            call self%centers_pdb%set_beta(i, real(labels_ap(i)))
        enddo
        write(unit = 125, fmt = '(a)') 'CENTERS DISTS DISTR'
        do i=1,ncls
            write(unit = 125, fmt = '(f6.3)') self%dists(centers_ap(i))
        end do
        call self%centers_pdb%writepdb('ClusterDistDistr')
        close(125)
        write(logfhandle,*) '****clustering wrt distances distribution, completed'
        deallocate(simmat, labels_ap, centers_ap)
    end subroutine affprop_cluster_dist_distr

    !Affinity propagation clustering based on aspect ratios
    subroutine affprop_cluster_ar(self)
        use simple_aff_prop
        class(nanoparticle), intent(inout) :: self
        type(aff_prop)           :: ap_nano
        type(image), allocatable :: img_clusters(:)
        real, pointer            :: rmat_cc(:,:,:)
        real,    allocatable     :: simmat(:,:)
        integer, allocatable     :: imat_onecls(:,:,:,:)
        integer, allocatable     :: centers_ap(:), labels_ap(:)
        real                     :: simsum
        integer                  :: i, j, ncls, nerr
        integer                  :: dim
        dim = size(self%ratios)
        allocate(simmat(dim, dim), source = 0.)
        write(logfhandle,*) '****clustering wrt aspect ratios, init'
        do i=1,dim-1
            do j=i+1,dim
                simmat(i,j) = -sqrt((self%ratios(i)-self%ratios(j))**2)
                simmat(j,i) = simmat(i,j)
            end do
        end do
        call ap_nano%new(dim, simmat)
        call ap_nano%propagate(centers_ap, labels_ap, simsum)
        ncls = size(centers_ap)
        ! Report clusters on images in dedicated directory
        call simple_chdir(trim(self%output_dir),errmsg="simple_nanoparticles :: affprop_cluster_ar, simple_chdir1; ")
        call simple_mkdir(trim(self%output_dir)//'/ClusterAspectRatio',errmsg="simple_nanoparticles :: affprop_cluster_ar, simple_mkdir; ")
        call simple_chdir(trim(self%output_dir)//'/ClusterAspectRatio',errmsg="simple_nanoparticles :: affprop_cluster_ar, simple_chdir; ")
        call self%img_cc%write('IMG_CC_IN_CLUSTER_AR.mrc')
        call self%img_cc%get_rmat_ptr(rmat_cc)
        allocate(imat_onecls(self%ldim(1),self%ldim(2),self%ldim(3), ncls), source = 0)
        allocate(img_clusters(ncls))
        !$omp do collapse(2) schedule(static) private(i,j)
        do i = 1, dim
            do j = 1, ncls
                call img_clusters(j)%new(self%ldim,self%smpd)
                if(labels_ap(i) == j) then
                        where(abs(rmat_cc(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3))-real(i))<TINY) imat_onecls(:,:,:,j) = 1
                endif
            enddo
        enddo
        !$omp end do
        !$omp parallel do schedule(static) private(j)
        do j = 1, ncls
            call img_clusters(j)%set_rmat(real(imat_onecls(:,:,:,j)))
            call img_clusters(j)%write(int2str(j)//'ClusterAr.mrc')
            call img_clusters(j)%kill
        enddo
        !$omp end parallel do
        if(allocated(img_clusters)) deallocate(img_clusters)
        if(allocated(imat_onecls))  deallocate(imat_onecls)
        open(119, file='ClusterAspectRatio')
        write(unit = 119,fmt ='(a,i2)') 'NR OF CLUSTERS FOUND AR:', ncls
        do i = 1, dim
            call self%centers_pdb%set_beta(i, real(labels_ap(i)))
        enddo
        write(unit = 119, fmt = '(a)') 'CENTERS AR'
        do i=1,size(centers_ap)
            write(unit = 119, fmt = '(f6.3)') self%ratios(centers_ap(i))
        end do
        call self%centers_pdb%writepdb('ClustersAspectRatio')
        close(119)
        write(logfhandle,*) '****clustering wrt aspect ratios, completed'
        deallocate(simmat, labels_ap, centers_ap)
    end subroutine affprop_cluster_ar

    ! Affinity propagation clustering based on agles wrt vec [0,0,1].
    subroutine affprop_cluster_ang(self)
        use simple_aff_prop
        use simple_atoms, only : atoms
        class(nanoparticle), intent(inout) :: self
        type(aff_prop)           :: ap_nano
        type(image), allocatable :: img_clusters(:)
        real, pointer            :: rmat_cc(:,:,:)
        real,    allocatable     :: simmat(:,:)
        real,    allocatable     :: avg_within(:), stdev_within(:)
        integer, allocatable     :: centers_ap(:), labels_ap(:)
        integer, allocatable     :: imat_onecls(:,:,:,:)
        integer                  :: i, j, ncls, nerr
        integer                  :: dim
        real                     :: simsum
        real                     :: avg, stdev
        integer, allocatable     :: cnt(:)
        dim = size(self%ang_var)!self%n_cc
        allocate(simmat(dim, dim), source = 0.)
        write(logfhandle,*) '****clustering wrt direction longest dim, init'
        do i=1,dim-1
            do j=i+1,dim
                simmat(i,j) = -sqrt((self%ang_var(i)-self%ang_var(j))**2)
                simmat(j,i) = simmat(i,j)
            end do
        end do
        call ap_nano%new(dim, simmat)
        call ap_nano%propagate(centers_ap, labels_ap, simsum)
        ncls = size(centers_ap)
        ! Report clusters on images in dedicated directory
        call simple_chdir(trim(self%output_dir),errmsg="simple_nanoparticles :: affprop_cluster_ang, simple_chdir1; ")
        call simple_mkdir(trim(self%output_dir)//'/ClusterAngLongestDim',errmsg="simple_nanoparticles :: affprop_cluster_ang, simple_mkdir; ")
        call simple_chdir(trim(self%output_dir)//'/ClusterAngLongestDim',errmsg="simple_nanoparticles :: affprop_cluster_ang, simple_chdir; ")
        call self%img_cc%get_rmat_ptr(rmat_cc)
        allocate(imat_onecls(self%ldim(1),self%ldim(2),self%ldim(3), ncls), source = 0)
        allocate(img_clusters(ncls))
        !$omp do collapse(2) schedule(static) private(i,j)
        do i = 1, dim
            do j = 1, ncls
                call img_clusters(j)%new(self%ldim,self%smpd)
                if(labels_ap(i) == j) then
                    where(abs(rmat_cc(1:self%ldim(1),1:self%ldim(2),1:self%ldim(3))-real(i))<TINY) imat_onecls(:,:,:,j) = 1
                endif
            enddo
        enddo
        !$omp end do
        !$omp parallel do schedule(static) private(j)
        do j = 1, ncls
            call img_clusters(j)%set_rmat(real(imat_onecls(:,:,:,j)))
            call img_clusters(j)%write(int2str(j)//'ClusterAng.mrc')
            call img_clusters(j)%kill
        enddo
        !$omp end parallel do
        if(allocated(img_clusters)) deallocate(img_clusters)
        if(allocated(imat_onecls))  deallocate(imat_onecls)
        open(111, file='ClusterAngLongestDim')
        write(unit = 111,fmt ='(a,i2)') 'NR OF CLUSTERS FOUND ANG:', ncls
        do i = 1, dim
            call self%centers_pdb%set_beta(i, real(labels_ap(i)))
        enddo
        write(unit = 111,fmt ='(a)') 'CENTERS ANG'
        do i=1,ncls
            write(unit = 111,fmt ='(f6.3)') self%ang_var(centers_ap(i))
        end do
        !standard deviation within each center
        allocate(  avg_within(ncls), source = 0.)
        allocate(stdev_within(ncls), source = 0.)
        allocate(cnt(ncls), source = 0)
        !$omp do collapse(2) schedule(static) private(i,j)
        do i = 1, ncls
            do j = 1, dim
                if(labels_ap(j) == i) then
                    cnt(i) = cnt(i) + 1 !cnt is how many atoms I have in each class
                    avg_within(i) = avg_within(i) + self%ang_var(j)
            endif
            enddo
        enddo
        !$omp end do
        avg_within = avg_within/cnt
        write(unit = 111,fmt ='(a,i3)')     'number of atoms in each class = ', cnt(1)
        do i =2, ncls
            write(unit = 111,fmt ='(a,i3)') '                                ', cnt(i)
        enddo
        write(unit = 111,fmt ='(a,i3)')     'total atoms =                   ', sum(cnt)
        !$omp do collapse(2) schedule(static) private(i,j)
        do i = 1, ncls
            do j = 1, dim
                if(labels_ap(j) == i) stdev_within(i) = stdev_within(i) + (self%ang_var(j)-avg_within(i))**2
            enddo
        enddo
        !$omp end do
        stdev_within = stdev_within/(cnt-1.)
        stdev_within = sqrt(stdev_within)
        write(unit = 111,fmt ='(a,f5.3)')  'stdev_within = ', stdev_within(1)
        do i = 2, ncls
            write(unit = 111,fmt ='(a,f5.3)')   '               ', stdev_within(i)
        enddo
        !standard deviation among different centers
        avg = 0.
        do i = 1, ncls
            avg = avg + self%ang_var(centers_ap(i))
        enddo
        avg = avg/real(ncls)
        stdev = 0.
        do i = 1, ncls
            stdev = stdev + (self%ang_var(centers_ap(i)) - avg)**2
        enddo
        stdev = stdev/(real(ncls)-1.)
        stdev = sqrt(stdev)
        write(unit = 111,fmt ='(a,f5.3)') 'standard deviation among centers: ', stdev
        call self%centers_pdb%writepdb('ClusterAngLongestDim')
        close(111)
        write(logfhandle,*) '****clustering wrt direction longest dim, completed'
        deallocate(simmat, labels_ap, centers_ap)
        if(allocated(cnt))          deallocate(cnt)
        if(allocated(avg_within))   deallocate(avg_within)
        if(allocated(stdev_within)) deallocate(stdev_within)
    end subroutine affprop_cluster_ang

    subroutine nanopart_cluster(self)
        class(nanoparticle), intent(inout) :: self
        ! clustering wrt to angle longest_dim-vector z=[0,0,1]
        call self%affprop_cluster_ang()
        ! clustering wrt aspect ratio
        call self%affprop_cluster_ar()
        ! clustering wrt interatomic distances distribution
        call self%affprop_cluster_dist_distr()
    end subroutine nanopart_cluster

    ! This subrotuine indentifies the 'rows' of atoms in the z direction.
    ! The idea is to look at the projection of the nanoparticle on the
    ! xy plane and identify all the atoms whose center has (almost, see
    ! MAX_DIST_CENTERS) the same x and y coords.
    ! The inputs are:
    ! -) centers, coordinates of the centers of mass of the atoms;
    ! For how it is built, self%centers(:3,i) contains the coords of the
    ! center of mass of the i-th cc.
    subroutine make_soft_mask(self) !change the name
        class(nanoparticle), intent(inout) :: self
        call self%img_bin%grow_bins(nint(0.5*self%avg_dist_atoms)+1)
        call self%img_bin%cos_edge(6)
        call simple_chdir(trim(self%output_dir),errmsg="simple_nanoparticles :: make_soft_mask, simple_chdir1; ")
        call self%img_bin%write(basename(trim(self%fbody))//'SoftMask.mrc')
    end subroutine make_soft_mask

    ! This subroutine takes in input 2 nanoparticle and their
    ! correspondent filenames.
    ! The output is the rmsd of their atomic models.
    subroutine compare_atomic_models(nano1,nano2)
        class(nanoparticle), intent(inout) :: nano1, nano2 !nanoparticles to compare
        real, allocatable :: centers1(:,:), centers2(:,:)
        real    :: ada       ! minimum average dist atoms between nano1 and nano2
        real    :: rmsd
        integer :: i
        logical :: print_ar ! for printing aspect ratios statistics
        logical :: print_as ! for printing asymmetric units in c3-sym nanoparticles
        real    :: ot1, ot2 ! otsh thresholds
        print_ar = .false.
        print_as = .false.
        if(print_as) then
            call nano1%print_asym_unit(3)
            call nano2%print_asym_unit(3)
        endif
        open(121, file='CompareAtomicModels')
        write(unit = 121, fmt = '(a)') '>>>>>>>>>   COMPARE NANO   >>>>>>>>>'
        write(unit = 121, fmt = '(a)') ''
        write(unit = 121, fmt = '(a)') 'Comparing atomic models of particles'
        write(unit = 121, fmt = '(a,a)') trim(nano1%fbody), ' ---> vol1'
        write(unit = 121, fmt = '(a)') 'and'
        write(unit = 121, fmt = '(a,a)') trim(nano2%fbody), ' ---> vol2'
        write(unit = 121, fmt = '(a)')  '>>>>>>>>>VOLUME COMPARISION>>>>>>>>'
        call nano1%phasecorrelation_nano_gaussian(ot1)
        call nano2%phasecorrelation_nano_gaussian(ot2)
        call nano1%binarize(ot1)
        call nano2%binarize(ot2)
        ! TO FIX!!!!!!!!!!!!!! HEREEE
        !Distance distribution calculation
        call nano1%distances_distribution()
        call nano2%distances_distribution()
        ! Outliers discarding
        call nano1%discard_outliers()
        call nano2%discard_outliers()
        ! Validate identified positions
        call nano1%validate_atomic_positions()
        call nano2%validate_atomic_positions()
        ! Radial dependent statistics calculation
        call nano1%radial_dependent_stats(1)
        call nano2%radial_dependent_stats(2)
        ! Aspect ratios calculations
        call nano1%calc_aspect_ratio(print_ar)
        call nano2%calc_aspect_ratio(print_ar)
        ! Atomic intensity stats
        call nano1%atom_intensity_stats()
        call nano2%atom_intensity_stats()
        ! Ouput file, come back to initial folder
        call simple_chdir(trim(nano1%output_dir), errmsg="simple_nanoparticles :: compare_atomic_models, simple_chdir; ")
        write(unit = 121, fmt = '(a,f6.3,a)') 'avg dist between atoms in vol1:', nano1%avg_dist_atoms*nano1%smpd,' A'
        write(unit = 121, fmt = '(a,f6.3,a)') 'avg dist between atoms in vol2:', nano2%avg_dist_atoms*nano2%smpd,' A'
        ! RMSD calculation
        ada = min(nano1%avg_dist_atoms, nano2%avg_dist_atoms)
        call atomic_position_rmsd(nano1,nano2, ada, rmsd)
        write(logfhandle,*) '***comparison completed'
        close(121)
        call nano1%kill
        call nano2%kill
        if(allocated(centers1)) deallocate(centers1)
        if(allocated(centers2)) deallocate(centers2)
    contains

        ! This subroutine takes in input coords of the atomic positions
        ! in the nanoparticles to compare and calculates the rmsd
        ! between them.
        ! See formula
        ! https://en.wikipedia.org/wiki/Root-mean-square_deviation_of_atomic_positions
        subroutine atomic_position_rmsd(nano1,nano2,ada,r)
            use simple_atoms, only : atoms
            use gnufor2
            class(nanoparticle), intent(inout) :: nano1, nano2 !nanoparticles to compare
            real,           intent(in)  :: ada !minimum average dist atoms between nano1 and nano2
            real, optional, intent(out) :: r   !rmsd calculated
            logical, allocatable :: mask(:)
            real,    allocatable :: dist(:), dist_sq(:), dist_no_zero(:), dist_close(:)
            integer :: location(1)
            integer :: i, j
            integer :: N_min !min{nb atoms in nano1, nb atoms in nano2}
            integer :: N_max !max{nb atoms in nano1, nb atoms in nano2}
            integer :: cnt,cnt2,cnt3
            real    :: sum, rmsd
            real :: coord(3)
            real :: avg, stdev, m(3), tmp_max, d !for statistics calculation
            type(atoms) :: centers_coupled1, centers_coupled2 !visualization purposes
            type(atoms) :: centers_close1, centers_close2
            type(atoms) :: couples1
            ! If they don't have the same nb of atoms
            if(size(nano1%centers, dim = 2) <= size(nano2%centers, dim = 2)) then
                N_min = size(nano1%centers, dim = 2)
                N_max = size(nano2%centers, dim = 2)
                write(unit = 121, fmt = '(a,i3)') 'NB atoms in vol1   ', N_min
                write(unit = 121, fmt = '(a,i3)') 'NB atoms in vol2   ', N_max
                write(unit = 121, fmt = '(a,i3,a)') '--->', abs(N_max-N_min), ' atoms do NOT correspond'
                call centers_coupled1%new(N_max, dummy=.true.)
                call centers_coupled2%new(N_max, dummy=.true.)
                call centers_close1%new  (N_max, dummy=.true.)
                call centers_close2%new  (N_max, dummy=.true.)
                call couples1%new        (N_max, dummy=.true.)
                allocate(dist(N_max), dist_sq(N_max), source = 0.)
                allocate(dist_close(N_max), source = 0.) ! there are going to be unused entry of the vector
                allocate(mask(N_min), source = .true.)
                cnt = 0
                cnt2= 0
                ! TO PARALLELISE
                do i = 1, N_max !compare based on centers2
                    dist(i) = pixels_dist(nano2%centers(:,i),nano1%centers(:,:),'min',mask,location)
                    if(dist(i)*nano2%smpd > 2.2) then
                        dist(i) = 0. !it means there is no correspondent atom in the other nano
                        cnt = cnt+1  !to discard them in the rmsd calculation
                        call couples1%set_coord(i,(nano2%centers(:,location(1))-1.)*nano2%smpd)
                        ! remove the atoms from the pdb file
                        call centers_coupled1%set_occupancy(i,0.)
                        call centers_coupled2%set_occupancy(i,0.)
                        call centers_close1%set_occupancy(i,0.)
                        call centers_close2%set_occupancy(i,0.)
                        call couples1%set_occupancy(i,0.)
                    elseif(dist(i)*nano2%smpd < 0.5) then
                        dist_close(i) = dist(i)**2
                        call centers_close2%set_coord(i,(nano2%centers(:,i)-1.)*nano2%smpd)
                        call centers_close1%set_coord(i,(nano1%centers(:,location(1))-1.)*nano1%smpd)
                        ! remove the atoms from the pdb file
                        call centers_coupled1%set_occupancy(i,0.)
                        call centers_coupled2%set_occupancy(i,0.)
                        call couples1%set_occupancy(i,0.)
                    elseif(dist(i)*nano2%smpd > 0.5 .and. dist(i)*nano2%smpd<=2.2 ) then  !to save the atoms which correspond with a precision in the range [0,220] pm
                        cnt2 = cnt2 + 1
                        call centers_coupled2%set_coord(i,(nano2%centers(:,i)-1.)*nano2%smpd)
                        call centers_coupled1%set_coord(i,(nano1%centers(:,location(1))-1.)*nano1%smpd)
                        call couples1%set_coord(i,(nano2%centers(:,location(1))-1.)*nano2%smpd)
                        mask(location(1)) = .false. ! not to consider the same atom more than once
                        ! remove the atoms from the pdb file
                        call centers_close1%set_occupancy(i,0.)
                        call centers_close2%set_occupancy(i,0.)
                    endif
                    dist_sq(i) = dist(i)**2 !formula wants them square, could improve performance here
                    if(DEBUG_HERE) then
                         write(logfhandle,*) 'ATOM', i,'coords: ', nano2%centers(:,i), 'coupled with '
                         write(logfhandle,*) '    ',location, 'coordinates: ', nano1%centers(:,location(1)), 'DIST^2= ', dist_sq(i), 'DIST = ', dist(i)
                    endif
                enddo
                ! END PARALLELISATION
            else
                N_min = size(nano2%centers, dim = 2)
                N_max = size(nano1%centers, dim = 2)
                write(unit = 121, fmt = '(a,i3)') 'NB atoms in vol1   ', N_max
                write(unit = 121, fmt = '(a,i3)') 'NB atoms in vol2   ', N_min
                write(unit = 121, fmt = '(i3,a)') abs(N_max-N_min), 'atoms do NOT correspond'
                allocate(dist(N_max), dist_sq(N_max), source = 0.)
                allocate(dist_close(N_max), source = 0.) ! there are going to be unused entry of the vector
                call centers_coupled1%new(N_max, dummy=.true.)
                call centers_coupled2%new(N_max, dummy=.true.)
                call centers_close1%new  (N_max, dummy=.true.)
                call centers_close2%new  (N_max, dummy=.true.)
                allocate(mask(N_min), source = .true.)
                cnt = 0
                cnt2= 0
                ! TO PARALLELISE
                do i = 1, N_max !compare based on centers1
                    dist(i) = pixels_dist(nano1%centers(:,i),nano2%centers(:,:),'min',mask,location)
                    if(dist(i)*nano2%smpd > 2.2) then ! 2.2 is the biggest lattice spacing they found in the paper
                        dist(i) = 0.
                        cnt = cnt+1
                        call couples1%set_coord(i,(nano1%centers(:,location(1))-1.)*nano1%smpd)
                        ! remove the atoms from the pdb file
                        call centers_coupled1%set_occupancy(i,0.)
                        call centers_coupled2%set_occupancy(i,0.)
                        call centers_close1%set_occupancy(i,0.)
                        call centers_close2%set_occupancy(i,0.)
                        call couples1%set_occupancy(i,0.)
                    elseif(dist(i)*nano2%smpd <= 0.5) then
                            dist_close(i) = dist(i)**2
                            call centers_close1%set_coord(i,(nano1%centers(:,i)-1.)*nano1%smpd)
                            call centers_close2%set_coord(i,(nano2%centers(:,location(1))-1.)*nano2%smpd)
                            ! remove the atoms from the pdb file
                            call centers_coupled1%set_occupancy(i,0.)
                            call centers_coupled2%set_occupancy(i,0.)
                            call couples1%set_occupancy(i,0.)
                    elseif(dist(i)*nano2%smpd > 0.5 .and. dist(i)*nano2%smpd<=2.2 ) then  !to save the atoms which correspond with a precision in the range [0,220] pm
                        cnt2 = cnt2 + 1
                            call centers_coupled1%set_coord(i,(nano1%centers(:,i)-1.)*nano1%smpd)
                            call centers_coupled2%set_coord(i,(nano2%centers(:,location(1))-1.)*nano2%smpd)
                            call couples1%set_coord(i,(nano1%centers(:,location(1))-1.)*nano1%smpd)
                            mask(location(1)) = .false. ! not to consider the same atom more than once
                            ! remove the atoms from the pdb file
                            call centers_close1%set_occupancy(i,0.)
                            call centers_close2%set_occupancy(i,0.)
                    endif
                    dist_sq(i) = dist(i)**2 !formula wants them square
                    if(DEBUG_HERE) then
                        write(logfhandle,*) 'ATOM', i,'coordinates: ', nano1%centers(:,i), 'coupled with '
                        write(logfhandle,*) '    ',location, 'coordinates: ', nano2%centers(:,location(1)), 'DIST^2= ', dist_sq(i), 'DIST = ', dist(i)
                    endif
                enddo
                ! END PARALLELISATION
            endif
            ! remove unused atoms from the pdb file
            !TO PARALLELISE
            do i = 1, N_max
                coord(:) = centers_close1%get_coord(i)
                if(coord(1)<TINY .and. coord(2)<TINY .and. coord(3)<TINY) call centers_close1%set_occupancy(i,0.)
                coord(:) = centers_close2%get_coord(i)
                if(coord(1)<TINY .and. coord(2)<TINY .and. coord(3)<TINY) call centers_close2%set_occupancy(i,0.)
                coord(:) = centers_coupled1%get_coord(i)
                if(coord(1)<TINY .and. coord(2)<TINY .and. coord(3)<TINY) call centers_coupled1%set_occupancy(i,0.)
                coord(:) = centers_coupled2%get_coord(i)
                if(coord(1)<TINY .and. coord(2)<TINY .and. coord(3)<TINY) call centers_coupled2%set_occupancy(i,0.)
            enddo
            ! END PARALLELISATION
            call centers_close1%writepdb  (trim(nano1%fbody)//'_atom_close_couples')
            call centers_close2%writepdb  (trim(nano2%fbody)//'_atom_close_couples')
            call centers_coupled1%writepdb(trim(nano1%fbody)//'_atom_couples')
            call centers_coupled2%writepdb(trim(nano2%fbody)//'_atom_couples')
            call couples1%writepdb('extra_atoms')
            !Avg dist and stdev symmetry breaking atoms from the center
            !Max dist atoms from the center
            avg = 0.
            cnt3 = 0
            m(:) = nano1%nanopart_masscen()
            m(:) = (m(:)-1.)*nano1%smpd
            tmp_max = 0.
            !TO PARALLELISE
            do i = 1, N_max
                coord(:) = centers_coupled1%get_coord(i)
                if(coord(1)>TINY .and. coord(2)>TINY .and. coord(3)>TINY) then
                    cnt3 = cnt3 + 1
                    avg = avg + euclid(coord,m)
                    if(euclid(coord,m) > tmp_max) tmp_max = euclid(coord,m)
                endif
            enddo
            ! END PARALLELISATION
            avg = avg/real(cnt3)
            cnt3 = 0
            stdev = 0.
            !TO PARALLELISE
            do i = 1, N_max
                coord(:) = centers_coupled1%get_coord(i)
                if(coord(1)>TINY .and. coord(2)>TINY .and. coord(3)>TINY) then
                    cnt3 = cnt3 + 1
                    stdev = stdev + (euclid(coord,m)-avg)**2
                endif
            enddo
            ! END PARALLELISATION
            stdev = sqrt(stdev/(real(cnt3)-1.))
            write(unit = 121, fmt = '(a,f6.3,a)')'AVG     DIST ATOMS THAT BREAK THE SYMMETRY TO THE CENTER: ', avg, ' A'
            write(unit = 121, fmt = '(a,f6.3,a)')'STDEV   DIST ATOMS THAT BREAK THE SYMMETRY TO THE CENTER: ', stdev, ' A'
            write(unit = 121, fmt = '(a,f6.3,a)')'MAX     DIST ATOMS THAT BREAK THE SYMMETRY TO THE CENTER: ', tmp_max, ' A'
            tmp_max = 0. ! reset
            !TO PARALLELISE
            do i = 1, size(nano1%centers, dim = 2)
                coord(:) = (nano1%centers(:,i)-1.)*nano1%smpd
                    d =  euclid(coord,m)
                    if(d > tmp_max) tmp_max = d
            enddo
            !END PARALLELISATION
            write(unit = 121, fmt = '(a,f6.3,a)')'MAX     DIST ATOMS IN VOL1 3D RECONSTRUCT. TO THE CENTER: ', tmp_max, ' A'
            ! kill atoms instances
            call centers_close1%kill
            call centers_close2%kill
            call centers_coupled1%kill
            call centers_coupled2%kill
            call couples1%kill
            !RMSD
            rmsd = sqrt(sum(dist_sq)/real(count(dist_sq > TINY)))
            dist_no_zero = pack(dist, dist>TINY)
            dist_no_zero = dist_no_zero*nano1%smpd ! report distances in Amstrongs
            call hist(dist_no_zero, 50)
            ! !Output on file, Matlab Compatible
            ! open(119, file='RMSDhist')
            ! write (119,*) 'r=[...'
            ! do i = 1, size(dist_no_zero)
            !     write (119,'(A)', advance='no') trim(real2str(dist_no_zero(i)))
            !     if(i < size(dist_no_zero)) write (119,'(A)', advance='no') ', '
            ! end do
            ! write (119,*) '];'
            ! close(119)
            !For SCV files
            open(117, file='RMSDhist')
            write (117,*) 'r'
            do i = 1, size(dist_no_zero)
                write (117,'(A)', advance='yes') trim(real2str(dist_no_zero(i)))
            end do
            close(117)
            write(unit = 121, fmt = '(i3,a,i2,a)') count(dist_no_zero <= 0.5),' atoms correspond withing      50 pm. (',count(dist_no_zero <= 0.5)*100/(N_min), '% of the atoms )'
            write(unit = 121, fmt = '(i3,a,i2,a)')  cnt-(N_max-N_min),        ' atoms have error bigger than 220 pm. (', (cnt-N_max+N_min)*100/N_min, '% of the atoms )'
            write(unit = 121, fmt = '(a,f6.3,a)') 'RMSD CALCULATED CONSIDERING ALL ATOMS   = ', rmsd*nano1%smpd, ' A'
            write(unit = 121, fmt = '(a,f6.3,a)') 'RMSD ATOMS THAT CORRESPOND WITHIN 50 PM = ', (sqrt(sum(dist_close)/real(count(dist_close > TINY))))*nano1%smpd, ' A'
            if(present(r)) r=rmsd
            deallocate(dist, dist_sq, dist_no_zero, mask)
        end subroutine atomic_position_rmsd
    end subroutine compare_atomic_models

    ! Check for symmetry at different radii.
    ! radii: 5, 7, 9, 12 A
    ! The idea is to identify the atomic positions
    ! contained in a certain radius, generate a distribution
    ! based on that and check for symmetry.
    subroutine identify_atomic_pos(self, atomic_pos)
        class(nanoparticle), intent(inout) :: self
        character(len=100),  intent(inout) :: atomic_pos
        real :: otsu_thresh
        ! Phase correlations approach
        call self%phasecorrelation_nano_gaussian(otsu_thresh)
        ! Nanoparticle binarization
        call self%binarize(otsu_thresh)
        ! Atom-to-atom distances distribution estimation
        call self%distances_distribution() !needed for discard_outliers
        ! Outliers discarding
        call self%discard_outliers()
       ! Validation of the selected atomic positions
        call self%validate_atomic_positions()
        atomic_pos = trim(self%fbody)//'_atom_centers.pdb'
    end subroutine identify_atomic_pos

    subroutine keep_atomic_pos_at_radius(self, radius, element, fname)
      class(nanoparticle), intent(inout) :: self
      real,                intent(in)    :: radius
      character(len=2),    intent(in)    :: element
      character(len=*),    intent(in)    :: fname !name of the pdb file where to write the coords
      character(len=4) :: atom_name
      integer     :: n_cc,cnt
      real        :: m(3) !coords of the center of mass of the nano
      real        :: d    !distance of the atom from the center of mass
      type(atoms) :: radial_atom
      ! Make subroutine for set_atom_name()
      select case(element)
      case('pt')
          atom_name     = ' pt '
          ! thoretical radius is already set
      case('pd')
          atom_name     = ' pd '
      case('fe')
          atom_name     = 'fe'
      case('au')
          self%atom_name     = ' au '
      case default
          THROW_HARD('Unknown atom element; keep_atomic_pos_at_radius')
     end select
      cnt = 0
      m = self%nanopart_masscen()
      ! Count nb of atoms in the selected radius
      do n_cc = 1, self%n_cc
            d = euclid(self%centers(:,n_cc), m)*self%smpd
           if(d<=radius) then
               cnt = cnt+1
           endif
      enddo
      call radial_atom%new (cnt, dummy=.true.)
      cnt = 0
      ! Fill in radial_atom with the atomic positions
      do n_cc = 1, self%n_cc
          d = euclid(self%centers(:,n_cc), m)*self%smpd
          if(d<=radius) then
             cnt = cnt+1
             call radial_atom%set_element(cnt,element)
             call radial_atom%set_name(cnt,atom_name)
             call radial_atom%set_coord(cnt,(self%centers(:,n_cc)-1.)*self%smpd)
           endif
      enddo
      call radial_atom%writepdb(fname)
    end subroutine keep_atomic_pos_at_radius

    ! This is the subroutine that executes all the steps
    ! for the structural analysis of one nananoparticle
    ! 3D reconstruction.
     subroutine detect_atoms(self)
         class(nanoparticle), intent(inout) :: self
         real :: otsu_thresh
         ! Phase correlations approach
         call self%phasecorrelation_nano_gaussian(otsu_thresh)
         ! Nanoparticle binarization
         call self%binarize(otsu_thresh)
         ! Atom-to-atom distances distribution estimation
         call self%distances_distribution() !needed for discard_outliers
         ! Outliers discarding
         call self%discard_outliers()
        ! Validation of the selected atomic positions
         call self%validate_atomic_positions()
         ! Radial dependent statistics calculation
         call self%radial_dependent_stats()
         ! Aspect ratios calculations
         call self%calc_aspect_ratio(print_ar=.false.)
         ! Atomic intensity stats calculation
         call self%atom_intensity_stats()
         ! Polarization search
         call self%search_polarization()
         ! Clustering
         call self%cluster
         ! Make soft mask
         call self%make_soft_mask()
     end subroutine detect_atoms

    subroutine kill_nanoparticle(self)
        class(nanoparticle), intent(inout) :: self
        self%ldim(3)           = 0
        self%smpd              = 0.
        self%nanop_mass_cen(3) = 0.
        self%avg_dist_atoms    = 0.
        self%n_cc              = 0
        call self%img%kill()
        call self%img_bin%kill()
        call self%img_cc%kill()
        call self%centers_pdb%kill
        if(allocated(self%centers))          deallocate(self%centers)
        if(allocated(self%ratios))           deallocate(self%ratios)
        if(allocated(self%dists))            deallocate(self%dists)
        if(allocated(self%loc_longest_dist)) deallocate(self%loc_longest_dist)
        if(allocated(self%ang_var))          deallocate(self%ang_var)
    end subroutine kill_nanoparticle
end module simple_nanoparticles_mod

    ! This subroutine performs size filtering on the connected
    ! components image of the nanoparticle. It calculates the
    ! size of all the connected components, the average and the standard
    ! deviation. It hypothesises gaussian distribution, so it discards
    ! the connected components which are outside the range [-2sigma,2sigma].
    ! subroutine size_filtering(self)
    !     class(nanoparticle), intent(inout) :: self
    !     integer, allocatable :: sz(:)
    !     real, pointer :: rmat(:,:,:)
    !     real, pointer :: rmat_cc(:,:,:)
    !     integer :: cc
    !     real    :: avg_sz
    !     real    :: stdev_sz
    !     write(logfhandle, *) '****size filtering, init'
    !     call self%img_bin%get_rmat_ptr(rmat)
    !     call self%img_cc%get_rmat_ptr(rmat_cc)
    !     sz = self%img_cc%size_connected_comps()
    !     avg_sz = real(sum(sz))/real(size(sz))
    !     stdev_sz = 0.
    !     do cc = 1, size(sz)
    !         stdev_sz = stdev_sz + (sz(cc) - avg_sz)**2
    !     enddo
    !     stdev_sz = sqrt(stdev_sz/(real(size(sz)-1)))
    !     !assuming Gaussian distrib, 95% is in [-2sigma,2sigma] and 68% is in [-sigma,sigma]
    !     !big ccs have already been removed by erosion. Now we need to remove too small
    !     !ccs, they usually represent background noise.
    !     !$omp do collapse(1) schedule(static) private(cc)
    !     do cc = 1, size(sz)
    !         if(sz(cc)<avg_sz-2.*stdev_sz ) then
    !             where(abs(rmat_cc-real(cc)) < TINY)
    !                 rmat_cc = 0.
    !                 rmat    = 0.
    !             endwhere
    !          endif
    !     enddo
    !     !$omp end do
    !     !update img_cc: re-order ccs
    !     call self%img_cc%order_cc()
    !     ! UPDATE IMG_BIN???
    !     call self%img_cc%write('AfterSizeFiltering.mrc')
    !     !update n_cc
    !     self%n_cc = nint(maxval(rmat_cc))
    !     !update centers
    !     call self%find_centers()
    !     write(logfhandle, *) '****size filtering, completed'
    !     deallocate(sz)
    ! end subroutine size_filtering

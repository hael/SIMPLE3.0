!==Class simple_build
!
! simple_build is the builder class for the methods in _SIMPLE_. Access is global in the
! using unit. The code is distributed with the hope that it will be useful, but _WITHOUT_ _ANY_ _WARRANTY_.
! Redistribution or modification is regulated by the GNU General Public License. 
! *Author:* Hans Elmlund, 2009-06-11.
! 
!==Changes are documented below
!
!* deugged and incorporated in the _SIMPLE_ library, HE 2009-06-25
!* reshaped according to the new simple_params class that will deal with all global parameters, HE 2011-08-18
!* rewritten with the new language features, HE 2012-06-18
!
module simple_build
use simple_defs
use simple_cmdline,          only: cmdline
use simple_comlin,           only: comlin
use simple_image,            only: image
use simple_centre_clust,     only: centre_clust
use simple_oris,             only: oris
use simple_pair_dtab,        only: pair_dtab
use simple_ppca,             only: ppca
use simple_projector,        only: projector
use simple_reconstructor,    only: reconstructor
use simple_eo_reconstructor, only: eo_reconstructor
use simple_params,           only: params
use simple_sym,              only: sym
use simple_polarft,          only: polarft
use simple_opt_spec,         only: opt_spec
use simple_convergence,      only: convergence
use simple_jiffys,           only: alloc_err
use simple_filehandling      ! use all in there
implicit none

public :: build, test_build
private

logical :: debug=.false.

type build
    ! GENERAL TOOLBOX
    type(oris)                          :: a, e               !< aligndata, discrete space
    type(sym)                           :: se                 !< symmetry elements object
    type(projector)                     :: proj               !< projector object
    type(convergence)                   :: conv               !< object for convergence checking of the PRIME2D/3D approaches
    type(image)                         :: img                !< individual image objects
    type(image)                         :: img_pad            !< -"-
    type(image)                         :: img_tmp            !< -"-
    type(image)                         :: img_msk            !< -"-
    type(image)                         :: img_filt           !< -"-
    type(image)                         :: img_copy           !< -"-
    type(image)                         :: vol                !< -"-
    type(image)                         :: vol_pad            !< -"-
    type(image)                         :: mskvol             !< mask volume
    ! CLUSTER TOOLBOX
    type(ppca)                          :: pca                !< 4 probabilistic pca
    type(centre_clust)                  :: cenclust           !< centre-based clustering object
    real, allocatable                   :: features(:,:)      !< features for clustering
    ! COMMON LINES TOOLBOX
    type(image), allocatable            :: imgs(:)            !< images (all should be read in)
    type(image), allocatable            :: imgs_sym(:)        !< images (all should be read in)
    type(comlin)                        :: clins              !< common lines data structure
    type(image), allocatable            :: ref_imgs(:,:)      !< array of reference images
    ! RECONSTRUCTION TOOLBOX
    type(eo_reconstructor)              :: eorecvol           !< object for eo reconstruction
    type(reconstructor)                 :: recvol             !< object for reconstruction
    ! PRIME TOOLBOX
    type(image), allocatable            :: cavgs(:)           !< class averages (Wiener normalised references)
    type(image), allocatable            :: refs(:)            !< referecnes
    type(image), allocatable            :: ctfsqsums(:)       !< CTF**2 sums for Wiener normalisation
    type(image), allocatable            :: refvols(:)         !< reference volumes for quasi-continuous search
    type(reconstructor), allocatable    :: recvols(:)         !< array of volumes for reconstruction
    type(eo_reconstructor), allocatable :: eorecvols(:)       !< array of volumes for eo-reconstruction
    real, allocatable                   :: ssnr(:,:)          !< spectral signal to noise rations
    real, allocatable                   :: fsc(:,:)           !< Fourier shell correlation
    integer, allocatable                :: nnmat(:,:)         !< matrix with nearest neighbor indices
    ! PRIVATE EXISTENCE VARIABLES
    logical, private                    :: general_tbox_exists          = .false.
    logical, private                    :: cluster_tbox_exists          = .false.
    logical, private                    :: comlin_tbox_exists           = .false.
    logical, private                    :: rec_tbox_exists              = .false.
    logical, private                    :: eo_rec_tbox_exists           = .false.
    logical, private                    :: hadamard_prime3D_tbox_exists = .false.
    logical, private                    :: hadamard_prime2D_tbox_exists = .false.
    logical, private                    :: cont3D_tbox_exists           = .false.
    logical, private                    :: read_features_exists         = .false.
  contains
    procedure                           :: build_general_tbox
    procedure                           :: kill_general_tbox
    procedure                           :: build_cluster_tbox
    procedure                           :: kill_cluster_tbox
    procedure                           :: build_comlin_tbox
    procedure                           :: kill_comlin_tbox
    procedure                           :: build_rec_tbox
    procedure                           :: kill_rec_tbox
    procedure                           :: build_eo_rec_tbox
    procedure                           :: kill_eo_rec_tbox
    procedure                           :: build_hadamard_prime3D_tbox
    procedure                           :: kill_hadamard_prime3D_tbox
    procedure                           :: build_hadamard_prime2D_tbox
    procedure                           :: kill_hadamard_prime2D_tbox
    procedure                           :: build_cont3D_tbox
    procedure                           :: kill_cont3D_tbox
    procedure                           :: read_features
    procedure                           :: read_nnmat
    procedure                           :: raise_hard_ctf_exception
end type build

contains

    !> \brief  constructs the general toolbox
    subroutine build_general_tbox( self, p, cline, do3d, nooritab, force_ctf )
        use simple_ran_tabu, only: ran_tabu
        use simple_math,     only: nvoxfind, rad2deg
        use simple_rnd,      only: seed_rnd
        class(build),      intent(inout) :: self
        class(params),     intent(inout) :: p
        class(cmdline),    intent(inout) :: cline
        logical, optional, intent(in)    :: do3d, nooritab, force_ctf
        type(ran_tabu) :: rt
        integer        :: alloc_stat, lfny
        real           :: slask(3)
        logical        :: err, ddo3d, fforce_ctf
        call self%kill_general_tbox
        ddo3d = .true.
        if( present(do3d) ) ddo3d = do3d
        fforce_ctf = .false.
        if( present(force_ctf) ) fforce_ctf = force_ctf
        ! seed the random number generator
        call seed_rnd
        if( debug ) write(*,'(a)') 'seeded random number generator'
        ! set up symmetry functionality
        call self%se%new(p%pgrp)
        p%nsym    = self%se%get_nsym()
        p%eullims = self%se%srchrange()
        if( debug ) write(*,'(a)') 'did setup symmetry functionality'
        ! create object for orientations
        call self%a%new(p%nptcls)
        if( present(nooritab) )then
            call self%a%spiral(p%nsym, p%eullims)
        else
            ! we need the oritab to override the deftab in order not to loose parameters
            if( p%deftab /= '' ) call self%a%read(p%deftab)
            if( p%oritab /= '' )then
                if( .not. cline%defined('nstates') .and. p%vols(1) .eq. '' )then
                    call self%a%read(p%oritab, p%nstates)
                else
                    call self%a%read(p%oritab)
                endif
                if( self%a%get_noris() > 1 )then
                    call self%a%stats('corr', slask(1), slask(2), slask(3), err)
                    if( err )then
                    else
                        if( p%frac < 0.99 ) call self%a%calc_hard_ptcl_weights(p%var, bystate=.true.)
                    endif
                endif
            endif
        endif
        if( debug ) write(*,'(a)') 'created & filled object for orientations'  
        if( debug ) write(*,'(a)') 'read deftab'
        if( self%a%isthere('dfx') .and. self%a%isthere('dfy'))then
            p%tfplan%mode = 'astig'
        else if( self%a%isthere('dfx') )then
            p%tfplan%mode = 'noastig'
        else
            p%tfplan%mode = 'no'
        endif
        if( p%tfplan%flag .ne. 'no' .and. p%tfplan%mode .eq. 'no' )then
            write(*,'(a)') 'WARNING! It looks like you want to do Wiener restoration (p%ctf .ne. no)'
            write(*,'(a)') 'but your input orientation table lacks defocus values'
        endif
        if( debug ) write(*,'(a)') 'did set number of dimensions and ctfmode'
        if( fforce_ctf ) call self%raise_hard_ctf_exception(p)
        ! generate discrete projection direction space
        call self%e%new( p%nspace )
        call self%e%spiral( p%nsym, p%eullims )
        if( debug ) write(*,'(a)') 'generated discrete projection direction space'
        if( p%box > 0 )then
            ! build image objects
            ! box-sized ones
            call self%img%new([p%box,p%box,1],p%smpd,p%imgkind)
            call self%img_copy%new([p%box,p%box,1],p%smpd,p%imgkind) 
            if( debug ) write(*,'(a)') 'did build box-sized image objects'
            ! boxmatch-sized ones
            call self%img_tmp%new([p%boxmatch,p%boxmatch,1],p%smpd,p%imgkind)
            call self%img_msk%new([p%boxmatch,p%boxmatch,1],p%smpd,p%imgkind)
            call self%img_filt%new([p%box,p%box,1],p%smpd,p%imgkind)
            if( debug ) write(*,'(a)') 'did build boxmatch-sized image objects'
            ! boxpd-sized ones
            call self%img_pad%new([p%boxpd,p%boxpd,1],p%smpd,p%imgkind)
            if( ddo3d )then
                call self%vol%new([p%box,p%box,p%box], p%smpd, p%imgkind)
                if( p%automsk.eq.'yes' )then
                    call self%mskvol%new([p%boxmatch,p%boxmatch,p%boxmatch],p%smpd,p%imgkind)
                endif
                call self%vol_pad%new([p%boxpd,p%boxpd,p%boxpd],p%smpd,p%imgkind)
            endif
            if( debug ) write(*,'(a)') 'did build boxpd-sized image objects'
            ! build arrays
            lfny = self%img%get_lfny(1)            
            allocate( self%ssnr(p%nstates,lfny), self%fsc(p%nstates,lfny), stat=alloc_stat )
            call alloc_err("In: build_general_tbox; simple_build, 1", alloc_stat)
            self%ssnr = 0.
            self%fsc  = 0.
            ! set default amsklp
            if( .not. cline%defined('amsklp') .and. cline%defined('lp') )then
                p%amsklp = self%img%get_lp(self%img%get_find(p%lp)-2)
            endif
            if( debug ) write(*,'(a)') 'did set default values'
        endif
        ! build projector 
        self%proj = projector(p%wfun,imgkind=p%imgkind)
        ! build convergence checker
        self%conv = convergence(self%a, p, cline)
        write(*,'(A)') '>>> DONE BUILDING GENERAL TOOLBOX'
        self%general_tbox_exists = .true.
    end subroutine build_general_tbox
    
    !> \brief  destructs the general toolbox
    subroutine kill_general_tbox( self )
        class(build), intent(inout)  :: self
        if( self%general_tbox_exists )then
            call self%se%kill
            call self%a%kill
            call self%e%kill
            call self%img%kill
            call self%img_copy%kill
            call self%img_tmp%kill
            call self%img_msk%kill
            call self%img_filt%kill
            call self%img_pad%kill
            call self%vol%kill
            call self%mskvol%kill
            call self%vol_pad%kill
            if( allocated(self%ssnr) )then
                deallocate(self%ssnr, self%fsc)
            endif
            self%general_tbox_exists = .false.
        endif
    end subroutine kill_general_tbox
    
    !> \brief  constructs the cluster toolbox
    subroutine build_cluster_tbox( self, p )
        class(build),  intent(inout) :: self
        class(params), intent(inout) :: p
        type(image)                  :: img
        integer                      :: alloc_stat
        call self%kill_cluster_tbox
        call img%new([p%box,p%box,1], p%smpd, p%imgkind)
        p%ncomps = img%get_npix(p%msk)
        call img%kill
        if( debug ) print *, 'ncomps (npixels): ', p%ncomps
        if( debug ) print *, 'nvars (nfeatures): ', p%nvars
        call self%pca%new(p%nptcls, p%ncomps, p%nvars)
        call self%cenclust%new(self%features, self%a, p%nptcls, p%nvars, p%ncls)
        allocate( self%features(p%nptcls,p%nvars), stat=alloc_stat )
        call alloc_err('build_cluster_toolbox', alloc_stat)
        write(*,'(A)') '>>> DONE BUILDING CLUSTER TOOLBOX'
        self%cluster_tbox_exists = .true.
    end subroutine build_cluster_tbox
    
    !> \brief  destructs the cluster toolbox
    subroutine kill_cluster_tbox( self )
        class(build), intent(inout) :: self
        if( self%cluster_tbox_exists )then
            call self%pca%kill
            call self%cenclust%kill
            deallocate( self%features )
            self%cluster_tbox_exists = .false.
        endif
    end subroutine kill_cluster_tbox
    
    !> \brief  constructs the common lines toolbox
    subroutine build_comlin_tbox( self, p )
        class(build),  intent(inout) :: self
        class(params), intent(in)    :: p
        integer :: alloc_stat, i
        call self%kill_comlin_tbox
        if( p%pgrp /= 'c1' )then ! set up symmetry functionality
            ! make object for symmetrized orientations
            call self%a%symmetrize(p%nsym)
            allocate( self%imgs_sym(1:p%nsym*p%nptcls), self%ref_imgs(p%nstates,p%nspace), stat=alloc_stat )
            call alloc_err( 'build_comlin_tbox; simple_build, 1', alloc_stat )
            do i=1,p%nptcls*p%nsym
                call self%imgs_sym(i)%new([p%box,p%box,1],p%smpd,p%imgkind)
            end do
            self%clins = comlin(self%a, self%imgs_sym)
        else ! set up assymetrical common lines-based alignment functionality
            allocate( self%imgs(1:p%nptcls), stat=alloc_stat )
            call alloc_err( 'build_comlin_tbox; simple_build, 2', alloc_stat )
            do i=1,p%nptcls
                call self%imgs(i)%new([p%box,p%box,1],p%smpd,p%imgkind)
            end do  
            self%clins = comlin( self%a, self%imgs )
        endif
        write(*,'(A)') '>>> DONE BUILDING COMLIN TOOLBOX'
        self%comlin_tbox_exists = .true.
    end subroutine build_comlin_tbox
    
    !> \brief  destructs the common lines toolbox
    subroutine kill_comlin_tbox( self )
        class(build), intent(inout) :: self
        integer :: i,j
        if( self%comlin_tbox_exists )then
            call self%a%kill
            if( allocated(self%imgs_sym) )then
                do i=1,size(self%imgs_sym)
                    call self%imgs_sym(i)%kill
                end do
                deallocate(self%imgs_sym)
            endif
            if( allocated(self%ref_imgs) )then
                do i=1,size(self%ref_imgs,1)
                    do j=1,size(self%ref_imgs,2)
                        call self%ref_imgs(i,j)%kill
                    end do
                end do
                deallocate(self%ref_imgs)
            endif
            if( allocated(self%imgs) )then
                do i=1,size(self%imgs)
                    call self%imgs(i)%kill 
                end do
                deallocate(self%imgs)
            endif
            call self%clins%kill
            self%comlin_tbox_exists = .false.
        endif
    end subroutine kill_comlin_tbox
    
    !> \brief  constructs the reconstruction toolbox
    subroutine build_rec_tbox( self, p )
        class(build),  intent(inout) :: self
        class(params), intent(in)    :: p
        call self%kill_rec_tbox
        call self%raise_hard_ctf_exception(p)
        call self%recvol%new([p%boxpd,p%boxpd,p%boxpd],p%smpd,p%imgkind)
        call self%recvol%alloc_rho(p)
        write(*,'(A)') '>>> DONE BUILDING RECONSTRUCTION TOOLBOX'
        self%rec_tbox_exists = .true.
    end subroutine build_rec_tbox
    
    !> \brief  destructs the reconstruction toolbox
    subroutine kill_rec_tbox( self )
        class(build), intent(inout) :: self
        if( self%rec_tbox_exists )then
            call self%recvol%dealloc_rho
            call self%recvol%kill
            self%rec_tbox_exists = .false.
        endif
    end subroutine kill_rec_tbox
    
    !> \brief  constructs the eo reconstruction toolbox
    subroutine build_eo_rec_tbox( self, p )
        class(build),  intent(inout) :: self
        class(params), intent(in)    :: p
        call self%kill_eo_rec_tbox
        call self%raise_hard_ctf_exception(p)
        call self%eorecvol%new(p)
        write(*,'(A)') '>>> DONE BUILDING EO RECONSTRUCTION TOOLBOX'
        self%eo_rec_tbox_exists = .true.
    end subroutine build_eo_rec_tbox
    
    !> \brief  destructs the eo reconstruction toolbox
    subroutine kill_eo_rec_tbox( self )
        class(build), intent(inout) :: self
        if( self%eo_rec_tbox_exists )then
            call self%eorecvol%kill
            self%eo_rec_tbox_exists = .false.
        endif
    end subroutine kill_eo_rec_tbox
    
    !> \brief  constructs the prime2D toolbox
    subroutine build_hadamard_prime2D_tbox( self, p )
        use simple_strings, only: str_has_substr
        class(build),  intent(inout) :: self
        class(params), intent(in)    :: p
        integer :: icls, alloc_stat, funit, io_stat
        call self%kill_hadamard_prime2D_tbox
        call self%raise_hard_ctf_exception(p)
        allocate( self%cavgs(p%ncls), self%refs(p%ncls), self%ctfsqsums(p%ncls), stat=alloc_stat )
        call alloc_err('build_hadamard_prime2D_tbox; simple_build, 1', alloc_stat)
        do icls=1,p%ncls
            call self%cavgs(icls)%new([p%box,p%box,1],p%smpd,p%imgkind)
            call self%refs(icls)%new([p%box,p%box,1],p%smpd,p%imgkind)
            call self%ctfsqsums(icls)%new([p%box,p%box,1],p%smpd,p%imgkind)
        end do
        if( str_has_substr(p%refine,'neigh') )then
            if( file_exists('nnmat.bin') )  call self%read_nnmat(p)
        endif
        write(*,'(A)') '>>> DONE BUILDING HADAMARD PRIME2D TOOLBOX'
        self%hadamard_prime2D_tbox_exists = .true.
    end subroutine build_hadamard_prime2D_tbox
    
    !> \brief  destructs the prime2D toolbox
    subroutine kill_hadamard_prime2D_tbox( self )
        class(build), intent(inout) :: self
        integer :: i
        if( self%hadamard_prime2D_tbox_exists )then
            do i=1,size(self%cavgs)
                call self%cavgs(i)%kill
                call self%refs(i)%kill
                call self%ctfsqsums(i)%kill
            end do
            deallocate(self%cavgs, self%refs, self%ctfsqsums)
            self%hadamard_prime2D_tbox_exists = .false.
        endif
    end subroutine kill_hadamard_prime2D_tbox

    !> \brief  constructs the prime3D toolbox
    subroutine build_hadamard_prime3D_tbox( self, p )
        use simple_strings, only: str_has_substr
        class(build),  intent(inout) :: self
        class(params), intent(in)    :: p
        integer :: s, alloc_stat, i
        call self%kill_hadamard_prime3D_tbox
        call self%raise_hard_ctf_exception(p)
        ! reconstruction objects
        if( p%norec .eq. 'yes' )then
            ! no reconstruction objects needed
        else
            if( p%eo .eq. 'yes' )then
                allocate( self%eorecvols(p%nstates), stat=alloc_stat )
                call alloc_err('build_hadamard_prime3D_tbox; simple_build, 1', alloc_stat)
                do s=1,p%nstates
                    call self%eorecvols(s)%new(p)
                end do
            else
                allocate( self%recvols(p%nstates), stat=alloc_stat )
                call alloc_err('build_hadamard_prime3D_tbox; simple_build, 2', alloc_stat)
                do s=1,p%nstates
                    call self%recvols(s)%new([p%boxpd,p%boxpd,p%boxpd],p%smpd,p%imgkind)
                    call self%recvols(s)%alloc_rho(p)
                end do
            endif
        endif
        if( str_has_substr(p%refine,'qcont') )then
            allocate( self%refvols(p%nstates), stat=alloc_stat)
            call alloc_err('build_hadamard_prime3D_tbox; simple_build, 4', alloc_stat)
            do s=1,p%nstates 
                call self%refvols(s)%new([p%boxmatch,p%boxmatch,p%boxmatch],p%smpd,p%imgkind)
            end do
        endif    
        if( str_has_substr(p%refine,'neigh') )then
            if( .not. str_has_substr(p%refine,'qcont') ) self%nnmat = self%e%nearest_neighbors(p%nnn)
        endif
        write(*,'(A)') '>>> DONE BUILDING HADAMARD PRIME3D TOOLBOX'
        self%hadamard_prime3D_tbox_exists = .true.
    end subroutine build_hadamard_prime3D_tbox
    
    !> \brief  destructs the prime3D toolbox
    subroutine kill_hadamard_prime3D_tbox( self )
        class(build), intent(inout) :: self
        integer :: i
        if( self%hadamard_prime3D_tbox_exists )then
            if( allocated(self%eorecvols) )then
                do i=1,size(self%eorecvols)
                    call self%eorecvols(i)%kill
                end do
                deallocate(self%eorecvols)
            endif
            if( allocated(self%recvols) )then
                do i=1,size(self%recvols)
                    call self%recvols(i)%dealloc_rho
                    call self%recvols(i)%kill
                end do
                deallocate(self%recvols)
            endif
            if( allocated(self%refvols) )then
                do i=1,size(self%refvols)
                    call self%refvols(i)%kill
                end do
                deallocate(self%refvols)
            endif
            if( allocated(self%nnmat) ) deallocate(self%nnmat)
            self%hadamard_prime3D_tbox_exists = .false.
        endif
    end subroutine kill_hadamard_prime3D_tbox
    
    !> \brief  constructs the toolbox for continuous Cartesian sampling refinement
    subroutine build_cont3D_tbox( self, p )
        class(build),  intent(inout) :: self
        class(params), intent(in)    :: p
        integer :: s, alloc_stat, i
        call self%kill_cont3D_tbox
        call self%raise_hard_ctf_exception(p)
        if( p%norec .eq. 'yes' )then
            ! no reconstruction objects needed
        else
            allocate( self%eorecvols(p%nstates), stat=alloc_stat )
            call alloc_err('build_cont3D_tbox; simple_build, 1', alloc_stat)
            do s=1,p%nstates
                call self%eorecvols(s)%new(p)
            end do
        endif
        write(*,'(A)') '>>> DONE BUILDING HADAMARD PRIME3D TOOLBOX'
        self%cont3D_tbox_exists = .true.
    end subroutine build_cont3D_tbox
    
    !> \brief  destructs the toolbox for continuous Cartesian sampling refinement
    subroutine kill_cont3D_tbox( self )
        class(build), intent(inout) :: self
        integer :: i
        if( self%cont3D_tbox_exists )then
            if( allocated(self%eorecvols) )then
                do i=1,size(self%eorecvols)
                    call self%eorecvols(i)%kill
                end do
                deallocate(self%eorecvols)
            endif
            self%cont3D_tbox_exists = .false.
        endif
    end subroutine kill_cont3D_tbox
    
    !>  \brief  for reading feature vectors from disk
    subroutine read_features( self, p )
        class(build),  intent(inout) :: self
        class(params), intent(in)    :: p
        integer :: k, file_stat, funit, recsz
        inquire( iolength=recsz ) self%features(1,:)
        funit = get_fileunit()
        open(unit=funit, status='old', action='read', file=p%featstk,&
        access='direct', form='unformatted', recl=recsz, iostat=file_stat)
        call fopen_err('build_read_features', file_stat)
        ! read features from disk
        do k=1,p%nptcls
            read(funit, rec=k) self%features(k,:)
        end do
        close(unit=funit)
    end subroutine read_features

    !>  \brief  for reading nearest neighbour matrix from disk
    subroutine read_nnmat( self, p )
        class(build),  intent(inout) :: self
        class(params), intent(in)    :: p
        integer :: alloc_stat, funit, io_stat
        if( allocated(self%nnmat) ) deallocate(self%nnmat)
        allocate( self%nnmat(p%ncls,p%nnn), stat=alloc_stat )
        call alloc_err('build_hadamard_prime2D_tbox; simple_build, 2', alloc_stat)
        funit = get_fileunit()
        open(unit=funit, status='OLD', action='READ', file='nnmat.bin', access='STREAM')
        read(unit=funit,pos=1,iostat=io_stat) self%nnmat
        ! check if the read was successful
        if( io_stat .ne. 0 )then
            write(*,'(a,i0,2a)') '**ERROR(read_nnmat): I/O error ',&
            io_stat, ' when reading nnmat.bin'
            stop 'I/O error; simple_build; read_nnmat'
        endif
        close(funit)
    end subroutine read_nnmat
    
    !> \brief  fall-over if CTF params are missing
    subroutine raise_hard_ctf_exception( self, p )
        class(build),  intent(inout) :: self
        class(params), intent(in)    :: p
        logical :: params_present(4)
        if( p%tfplan%flag.ne.'no' )then
            params_present(1) = self%a%isthere('kv')
            params_present(2) = self%a%isthere('cs')
            params_present(3) = self%a%isthere('fraca')
            params_present(4) = self%a%isthere('dfx') 
            if( all(params_present) )then
                ! alles ok
            else
                if( .not. params_present(1) ) write(*,*) 'ERROR! ctf .ne. no and input doc lacks kv'
                if( .not. params_present(2) ) write(*,*) 'ERROR! ctf .ne. no and input doc lacks cs'
                if( .not. params_present(3) ) write(*,*) 'ERROR! ctf .ne. no and input doc lacks fraca'
                if( .not. params_present(4) ) write(*,*) 'ERROR! ctf .ne. no and input doc lacks defocus'
                stop
            endif
        endif
    end subroutine raise_hard_ctf_exception
    
    ! UNIT TEST
    
    !> \brief  build unit test
    subroutine test_build
        type(build)   :: myb
        type(cmdline) :: mycline_static, mycline_varying
        type(params)  :: myp
        write(*,'(a)') '**info(simple_build_unit_test): testing the different building options'
        ! setup command line
        call mycline_static%set('box',      100.)
        call mycline_static%set('msk',       40.)
        call mycline_static%set('smpd',       2.)
        call mycline_static%set('nvars',     40.)
        call mycline_static%set('nptcls', 10000.)
        call mycline_static%set('ncls',     100.)
        call mycline_static%set('nstates',    2.)
        write(*,'(a)') '**info(simple_build_unit_test): generated command line'
        ! 12 cases to test
        ! case 1:  refine=no, pgrp=c1, eo=yes
        write(*,'(a)') '**info(simple_build_unit_test): testing case: refine=no, pgrp=c1, eo=yes'
        mycline_varying = mycline_static
        call mycline_varying%set('refine', 'no')
        call mycline_varying%set('pgrp',   'c1')
        call mycline_varying%set('eo',    'yes')
        myp = params(mycline_varying, checkdistr=.false.)
        call tester
        write(*,'(a)') '**info(simple_build_unit_test): case 1 passed'
        ! case 2:  refine=no, pgrp=c1, eo=no
        write(*,'(a)') '**info(simple_build_unit_test): testing case: refine=no, pgrp=c1, eo=no'
        mycline_varying = mycline_static
        call mycline_varying%set('refine', 'no')
        call mycline_varying%set('pgrp',   'c1')
        call mycline_varying%set('eo',    'yes')
        myp = params(mycline_varying, checkdistr=.false.) 
        call tester
        write(*,'(a)') '**info(simple_build_unit_test): case 2 passed'
        ! case 3:  refine=no, pgrp=c2, eo=yes
        write(*,'(a)') '**info(simple_build_unit_test): testing case: refine=no, pgrp=c2, eo=yes'
        mycline_varying = mycline_static
        call mycline_varying%set('refine', 'no')
        call mycline_varying%set('pgrp',   'c1')
        call mycline_varying%set('eo',    'yes')
        myp = params(mycline_varying, checkdistr=.false.) 
        call tester
        write(*,'(a)') '**info(simple_build_unit_test): case 3 passed'
        ! case 4:  refine=no, pgrp=c2, eo=no
        write(*,'(a)') '**info(simple_build_unit_test): testing case: refine=no, pgrp=c2, eo=no'
        mycline_varying = mycline_static
        call mycline_varying%set('refine', 'no')
        call mycline_varying%set('pgrp',   'c1')
        call mycline_varying%set('eo',    'yes')
        myp = params(mycline_varying, checkdistr=.false.) 
        call tester
        write(*,'(a)') '**info(simple_build_unit_test): case 4 passed'
        ! case 5:  refine=neigh, pgrp=c1, eo=yes
        write(*,'(a)') '**info(simple_build_unit_test): testing case: refine=neigh, pgrp=c1, eo=yes'
        mycline_varying = mycline_static
        call mycline_varying%set('refine', 'no')
        call mycline_varying%set('pgrp',   'c1')
        call mycline_varying%set('eo',    'yes')
        myp = params(mycline_varying, checkdistr=.false.) 
        call tester
        write(*,'(a)') '**info(simple_build_unit_test): case 5 passed'
        ! case 6:  refine=neigh, pgrp=c1, eo=no
        write(*,'(a)') '**info(simple_build_unit_test): testing case: refine=neigh, pgrp=c1, eo=no'
        mycline_varying = mycline_static
        call mycline_varying%set('refine', 'no')
        call mycline_varying%set('pgrp',   'c1')
        call mycline_varying%set('eo',    'yes')
        myp = params(mycline_varying, checkdistr=.false.) 
        call tester
        write(*,'(a)') '**info(simple_build_unit_test): case 6 passed'
        ! case 7:  refine=neigh, pgrp=c2, eo=yes
        write(*,'(a)') '**info(simple_build_unit_test): testing case: refine=neigh, pgrp=c2, eo=yes'
        mycline_varying = mycline_static
        call mycline_varying%set('refine', 'no')
        call mycline_varying%set('pgrp',   'c1')
        call mycline_varying%set('eo',    'yes')
        myp = params(mycline_varying, checkdistr=.false.) 
        call tester
        write(*,'(a)') '**info(simple_build_unit_test): case 7 passed'
        ! case 8:  refine=neigh, pgrp=c2, eo=no
        write(*,'(a)') '**info(simple_build_unit_test): testing case: refine=neigh, pgrp=c2, eo=no'
        mycline_varying = mycline_static
        call mycline_varying%set('refine', 'no')
        call mycline_varying%set('pgrp',   'c1')
        call mycline_varying%set('eo',    'yes')
        myp = params(mycline_varying, checkdistr=.false.) 
        call tester
        write(*,'(a)') '**info(simple_build_unit_test): case 8 passed'
        ! case 9:  refine=neigh, pgrp=c1, eo=yes
        write(*,'(a)') '**info(simple_build_unit_test): testing case: refine=neigh, pgrp=c1, eo=yes'
        mycline_varying = mycline_static
        call mycline_varying%set('refine', 'no')
        call mycline_varying%set('pgrp',   'c1')
        call mycline_varying%set('eo',    'yes')
        myp = params(mycline_varying, checkdistr=.false.) 
        call tester
        write(*,'(a)') '**info(simple_build_unit_test): case 9 passed'
        ! case 10: refine=neigh, pgrp=c1, eo=no
        write(*,'(a)') '**info(simple_build_unit_test): testing case: refine=neigh, pgrp=c1, eo=no'
        mycline_varying = mycline_static
        call mycline_varying%set('refine', 'no')
        call mycline_varying%set('pgrp',   'c1')
        call mycline_varying%set('eo',    'yes')
        myp = params(mycline_varying, checkdistr=.false.)
        write(*,'(a)') '**info(simple_build_unit_test): case 10 passed'
        ! case 11: refine=neigh, pgrp=c2, eo=yes
        write(*,'(a)') '**info(simple_build_unit_test): testing case: refine=neigh, pgrp=c2, eo=yes'
        mycline_varying = mycline_static
        call mycline_varying%set('refine', 'no')
        call mycline_varying%set('pgrp',   'c1')
        call mycline_varying%set('eo',    'yes')
        myp = params(mycline_varying, checkdistr=.false.) 
        call tester
        write(*,'(a)') '**info(simple_build_unit_test): case 11 passed'
        ! case 12: refine=neigh, pgrp=c2, eo=no
        write(*,'(a)') '**info(simple_build_unit_test): testing case: refine=neigh, pgrp=c2, eo=no'
        mycline_varying = mycline_static
        call mycline_varying%set('refine', 'no')
        call mycline_varying%set('pgrp',   'c1')
        call mycline_varying%set('eo',    'yes')
        myp = params(mycline_varying, checkdistr=.false.) 
        call tester
        write(*,'(a)') '**info(simple_build_unit_test): case 12 passed'
        write(*,'(a)') 'SIMPLE_BUILD_UNIT_TEST COMPLETED SUCCESSFULLY ;-)'
        
      contains
        
          subroutine tester
              call myb%build_general_tbox(myp, mycline_varying, do3d=.true., nooritab=.true.)
              call myb%build_general_tbox(myp, mycline_varying, do3d=.true., nooritab=.true.)
              call myb%kill_general_tbox
              write(*,'(a)') 'build_general_tbox passed'
              call myb%build_cluster_tbox(myp)
              call myb%build_cluster_tbox(myp)
              call myb%kill_cluster_tbox
              write(*,'(a)') 'build_cluster_tbox passed'
              call myb%build_comlin_tbox(myp)
              call myb%build_comlin_tbox(myp)
              call myb%kill_comlin_tbox
              write(*,'(a)') 'build_comlin_tbox passed'
              call myb%build_rec_tbox(myp)
              call myb%build_rec_tbox(myp)
              call myb%kill_rec_tbox
              write(*,'(a)') 'build_rec_tbox passed'
              call myb%build_eo_rec_tbox(myp)
              call myb%build_eo_rec_tbox(myp)
              call myb%kill_eo_rec_tbox
              write(*,'(a)') 'build_eo_rec_tbox passed'
              call myb%build_hadamard_prime3D_tbox(myp)
              call myb%build_hadamard_prime3D_tbox(myp)
              call myb%kill_hadamard_prime3D_tbox
              write(*,'(a)') 'build_hadamard_prime3D_tbox passed'
              call myb%build_hadamard_prime2D_tbox(myp)
              call myb%build_hadamard_prime2D_tbox(myp)
              call myb%kill_hadamard_prime2D_tbox
              write(*,'(a)') 'build_hadamard_prime2D_tbox passed'
              call myb%build_cont3D_tbox(myp)
              call myb%build_cont3D_tbox(myp)
              call myb%kill_cont3D_tbox
              write(*,'(a)') 'build_cont3D_tbox passed'
          end subroutine tester
        
    end subroutine test_build

end module simple_build

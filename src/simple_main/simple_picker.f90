module simple_picker
!$ use omp_lib
!$ use omp_lib_kinds
use simple_defs
use simple_math,         only: sortmeans
use simple_image,        only: image
use simple_math,         only: euclid, hpsort
use simple_filehandling, only: get_fileunit, remove_abspath, fname_new_ext
use simple_jiffys,       only: alloc_err, find_ldim_nptcls
implicit none

public :: init_picker, exec_picker, kill_picker
private

integer,          parameter   :: MAXKMIT  = 20
integer,          parameter   :: SPECNCLS = 10
real,             parameter   :: BOXFRAC  = 0.5
logical,          parameter   :: DEBUG=.true., DOPRINT=.true.
type(image)                   :: micrograph, mic_shrunken, ptcl_target
type(image),      allocatable :: refs(:)
logical,          allocatable :: selected_peak_positions(:), is_a_peak(:,:)
real,             allocatable :: sxx(:), corrmat(:,:), specscores(:,:)
integer,          allocatable :: peak_positions(:,:), refmat(:,:), backgr_positions(:,:)
character(len=:), allocatable :: micname, refsname
character(len=STDLEN)         :: boxname
integer                       :: ldim(3), ldim_refs(3), ldim_shrink(3)
integer                       :: ntargets, nx, ny, nrefs, npeaks, offset
integer                       :: orig_box, lfny, ncls, nbackgr
real                          :: smpd_shrunken, corrmax, corrmin
real                          :: smpd, msk, shrink, lp, distthr

contains

    

    subroutine init_picker( micfname, refsfname, smpd_in, msk_in, shrink_in, offset_in, lp_in, distthr_in )
        character(len=*),  intent(in) :: micfname, refsfname
        real,              intent(in) :: smpd_in, msk_in, shrink_in
        integer, optional, intent(in) :: offset_in
        real,    optional, intent(in) :: lp_in, distthr_in
        integer :: alloc_stat, ifoo, iref
        allocate(micname,  source=trim(micfname))
        allocate(refsname, source=trim(refsfname))
        boxname   = remove_abspath(fname_new_ext(micname,'box'))
        smpd      = smpd_in
        msk       = msk_in
        shrink    = shrink_in
        offset    = 3
        if( present(offset_in)) offset = offset_in
        lp        = 20.0
        if( present(lp_in)    ) lp     = lp_in
        ! read micrograph
        call find_ldim_nptcls(micname, ldim, ifoo)
        call micrograph%new(ldim, smpd)
        call micrograph%read(micname)
        ! find out reference dimensions
        call find_ldim_nptcls(refsname, ldim_refs, nrefs)
        orig_box     = nint(shrink)*ldim_refs(1)
        ldim_refs(3) = 1 ! correct 4 stupid mrc convention
        ! set constants
        ldim_shrink(1) = nint(real(ldim(1))/shrink)
        ldim_shrink(2) = nint(real(ldim(2))/shrink)
        ldim_shrink(3) = 1
        nx             = ldim_shrink(1)-ldim_refs(1)
        ny             = ldim_shrink(2)-ldim_refs(2)
        smpd_shrunken  = shrink*smpd
        msk            = min(msk/shrink,real(ldim_refs(1)/2-5)) ! mask parameter need to be modulated by shrink
        distthr = BOXFRAC*real(ldim_refs(1))
        if( present(distthr_in) ) distthr = distthr_in/shrink ! inputted dist thresh need to be modulated by shrink
        ! read references
        allocate( refs(nrefs), sxx(nrefs), stat=alloc_stat )
        call alloc_err( "In: simple_picker :: init_picker, 1", alloc_stat)
        do iref=1,nrefs
            call refs(iref)%new(ldim_refs, smpd_shrunken)
            call refs(iref)%read(refsname, iref)
            call refs(iref)%mask(msk, 'hard')
            call refs(iref)%prenorm4real_corr(sxx(iref))
        end do
        ! pre-process micrograph
        call micrograph%fwd_ft
        call micrograph%bp(0., lp)
        call mic_shrunken%new(ldim_shrink, smpd_shrunken)
        call micrograph%clip(mic_shrunken)
        call mic_shrunken%bwd_ft
        if( DEBUG ) call mic_shrunken%write('shrunken.mrc')
    end subroutine init_picker

    subroutine exec_picker
        call extract_peaks_and_background
        call distance_filter
        call refine_positions
        call estimate_ssnr
        ! bring back coordinates to original sampling
        peak_positions   = shrink*peak_positions
        backgr_positions = shrink*backgr_positions
        ! write output
        call write_boxfile
    end subroutine exec_picker

    subroutine extract_peaks_and_background
        real    :: means(2), corrs(nrefs), spec_thresh
        integer :: xind, yind, alloc_stat, funit, iref, i, loc(1), ind
        integer, allocatable :: labels(:), target_positions(:,:)
        real,    allocatable :: target_corrs(:), spec(:)
        write(*,'(a)') '>>> EXTRACTING PEAKS & BACKGROUND'
        ntargets = 0
        do xind=0,nx,offset
            do yind=0,ny,offset
                ntargets = ntargets + 1
            end do
        end do
        allocate( target_corrs(ntargets), target_positions(ntargets,2),&
                  corrmat(0:nx,0:ny), refmat(0:nx,0:ny), is_a_peak(0:nx,0:ny), stat=alloc_stat )
        call alloc_err( 'In: simple_picker :: gen_corr_peaks, 1', alloc_stat )
        target_corrs     = 0.
        target_positions = 0
        corrmat          = -1.
        refmat           = 0
        is_a_peak        = .false.
        ntargets         = 0
        corrmax          = -1.
        corrmin          = 1.
        do xind=0,nx,offset
            do yind=0,ny,offset
                ntargets = ntargets + 1
                target_positions(ntargets,:) = [xind,yind]
                call mic_shrunken%window([xind,yind], ldim_refs(1), ptcl_target)
                !$omp parallel do schedule(auto) default(shared) private(iref)
                do iref=1,nrefs
                    corrs(iref) = refs(iref)%real_corr_prenorm(ptcl_target, sxx(iref))
                end do
                !$omp end parallel do
                loc = maxloc(corrs)
                target_corrs(ntargets) = corrs(loc(1))
                corrmat(xind,yind)     = target_corrs(ntargets)
                refmat(xind,yind)      = loc(1)
                if( target_corrs(ntargets) > corrmax ) corrmax = target_corrs(ntargets)
                if( target_corrs(ntargets) < corrmin ) corrmin = target_corrs(ntargets)
            end do
        end do
        call sortmeans(target_corrs, MAXKMIT, means, labels)
        npeaks = count(labels == 2)
        allocate( peak_positions(npeaks,2), specscores(0:nx,0:ny), stat=alloc_stat)
        call alloc_err( 'In: simple_picker :: gen_corr_peaks, 2', alloc_stat )
        peak_positions = 0
        specscores     = 0.0
        ! store peak positions
        npeaks = 0
        do i=1,ntargets
            if( labels(i) == 2 )then
                npeaks = npeaks + 1
                peak_positions(npeaks,:) = target_positions(i,:)
                is_a_peak(target_positions(i,1),target_positions(i,2)) = .true.
            endif
        end do
        ! calculate spectral scores for background images
        do xind=0,nx,ldim_refs(1)/2
            do yind=0,ny,ldim_refs(1)/2
                if( is_a_peak(xind,yind) )then
                    ! this is a box with signal
                else
                    ! this is a background candidate
                    call mic_shrunken%window([xind,yind], ldim_refs(1), ptcl_target)
                    call ptcl_target%fwd_ft
                    spec = ptcl_target%spectrum('power')
                    specscores(xind,yind) = sum(spec)
                    call ptcl_target%kill
                    deallocate(spec)
                endif
            end do
        end do
        ! remove zero spectral scores
        do xind=0,nx
            do yind=0,ny
                if( specscores(xind,yind) > 0.0 )then
                    ! this is a valid measurement
                    is_a_peak(xind,yind) = .false.
                else
                    ! this is not & we filter it out by flagging it as a peak
                    is_a_peak(xind,yind) = .true.
                endif
            end do
        end do
        spec = pack(specscores, mask=.not. is_a_peak)
        call hpsort(size(spec), spec)
        ind = min(100,size(spec))
        spec_thresh = spec(ind)
        ! remove high SNR imgs
        nbackgr = 0
        do xind=0,nx,ldim_refs(1)/2
            do yind=0,ny,ldim_refs(1)/2
                if( specscores(xind,yind) >= spec_thresh )then
                    ! this is a high SNR peak, remove it 
                    is_a_peak(xind,yind) = .true.
                else
                    nbackgr = nbackgr + 1
                endif
            end do
        end do
        allocate( backgr_positions(nbackgr,2), stat=alloc_stat)
        call alloc_err( 'In: simple_picker :: gen_corr_peaks, 3', alloc_stat )
        nbackgr = 0
        do xind=0,nx,ldim_refs(1)/2
            do yind=0,ny,ldim_refs(1)/2
                if( is_a_peak(xind,yind) )then
                else
                    nbackgr = nbackgr + 1
                    backgr_positions(nbackgr,:) = [xind,yind]
                endif
            end do
        end do
    end subroutine extract_peaks_and_background

    subroutine distance_filter
        integer :: ipeak, jpeak, ipos(2), jpos(2), alloc_stat, loc(1)
        real    :: dist
        logical, allocatable :: mask(:)
        real,    allocatable :: corrs(:)
        write(*,'(a)') '>>> DISTANCE FILTERING'
        allocate( mask(npeaks), corrs(npeaks), selected_peak_positions(npeaks), stat=alloc_stat)
        call alloc_err( 'In: simple_picker :: distance_filter', alloc_stat )
        selected_peak_positions = .true.
        do ipeak=1,npeaks
            ipos = peak_positions(ipeak,:)
            mask = .false.
            !$omp parallel do schedule(auto) default(shared) private(jpeak,jpos,dist)
            do jpeak=1,npeaks
                jpos = peak_positions(jpeak,:)
                dist = euclid(real(ipos),real(jpos))
                if( dist < distthr ) mask(jpeak) = .true.
                corrs(jpeak) = corrmat(jpos(1),jpos(2))
            end do
            !$omp end parallel do
            ! find best match in the neigh
            loc = maxloc(corrs, mask=mask)
            ! eliminate all but the best
            mask(loc(1)) = .false.
            where( mask )
                selected_peak_positions = .false.
            end where
        end do
        write(*,'(a,1x,I5)') 'peak positions left after distance filtering: ', count(selected_peak_positions)
    end subroutine distance_filter

    subroutine refine_positions
        integer                  :: ipeak, xrange(2), yrange(2), xind, yind, ref
        type(image), allocatable :: target_imgs(:,:)
        real,        allocatable :: target_corrs(:,:)
        real                     :: corr
        write(*,'(a)') '>>> REFINING POSITIONS'
        do ipeak=1,npeaks
            if( selected_peak_positions(ipeak) )then
                call srch_range(peak_positions(ipeak,:))
                ref = refmat(peak_positions(ipeak,1),peak_positions(ipeak,2))
                allocate(target_imgs(xrange(1):xrange(2),yrange(1):yrange(2)),&
                         target_corrs(xrange(1):xrange(2),yrange(1):yrange(2)))
                do xind=xrange(1),xrange(2)
                    do yind=yrange(1),yrange(2)
                        call mic_shrunken%window([xind,yind], ldim_refs(1), target_imgs(xind,yind))
                    end do
                end do
                !$omp parallel do schedule(auto) default(shared) private(xind,yind)
                do xind=xrange(1),xrange(2)
                    do yind=yrange(1),yrange(2)
                        target_corrs(xind,yind) = refs(ref)%real_corr_prenorm(target_imgs(xind,yind), sxx(ref))
                    end do
                end do
                !$omp end parallel do
                corr = -1
                do xind=xrange(1),xrange(2)
                    do yind=yrange(1),yrange(2)
                        call target_imgs(xind,yind)%kill
                        if( target_corrs(xind,yind) > corr )then
                            peak_positions(ipeak,:) = [xind,yind]
                            corr = target_corrs(xind,yind)
                        endif
                    end do
                end do
                deallocate(target_imgs, target_corrs)
            endif
        end do

        contains

            subroutine srch_range( pos )
                integer, intent(in) :: pos(2)
                xrange(1) = max(0,  pos(1) - offset)
                xrange(2) = min(nx, pos(1) + offset)
                yrange(1) = max(0,  pos(2) - offset)
                yrange(2) = min(ny, pos(2) + offset)
            end subroutine srch_range

    end subroutine refine_positions

    subroutine estimate_ssnr
        real,    allocatable :: sig_spec(:), noise_spec(:), spec(:)
        real,    allocatable :: ssnr(:), res(:), pscores(:)
        integer, allocatable :: labels(:), labels_bin(:)
        integer :: nsig, nnoise, ipeak, xind, yind, k, n
        integer, parameter :: NMEANS=10
        real    :: means(NMEANS), means_bin(2)
        n = count(selected_peak_positions)
        allocate(pscores(n))
        nsig = 0
        do ipeak=1,npeaks
            if( selected_peak_positions(ipeak) )then
                nsig = nsig + 1            
                call mic_shrunken%window(peak_positions(ipeak,:), ldim_refs(1), ptcl_target)
                call ptcl_target%fwd_ft
                spec = ptcl_target%spectrum('power')
                pscores(nsig) = sum(spec)
                if( allocated(sig_spec) )then
                    sig_spec = sig_spec + spec
                else
                    allocate(sig_spec(size(spec)), source=spec)
                endif
                call ptcl_target%kill
                deallocate(spec)
            endif
        end do
        sig_spec = sig_spec/real(nsig)
        if( nsig > NMEANS )then
            call sortmeans(pscores, MAXKMIT, means, labels)
            call sortmeans(means,   MAXKMIT, means_bin, labels_bin)
            if( DOPRINT )then
               do k=1,NMEANS
                  write(*,*) 'quanta: ', k, 'mean: ', means(k), 'pop: ', count(labels == k), 'bin: ', labels_bin(k)
               end do
            endif
            ! delete the outliers
            nsig = 0
            do ipeak=1,npeaks
                if( selected_peak_positions(ipeak) )then
                    nsig = nsig + 1
                    ! remove outliers
                    if( labels(nsig) == 1 .or. labels(nsig) == NMEANS )then
                        selected_peak_positions(ipeak) = .false.
                    endif
                    ! remove too high contrast stuff
                    if( labels_bin(labels(nsig)) == 2 )then
                        selected_peak_positions(ipeak) = .false.
                    endif
                endif
            end do
            write(*,'(a,1x,I5)') 'peak positions left after outlier exclusion: ', count(selected_peak_positions)
        endif
        ! ! second, estimate noise spectrum
        ! nnoise = 0
        ! do xind=0,nx,ldim_refs(1)/2
        !     do yind=0,ny,ldim_refs(1)/2
        !         if( is_a_peak(xind,yind) )then
        !         else
        !             nnoise = nnoise + 1
        !             call mic_shrunken%window(backgr_positions(nnoise,:), ldim_refs(1), ptcl_target)
        !             call ptcl_target%fwd_ft
        !             spec = ptcl_target%spectrum('power')
        !             if( allocated(noise_spec) )then
        !                 noise_spec = noise_spec + spec
        !             else
        !                 allocate(noise_spec(size(spec)), source=spec)
        !             endif
        !             call ptcl_target%kill
        !             deallocate(spec)
        !         endif
        !     end do
        ! end do
        ! noise_spec = noise_spec/real(nnoise)
        ! allocate(ssnr(size(noise_spec)))
        ! ssnr = 0.
        ! where(noise_spec > 0.)
        !     ssnr = sig_spec/noise_spec
        ! end where
        write(*,'(a,1x,f7.3)') '>>> SPECTRAL SCORE:', sum(sig_spec)/real(size(sig_spec))
    end subroutine estimate_ssnr

    subroutine write_boxfile
        integer :: funit, ipeak
        funit = get_fileunit()
        open(unit=funit, status='REPLACE', action='WRITE', file=boxname)
        do ipeak=1,npeaks
            if( selected_peak_positions(ipeak) )then             
                write(funit,'(I7,I7,I7,I7,I7)') peak_positions(ipeak,1),&
                peak_positions(ipeak,2), orig_box, orig_box, -3
            endif
        end do
        close(funit)
    end subroutine write_boxfile

    subroutine write_backgr_coords
        integer :: funit, xind, yind
        funit = get_fileunit()
        open(unit=funit, status='REPLACE', action='WRITE', file='background.box')
        nbackgr = 0
        do xind=0,nx,ldim_refs(1)/2
            do yind=0,ny,ldim_refs(1)/2
                if( is_a_peak(xind,yind) )then
                else
                    nbackgr = nbackgr + 1
                    write(funit,'(I7,I7,I7,I7,I7)') backgr_positions(nbackgr,1),&
                    backgr_positions(nbackgr,2), orig_box, orig_box, -3
                endif
            end do
        end do
    end subroutine write_backgr_coords

    subroutine kill_picker
        integer :: iref
        if( allocated(micname) )then
            deallocate(selected_peak_positions,is_a_peak,sxx,corrmat,specscores)
            deallocate(peak_positions,refmat,backgr_positions,micname,refsname)
            do iref=1,nrefs
                call refs(iref)%kill
            end do
            deallocate(refs)
        endif
    end subroutine kill_picker

end module simple_picker
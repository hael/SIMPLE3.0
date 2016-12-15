!==Class simple_commander_preproc
!
! This class contains the set of concrete preprocessing commanders of the SIMPLE library. This class provides the glue between the reciver 
! (main reciever is simple_exec program) and the abstract action, which is simply execute (defined by the base class: simple_commander_base). 
! Later we can use the composite pattern to create MacroCommanders (or workflows)
!
! The code is distributed with the hope that it will be useful, but _WITHOUT_ _ANY_ _WARRANTY_.
! Redistribution and modification is regulated by the GNU General Public License.
! *Authors:* Frederic Bonnet, Cyril Reboul & Hans Elmlund 2016
!
module simple_commander_preproc
use simple_defs            ! singleton
use simple_jiffys          ! singleton
use simple_timing          ! singleton
use simple_cuda            ! singleton
use simple_cuda_defs       ! singleton
use simple_cmdline,        only: cmdline
use simple_params,         only: params
use simple_build,          only: build
use simple_commander_base, only: commander_base
implicit none

public :: select_frames_commander
public :: boxconvs_commander
public :: integrate_movies_commander
public :: powerspecs_commander
public :: unblur_movies_commander
public :: select_commander
public :: pick_commander
public :: extract_commander
private

type, extends(commander_base) :: select_frames_commander 
  contains
    procedure :: execute      => exec_select_frames
end type select_frames_commander
type, extends(commander_base) :: boxconvs_commander
  contains
    procedure :: execute      => exec_boxconvs
end type boxconvs_commander
type, extends(commander_base) :: integrate_movies_commander
  contains
    procedure :: execute      => exec_integrate_movies
end type integrate_movies_commander
type, extends(commander_base) :: powerspecs_commander
 contains
   procedure :: execute      => exec_powerspecs
end type powerspecs_commander
type, extends(commander_base) :: unblur_movies_commander
  contains
    procedure :: execute      => exec_unblur_movies
end type unblur_movies_commander
type, extends(commander_base) :: select_commander
  contains
    procedure :: execute      => exec_select
end type select_commander
type, extends(commander_base) :: pick_commander
  contains
    procedure :: execute      => exec_pick
end type pick_commander
type, extends(commander_base) :: extract_commander
  contains
    procedure :: execute      => exec_extract
end type extract_commander

contains

    subroutine exec_select_frames( self, cline )
        use simple_imgfile, only: imgfile
        use simple_image,   only: image
        class(select_frames_commander), intent(inout) :: self
        class(cmdline),                 intent(inout) :: cline
        type(params)                       :: p
        type(build)                        :: b
        integer                            :: nmovies, nframes, frame, numlen, ldim(3)
        integer                            :: fromto(2), movie, cnt, cnt2, ntot, lfoo(3), ifoo
        character(len=STDLEN), allocatable :: movienames(:)
        character(len=:), allocatable      :: new_name
        type(image)                        :: img_frame
        logical, parameter                 :: debug = .false.
        p = params(cline, checkdistr=.false.)            ! constants & derived constants produced
        call b%build_general_tbox(p,cline,do3d=.false.) ! general objects built
        call read_filetable(p%filetab, movienames)
        nmovies = size(movienames)
        ! find ldim and numlen (length of number string)
        if( cline%defined('startit') )then
            call find_ldim_nptcls(movienames(p%startit), ldim, ifoo)
        endif
        if( debug ) write(*,*) 'logical dimension: ', ldim
        ldim(3) = 1 ! to correct for the stupide 3:d dim of mrc stacks
        numlen = len(int2str(nmovies))
        if( debug ) write(*,*) 'length of number string: ', numlen
        ! determine loop range
        if( cline%defined('part') )then
            if( cline%defined('fromp') .and. cline%defined('top') )then
                fromto(1) = p%fromp
                fromto(2) = p%top
                ntot = fromto(2)-fromto(1)+1
            else
                stop 'fromp & top args need to be defined in parallel execution; simple_select_frames'
            endif
        else
            fromto(1) = 1
            if( cline%defined('startit') ) fromto(1) = p%startit
            fromto(2) = nmovies
            ntot      = nmovies
        endif
        if( debug ) write(*,*) 'fromto: ', fromto(1), fromto(2)
        call img_frame%new([ldim(1),ldim(2),1], p%smpd)
        ! loop over exposures (movies)
        cnt2 = 0
        do movie=fromto(1),fromto(2)
            if( .not. file_exists(movienames(movie)) )then
                write(*,*) 'inputted movie stack does not exist: ', trim(adjustl(movienames(movie)))
            endif
            cnt2 = cnt2+1
            ! get number of frames from stack
            call find_ldim_nptcls(movienames(movie), lfoo, nframes)
            if( debug ) write(*,*) 'number of frames: ', nframes
            ! create new name
            allocate(new_name, source=trim(adjustl(p%fbody))//int2str_pad(movie, numlen)//p%ext)
            cnt = 0
            do frame=p%fromp,p%top
                cnt = cnt+1
                call img_frame%read(movienames(movie),frame)
                call img_frame%write(new_name,cnt)
            end do
            deallocate(new_name)
            write(*,'(f4.0,1x,a)') 100.*(real(cnt2)/real(ntot)), 'percent of the movies processed'
        end do
        ! end gracefully
        call simple_end('**** SIMPLE_SELECT_FRAMES NORMAL STOP ****')
    end subroutine exec_select_frames
    
    subroutine exec_boxconvs( self, cline )
        use simple_image, only: image
        class(boxconvs_commander), intent(inout) :: self
        class(cmdline),            intent(inout) :: cline
        type(params)                       :: p
        type(build)                        :: b
        type(image)                        :: tmp
        character(len=STDLEN), allocatable :: imgnames(:)
        integer                            :: iimg, nimgs, ldim(3), iimg_start, iimg_stop, ifoo
        logical                            :: debug=.false.
        if( cline%defined('stk') .and. cline%defined('filetab') )then
            stop 'stk and filetab cannot both be defined; input either or!'
        endif
        if( .not. cline%defined('stk') .and. .not. cline%defined('filetab') )then
            stop 'either stk or filetab need to be defined!'
        endif
        p = params(cline, checkdistr=.false.)               ! parameters generated
        call b%build_general_tbox( p, cline, do3d=.false. ) ! general objects built
        ! do the work
        if( cline%defined('stk') )then
            call b%img%new(p%ldim, p%smpd) ! img re-generated (to account for possible non-square)
            tmp = 0.0
            do iimg=1,p%nptcls
                call b%img%read(p%stk, iimg)
                tmp = b%img%boxconv(p%boxconvsz)
                call tmp%write(trim(adjustl(p%fbody))//p%ext, iimg)
                call progress(iimg, p%nptcls)
            end do
        else
            call read_filetable(p%filetab, imgnames)
            nimgs = size(imgnames)
            if( debug ) write(*,*) 'read the img filenames'
            ! get logical dimension of micrographs
            call find_ldim_nptcls(imgnames(1), ldim, ifoo)
            ldim(3) = 1 ! to correct for the stupide 3:d dim of mrc stacks
            if( debug ) write(*,*) 'logical dimension: ', ldim
            call b%img%new(ldim, p%smpd) ! img re-generated (to account for possible non-square)
            ! determine loop range
            iimg_start = 1
            if( cline%defined('startit') ) iimg_start = p%startit
            iimg_stop  = nimgs
            if( debug ) write(*,*) 'fromto: ', iimg_start, iimg_stop
            ! do it
            tmp = 0.0
            do iimg=iimg_start,iimg_stop
                if( .not. file_exists(imgnames(iimg)) )then
                    write(*,*) 'inputted img file does not exist: ', trim(adjustl(imgnames(iimg)))
                endif
                call b%img%read(imgnames(iimg), 1)
                tmp = b%img%boxconv(p%boxconvsz)
                call tmp%write(trim(adjustl(p%fbody))//p%ext, iimg)
                call progress(iimg, nimgs)
            end do
            call tmp%kill
            deallocate(imgnames)
        endif
        ! end gracefully
        call simple_end('**** SIMPLE_BOXCONVS NORMAL STOP ****')
    end subroutine exec_boxconvs
    
    subroutine exec_integrate_movies(self,cline)
        use simple_imgfile, only: imgfile
        use simple_image,   only: image
        class(integrate_movies_commander), intent(inout) :: self
        class(cmdline),                    intent(inout) :: cline
        type(params)                       :: p
        type(build)                        :: b
        integer                            :: nmovies, nframes, frame, alloc_stat, lfoo(3)
        integer                            :: numlen, ldim(3), fromto(2), movie, ifoo, ldim_scaled(3)
        character(len=STDLEN), allocatable :: movienames(:)
        character(len=:), allocatable      :: cpcmd
        real                               :: x, y, smpd, smpd_scaled
        type(image), allocatable           :: img_frames(:)
        type(image)                        :: img_sum, pspec, frame_tmp
        logical, parameter                 :: debug = .false.
        p = params(cline,checkdistr=.false.) ! constants & derived constants produced
        call b%build_general_tbox(p,cline,do3d=.false.)
        call read_filetable(p%filetab, movienames)
        nmovies = size(movienames)
        if( debug ) write(*,*) 'read the movie filenames'
        ! find ldim and numlen (length of number string)
        call find_ldim_nptcls(movienames(1), ldim, ifoo)
        if( debug ) write(*,*) 'logical dimension: ', ldim
        ldim(3) = 1 ! to correct for the stupid 3:d dim of mrc stacks
        if( p%scale < 0.99 )then
            ldim_scaled(1) = nint(real(ldim(1))*p%scale)
            ldim_scaled(2) = nint(real(ldim(2))*p%scale)
            ldim_scaled(3) = 1
        else
            ldim_scaled = ldim
        endif
        ! SET SAMPLING DISTANCE
        smpd        = p%smpd 
        smpd_scaled = p%smpd/p%scale
        numlen  = len(int2str(nmovies))
        if( debug ) write(*,*) 'length of number string: ', numlen
        ! determine loop range
        if( cline%defined('part') )then
            if( cline%defined('fromp') .and. cline%defined('top') )then
                fromto(1) = p%fromp
                fromto(2) = p%top
            else
                stop 'fromp & top args need to be defined in parallel execution; simple_integrate_movies'
            endif
        else
            fromto(1) = 1
            fromto(2) = nmovies
        endif
        if( debug ) write(*,*) 'fromto: ', fromto(1), fromto(2)
        ! create sum
        call img_sum%new([ldim_scaled(1),ldim_scaled(2),1], p%smpd)
        ! loop over exposures (movies)
        do movie=fromto(1),fromto(2)
            if( .not. file_exists(movienames(movie)) )&
            & write(*,*) 'inputted movie stack does not exist: ', trim(adjustl(movienames(movie)))
            ! get number of frames from stack
            call find_ldim_nptcls(movienames(movie), lfoo, nframes)
            if( debug ) write(*,*) 'number of frames: ', nframes
            ! create frames & read
            allocate(img_frames(nframes), stat=alloc_stat)
            call alloc_err('In: simple_integrate_movies', alloc_stat)
            img_sum = 0.
            do frame=1,nframes
                call frame_tmp%new(ldim, smpd)
                call frame_tmp%read(movienames(movie),frame)
                call img_frames(frame)%new([ldim_scaled(1),ldim_scaled(2),1], smpd_scaled)
                call frame_tmp%clip(img_frames(frame))
                call img_sum%add(img_frames(frame))
            end do
            ! write output
            call img_sum%write(trim(adjustl(p%fbody))//'_intg'//int2str_pad(movie, numlen)//p%ext)
            pspec = img_sum%mic2spec(p%pspecsz, trim(adjustl(p%speckind)))
            call pspec%write(trim(adjustl(p%fbody))//'_pspec'//int2str_pad(movie, numlen)//p%ext)
            ! destroy objects and deallocate
            do frame=1,nframes
                call img_frames(frame)%kill
            end do
            deallocate(img_frames)
        end do
        ! end gracefully
        call simple_end('**** SIMPLE_INTEGRATE_MOVIES NORMAL STOP ****')
    end subroutine exec_integrate_movies
    
    subroutine exec_powerspecs( self, cline )
        use simple_imgfile, only: imgfile
        use simple_image,   only: image
        class(powerspecs_commander), intent(inout) :: self
        class(cmdline),              intent(inout) :: cline
        type(params)                       :: p
        type(build)                        :: b
        type(image)                        :: powspec, tmp, mask
        character(len=STDLEN), allocatable :: imgnames(:)
        integer                            :: iimg, nimgs, ldim(3), iimg_start, iimg_stop, ifoo
        logical                            :: debug=.false.
        if( cline%defined('stk') .and. cline%defined('filetab') )then
            stop 'stk and filetab cannot both be defined; input either or!'
        endif
        if( .not. cline%defined('stk') .and. .not. cline%defined('filetab') )then
            stop 'either stk or filetab need to be defined!'
        endif
        p = params(cline, checkdistr=.false.)           ! constants & derived constants produced
        call b%build_general_tbox(p,cline,do3d=.false.) ! general toolbox built
        ! create mask
        call tmp%new([p%clip,p%clip,1], p%smpd)
        tmp = cmplx(1.,0.)
        call tmp%bp(0.,p%lp,0.)
        call tmp%ft2img('real', mask)
        call mask%write('resolution_mask.mrc', 1)
        ! do the work
        if( cline%defined('stk') )then
            call b%img%new(p%ldim, p%smpd) ! img re-generated (to account for possible non-square)
            tmp = 0.0
            do iimg=1,p%nptcls
                call b%img%read(p%stk, iimg)
                powspec = b%img%mic2spec(p%pspecsz, trim(adjustl(p%speckind)))
                call powspec%clip(tmp)
                call tmp%write(trim(adjustl(p%fbody))//p%ext, iimg)
                call progress(iimg, p%nptcls)
            end do
        else
            call read_filetable(p%filetab, imgnames)
            nimgs = size(imgnames)
            if( debug ) write(*,*) 'read the img filenames'
            ! get logical dimension of micrographs
            call find_ldim_nptcls(imgnames(1), ldim, ifoo)
            ldim(3) = 1 ! to correct for the stupide 3:d dim of mrc stacks
            if( debug ) write(*,*) 'logical dimension: ', ldim
            call b%img%new(ldim, p%smpd) ! img re-generated (to account for possible non-square)
            ! determine loop range
            iimg_start = 1
            if( cline%defined('startit') ) iimg_start = p%startit
            iimg_stop  = nimgs
            if( debug ) write(*,*) 'fromto: ', iimg_start, iimg_stop
            ! do it
            tmp = 0.0
            do iimg=iimg_start,iimg_stop
                if( .not. file_exists(imgnames(iimg)) )then
                    write(*,*) 'inputted img file does not exist: ', trim(adjustl(imgnames(iimg)))
                endif
                call b%img%read(imgnames(iimg), 1)
                powspec = b%img%mic2spec(p%pspecsz, trim(adjustl(p%speckind)))
                call powspec%clip(tmp)
                call tmp%write(trim(adjustl(p%fbody))//p%ext, iimg)
                call progress(iimg, nimgs)
            end do
        endif
        ! end gracefully
        call simple_end('**** SIMPLE_POWERSPECS NORMAL STOP ****')
    end subroutine exec_powerspecs
    
    subroutine exec_unblur_movies( self, cline )
        use simple_unblur      ! singleton
        use simple_procimgfile ! singleton
        use simple_imgfile,    only: imgfile
        use simple_oris,       only: oris
        use simple_image,      only: image
        class(unblur_movies_commander), intent(inout) :: self
        class(cmdline),                 intent(inout) :: cline
        type(params)                       :: p
        type(build)                        :: b
        type(image)                        :: movie_sum, pspec_sum, pspec_ctf, movie_sum_ctf
        type(image)                        :: movie_sum_corrected, pspec_half_n_half
        integer                            :: nmovies, imovie, imovie_start, imovie_stop, file_stat
        integer                            :: funit_movies, frame_counter, numlen,  ntot, alloc_stat, fnr
        character(len=:), allocatable      :: cpcmd, new_name
        character(len=STDLEN), allocatable :: movienames(:)
        character(len=STDLEN)              :: moviename
        real                               :: corr, time_per_frame
        logical                            :: debug=.false.
        ! CUDA err variable for the return function calls
        integer                            :: err, lfoo(3), nframes, movie_counter
        call timestamp()
        ! call start_Alltimers_cpu()
        ! starting the cuda environment
        call simple_cuda_init(err)
        if( err .ne. RC_SUCCESS ) write(*,*) 'cublas init failed'
        p = params(cline, checkdistr=.false.)           ! constants & derived constants produced
        if( p%scale > 1.05 )then
            stop 'scale cannot be > 1; simple_commander_preproc :: exec_unblur_movies'
        endif
        call b%build_general_tbox(p,cline,do3d=.false.) ! general objects built
        if( p%tomo .eq. 'yes' )then
            if( .not. p%l_dose_weight )then
                write(*,*) 'tomo=yes only supported with dose weighting!'
                stop 'give total exposure time: exp_time (in seconds) and dose_rate (in e/A2/s)'
            endif
        endif
        call read_filetable(p%filetab, movienames)
        nmovies = size(movienames)
        ! determine loop range
        if( cline%defined('part') )then
            if( p%tomo .eq. 'no' )then
                if( cline%defined('fromp') .and. cline%defined('top') )then
                    imovie_start = p%fromp
                    imovie_stop  = p%top
                else
                    stop 'fromp & top args need to be defined in parallel execution; simple_unblur_movies'
                endif
            else
                imovie_start = 1
                imovie_stop  = nmovies
            endif
        else
            imovie_start = 1
            if( cline%defined('startit') ) imovie_start = p%startit
            imovie_stop  = nmovies
        endif
        if( debug ) write(*,*) 'fromto: ', imovie_start, imovie_stop
        ntot = imovie_stop-imovie_start+1
        if( cline%defined('numlen') )then
            numlen = p%numlen
        else
            numlen = len(int2str(nmovies))
        endif
        if( debug ) write(*,*) 'length of number string: ', numlen
        ! for series of tomographic movies we need to calculate the time_per_frame
        if( p%tomo .eq. 'yes' )then
            ! get number of frames & dim from stack
            call find_ldim_nptcls(movienames(1), lfoo, nframes, endconv=endconv)
            ! calculate time_per_frame
            time_per_frame = p%exp_time/real(nframes*nmovies)
        endif
        ! align
        frame_counter = 0
        movie_counter = 0
        do imovie=imovie_start,imovie_stop
            if( .not. file_exists(movienames(imovie)) )then
                write(*,*) 'inputted movie stack does not exist: ', trim(adjustl(movienames(imovie)))
            endif
            movie_counter = movie_counter + 1
            write(*,'(a,1x,i5)') '>>> PROCESSING MOVIE:', imovie
            if( p%frameavg > 0 )then
                moviename = 'tmpframeavgmovie'//p%ext
                call frameavg_imgfile(movienames(imovie), moviename, p%frameavg)
            else
                moviename = movienames(imovie)
            endif
            call unblur_movie(moviename, p, corr)
            if( p%tomo .eq. 'yes' )then
                call unblur_calc_sums_tomo(frame_counter, time_per_frame, movie_sum, movie_sum_corrected, movie_sum_ctf)
            else
                call unblur_calc_sums(movie_sum, movie_sum_corrected, movie_sum_ctf)
            endif
            if( debug ) print *, 'ldim of output movie_sum:           ', movie_sum%get_ldim()
            if( debug ) print *, 'ldim of output movie_sum_corrected: ', movie_sum_corrected%get_ldim()
            if( debug ) print *, 'ldim of output movie_sum_ctf      : ', movie_sum_ctf%get_ldim()
            if( cline%defined('fbody') )then
                call movie_sum_corrected%write(trim(adjustl(p%fbody))//'_intg'//int2str_pad(imovie, numlen)//p%ext)
                call movie_sum_ctf%write(trim(adjustl(p%fbody))//'_ctf'//int2str_pad(imovie, numlen)//p%ext)
            else
                call movie_sum_corrected%write(int2str_pad(imovie, numlen)//'_intg'//p%ext)
                call movie_sum_ctf%write(int2str_pad(imovie, numlen)//'_ctf'//p%ext)
            endif
            pspec_sum         = movie_sum%mic2spec(p%pspecsz,     trim(adjustl(p%speckind)))
            pspec_ctf         = movie_sum_ctf%mic2spec(p%pspecsz, trim(adjustl(p%speckind)))
            pspec_half_n_half = pspec_sum%before_after(pspec_ctf)
            if( debug ) print *, 'ldim of pspec_sum:         ', pspec_sum%get_ldim()
            if( debug ) print *, 'ldim of pspec_ctf:         ', pspec_ctf%get_ldim()
            if( debug ) print *, 'ldim of pspec_half_n_half: ', pspec_half_n_half%get_ldim()
            if( cline%defined('fbody') )then
                call pspec_half_n_half%write(trim(adjustl(p%fbody))//'_pspec'//int2str_pad(imovie, numlen)//p%ext)
            else
                call pspec_half_n_half%write(int2str_pad(imovie, numlen)//'_pspec'//p%ext)
            endif
            call movie_sum%kill
            call movie_sum_corrected%kill
            call movie_sum_ctf%kill
            call pspec_sum%kill
            call pspec_ctf%kill
            call pspec_half_n_half%kill
            write(*,'(f4.0,1x,a)') 100.*(real(movie_counter)/real(ntot)), 'percent of the movies processed'
        end do
        if( cline%defined('part') )then
            fnr = get_fileunit()
            open(unit=fnr, FILE='JOB_FINISHED_'//int2str_pad(p%part,p%numlen), STATUS='REPLACE', action='WRITE', iostat=file_stat)
            call fopen_err( 'In: simple_unblur_movies', file_stat )
            write(fnr,'(A)') '**** SIMPLE_COMLIN_SMAT NORMAL STOP ****'
            close(fnr)
        endif
        ! end gracefully
        call simple_end('**** SIMPLE_UNBLUR_MOVIES NORMAL STOP ****')
        !*******************************************************************************
        !    Environment shutdown
        !
        !*******************************************************************************
        !shutting down the environment
        call simple_cuda_shutdown()
        !shutting down the timers
        ! call stop_Alltimers_cpu()
    end subroutine exec_unblur_movies

    subroutine exec_select( self, cline )
        use simple_image,  only: image
        use simple_corrmat ! singleton
        class(select_commander), intent(inout) :: self
        class(cmdline),          intent(inout) :: cline
        type(params)                       :: p
        type(build)                        :: b
        type(image), allocatable           :: imgs_sel(:), imgs_all(:)
        type(image)                        :: stk3_img
        character(len=STDLEN), allocatable :: imgnames(:)
        integer                            :: iimg, isel, nall, nsel, loc(1), ios, funit, ldim(3), ifoo, lfoo(3)
        integer, allocatable               :: selected(:)
        real, allocatable                  :: correlations(:,:)
        logical, parameter                 :: debug=.false.
        ! error check
        if( cline%defined('stk3') .or. cline%defined('filetab') )then
            ! all good
        else
            stop 'Need either stk3 or filetab are part of the command line!'
        endif
        p = params(cline)                   ! parameters generated
        call b%build_general_tbox(p, cline) ! general objects built
        ! find number of selected cavgs
        call find_ldim_nptcls(p%stk2, lfoo, nsel)
        ! find number of original cavgs
        call find_ldim_nptcls(p%stk, lfoo, nall)
        ! read images
        allocate(imgs_sel(nsel), imgs_all(nall))
        do isel=1,nsel
            call imgs_sel(isel)%new([p%box,p%box,1], p%smpd)
            call imgs_sel(isel)%read(p%stk2, isel)
        end do
        do iimg=1,nall
            call imgs_all(iimg)%new([p%box,p%box,1], p%smpd)
            call imgs_all(iimg)%read(p%stk, iimg)
        end do
        write(*,'(a)') '>>> CALCULATING CORRELATIONS'
        call calc_cartesian_corrmat(imgs_sel, imgs_all, correlations)
        ! find selected
        allocate(selected(nsel))
        do isel=1,nsel
            loc = maxloc(correlations(isel,:))
            selected(isel) = loc(1)
            if( debug ) print *, 'selected: ', loc(1), ' with corr: ', correlations(isel,loc(1))
        end do
        if( cline%defined('filetab') )then
            ! read filetable
            call read_filetable(p%filetab, imgnames)
            if( size(imgnames) /= nall ) stop 'nr of entries in filetab and stk not consistent'
            funit = get_fileunit()
            open(unit=funit, file=p%outfile, iostat=ios, status="replace", action="write", access="sequential")
            if( ios /= 0 )then
                write(*,*) "Error opening file name", trim(adjustl(p%outfile))
                stop
            endif
            call execute_command_line('mkdir '//trim(adjustl(p%dir)))
            ! write outoput & move files
            do isel=1,nsel
                write(funit,'(a)') trim(adjustl(imgnames(selected(isel))))
                call execute_command_line('mv '//trim(adjustl(imgnames(selected(isel))))//' '//trim(adjustl(p%dir)))
            end do
            close(funit)
            deallocate(imgnames)
        endif
        if( cline%defined('stk3') )then
            call find_ldim_nptcls(p%stk3, ldim, ifoo)
            ldim(3) = 1
            call stk3_img%new(ldim,1.)
            do isel=1,nsel
                call stk3_img%read(p%stk3, selected(isel))
                call stk3_img%write(p%outstk, isel)
            end do
        endif
        ! end gracefully
        call simple_end('**** SIMPLE_SELECT NORMAL STOP ****')
    end subroutine exec_select

    subroutine exec_pick( self, cline)
        use simple_picker
        class(pick_commander), intent(inout) :: self
        class(cmdline),        intent(inout) :: cline
        type(params)                         :: p
        integer                              :: nmicrographs, funit, alloc_stat, imic
        integer                              :: imic_start, imic_stop, ntot, imic_cnt
        integer                              :: offset
        real                                 :: shrink, dcrit_rel
        character(len=STDLEN), allocatable   :: micrographnames(:)
        p = params(cline, checkdistr=.false.) ! constants & derived constants produced
        offset    = 3
        if( cline%defined('offset') )    offset = p%offset
        shrink    = 4.0
        if( cline%defined('shrink') )    shrink = p%shrink
        dcrit_rel = 0.5
        if( cline%defined('dcrit_rel') ) dcrit_rel = p%dcrit_rel
        ! check filetab existence
        if( .not. file_exists(p%filetab) ) stop 'inputted filetab does not exist in cwd'
        ! set number of micrographs
        nmicrographs = nlines(p%filetab)
        ! read the filenames
        funit = get_fileunit()
        open(unit=funit, status='old', file=p%filetab)
        allocate( micrographnames(nmicrographs), stat=alloc_stat )
        call alloc_err('In: simple_commander_preproc :: exec_pick', alloc_stat)
        do imic=1,nmicrographs
            read(funit, '(a256)') micrographnames(imic)
        end do
        close(funit)
        ! determine loop range
        if( cline%defined('part') )then
            if( cline%defined('fromp') .and. cline%defined('top') )then
                imic_start = p%fromp
                imic_stop  = p%top
            else
                stop 'fromp & top args need to be defined in parallel execution; simple_pick'
            endif
        else
            imic_start = 1
            if( cline%defined('startit') ) imic_start = p%startit
            imic_stop  = nmicrographs
        endif
        ntot     = imic_stop-imic_start+1
        imic_cnt = 0
        do imic=imic_start,imic_stop
            imic_cnt = imic_cnt + 1
            if( .not. file_exists(micrographnames(imic)) )then
                write(*,*) 'inputted micrograph does not exist: ', trim(adjustl(micrographnames(imic)))
            endif
            write(*,'(a,1x,i5)') '>>> PROCESSING MICROGRAPH:', imic, trim(adjustl(micrographnames(imic)))
            if( cline%defined('thres') )then
                call init_picker(micrographnames(imic), p%refs, p%smpd, p%msk, offset_in=offset,&
                shrink_in=shrink, lp_in=p%lp, dcrit_rel_in=dcrit_rel, distthr_in=p%thres)
            else
                call init_picker(micrographnames(imic), p%refs, p%smpd, p%msk, offset_in=offset,&
                shrink_in=shrink, lp_in=p%lp, dcrit_rel_in=dcrit_rel)
            endif
            call pick_particles
            call kill_picker
            write(*,'(f4.0,1x,a)') 100.*(real(imic_cnt)/real(ntot)), 'percent of the micrographs processed'
        end do
    end subroutine exec_pick
    
    subroutine exec_extract( self, cline )
        use simple_nrtxtfile, only: nrtxtfile
        use simple_imgfile,   only: imgfile
        use simple_image,     only: image
        use simple_math,      only: euclid, hpsort, median
        use simple_oris,      only: oris
        use simple_stat,      only: moment
        class(extract_commander), intent(inout) :: self
        class(cmdline),           intent(inout) :: cline
        type(params)                       :: p
        type(build)                        :: b
        integer                            :: nmovies, nboxfiles, funit_movies, funit_box, nframes, frame, pind
        integer                            :: i, j, k, alloc_stat, ldim(3), box_current, movie, ndatlines, nptcls
        integer                            :: cnt, niter, fromto(2), orig_box
        integer                            :: movie_ind, numlen, ntot, lfoo(3), ifoo, noutside=0
        type(nrtxtfile)                    :: boxfile
        character(len=STDLEN)              :: mode, framestack, sumstack
        character(len=STDLEN), allocatable :: movienames(:), boxfilenames(:)
        real, allocatable                  :: boxdata(:,:)
        integer, allocatable               :: pinds(:)
        real                               :: x, y, dfx, dfy, angast, ctfres, med, ave,sdev, var
        type(image)                        :: img_frame
        type(oris)                         :: outoris
        logical                            :: err
        logical, parameter                 :: debug = .false.
        p = params(cline, checkdistr=.false.) ! constants & derived constants produced
        if( p%noise_norm .eq. 'yes' )then
            if( .not. cline%defined('msk') ) stop 'need rough mask radius as input (msk) for noise normalisation'
        endif
        
        ! check file inout existence
        if( .not. file_exists(p%filetab) ) stop 'inputted filetab does not exist in cwd'
        if( .not. file_exists(p%boxtab) )  stop 'inputted boxtab does not exist in cwd'
        nmovies = nlines(p%filetab)
        if( debug ) write(*,*) 'nmovies: ', nmovies
        nboxfiles = nlines(p%boxtab)
        if( debug ) write(*,*) 'nboxfiles: ', nboxfiles
        if( nmovies /= nboxfiles ) stop 'number of entries in inputted files do not match!'
        funit_movies = get_fileunit()
        open(unit=funit_movies, status='old', file=p%filetab)
        funit_box = get_fileunit()
        open(unit=funit_box, status='old', file=p%boxtab)
        allocate( movienames(nmovies), boxfilenames(nmovies), stat=alloc_stat )
        call alloc_err('In: simple_extract; boxdata etc., 1', alloc_stat)

        ! remove output file
        call del_txtfile('extract_params.txt')

        ! read the filenames
        do movie=1,nmovies
            read(funit_movies,'(a256)') movienames(movie)
            read(funit_box,   '(a256)') boxfilenames(movie)
        end do
        close(funit_movies)
        close(funit_box)
        if( debug ) write(*,*) 'read the filenames'

        ! determine loop range
        fromto(1) = 1
        fromto(2) = nmovies
        ntot = fromto(2)-fromto(1)+1
        if( debug ) write(*,*) 'fromto: ', fromto(1), fromto(2)

        ! count the number of particles & find ldim
        nptcls = 0
        do movie=fromto(1),fromto(2)
            if( file_exists(boxfilenames(movie)) )then
                if( nlines(boxfilenames(movie)) > 0 )then
                    call boxfile%new(boxfilenames(movie), 1)
                    ndatlines = boxfile%get_ndatalines()
                    nptcls = nptcls+ndatlines
                    call boxfile%kill
                endif
            else
                write(*,*) 'WARNING! The inputted boxfile (below) does not exist'
                write(*,*) trim(boxfilenames(movie))
            endif
        end do
        call find_ldim_nptcls(movienames(1), ldim, ifoo)
        if( debug ) write(*,*) 'number of particles: ', nptcls

        ! create frame
        call img_frame%new([ldim(1),ldim(2),1], p%smpd)

        ! initialize
        call outoris%new(nptcls)
        pind = 0
        if( debug ) write(*,*) 'made outoris'

        ! loop over exposures (movies)
        niter    = 0
        noutside = 0
        do movie=fromto(1),fromto(2)
    
            ! get movie index (parsing the number string from the filename)
            call fname2ind(trim(adjustl(movienames(movie))), movie_ind)

            ! process boxfile
            ndatlines = 0
            if( file_exists(boxfilenames(movie)) )then
                if( nlines(boxfilenames(movie)) > 0 )then
                    call boxfile%new(boxfilenames(movie), 1)
                    ndatlines = boxfile%get_ndatalines()
                endif       
            endif
            if( ndatlines == 0 ) cycle
    
            ! update iteration counter (has to be after the cycle statements or suffer bug!!!)
            niter = niter+1

             ! show progress
            if( niter > 1 ) call progress(niter,ntot)
    
            ! read box data
            allocate( boxdata(ndatlines,boxfile%get_nrecs_per_line()), pinds(ndatlines), stat=alloc_stat )
            call alloc_err('In: simple_extract; boxdata etc., 2', alloc_stat)
            do j=1,ndatlines
                call boxfile%readNextDataLine(boxdata(j,:))
                orig_box = nint(boxdata(j,3))
                if( nint(boxdata(j,3)) /= nint(boxdata(j,4)) )then
                    stop 'Only square windows are currently allowed!'
                endif
            end do
    
            ! create particle index list and set movie index
            if( .not. cline%defined('box') ) p%box = nint(boxdata(1,3)) ! use the box size from the box file
            do j=1,ndatlines
                if( box_inside(ldim, nint(boxdata(j,1:2)), p%box) )then
                    pind     = pind+1
                    pinds(j) = pind
                    call outoris%set(pinds(j), 'movie', real(movie_ind))
                else
                    pinds(j) = 0
                endif
            end do
    
            ! check box parsing
            if( .not. cline%defined('box') )then
                if( niter == 1 )then
                    p%box = nint(boxdata(1,3))   ! use the box size from the box file
                else
                    box_current = nint(boxdata(1,3))
                    if( box_current /= p%box )then
                        write(*,*) 'box_current: ', box_current, 'box in params: ', p%box
                        stop 'inconsistent box sizes in box files'
                    endif
                endif
                if( p%box == 0 )then
                    write(*,*) 'ERROR, box cannot be zero!'
                    stop
                endif
            endif
            if( debug ) write(*,*) 'did check box parsing'
    
            ! get number of frames from stack
            call find_ldim_nptcls(movienames(movie), lfoo, nframes )
            numlen  = len(int2str(nframes))
            if( debug ) write(*,*) 'number of frames: ', nframes
    
            ! build general objects
            if( niter == 1 ) call b%build_general_tbox(p,cline,do3d=.false.)

            ! extract ctf info
            if( b%a%isthere('dfx') )then
                dfx = b%a%get(movie,'dfx')
                ctfres = b%a%get(movie,'ctfres')
                angast= 0.
                if( b%a%isthere('dfy') )then ! astigmatic CTF
                    if( .not. b%a%isthere('angast') ) stop 'need angle of astigmatism for CTF correction'
                    dfy = b%a%get(movie,'dfy')
                    angast = b%a%get(movie,'angast')
                endif
                ! set CTF info in outoris
                do i=1,ndatlines
                    if( pinds(i) > 0 )then
                        call outoris%set(pinds(i), 'dfx', dfx)
                        call outoris%set(pinds(i), 'ctfres', ctfres)
                        if( b%a%isthere('dfy') )then
                            call outoris%set(pinds(i), 'angast', angast)
                            call outoris%set(pinds(i), 'dfy', dfy)
                        endif
                    endif
                end do
                if( debug ) write(*,*) 'did set CTF parameters dfx/dfy/angast/ctfres: ', dfx, dfy, angast, ctfres
            endif
    
            ! loop over frames
            do frame=1,nframes
        
                ! read frame
                call img_frame%read(movienames(movie),frame)
        
                if( nframes > 1 )then
                    ! shift frame according to global shift (drift correction)
                    if( b%a%isthere(movie, 'x'//int2str(frame)) .and. b%a%isthere(movie, 'y'//int2str(frame))  )then
                        call img_frame%fwd_ft
                        x = b%a%get(movie, 'x'//int2str(frame))
                        y = b%a%get(movie, 'y'//int2str(frame))
                        call img_frame%shift(-x,-y)
                        call img_frame%bwd_ft
                    else
                        write(*,*) 'no shift parameters available for alignment of frames'
                        stop 'use simple_unblur_movies if you want to integrate frames'
                    endif
                endif
        
                ! extract the particle images & normalize
                if( nframes > 1 )then
                    framestack = 'framestack'//int2str_pad(frame,numlen)//p%ext
                else
                    framestack = 'sumstack'//p%ext
                endif
                cnt = 0
                do j=1,ndatlines ! loop over boxes
                    if( pinds(j) > 0 )then
                        ! modify coordinates if change in box (shift by half)
                        if( debug ) print *, 'original coordinate: ', boxdata(j,1:2) 
                        if( orig_box /= p%box ) boxdata(j,1:2) = boxdata(j,1:2)-real(p%box-orig_box)/2.
                        if( debug ) print *, 'shifted coordinate: ', boxdata(j,1:2) 
                        ! extract the window    
                        call img_frame%window(nint(boxdata(j,1:2)), p%box, b%img, noutside)
                        if( p%neg .eq. 'yes' ) call b%img%neg
                        if( p%noise_norm .eq. 'yes' )then
                            call b%img%noise_norm(p%msk)
                        else
                            call b%img%norm
                        endif
                        call b%img%write(trim(adjustl(framestack)), pinds(j))
                    endif
                end do
            end do
    
            if( nframes > 1 )then
                ! create the sum and normalize it
                sumstack = 'sumstack'//p%ext
                cnt = 0
                do j=1,ndatlines ! loop over boxes
                    if( pinds(j) > 0 )then
                        b%img_copy = 0.
                        do frame=1,nframes ! loop over frames
                            framestack = 'framestack'//int2str_pad(frame,numlen)//p%ext
                            call b%img%read(trim(adjustl(framestack)), pinds(j))
                            call b%img_copy%add(b%img)
                        end do
                        if( p%noise_norm .eq. 'yes' )then
                            call b%img_copy%noise_norm(p%msk)
                        else
                            call b%img_copy%norm
                        endif
                        call b%img_copy%write(trim(adjustl(sumstack)), pinds(j))
                    endif
                end do
            endif
    
            ! write output
            do j=1,ndatlines ! loop over boxes
                if( pinds(j) > 0 )then
                    call outoris%write(pinds(j), 'extract_params.txt')
                endif
            end do
    
            ! destruct
            call boxfile%kill
            deallocate(boxdata, pinds)
        end do
        if( p%outside .eq. 'yes' .and. noutside > 0 )then
            write(*,'(a,1x,i5,1x,a)') 'WARNING!', noutside, 'boxes extend outside micrograph'
        endif

        ! end gracefully
        call simple_end('**** SIMPLE_EXTRACT NORMAL STOP ****')

        contains
    
            function box_inside( ldim, coord, box ) result( inside )
                integer, intent(in) :: ldim(3), coord(2), box
                integer             :: fromc(2), toc(2)
                logical             :: inside
                if( p%outside .eq. 'yes' )then
                    inside = .true.
                    return
                endif
                fromc  = coord+1       ! compensate for the c-range that starts at 0
                toc    = fromc+(box-1) ! the lower left corner is 1,1
                inside = .true.        ! box is inside
                if( any(fromc < 1) .or. toc(1) > ldim(1) .or. toc(2) > ldim(2) ) inside = .false.
            end function box_inside
            
    end subroutine exec_extract

end module simple_commander_preproc

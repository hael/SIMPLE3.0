!==Class simple_commander_tseries
!
! This class contains the set of concrete time-series commanders of the SIMPLE library. This class provides the glue 
! between the reciver (main reciever is simple_exec program) and the abstract action, which is simply execute (defined by the base 
! class: simple_commander_base). Later we can use the composite pattern to create MacroCommanders (or workflows)
!
! The code is distributed with the hope that it will be useful, but _WITHOUT_ _ANY_ _WARRANTY_.
! Redistribution and modification is regulated by the GNU General Public License.
! *Authors:* Cyril Reboul & Hans Elmlund 2016
!
module simple_commander_tseries
use simple_defs
use simple_cmdline,        only: cmdline
use simple_params,         only: params
use simple_build,          only: build
use simple_commander_base, only: commander_base
use simple_strings,        only: int2str, int2str_pad
use simple_filehandling    ! use all in there
use simple_jiffys          ! use all in there
implicit none

public :: tseries_extract_commander
public :: tseries_track_commander
private

type, extends(commander_base) :: tseries_extract_commander
  contains
    procedure :: execute      => exec_tseries_extract
end type tseries_extract_commander
type, extends(commander_base) :: tseries_track_commander
  contains
    procedure :: execute      => exec_tseries_track
end type tseries_track_commander

contains

    subroutine exec_tseries_extract( self, cline )
        use simple_image, only: image
        class(tseries_extract_commander), intent(inout) :: self
        class(cmdline),                   intent(inout) :: cline
        type(params) :: p
        character(len=STDLEN), allocatable :: filenames(:)
        character(len=STDLEN)              :: outfname
        integer      :: ldim(3), nframes, frame_from, frame_to, numlen, cnt
        integer      :: iframe, jframe, nfiles
        type(image)  :: frame_img
        p = params(cline) ! parameters generated
        if( cline%defined('filetab') )then
            call read_filetable(p%filetab, filenames)
            nfiles = size(filenames)
            numlen = len(int2str(nfiles))
        else
            stop 'need filetab input, listing all the individual frames of&
            &the time series; simple_commander_tseries :: exec_tseries_extract'
        endif
        call find_ldim_nptcls(filenames(1),ldim,nframes)
        if( nframes == 1 .and. ldim(3) == 1 )then
            ! all ok
            call frame_img%new(ldim, p%smpd)
        else
            write(*,*) 'ldim(3): ', ldim(3)
            write(*,*) 'nframes: ', nframes
            stop 'simple_commander_imgproc :: exec_tseries_extract assumes one frame per file' 
        endif
        if( cline%defined('frameavg') )then
            if( p%frameavg < 3 )then
                stop 'frameavg integer (nr of frames to average) needs to be >= 3; &
                &simple_commander_imgproc :: exec_tseries_extract'
            endif
        else
            stop 'need frameavg integer input = nr of frames to average; &
            &simple_commander_imgproc :: exec_tseries_extract'
        endif
        do iframe=1,nfiles - p%frameavg + 1
            if( cline%defined('fbody') )then
                outfname = 'tseries_frames'//int2str_pad(iframe,numlen)//p%ext
            else
                outfname = trim(p%fbody)//'tseries_frames'//int2str_pad(iframe,numlen)//p%ext
            endif
            frame_from = iframe
            frame_to   = iframe + p%frameavg - 1
            cnt = 0
            do jframe=frame_from,frame_to
                cnt = cnt + 1
                call frame_img%read(filenames(jframe),1)
                call frame_img%write(outfname,cnt)
            end do
        end do
        call frame_img%kill
        ! end gracefully
        call simple_end('**** SIMPLE_TSERIES_EXTRACT NORMAL STOP ****')
    end subroutine exec_tseries_extract

    ! filetab
    ! boxfile
    ! fbody
    ! smpd
    ! lp
    ! offset (7 pix)
    ! FROM BOX FILE: xccoord, ycoord, box

    subroutine exec_tseries_track( self, cline )
        use simple_tseries_tracker
        use simple_nrtxtfile, only: nrtxtfile
        class(tseries_track_commander), intent(inout) :: self
        class(cmdline),                 intent(inout) :: cline
        type(params)      :: p
        type(nrtxtfile)   :: boxfile
        integer           :: ndatlines, alloc_stat, j, orig_box, numlen
        real, allocatable :: boxdata(:,:)

        p = params(cline) ! parameters generated
        ! check file inout existence and read filetables
        if( .not. file_exists(p%filetab) ) stop 'inputted filetab does not exist in cwd'
        if( .not. file_exists(p%boxfile)  ) stop 'inputted boxfile does not exist in cwd'

        if( nlines(p%boxfile) > 0 )then
            call boxfile%new(p%boxfile, 1)
            ndatlines = boxfile%get_ndatalines()
            numlen    = len(int2str(ndatlines))
            allocate( boxdata(ndatlines,boxfile%get_nrecs_per_line()), stat=alloc_stat)
            call alloc_err('In: simple_commander_tseries :: exec_tseries_track', alloc_stat)
            do j=1,ndatlines
                call boxfile%readNextDataLine(boxdata(j,:))
                orig_box = nint(boxdata(j,3))
                if( nint(boxdata(j,3)) /= nint(boxdata(j,4)) )then
                    stop 'Only square windows are currently allowed!'
                endif
                call init_tracker(p%filetab, nint(boxdata(j,1:2)), orig_box, p%offset, p%smpd, p%lp)
                call track_particle
                call write_tracked_series(p%fbody//int2str_pad(j,numlen))
                call kill_tracker
            end do
        else
            stop 'inputted boxfile is empty; simple_commander_tseries :: exec_tseries_track'
        endif
    end subroutine exec_tseries_track

end module simple_commander_tseries

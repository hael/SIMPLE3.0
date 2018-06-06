!!
!! System library functions and error checking
!!
!! Error routines:   simple_stop, allocchk, simple_error_check, raise_sys_error
!! System routines:  exec_cmdline, simple_sleep, simple_isenv simple_getcwd, simple_chdir simple_chmod
!! File routines:    simple_file_stat, wait_for_closure is_io is_open file_exists is_file_open
!! Memory routines:  simple_mem_usage, simple_dump_mem_usage

!! Function:  get_sys_error simple_getenv  get_lunit cpu_usage get_process_id

!! New interface: get_file_list, list_dirs, subprocess, glob_list_tofile, show_dir_content_recursive
!! New OS calls:  simple_list_dirs, simple_list_files, simple_rmdir, simple_del_files, exec_subprocess

module simple_syslib
use simple_defs
use simple_error
use iso_c_binding
#if defined(GNU)
use, intrinsic :: iso_fortran_env, only: &
    &stderr=>ERROR_UNIT, stdout=>OUTPUT_UNIT,&
    &IOSTAT_END, IOSTAT_EOR, COMPILER_VERSION, COMPILER_OPTIONS
#elif defined(INTEL)
use, intrinsic :: iso_fortran_env, only: &
    &stderr=>ERROR_UNIT, stdout=>OUTPUT_UNIT,&
    &IOSTAT_END, IOSTAT_EOR
#endif
#if defined(INTEL)
use ifport, killpid=>kill, intel_ran=>ran
use ifcore
#endif
use simple_error
implicit none

private :: raise_sys_error
public

!> libc interface
interface

    ! rmdir    CONFORMING TO POSIX.1-2001, POSIX.1-2008, SVr4, 4.3BSD.
    ! On  success,  zero is returned.  On error, -1 is returned, and errno is
    ! set appropriately.
    function rmdir(dirname) bind(C, name="rmdir")
        use, intrinsic :: iso_c_binding
        integer(c_int) :: rmdir
        character(c_char),dimension(*),intent(in)  ::  dirname
    end function rmdir

    function mkdir(path,mode) bind(c,name="mkdir")
        use, intrinsic :: iso_c_binding
        integer(c_int) :: mkdir
        character(kind=c_char,len=1),dimension(*),intent(in) :: path
        integer(c_int16_t), value :: mode
    end function mkdir

    function symlink(target_path, link_path) bind(c,name="symlink")
        use, intrinsic :: iso_c_binding
        integer(c_int) :: symlink
        character(kind=c_char,len=1),dimension(*),intent(in) :: target_path
        character(kind=c_char,len=1),dimension(*),intent(in) :: link_path
    end function symlink
    function sync () bind(c,name="sync")
        integer :: sync
    end function sync

end interface

!> SIMPLE_POSIX.c commands
interface

    function isdir(dirname, str_len) bind(C, name="isdir")
        import
        integer(c_int) :: isdir
        character(c_char),dimension(*),intent(in)  ::  dirname
        integer(c_int), intent(in) :: str_len
    end function isdir

    function makedir(dirname) bind(C, name="makedir")
        import
        integer(c_int) :: makedir
        character(c_char),dimension(*),intent(in)  ::  dirname
    end function makedir

    function removedir(dirname,len, count) bind(C, name="remove_directory")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: removedir
        character(c_char),dimension(*),intent(in)  ::  dirname
        integer(c_int), intent(in) :: len
        integer(c_int), intent(in) :: count
    end function removedir

    function recursive_delete(dirname,len, count) bind(C, name="recursive_delete")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: recursive_delete
        character(c_char),dimension(*),intent(in)  ::  dirname
        integer(c_int), intent(in) :: len
        integer(c_int), intent(in) :: count
    end function recursive_delete

    function get_file_list(path,  ext, count) bind(c,name="get_file_list")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: get_file_list                           !> return success
        character(kind=c_char,len=1),dimension(*),intent(in)   :: path
        character(kind=c_char,len=1),dimension(*),intent(in)   :: ext
        integer(c_int), intent(inout) :: count                    !> number of elements in results
    end function get_file_list

    function get_file_list_modified(path, ext, count, flag) bind(c,name="get_file_list_modified")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: get_file_list_modified                  !> return success
        character(kind=c_char,len=1),dimension(*),intent(in)   :: path
        character(kind=c_char,len=1),dimension(3),intent(in)   :: ext
        integer(c_int), intent(inout) :: count                    !> number of elements in results
        integer(c_int), intent(in), value :: flag                 !> 1st bit reverse, 2nd bit alphanumeric sort or modified time
    end function get_file_list_modified

    function glob_file_list(av, count, flag) bind(c,name="glob_file_list")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: glob_file_list                           !> return success
        character(kind=c_char,len=1),dimension(*),intent(in)    :: av  !> glob string
        integer(c_int), intent(inout) :: count                     !> number of elements in results
        integer(c_int), intent(in)    :: flag                      !> flag 1=time-modified reverse
    end function glob_file_list

    function glob_rm_all(av, count) bind(c,name="glob_rm_all")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: glob_rm_all                              !> return success
        character(kind=c_char,len=1),dimension(*),intent(in):: av  !> glob string
        integer(c_int), intent(inout) :: count                     !> number of elements in results
    end function glob_rm_all

    function list_dirs(path,  count) bind(c,name="list_dirs")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: list_dirs                                 !> return success
        character(kind=c_char,len=1),dimension(*),intent(in)   :: path
        type(c_ptr) :: file_list_ptr
        integer(c_int), intent(inout) :: count                      !> return number of elements in results
    end function list_dirs

    subroutine show_dir_content_recursive(path) bind(c,name="show_dir_content_recursive")
        use, intrinsic :: iso_c_binding
        implicit none
        character(kind=c_char,len=1),dimension(*),intent(in) :: path
    end subroutine show_dir_content_recursive

    function subprocess(cmd, cmdlen) bind(c,name="subprocess")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: subprocess                                  !> return PID of forked process
        character(kind=c_char,len=1),dimension(*),intent(in) :: cmd   !> executable path
        integer(c_int), intent(in) :: cmdlen
    end function subprocess

    function wait_pid(pid) bind(c,name="wait_pid")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: wait_pid                                  !> return PID of forked process
        integer(c_int), intent(in) :: pid
    end function wait_pid

    function fcopy(file1, len1, file2, len2) bind(c,name="fcopy")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: fcopy                                       !> return success of fcopy
        character(kind=c_char,len=1),dimension(*),intent(in) :: file1
        integer(c_int), intent(in) :: len1
        character(kind=c_char,len=1),dimension(*),intent(in) :: file2
        integer(c_int), intent(in) :: len2
    end function fcopy

    function fcopy_mmap(file1, len1, file2, len2) bind(c,name="fcopy_mmap")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: fcopy_mmap                                       !> return success of fcopy
        character(kind=c_char,len=1),dimension(*),intent(in) :: file1
        integer(c_int), intent(in) :: len1
        character(kind=c_char,len=1),dimension(*),intent(in) :: file2
        integer(c_int), intent(in) :: len2
      end function fcopy_mmap

    function fcopy2(file1, len1, file2, len2) bind(c,name="fcopy_sendfile")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: fcopy2                                       !> return success of fcopy
        character(kind=c_char,len=1),dimension(*),intent(in) :: file1
        integer(c_int), intent(in) :: len1
        character(kind=c_char,len=1),dimension(*),intent(in) :: file2
        integer(c_int), intent(in) :: len2
    end function fcopy2

    function touch(filename, len) bind(c,name="touch")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: touch                                       !> return success of touch
        character(kind=c_char,len=1),dimension(*),intent(in) :: filename
        integer(c_int), intent(in) :: len
    end function touch

    subroutine free_file_list(p, n) bind(c, name='free_file_list')
        use, intrinsic :: iso_c_binding, only: c_ptr, c_int, c_char
        implicit none
        type(c_ptr), intent(in), value :: p
        integer(c_int), intent(in), value :: n
    end subroutine free_file_list

    function get_absolute_pathname(infile, inlen, outfile, outlen) bind(c,name="get_absolute_pathname")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: get_absolute_pathname
        character(kind=c_char,len=1),dimension(*),intent(in) :: infile
        integer(c_int), intent(in) :: inlen  !> string lengths
        character(kind=c_char,len=1),dimension(*),intent(inout) :: outfile
        integer(c_int), intent(out) :: outlen  !> string lengths
    end function get_absolute_pathname

    function get_sysinfo(HWM, totRAM, shRAM, bufRAM, peakBuf) bind(c,name="get_sysinfo")
        use, intrinsic :: iso_c_binding
        implicit none
        integer(c_int) :: get_sysinfo
        integer(c_long), intent(inout) :: HWM, totRAM, shRAM, bufRAM, peakBuf
    end function get_sysinfo

end interface

contains

    !>  Wrapper for system call
    subroutine exec_cmdline( cmdline, waitflag, suppress_errors)
        character(len=*),  intent(in) :: cmdline
        logical, optional, intent(in) :: waitflag, suppress_errors
        character(len=:), allocatable :: cmdmsg, tmp,  cmsg
        integer ::  cstat, exec_stat
        logical :: l_doprint, wwait, l_suppress_errors
        l_doprint = .false.
        wwait     = .true.
        if( present(waitflag)        ) wwait = waitflag
        if( present(suppress_errors) ) l_suppress_errors = suppress_errors
        allocate(cmsg, source=trim(adjustl(cmdline)))
        if( l_suppress_errors )then
            allocate(tmp, source=cmsg//' '//SUPPRESS_MSG)
            cmsg = trim(tmp)
        endif
        call execute_command_line(trim(adjustl(cmsg)), wait=wwait, exitstat=exec_stat, cmdstat=cstat, cmdmsg=cmdmsg)
        if( .not. l_suppress_errors ) call raise_sys_error( cmsg, exec_stat, cstat, cmdmsg )
        if( l_doprint )then
            write(*,*) 'command            : ', cmsg
            write(*,*) 'status of execution: ', exec_stat
        endif
    end subroutine exec_cmdline

    !>  Wrapper for simple_posix's subprocess : this uses system fork & execp
    subroutine exec_subprocess( cmdline, pid )
        character(len=*),  intent(in)      :: cmdline
        integer, intent(out)               :: pid
        character(len=STDLEN)              :: tmp
        character(len=:), allocatable      :: cmd
        integer                            :: pos, cmdlen
        allocate(cmd, source=trim(adjustl(cmdline))//c_null_char)
        cmdlen = len(trim(adjustl(cmd)))
        pid = subprocess( cmd, cmdlen  )
        deallocate(cmd)
    end subroutine exec_subprocess

    !>  Handles error from system call
    subroutine raise_sys_error( cmd, exitstat, cmdstat, cmdmsg )
        integer,               intent(in) :: exitstat, cmdstat
        character(len=*),      intent(in) :: cmd
        character(len=STDLEN), intent(in) :: cmdmsg
        logical :: err
        err = .false.
        if( exitstat /= 0 )then
            write(*,*)'System error', exitstat,' for command: ', trim(adjustl(cmd))
            err = .true.
        endif
        if( cmdstat /= 0 )then
            call simple_error_check(cmdstat,' command could not be executed: '//trim(adjustl(cmd)))
            write(*,*)'cmdstat = ',cmdstat,' command could not be executed: ', trim(adjustl(cmd))
            err = .true.
        endif
    end subroutine raise_sys_error

    !! ENVIRONMENT FUNCTIONS

    !> isenv; return 0 if environment variable is present
    logical function simple_isenv( name )
        character(len=*), intent(in) :: name
        character(len=STDLEN)        :: varval
        integer                      :: length, status
        simple_isenv=.false.
        status=1
        call get_environment_variable( trim(adjustl(name)), status=status)
        if(status==0) simple_isenv=.true.
    end function simple_isenv

    !> simple_getenv gets the environment variable string and status
    function simple_getenv( name , retval, allowfail)  result( status )
        character(len=*),      intent(in)  :: name
        character(len=*),      intent(out) :: retval
        logical,     optional, intent(in)  :: allowfail
        integer                            :: length, status
        call get_environment_variable( trim(name), value=retval, length=length, status=status)
        if( status == -1 ) write(*,*) 'value string too short; simple_syslib :: simple_getenv'
        if( status ==  1 )then
            write(*,*) 'environment variable: ', trim(name), ' is not defined; simple_syslib :: simple_getenv'
            retval = 'undefined'
            return
        endif
        if( status ==  2 ) write(*,*) 'environment variables not supported by system; simple_syslib :: simple_getenv'
        if( length ==  0 .or. status /= 0 )then
            retval = ""
            return
        end if
    end function simple_getenv

    subroutine simple_sleep( secs )
        integer, intent(in) :: secs
        integer(kind=8)     :: longtime
#if defined(INTEL)
        integer             :: msecs
        msecs = 1000*INT(secs)
        call sleepqq(msecs)  !! milliseconds
#else
        call sleep(INT(secs)) !! intrinsic
#endif
    end subroutine simple_sleep

    !! SYSTEM FILE OPERATIONS

    !> \brief Touch file, create file if necessary
    subroutine simple_touch( fname , errmsg, status)
        character(len=*), intent(in)           :: fname !< input filename
        character(len=*), intent(in), optional :: errmsg
        integer, intent(out), optional :: status
        integer :: iostat
        iostat  = touch(trim(adjustl(fname)), len_trim(adjustl(fname)))
        if(iostat/=0)then
            call simple_error_check(iostat, "In simple_touch  msg:"//trim(errmsg))
        endif
        if(present(status))status=iostat
    end subroutine simple_touch

    !> \brief Soft link file
    subroutine syslib_symlink( f1, f2 , errmsg, status)
        character(len=*), intent(in)           :: f1, f2 !< input filename
        character(len=*), intent(in), optional :: errmsg
        integer, intent(out), optional :: status
        integer :: iostat
        iostat  = symlink(trim(adjustl(f1))//achar(0), trim(adjustl(f2))//achar(0))
        if(iostat/=0)then
            call simple_error_check(iostat, "In syslib_symlink  msg:"//trim(errmsg))
        endif
        if(present(status))status=iostat
    end subroutine syslib_symlink

    subroutine syslib_copy_file(fname1, fname2, status)
        character(len=*),  intent(in)  :: fname1, fname2 !< input filenames
        integer, optional, intent(out) :: status
        integer(dp),      parameter   :: MAXBUFSZ = 1e8  ! 100 MB max buffer size
        character(len=1), allocatable :: byte_buffer(:)
        integer(dp) :: sz, nchunks, leftover, bufsz, bytepos, in, out, ichunk
        integer     :: ioerr
        if( present(status) )status = 0
        ! process input file
        ! we need to inquire size before opening file as stream access
        ! does not allow inquire of size from file unit
        inquire(file=trim(fname1),size=sz)
        open(newunit=in, file=trim(fname1), status="old", action="read", access="stream", iostat=ioerr)
        if( ioerr /= 0 )then
            print *,"In syslib_copy_file, failed to open input file ", trim(fname1)
            call simple_error_check(ioerr,"syslib_copy_file input file not opened")
            if( present(status) ) status = ioerr
            return
        endif
        if( sz <= MAXBUFSZ )then
            nchunks  = 1
            leftover = 0
            bufsz    = sz
        else
            nchunks  = sz / MAXBUFSZ
            leftover = sz - nchunks * MAXBUFSZ
            bufsz    = MAXBUFSZ
        endif
        ! allocate raw byte buffer
        allocate(byte_buffer(bufsz))
        ! process output file
        open(newunit=out, file=trim(fname2), status="replace", action="write", access="stream", iostat=ioerr)
        if( ioerr /= 0 )then
            print *,"In syslib_copy_file, failed to open output file ", trim(fname2)
            call simple_error_check(ioerr,"syslib_copy_file output file not opened")
            if( present(status) ) status = ioerr
            return
        endif
        bytepos = 1
        do ichunk=1,nchunks
            read(in,   pos=bytepos, iostat=ioerr) byte_buffer
            if( ioerr /= 0 ) call simple_stop("simple_syslib::syslib_copy_file failed to read byte buffer ", __FILENAME__,__LINE__)
            write(out, pos=bytepos, iostat=ioerr) byte_buffer
            if( ioerr /= 0 ) call simple_stop("simple_syslib::syslib_copy_file failed to write byte buffer ", __FILENAME__,__LINE__)
            bytepos = bytepos + bufsz
        end do
        ! take care of leftover
        if( leftover > 0 )then
            read(in,   pos=bytepos, iostat=ioerr) byte_buffer(:leftover)
            if( ioerr /= 0 ) call simple_stop("simple_syslib::syslib_copy_file failed to read byte buffer ", __FILENAME__,__LINE__)
            write(out, pos=bytepos, iostat=ioerr) byte_buffer(:leftover)
            if( ioerr /= 0 ) call simple_stop("simple_syslib::syslib_copy_file failed to write byte buffer ", __FILENAME__,__LINE__)
        endif
        close(in)
        close(out)
    end subroutine syslib_copy_file

    !> \brief  Rename or move file
    function simple_rename( filein, fileout , overwrite, errmsg ) result(file_status)
        character(len=*), intent(in)  :: filein, fileout !< input filename
        logical, intent(in), optional :: overwrite      !< default true
        character(len=*), intent(in), optional  :: errmsg !< message
        integer                       :: file_status
        logical                       :: force_overwrite
        character(kind=c_char, len=:), allocatable :: f1, f2
        character(len=:), allocatable :: msg, errormsg
        force_overwrite=.true.
        if(present(overwrite)) force_overwrite=overwrite
        if( file_exists(trim(fileout)) .and. (force_overwrite) )&
            call del_file(trim(fileout))
        if (present(errmsg))then
            allocate(errormsg,source=". Message: "//trim(errmsg))
        else
            allocate(errormsg,source=". ")
        end if
        if( file_exists(filein) )then
            allocate(msg,source="simple_rename failed to rename file "//trim(filein)//trim(errormsg))
            allocate(f1, source=trim(adjustl(filein))//achar(0))
            allocate(f2, source=trim(adjustl(fileout))//achar(0))
            file_status = rename(trim(f1), trim(f2))
            if(file_status /= 0)&
                call simple_error_check(file_status,trim(msg))
            deallocate(f1,f2,msg)
        else
            call simple_stop("simple_fileio::simple_rename, designated input filename doesn't exist "//&
                trim(filein)//trim(errormsg),__FILENAME__,__LINE__)
        end if
        deallocate(errormsg)
    end function simple_rename

    function simple_chmod(pathname, mode ) result( status )
        character(len=*), intent(in) :: pathname, mode
        integer :: status, imode
#if defined(INTEL)
        ! Function method
        status = chmod(pathname, mode)
#else
        imode = INT(o'000') ! convert symbolic to octal
        if ( index(mode, 'x') /=0) imode=IOR(imode,INT(o'111'))
        if ( index(mode, 'w') /=0) imode=IOR(imode,INT(o'222'))
        if ( index(mode, 'r') /=0) imode=IOR(imode,INT(o'444'))
        status = chmod(pathname, mode) !! intrinsic GNU
#endif
        if(status/=0)&
            call simple_error_check(status,"simple_syslib::simple_chmod chmod failed "//trim(pathname))
    end function simple_chmod

    !>  Wrapper for POSIX system call stat
    subroutine simple_file_stat( filename, status, buffer, doprint )
#if defined(INTEL)
        use ifposix
#endif
        character(len=*),     intent(in)    :: filename
        integer,              intent(inout) :: status
        integer, allocatable, intent(inout) :: buffer(:)  !< POSIX stat struct
        logical, optional,    intent(in)    :: doprint
        logical :: l_print = .true., currently_opened=.false.
        integer :: funit
        character(len=STDLEN) :: io_message
#if defined(GNU)
        allocate(buffer(13), source=0)
        status = stat(trim(adjustl(filename)), buffer)
#elif defined(INTEL)
        inquire(file=trim(adjustl(filename)), opened=currently_opened, iostat=status)
        if(status /= 0)&
            call simple_error_check(status,"simple_syslib::simple_sys_stat inquire failed "//trim(filename))
        if(.not.currently_opened) open(newunit=funit,file=trim(adjustl(filename)),status='old')
        !allocate(buffer(13), source=0)
        status = STAT (trim(adjustl(filename)) , buffer)
        if (.NOT. status) then
            call simple_error_check(status, "In simple_syslib::simple_file_stat "//trim(filename))
            print *, buffer
        end if
        if(.not.currently_opened) close(funit)
#endif
        if( present(doprint) )l_print = doprint
        if( l_print )then
            write(*,*) 'command: stat ', trim(adjustl(filename))
            write(*,*) 'status of execution: ', status
        endif
    end subroutine simple_file_stat

    logical function is_io(unit)
        integer, intent(in) :: unit
        is_io=.false.
        if (unit == stderr .or. unit == stdout .or. unit == stdin) is_io= .true.
    end function is_io

    !>  \brief  check whether a IO unit is currently opened
    logical function is_open( unit_number )
        integer, intent(in)   :: unit_number
        integer               :: io_status
        character(len=STDLEN) :: io_message
        io_status = 0
        inquire(unit=unit_number, opened=is_open,iostat=io_status,iomsg=io_message)
        if (io_status .ne. 0) then
            print *, 'is_open: IO error ', io_status, ': ', trim(adjustl(io_message))
            call simple_stop ('IO error; is_open; simple_fileio      ',__FILENAME__,__LINE__)
        endif
    end function is_open

    !>  \brief  check if a file exists on disk
    !! return logical true=dir exists, false=dir does not exist
    logical function dir_exists( dname )
        character(len=*), intent(in) :: dname
        integer :: status
        integer, allocatable :: buffer(:)
        character(kind=c_char, len=:), allocatable :: d1
        dir_exists=.false.
        !        inquire(file=trim(adjustl(dname)), exist = dir_exists)
        allocate(d1,source=trim(adjustl(dname))//achar(0))
        status = isdir(trim(d1), len_trim(d1))
        deallocate(d1)
        print *," Status ", status
        if (status == 1) then
            dir_exists = .true.
            !            print *, " isdir status ", status
           call simple_file_stat( trim(adjustl(dname)), status, buffer, .true. )
           if(global_debug)then
                print *, " status ", status
                print *, " file mode ", buffer(3)
                print *, " last modified ", buffer(10)
            endif
        endif
    end function dir_exists

    !>  \brief  check if a file exists on disk
    !! return logical true=FILE exists, false=FILE does not exist
    logical function file_exists( fname )
        character(len=*), intent(in) :: fname
        inquire(file=trim(adjustl(fname)), exist = file_exists)
    end function file_exists

    !>  \brief  check whether a file is currently opened
    logical function is_file_open( fname )
        character(len=*), intent(in)  :: fname
        integer               :: io_status
        character(len=STDLEN) :: io_message
        io_status = 0
        inquire(file=fname, opened=is_file_open,iostat=io_status,iomsg=io_message)
        if (io_status .ne. 0) then
            print *, 'is_open: IO error ', io_status, ': ', trim(adjustl(io_message))
            stop 'IO error; is_file_open; simple_fileio      '
        endif
    end function is_file_open

    !>  \brief  waits for file to be closed
    subroutine wait_for_closure( fname )
        character(len=*), intent(in)  :: fname
        logical :: exists, closed
        integer :: wait_time
        wait_time = 0
        do
            if( wait_time == 60 )then
                write(*,'(A,A)')'>>> WARNING: been waiting for a minute for file: ',trim(adjustl(fname))
                wait_time = 0
                flush(stdout)
            endif
            exists = file_exists(fname)
            closed = .false.
            if( exists )closed = .not. is_file_open(fname)
            if( exists .and. closed )exit
            call simple_sleep(1)
            wait_time = wait_time + 1
        enddo
    end subroutine wait_for_closure

    !> \brief  Get current working directory
    subroutine simple_getcwd( cwd )
        character(len=*), intent(inout) :: cwd   !< output pathname
        integer :: io_status
        io_status = getcwd(cwd)
        if(io_status /= 0) call simple_error_check(io_status, &
            "syslib:: simple_getcwd failed to get path "//trim(cwd))
    end subroutine simple_getcwd

    !> \brief  Change working directory
    !! return optional status 0=success
    subroutine simple_chdir( newd, oldd, status )
        character(len=*),           intent(in)  :: newd   !< output pathname
        character(len=*), optional, intent(out) :: oldd
        integer,          optional, intent(out) :: status
        character(len=STDLEN)                   :: olddir
        integer :: io_status
        logical :: dir_e, qq
        if(present(status)) status = 1
        if(present(oldd))then
            call simple_getcwd(olddir)
            oldd = trim(olddir)
        endif
        inquire(file=newd, exist=dir_e)
        if(dir_e) then
#ifdef INTEL
            if( changedirqq(trim(newd)) .eqv. .false.) call simple_error_check(io_status, &
                "syslib:: changedirqq failed  "//trim(newd))
#else
            io_status = chdir(newd)
#endif
            if(io_status /= 0) call simple_error_check(io_status, &
                "syslib:: simple_chdir failed to change path "//trim(newd))
        else
            call simple_stop("syslib:: simple_chdir directory does not exist ",__FILENAME__,__LINE__)
        endif
        if(present(status)) status = io_status
    end subroutine simple_chdir

    !> \brief  Make directory -- fail when ignore is false
    !! return optional status 0=success
    subroutine simple_mkdir( dir, ignore, status)
        character(len=*), intent(in)            :: dir
        logical,          intent(in), optional  :: ignore
        integer,          intent(out), optional :: status
        character(kind=c_char, len=:), allocatable :: path
        integer :: io_status, idir, ndirs, lenstr
        logical :: dir_e, ignore_here,  dir_p, qq
        ignore_here = .false.
        io_status=0
        inquire(file=trim(dir), exist=dir_e)
        if(.not. dir_e) then
            allocate(path, source=trim(adjustl(dir))//c_null_char)
#ifdef INTEL
            if(makedirqq(trim(path)) .eqv. .false.) call simple_error_check(io_status, &
                    "syslib:: makedirqq failed creating "//trim(path))
#else
            io_status = makedir(trim(path))

#endif
            inquire(file=trim(path), exist=dir_e)
            if(.not. dir_e) then
                print *," syslib:: simple_mkdir failed to create "//trim(path)
            endif
            if(.not. ignore_here)then
                if(io_status /= 0) call simple_error_check(io_status, &
                    "syslib:: simple_mkdir failed to create "//trim(path))
            endif
            deallocate(path)
        else
            if(global_verbose) print *," Directory ", trim(dir), " already exists, simple_mkdir ignoring request"
        end if
        if(present(status)) status = io_status
    end subroutine simple_mkdir

    !> \brief  Remove directory
    !! status 0=success
    subroutine simple_rmdir( d , status)
        character(len=*), intent(in)              :: d
        integer,          intent(out), optional   :: status
        character(kind=c_char,len=:), allocatable :: path
        integer                                   :: io_status
        logical                                   :: dir_e
        integer :: err, length, count
        logical(4) qq
        character(len=100) :: msg
        io_status=0
        inquire(file=trim(adjustl(d)), exist=dir_e)
        if(dir_e) then
            count=0
            allocate(path, source=trim(adjustl(d))//c_null_char)
            length = len_trim(adjustl(path))
#ifdef INTEL
            if( deldirqq(trim(path)).eqv. .false.) call simple_error_check(io_status, &
                    "syslib:: deldirqq failed  "//trim(path))
#else
            io_status = removedir(trim(path), length, count)
#endif
            if(global_debug) print *,' simple_rmdir removed ', count, ' items'
            deallocate(path)
            if(io_status /= 0)then
                err = int( IERRNO(), kind=4 ) !!  EXTERNAL;  no implicit type in INTEL
                call simple_error_check(io_status, "syslib:: simple_rmdir failed to remove "//trim(d))
                io_status=0
            endif
        else
            print *," Directory ", d, " does not exists, simple_rmdir ignoring request"
        end if
        if(present(status)) status = io_status
    end subroutine simple_rmdir

    function simple_list_dirs(path, outfile, status) result(list)
        character(len=*),           intent(in)  :: path
        character(len=*), optional, intent(in)  :: outfile
        integer,          optional, intent(out) :: status
        character(len=STDLEN), allocatable      :: list(:)
        character(len=STDLEN)                   :: cur
        character(kind=c_char,len=:), allocatable :: pathhere
        integer :: stat, i,num_dirs, luntmp
        allocate(pathhere, source=trim(adjustl(path))//c_null_char)
        stat = list_dirs(trim(pathhere), num_dirs)
        if(stat/=0)call simple_stop("simple_syslib::simple_list_dirs failed to process list_dirs "//trim(pathhere),&
            __FILENAME__,__LINE__)
        if(present(outfile)) call syslib_copy_file('__simple_filelist__', trim(outfile))
        open(newunit = luntmp, file = '__simple_filelist__')
        allocate( list(num_dirs) )
        do i = 1,num_dirs
            read( luntmp, '(a)' ) list(i)
        enddo
        close( luntmp, status = 'delete' )
        deallocate(pathhere)
        if(present(status)) status= stat
    end function simple_list_dirs

    function find_next_int_dir_prefix( dir2list ) result( next_int_dir_prefix )
        use simple_strings, only: char_is_a_number, map_str_nrs, str2int
        character(len=*), intent(in)       :: dir2list
        character(len=STDLEN)              :: str
        character(len=STDLEN), allocatable :: dirs(:)
        logical,               allocatable :: nrmap(:)
        integer,               allocatable :: dirinds(:)
        integer :: i, j, last_nr_ind, io_stat, ivar
        integer :: next_int_dir_prefix, ndirs
        dirs  = simple_list_dirs(dir2list)
        if( allocated(dirs) )then
            ndirs = size(dirs)
        else
            next_int_dir_prefix = 1
            return
        endif
        allocate(dirinds(ndirs), source=0)
        do i=1,ndirs
            str = trim(dirs(i))
            if( char_is_a_number(str(1:1)) )then
                nrmap = map_str_nrs(trim(str))
                do j=1,size(nrmap)
                    if( nrmap(j) )then
                        last_nr_ind = j
                    else
                        exit
                    endif
                enddo
                call str2int(str(1:last_nr_ind), io_stat, dirinds(i))
            endif
        end do
        if( any(dirinds > 0) )then
            next_int_dir_prefix =  maxval(dirinds) + 1
        else
            next_int_dir_prefix = 1
        endif
    end function find_next_int_dir_prefix

    subroutine simple_list_files( pattern, list, id )
        use simple_strings, only: int2str
        character(len=*),                       intent(in)    :: pattern
        character(len=LONGSTRLEN), allocatable, intent(inout) :: list(:)
        integer,                   optional,    intent(in)    :: id
        character(len=STDLEN)     :: cmd
        character(len=LONGSTRLEN) :: tmpfile
        character(len=1) :: junk
        integer :: sz, funit, ios, i, nlines
        if( present(id) )then
            tmpfile = '__simple_filelist_'//int2str(id)//'__'
        else
            tmpfile = '__simple_filelist__'
        endif
        cmd     = 'ls '//trim(pattern)//' > '//trim(tmpfile)
        call exec_cmdline( cmd, suppress_errors=.true.)
        inquire(file=trim(tmpfile), size=sz)
        if( allocated(list) ) deallocate(list)
        if( sz > 0 )then
            open(newunit=funit, file=trim(tmpfile))
            nlines = 0
            do
                read(funit,*,iostat=ios) junk
                if(ios /= 0)then
                    exit
                else
                    nlines = nlines + 1
                endif
            end do
            rewind(funit)
            allocate( list(nlines) )
            do i=1,nlines
                read(funit, '(a)') list(i)
            enddo
            close(funit, status='delete')
        else
            open(newunit=funit, file=trim(tmpfile))
            close(funit, status='delete')
        endif
    end subroutine simple_list_files

    !> Glob list : Emulate ls "glob" > outfile
    !!    iostat = glob_list_tofile('dir/*tmp*.txt', 'out.txt')
    function simple_glob_list_tofile(glob, outfile, tr) result(status)
        character(len=*), intent(in)           :: glob
        character(len=*), intent(in)           :: outfile
        logical,          intent(in), optional :: tr !> "ls -tr " reverse time-modified flag
        character(kind=c_char,len=:), allocatable :: thisglob
        character(1) :: sep='/'
        integer      :: status
        type(c_ptr)  :: file_list_ptr
        integer      :: i,num_files, luntmp, time_sorted_flag
        time_sorted_flag = 0
        status=0
        if(len(glob)==0) then
            allocate(thisglob, source=trim(glob)//achar(0))
        else
            allocate(thisglob, source='*'//achar(0))
        end if
        time_sorted_flag = 0
        if(present(tr))then
            if(tr) time_sorted_flag = 1
        end if
        if(global_debug) print *, 'Calling  glob_file_list ', trim(thisglob)
        status = glob_file_list(trim(thisglob), num_files, time_sorted_flag)
        if(status/=0)call simple_stop("simple_syslib::simple_glob_list_files failed to process file list "//&
            &trim(thisglob),__FILENAME__,__LINE__)
        if(global_debug) print *, ' In simple_syslib::simple_glob_list_tofile  outfile : ', outfile
        if(file_exists(trim(outfile))) call del_file(trim(outfile))
        call syslib_copy_file(trim('__simple_filelist__'), trim(outfile), status)
        if(status/=0) call simple_stop("simple_syslib::simple_glob_list_files failed to copy tmpfile to "//&
            &trim(outfile),__FILENAME__,__LINE__)
        deallocate(thisglob)
    end function simple_glob_list_tofile

    !> \brief  is for deleting a file
    subroutine del_file( file )
        character(len=*), intent(in) :: file !< input filename
        integer :: fnr, file_status
        if( file_exists(file) )then
            open(newunit=fnr,file=file,STATUS='OLD',IOSTAT=file_status)
            if( file_status == 0 )then
                close(fnr, status='delete',IOSTAT=file_status)
                if(file_status /=0) call simple_stop("simple_syslib::del_file failed to close file "//&
                    &trim(file),__FILENAME__,__LINE__)
            end if
        endif
    end subroutine del_file

    !> generic deletion of files using POSIX glob, emulate rm -f glob
    function simple_del_files(glob, dlist, status) result(glob_elems)
        character(len=*), intent(in), optional   :: glob
        character(len=:), allocatable, intent(out), optional  :: dlist(:)
        integer,          intent(out), optional  :: status
        type(c_ptr)                                :: listptr
        character(kind=c_char,len=STDLEN), pointer :: list(:)
        character(len=STDLEN)                      :: cur
        character(kind=c_char,len=:), allocatable  :: thisglob
        integer                                    :: i, glob_elems,iostatus, luntmp
        if(present(glob))then
            thisglob=trim(glob)//c_null_char
        else
            thisglob='*'//c_null_char
        endif
        !! glob must be protected by c_null char
        iostatus =  glob_file_list(trim(thisglob), glob_elems, 0)  ! simple_posix.c
        if(status/=0) call simple_stop("simple_syslib::simple_del_files glob failed",__FILENAME__,__LINE__)
        !! Read temp filelist
        open(newunit=luntmp, file='__simple_filelist__')
        allocate( list(glob_elems) )
        do i = 1,glob_elems
            read( luntmp, '(a)' ) list(i)
        enddo
        close( luntmp, status='delete' )
        !! delete and double check
        if ( glob_elems > 0) then
            do i=1,glob_elems
                call del_file(list(i))
            enddo
            do i=1,glob_elems
                if(file_exists(list(i))) call simple_stop(" simple_del_files failed to delete "//&
                    &trim(list(i)),__FILENAME__,__LINE__)
            enddo
        else
            print *,"simple_syslib::simple_del_files no files matching ", trim(thisglob)
        endif
        if(present(dlist)) then
            allocate(dlist(glob_elems), source=list)
            do i=1,glob_elems
                dlist(i)= list(i)
            end do
        end if
        if(present(status))status=iostatus
        deallocate(list)
        deallocate(thisglob)
    end function simple_del_files

    !> forced deletion of dirs and files using POSIX glob -- rm -rf glob
    !! No return of number of deleted files or list
    !! call syslib_rm("tmpdir*/tmp*.ext",  status=stat)
    subroutine syslib_rm_rf(glob,  status)
        character(len=*), intent(in), optional     :: glob
        integer,          intent(out), optional    :: status
        character(kind=c_char,len=STDLEN), pointer :: list(:)
        character(len=STDLEN)                      :: cur
        character(kind=c_char,len=:), allocatable  :: thisglob
        type(c_ptr)                                :: listptr
        integer                                    :: i, glob_elems,iostatus, luntmp
        if(present(glob))then
            allocate(thisglob, source=trim(glob)//c_null_char)
        else
            allocate(thisglob, source='./*'//c_null_char)
        endif
        call del_file('__simple_filelist__')
        !! glob must be protected by c_null char
        iostatus =  glob_rm_all(trim(thisglob), glob_elems)  ! simple_posix.c
        if(iostatus/=0) call simple_stop("simple_syslib::simple_rm_force glob failed")
        open(newunit = luntmp, file = '__simple_filelist__')
        allocate( list(glob_elems) )
        do i = 1,glob_elems
            read( luntmp, '(a)' , iostat=iostatus) list(i)
            if(iostatus/=0) call simple_stop("simple_syslib::simple_rm_force reading temp file failed")
        enddo
        close( luntmp, status = 'delete' )
        if ( glob_elems > 0) then
            do i=1, glob_elems
                if(file_exists(list(i))) then
                    print *, " failed to delete "//trim(list(i))
                    call simple_stop(" simple_syslib::simple_rm_force ",__FILENAME__,__LINE__)
                end if
            enddo
        else
            print *,"simple_syslib::syslib_rm_rf no files matching ", trim(thisglob)
        endif
        if(present(status))status=iostatus
        deallocate(thisglob)
    end subroutine syslib_rm_rf

    !> forced deletion of dirs and files using POSIX glob -- rm -rf glob
    !! num_deleted = simple_rm_force("tmpdir*/tmp*.ext", dlist=list_of_deleted_elements, status=stat)
    function simple_rm_force(glob, dlist, status) result(glob_elems)
        character(len=*), intent(in), optional     :: glob
        character(len=:), allocatable, intent(out), optional    :: dlist(:)
        integer,          intent(out), optional    :: status
        character(kind=c_char,len=STDLEN), pointer :: list(:)
        character(len=STDLEN)                      :: cur
        character(kind=c_char,len=:), allocatable  :: thisglob
        type(c_ptr)                                :: listptr
        integer                                    :: i, glob_elems,iostatus, luntmp
        if(present(glob))then
            allocate(thisglob, source=trim(glob)//c_null_char)
        else
            allocate(thisglob, source='*'//c_null_char)
        endif
        call del_file('__simple_filelist__')
        !! glob must be protected by c_null char
        iostatus =  glob_rm_all(trim(thisglob), glob_elems)  ! simple_posix.c
        if(iostatus/=0) call simple_stop("simple_syslib::simple_rm_force glob failed")
        open(newunit = luntmp, file = '__simple_filelist__')
        allocate( list(glob_elems) )
        do i = 1,glob_elems
            read( luntmp, '(a)' , iostat=iostatus) list(i)
            if(iostatus/=0) call simple_stop("simple_syslib::simple_rm_force reading temp file failed")
        enddo
        close( luntmp, status = 'delete' )
        if ( glob_elems > 0) then
            do i=1, glob_elems
                if(file_exists(list(i))) then
                    print *, " failed to delete "//trim(list(i))
                    call simple_stop(" simple_syslib::simple_rm_force ",__FILENAME__,__LINE__)
                end if
            enddo
        else
            print *,"simple_syslib::simple_rm_force no files matching ", trim(thisglob)
        endif
        if(present(dlist)) then
           allocate( dlist(glob_elems), source=list)
        else
           deallocate(list)
        end if
        if(present(status))status=iostatus
        deallocate(thisglob)
    end function simple_rm_force

    !> simple_timestamp prints time stamp (based on John Burkardt's website code)
    subroutine simple_timestamp ( )
        character(len= 8) :: ampm
        integer (kind=sp) :: d
        integer (kind=sp) :: h
        integer (kind=sp) :: m
        integer (kind=sp) :: mm
        character (len=9 ), parameter, dimension(12) :: month = (/ &
            'January  ', 'February ', 'March    ', 'April    ', &
            'May      ', 'June     ', 'July     ', 'August   ', &
            'September', 'October  ', 'November ', 'December ' /)
        integer    :: n, s, y, values(8)

        call date_and_time(values=values)
        y = values(1)
        m = values(2)
        d = values(3)
        h = values(5)
        n = values(6)
        s = values(7)
        mm = values(8)
        if ( h < 12 ) then
            ampm = 'AM'
        else if ( h == 12 ) then
            if ( n == 0 .and. s == 0 ) then
                ampm = 'Noon'
            else
                ampm = 'PM'
            end if
        else
            h = h - 12
            if ( h < 12 ) then
                ampm = 'PM'
            else if ( h == 12 ) then
                if ( n == 0 .and. s == 0 ) then
                    ampm = 'Midnight'
                else
                    ampm = 'AM'
                end if
            end if
        end if
        write ( *, '(i2.2,1x,a,1x,i4,2x,i2,a1,i2.2,a1,i2.2,a1,i3.3,1x,a)' ) &
            d, trim ( month(m) ), y, h, ':', n, ':', s, '.', mm, trim ( ampm )
    end subroutine simple_timestamp

    function cpu_usage ()
        real    :: cpu_usage
        integer :: ios, i
        integer :: unit,oldidle, oldsum, sumtimes
        real    :: percent
        character(len = 4) lineID ! 'cpu '
        integer, dimension(9) :: times
        cpu_usage=0.0
        sumtimes = 0
        times = 0
        percent = 0.
        write(*,'(a)') 'CPU Usage'
        open(newunit=unit, file = '/proc/stat', status = 'old', action = 'read', iostat = ios)
        if (ios /= 0) then
            print *, 'Error opening /proc/stat'
            stop
        else
            read(unit, fmt = *, iostat = ios) lineID, (times(i), i = 1, 9)
            if (ios /= 0) then
                print *, 'Error reading /proc/stat'
                stop
            end if
            close(unit, iostat = ios)
            if (ios /= 0) then
                print *, 'Error closing /proc/stat'
                stop
            end if
            if (lineID /= 'cpu ') then
                print *, 'Error reading /proc/stat'
                stop
            end if
            sumtimes = sum(times)
            percent = (1. - real((times(4) - oldidle)) / real((sumtimes - oldsum))) * 100.
            write(*, fmt = '(F6.2,A2)') percent, '%'
            oldidle = times(4)
            oldsum = sumtimes
        end if
        cpu_usage=percent
    end function cpu_usage

    !! SYSTEM INFO ROUTINES

    integer function get_process_id( )
        get_process_id = getpid()
    end function get_process_id

    subroutine print_compiler_info(file_unit)
        use simple_strings, only: int2str
#ifdef INTEL
        character*56  :: str
#endif
#ifdef GNU
        character(*), parameter :: compilation_cmd = compiler_options()
        character(*), parameter :: compiler_ver = compiler_version()
#endif
        integer, intent (in), optional :: file_unit
        integer  :: file_unit_op
        integer  :: status
        if (present(file_unit)) then
            file_unit_op = file_unit
        else
            file_unit_op = stdout
        end if
#if defined(GNU)
        write( file_unit_op, '(A,A,A,A)' ) &
            ' This file was compiled by ', trim(adjustl(compiler_ver)), &
            ' using the options ', trim(adjustl(compilation_cmd))
#endif
#ifdef INTEL
        status = for_ifcore_version( str )
        write( file_unit_op, '(A,A)' ) &
            ' Intel IFCORE version ', trim(adjustl(str))
        status = for_ifport_version( str )
        write( file_unit_op, '(A,A)' ) &
            ' Intel IFPORT version ', trim(adjustl(str))
#endif
    end subroutine print_compiler_info

    subroutine simple_sysinfo_usage(valueRSS,valuePeak,valueSize,valueHWM)
        integer(kind=8), intent(out) :: valueRSS
        integer(kind=8), intent(out) :: valuePeak
        integer(kind=8), intent(out) :: valueSize
        integer(kind=8), intent(out) :: valueHWM
        integer :: stat
        integer(c_long) :: HWM, totRAM, shRAM, bufRAM, peakBuf
        stat = get_sysinfo( HWM, totRAM, shRAM, bufRAM, peakBuf)
        if (stat /= 0 ) call simple_stop("simple_sysinfo_usage failed")
        valueRSS = bufRAM
        valuePeak = totRAM
        valueSize = shRAM
        valueHWM = HWM
        if(global_debug)then
            print *," simple_sysinfo_usage :"
            print *," Total usable main memory size (bytes):", valuePeak
            print *," Amount of shared memory:              ", valueSize
            print *," Memory used by buffers:               ", valueRSS
            print *," High water mark:                      ", valueHWM
        endif
    end subroutine simple_sysinfo_usage

    ! Suggestion from https://stackoverflow.com/a/30241280
    subroutine simple_mem_usage(valueRSS,valuePeak,valueSize,valueHWM)
        implicit none
        integer(kind=8), intent(out) :: valueRSS
        integer(kind=8), intent(out), optional :: valuePeak
        integer(kind=8), intent(out), optional :: valueSize
        integer(kind=8), intent(out), optional :: valueHWM
        character(len=200) :: filename=' '
        character(len=80)  :: line
        character(len=8)   :: pid_char=' '
        integer            :: pid,unit
        logical            :: ifxst, debug
        debug=.false.
        valueRSS=-1    ! return negative number if not found
        if(present(valuePeak))valuePeak=-1
        if(present(valueSize))valueSize=-1
        if(present(valueHWM))valueHWM=-1
        !--- get process ID
        pid=getpid()
        write(pid_char,'(I8)') pid
        filename='/proc/'//trim(adjustl(pid_char))//'/status'
        if(debug) print *,'simple_mem_usage:debug:  Fetching ', trim(filename)
        !--- read system file
        inquire (file=trim(filename),exist=ifxst)
        if (.not.ifxst) then
            write (*,*) 'system file does not exist'
            return
        endif
        open(newunit=unit, file=filename, action='read')
        ! the order of the following do loops is dependent on cat /proc/PID/status listing
        if(present(valuePeak))then
            do
                read (unit,'(a)',end=110) line
                if (line(1:7).eq.'VmPeak:') then
                    read (line(8:),*) valuePeak
                    if(debug) print *,'simple_mem_usage:debug:  Peak ', valuePeak
                    exit
                endif
            enddo
110         continue
        endif
        if(present(valueSize))then
            do
                read (unit,'(a)',end=120) line
                if (line(1:7).eq.'VmSize:') then
                    read (line(8:),*) valueSize
                    if(debug) print *,'simple_mem_usage:debug:  VM Size ', valueSize
                    exit
                endif
            enddo
120         continue
        endif
        if(present(valueHWM))then
            do
                read (unit,'(a)',end=130) line
                if (line(1:6).eq.'VmHWM:') then
                    read (line(7:),*) valueHWM
                    if(debug) print *,'simple_mem_usage:debug:  peak RAM ', valueHWM
                    exit
                endif
            enddo
130         continue
        endif
        do
            read (unit,'(a)',end=140) line
            if (line(1:6).eq.'VmRSS:') then
                read (line(7:),*) valueRSS
                if(debug) print *,'simple_mem_usage:debug: RSS ', valueRSS
                exit
            endif
        enddo
140     continue
        close(unit)
        return
    end subroutine simple_mem_usage

    subroutine simple_dump_mem_usage(dump_file)
        character(len=*), intent(inout), optional :: dump_file
        character(len=200)    :: filename=' '
        character(len=80)     :: line
        character(len=8)      :: pid_char=' '
        character(len=STDLEN) :: command
        integer               :: pid,unit
        logical               :: ifxst
#ifdef MACOSX
        print *," simple_dump_mem_usage cannot run on MacOSX"
        return
#endif
        !--- get process ID --  make thread safe
        !  omp critical dump_mem
        pid=getpid()
        write(pid_char,'(I8)') pid
        filename='/proc/'//trim(adjustl(pid_char))//'/status'
        command = 'grep -E "^(VmPeak|VmSize|VmHWM|VmRSS):"<'//trim(filename)//'|awk "{a[NR-1]=\$2}END{print a[0],a[1],a[2],a[3]}" '
!!         | awk {a[NR-1]=$2} END{print a[0],a[1],a[2],a[3]}
        if(present(dump_file)) command = trim(command)//' >> '//trim(dump_file)
        call exec_cmdline(trim(command))
        !  omp end critical
    end subroutine simple_dump_mem_usage

    subroutine simple_full_path (infile, absolute_name, errmsg, check_exists)
        character(len=*),              intent(in)  :: infile, errmsg
        character(len=:), allocatable, intent(out) :: absolute_name
        logical,          optional,    intent(in)  :: check_exists
        type(c_ptr)                                :: cstring
        integer(1),          dimension(:), pointer :: iptr
        character(kind=c_char),            pointer :: fstring(:)
        character(len=LINE_MAX_LEN),       target  :: fstr
        character(kind=c_char,len=STDLEN)          :: infilename_c
        character(kind=c_char,len=LONGSTRLEN)      :: outfilename_c
        integer :: slen, i
        integer :: lengthin, status, lengthout
        logical :: check_exists_here
        check_exists_here = .true.
        if( present(check_exists) )check_exists_here = check_exists
        if( check_exists_here )then
            if( .not.file_exists(trim(infile)) )then
                write(*,*)'File does not exists: ', trim(infile)
                write(*,*)trim(errmsg)
                stop
            endif
        endif
        lengthin     = len_trim(infile)
        cstring      = c_loc(fstr)
        infilename_c = trim(infile)//achar(0)
        status       = get_absolute_pathname(trim(adjustl(infilename_c)), lengthin, outfilename_c, lengthout )
        if(global_debug) print *, " out string ", trim(outfilename_c(1:lengthout))
        if(global_debug) print *, " length outfile  ", lengthout, len_trim(outfilename_c)
        if(allocated(absolute_name)) deallocate(absolute_name)
        if( lengthout > 1)then
           allocate(absolute_name, source=trim(outfilename_c(1:lengthout)))
        else
            allocate(absolute_name, source=trim(infile))
        end if
    end subroutine simple_full_path

end module simple_syslib

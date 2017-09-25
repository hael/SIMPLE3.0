! batch-processing manager - control module

module simple_qsys_ctrl
#include "simple_lib.f08"

use simple_qsys_base,    only: qsys_base
use simple_chash,        only: chash
use simple_cmdline,      only: cmdline


implicit none

public :: qsys_ctrl
private
#include "simple_local_flags.inc"
integer, parameter :: SHORTTIME = 3

type qsys_ctrl
    private
    character(len=STDLEN)          :: exec_binary = ''           !< binary to execute in parallel
                                                                 !< trim(simplepath)//'/bin/simple_exec'
    character(len=32), allocatable :: script_names(:)            !< file names of generated scripts
    character(len=32), allocatable :: jobs_done_fnames(:)        !< touch files indicating completion
    character(len=STDLEN)          :: pwd        = ''            !< working directory
    class(qsys_base), pointer      :: myqsys     => null()       !< pointer to polymorphic qsys object
    integer, pointer               :: parts(:,:) => null()       !< defines the fromp/top ranges for all partitions
    class(cmdline), allocatable    :: cline_stack(:)             !< stack of command lines, for streaming only
    logical, allocatable           :: jobs_done(:)               !< to indicate completion of distributed scripts
    logical, allocatable           :: jobs_submitted(:)          !< to indicate which jobs have been submitted
    integer                        :: fromto_part(2)         = 0 !< defines the range of partitions controlled by this instance
    integer                        :: nparts_tot             = 0 !< total number of partitions
    integer                        :: ncomputing_units       = 0 !< number of computing units
    integer                        :: ncomputing_units_avail = 0 !< number of available units
    integer                        :: numlen                 = 0 !< length of padded number string
    integer                        :: cline_stacksz          = 0 !< size of stack of command lines, for streaming only
    logical                        :: stream    = .false.        !< stream flag
    logical                        :: existence = .false.        !< indicates existence

  contains
    ! CONSTRUCTOR
    procedure          :: new
    ! GETTER
    procedure          :: get_exec_bin
    procedure          :: get_jobs_status
    procedure          :: print_jobs_status
    procedure          :: exists
    ! SETTER
    procedure          :: free_all_cunits
    procedure          :: set_jobs_status
    ! SCRIPT GENERATORS
    procedure          :: generate_scripts
    procedure, private :: generate_script_1
    procedure, private :: generate_script_2
    generic            :: generate_script => generate_script_2
    ! SUBMISSION TO QSYS
    procedure          :: submit_scripts
    procedure          :: submit_script
    ! QUERIES
    procedure          :: update_queue
    ! THE MASTER SCHEDULER
    procedure          :: schedule_jobs
    ! STREAMING
    procedure          :: schedule_streaming
    procedure          :: add_to_streaming
    procedure          :: get_stacksz
    ! DESTRUCTOR
    procedure          :: kill
end type qsys_ctrl

interface qsys_ctrl
    module procedure constructor
end interface qsys_ctrl

contains

    ! CONSTRUCTORS

    !>  \brief  is a constructor
    function constructor( exec_binary, qsys_obj, parts, fromto_part, ncomputing_units, stream ) result( self )
        character(len=*),         intent(in) :: exec_binary      !< the binary that we want to execute in parallel
        class(qsys_base), target, intent(in) :: qsys_obj         !< the object that defines the qeueuing system
        integer,          target, intent(in) :: parts(:,:)       !< defines the start_ptcl/stop_ptcl ranges
        integer,                  intent(in) :: fromto_part(2)   !< defines the range of partitions controlled by this object
        integer,                  intent(in) :: ncomputing_units !< number of computing units (<= the number of parts controlled)
        logical,                  intent(in) :: stream           !< stream flag
        type(qsys_ctrl) :: self
        call self%new(exec_binary, qsys_obj, parts, fromto_part, ncomputing_units, stream )
    end function constructor

    !>  \brief  is a constructor
    subroutine new( self, exec_binary, qsys_obj, parts, fromto_part, ncomputing_units, stream )
        use simple_syslib,       only: simple_getenv
        class(qsys_ctrl),         intent(inout) :: self             !< the instance
        character(len=*),         intent(in)    :: exec_binary      !< the binary that we want to execute in parallel
        class(qsys_base), target, intent(in)    :: qsys_obj         !< the object that defines the qeueuing system
        integer,          target, intent(in)    :: parts(:,:)       !< defines the start_ptcl/stop_ptcl ranges
        integer,                  intent(in)    :: fromto_part(2)   !< defines the range of partitions controlled by this object
        integer,                  intent(in)    :: ncomputing_units !< number of computing units (<= the number of parts controlled)
        logical,                  intent(in)    :: stream           !< stream flag
        integer :: ipart
        call self%kill
        self%stream                 =  stream
        self%exec_binary            =  exec_binary
        self%myqsys                 => qsys_obj
        self%parts                  => parts
        self%fromto_part            =  fromto_part
        self%nparts_tot             =  size(parts,1)
        self%ncomputing_units       =  ncomputing_units
        self%ncomputing_units_avail =  ncomputing_units
        if( self%stream )then
            self%numlen = 5
        else
            self%numlen = len(int2str(self%nparts_tot))
        endif
        ! allocate
        allocate(   self%jobs_done(fromto_part(1):fromto_part(2)),&
                    self%jobs_submitted(fromto_part(1):fromto_part(2)),&
                    self%script_names(fromto_part(1):fromto_part(2)),&
                    self%jobs_done_fnames(fromto_part(1):fromto_part(2)), stat=alloc_stat)
        if(alloc_stat /= 0) allocchk("In: simple_qsys_ctrl :: new")
        if( self%stream )then
            self%jobs_done = .true.
        else
            self%jobs_done = .false.
        endif
        self%jobs_submitted = .false.
        ! create script names
        do ipart=fromto_part(1),fromto_part(2)
            self%script_names(ipart) = 'distr_simple_script_'//int2str_pad(ipart,self%numlen)
        end do
        ! create jobs done flags
        do ipart=self%fromto_part(1),self%fromto_part(2)
            self%jobs_done_fnames(ipart) = 'JOB_FINISHED_'//int2str_pad(ipart,self%numlen)
        end do
        ! get pwd
        self%pwd = trim(adjustl( simple_getenv('PWD') ))
        self%existence = .true.
    end subroutine new

    ! GETTER

    !>  \brief  for getting the execute simple binary
    function get_exec_bin( self ) result( exec_bin )
        class(qsys_ctrl), intent(in) :: self
        character(len=STDLEN)        :: exec_bin
        exec_bin = self%exec_binary
    end function get_exec_bin

    !>  \brief  for getting jobs status logical flags
    subroutine get_jobs_status( self, jobs_done, jobs_submitted )
        class(qsys_ctrl), intent(in) :: self
        logical, allocatable :: jobs_done(:), jobs_submitted(:)
        if( allocated(jobs_done) )      deallocate(jobs_done)
        if( allocated(jobs_submitted) ) deallocate(jobs_submitted)
        allocate(jobs_done(size(self%jobs_done)), source=self%jobs_done)
        allocate(jobs_submitted(size(self%jobs_submitted)), source=self%jobs_submitted)
    end subroutine get_jobs_status

    !>  \brief  for printing jobs status logical flags
    subroutine print_jobs_status( self )
        class(qsys_ctrl), intent(in) :: self
        integer :: i
        do i=1,size(self%jobs_submitted)
            print *, i, 'submitted: ', self%jobs_submitted(i), 'done: ', self%jobs_done(i)
        end do
    end subroutine print_jobs_status

    !>  \brief  for checking existence
    logical function exists( self )
        class(qsys_ctrl), intent(in) :: self
        exists = self%existence
    end function exists

    ! SETTERS

    !> \brief for freeing all available computing units
    subroutine free_all_cunits( self )
        class(qsys_ctrl), intent(inout) :: self
        self%ncomputing_units_avail = self%ncomputing_units
    end subroutine free_all_cunits

    !>  \brief  for setting jobs status logical flags
    subroutine set_jobs_status( self, jobs_done, jobs_submitted )
        class(qsys_ctrl), intent(inout) :: self
        logical,          intent(in)    :: jobs_done(:), jobs_submitted(:)
        self%jobs_done(:size(jobs_done)) = jobs_done
        self%jobs_submitted(:size(jobs_submitted)) = jobs_submitted
    end subroutine set_jobs_status

    ! SCRIPT GENERATORS

    !>  \brief  public script generator
    subroutine generate_scripts( self, job_descr, ext, q_descr, outfile_body, outfile_ext, part_params, chunkdistr )
        class(qsys_ctrl),           intent(inout) :: self
        class(chash),               intent(inout) :: job_descr
        character(len=4),           intent(in)    :: ext
        class(chash),               intent(in)    :: q_descr
        character(len=*), optional, intent(in)    :: outfile_body
        character(len=4), optional, intent(in)    :: outfile_ext
        class(chash),     optional, intent(in)    :: part_params(:)
        logical,          optional, intent(in)    :: chunkdistr
        character(len=:), allocatable :: outfile_body_local, key, val
        integer :: ipart, iadd
        logical :: part_params_present, cchunkdistr
        cchunkdistr = .false.
        if( present(chunkdistr) ) cchunkdistr = .true.
        if( present(outfile_body) )then
            allocate(outfile_body_local, source=trim(outfile_body))
        endif
        part_params_present = present(part_params)
        do ipart=self%fromto_part(1),self%fromto_part(2)
            if( cchunkdistr )then
                ! don't input part-dependent parameters
            else
                call job_descr%set('fromp',   int2str(self%parts(ipart,1)))
                call job_descr%set('top',     int2str(self%parts(ipart,2)))
                call job_descr%set('part',    int2str(ipart))
                call job_descr%set('nparts',  int2str(self%nparts_tot))
                if( allocated(outfile_body_local) )then
                    if( present(outfile_ext) )then
                        call job_descr%set('outfile', trim(trim(outfile_body_local)//int2str_pad(ipart,self%numlen)//outfile_ext))
                    else
                        call job_descr%set('outfile', trim(trim(outfile_body_local)//int2str_pad(ipart,self%numlen)//METADATEXT))
                    endif
                endif
            endif
            if( part_params_present  )then
                do iadd=1,part_params(ipart)%size_of_chash()
                    key = part_params(ipart)%get_key(iadd)
                    val = part_params(ipart)%get(iadd)
                    call job_descr%set(key, val)
                end do
            endif
            call self%generate_script_1(job_descr, ipart, q_descr)
        end do
        if( .not. cchunkdistr )then
            call job_descr%delete('fromp')
            call job_descr%delete('top')
            call job_descr%delete('part')
            call job_descr%delete('nparts')
            if( allocated(outfile_body_local) )then
                call job_descr%delete('outfile')
                deallocate(outfile_body_local)
            endif
        endif
        if( part_params_present  )then
            do iadd=1,part_params(1)%size_of_chash()
                key = part_params(1)%get_key(iadd)
                call job_descr%delete(key)
            end do
        endif
        ! when we generate the scripts we also reset the number of available computing units
        if( .not. self%stream ) self%ncomputing_units_avail = self%ncomputing_units
    end subroutine generate_scripts

    !>  \brief  private part script generator
    subroutine generate_script_1( self, job_descr, ipart, q_descr )
        use simple_syslib,       only: wait_for_closure
        class(qsys_ctrl), intent(inout) :: self
        class(chash),     intent(in)    :: job_descr
        integer,          intent(in)    :: ipart
        class(chash),     intent(in)    :: q_descr
        character(len=512) :: io_msg
        integer :: ios, funit
        call fopen(funit, file=self%script_names(ipart), iostat=ios, STATUS='REPLACE', &
            action='WRITE', iomsg=io_msg)
        call fileio_errmsg('simple_qsys_ctrl :: gen_qsys_script; Error when opening file for writing: '&
             //trim(self%script_names(ipart))//' ; '//trim(io_msg),ios )
        ! need to specify shell
        write(funit,'(a)') '#!/bin/bash'
        ! write (run-time polymorphic) instructions to the qsys
        if( q_descr%get('qsys_name').ne.'local' )then
            call self%myqsys%write_instr(q_descr, fhandle=funit)
        else
            call self%myqsys%write_instr(job_descr, fhandle=funit)
        endif
        write(funit,'(a)',advance='yes') 'cd '//trim(self%pwd)
        write(funit,'(a)',advance='yes') ''
        ! compose the command line
        write(funit,'(a)',advance='no') trim(self%exec_binary)//' '//trim(job_descr%chash2str())
        ! direct output
        write(funit,'(a)',advance='yes') ' > OUT'//int2str_pad(ipart,self%numlen)
        ! exit shell when done
        write(funit,'(a)',advance='yes') ''
        write(funit,'(a)',advance='yes') 'exit'
        call fclose(funit, errmsg='simple_qsys_ctrl :: gen_qsys_script; Error when close file: '&
             //trim(self%script_names(ipart)) )
        if( q_descr%get('qsys_name').eq.'local' )then
            ios = simple_chmod(trim(self%script_names(ipart)),'+x')
            if( ios .ne. 0 )then
                write(*,'(a)',advance='no') 'simple_qsys_scripts :: gen_qsys_script; Error'
                write(*,'(a)') 'chmoding submit script'//trim(self%script_names(ipart))
                stop
            endif
        endif
        ! when we generate the script we also unflag jobs_submitted and jobs_done
        self%jobs_done(ipart)      = .false.
        self%jobs_submitted(ipart) = .false.
        call wait_for_closure(self%script_names(ipart))
    end subroutine generate_script_1

    !>  \brief  public script generator for single jobs
    subroutine generate_script_2( self, job_descr, q_descr, exec_bin, script_name, outfile )
        use simple_syslib,       only: wait_for_closure
        class(qsys_ctrl), intent(inout) :: self
        class(chash),     intent(in)    :: job_descr
        class(chash),     intent(in)    :: q_descr
        character(len=*), intent(in)    :: exec_bin, script_name, outfile
        character(len=512) :: io_msg
        integer :: ios, funit
        call fopen(funit, file=script_name, iostat=ios, STATUS='REPLACE', action='WRITE', iomsg=io_msg)
        call fileio_errmsg('simple_qsys_ctrl :: generate_script_2; Error when opening file: '&
                 //trim(script_name)//' ; '//trim(io_msg),ios )
        ! need to specify shell
        write(funit,'(a)') '#!/bin/bash'
        ! write (run-time polymorphic) instructions to the qsys
        if( q_descr%get('qsys_name').ne.'local' )then
            call self%myqsys%write_instr(q_descr, fhandle=funit)
        else
            call self%myqsys%write_instr(job_descr, fhandle=funit)
        endif
        write(funit,'(a)',advance='yes') 'cd '//trim(self%pwd)
        write(funit,'(a)',advance='yes') ''
        ! compose the command line
        write(funit,'(a)',advance='no') trim(exec_bin)//' '//job_descr%chash2str()
        ! direct output
        write(funit,'(a)',advance='yes') ' > '//outfile
        ! exit shell when done
        write(funit,'(a)',advance='yes') ''
        write(funit,'(a)',advance='yes') 'exit'
        call fclose(funit, ios, &
            &errmsg='simple_qsys_ctrl :: generate_script_2; Error when closing file: '&
            &//trim(script_name))
            !!!!!!!!!
        call wait_for_closure(script_name)
        !!!!!!!!!
        if( trim(q_descr%get('qsys_name')).eq.'local' )then
            ios=simple_chmod(trim(script_name),'+x')
            if( ios .ne. 0 )then
                write(*,'(a)',advance='no') 'simple_qsys_ctrl :: generate_script_2; Error'
                write(*,'(a)') 'chmoding submit script'//trim(script_name)
                stop
            end if
        endif
    end subroutine generate_script_2

    ! SUBMISSION TO QSYS

    subroutine submit_scripts( self )
        use simple_qsys_local,   only: qsys_local
        class(qsys_ctrl),  intent(inout) :: self
 !       class(qsys_base),        pointer :: pmyqsys
        character(len=LONGSTRLEN)        :: qsys_cmd
        character(len=STDLEN)            ::  script_name
        integer               :: ipart
        logical               :: submit_or_not(self%fromto_part(1):self%fromto_part(2))
        ! make a submission mask
        submit_or_not = .false.
        do ipart=self%fromto_part(1),self%fromto_part(2)
            if( self%jobs_submitted(ipart) )then
                ! do nothing
                cycle
            endif
            if( self%ncomputing_units_avail > 0 )then
                submit_or_not(ipart) = .true.
                ! flag job submitted
                self%jobs_submitted(ipart) = .true.
                ! decrement ncomputing_units_avail
                self%ncomputing_units_avail = self%ncomputing_units_avail - 1
            endif
        end do
        if( .not. any(submit_or_not) ) return
        ! on the fly submission
        do ipart=self%fromto_part(1),self%fromto_part(2)
            if( submit_or_not(ipart) )then
                script_name = trim(adjustl(self%script_names(ipart)))
                !!!!!!!!!!!
                if( .not.file_exists('./'//trim(script_name)))then
                    write(*,'(A,A)')'FILE DOES NOT EXIST:',trim(script_name)
                endif
                !!!!!!!!!!!!
                select type( pmyqsys => self%myqsys )
                    class is(qsys_local)
                        qsys_cmd = trim(adjustl(self%myqsys%submit_cmd()))//' ./'//trim(adjustl(script_name))//' &'
                    class DEFAULT
                        qsys_cmd = trim(adjustl(self%myqsys%submit_cmd()))//' ./'//trim(adjustl(script_name))
                end select
                call exec_cmdline(trim(adjustl(qsys_cmd)))
            endif
        end do
    end subroutine submit_scripts

    subroutine submit_script( self, script_name )
        use simple_qsys_local,   only: qsys_local
        class(qsys_ctrl), intent(inout) :: self
        character(len=*), intent(in)    :: script_name
        character(len=STDLEN) :: cmd
        !!!!!!!!!!!
        if( .not.file_exists('./'//trim(script_name)))then
            write(*,'(A,A)')'FILE DOES NOT EXIST:',trim(script_name)
        endif
        !!!!!!!!!!!!
        select type( pmyqsys => self%myqsys )
            class is(qsys_local)
                cmd = trim(adjustl(self%myqsys%submit_cmd()))//' '//trim(adjustl(self%pwd))&
                &//'/'//trim(adjustl(script_name))//' &'
            class DEFAULT
                cmd = trim(adjustl(self%myqsys%submit_cmd()))//' '//trim(adjustl(self%pwd))&
                &//'/'//trim(adjustl(script_name))
        end select
        ! execute the command
        call exec_cmdline(trim(cmd))
    end subroutine submit_script

    ! QUERIES

    subroutine update_queue( self )
        class(qsys_ctrl),  intent(inout) :: self
        integer :: ipart, njobs_in_queue
        do ipart=self%fromto_part(1),self%fromto_part(2)
            if( .not. self%jobs_done(ipart) )then
                self%jobs_done(ipart) = file_exists(self%jobs_done_fnames(ipart))
            endif
            if( self%stream )then
                ! all done
            else
                if( self%jobs_done(ipart) )self%jobs_submitted(ipart) = .true.
            endif
        end do
        if( self%stream )then
            self%ncomputing_units_avail = min(count(self%jobs_done), self%ncomputing_units)
        else
            njobs_in_queue = count(self%jobs_submitted .eqv. (.not.self%jobs_done))
            self%ncomputing_units_avail = self%ncomputing_units - njobs_in_queue
        endif
    end subroutine update_queue

    ! THE MASTER SCHEDULER

    subroutine schedule_jobs( self )
        use simple_syslib, only: simple_sleep
        class(qsys_ctrl),  intent(inout) :: self
        do
            if( all(self%jobs_done) ) exit
            call self%update_queue
            call self%submit_scripts
            call simple_sleep(SHORTTIME)
        end do
    end subroutine schedule_jobs

    ! STREAMING

    subroutine schedule_streaming( self, q_descr )
        class(qsys_ctrl),  intent(inout) :: self
        class(chash),      intent(in)    :: q_descr
        type(cmdline)         :: cline
        type(chash)           :: job_descr
        character(len=STDLEN) :: outfile, script_name
        integer               :: ipart
        call self%update_queue
        if( self%cline_stacksz .eq. 0 )return
        if( self%ncomputing_units_avail > 0 )then
            do ipart = 1, self%ncomputing_units
                if( self%cline_stacksz .eq. 0 )exit
                if( self%jobs_done(ipart) )then
                    cline = self%cline_stack(1)
                    call updatestack
                    call cline%set('part', real(ipart)) ! computing unit allocation
                    call cline%gen_job_descr(job_descr)
                    script_name = self%script_names(ipart)
                    outfile     = 'OUT' // int2str_pad(ipart, self%numlen)
                    self%jobs_submitted(ipart) = .true.
                    self%jobs_done(ipart)      = .false.
                    call del_file(self%jobs_done_fnames(ipart))
                    call self%generate_script_2(job_descr, q_descr, self%exec_binary, script_name, outfile)
                    call self%submit_script( script_name )
                endif
            enddo
        endif

        contains

            ! move everything up so '1' is index for next job
            subroutine updatestack
                type(cmdline), allocatable :: tmp_stack(:)
                integer :: i
                if( self%cline_stacksz > 1 )then
                    tmp_stack = self%cline_stack(2:)
                    self%cline_stacksz = self%cline_stacksz-1
                    deallocate(self%cline_stack)
                    allocate(self%cline_stack(self%cline_stacksz))
                    do i = 1, self%cline_stacksz
                        self%cline_stack(i) = tmp_stack(i)
                    enddo
                    deallocate(tmp_stack)
                else
                    deallocate(self%cline_stack)
                    self%cline_stacksz = 0
                endif
            end subroutine updatestack

    end subroutine schedule_streaming

    !>  \brief  is to append to the streaming command-line stack
    subroutine add_to_streaming( self, cline )
        class(qsys_ctrl),  intent(inout) :: self
        class(cmdline),    intent(in)    :: cline
        type(cmdline), allocatable :: tmp_stack(:)
        integer :: i
        if( .not. allocated(self%cline_stack) )then
            ! empty stack
            allocate( self%cline_stack(1) )
            self%cline_stack(1) = cline
            self%cline_stacksz  = 1
        else
            ! append
            tmp_stack = self%cline_stack
            deallocate(self%cline_stack)
            self%cline_stacksz = self%cline_stacksz + 1
            allocate( self%cline_stack(self%cline_stacksz) )
            do i = 1, self%cline_stacksz-1
                self%cline_stack(i) = tmp_stack(i)
            enddo
            self%cline_stack(self%cline_stacksz) = cline
        endif
    end subroutine add_to_streaming

    integer function get_stacksz( self )
        class(qsys_ctrl), intent(inout) :: self
        get_stacksz = self%cline_stacksz
    end function get_stacksz

    ! DESTRUCTOR

    !>  \brief  is a destructor
    subroutine kill( self )
        class(qsys_ctrl), intent(inout) :: self
        if( self%existence )then
            self%exec_binary            =  ''
            self%pwd                    =  ''
            self%myqsys                 => null()
            self%parts                  => null()
            self%fromto_part(2)         =  0
            self%ncomputing_units       =  0
            self%ncomputing_units_avail =  0
            self%numlen                 =  0
            self%cline_stacksz          =  0
            deallocate(self%script_names, self%jobs_done, self%jobs_done_fnames, &
            self%jobs_submitted, stat=alloc_stat)
            if(alloc_stat /= 0) allocchk("simple_qsys_ctrl::kill deallocating ")
            if(allocated(self%cline_stack))deallocate(self%cline_stack)
            self%existence = .false.

        endif
    end subroutine kill

end module simple_qsys_ctrl

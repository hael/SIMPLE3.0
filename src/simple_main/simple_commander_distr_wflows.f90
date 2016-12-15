!==Class simple_commander_distr_wflows
!
! This class contains the set of concrete commanders responsible for execution of parallel (or distributed)
! workflows in SIMPLE. This class provides the glue between the reciver (main reciever is simple_distr_exec 
! program) and the abstract action, which is simply execute (defined by the base class: simple_commander_base).
!
! The code is distributed with the hope that it will be useful, but _WITHOUT_ _ANY_ _WARRANTY_.
! Redistribution and modification is regulated by the GNU General Public License.
! *Authors:* Frederic Bonnet, Cyril Reboul & Hans Elmlund 2016
!
module simple_commander_distr_wflows
use simple_cmdline,        only: cmdline
use simple_chash,          only: chash
use simple_qsys_base,      only: qsys_base
use simple_qsys_factory,   only: qsys_factory
use simple_qsys_ctrl,      only: qsys_ctrl
use simple_params,         only: params
use simple_commander_base, only: commander_base
use simple_commander_distr ! use all in there
use simple_map_reduce      ! singleton
use simple_defs            ! singleton
use simple_jiffys          ! singleton
use simple_qsys_funs       ! singleton
implicit none

public :: unblur_movies_distr_commander
public :: unblur_tomo_movies_distr_commander
public :: shellweight3D_distr_commander
public :: prime3D_init_distr_commander
public :: prime3D_distr_commander
public :: prime2D_init_distr_commander
public :: prime2D_distr_commander
public :: classrefine_distr_commander
public :: find_nnimgs_distr_commander
public :: recvol_distr_commander
public :: eo_recvol_distr_commander
private

type, extends(commander_base) :: unblur_movies_distr_commander
  contains
    procedure :: execute      => exec_unblur_movies_distr
end type unblur_movies_distr_commander
type, extends(commander_base) :: unblur_tomo_movies_distr_commander
  contains
    procedure :: execute      => exec_unblur_tomo_movies_distr
end type unblur_tomo_movies_distr_commander
type, extends(commander_base) :: shellweight3D_distr_commander
  contains
    procedure :: execute      => exec_shellweight3D_distr
end type shellweight3D_distr_commander
type, extends(commander_base) :: prime3D_init_distr_commander
  contains
    procedure :: execute      => exec_prime3D_init_distr
end type prime3D_init_distr_commander
type, extends(commander_base) :: prime3D_distr_commander
  contains
    procedure :: execute      => exec_prime3D_distr
end type prime3D_distr_commander
type, extends(commander_base) :: prime2D_init_distr_commander
  contains
    procedure :: execute      => exec_prime2D_init_distr
end type prime2D_init_distr_commander
type, extends(commander_base) :: prime2D_distr_commander
  contains
    procedure :: execute      => exec_prime2D_distr
end type prime2D_distr_commander
type, extends(commander_base) :: classrefine_distr_commander
  contains
    procedure :: execute      => exec_classrefine_distr
end type classrefine_distr_commander
type, extends(commander_base) :: find_nnimgs_distr_commander
  contains
    procedure :: execute      => exec_find_nnimgs_distr
end type find_nnimgs_distr_commander
type, extends(commander_base) :: recvol_distr_commander
  contains
    procedure :: execute      => exec_recvol_distr
end type recvol_distr_commander
type, extends(commander_base) :: eo_recvol_distr_commander
  contains
    procedure :: execute      => exec_eo_recvol_distr
end type eo_recvol_distr_commander

integer, parameter :: MAXNKEYS=30, KEYLEN=32

contains

    ! UNBLUR SINGLE-PARTICLE DDDs

    subroutine exec_unblur_movies_distr( self, cline )
        use simple_commander_preproc
        use simple_oris, only: oris
        class(unblur_movies_distr_commander), intent(inout) :: self
        class(cmdline),                       intent(inout) :: cline
        character(len=STDLEN), allocatable :: movienames(:)
        type(params)              :: p_master
        type(qsys_ctrl)           :: qscripts
        character(len=KEYLEN)     :: str
        type(chash)               :: myq_descr, job_descr
        integer, allocatable      :: parts(:,:)
        type(qsys_factory)        :: qsys_fac
        class(qsys_base), pointer :: myqsys
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        p_master%nptcls = nlines(p_master%filetab)
        if( p_master%nparts > p_master%nptcls ) stop 'nr of partitions (nparts) mjust be < number of entries in filetable'
        ! setup the environment for distributed execution
        call setup_qsys_env(p_master, qsys_fac, myqsys, parts, qscripts, myq_descr)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! setup the environment for distributed execution
        call setup_qsys_env(p_master, qsys_fac, myqsys, parts, qscripts, myq_descr)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! prepare scripts
        call qsys_cleanup_iter
        call qscripts%generate_scripts(job_descr, p_master%ext, myq_descr)
        ! manage job scheduling
        call qscripts%schedule_jobs
    end subroutine exec_unblur_movies_distr

    ! UNBLUR TOMOGRAPHIC DDDs

    subroutine exec_unblur_tomo_movies_distr( self, cline )
        use simple_commander_preproc
        use simple_oris, only: oris
        class(unblur_tomo_movies_distr_commander), intent(inout) :: self
        class(cmdline),                            intent(inout) :: cline
        character(len=STDLEN), allocatable :: tomonames(:), tiltnames(:)
        type(oris)                         :: exp_doc
        integer                            :: nseries, ipart, numlen
        type(params)                       :: p_master
        integer, allocatable               :: parts(:,:)
        type(qsys_ctrl)                    :: qscripts
        character(len=KEYLEN)              :: str
        type(chash)                        :: myq_descr, job_descr
        type(chash), allocatable           :: part_params(:)
        type(qsys_factory)                 :: qsys_fac
        class(qsys_base), pointer          :: myqsys
        ! make master parameters
        call cline%set('prg', 'unblur_movies')
        p_master = params(cline, checkdistr=.false.)
        if( cline%defined('tomoseries') )then
            call read_filetable(p_master%tomoseries, tomonames)
        else
            stop 'need tomoseries (filetable of filetables) to be part of the command line when tomo=yes'
        endif
        nseries = size(tomonames)
        call exp_doc%new(nseries)
        if( cline%defined('exp_doc') )then
            if( file_exists(p_master%exp_doc) )then
                call exp_doc%read(p_master%exp_doc)
            else
                write(*,*) 'the required parameter file (flag exp_doc): ', trim(p_master%exp_doc)
                stop 'not in cwd'
            endif
        else
            stop 'need exp_doc (line: exp_time=X dose_rate=Y) to be part of the command line when tomo=yes'
        endif
        p_master%nparts = nseries
        p_master%nptcls = nseries
        numlen = len(int2str(p_master%nparts))
        ! prepare part-dependent parameters
        allocate(part_params(p_master%nparts))
        do ipart=1,p_master%nparts
            call part_params(ipart)%new(4)
            call part_params(ipart)%set('filetab', trim(tomonames(ipart)))
            call part_params(ipart)%set('fbody', 'tomo'//int2str_pad(ipart,numlen))
            call real2str(exp_doc%get(ipart,'exp_time'), str)
            call part_params(ipart)%set('exp_time', str)
            call real2str(exp_doc%get(ipart,'dose_rate'), str)
            call part_params(ipart)%set('dose_rate', str)
        end do
        ! setup the environment for distributed execution
        call setup_qsys_env(p_master, qsys_fac, myqsys, parts, qscripts, myq_descr)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! prepare scripts
        call qsys_cleanup_iter
        call qscripts%generate_scripts(job_descr, p_master%ext, myq_descr, part_params=part_params)
        ! manage job scheduling
        call qscripts%schedule_jobs
    end subroutine exec_unblur_tomo_movies_distr

    ! SHELLWEIGHT3D

    subroutine exec_shellweight3D_distr( self, cline )
        use simple_commander_prime3D
        use simple_commander_distr
        class(shellweight3D_distr_commander), intent(inout) :: self
        class(cmdline),                       intent(inout) :: cline
        ! constants
        logical, parameter                 :: DEBUG=.false.
        character(len=32), parameter       :: ALGNFBODY = 'algndoc_'
        ! commanders
        type(split_commander)              :: xsplit
        type(shellweight3D_commander)      :: xshellweight3D
        type(merge_algndocs_commander)     :: xmerge_algndocs
        type(merge_shellweights_commander) :: xmerge_shellweights
        ! command lines
        type(cmdline)                      :: cline_merge_algndocs
        type(cmdline)                      :: cline_merge_shellweights
        ! other variables
        type(params)                       :: p_master
        integer, allocatable               :: parts(:,:)
        type(qsys_ctrl)                    :: qscripts
        integer                            :: iter
        integer                            :: cstat, estat
        character(len=100)                 :: cmsg
        type(chash)                        :: myq_descr, job_descr
        type(qsys_factory)                 :: qsys_fac
        class(qsys_base), pointer          :: myqsys
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        ! setup the environment for distributed execution
        call setup_qsys_env(p_master, qsys_fac, myqsys, parts, qscripts, myq_descr)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! split stack
        if( stack_is_split(p_master%ext, p_master%nparts) )then
            ! check that the stack partitions are of correct sizes
            call stack_parts_of_correct_sizes(p_master%ext, parts)
        else
            call xsplit%execute( cline )
        endif
        ! prepare scripts
        call qsys_cleanup_iter
        call qscripts%generate_scripts(job_descr, p_master%ext, myq_descr, ALGNFBODY)
        ! manage job scheduling
        call qscripts%schedule_jobs
        ! merge matrices
        call xmerge_shellweights%execute(cline)
        call qsys_cleanup_iter
        call execute_command_line('rm -rf cont3D_shellweights_part*', exitstat=estat, cmdstat=cstat, cmdmsg=cmsg)
        if( cstat > 0 )then
            print *, 'simple_commander_distr_wflows :: exec_find_nnimgs_distr; command execution failed with error ', trim(cmsg)
        elseif( cstat < 0 )then
            print *, 'simple_commander_distr_wflows :: exec_find_nnimgs_distr; command execution not supported'
        endif
        call simple_end('**** SIMPLE_DISTR_SHELLWEIGHT3D NORMAL STOP ****')
    end subroutine exec_shellweight3D_distr

    ! EO_RECVOL

    subroutine exec_eo_recvol_distr( self, cline )
        use simple_commander_rec
        class(eo_recvol_distr_commander), intent(inout) :: self
        class(cmdline),                   intent(inout) :: cline
        ! constants
        logical, parameter                  :: DEBUG=.false.
        ! commanders
        type(shellweight3D_distr_commander) :: xshellweight3D_distr
        type(split_commander)               :: xsplit
        type(eo_volassemble_commander)      :: xeo_volassemble
        ! command lines
        type(cmdline)                       :: cline_shellweight3D
        ! other variables
        type(params)                        :: p_master
        integer, allocatable                :: parts(:,:)
        type(qsys_ctrl)                     :: qscripts
        type(chash)                         :: myq_descr, job_descr
        type(qsys_factory)                  :: qsys_fac
        class(qsys_base), pointer           :: myqsys
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        ! setup the environment for distributed execution
        call setup_qsys_env(p_master, qsys_fac, myqsys, parts, qscripts, myq_descr)
        if( p_master%shellw .eq. 'yes' )then
            ! we need to set the prg flag for the command lines that control distributed workflows 
            cline_shellweight3D = cline
            call cline_shellweight3D%set('prg',     'shellweight3D'        )
            call cline_shellweight3D%set('outfile', 'shellweight3D_doc.txt')
            ! execute
            call xshellweight3D_distr%execute(cline_shellweight3D)
            call cline%set('oritab', 'shellweight3D_doc.txt')
        endif
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! split stack
        if( stack_is_split(p_master%ext, p_master%nparts) )then
            ! check that the stack partitions are of correct sizes
            call stack_parts_of_correct_sizes(p_master%ext, parts)
        else
            call xsplit%execute(cline)
        endif
        ! prepare scripts
        call qsys_cleanup_iter
        call qscripts%generate_scripts(job_descr, p_master%ext, myq_descr)
        ! manage job scheduling
        call qscripts%schedule_jobs
        ! assemble volumes
        call xeo_volassemble%execute(cline)
        call qsys_cleanup_iter
        call simple_end('**** SIMPLE_DISTR_EO_RECVOL NORMAL STOP ****')
    end subroutine exec_eo_recvol_distr

    ! PRIME3D

    subroutine exec_prime3D_init_distr( self, cline )
        use simple_commander_prime3D
        use simple_commander_rec
        class(prime3D_init_distr_commander), intent(inout) :: self
        class(cmdline),                      intent(inout) :: cline
        ! constants
        logical, parameter           :: debug=.false.
        ! commanders
        type(prime3D_init_commander) :: xprime3D_init
        type(volassemble_commander)  :: xvolassemble
        type(split_commander)        :: xsplit
        ! command lines
        type(cmdline)                :: cline_volassemble
        ! other variables
        type(params)                 :: p_master
        integer, allocatable         :: parts(:,:)
        type(qsys_ctrl)              :: qscripts
        character(len=KEYLEN)        :: keys_required(MAXNKEYS)='', keys_optional(MAXNKEYS)=''
        character(len=STDLEN)        :: vol
        type(chash)                  :: myq_descr, job_descr
         type(qsys_factory)          :: qsys_fac
        class(qsys_base), pointer    :: myqsys
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        ! setup the environment for distributed execution
        call setup_qsys_env(p_master, qsys_fac, myqsys, parts, qscripts, myq_descr)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! init
        if( cline%defined('vol1') )then
           vol = trim(p_master%vols(1))
        else
           vol = trim('startvol_state01'//p_master%ext)
        endif
        ! split stack
        if( stack_is_split(p_master%ext, p_master%nparts) )then
            ! check that the stack partitions are of correct sizes
            call stack_parts_of_correct_sizes(p_master%ext, parts)
        else
            call xsplit%execute( cline )
        endif
        ! prepare command lines from prototype master
        cline_volassemble = cline
        call cline_volassemble%set( 'outvol', vol )
        call cline_volassemble%set( 'eo', 'no' )
        ! prepare scripts
        call qsys_cleanup_iter
        call qscripts%generate_scripts(job_descr, p_master%ext, myq_descr)
        ! manage job scheduling
        call qscripts%schedule_jobs
        ! assemble volumes
        call xvolassemble%execute( cline_volassemble )
        ! termination
        call qsys_cleanup_iter
        call simple_end('**** SIMPLE_DISTR_PRIME3D_INIT NORMAL STOP ****')
    end subroutine exec_prime3D_init_distr

    subroutine exec_prime3D_distr( self, cline )
        use simple_commander_prime3D
        use simple_commander_mask
        use simple_commander_rec
        use simple_syscalls
        class(prime3D_distr_commander), intent(inout) :: self
        class(cmdline),                 intent(inout) :: cline
        ! constants
        logical, parameter             :: DEBUG=.false.
        character(len=32), parameter   :: DIRFBODY  = 'prime3Dround_'
        character(len=32), parameter   :: ALGNFBODY = 'algndoc_'
        character(len=32), parameter   :: ITERFBODY = 'prime3Ddoc_'
        character(len=32), parameter   :: VOLFBODY  = 'recvol_state'
        ! commanders
        type(prime3D_init_distr_commander) :: xprime3D_init_distr
        type(recvol_distr_commander)       :: xrecvol_distr
        type(prime3D_commander)        :: xprime3D
        type(resrange_commander)       :: xresrange
        type(merge_algndocs_commander) :: xmerge_algndocs
        type(volassemble_commander)    :: xvolassemble
        type(eo_volassemble_commander) :: xeo_volassemble
        type(check3D_conv_commander)   :: xcheck3D_conv
        type(split_commander)          :: xsplit
        ! command lines
        type(cmdline)                  :: cline_recvol_distr
        type(cmdline)                  :: cline_prime3D_init
        type(cmdline)                  :: cline_resrange
        type(cmdline)                  :: cline_check3D_conv
        type(cmdline)                  :: cline_merge_algndocs
        type(cmdline)                  :: cline_volassemble
        ! other variables
        type(params)                   :: p_master
        integer, allocatable           :: parts(:,:)
        type(qsys_ctrl)                :: qscripts
        character(len=STDLEN)          :: vol, oritab, str, str_iter, dir_iter, str_state
        integer                        :: state, iter, status, cnt
        type(chash)                    :: myq_descr, job_descr
        type(qsys_factory)             :: qsys_fac
        class(qsys_base), pointer      :: myqsys
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        ! options check
        if( p_master%automsk.eq.'yes' )stop 'Automasking not supported yet' ! automask deactivated for now
        if( p_master%nstates>1 .and. p_master%dynlp.eq.'yes' )&
            &stop 'Incompatible options: nstates>1 and dynlp=yes'
        if( p_master%automsk.eq.'yes' .and. p_master%dynlp.eq.'yes' )&
            &stop 'Incompatible options: automsk=yes and dynlp=yes'
        if( p_master%eo.eq.'yes' .and. p_master%dynlp.eq.'yes' )&
            &stop 'Incompatible options: eo=yes and dynlp=yes'
        ! setup the environment for distributed execution
        call setup_qsys_env(p_master, qsys_fac, myqsys, parts, qscripts, myq_descr)

        ! initialise
        if( .not. cline%defined('nspace') ) call cline%set('nspace', 1000.)
        call cline%set( 'box', real(p_master%box) )
        ! prepare command lines from prototype master
        cline_recvol_distr   = cline
        cline_prime3D_init   = cline
        cline_resrange       = cline
        cline_check3D_conv   = cline
        cline_merge_algndocs = cline
        cline_volassemble    = cline
        ! initialise static command line parameters and static job description parameter
        call cline_recvol_distr%set( 'prg', 'recvol' )          ! required for distributed call
        call cline_prime3D_init%set( 'prg', 'prime3D_init' )    ! required for distributed call
        call cline_merge_algndocs%set( 'nthr', 1. )
        call cline_merge_algndocs%set( 'fbody',  ALGNFBODY)
        call cline_merge_algndocs%set( 'nptcls', real(p_master%nptcls) )
        call cline_merge_algndocs%set( 'ndocs',  real(p_master%nparts) )
        call cline_check3D_conv%set( 'box',    real(p_master%box))
        call cline_check3D_conv%set( 'nptcls', real(p_master%nptcls))
        call cline_volassemble%set( 'nthr', 1. )

        ! SPLIT STACK
        if( stack_is_split(p_master%ext, p_master%nparts) )then
            ! check that the stack partitions are of correct sizes
            call stack_parts_of_correct_sizes(p_master%ext, parts)
        else
            call xsplit%execute( cline )
        endif

        ! GENERATE STARTING MODELS & ORIENTATIONS
        ! Orientations
        if( cline%defined('oritab') )then
            oritab=trim(p_master%oritab)
        else
            oritab='prime3D_startdoc.txt'
        endif
        ! Models
        if( .not.cline%defined('oritab') .and. .not.cline%defined('vol1') )then
            ! ab-initio
            call xprime3D_init_distr%execute( cline_prime3D_init )
            call cline%set( 'vol1', trim('startvol_state01'//p_master%ext) )
        else if( cline%defined('oritab') .and. .not.cline%defined('vol1') )then
            ! reconstructions needed
            call xrecvol_distr%execute( cline_recvol_distr )
            do state = 1,p_master%nstates
                ! rename volumes and updates cline
                str_state = int2str_pad(state,2)
                vol = trim( VOLFBODY )//trim(str_state)//p_master%ext
                str = 'startvol_state'//trim(str_state)//p_master%ext
                call rename( trim(vol), trim(str) )
                vol = 'vol'//trim(int2str(state))
                call cline%set( trim(vol), trim(str) )
            enddo
        else if( .not.cline%defined('oritab') .and. cline%defined('vol1') )then
            if( p_master%nstates>1 )stop 'orientations doc at least must be provided for nstates>1'
            if( p_master%refine .ne. 'greedy' )call cline%set('refine', 'greedy')
        else
            ! all good
        endif

        ! DYNAMIC LOW-PASS
        if( p_master%dynlp.eq.'yes' )then
            if( cline%defined('lpstart') .and. cline%defined('lpstop') )then
                ! all good
            else
                call xresrange%execute( cline_resrange )
                ! initial low-pass
                if( .not. cline%defined('lpstart') )then
                    call cline%set('lpstart', cline_resrange%get_rarg('lpstart') )
                    p_master%lpstart = cline%get_rarg('lpstart')
                endif
                ! final low-pass
                if( .not.cline%defined('lpstop') )then
                    call cline%set('lpstop', cline_resrange%get_rarg('lpstop') )
                    p_master%lpstop = cline%get_rarg('lpstop')
                endif
            endif
            ! initial fourier index
            p_master%find = int( ( real(p_master%box-1)*p_master%smpd ) / p_master%lpstart )
            call cline_check3D_conv%set( 'update_res', 'no' )
            call cline_check3D_conv%set( 'find', real(p_master%find) )
            call cline%set( 'find', real(p_master%find) )
        endif

        ! prepare Prime3D job description
        call cline%gen_job_descr(job_descr)

        ! MAIN LOOP
        iter = p_master%startit-1
        do
            iter = iter+1
            write(*,'(A)')   '>>>'
            write(*,'(A,I6)')'>>> ITERATION ', iter
            write(*,'(A)')   '>>>'
            ! FILE HANDLING
            str_iter = int2str_pad(iter,3)
            dir_iter = trim(DIRFBODY)//trim(str_iter)//'/'
            call sys_mkdir( trim(dir_iter) )
            call qsys_cleanup_iter
            ! PREPARE PRIME3D SCRIPTS
            call job_descr%set( 'oritab', oritab ) 
            call job_descr%set( 'startit', trim(int2str(iter)) )
            call qscripts%generate_scripts(job_descr, p_master%ext, myq_descr, ALGNFBODY)
            ! PRIMED3D JOB SCHEDULING
            call qscripts%schedule_jobs
            ! ASSEMBLE ALIGNMENT DOCS
            oritab = trim( dir_iter )//trim( ITERFBODY )//trim(str_iter)//'.txt'
            call cline_merge_algndocs%set( 'outfile', trim(oritab) )
            call xmerge_algndocs%execute( cline_merge_algndocs )
            ! ASSEMBLE VOLUMES
            call cline_volassemble%set( 'oritab', trim(oritab) )
            if( p_master%eo.eq.'yes' )then
                str = 'rm fsc_state01.bin' ! this is temporary and related to automask
                call exec_cmdline( str )   ! and leveraged just below
                call xeo_volassemble%execute( cline_volassemble )
            else
                call xvolassemble%execute( cline_volassemble )
            endif
            ! move volumes and update job_descr
            do state = 1,p_master%nstates
                str_state = int2str_pad(state,2)
                vol = trim( VOLFBODY )//trim(str_state)//p_master%ext
                str = trim(dir_iter)//trim(volfbody)//trim(str_state)//p_master%ext
                call rename( trim(vol), trim(str) )
                vol = 'vol'//trim(int2str(state))
                call job_descr%set( trim(vol), trim(str) )
            enddo
            if( p_master%eo.eq.'yes' )then
                ! copy other files in binary format (fsc, ssnr, etc.)
                cnt = 0                                             ! this is temprorary and related to automask
                do while( .not.file_exists('./fsc_state01.bin') )   ! simply create extra-timing precaution 
                    cnt = cnt + 1                                   !
                    if( cnt>30 )stop './fsc_state01.bin not found'  !
                    call sleep( 1 )                                 !
                enddo                                               !
                call copy_bin_files( 'fsc_',       dir_iter, p_master%nstates )
                call copy_bin_files( 'pssnr2D_',   dir_iter, p_master%nstates )
                call copy_bin_files( 'pssnr3D_',   dir_iter, p_master%nstates )
                call copy_bin_files( 'ctfsqspec_', dir_iter, p_master%nstates )
                if( p_master%automsk.eq.'yes')call copy_bin_files( 'automask_', dir_iter, p_master%nstates )
            endif
            ! CONVERGENCE
            call cline_check3D_conv%set( 'oritab', trim(oritab) )
            call xcheck3D_conv%execute( cline_check3D_conv )
            if( iter >= p_master%startit+2 )then
                ! after a minimum of 2 iterations
                if( cline_check3D_conv%get_carg('converged').eq.'yes' )exit
            endif
            if( iter>=p_master%maxits ) exit
            ! ITERATION DEPENDENT UPDATES
            if( cline_check3D_conv%defined('trs') .and. .not.job_descr%isthere('trs') )then
                ! activates shift search if frac >= 90
                call real2str(cline_check3D_conv%get_rarg('trs'), str)
                call job_descr%set( 'trs', trim(str) )
            endif
            if( p_master%dynlp.eq.'yes' )then
                ! dynamic resolution update
                if( cline_check3D_conv%get_carg('update_res').eq.'yes' )then
                    p_master%find = p_master%find + p_master%fstep  ! fourier index update
                    call job_descr%set( 'find', int2str(p_master%find) )
                    call cline_check3D_conv%set( 'find', real(p_master%find) )
               endif
            endif
        end do
        call qsys_cleanup_iter
        ! POST PROCESSING ?
        call simple_end('**** SIMPLE_DISTR_PRIME3D NORMAL STOP ****')
    end subroutine exec_prime3D_distr

    ! PRIME2D_INIT

    subroutine exec_prime2D_init_distr( self, cline )
        use simple_commander_prime2D
        use simple_commander_distr
        use simple_commander_mask
        class(prime2D_init_distr_commander), intent(inout) :: self
        class(cmdline),                      intent(inout) :: cline
        ! constants
        logical, parameter           :: DEBUG=.false.
        ! commanders
        type(cavgassemble_commander) :: xcavgassemble
        type(split_commander)        :: xsplit
        ! command lines
        type(cmdline)                :: cline_cavgassemble
        ! other variables
        type(params)                 :: p_master
        integer, allocatable         :: parts(:,:)
        type(qsys_ctrl)              :: qscripts
        character(len=STDLEN)        :: refs, oritab
        integer                      :: iter
        type(chash)                  :: myq_descr, job_descr
        type(qsys_factory)           :: qsys_fac
        class(qsys_base), pointer    :: myqsys
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        ! setup the environment for distributed execution
        call setup_qsys_env(p_master, qsys_fac, myqsys, parts, qscripts, myq_descr)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! prepare command lines from prototype master
        cline_cavgassemble   = cline
        call cline_cavgassemble%set('nthr',1.)
        call cline_cavgassemble%set('oritab', 'prime2D_startdoc.txt')
        ! split stack
        if( stack_is_split(p_master%ext, p_master%nparts) )then
            ! check that the stack partitions are of correct sizes
            call stack_parts_of_correct_sizes(p_master%ext, parts)
        else
            call xsplit%execute(cline)
        endif
        ! prepare scripts
        call qsys_cleanup_iter
        call qscripts%generate_scripts(job_descr, p_master%ext, myq_descr)
        ! manage job scheduling
        call qscripts%schedule_jobs
        ! assemble class averages
        call xcavgassemble%execute(cline_cavgassemble)
        call qsys_cleanup_iter
        call simple_end('**** SIMPLE_DISTR_PRIME2D_INIT NORMAL STOP ****')
    end subroutine exec_prime2D_init_distr

    ! PRIME2D

    subroutine exec_prime2D_distr( self, cline )
        use simple_commander_prime2D
        use simple_commander_distr
        use simple_commander_mask
        use simple_oris, only: oris
        class(prime2D_distr_commander), intent(inout) :: self
        class(cmdline),                 intent(inout) :: cline
        ! constants
        logical, parameter                 :: DEBUG=.true.
        integer, parameter                 :: MAXNKEYS=30, KEYLEN=32
        character(len=32), parameter       :: ALGNFBODY       = 'algndoc_'
        character(len=32), parameter       :: ITERFBODY       = 'prime2Ddoc_'
        character(len=32), parameter       :: CAVGS_ITERFBODY = 'cavgs_iter'
        real,              parameter       :: FRACLIM_CREFINE = 50.
        real,              parameter       :: MSK_FRAC        = 0.06
        real,              parameter       :: MINSHIFT        = 2.0
        real,              parameter       :: MAXSHIFT        = 6.0
        ! commanders
        type(prime2D_init_distr_commander) :: xprime2D_init_distr
        type(find_nnimgs_distr_commander)  :: xfind_nnimgs_distr
        type(classrefine_distr_commander)  :: xclassrefine_distr
        type(cavgassemble_commander)       :: xcavgassemble
        type(check2D_conv_commander)       :: xcheck2D_conv
        type(rank_cavgs_commander)         :: xrank_cavgs
        type(merge_algndocs_commander)     :: xmerge_algndocs
        type(split_commander)              :: xsplit
        type(automask2D_commander)         :: xautomask2D
        ! command lines
        type(cmdline)                      :: cline_check2D_conv
        type(cmdline)                      :: cline_cavgassemble
        type(cmdline)                      :: cline_rank_cavgs
        type(cmdline)                      :: cline_merge_algndocs
        type(cmdline)                      :: cline_automask2D
        type(cmdline)                      :: cline_prime2D_init
        type(cmdline)                      :: cline_find_nnimgs
        type(cmdline)                      :: cline_classrefine
        ! other variables
        type(params)                       :: p_master
        integer, allocatable               :: parts(:,:)
        type(qsys_ctrl)                    :: qscripts
        character(len=STDLEN)              :: refs, oritab, str, str_iter
        integer                            :: iter
        type(chash)                        :: myq_descr, job_descr
        type(oris)                         :: crefine_os
        type(qsys_factory)                 :: qsys_fac
        class(qsys_base), pointer          :: myqsys
        real                               :: frac_srch_space, trs, lplim
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        ! setup the environment for distributed execution
        call setup_qsys_env(p_master, qsys_fac, myqsys, parts, qscripts, myq_descr)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! create crefine oris object
        call crefine_os%new(p_master%nptcls)
        ! initialise low-pass limit
        lplim = p_master%lp
        ! initialise starting references, orientations
        if( cline%defined('oritab') )then
            oritab=trim(p_master%oritab)
        else
            oritab=''
        endif
        if( cline%defined('refs') )then
            refs = trim(p_master%refs)
        else
            refs = trim('startcavgs' // p_master%ext)
        endif
        ! prepare command lines from prototype master
        cline_check2D_conv   = cline
        cline_cavgassemble   = cline
        cline_rank_cavgs     = cline
        cline_merge_algndocs = cline
        cline_automask2D     = cline
        cline_prime2D_init   = cline
        cline_find_nnimgs    = cline
        cline_classrefine    = cline
        ! we need to set the prg flag for the command lines that control distributed workflows 
        call cline_prime2D_init%set('prg', 'prime2D_init')
        call cline_find_nnimgs%set('prg', 'find_nnimgs' )
        call cline_classrefine%set('prg', 'classrefine' )
        ! initialise static command line parameters and static job description parameters
        call cline_merge_algndocs%set('fbody',  ALGNFBODY)
        call cline_merge_algndocs%set('nptcls', real(p_master%nptcls))
        call cline_merge_algndocs%set('ndocs', real(p_master%nparts))
        call cline_check2D_conv%set('box', real(p_master%box))
        call cline_check2D_conv%set('nptcls', real(p_master%nptcls))
        if( .not. cline%defined('refs') .and. job_descr%isthere('automsk') ) call job_descr%delete('automsk')
        ! split stack
        if( stack_is_split(p_master%ext, p_master%nparts) )then
            ! check that the stack partitions are of correct sizes
            call stack_parts_of_correct_sizes(p_master%ext, parts)
        else
            call xsplit%execute(cline)
        endif
        ! execute initialiser
        if( .not. cline%defined('refs') )then
            call xprime2D_init_distr%execute(cline_prime2D_init)
            oritab='prime2D_startdoc.txt'
        endif
        ! main loop
        iter = p_master%startit-1
        do
            iter     = iter+1
            str_iter = trim( int2str_pad(iter,3) )
            call qsys_cleanup_iter
            ! identify nearest neighbors in parallel, if needed
            if( str_has_substr(p_master%refine,'neigh') )then
                call cline_find_nnimgs%set('stk', refs)
                call xfind_nnimgs_distr%execute(cline_find_nnimgs)
            endif
            ! prepare scripts
            if( oritab .ne. '' ) call job_descr%set('oritab',  oritab)
            call job_descr%set('refs',    refs)
            call job_descr%set('startit', int2str(iter))
            call real2str(lplim, str)
            call job_descr%set('lp', trim(str))
            call qscripts%generate_scripts(job_descr, p_master%ext, myq_descr, ALGNFBODY)
            ! manage job scheduling
            call qscripts%schedule_jobs
            ! merge orientation documents
            oritab=trim(ITERFBODY)// str_iter //'.txt'
            call cline_merge_algndocs%set('outfile', oritab)
            call xmerge_algndocs%execute(cline_merge_algndocs)
            ! assemble class averages
            refs = trim(trim(CAVGS_ITERFBODY)// str_iter //p_master%ext)
            call cline_cavgassemble%set('oritab',     oritab)
            call cline_cavgassemble%set('which_iter', real(iter))
            call xcavgassemble%execute(cline_cavgassemble)
            ! check convergence
            call cline_check2D_conv%set('oritab', oritab)
            call cline_check2D_conv%set('lp',     real(p_master%lp)) ! may be subjected to iter-dependent update in future
            call xcheck2D_conv%execute(cline_check2D_conv)
            frac_srch_space = cline_check2D_conv%get_rarg('frac')
            if( frac_srch_space >= FRACLIM_CREFINE )then
                ! activate within class refinement
                call cline_classrefine%set('refs',   refs  )
                call cline_classrefine%set('oritab', oritab)
                call real2str(lplim, str)
                call cline_classrefine%set('lp', str)
                if( cline_check2D_conv%defined('trs') )then
                    trs = cline_check2D_conv%get_rarg('trs')
                else
                    ! determine shift bounds
                    trs = MSK_FRAC*real(p_master%msk)
                    trs = max(MINSHIFT,trs)
                    trs = min(MAXSHIFT,trs)
                endif
                call cline_classrefine%set('trs', trs)
                call cline_classrefine%set('ncunits', real(p_master%ncunits))
                call xclassrefine_distr%execute(cline_classrefine)
                oritab='classrefine_doc_merged.txt'
                call crefine_os%read(oritab)
                lplim = crefine_os%median('lp')
            endif
            ! this activates shifting & automasking if frac >= 90
            if( cline_check2D_conv%defined('trs') .and. .not.job_descr%isthere('trs') )then
                ! activates shift search
                call real2str(cline_check2D_conv%get_rarg('trs'), str)
                call job_descr%set('trs', trim(str) )
                if( cline%defined('automsk') )then
                    ! activates masking
                    if( cline%get_carg('automsk').ne.'no' )call job_descr%set('automsk','yes')
                endif
            endif
            if( cline_check2D_conv%get_carg('converged').eq.'yes' .or. iter==p_master%maxits ) exit
        end do
        call qsys_cleanup_iter
        ! performs masking
        if( cline_automask2D%get_carg('automsk').eq.'cavg' )then
            call cline_automask2D%set('stk', refs)
            call xautomask2D%execute(cline_automask2D)
            refs = trim('cavgs_iter'//int2str_pad(iter,3)//'msk'//p_master%ext)
        endif
        ! ranking
        call cline_rank_cavgs%set('oritab', oritab)
        call cline_rank_cavgs%set('stk',    refs)
        call cline_rank_cavgs%set('outstk', trim('cavgs_final_ranked'//p_master%ext))
        call xrank_cavgs%execute( cline_rank_cavgs )
        call simple_end('**** SIMPLE_DISTR_PRIME2D NORMAL STOP ****')
    end subroutine exec_prime2D_distr

    ! CLASSREFINE (within class refinement)

    subroutine exec_classrefine_distr( self, cline )
        use simple_commander_prime2D,  only: classrefine_commander
        use simple_oris,               only: oris
        use simple_image,              only: image
        class(classrefine_distr_commander), intent(inout) :: self
        class(cmdline),                     intent(inout) :: cline
        ! constants
        logical,           parameter :: DEBUG=.false.
        character(len=32), parameter :: ALGNFBODY='classrefine_doc_class'
        integer,           parameter :: NUMLEN=5
        ! commanders
        type(classrefine_commander)       :: xclassrefine
        type(merge_crefine_out_commander) :: xmerge_crefine_out
         ! command lines
        type(cmdline)                     :: cline_merge_crefine_out
        ! other variables
        integer,          allocatable     :: parts(:,:)
        type(chash),      allocatable     :: part_params(:)
        character(len=:), allocatable     :: fname
        class(qsys_base), pointer         :: myqsys
        type(oris)                        :: os
        type(params)                      :: p_master
        type(qsys_ctrl)                   :: qscripts
        type(chash)                       :: myq_descr, job_descr
        type(qsys_factory)                :: qsys_fac
        type(image)                       :: img
        integer                           :: cstat, estat
        character(len=100)                :: cmsg
        integer                           :: ldim(3), ncls, icls
        integer                           :: nl, cnt, alloc_stat, pop
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        ! read in oritab
        nl = nlines(p_master%oritab)
        call os%new(nl)
        call os%read(p_master%oritab)
        ! make the part_params array
        ncls = os%get_ncls()
        cnt  = 0
        do icls=1,ncls
            pop = os%get_clspop(icls)
            if( pop >= p_master%minp ) cnt = cnt + 1
        end do
        allocate( part_params(cnt), stat=alloc_stat )
        call alloc_err("In: simple_commander_distr_wflows :: exec_classrefine_distr", alloc_stat)
        cnt  = 0
        do icls=1,ncls
            pop = os%get_clspop(icls)
            if( pop >= p_master%minp )then
                cnt = cnt + 1
                call part_params(cnt)%new(1)
                call part_params(cnt)%set('class', int2str(icls))
            endif
        end do
        ! update p_master
        p_master%nparts = cnt
        ! setup the environment for distributed execution
        call setup_qsys_env(p_master, qsys_fac, myqsys, parts, qscripts, myq_descr)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! prepare merge_classdocs command line from prototype master
        cline_merge_crefine_out = cline
        call cline_merge_crefine_out%set('nptcls',  real(nl))
        call cline_merge_crefine_out%set('outfile', 'classrefine_doc_merged.txt')
        call cline_merge_crefine_out%set('box',     real(p_master%box))
        ! prepare scripts
        call qsys_cleanup_iter
        call qscripts%generate_scripts(job_descr, p_master%ext,&
        myq_descr, outfile_body=ALGNFBODY, part_params=part_params)
        ! manage job scheduling
        call qscripts%schedule_jobs
        ! merge the ouput (file-bodies hardcoded)
        call xmerge_crefine_out%execute(cline_merge_crefine_out)
        ! update the references
        call find_ldim_nptcls(p_master%refs, ldim, ncls)
        ldim(3) = 1 ! correct for stupid mrc convention
        call img%new(ldim, p_master%smpd)
        do icls=1,ncls
            allocate(fname, source='classrefine_avg_class'//int2str_pad(icls,NUMLEN)//p_master%ext)
            if( file_exists(fname) )then
                call img%read(fname, 1)
                call img%write(p_master%refs, icls)
                call del_binfile(fname)
            endif
            deallocate(fname)
        end do
        ! end gracefully
        call simple_end('**** SIMPLE_DISTR_CLASSREFINE NORMAL STOP ****')
    end subroutine exec_classrefine_distr

    ! FIND_NNIMGS (to find nearest neighbors in 2D)

    subroutine exec_find_nnimgs_distr( self, cline )
        use simple_commander_misc,  only: find_nnimgs_commander
        use simple_commander_distr, only: merge_nnmat_commander
        class(find_nnimgs_distr_commander), intent(inout) :: self
        class(cmdline),                     intent(inout) :: cline
        ! constants
        logical, parameter            :: DEBUG=.false.
        ! commanders
        type(find_nnimgs_commander)   :: xfind_nnimgs
        type(merge_nnmat_commander)   :: xmerge_nnmat
        ! other variables
        type(params)                  :: p_master
        integer, allocatable          :: parts(:,:)
        type(qsys_ctrl)               :: qscripts
        integer                       :: cstat, estat
        character(len=100)            :: cmsg
        type(chash)                   :: myq_descr, job_descr
        type(qsys_factory)            :: qsys_fac
        class(qsys_base), pointer     :: myqsys
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        ! setup the environment for distributed execution
        call setup_qsys_env(p_master, qsys_fac, myqsys, parts, qscripts, myq_descr)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! main functionality
        call qsys_cleanup_iter
        call qscripts%generate_scripts(job_descr, p_master%ext, myq_descr)
        call qscripts%schedule_jobs
        call xmerge_nnmat%execute(cline)
        call qsys_cleanup_iter
        call execute_command_line('rm -rf nnmat_part*', exitstat=estat, cmdstat=cstat, cmdmsg=cmsg)
        if( cstat > 0 )then
            print *, 'simple_commander_distr_wflows :: exec_find_nnimgs_distr; command execution failed with error ', trim(cmsg)
        elseif( cstat < 0 )then
            print *, 'simple_commander_distr_wflows :: exec_find_nnimgs_distr; command execution not supported'
        endif
        call simple_end('**** SIMPLE_DISTR_FIND_NNIMGS NORMAL STOP ****')
    end subroutine exec_find_nnimgs_distr

    subroutine exec_recvol_distr( self, cline )
        use simple_commander_rec
        class(recvol_distr_commander), intent(inout) :: self
        class(cmdline),                intent(inout) :: cline
        ! constants
        logical, parameter                  :: debug=.false.
        ! commanders
        type(recvol_commander)              :: xrecvol
        type(recvol_commander)              :: xeo_recvol
        type(volassemble_commander)         :: xvolassemble
        type(eo_volassemble_commander)      :: xeo_volassemble
        type(split_commander)               :: xsplit
        type(shellweight3D_distr_commander) :: xshellweight3D_distr
        ! command lines
        type(cmdline)                       :: cline_shellweight3D        ! other variables
        type(params)                        :: p_master
        integer, allocatable                :: parts(:,:)
        type(qsys_ctrl)                     :: qscripts
        character(len=STDLEN)               :: vol
        type(chash)                         :: myq_descr, job_descr
         type(qsys_factory)                 :: qsys_fac
        class(qsys_base), pointer           :: myqsys
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        ! setup the environment for distributed execution
        call setup_qsys_env(p_master, qsys_fac, myqsys, parts, qscripts, myq_descr)
        if( p_master%shellw .eq. 'yes' )then
            ! we need to set the prg flag for the command lines that control distributed workflows 
            cline_shellweight3D = cline
            call cline_shellweight3D%set('prg',     'shellweight3D'        )
            call cline_shellweight3D%set('outfile', 'shellweight3D_doc.txt')
            ! execute
            call xshellweight3D_distr%execute(cline_shellweight3D)
            call cline%set('oritab', 'shellweight3D_doc.txt')
        endif
        call cline%set( 'prg','recvol' )
        if( p_master%eo .eq. 'yes' )call cline%set( 'prg','eo_recvol' )
        call cline%gen_job_descr(job_descr)
        ! split stack
        if( stack_is_split(p_master%ext, p_master%nparts) )then
            ! check that the stack partitions are of correct sizes
            call stack_parts_of_correct_sizes(p_master%ext, parts)
        else
            call xsplit%execute( cline )
        endif
        !call qsys_cleanup_iter
        call qscripts%generate_scripts(job_descr, p_master%ext, myq_descr)
        ! manage job scheduling
        call qscripts%schedule_jobs
        ! assemble volumes
        if( p_master%eo.eq.'yes' )then
            call xeo_volassemble%execute( cline )
        else
            call xvolassemble%execute( cline )
        endif
        ! termination
        call qsys_cleanup_iter
        call simple_end('**** SIMPLE_RECVOL_INIT NORMAL STOP ****')
    end subroutine exec_recvol_distr

end module simple_commander_distr_wflows

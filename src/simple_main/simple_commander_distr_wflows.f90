!==Class simple_commander_distr_wflows
!
! This class contains the set of concrete commanders responsible for execution of parallel (or distributed)
! workflows in SIMPLE. This class provides the glue between the reciver (main reciever is simple_distr_exec 
! program) and the abstract action, which is simply execute (defined by the base class: simple_commander_base).
!
! The code is distributed with the hope that it will be useful, but _WITHOUT_ _ANY_ _WARRANTY_.
! Redistribution and modification is regulated by the GNU General Public License.
! *Authors:* Cyril Reboul & Hans Elmlund 2016
!
module simple_commander_distr_wflows
use simple_defs
use simple_cmdline,        only: cmdline
use simple_chash,          only: chash
use simple_qsys_env,       only: qsys_env
use simple_params,         only: params
use simple_commander_base, only: commander_base
use simple_strings,        only: real2str
use simple_commander_distr ! use all in there
use simple_map_reduce      ! use all in there
use simple_qsys_funs       ! use all in there
use simple_syscalls        ! use all in there
use simple_filehandling    ! use all in there
use simple_jiffys          ! use all in there
implicit none

public :: unblur_ctffind_distr_commander
public :: unblur_distr_commander
public :: unblur_tomo_movies_distr_commander
public :: ctffind_distr_commander
public :: pick_distr_commander
public :: makecavgs_distr_commander
public :: cont3D_distr_commander
public :: prime2D_distr_commander
public :: prime2D_chunk_distr_commander
public :: prime3D_init_distr_commander
public :: prime3D_distr_commander
public :: shellweight3D_distr_commander
public :: recvol_distr_commander
public :: tseries_track_distr_commander
private

type, extends(commander_base) :: unblur_ctffind_distr_commander
  contains
    procedure :: execute      => exec_unblur_ctffind_distr
end type unblur_ctffind_distr_commander
type, extends(commander_base) :: unblur_distr_commander
  contains
    procedure :: execute      => exec_unblur_distr
end type unblur_distr_commander
type, extends(commander_base) :: unblur_tomo_movies_distr_commander
  contains
    procedure :: execute      => exec_unblur_tomo_movies_distr
end type unblur_tomo_movies_distr_commander
type, extends(commander_base) :: ctffind_distr_commander
  contains
    procedure :: execute      => exec_ctffind_distr
end type ctffind_distr_commander
type, extends(commander_base) :: pick_distr_commander
  contains
    procedure :: execute      => exec_pick_distr
end type pick_distr_commander
type, extends(commander_base) :: makecavgs_distr_commander
  contains
    procedure :: execute      => exec_makecavgs_distr
end type makecavgs_distr_commander
type, extends(commander_base) :: prime2D_distr_commander
  contains
    procedure :: execute      => exec_prime2D_distr
end type prime2D_distr_commander
type, extends(commander_base) :: prime2D_chunk_distr_commander
  contains
    procedure :: execute      => exec_prime2D_chunk_distr
end type prime2D_chunk_distr_commander
type, extends(commander_base) :: prime3D_init_distr_commander
  contains
    procedure :: execute      => exec_prime3D_init_distr
end type prime3D_init_distr_commander
type, extends(commander_base) :: cont3D_distr_commander
  contains
    procedure :: execute      => exec_cont3D_distr
end type cont3D_distr_commander
type, extends(commander_base) :: prime3D_distr_commander
  contains
    procedure :: execute      => exec_prime3D_distr
end type prime3D_distr_commander
type, extends(commander_base) :: shellweight3D_distr_commander
  contains
    procedure :: execute      => exec_shellweight3D_distr
end type shellweight3D_distr_commander
type, extends(commander_base) :: recvol_distr_commander
  contains
    procedure :: execute      => exec_recvol_distr
end type recvol_distr_commander
type, extends(commander_base) :: tseries_track_distr_commander
  contains
    procedure :: execute      => exec_tseries_track_distr
end type tseries_track_distr_commander

integer, parameter :: KEYLEN=32

contains

    ! PIPELINED UNBLUR + CTFFIND

    subroutine exec_unblur_ctffind_distr( self, cline )
        use simple_commander_preproc
        class(unblur_ctffind_distr_commander), intent(inout) :: self
        class(cmdline),                        intent(inout) :: cline
        character(len=32), parameter   :: UNIDOCFBODY = 'unindoc_'
        type(merge_algndocs_commander) :: xmerge_algndocs
        type(cmdline)  :: cline_merge_algndocs
        type(qsys_env) :: qenv
        type(params)   :: p_master
        type(chash)    :: job_descr
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        p_master%nptcls = nlines(p_master%filetab)
        if( p_master%nparts > p_master%nptcls ) stop 'nr of partitions (nparts) mjust be < number of entries in filetable'
        ! prepare merge_algndocs command line
        cline_merge_algndocs = cline
        call cline_merge_algndocs%set( 'nthr',    1.                         )
        call cline_merge_algndocs%set( 'fbody',   'unindoc_'                 )
        call cline_merge_algndocs%set( 'nptcls',  real(p_master%nptcls)      )
        call cline_merge_algndocs%set( 'ndocs',   real(p_master%nparts)      )
        call cline_merge_algndocs%set( 'outfile', 'simple_unidoc_merged.txt' )
        ! setup the environment for distributed execution
        call qenv%new(p_master)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! schedule & clean
        call qenv%gen_scripts_and_schedule_jobs(p_master, job_descr, algnfbody=UNIDOCFBODY)
        ! merge docs
        call xmerge_algndocs%execute( cline_merge_algndocs )
        ! clean
        call qsys_cleanup(p_master)
        ! end gracefully
        call simple_end('**** SIMPLE_DISTR_UNBLUR_CTFFIND NORMAL STOP ****')
    end subroutine exec_unblur_ctffind_distr

    ! UNBLUR SP DDDs

    subroutine exec_unblur_distr( self, cline )
        use simple_commander_preproc
        class(unblur_distr_commander), intent(inout) :: self
        class(cmdline),                intent(inout) :: cline
        character(len=32), parameter   :: UNIDOCFBODY = 'unindoc_'
        type(merge_algndocs_commander) :: xmerge_algndocs
        type(cmdline)  :: cline_merge_algndocs
        type(qsys_env) :: qenv
        type(params)   :: p_master
        type(chash)    :: job_descr
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        p_master%nptcls = nlines(p_master%filetab)
        if( p_master%nparts > p_master%nptcls ) stop 'nr of partitions (nparts) mjust be < number of entries in filetable'
        ! prepare merge_algndocs command line
        cline_merge_algndocs = cline
        call cline_merge_algndocs%set( 'nthr',    1.                         )
        call cline_merge_algndocs%set( 'fbody',   'unindoc_'                 )
        call cline_merge_algndocs%set( 'nptcls',  real(p_master%nptcls)      )
        call cline_merge_algndocs%set( 'ndocs',   real(p_master%nparts)      )
        call cline_merge_algndocs%set( 'outfile', 'simple_unidoc_merged.txt' )
        ! setup the environment for distributed execution
        call qenv%new(p_master)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! schedule & clean
        call qenv%gen_scripts_and_schedule_jobs(p_master, job_descr, algnfbody=UNIDOCFBODY)
        ! merge docs
        call xmerge_algndocs%execute( cline_merge_algndocs )
        ! clean
        call qsys_cleanup(p_master)
        ! end gracefully
        call simple_end('**** SIMPLE_DISTR_UNBLUR NORMAL STOP ****')
    end subroutine exec_unblur_distr

    ! UNBLUR TOMOGRAPHIC DDDs

    subroutine exec_unblur_tomo_movies_distr( self, cline )
        use simple_commander_preproc
        use simple_oris, only: oris
        class(unblur_tomo_movies_distr_commander), intent(inout) :: self
        class(cmdline),                            intent(inout) :: cline
        character(len=STDLEN), allocatable :: tomonames(:), tiltnames(:)
        type(oris)               :: exp_doc
        integer                  :: nseries, ipart, numlen
        type(qsys_env)           :: qenv
        type(params)             :: p_master
        character(len=KEYLEN)    :: str
        type(chash)              :: job_descr
        type(chash), allocatable :: part_params(:)
        ! make master parameters
        call cline%set('prg', 'unblur')
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
            str = real2str(exp_doc%get(ipart,'exp_time'))
            call part_params(ipart)%set('exp_time', trim(str))
            str = real2str(exp_doc%get(ipart,'dose_rate'))
            call part_params(ipart)%set('dose_rate', trim(str))
        end do
        ! setup the environment for distributed execution
        call qenv%new(p_master)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! schedule & clean
        call qenv%gen_scripts_and_schedule_jobs(p_master, job_descr, part_params=part_params)
        call qsys_cleanup(p_master)
        call simple_end('**** SIMPLE_DISTR_UNBLUR_TOMO_MOVIES NORMAL STOP ****')
    end subroutine exec_unblur_tomo_movies_distr

    ! CTFFIND

    subroutine exec_ctffind_distr( self, cline )
        class(ctffind_distr_commander), intent(inout) :: self
        class(cmdline),                 intent(inout) :: cline
        type(merge_algndocs_commander) :: xmerge_algndocs
        type(cmdline)                  :: cline_merge_algndocs
        type(params)                   :: p_master
        character(len=KEYLEN)          :: str
        type(chash)                    :: job_descr
        type(qsys_env)                 :: qenv
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        p_master%nptcls = nlines(p_master%filetab)
        if( p_master%nparts > p_master%nptcls ) stop 'nr of partitions (nparts) mjust be < number of entries in filetable'
        ! prepare merge_algndocs command line
        cline_merge_algndocs = cline
        call cline_merge_algndocs%set( 'nthr', 1. )
        call cline_merge_algndocs%set( 'fbody',  'ctffind_output_part')
        call cline_merge_algndocs%set( 'nptcls', real(p_master%nptcls) )
        call cline_merge_algndocs%set( 'ndocs',  real(p_master%nparts) )
        call cline_merge_algndocs%set( 'outfile', 'ctffind_output_merged.txt' )
        ! setup the environment for distributed execution
        call qenv%new(p_master)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! schedule
        call qenv%gen_scripts_and_schedule_jobs(p_master, job_descr)
        ! merge docs
        call xmerge_algndocs%execute( cline_merge_algndocs )
        ! clean
        call qsys_cleanup(p_master)
        call simple_end('**** SIMPLE_DISTR_CTFFIND NORMAL STOP ****')
    end subroutine exec_ctffind_distr

    ! PICKER

    subroutine exec_pick_distr( self, cline )
        use simple_commander_preproc
        class(pick_distr_commander), intent(inout) :: self
        class(cmdline),              intent(inout) :: cline
        type(qsys_env) :: qenv
        type(params)   :: p_master
        type(chash)    :: job_descr
        integer        :: numlen
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        p_master%nptcls = nlines(p_master%filetab)
        if( p_master%nparts > p_master%nptcls ) stop 'nr of partitions (nparts) mjust be < number of entries in filetable'
        ! setup the environment for distributed execution
        call qenv%new(p_master)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! schedule & clean
        call qenv%gen_scripts_and_schedule_jobs(p_master, job_descr)
        call qsys_cleanup(p_master)        
        call simple_end('**** SIMPLE_DISTR_PICK NORMAL STOP ****')
    end subroutine exec_pick_distr

    ! PARALLEL CLASS AVERAGE GENERATION

    subroutine exec_makecavgs_distr( self, cline )
        use simple_commander_prime2D
        use simple_commander_distr
        use simple_commander_mask
        class(makecavgs_distr_commander), intent(inout) :: self
        class(cmdline),                   intent(inout) :: cline
        logical, parameter    :: DEBUG=.false.
        type(split_commander) :: xsplit
        type(cmdline)         :: cline_cavgassemble
        type(qsys_env)        :: qenv
        type(params)          :: p_master
        type(chash)           :: job_descr
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        ! setup the environment for distributed execution
        call qenv%new(p_master)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! prepare command lines from prototype master
        cline_cavgassemble   = cline
        call cline_cavgassemble%set('nthr',1.)
        call cline_cavgassemble%set('prg', 'cavgassemble')
        if( .not. cline%defined('oritab') )then
            call cline_cavgassemble%set('oritab', 'prime2D_startdoc.txt')
        endif
        ! split stack
        if( stack_is_split(p_master%ext, p_master%nparts) )then
            ! check that the stack partitions are of correct sizes
            call stack_parts_of_correct_sizes(p_master%ext, qenv%parts, p_master%box)
        else
            call xsplit%execute(cline)
        endif
        ! schedule
        call qenv%gen_scripts_and_schedule_jobs(p_master, job_descr)
        ! assemble class averages
        call qenv%exec_simple_prg_in_queue(cline_cavgassemble, 'CAVGASSEMBLE', 'CAVGASSEMBLE_FINISHED')
        call qsys_cleanup(p_master)
        call simple_end('**** SIMPLE_DISTR_MAKECAVGS NORMAL STOP ****', print_simple=.false.)
    end subroutine exec_makecavgs_distr

    ! PRIME2D

    subroutine exec_prime2D_distr( self, cline )
        use simple_commander_prime2D ! use all in there
        use simple_commander_distr   ! use all in there
        use simple_commander_mask    ! use all in there
        use simple_commander_imgproc, only: scale_commander
        use simple_magic_boxes,       only: autoscale
        use simple_procimgfile,       only: random_selection_from_imgfile
        use simple_oris,              only: oris
        use simple_strings,           only: str_has_substr
        use simple_image,             only: image
        class(prime2D_distr_commander), intent(inout) :: self
        class(cmdline),                 intent(inout) :: cline
        ! constants
        logical,               parameter :: DEBUG           = .true.
        character(len=32),     parameter :: ALGNFBODY       = 'algndoc_'
        character(len=32),     parameter :: ITERFBODY       = 'prime2Ddoc_'
        character(len=32),     parameter :: CAVGS_ITERFBODY = 'cavgs_iter'
        real,                  parameter :: MSK_FRAC        = 0.06
        real,                  parameter :: MINSHIFT        = 2.0
        real,                  parameter :: MAXSHIFT        = 6.0
        character(len=STDLEN), parameter :: STKSCALEDBODY   = 'stk_sc_prime2D'
        ! commanders
        type(scale_commander)           :: xscale
        type(check2D_conv_commander)    :: xcheck2D_conv
        type(rank_cavgs_commander)      :: xrank_cavgs
        type(merge_algndocs_commander)  :: xmerge_algndocs
        type(split_commander)           :: xsplit
        type(automask2D_commander)      :: xautomask2D
        type(makecavgs_distr_commander) :: xmakecavgs
        ! command lines
        type(cmdline)         :: cline_scale
        type(cmdline)         :: cline_check2D_conv
        type(cmdline)         :: cline_cavgassemble
        type(cmdline)         :: cline_rank_cavgs
        type(cmdline)         :: cline_merge_algndocs
        type(cmdline)         :: cline_automask2D
        type(cmdline)         :: cline_makecavgs
        ! other variables
        type(qsys_env)        :: qenv
        type(params)          :: p_master
        character(len=STDLEN) :: refs, oritab, str, str_iter, native_stk
        real                  :: smpd_sc, msk_sc, scale, native_smpd, native_msk
        real, allocatable     :: res_native(:), res_scaled(:)
        integer               :: iter, i, box_sc, native_box
        type(chash)           :: job_descr
        type(image)           :: img_native, img_scaled
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        ! setup the environment for distributed execution
        call qenv%new(p_master)
        
        if( p_master%l_autoscale )then
            ! prepare for down-scaling
            native_stk  = p_master%stk
            native_smpd = p_master%smpd
            native_msk  = p_master%msk
            native_box  = p_master%box
            cline_scale = cline
            call autoscale(p_master%box, p_master%smpd, box_sc, smpd_sc, scale)
            msk_sc = scale * p_master%msk
            call cline_scale%set('newbox', real(box_sc))
            call cline_scale%set('outstk', trim(STKSCALEDBODY)//p_master%ext)
            p_master%stk  = trim(STKSCALEDBODY)//p_master%ext
            p_master%smpd = smpd_sc
            p_master%msk  = msk_sc
            p_master%box  = box_sc
            call cline%set('stk',  trim(p_master%stk))
            call cline%set('smpd', p_master%smpd)
            call cline%set('msk',  p_master%msk)
            ! needed for mapping the shell-weights to the native sampling
            call img_native%new([native_box,native_box,1], native_smpd)
            call img_scaled%new([box_sc,box_sc,1], smpd_sc)
            res_native = img_native%get_res()
            res_scaled = img_scaled%get_res()
            call img_native%kill
            call img_scaled%kill
        endif

        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! initialise starting references, orientations
        if( cline%defined('oritab') )then
            oritab=trim(p_master%oritab)
        else
            oritab=''
        endif
        if( cline%defined('refs') )then
            refs = trim(p_master%refs)
        else
            refs = trim('start2Drefs' // p_master%ext)
        endif

        ! prepare command lines from prototype master
        cline_check2D_conv   = cline
        cline_cavgassemble   = cline
        cline_rank_cavgs     = cline
        cline_merge_algndocs = cline
        cline_automask2D     = cline
        cline_makecavgs      = cline

        ! initialise static command line parameters and static job description parameters
        call cline_merge_algndocs%set('fbody',  ALGNFBODY)
        call cline_merge_algndocs%set('nptcls', real(p_master%nptcls))
        call cline_merge_algndocs%set('ndocs', real(p_master%nparts))
        call cline_check2D_conv%set('box', real(p_master%box))
        call cline_check2D_conv%set('nptcls', real(p_master%nptcls))
        call cline_cavgassemble%set('prg', 'cavgassemble')
        if( .not. cline%defined('refs') .and. job_descr%isthere('automsk') ) call job_descr%delete('automsk')

        if( p_master%l_autoscale )then
            if( .not. file_exists(trim(STKSCALEDBODY)//p_master%ext) )then
                write(*,'(A)') '>>>'
                write(*,'(A)') '>>> AUTO-SCALING IMAGES'
                write(*,'(A)') '>>>'
                call xscale%execute(cline_scale)
            endif
        endif
        ! split stack
        if( stack_is_split(p_master%ext, p_master%nparts) )then
            ! check that the stack partitions are of correct sizes
            call stack_parts_of_correct_sizes(p_master%ext, qenv%parts, p_master%box)
        else
            call xsplit%execute(cline)
        endif
        ! execute initialiser
        if( .not. cline%defined('refs') )then
            p_master%refs = 'start2Drefs'//p_master%ext
            call random_selection_from_imgfile(p_master%stk, p_master%refs, p_master%ncls, p_master%smpd)
        endif
        if( cline%defined('extr_thresh') )then
            ! all is well
        else
            ! starts from the top
            p_master%extr_thresh = EXTRINITHRESH / p_master%rrate
            if( p_master%startit > 1 )then
                ! need to update the randomization rate
                do i=1,p_master%startit-1
                     p_master%extr_thresh = p_master%extr_thresh * p_master%rrate
                end do
            endif
        endif

        ! main loop
        iter = p_master%startit - 1
        do
            iter = iter+1
            str_iter = int2str_pad(iter,3)
            write(*,'(A)')   '>>>'
            write(*,'(A,I6)')'>>> ITERATION ', iter
            write(*,'(A)')   '>>>'
            ! exponential cooling of the randomization rate
            p_master%extr_thresh = p_master%extr_thresh * p_master%rrate
            call job_descr%set('extr_thresh', real2str(p_master%extr_thresh))
            call cline%set('extr_thresh', p_master%extr_thresh)
            if( oritab .ne. '' ) call job_descr%set('oritab',  trim(oritab))
            call job_descr%set('refs',    trim(refs))
            call job_descr%set('startit', int2str(iter))
            ! schedule
            call qenv%gen_scripts_and_schedule_jobs(p_master, job_descr, algnfbody=ALGNFBODY)
            ! merge orientation documents
            oritab=trim(ITERFBODY)// trim(str_iter) //'.txt'
            call cline_merge_algndocs%set('outfile', trim(oritab))
            call xmerge_algndocs%execute(cline_merge_algndocs)
            ! assemble class averages
            refs = trim(trim(CAVGS_ITERFBODY)// trim(str_iter) //p_master%ext)
            call cline_cavgassemble%set('oritab', trim(oritab))
            call cline_cavgassemble%set('which_iter', real(iter))
            call qenv%exec_simple_prg_in_queue(cline_cavgassemble, 'CAVGASSEMBLE', 'CAVGASSEMBLE_FINISHED')
            ! check convergence
            call cline_check2D_conv%set('oritab', trim(oritab))
            call cline_check2D_conv%set('lp',     real(p_master%lp)) ! may be subjected to iter-dependent update in future
            call xcheck2D_conv%execute(cline_check2D_conv)
            ! this activates shifting & automasking if frac >= 80
            if( cline_check2D_conv%defined('trs') .and. .not.job_descr%isthere('trs') )then
                ! activates shift search
                str = real2str(cline_check2D_conv%get_rarg('trs'))
                call job_descr%set('trs', trim(str) )
                if( cline%defined('automsk') )then
                    ! activates masking
                    if( cline%get_carg('automsk') .ne. 'no' ) call job_descr%set('automsk','yes')
                endif
            endif
            if( cline_check2D_conv%get_carg('converged').eq.'yes' .or. iter==p_master%maxits ) exit
        end do
        call qsys_cleanup(p_master)

        if( p_master%l_autoscale )then
            write(*,'(A)') '>>>'
            write(*,'(A)') '>>> GENERATING CLASS AVERAGES AT NATIVE SAMPLING'
            write(*,'(A)') '>>>'
            ! re-split stack
            call del_files('stack_part', p_master%nparts, ext=p_master%ext)
            call cline%set('stk',        native_stk)
            call cline%set('smpd',       native_smpd)
            call xsplit%execute(cline)

            ! setup and re-sample shellweights
            ! call setup_shellweights_from_parts( p, doshellweight, wmat, res_calc, res_target )

            
            
            ! pepare makecavgs command line
            cline_makecavgs = cline
            call cline_makecavgs%set('prg',     'makecavgs')
            call cline_makecavgs%set('stk',     native_stk)
            call cline_makecavgs%set('smpd',    native_smpd)
            call cline_makecavgs%set('msk',     native_msk)
            call cline_makecavgs%set('oritab',  trim(oritab))
            call cline_makecavgs%set('mul',     1./scale)
            call cline_makecavgs%set('refs',    'prime2Dcavgs_final'//p_master%ext)
            call cline_makecavgs%set('outfile', 'prime2Ddoc_final.txt')
            ! execute
            call xmakecavgs%execute(cline_makecavgs)
            ! cleanup
            call del_files('stack_part', p_master%nparts, ext=p_master%ext)
        else
            call rename(trim(oritab), 'prime2Dcavgs_final'//p_master%ext)
            call rename(trim(refs),   'prime2Ddoc_final.txt')
        endif
        ! ranking
        call cline_rank_cavgs%set('oritab', 'prime2Ddoc_final.txt')
        call cline_rank_cavgs%set('stk',    'prime2Dcavgs_final'//p_master%ext)
        call cline_rank_cavgs%set('outstk', trim('prime2Dcavgs_final_ranked'//p_master%ext))
        call xrank_cavgs%execute( cline_rank_cavgs )
        ! end gracefully
        call simple_end('**** SIMPLE_DISTR_PRIME2D NORMAL STOP ****')
    end subroutine exec_prime2D_distr

    ! PRIME2D CHUNK-BASED DISTRIBUTION 

    subroutine exec_prime2D_chunk_distr( self, cline )
        use simple_commander_prime2D ! use all in there
        use simple_commander_distr   ! use all in there
        use simple_commander_mask    ! use all in there
        use simple_commander_imgproc, only: stack_commander, scale_commander
        use simple_magic_boxes,       only: autoscale
        use simple_oris,              only: oris
        use simple_ori,               only: ori
        use simple_strings,           only: str_has_substr
        class(prime2D_chunk_distr_commander), intent(inout) :: self
        class(cmdline),                       intent(inout) :: cline
        character(len=STDLEN), parameter   :: CAVGNAMES     = 'prime2Dcavgs_final.txt'
        character(len=STDLEN), parameter   :: STKSCALEDBODY = 'stk_sc_prime2D'
        character(len=STDLEN), allocatable :: final_docs(:), final_cavgs(:)
        character(len=STDLEN)              :: chunktag, native_stk
        type(scale_commander)              :: xscale
        type(split_commander)              :: xsplit
        type(makecavgs_distr_commander)    :: xmakecavgs
        type(stack_commander)              :: xstack
        type(rank_cavgs_commander)         :: xrank_cavgs
        type(cmdline)                      :: cline_scale
        type(cmdline)                      :: cline_stack
        type(cmdline)                      :: cline_makecavgs
        type(cmdline)                      :: cline_rank_cavgs
        type(qsys_env)                     :: qenv
        type(params)                       :: p_master
        type(chash), allocatable           :: part_params(:)
        type(chash)                        :: job_descr
        type(oris)                         :: os
        real    :: smpd_sc, msk_sc, scale, native_smpd, native_msk
        integer :: ipart, numlen, nl, ishift, nparts, npart_params, native_box, box_sc
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        ! determine the number of partitions
        nparts = nint(real(p_master%nptcls)/real(p_master%chunksz))
        numlen = len(int2str(nparts))
        call cline%set('nparts', real(nparts))
        call cline%set('numlen', real(numlen))
        ! re-make the master parameters to accomodate nparts/numlen
        p_master = params(cline, checkdistr=.false.)
        ! setup the environment for distributed execution
        call qenv%new(p_master)

        if( p_master%l_autoscale )then
            ! prepare for down-scaling
            native_stk  = p_master%stk
            native_smpd = p_master%smpd
            native_msk  = p_master%msk
            native_box  = p_master%box
            cline_scale = cline
            call autoscale(p_master%box, p_master%smpd, box_sc, smpd_sc, scale)
            msk_sc = scale * p_master%msk
            call cline_scale%set('newbox', real(box_sc))
            call cline_scale%set('outstk', trim(STKSCALEDBODY)//p_master%ext)
            p_master%stk  = trim(STKSCALEDBODY)//p_master%ext
            p_master%smpd = smpd_sc
            p_master%msk  = msk_sc
            p_master%box  = box_sc
            call cline%set('stk',  trim(p_master%stk))
            call cline%set('smpd', p_master%smpd)
            call cline%set('msk',  p_master%msk)
        endif

        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! prepare part-dependent parameters and docs
        npart_params = 3
        if( cline%defined('deftab') .and. cline%defined('oritab') )then
            stop 'ERROR, deftab or oritab can be part of of command line, not both; exec_prime2D_chunk_distr'
        else if( cline%defined('deftab') .or. cline%defined('oritab') )then
            npart_params = npart_params + 1
        endif
        allocate(part_params(p_master%nparts))
        ishift = 0
        do ipart=1,p_master%nparts
            call part_params(ipart)%new(npart_params)
            chunktag = 'chunk'//int2str_pad(ipart,numlen)
            call part_params(ipart)%set('chunk',    int2str(ipart))
            call part_params(ipart)%set('chunktag', chunktag)
            call part_params(ipart)%set('stk', 'stack_part'//int2str_pad(ipart,numlen)//p_master%ext)
            if( cline%defined('deftab') )then
                call read_part_and_write(qenv%parts(ipart,:), p_master%deftab, trim(chunktag)//'deftab.txt')
                call part_params(ipart)%set('deftab', trim(chunktag)//'deftab.txt')
            endif
            if( cline%defined('oritab') )then
                call read_part_and_write(qenv%parts(ipart,:), p_master%oritab, trim(chunktag)//'oritab.txt', ishift)
                call part_params(ipart)%set('oritab', trim(chunktag)//'oritab.txt')
                ishift = ishift - p_master%ncls
            endif
        end do

        if( p_master%l_autoscale )then
            if( .not. file_exists(trim(STKSCALEDBODY)//p_master%ext) )then
                write(*,'(A)') '>>>'
                write(*,'(A)') '>>> AUTO-SCALING IMAGES'
                write(*,'(A)') '>>>'
                call xscale%execute(cline_scale)
            endif
        endif
        ! split stack
        if( stack_is_split(p_master%ext, p_master%nparts) )then
            ! check that the stack partitions are of correct sizes
            call stack_parts_of_correct_sizes(p_master%ext, qenv%parts, p_master%box)
        else
            call xsplit%execute(cline)
        endif
        ! schedule & clean
        call qenv%gen_scripts_and_schedule_jobs(p_master, job_descr, part_params=part_params, chunkdistr=.true.)
        call qsys_cleanup(p_master)
        ! merge final stacks of cavgs and orientation documents
        allocate(final_docs(p_master%nparts), final_cavgs(p_master%nparts))
        ishift = 0
        do ipart=1,p_master%nparts
            chunktag = 'chunk'//int2str_pad(ipart,numlen)
            final_cavgs(ipart) = sys_get_last_fname(trim(chunktag)//'cavgs_iter', p_master%ext)
            final_docs(ipart)  = sys_get_last_fname(trim(chunktag)//'prime2Ddoc_', 'txt')
            if( ipart > 1 )then
                ! the class indices need to be shifted by p%ncls
                ishift = ishift + p_master%ncls
                ! modify the doc accordingly
                nl = nlines(final_docs(ipart))
                call os%new(nl)
                call os%read(final_docs(ipart))
                call os%shift_classes(ishift)
                call os%write(final_docs(ipart))
            endif
        end do
        ! merge docs
        call sys_merge_docs(final_docs, 'temp_prime2Ddoc_merged.txt')
        
        if( p_master%l_autoscale )then
            write(*,'(A)') '>>>'
            write(*,'(A)') '>>> GENERATING CLASS AVERAGES AT NATIVE SAMPLING'
            write(*,'(A)') '>>>'
            ! re-split stack
            call del_files('stack_part', p_master%nparts, ext=p_master%ext)
            call cline%set('stk',        native_stk)
            call cline%set('smpd',       native_smpd)
            call xsplit%execute(cline)
            ! pepare makecavgs command line
            call cline_makecavgs%set('prg',     'makecavgs')
            call cline_makecavgs%set('stk',     native_stk)
            call cline_makecavgs%set('smpd',    native_smpd)
            call cline_makecavgs%set('msk',     native_msk)
            call cline_makecavgs%set('oritab',  'temp_prime2Ddoc_merged.txt')
            call cline_makecavgs%set('mul',     1./scale)
            call cline_makecavgs%set('refs',    'prime2Dcavgs_final'//p_master%ext)
            call cline_makecavgs%set('outfile', 'prime2Ddoc_final.txt')
            ! execute
            call xmakecavgs%execute(cline_makecavgs)
            ! cleanup
            call del_files('stack_part', p_master%nparts, ext=p_master%ext)
            call del_file('temp_prime2Ddoc_merged.txt')
        else
            ! merge class averages
            call write_filetable(CAVGNAMES, final_cavgs)
            call cline_stack%set('filetab', CAVGNAMES)
            call cline_stack%set('outstk', 'prime2Dcavgs_final'//p_master%ext)
            call xstack%execute(cline_stack)
            ! cleanup
            call rename('temp_prime2Ddoc_merged.txt', 'prime2Ddoc_final.txt')
            call del_file(CAVGNAMES)
        endif
        ! ranking
        call cline_rank_cavgs%set('oritab', 'prime2Ddoc_final.txt')
        call cline_rank_cavgs%set('stk',    'prime2Dcavgs_final'//p_master%ext)
        call cline_rank_cavgs%set('outstk', trim('prime2Dcavgs_final_ranked'//p_master%ext))
        ! end gracefully
        call simple_end('**** SIMPLE_DISTR_PRIME2D_CHUNK NORMAL STOP ****')

        contains

            subroutine read_part_and_write( pfromto, file_in, file_out, ishift )
                integer,           intent(in) :: pfromto(2)
                character(len=*),  intent(in) :: file_in, file_out
                integer, optional, intent(in) :: ishift
                integer    :: nl, cnt, i
                type(oris) :: os_in, os_out
                type(ori)  :: o
                nl = nlines(file_in)
                call os_in%new(nl)
                call os_in%read(file_in)
                call os_out%new(pfromto(2) - pfromto(1) + 1)
                cnt = 0
                do i=pfromto(1),pfromto(2)
                    cnt = cnt + 1
                    o   = os_in%get_ori(i)
                    call os_out%set_ori(cnt, o)
                end do
                if( present(ishift) ) call os_out%shift_classes(ishift)
                call os_out%write(file_out)
            end subroutine read_part_and_write

    end subroutine exec_prime2D_chunk_distr

    ! PRIME3D_INIT

    subroutine exec_prime3D_init_distr( self, cline )
        use simple_commander_prime3D
        use simple_commander_rec
        class(prime3D_init_distr_commander), intent(inout) :: self
        class(cmdline),                      intent(inout) :: cline
        logical, parameter    :: debug=.false.
        type(split_commander) :: xsplit
        type(cmdline)         :: cline_volassemble
        type(qsys_env)        :: qenv
        type(params)          :: p_master
        character(len=STDLEN) :: vol
        type(chash)           :: job_descr
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        ! setup the environment for distributed execution
        call qenv%new(p_master)
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
            call stack_parts_of_correct_sizes(p_master%ext, qenv%parts, p_master%box)
        else
            call xsplit%execute( cline )
        endif
        ! prepare command lines from prototype master
        cline_volassemble = cline
        call cline_volassemble%set( 'outvol',  vol                  )
        call cline_volassemble%set( 'eo',     'no'                  )
        call cline_volassemble%set( 'prg',    'volassemble'         )
        call cline_volassemble%set( 'oritab', 'prime3D_startdoc.txt')
        call qenv%gen_scripts_and_schedule_jobs(p_master, job_descr)
        call qenv%exec_simple_prg_in_queue(cline_volassemble, 'VOLASSEMBLE', 'VOLASSEMBLE_FINISHED')
        call qsys_cleanup(p_master)
        call simple_end('**** SIMPLE_DISTR_PRIME3D_INIT NORMAL STOP ****', print_simple=.false.)
    end subroutine exec_prime3D_init_distr

    ! PRIME3D

    subroutine exec_prime3D_distr( self, cline )
        use simple_commander_prime3D
        use simple_commander_mask
        use simple_commander_rec
        use simple_commander_volops
        use simple_oris, only: oris
        use simple_math, only: calc_fourier_index, calc_lowpass_lim
        class(prime3D_distr_commander), intent(inout) :: self
        class(cmdline),                 intent(inout) :: cline
        ! constants
        logical,           parameter :: DEBUG=.false.
        character(len=32), parameter :: ALGNFBODY    = 'algndoc_'
        character(len=32), parameter :: ITERFBODY    = 'prime3Ddoc_'
        character(len=32), parameter :: VOLFBODY     = 'recvol_state'
        character(len=32), parameter :: RESTARTFBODY = 'prime3D_restart'
        ! commanders
        type(prime3D_init_distr_commander)  :: xprime3D_init_distr
        type(shellweight3D_distr_commander) :: xshellweight3D_distr
        type(recvol_distr_commander)        :: xrecvol_distr
        type(resrange_commander)            :: xresrange
        type(merge_algndocs_commander)      :: xmerge_algndocs
        type(check3D_conv_commander)        :: xcheck3D_conv
        type(split_commander)               :: xsplit
        type(postproc_vol_commander)        :: xpostproc_vol
        ! command lines
        type(cmdline)         :: cline_recvol_distr
        type(cmdline)         :: cline_prime3D_init
        type(cmdline)         :: cline_resrange
        type(cmdline)         :: cline_check3D_conv
        type(cmdline)         :: cline_merge_algndocs
        type(cmdline)         :: cline_volassemble
        type(cmdline)         :: cline_shellweight3D
        type(cmdline)         :: cline_postproc_vol
        ! other variables
        type(qsys_env)        :: qenv
        type(params)          :: p_master
        type(chash)           :: job_descr
        type(oris)            :: os
        character(len=STDLEN) :: vol, vol_iter, oritab, str, str_iter
        character(len=STDLEN) :: str_state, fsc_file, volassemble_output
        character(len=STDLEN) :: restart_file
        real                  :: frac_srch_space
        integer               :: s, state, iter, i
        logical               :: vol_defined
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        ! make oritab
        call os%new(p_master%nptcls)
        ! options check
        !if( p_master%automsk.eq.'yes' )stop 'Automasking not supported yet' ! automask deactivated for now
        if( p_master%nstates>1 .and. p_master%dynlp.eq.'yes' )&
            &stop 'Incompatible options: nstates>1 and dynlp=yes'
        if( p_master%automsk.eq.'yes' .and. p_master%dynlp.eq.'yes' )&
            &stop 'Incompatible options: automsk=yes and dynlp=yes'
        if( p_master%eo.eq.'yes' .and. p_master%dynlp.eq.'yes' )&
            &stop 'Incompatible options: eo=yes and dynlp=yes'
        ! setup the environment for distributed execution
        call qenv%new(p_master)
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
        cline_shellweight3D  = cline
        cline_postproc_vol   = cline
        ! initialise static command line parameters and static job description parameter
        call cline_recvol_distr%set( 'prg', 'recvol' )       ! required for distributed call
        call cline_prime3D_init%set( 'prg', 'prime3D_init' ) ! required for distributed call
        call cline_shellweight3D%set('prg', 'shellweight3D') ! required for distributed call
        call cline_merge_algndocs%set( 'nthr', 1. )
        call cline_merge_algndocs%set( 'fbody',  ALGNFBODY)
        call cline_merge_algndocs%set( 'nptcls', real(p_master%nptcls) )
        call cline_merge_algndocs%set( 'ndocs',  real(p_master%nparts) )
        call cline_check3D_conv%set( 'box',    real(p_master%box))
        call cline_check3D_conv%set( 'nptcls', real(p_master%nptcls))
        call cline_volassemble%set( 'nthr', 1. )
        call cline_postproc_vol%set( 'nstates', 1. )
        ! removes unnecessary volume keys
        do state = 1,p_master%nstates
            vol = 'vol'//int2str( state )
            call cline_check3D_conv%delete( trim(vol) )
            call cline_merge_algndocs%delete( trim(vol) )
            call cline_volassemble%delete( trim(vol) )
        enddo
        ! SPLIT STACK
        if( stack_is_split(p_master%ext, p_master%nparts) )then
            ! check that the stack partitions are of correct sizes
            call stack_parts_of_correct_sizes(p_master%ext, qenv%parts, p_master%box)
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
        vol_defined = .false.
        do state = 1,p_master%nstates
            vol = 'vol' // int2str(state)
            if( cline%defined(trim(vol)) )vol_defined = .true.
        enddo
        if( .not.cline%defined('oritab') .and. .not.vol_defined )then
            ! ab-initio
            call xprime3D_init_distr%execute( cline_prime3D_init )
            call cline%set( 'vol1', trim('startvol_state01'//p_master%ext) )
            call cline%set( 'oritab', oritab )
        else if( cline%defined('oritab') .and. .not.vol_defined )then
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
                call cline_shellweight3D%set( trim(vol), trim(str) )
            enddo
        else if( .not.cline%defined('oritab') .and. vol_defined )then
            ! projection matching
            select case( p_master%refine )
                case( 'neigh', 'shcneigh', 'shift' )
                    stop 'refinement method requires input orientation document'
                case DEFAULT
                    ! refine=no|shc, all good?
            end select
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
            p_master%find = calc_fourier_index(p_master%lpstart, p_master%box, p_master%smpd)
            p_master%lp   = p_master%lpstart
            call cline_check3D_conv%set( 'update_res', 'no' )
            call cline_check3D_conv%set( 'find', real(p_master%find) )
            call cline%set( 'find', real(p_master%find) )
        endif
        ! EXTREMAL DYNAMICS
        if( cline%defined('extr_thresh') )then
            ! all is well
        else
            ! starts from the top
            p_master%extr_thresh = EXTRINITHRESH / p_master%rrate
            if( p_master%startit > 1 )then
                ! need to update the randomization rate
                do i=1,p_master%startit-1
                     p_master%extr_thresh = p_master%extr_thresh * p_master%rrate
                end do
            endif
        endif
        ! prepare Prime3D job description
        call cline%gen_job_descr(job_descr)
        ! MAIN LOOP
        iter = p_master%startit-1
        do
            iter = iter+1
            str_iter = int2str_pad(iter,3)
            write(*,'(A)')   '>>>'
            write(*,'(A,I6)')'>>> ITERATION ', iter
            write(*,'(A)')   '>>>'
            if( cline%defined('oritab') )then
                call os%read(trim(cline%get_carg('oritab')))
                frac_srch_space = os%get_avg('frac')
                call job_descr%set( 'oritab', trim(oritab) )
                call cline_shellweight3D%set( 'oritab', trim(oritab) )
                if( p_master%l_shellw .and. frac_srch_space >= SHW_FRAC_LIM  )then
                    call xshellweight3D_distr%execute(cline_shellweight3D)
                endif
            endif
            ! exponential cooling of the randomization rate
            p_master%extr_thresh = p_master%extr_thresh * p_master%rrate
            call job_descr%set('extr_thresh', real2str(p_master%extr_thresh))
            call cline%set('extr_thresh', p_master%extr_thresh)
            call job_descr%set( 'startit', trim(int2str(iter)) )
            call cline%set( 'startit', real(iter) )
            ! schedule
            call qenv%gen_scripts_and_schedule_jobs(p_master, job_descr, algnfbody=ALGNFBODY)
            ! ASSEMBLE ALIGNMENT DOCS
            oritab = trim(ITERFBODY)//trim(str_iter)//'.txt'    
            call cline%set( 'oritab', oritab )
            call cline_shellweight3D%set( 'oritab', trim(oritab) )
            call cline_merge_algndocs%set( 'outfile', trim(oritab) )
            call xmerge_algndocs%execute( cline_merge_algndocs )
            if( p_master%norec .eq. 'yes' )then
                ! RECONSTRUCT VOLUMES
                call cline_recvol_distr%set( 'oritab', trim(oritab) )
                do state = 1,p_master%nstates
                    call cline_recvol_distr%delete('state')
                    call cline_recvol_distr%set('state', real(state))
                    call xrecvol_distr%execute( cline_recvol_distr )
                end do
                call cline_recvol_distr%delete('state')
            else
                ! ASSEMBLE VOLUMES
                call cline_volassemble%set( 'oritab', trim(oritab) )
                if( p_master%eo.eq.'yes' )then
                    do state = 1,p_master%nstates
                        str_state = int2str_pad(state,2)
                        call del_file('fsc_state'//trim(str_state)//'.bin')
                    enddo
                    call cline_volassemble%set( 'prg', 'eo_volassemble' ) ! required for cmdline exec
                else
                    call cline_volassemble%set( 'prg', 'volassemble' )    ! required for cmdline exec
                endif
                if( p_master%eo .eq. 'yes' )then
                    volassemble_output = 'RESOLUTION'//trim(str_iter)
                else
                    volassemble_output = 'VOLASSEMBLE'
                endif
                call qenv%exec_simple_prg_in_queue(cline_volassemble,&
                &trim(volassemble_output), 'VOLASSEMBLE_FINISHED')
            endif
            ! rename volumes, postprocess & update job_descr
            call os%read(trim(oritab))
            do state = 1,p_master%nstates
                str_state = int2str_pad(state,2)
                if( os%get_statepop( state ) == 0 )then
                    ! cleanup for empty state
                    vol = 'vol'//trim(int2str(state))
                    call cline%delete( vol )
                    call job_descr%delete( trim(vol) )
                    call cline_shellweight3D%delete( trim(vol) )
                else
                    if( p_master%nstates>1 )then
                        ! cleanup postprocessing cmdline as it only takes one volume at a time
                        do s = 1,p_master%nstates
                            vol = 'vol'//int2str(s)
                            call cline_postproc_vol%delete( trim(vol) )
                        enddo
                    endif
                    ! rename state volume
                    vol       = trim(VOLFBODY)//trim(str_state)//p_master%ext
                    vol_iter  = trim(VOLFBODY)//trim(str_state)//'_iter'//trim(str_iter)//p_master%ext
                    call rename( trim(vol), trim(vol_iter) )
                    ! post-process
                    vol = 'vol'//trim(int2str(state))
                    call cline_postproc_vol%set( 'vol1' , trim(vol_iter))
                    fsc_file = 'fsc_state'//trim(str_state)//'.bin'
                    if( file_exists(fsc_file) .and. p_master%eo .eq. 'yes' )then
                        call cline_postproc_vol%delete('lp')
                        call cline_postproc_vol%set('fsc', trim(fsc_file))
                    else
                        call cline_postproc_vol%delete('fsc')
                        call cline_postproc_vol%set('lp', p_master%lp)
                    endif
                    call xpostproc_vol%execute(cline_postproc_vol)
                    ! updates cmdlines & job description
                    call job_descr%set( trim(vol), trim(vol_iter) )
                    call cline%set( trim(vol), trim(vol_iter) )
                    call cline_shellweight3D%set( trim(vol), trim(vol_iter) )
                endif
            enddo
            ! CONVERGENCE
            call cline_check3D_conv%set( 'oritab', trim(oritab) )
            if(p_master%refine.eq.'het')call cline_check3D_conv%delete('update_res')
            call xcheck3D_conv%execute( cline_check3D_conv )
            if( iter >= p_master%startit+2 )then
                ! after a minimum of 2 iterations
                if( cline_check3D_conv%get_carg('converged') .eq. 'yes' ) exit
            endif
            if( iter >= p_master%maxits ) exit
            ! ITERATION DEPENDENT UPDATES
            if( cline_check3D_conv%defined('trs') .and. .not.job_descr%isthere('trs') )then
                ! activates shift search if frac >= 90
                str = real2str(cline_check3D_conv%get_rarg('trs'))
                call job_descr%set( 'trs', trim(str) )
                call cline%set( 'trs', cline_check3D_conv%get_rarg('trs') )
            endif
            if( p_master%dynlp.eq.'yes' )then
                ! dynamic resolution update
                if( cline_check3D_conv%get_carg('update_res').eq.'yes' )then
                    p_master%find = p_master%find + p_master%fstep  ! fourier index update
                    p_master%lp   = calc_lowpass_lim(p_master%find , p_master%box, p_master%smpd)
                    call cline%set( 'lp', real(p_master%lp) )
                    call job_descr%set( 'find', int2str(p_master%find) )
                    call cline%set( 'find', real(p_master%find) )
                    call cline_check3D_conv%set( 'find', real(p_master%find) )
               endif
            endif
            ! RESTART
            restart_file = trim(RESTARTFBODY)//'_iter'//int2str_pad( iter, 3)//'.txt'
            call cline%write( restart_file )
        end do
        call qsys_cleanup(p_master)
        ! RESTART
        restart_file = trim(RESTARTFBODY)//'_iter'//int2str_pad( iter, 3)//'.txt'
        call cline%write( restart_file )
        ! report the last iteration on exit
        call cline%delete( 'startit' )
        call cline%set('endit', real(iter))
        ! end gracefully
        call simple_end('**** SIMPLE_DISTR_PRIME3D NORMAL STOP ****')
    end subroutine exec_prime3D_distr

    ! CONT3D

    subroutine exec_cont3D_distr( self, cline )
        use simple_commander_prime3D
        use simple_commander_mask
        use simple_commander_rec
        use simple_commander_volops
        use simple_oris, only: oris
        use simple_math, only: calc_fourier_index, calc_lowpass_lim
        class(cont3D_distr_commander), intent(inout) :: self
        class(cmdline),                intent(inout) :: cline
        ! constants
        logical,           parameter :: DEBUG=.false.
        character(len=32), parameter :: ALGNFBODY    = 'algndoc_'
        character(len=32), parameter :: ITERFBODY    = 'cont3Ddoc_'
        character(len=32), parameter :: VOLFBODY     = 'recvol_state'
        character(len=32), parameter :: RESTARTFBODY = 'cont3D_restart'
        ! ! commanders
        type(shellweight3D_distr_commander) :: xshellweight3D_distr
        type(recvol_distr_commander)        :: xrecvol_distr
        type(merge_algndocs_commander)      :: xmerge_algndocs
        type(check3D_conv_commander)        :: xcheck3D_conv
        type(split_commander)               :: xsplit
        type(postproc_vol_commander)        :: xpostproc_vol
        ! command lines
        type(cmdline)         :: cline_recvol_distr
        type(cmdline)         :: cline_check3D_conv
        type(cmdline)         :: cline_merge_algndocs
        type(cmdline)         :: cline_volassemble
        type(cmdline)         :: cline_shellweight3D
        type(cmdline)         :: cline_postproc_vol
        ! other variables
        type(qsys_env)        :: qenv
        type(params)          :: p_master
        type(chash)           :: job_descr
        type(oris)            :: os
        character(len=STDLEN) :: vol, vol_iter, oritab, str, str_iter
        character(len=STDLEN) :: str_state, fsc_file, volassemble_output
        character(len=STDLEN) :: restart_file
        real                  :: frac_srch_space
        integer               :: s, state, iter
        logical               :: vol_defined
        ! ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        ! make oritab
        call os%new(p_master%nptcls)
        ! options check
        if( p_master%automsk.eq.'yes' )stop 'Automasking not supported yet' ! automask deactivated for now
        if( p_master%nstates>1 .and. p_master%dynlp.eq.'yes' )&
            &stop 'Incompatible options: nstates>1 and dynlp=yes'
        if( p_master%automsk.eq.'yes' .and. p_master%dynlp.eq.'yes' )&
            &stop 'Incompatible options: automsk=yes and dynlp=yes'
        ! setup the environment for distributed execution
        call qenv%new(p_master)

        ! initialise
        if( .not. cline%defined('nspace') ) call cline%set('nspace', 1000.)
        call cline%set('box', real(p_master%box))
        ! prepare command lines from prototype master
        cline_recvol_distr   = cline
        cline_check3D_conv   = cline
        cline_merge_algndocs = cline
        cline_volassemble    = cline
        cline_shellweight3D  = cline
        cline_postproc_vol   = cline
        ! initialise static command line parameters and static job description parameter
        call cline_recvol_distr%set( 'prg', 'recvol' )       ! required for distributed call
        call cline_shellweight3D%set('prg', 'shellweight3D') ! required for distributed call
        call cline_merge_algndocs%set( 'nthr', 1. )
        call cline_merge_algndocs%set( 'fbody',  ALGNFBODY)
        call cline_merge_algndocs%set( 'nptcls', real(p_master%nptcls) )
        call cline_merge_algndocs%set( 'ndocs',  real(p_master%nparts) )
        call cline_check3D_conv%set( 'box',    real(p_master%box))
        call cline_check3D_conv%set( 'nptcls', real(p_master%nptcls))
        call cline_volassemble%set( 'nthr', 1. )
        call cline_postproc_vol%set( 'nstates', 1. )
        ! removes unnecessary volume keys
        do state = 1,p_master%nstates
            vol = 'vol'//int2str( state )
            call cline_check3D_conv%delete( trim(vol) )
            call cline_merge_algndocs%delete( trim(vol) )
            call cline_volassemble%delete( trim(vol) )
        enddo
        ! SPLIT STACK
        if( stack_is_split(p_master%ext, p_master%nparts) )then
            ! check that the stack partitions are of correct sizes
            call stack_parts_of_correct_sizes(p_master%ext, qenv%parts, p_master%box)
        else
            call xsplit%execute( cline )
        endif
        ! GENERATE STARTING MODELS & ORIENTATIONS
        ! Orientations
        oritab=trim(p_master%oritab)
        ! Models
        vol_defined = .false.
        do state = 1,p_master%nstates
            vol = 'vol' // int2str(state)
            if( cline%defined(trim(vol)) )vol_defined = .true.
        enddo
        if( .not.vol_defined )then
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
                call cline_shellweight3D%set( trim(vol), trim(str) )
            enddo
        else
            ! all good
        endif
        ! prepare Cont3D job description
        call cline%gen_job_descr(job_descr)
        ! MAIN LOOP
        iter = p_master%startit-1
        do
            iter = iter+1
            str_iter = int2str_pad(iter,3)
            write(*,'(A)')   '>>>'
            write(*,'(A,I6)')'>>> ITERATION ', iter
            write(*,'(A)')   '>>>' 
            call os%read(trim(cline%get_carg('oritab')))
            frac_srch_space = os%get_avg('frac')
            call job_descr%set( 'oritab', trim(oritab) )
            call cline_shellweight3D%set( 'oritab', trim(oritab) )
            if( p_master%l_shellw .and. frac_srch_space >= SHW_FRAC_LIM )then
                call xshellweight3D_distr%execute(cline_shellweight3D)
            endif
            call job_descr%set( 'startit', trim(int2str(iter)) )
            call cline%set( 'startit', real(iter) )
            ! schedule
            call qenv%gen_scripts_and_schedule_jobs(p_master, job_descr, algnfbody=ALGNFBODY)
            ! ASSEMBLE ALIGNMENT DOCS
            oritab = trim(ITERFBODY)//trim(str_iter)//'.txt'    
            call cline%set( 'oritab', oritab )
            call cline_shellweight3D%set('oritab', trim(oritab))
            call cline_merge_algndocs%set('outfile', trim(oritab))
            call xmerge_algndocs%execute(cline_merge_algndocs)
            ! ASSEMBLE VOLUMES
            call cline_volassemble%set( 'oritab', trim(oritab) )
            do state = 1,p_master%nstates
                str_state = int2str_pad(state,2)
                call del_file('fsc_state'//trim(str_state)//'.bin')
            enddo
            call cline_volassemble%set( 'prg', 'eo_volassemble' )
            if( p_master%eo .eq. 'yes' )then
                volassemble_output = 'RESOLUTION'//trim(str_iter)
            else
                volassemble_output = 'VOLASSEMBLE'
            endif
            call qenv%exec_simple_prg_in_queue(cline_volassemble,&
            &trim(volassemble_output), 'VOLASSEMBLE_FINISHED')
            ! rename volumes, postprocess & update job_descr
            call os%read(trim(oritab))
            do state = 1,p_master%nstates
                str_state = int2str_pad(state,2)
                if( os%get_statepop( state ) == 0 )then
                    ! cleanup for empty state
                    vol = 'vol'//trim(int2str(state))
                    call cline%delete( vol )
                    call job_descr%delete( trim(vol) )
                    call cline_shellweight3D%delete( trim(vol) )
                else
                    if( p_master%nstates>1 )then
                        ! cleanup postprocessing cmdline as it only takes one volume at a time
                        do s = 1,p_master%nstates
                            vol = 'vol'//int2str(s)
                            call cline_postproc_vol%delete( trim(vol) )
                        enddo
                    endif
                    ! rename state volume
                    vol       = trim(VOLFBODY)//trim(str_state)//p_master%ext
                    vol_iter  = trim(VOLFBODY)//trim(str_state)//'_iter'//trim(str_iter)//p_master%ext
                    call rename( trim(vol), trim(vol_iter) )
                    ! post-process
                    vol = 'vol'//trim(int2str(state))
                    call cline_postproc_vol%set('vol1' , trim(vol_iter))
                    fsc_file = 'fsc_state'//trim(str_state)//'.bin'
                    call cline_postproc_vol%delete('lp')
                    call cline_postproc_vol%set('fsc', trim(fsc_file))
                    call xpostproc_vol%execute(cline_postproc_vol)
                    ! updates cmdlines & job description
                    call job_descr%set(trim(vol), trim(vol_iter))
                    call cline%set(trim(vol), trim(vol_iter))
                    call cline_shellweight3D%set( trim(vol), trim(vol_iter) )
                endif
            enddo
            ! RESTART
            restart_file = trim(RESTARTFBODY)//'_iter'//int2str_pad( iter, 3)//'.txt'
            call cline%write( restart_file )
            ! CONVERGENCE
            call cline_check3D_conv%set('oritab', trim(oritab))
            call xcheck3D_conv%execute(cline_check3D_conv )
            if( iter >= p_master%startit+2 )then
                ! after a minimum of 2 iterations
                if(cline_check3D_conv%get_carg('converged') .eq. 'yes') exit
            endif
            if( iter >= p_master%maxits ) exit
            ! ITERATION DEPENDENT UPDATES
            ! nothing so far
        end do
        call qsys_cleanup(p_master)
        ! report the last iteration on exit
        call cline%delete('startit')
        call cline%set('endit', real(iter))
        ! end gracefully
        call simple_end('**** SIMPLE_DISTR_CONT3D NORMAL STOP ****')
    end subroutine exec_cont3D_distr

    ! SHELLWEIGHT3D

    subroutine exec_shellweight3D_distr( self, cline )
        use simple_commander_prime3D
        use simple_commander_distr
        class(shellweight3D_distr_commander), intent(inout) :: self
        class(cmdline),                       intent(inout) :: cline
        ! constants
        logical,           parameter       :: DEBUG=.false.
        character(len=32), parameter       :: ALGNFBODY = 'algndoc_'
        ! commanders
        type(split_commander)              :: xsplit
        type(shellweight3D_commander)      :: xshellweight3D
        type(merge_algndocs_commander)     :: xmerge_algndocs
        type(merge_shellweights_commander) :: xmerge_shellweights
        ! other variables
        type(qsys_env) :: qenv
        type(params)   :: p_master
        type(chash)    :: job_descr
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        ! setup the environment for distributed execution
        call qenv%new(p_master)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! split stack
        if( stack_is_split(p_master%ext, p_master%nparts) )then
            ! check that the stack partitions are of correct sizes
            call stack_parts_of_correct_sizes(p_master%ext, qenv%parts, p_master%box)
        else
            call xsplit%execute( cline )
        endif
        ! schedule
        call qenv%gen_scripts_and_schedule_jobs(p_master, job_descr, algnfbody=ALGNFBODY)
        ! merge matrices
        call xmerge_shellweights%execute(cline)
        call qsys_cleanup(p_master)
        call del_files('shellweights_part', p_master%nparts, ext='.bin')
        call simple_end('**** SIMPLE_DISTR_SHELLWEIGHT3D NORMAL STOP ****', print_simple=.false.)
    end subroutine exec_shellweight3D_distr

    ! RECVOL

    subroutine exec_recvol_distr( self, cline )
        use simple_commander_rec
        class(recvol_distr_commander), intent(inout) :: self
        class(cmdline),                intent(inout) :: cline
        logical, parameter                  :: debug=.false.
        type(split_commander)               :: xsplit
        type(shellweight3D_distr_commander) :: xshellweight3D_distr
        type(cmdline)                       :: cline_shellweight3D
        type(qsys_env)                      :: qenv
        type(params)                        :: p_master
        character(len=STDLEN)               :: vol, volassemble_output
        type(chash)                         :: job_descr
        integer                             :: istate
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        ! setup the environment for distributed execution
        call qenv%new(p_master)
        if( p_master%shellw .eq. 'yes' )then
            ! we need to set the prg flag for the command lines that control distributed workflows 
            cline_shellweight3D = cline
            call cline_shellweight3D%set('prg', 'shellweight3D')
            call xshellweight3D_distr%execute(cline_shellweight3D)
        endif
        call cline%gen_job_descr(job_descr)
        ! split stack
        if( stack_is_split(p_master%ext, p_master%nparts) )then
            ! check that the stack partitions are of correct sizes
            call stack_parts_of_correct_sizes(p_master%ext, qenv%parts, p_master%box)
        else
            call xsplit%execute( cline )
        endif
        ! schedule
        call qenv%gen_scripts_and_schedule_jobs(p_master, job_descr)
        ! assemble volumes
        if( p_master%eo .eq. 'yes' )then
            call cline%set('prg', 'eo_volassemble')
            volassemble_output = 'RESOLUTION'
        else
            call cline%set('prg', 'volassemble')
            volassemble_output = 'VOLASSEMBLE'
        endif
        call qenv%exec_simple_prg_in_queue(cline,&
        &trim(volassemble_output), 'VOLASSEMBLE_FINISHED')
        ! termination
        call qsys_cleanup(p_master)
        call simple_end('**** SIMPLE_RECVOL NORMAL STOP ****', print_simple=.false.)
    end subroutine exec_recvol_distr

    ! TIME-SERIES ROUTINES

    subroutine exec_tseries_track_distr( self, cline )
        use simple_commander_tseries, only: tseries_track_commander
        use simple_nrtxtfile,         only: nrtxtfile 
        class(tseries_track_distr_commander), intent(inout) :: self
        class(cmdline),                       intent(inout) :: cline
        logical, parameter            :: debug=.false.
        type(tseries_track_commander) :: xtseries_track
        type(qsys_env)                :: qenv
        type(params)                  :: p_master
        type(chash)                   :: job_descr
        type(nrtxtfile)               :: boxfile
        real,        allocatable      :: boxdata(:,:)
        type(chash), allocatable      :: part_params(:)
        integer :: ndatlines, numlen, alloc_stat, j, orig_box, ipart
        ! make master parameters
        p_master = params(cline, checkdistr=.false.)
        if( .not. file_exists(p_master%boxfile)  ) stop 'inputted boxfile does not exist in cwd'
        if( nlines(p_master%boxfile) > 0 )then
            call boxfile%new(p_master%boxfile, 1)
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
            end do
        else
            stop 'inputted boxfile is empty; simple_commander_tseries :: exec_tseries_track'
        endif
        call boxfile%kill
        call cline%delete('boxfile')
        p_master%nptcls = ndatlines
        p_master%nparts = p_master%nptcls
        if( p_master%ncunits > p_master%nparts )&
        &stop 'nr of computational units (ncunits) mjust be <= number of entries in boxfiles'
        ! box and numlen need to be part of command line
        call cline%set('box',    real(orig_box))
        call cline%set('numlen', real(numlen)  )
        ! prepare part-dependent parameters
        allocate(part_params(p_master%nparts))
        do ipart=1,p_master%nparts
            call part_params(ipart)%new(3)
            call part_params(ipart)%set('xcoord', real2str(boxdata(ipart,1)))
            call part_params(ipart)%set('ycoord', real2str(boxdata(ipart,2)))
            call part_params(ipart)%set('ind',    int2str(ipart))
        end do
        ! setup the environment for distributed execution
        call qenv%new(p_master)
        ! schedule & clean
        call qenv%gen_scripts_and_schedule_jobs(p_master, job_descr, part_params=part_params)
        call qsys_cleanup(p_master)
        ! end gracefully
        call simple_end('**** SIMPLE_TSERIES_TRACK NORMAL STOP ****')
    end subroutine exec_tseries_track_distr

end module simple_commander_distr_wflows

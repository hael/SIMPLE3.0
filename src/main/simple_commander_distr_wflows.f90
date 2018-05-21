! concrete commander: distributed workflows
module simple_commander_distr_wflows
include 'simple_lib.f08'
use simple_qsys_env,       only: qsys_env
use simple_qsys_funs,      only: qsys_cleanup, qsys_watcher
use simple_commander_base, only: commander_base
use simple_sp_project,     only: sp_project
use simple_cmdline,        only: cmdline
use simple_parameters,     only: parameters
use simple_builder,        only: builder
implicit none

public :: preprocess_distr_commander
public :: motion_correct_distr_commander
public :: motion_correct_tomo_distr_commander
public :: powerspecs_distr_commander
public :: ctf_estimate_distr_commander
public :: pick_distr_commander
public :: make_cavgs_distr_commander
public :: cluster2D_distr_commander
public :: refine3D_init_distr_commander
public :: refine3D_distr_commander
public :: reconstruct3D_distr_commander
public :: tseries_track_distr_commander
public :: symsrch_distr_commander
public :: scale_project_distr_commander
private

type, extends(commander_base) :: preprocess_distr_commander
  contains
    procedure :: execute      => exec_preprocess_distr
end type preprocess_distr_commander
type, extends(commander_base) :: motion_correct_distr_commander
  contains
    procedure :: execute      => exec_motion_correct_distr
end type motion_correct_distr_commander
type, extends(commander_base) :: motion_correct_tomo_distr_commander
  contains
    procedure :: execute      => exec_motion_correct_tomo_distr
end type motion_correct_tomo_distr_commander
type, extends(commander_base) :: powerspecs_distr_commander
  contains
    procedure :: execute      => exec_powerspecs_distr
end type powerspecs_distr_commander
type, extends(commander_base) :: ctf_estimate_distr_commander
  contains
    procedure :: execute      => exec_ctf_estimate_distr
end type ctf_estimate_distr_commander
type, extends(commander_base) :: pick_distr_commander
  contains
    procedure :: execute      => exec_pick_distr
end type pick_distr_commander
type, extends(commander_base) :: make_cavgs_distr_commander
  contains
    procedure :: execute      => exec_make_cavgs_distr
end type make_cavgs_distr_commander
type, extends(commander_base) :: cluster2D_distr_commander
  contains
    procedure :: execute      => exec_cluster2D_distr
end type cluster2D_distr_commander
type, extends(commander_base) :: refine3D_init_distr_commander
  contains
    procedure :: execute      => exec_refine3D_init_distr
end type refine3D_init_distr_commander
type, extends(commander_base) :: refine3D_distr_commander
  contains
    procedure :: execute      => exec_refine3D_distr
end type refine3D_distr_commander
type, extends(commander_base) :: reconstruct3D_distr_commander
  contains
    procedure :: execute      => exec_reconstruct3D_distr
end type reconstruct3D_distr_commander
type, extends(commander_base) :: tseries_track_distr_commander
  contains
    procedure :: execute      => exec_tseries_track_distr
end type tseries_track_distr_commander
type, extends(commander_base) :: symsrch_distr_commander
  contains
    procedure :: execute      => exec_symsrch_distr
end type symsrch_distr_commander
type, extends(commander_base) :: scale_project_distr_commander
  contains
    procedure :: execute      => exec_scale_project_distr
end type scale_project_distr_commander

#include "simple_local_flags.inc"
contains

    subroutine exec_preprocess_distr( self, cline )
        use simple_commander_preprocess, only: preprocess_commander
        class(preprocess_distr_commander), intent(inout) :: self
        class(cmdline),                    intent(inout) :: cline
        type(parameters)              :: params
        type(qsys_env)                :: qenv
        type(chash)                   :: job_descr
        type(sp_project)              :: spproj
        character(len=:), allocatable :: output_dir, output_dir_ctf_estimate, output_dir_picker
        character(len=:), allocatable :: output_dir_motion_correct
        logical                       :: l_pick
        if( .not. cline%defined('oritype') ) call cline%set('oritype', 'mic')
        params = parameters(cline)
        ! set mkdir to no (to avoid nested directory structure)
        call cline%set('mkdir', 'no')
        ! picking
        if( cline%defined('refs') )then
            l_pick = .true.
        else
            l_pick = .false.
        endif
        ! output directories
        output_dir = './'
        ! read in movies
        call spproj%read(params%projfile)
        ! DISTRIBUTED EXECUTION
        params%nptcls = spproj%os_mic%get_noris()
        if( params%nparts > params%nptcls ) stop 'nr of partitions (nparts) mjust be < number of entries in filetable'
        ! deal with numlen so that length matches JOB_FINISHED indicator files
        params%numlen = len(int2str(params%nparts))
        call cline%set('numlen', real(params%numlen))
        ! setup the environment for distributed execution
        call qenv%new( numlen=params%numlen)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! schedule & clean
        call qenv%gen_scripts_and_schedule_jobs(job_descr, algnfbody=trim(ALGN_FBODY))
        ! merge docs
        call spproj%read(params%projfile)
        call spproj%merge_algndocs(params%nptcls, params%nparts, 'mic', ALGN_FBODY)
        call spproj%kill
        ! cleanup
        call qsys_cleanup
        ! end gracefully
        call simple_end('**** SIMPLE_DISTR_PREPROCESS NORMAL STOP ****')
    end subroutine exec_preprocess_distr

    subroutine exec_motion_correct_distr( self, cline )
        class(motion_correct_distr_commander), intent(inout) :: self
        class(cmdline),                        intent(inout) :: cline
        type(parameters)              :: params
        type(sp_project)              :: spproj
        type(qsys_env)                :: qenv
        type(chash)                   :: job_descr
        character(len=:), allocatable :: output_dir
        call cline%set('oritype', 'mic')
        params = parameters(cline)
        params%numlen = len(int2str(params%nparts))
        call cline%set('numlen', real(params%numlen))
        ! output directory
        output_dir = './'
        ! setup the environment for distributed execution
        call qenv%new(numlen=params%numlen)
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! schedule & clean
        call qenv%gen_scripts_and_schedule_jobs( job_descr, algnfbody=trim(ALGN_FBODY))
        ! merge docs
        call spproj%read(params%projfile)
        call spproj%merge_algndocs(params%nptcls, params%nparts, 'mic', ALGN_FBODY)
        call spproj%kill
        ! clean
        call qsys_cleanup
        ! end gracefully
        call simple_end('**** SIMPLE_DISTR_MOTION_CORRECT NORMAL STOP ****')
    end subroutine exec_motion_correct_distr

    subroutine exec_motion_correct_tomo_distr( self, cline )
        use simple_oris, only: oris
        class(motion_correct_tomo_distr_commander), intent(inout) :: self
        class(cmdline),                             intent(inout) :: cline
        character(len=LONGSTRLEN), allocatable :: tomonames(:)
        type(parameters)         :: params
        type(oris)               :: exp_doc
        integer                  :: nseries, ipart
        type(qsys_env)           :: qenv
        character(len=KEYLEN)    :: str
        type(chash)              :: job_descr
        type(chash), allocatable :: part_params(:)
        call cline%set('prg', 'motion_correct')
        if( .not. cline%defined('oritype') ) call cline%set('oritype', 'stk')
        params = parameters(cline)
        ! set mkdir to no (to avoid nested directory structure)
        call cline%set('mkdir', 'no')
        if( cline%defined('tomoseries') )then
            call read_filetable(params%tomoseries, tomonames)
        else
            stop 'need tomoseries (filetable of filetables) to be part of the command line when tomo=yes'
        endif
        nseries = size(tomonames)
        call exp_doc%new(nseries)
        if( cline%defined('exp_doc') )then
            if( file_exists(params%exp_doc) )then
                call exp_doc%read(params%exp_doc)
            else
                write(*,*) 'the required parameter file (flag exp_doc): ', trim(params%exp_doc)
                stop 'not in cwd'
            endif
        else
            stop 'need exp_doc (line: exp_time=X dose_rate=Y) to be part of the command line when tomo=yes'
        endif
        params%nparts = nseries
        params%nptcls = nseries
        ! prepare part-dependent parameters
        allocate(part_params(params%nparts), stat=alloc_stat) ! -1. is default excluded value
        if(alloc_stat.ne.0)call allocchk("simple_commander_distr_wflows::motion_correct_tomo_moview_distr ", alloc_stat)
        do ipart=1,params%nparts
            call part_params(ipart)%new(4)
            call part_params(ipart)%set('filetab', trim(tomonames(ipart)))
            call part_params(ipart)%set('fbody', 'tomo'//int2str_pad(ipart,params%numlen_tomo))
            str = real2str(exp_doc%get(ipart,'exp_time'))
            call part_params(ipart)%set('exp_time', trim(str))
            str = real2str(exp_doc%get(ipart,'dose_rate'))
            call part_params(ipart)%set('dose_rate', trim(str))
        end do
        ! setup the environment for distributed execution
        call qenv%new()
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! schedule & clean
        call qenv%gen_scripts_and_schedule_jobs( job_descr, part_params=part_params)
        call qsys_cleanup
        call simple_end('**** SIMPLE_DISTR_MOTION_CORRECT_TOMO NORMAL STOP ****')
    end subroutine exec_motion_correct_tomo_distr

    subroutine exec_powerspecs_distr( self, cline )
        class(powerspecs_distr_commander), intent(inout) :: self
        class(cmdline),                    intent(inout) :: cline
        type(parameters) :: params
        type(qsys_env)   :: qenv
        type(chash)      :: job_descr
        if( .not. cline%defined('oritype') ) call cline%set('oritype', 'stk')
        params = parameters(cline)
        ! set mkdir to no (to avoid nested directory structure)
        call cline%set('mkdir', 'no')
        params%nptcls = nlines(params%filetab)
        if( params%nparts > params%nptcls ) stop 'nr of partitions (nparts) mjust be < number of entries in filetable'
        ! setup the environment for distributed execution
        call qenv%new()
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! schedule & clean
        call qenv%gen_scripts_and_schedule_jobs(job_descr)
        ! clean
        call qsys_cleanup
        ! end gracefully
        call simple_end('**** SIMPLE_DISTR_POWERSPECS NORMAL STOP ****')
    end subroutine exec_powerspecs_distr

    subroutine exec_ctf_estimate_distr( self, cline )
        class(ctf_estimate_distr_commander), intent(inout) :: self
        class(cmdline),                      intent(inout) :: cline
        type(parameters)              :: params
        type(sp_project)              :: spproj
        type(chash)                   :: job_descr
        type(qsys_env)                :: qenv
        character(len=:), allocatable :: output_dir
        if( .not. cline%defined('oritype') ) call cline%set('oritype', 'mic')
        params = parameters(cline)
        ! set mkdir to no (to avoid nested directory structure)
        call cline%set('mkdir', 'no')
        params%numlen = len(int2str(params%nparts))
        call cline%set('numlen', real(params%numlen))
        ! output directory
        output_dir = './'
        ! setup the environment for distributed execution
        call qenv%new()
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! schedule
        call qenv%gen_scripts_and_schedule_jobs( job_descr, algnfbody=trim(ALGN_FBODY))
        ! merge docs
        call spproj%read(params%projfile)
        call spproj%merge_algndocs(params%nptcls, params%nparts, 'mic', ALGN_FBODY)
        ! cleanup
        call qsys_cleanup
        ! graceful ending
        call simple_end('**** SIMPLE_DISTR_CTF_ESTIMATE NORMAL STOP ****')
    end subroutine exec_ctf_estimate_distr

    subroutine exec_pick_distr( self, cline )
        class(pick_distr_commander), intent(inout) :: self
        class(cmdline),              intent(inout) :: cline
        type(parameters)              :: params
        type(sp_project)              :: spproj
        type(qsys_env)                :: qenv
        type(chash)                   :: job_descr
        character(len=:), allocatable :: output_dir
        if( .not. cline%defined('oritype') ) call cline%set('oritype', 'mic')
        params = parameters(cline)
        ! set mkdir to no (to avoid nested directory structure)
        call cline%set('mkdir', 'no')
        params%numlen = len(int2str(params%nparts))
        call cline%set('numlen', real(params%numlen))
        ! output directory
        output_dir = './'
        ! setup the environment for distributed execution
        call qenv%new()
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! schedule & clean
        call qenv%gen_scripts_and_schedule_jobs( job_descr, algnfbody=trim(ALGN_FBODY))
        ! merge docs
        call spproj%read(params%projfile)
        call spproj%merge_algndocs(params%nptcls, params%nparts, 'mic', ALGN_FBODY)
        ! cleanup
        call qsys_cleanup
        ! graceful exit
        call simple_end('**** SIMPLE_DISTR_PICK NORMAL STOP ****')
    end subroutine exec_pick_distr

    subroutine exec_make_cavgs_distr( self, cline )
        class(make_cavgs_distr_commander), intent(inout) :: self
        class(cmdline),                    intent(inout) :: cline
        type(parameters) :: params
        type(cmdline)    :: cline_cavgassemble
        type(qsys_env)   :: qenv
        type(chash)      :: job_descr
        if( .not. cline%defined('oritype') ) call cline%set('oritype', 'ptcl2D')
        params = parameters(cline)
        ! set mkdir to no (to avoid nested directory structure)
        call cline%set('mkdir', 'no')
        ! setup the environment for distributed execution
        call qenv%new()
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! prepare command lines from prototype master
        cline_cavgassemble = cline
        call cline_cavgassemble%set('prg', 'cavgassemble')
        call cline_cavgassemble%set('projfile', trim(params%projfile))
        ! schedule
        call qenv%gen_scripts_and_schedule_jobs( job_descr)
        ! assemble class averages
        call qenv%exec_simple_prg_in_queue(cline_cavgassemble, 'CAVGASSEMBLE', 'CAVGASSEMBLE_FINISHED')
        call qsys_cleanup
        call simple_end('**** SIMPLE_DISTR_MAKE_CAVGS NORMAL STOP ****', print_simple=.false.)
    end subroutine exec_make_cavgs_distr

    subroutine exec_cluster2D_distr( self, cline )
        use simple_procimgfile,         only: random_selection_from_imgfile, copy_imgfile
        use simple_commander_cluster2D, only: check_2Dconv_commander
        class(cluster2D_distr_commander), intent(inout) :: self
        class(cmdline),                   intent(inout) :: cline
        ! commanders
        type(check_2Dconv_commander)     :: xcheck_2Dconv
        type(make_cavgs_distr_commander) :: xmake_cavgs
        ! command lines
        type(cmdline) :: cline_check_2Dconv
        type(cmdline) :: cline_cavgassemble
        type(cmdline) :: cline_make_cavgs
        ! other variables
        type(parameters)          :: params
        type(builder)             :: build
        type(qsys_env)            :: qenv
        character(len=LONGSTRLEN) :: refs, refs_even, refs_odd, str, str_iter
        integer                   :: iter
        type(chash)               :: job_descr
        real                      :: frac_srch_space
        if( .not. cline%defined('oritype') ) call cline%set('oritype', 'ptcl2D')
        call build%init_params_and_build_spproj(cline, params)
        ! set mkdir to no (to avoid nested directory structure)
        call cline%set('mkdir', 'no')
        ! setup the environment for distributed execution
        call qenv%new()
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! prepare command lines from prototype master
        cline_check_2Dconv   = cline
        cline_cavgassemble   = cline
        cline_make_cavgs     = cline
        ! initialise static command line parameters and static job description parameters
        call cline_cavgassemble%set('prg', 'cavgassemble')
        call cline_make_cavgs%set('prg',   'make_cavgs')
        if( job_descr%isthere('automsk') ) call job_descr%delete('automsk')
        ! splitting
        call build%spproj%split_stk(params%nparts)
        ! execute initialiser
        if( .not. cline%defined('refs') )then
            refs               = 'start2Drefs' // params%ext
            params%refs      = trim(refs)
            params%refs_even = 'start2Drefs_even'//params%ext
            params%refs_odd  = 'start2Drefs_odd'//params%ext
            if( build%spproj%is_virgin_field('ptcl2D') )then
                call random_selection_from_imgfile(build%spproj, params%refs, params%box, params%ncls)
                call copy_imgfile(trim(params%refs), trim(params%refs_even), params%smpd, [1,params%ncls])
                call copy_imgfile(trim(params%refs), trim(params%refs_odd),  params%smpd, [1,params%ncls])
            else
                call cline_make_cavgs%set('refs', params%refs)
                call xmake_cavgs%execute(cline_make_cavgs)
            endif
        else
            refs = trim(params%refs)
        endif
        ! extremal dynamics
        if( cline%defined('extr_iter') )then
            params%extr_iter = params%extr_iter - 1
        else
            params%extr_iter = params%startit - 1
        endif
        ! deal with eo partitioning
        if( build%spproj_field%get_nevenodd() == 0 )then
            if( params%tseries .eq. 'yes' )then
                call build%spproj_field%partition_eo(tseries=.true.)
            else
                call build%spproj_field%partition_eo
            endif
            call build%spproj%write_segment_inside(params%oritype)
        endif
        ! main loop
        iter = params%startit - 1
        do
            iter = iter + 1
            str_iter = int2str_pad(iter,3)
            write(*,'(A)')   '>>>'
            write(*,'(A,I6)')'>>> ITERATION ', iter
            write(*,'(A)')   '>>>'
            ! cooling of the randomization rate
            params%extr_iter = params%extr_iter + 1
            call job_descr%set('extr_iter', trim(int2str(params%extr_iter)))
            call cline%set('extr_iter', real(params%extr_iter))
            ! updates
            call job_descr%set('refs', trim(refs))
            call job_descr%set('startit', int2str(iter))
            ! the only FRC we have is from the previous iteration, hence the iter - 1
            call job_descr%set('frcs', trim(FRCS_FILE))
            ! schedule
            call qenv%gen_scripts_and_schedule_jobs(job_descr, algnfbody=trim(ALGN_FBODY))
            ! merge orientation documents
            call build%spproj%merge_algndocs(params%nptcls, params%nparts, 'ptcl2D', ALGN_FBODY)
            ! assemble class averages
            refs      = trim(CAVGS_ITER_FBODY) // trim(str_iter)            // params%ext
            refs_even = trim(CAVGS_ITER_FBODY) // trim(str_iter) // '_even' // params%ext
            refs_odd  = trim(CAVGS_ITER_FBODY) // trim(str_iter) // '_odd'  // params%ext
            call cline_cavgassemble%set('refs', trim(refs))
            call qenv%exec_simple_prg_in_queue(cline_cavgassemble, 'CAVGASSEMBLE', 'CAVGASSEMBLE_FINISHED')
            ! remapping of empty classes
            call remap_empty_cavgs
            ! check convergence
            call xcheck_2Dconv%execute(cline_check_2Dconv)
            frac_srch_space = 0.
            if( iter > 1 ) frac_srch_space = cline_check_2Dconv%get_rarg('frac')
            ! the below activates shifting & automasking
            if( iter > 3 .and. (frac_srch_space >= FRAC_SH_LIM .or. cline_check_2Dconv%defined('trs')) )then
                if( .not.job_descr%isthere('trs') )then
                    ! activates shift search
                    str = real2str(cline_check_2Dconv%get_rarg('trs'))
                    call job_descr%set('trs', trim(str) )
                endif
                if( cline%defined('automsk') )then
                    ! activates masking
                    if( cline%get_carg('automsk') .ne. 'no' ) call job_descr%set('automsk','cavg')
                endif
            endif
            if( cline_check_2Dconv%get_carg('converged').eq.'yes' .or. iter==params%maxits ) exit
        end do
        call qsys_cleanup
        ! report the last iteration on exit
        call cline%delete( 'startit' )
        call cline%set('endit', real(iter))
        ! end gracefully
        call simple_end('**** SIMPLE_DISTR_CLUSTER2D NORMAL STOP ****')

        contains

            subroutine remap_empty_cavgs
                use simple_image,           only: image
                use simple_projection_frcs, only: projection_frcs
                type(image)           :: img_cavg
                type(projection_frcs) :: frcs
                integer, allocatable  :: fromtocls(:,:)
                integer               :: icls, state
                if( params%dyncls.eq.'yes' )then
                    call build%spproj%read_segment('ptcl2D', params%projfile )
                    call build%spproj_field%fill_empty_classes(params%ncls, fromtocls)
                    if( allocated(fromtocls) )then
                        ! updates refs
                        call img_cavg%new([params%box,params%box,1], params%smpd)
                        do icls = 1, size(fromtocls, dim=1)
                            call img_cavg%read(trim(refs), fromtocls(icls, 1))
                            call img_cavg%write(trim(refs), fromtocls(icls, 2))
                        enddo
                        call img_cavg%read(trim(refs), params%ncls)
                        call img_cavg%write(trim(refs), params%ncls)     ! to preserve size
                        do icls = 1, size(fromtocls, dim=1)
                            call img_cavg%read(trim(refs_even), fromtocls(icls, 1))
                            call img_cavg%write(trim(refs_even), fromtocls(icls, 2))
                        enddo
                        call img_cavg%read(trim(refs_even), params%ncls)
                        call img_cavg%write(trim(refs_even), params%ncls) ! to preserve size
                        do icls = 1, size(fromtocls, dim=1)
                            call img_cavg%read(trim(refs_odd), fromtocls(icls, 1))
                            call img_cavg%write(trim(refs_odd), fromtocls(icls, 2))
                        enddo
                        call img_cavg%read(trim(refs_odd), params%ncls)
                        call img_cavg%write(trim(refs_odd), params%ncls)  ! to preserve size
                        ! updates FRCs
                        state     = 1
                        call frcs%new(params%ncls, params%box, params%smpd, state)
                        call frcs%read(trim(FRCS_FILE))
                        do icls = 1, size(fromtocls, dim=1)
                            call frcs%set_frc( fromtocls(icls,2),&
                            &frcs%get_frc(fromtocls(icls,1), params%box, state), state)
                        enddo
                        ! need to be re-written for distributed apps!
                        call frcs%write(trim(FRCS_FILE))
                        call build%spproj%write_segment_inside(params%oritype)
                    endif
                endif
            end subroutine remap_empty_cavgs

    end subroutine exec_cluster2D_distr

    subroutine exec_refine3D_init_distr( self, cline )
        class(refine3D_init_distr_commander), intent(inout) :: self
        class(cmdline),                       intent(inout) :: cline
        type(parameters)      :: params
        type(builder)         :: build
        type(cmdline)         :: cline_volassemble
        type(qsys_env)        :: qenv
        character(len=STDLEN) :: vol
        type(chash)           :: job_descr
        if( .not. cline%defined('oritype') ) call cline%set('oritype', 'ptcl3D')
        call build%init_params_and_build_spproj(cline, params)
        ! set mkdir to no (to avoid nested directory structure)
        call cline%set('mkdir', 'no')
        ! setup the environment for distributed execution
        call qenv%new()
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! init
        if( cline%defined('vol1') )then
            vol = trim(params%vols(1))
        else
            vol = 'startvol_state01'//params%ext
        endif
        ! splitting
        call build%spproj%split_stk(params%nparts)
        ! prepare command lines from prototype master
        cline_volassemble = cline
        call cline_volassemble%set( 'outvol',  vol)
        call cline_volassemble%set( 'eo',     'no')
        call cline_volassemble%set( 'prg',    'volassemble')
        call qenv%gen_scripts_and_schedule_jobs( job_descr)
        call qenv%exec_simple_prg_in_queue(cline_volassemble, 'VOLASSEMBLE', 'VOLASSEMBLE_FINISHED')
        call qsys_cleanup
        call simple_end('**** SIMPLE_DISTR_REFINE3D_INIT NORMAL STOP ****', print_simple=.false.)
    end subroutine exec_refine3D_init_distr

    subroutine exec_refine3D_distr( self, cline )
        use simple_commander_refine3D, only: check_3Dconv_commander
        use simple_commander_volops,   only: postprocess_commander
        class(refine3D_distr_commander), intent(inout) :: self
        class(cmdline),                  intent(inout) :: cline
        ! commanders
        type(refine3D_init_distr_commander) :: xrefine3D_init_distr
        type(reconstruct3D_distr_commander) :: xreconstruct3D_distr
        type(check_3Dconv_commander)        :: xcheck_3Dconv
        type(postprocess_commander)         :: xpostprocess
        ! command lines
        type(cmdline)         :: cline_reconstruct3D_distr
        type(cmdline)         :: cline_refine3D_init
        type(cmdline)         :: cline_check_3Dconv
        type(cmdline)         :: cline_volassemble
        type(cmdline)         :: cline_postprocess
        ! other variables
        type(parameters)      :: params
        type(builder)         :: build
        type(qsys_env)        :: qenv
        type(chash)           :: job_descr
        character(len=STDLEN), allocatable :: state_assemble_finished(:)
        character(len=STDLEN) :: vol, vol_even, vol_odd, vol_iter, vol_iter_even
        character(len=STDLEN) :: vol_iter_odd, str, str_iter, optlp_file
        character(len=STDLEN) :: str_state, fsc_file, volassemble_output
        real                  :: corr, corr_prev
        integer               :: s, state, iter, iostat
        logical               :: vol_defined, have_oris, do_abinitio, converged
        if( .not. cline%defined('oritype') ) call cline%set('oritype', 'ptcl3D')
        call build%init_params_and_build_spproj(cline, params)
        ! set mkdir to no (to avoid nested directory structure)
        call cline%set('mkdir', 'no')
        ! setup the environment for distributed execution
        call qenv%new()
        ! prepare command lines from prototype master
        cline_reconstruct3D_distr = cline
        cline_refine3D_init       = cline
        cline_check_3Dconv        = cline
        cline_volassemble         = cline
        cline_postprocess         = cline
        ! initialise static command line parameters and static job description parameter
        call cline_reconstruct3D_distr%set( 'prg', 'reconstruct3D' ) ! required for distributed call
        call cline_refine3D_init%set(       'prg', 'refine3D_init' ) ! required for distributed call
        call cline_postprocess%set('prg', 'postprocess' )   ! required for local call
        if( trim(params%refine).eq.'clustersym' ) call cline_reconstruct3D_distr%set( 'pgrp', 'c1' )
        call cline_postprocess%set('nstates', 1.)
        call cline_postprocess%set('mirr',  'no')
        call cline_postprocess%delete('projfile')
        call cline_postprocess%delete('projname')
        ! for parallel volassemble over states
        allocate(state_assemble_finished(params%nstates) , stat=alloc_stat)
        if(alloc_stat /= 0)call allocchk("simple_commander_distr_wflows::exec_refine3D_distr state_assemble ",alloc_stat)
        ! removes unnecessary volume keys and generates volassemble finished names
        do state = 1,params%nstates
            vol = 'vol'//int2str( state )
            call cline_check_3Dconv%delete( trim(vol) )
            call cline_volassemble%delete( trim(vol) )
            state_assemble_finished(state) = 'VOLASSEMBLE_FINISHED_STATE'//int2str_pad(state,2)
        enddo
        DebugPrint ' In exec_refine3D_distr; begin splitting'
        ! splitting
        call build%spproj%split_stk(params%nparts)
        DebugPrint ' In exec_refine3D_distr; begin starting models'
        ! GENERATE STARTING MODELS & ORIENTATIONS
        vol_defined = .false.
        do state = 1,params%nstates
            vol = 'vol' // int2str(state)
            if( cline%defined(trim(vol)) ) vol_defined = .true.
        enddo
        have_oris   = .not. build%spproj%is_virgin_field(params%oritype)
        do_abinitio = .not. have_oris .and. .not. vol_defined
        if( do_abinitio )then
            call xrefine3D_init_distr%execute( cline_refine3D_init)
            call cline%set('vol1', trim(STARTVOL_FBODY)//'01'//params%ext)
        else if( have_oris .and. .not. vol_defined )then
            ! reconstructions needed
            call xreconstruct3D_distr%execute( cline_reconstruct3D_distr )
            do state = 1,params%nstates
                ! rename volumes and update cline
                str_state = int2str_pad(state,2)
                vol = trim(VOL_FBODY)//trim(str_state)//params%ext
                str = trim(STARTVOL_FBODY)//trim(str_state)//params%ext
                iostat = simple_rename( trim(vol), trim(str) )
                vol = 'vol'//trim(int2str(state))
                call cline%set( trim(vol), trim(str) )
                if( params%eo .ne. 'no' )then
                    vol_even = trim(VOL_FBODY)//trim(str_state)//'_even'//params%ext
                    str = trim(STARTVOL_FBODY)//trim(str_state)//'_even'//params%ext
                    iostat= simple_rename( trim(vol_even), trim(str) )
                    vol_odd  = trim(VOL_FBODY)//trim(str_state)//'_odd' //params%ext
                    str = trim(STARTVOL_FBODY)//trim(str_state)//'_odd'//params%ext
                    iostat =  simple_rename( trim(vol_odd), trim(str) )
                endif
            enddo
        else if( .not. have_oris .and. vol_defined )then
            ! projection matching
            select case( params%neigh )
                case( 'yes' )
                    stop 'refinement method requires input orientation document'
                case DEFAULT
                    ! all good
            end select
        endif
        ! EXTREMAL DYNAMICS
        if( cline%defined('extr_iter') )then
            params%extr_iter = params%extr_iter - 1
        else
            params%extr_iter = params%startit - 1
        endif
        ! EO PARTITIONING
        DebugPrint ' In exec_refine3D_distr; begin partition_eo'
        if( params%eo .ne. 'no' )then
            if( build%spproj_field%get_nevenodd() == 0 )then
                if( params%tseries .eq. 'yes' )then
                    call build%spproj_field%partition_eo(tseries=.true.)
                else
                    call build%spproj_field%partition_eo
                endif
                call build%spproj%write_segment_inside(params%oritype)
            endif
        endif
        ! prepare job description
        call cline%gen_job_descr(job_descr)
        ! MAIN LOOP
        iter = params%startit - 1
        corr = -1.
        do
            iter = iter + 1
            str_iter = int2str_pad(iter,3)
            write(*,'(A)')   '>>>'
            write(*,'(A,I6)')'>>> ITERATION ', iter
            write(*,'(A)')   '>>>'
            if( have_oris .or. iter > params%startit )then
                call build%spproj%read()
                if( params%refine .eq. 'snhc' )then
                    ! update stochastic neighborhood size if corr is not improving
                    corr_prev = corr
                    corr      = build%spproj_field%get_avg('corr')
                    if( iter > 1 .and. corr <= corr_prev )then
                        params%szsn = min(SZSN_MAX,params%szsn + SZSN_STEP)
                    endif
                    call job_descr%set('szsn', int2str(params%szsn))
                    call cline%set('szsn', real(params%szsn))
                endif
            endif
            ! exponential cooling of the randomization rate
            params%extr_iter = params%extr_iter + 1
            call job_descr%set('extr_iter', trim(int2str(params%extr_iter)))
            call cline%set('extr_iter', real(params%extr_iter))
            call job_descr%set( 'startit', trim(int2str(iter)))
            call cline%set('startit', real(iter))
            ! FRCs
            if( cline%defined('frcs') )then
                ! all good
            else
                call job_descr%set('frcs', trim(FRCS_FBODY)//'01'//BIN_EXT)
            endif
            ! schedule
            call qenv%gen_scripts_and_schedule_jobs( job_descr, algnfbody=trim(ALGN_FBODY))
            ! ASSEMBLE ALIGNMENT DOCS
            call build%spproj%merge_algndocs(params%nptcls, params%nparts, params%oritype, ALGN_FBODY)

            ! ASSEMBLE VOLUMES
            if( params%eo.ne.'no' )then
                call cline_volassemble%set( 'prg', 'volassemble_eo' ) ! required for cmdline exec
            else
                call cline_volassemble%set( 'prg', 'volassemble' )    ! required for cmdline exec
            endif
            do state = 1,params%nstates
                str_state = int2str_pad(state,2)
                if( params%eo .ne. 'no' )then
                    volassemble_output = 'RESOLUTION_STATE'//trim(str_state)//'_ITER'//trim(str_iter)
                else
                    volassemble_output = ''
                endif
                call cline_volassemble%set( 'state', real(state) )
                call qenv%exec_simple_prg_in_queue(cline_volassemble, trim(volassemble_output),&
                    &script_name='simple_script_state'//trim(str_state))
            end do
            call qsys_watcher(state_assemble_finished)
            ! rename volumes, postprocess & update job_descr
            do state = 1,params%nstates
                str_state = int2str_pad(state,2)
                if( build%spproj_field%get_pop( state, 'state' ) == 0 )then
                    ! cleanup for empty state
                    vol = 'vol'//trim(int2str(state))
                    call cline%delete( vol )
                    call job_descr%delete( trim(vol) )
                else
                    if( params%nstates>1 )then
                        ! cleanup postprocessing cmdline as it only takes one volume at a time
                        do s = 1,params%nstates
                            vol = 'vol'//int2str(s)
                            call cline_postprocess%delete( trim(vol) )
                        enddo
                    endif
                    ! rename state volume
                    vol      = trim(VOL_FBODY)//trim(str_state)//params%ext
                    vol_even = trim(VOL_FBODY)//trim(str_state)//'_even'//params%ext
                    vol_odd  = trim(VOL_FBODY)//trim(str_state)//'_odd' //params%ext
                    if( params%refine .eq. 'snhc' )then
                        vol_iter  = trim(SNHCVOL)//trim(str_state)//params%ext
                    else
                        vol_iter      = trim(VOL_FBODY)//trim(str_state)//'_iter'//trim(str_iter)//params%ext
                        vol_iter_even = trim(VOL_FBODY)//trim(str_state)//'_iter'//trim(str_iter)//'_even'//params%ext
                        vol_iter_odd  = trim(VOL_FBODY)//trim(str_state)//'_iter'//trim(str_iter)//'_odd' //params%ext
                    endif
                    iostat = simple_rename( trim(vol), trim(vol_iter) )
                    if( params%eo .ne. 'no' )then
                        iostat= simple_rename( trim(vol_even), trim(vol_iter_even) )
                        iostat= simple_rename( trim(vol_odd),  trim(vol_iter_odd)  )
                    endif
                    ! post-process
                    vol = 'vol'//trim(int2str(state))
                    call cline_postprocess%set( 'vol1', trim(vol_iter))
                    fsc_file   = FSC_FBODY//trim(str_state)//'.bin'
                    optlp_file = ANISOLP_FBODY//trim(str_state)//params%ext
                    if( file_exists(optlp_file) .and. params%eo .ne. 'no' )then
                        call cline_postprocess%delete('lp')
                        call cline_postprocess%set('fsc', trim(fsc_file))
                        call cline_postprocess%set('vol_filt', trim(optlp_file))
                    else if( file_exists(fsc_file) .and. params%eo .ne. 'no' )then
                        call cline_postprocess%delete('lp')
                        call cline_postprocess%set('fsc', trim(fsc_file))
                    else
                        call cline_postprocess%delete('fsc')
                        call cline_postprocess%set('lp', params%lp)
                    endif
                    call xpostprocess%execute(cline_postprocess)
                    ! updates cmdlines & job description
                    vol = 'vol'//trim(int2str(state))
                    call job_descr%set( trim(vol), trim(vol_iter) )
                    call cline%set( trim(vol), trim(vol_iter) )
                endif
            enddo
            ! CONVERGENCE
            converged = .false.
            if( params%refine.eq.'cluster' ) call cline_check_3Dconv%delete('update_res')
            call xcheck_3Dconv%execute(cline_check_3Dconv)
            if( iter >= params%startit + 2 )then
                ! after a minimum of 2 iterations
                if( cline_check_3Dconv%get_carg('converged') .eq. 'yes' ) converged = .true.
            endif
            if( iter >= params%maxits ) converged = .true.
            if( converged )then
                ! update sp_project with the final volume(s)
                if( trim(params%refine) .eq. 'snhc' )then
                    str_state = int2str_pad(1,2)
                    call build%spproj%add_vol2os_out(trim(SNHCVOL)//trim(str_state)//params%ext,&
                        &build%spproj%get_smpd(), 1, 'vol')
                else
                    do state = 1,params%nstates
                        str_state = int2str_pad(state,2)
                        vol_iter = trim(VOL_FBODY)//trim(str_state)//'_iter'//trim(str_iter)//params%ext
                        call build%spproj%add_vol2os_out(vol_iter, build%spproj%get_smpd(), state, 'vol')
                    enddo
                endif
                ! safest to write the whole thing here as multiple fields updated
                call build%spproj%write()
                exit ! main loop
            endif
            ! ITERATION DEPENDENT UPDATES
            if( cline_check_3Dconv%defined('trs') .and. .not.job_descr%isthere('trs') )then
                ! activates shift search if frac >= 90
                str = real2str(cline_check_3Dconv%get_rarg('trs'))
                call job_descr%set( 'trs', trim(str) )
                call cline%set( 'trs', cline_check_3Dconv%get_rarg('trs') )
            endif
        end do
        call qsys_cleanup
        ! report the last iteration on exit
        call cline%delete( 'startit' )
        call cline%set('endit', real(iter))
        ! end gracefully
        call simple_end('**** SIMPLE_DISTR_REFINE3D NORMAL STOP ****')
    end subroutine exec_refine3D_distr

    subroutine exec_reconstruct3D_distr( self, cline )
        class(reconstruct3D_distr_commander), intent(inout) :: self
        class(cmdline),                       intent(inout) :: cline
        type(parameters)                   :: params
        type(builder)                      :: build
        type(qsys_env)                     :: qenv
        type(cmdline)                      :: cline_volassemble
        character(len=STDLEN)              :: volassemble_output, str_state
        character(len=STDLEN), allocatable :: state_assemble_finished(:)
       ! type(build)                        :: b
        type(chash)                        :: job_descr
        integer                            :: state
        if( .not. cline%defined('oritype') ) call cline%set('oritype', 'ptcl3D')
        call cline%delete('refine')
        call build%init_params_and_build_spproj(cline, params)
        ! set mkdir to no (to avoid nested directory structure)
        call cline%set('mkdir', 'no')
        ! setup the environment for distributed execution
        call qenv%new()
        call cline%gen_job_descr(job_descr)
        ! splitting
        call build%spproj%split_stk(params%nparts)
        ! eo partitioning
        if( params%eo .ne. 'no' )then
            if( build%spproj_field%get_nevenodd() == 0 )then
                if( params%tseries .eq. 'yes' )then
                    call build%spproj_field%partition_eo(tseries=.true.)
                else
                    call build%spproj_field%partition_eo
                endif
                call build%spproj%write_segment_inside(params%oritype)
            endif
        endif
        ! schedule
        call qenv%gen_scripts_and_schedule_jobs(job_descr)
        ! assemble volumes
        ! this is for parallel volassemble over states
        allocate(state_assemble_finished(params%nstates) )
        do state = 1, params%nstates
            state_assemble_finished(state) = 'VOLASSEMBLE_FINISHED_STATE'//int2str_pad(state,2)
        enddo
        cline_volassemble = cline
        if( params%eo .ne. 'no' )then
            call cline_volassemble%set('prg', 'volassemble_eo')
        else
            call cline_volassemble%set('prg', 'volassemble')
        endif
        ! parallel assembly
        do state = 1, params%nstates
            str_state = int2str_pad(state,2)
            if( params%eo .ne. 'no' )then
                volassemble_output = 'RESOLUTION_STATE'//trim(str_state)
            else
                volassemble_output = ''
            endif
            call cline_volassemble%set( 'state', real(state) )
            call qenv%exec_simple_prg_in_queue(cline_volassemble, trim(volassemble_output),&
                &script_name='simple_script_state'//trim(str_state))
        end do
        call qsys_watcher(state_assemble_finished)
        ! termination
        call qsys_cleanup
        call simple_end('**** SIMPLE_RECONSTRUCT3D NORMAL STOP ****', print_simple=.false.)
    end subroutine exec_reconstruct3D_distr

    subroutine exec_tseries_track_distr( self, cline )
        use simple_nrtxtfile,         only: nrtxtfile
        class(tseries_track_distr_commander), intent(inout) :: self
        class(cmdline),                       intent(inout) :: cline
        type(parameters)              :: params
        type(qsys_env)                :: qenv
        type(chash)                   :: job_descr
        type(nrtxtfile)               :: boxfile
        real,        allocatable      :: boxdata(:,:)
        type(chash), allocatable      :: part_params(:)
        integer :: ndatlines, numlen, alloc_stat, j, orig_box, ipart
        params = parameters(cline)
        ! set mkdir to no (to avoid nested directory structure)
        call cline%set('mkdir', 'no')
        if( .not. file_exists(params%boxfile)  ) stop 'inputted boxfile does not exist in cwd'
        if( nlines(params%boxfile) > 0 )then
            call boxfile%new(params%boxfile, 1)
            ndatlines = boxfile%get_ndatalines()
            numlen    = len(int2str(ndatlines))
            allocate( boxdata(ndatlines,boxfile%get_nrecs_per_line()), stat=alloc_stat)
            if(alloc_stat.ne.0)call allocchk('In: simple_commander_tseries :: exec_tseries_track', alloc_stat)
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
        params%nptcls = ndatlines
        params%nparts = params%nptcls
        if( params%ncunits > params%nparts )&
        &stop 'nr of computational units (ncunits) mjust be <= number of entries in boxfiles'
        ! box and numlen need to be part of command line
        call cline%set('box',    real(orig_box))
        call cline%set('numlen', real(numlen)  )
        ! prepare part-dependent parameters
        allocate(part_params(params%nparts))
        do ipart=1,params%nparts
            call part_params(ipart)%new(3)
            call part_params(ipart)%set('xcoord', real2str(boxdata(ipart,1)))
            call part_params(ipart)%set('ycoord', real2str(boxdata(ipart,2)))
            call part_params(ipart)%set('ind',    int2str(ipart))
        end do
        ! setup the environment for distributed execution
        call qenv%new()
        ! schedule & clean
        call cline%gen_job_descr(job_descr)
        call qenv%gen_scripts_and_schedule_jobs( job_descr, part_params=part_params)
        call qsys_cleanup
        ! end gracefully
        call simple_end('**** SIMPLE_TSERIES_TRACK NORMAL STOP ****')
    end subroutine exec_tseries_track_distr

    subroutine exec_symsrch_distr( self, cline )
        use simple_comlin_srch,    only: comlin_srch_get_nproj
        use simple_commander_misc, only: sym_aggregate_commander
        use simple_ori,            only: ori
        use simple_oris,          only: oris
        use simple_sym,            only: sym
        class(symsrch_distr_commander), intent(inout) :: self
        class(cmdline),                 intent(inout) :: cline
        type(cmdline)                  :: cline_gridsrch
        type(cmdline)                  :: cline_srch
        type(cmdline)                  :: cline_aggregate
        type(qsys_env)                 :: qenv
        type(chash)                    :: job_descr
        type(oris)                     :: o_shift, grid_symaxes,e
        type(ori)                      :: symaxis
        type(sym)                      :: syme
        type(sp_project)               :: spproj
        type(ctfparams)                :: ctfvars
        type(parameters)               :: params
        integer,    allocatable        :: order(:)
        real,       allocatable        :: corrs(:)
        real                           :: shvec(3)
        integer                        :: i, comlin_srch_nproj, nbest_here
        integer                        :: bestloc(1), cnt, numlen
        character(len=STDLEN)          :: part_tab
        character(len=:),  allocatable :: symsrch_projname
        character(len=*), parameter :: GRIDSYMFBODY = 'grid_symaxes_part'           !<
        character(len=*), parameter :: SYMFBODY     = 'symaxes_part'                !< symmetry axes doc (distributed mode)
        character(len=*), parameter :: SYMSHTAB     = 'sym_3dshift'//trim(TXT_EXT)  !< volume 3D shift
        character(len=*), parameter :: SYMPROJSTK   = 'sym_projs.mrc'               !< volume reference projections
        integer,          parameter :: NBEST = 30
        if( .not. cline%defined('oritype') ) call cline%set('oritype', 'cls3D')
        params = parameters(cline)
        ! constants
        symsrch_projname = 'symsrch_proj'
        call del_file(trim(symsrch_projname)//trim(METADATA_EXT))
        ! set mkdir to no (to avoid nested directory structure)
        call cline%set('mkdir', 'no')
        comlin_srch_nproj = comlin_srch_get_nproj( pgrp=trim(params%pgrp) )
        params%nptcls     = comlin_srch_nproj
        if( params%nparts > comlin_srch_nproj )then
            stop 'number of partitions (npart) > nr of jobs, adjust!'
        endif
        call cline%set('nptcls', real(params%nspace))
        ! read in master project
        call spproj%read(params%projfile)

        ! 1. GRID SEARCH
        cline_gridsrch = cline
        call cline_gridsrch%set('prg',      'symsrch')
        call cline_gridsrch%set('refine',   'no') !!
        call cline_gridsrch%set('fbody',    trim(GRIDSYMFBODY))
        call cline_gridsrch%set('projfile', trim(symsrch_projname)//trim(METADATA_EXT))
        call cline_gridsrch%set('oritype',  params%oritype)
        ! local project update
        ! reference orientations for common lines
        call spproj%os_cls3D%new(params%nspace)
        call spproj%os_cls3D%spiral
        ! name change
        call spproj%projinfo%delete_entry('projname')
        call spproj%projinfo%delete_entry('projfile')
        call spproj%update_projinfo(cline_gridsrch)
        call spproj%write
        ! schedule & merge
        call qenv%new()
        call cline_gridsrch%gen_job_descr(job_descr)
        call qenv%gen_scripts_and_schedule_jobs(job_descr)
        call spproj%merge_algndocs(comlin_srch_nproj, params%nparts, params%oritype, trim(GRIDSYMFBODY))

        ! 2. SELECTION OF SYMMETRY PEAKS TO REFINE
        nbest_here = min(NBEST, spproj%os_cls3D%get_noris())
        call grid_symaxes%new(nbest_here)
        order = spproj%os_cls3D%order_corr()
        cnt = 0
        do i = comlin_srch_nproj, comlin_srch_nproj-nbest_here+1, -1
            cnt = cnt + 1
            call grid_symaxes%set_ori(cnt, spproj%os_cls3D%get_ori(order(i)))
        enddo
        spproj%os_cls3D = grid_symaxes
        call spproj%write
        deallocate(order)
        call grid_symaxes%kill

        ! 3. REFINEMENT
        call qsys_cleanup
        cline_srch = cline
        call cline_srch%set('prg',      'symsrch')
        call cline_srch%set('refine',   'yes') !!
        call cline_srch%set('nthr',     1.) !!
        call cline_srch%set('projfile', trim(symsrch_projname)//trim(METADATA_EXT))
        call cline_srch%set('oritype',  params%oritype)
        call cline_srch%set('fbody',    trim(SYMFBODY))
        ! switch to collection of single threaded jobs
        params%nptcls  = min(comlin_srch_nproj, nbest_here)
        params%ncunits = params%nparts * params%nthr
        params%nparts  = nbest_here
        params%nthr    = 1
        ! schedule & merge
        call qenv%new()
        call cline_srch%gen_job_descr(job_descr)
        call qenv%gen_scripts_and_schedule_jobs(job_descr)
        call spproj%merge_algndocs(nbest_here, params%nparts, params%oritype, trim(SYMFBODY))

        ! 4. REAL-SPACE EVALUATION
        ! adding reference orientations to ptcl3D segment to allow for reconstruction
        call e%new(params%nspace)
        call e%spiral
        ctfvars%smpd = params%smpd
        call spproj%add_stk(trim(SYMPROJSTK), ctfvars, e)
        call spproj%write
        ! execution
        cline_aggregate = cline
        call cline_aggregate%set('prg' ,     'sym_aggregate' )
        call cline_aggregate%set('projfile', trim(symsrch_projname)//trim(METADATA_EXT))
        call cline_aggregate%set('oritype',  'ptcl3D')
        call cline_aggregate%set('eo',       'no' )
        call qenv%exec_simple_prg_in_queue(cline_aggregate,'SYM_AGGREGATE','SYM_AGGREGATE_FINISHED')

        ! read and pick best
        call spproj%read_segment('cls3D', symsrch_projname)
        corrs = spproj%os_cls3D%get_all('corr')
        bestloc = maxloc(corrs)
        symaxis = spproj%os_cls3D%get_ori(bestloc(1))
        write(*,'(A)') '>>> FOUND SYMMETRY AXIS ORIENTATION:'
        call symaxis%print_ori()
        call spproj%kill
        ! output
        if( cline%defined('projfile') )then
            call spproj%read(params%projfile)
            if( spproj%os_ptcl3D%get_noris() == 0 )then
                print *,'No orientations found in this project:',params%projfile
                stop
            endif
            ! transfer shift and symmetry to input orientations
            call syme%new(params%pgrp)
            call o_shift%new(1)
            ! retrieve shift
            call o_shift%read(trim(SYMSHTAB), [1,1])
            shvec(1) = o_shift%get(1,'x')
            shvec(2) = o_shift%get(1,'y')
            shvec(3) = o_shift%get(1,'z')
            shvec    = -1. * shvec ! the sign is right
            ! rotate the orientations & transfer the 3d shifts to 2d
            if( cline%defined('state') )then
                call syme%apply_sym_with_shift(spproj%os_ptcl3D, symaxis, shvec, params%state )
            else
                call syme%apply_sym_with_shift(spproj%os_ptcl3D, symaxis, shvec )
            endif
            call spproj%write
        endif

        ! Cleanup
        call qsys_cleanup
        call del_file(trim(SYMSHTAB))
        numlen =  len(int2str(nbest_here))
        do i = 1, nbest_here
            part_tab = trim(SYMFBODY)//int2str_pad(i, numlen)//trim(METADATA_EXT)
            call del_file(trim(part_tab))
        enddo
        params%nparts = nint(cline%get_rarg('nparts'))
        numlen =  len(int2str(params%nparts))
        do i = 1, params%nparts
            part_tab = trim(GRIDSYMFBODY)//int2str_pad(i, numlen)//trim(METADATA_EXT)
            call del_file(trim(part_tab))
        enddo
        call del_file('SYM_AGGREGATE')
        ! end gracefully
        call simple_end('**** SIMPLE_DISTR_SYMSRCH NORMAL STOP ****')
    end subroutine exec_symsrch_distr

    subroutine exec_scale_project_distr( self, cline )
        class(scale_project_distr_commander), intent(inout) :: self
        class(cmdline),                       intent(inout) :: cline
        type(qsys_env)                     :: qenv
        type(chash)                        :: job_descr
        type(cmdline)                      :: cline_scale
        type(chash),               allocatable :: part_params(:)
        character(len=LONGSTRLEN), allocatable :: part_stks(:)
        type(parameters)      :: params
        type(builder)         :: build
        character(len=STDLEN) :: filetab
        integer, allocatable  :: parts(:,:)
        real                  :: smpd
        integer               :: ipart, nparts, nstks, cnt, istk, partsz, box
        call build%init_params_and_build_spproj(cline, params)
        ! set mkdir to no (to avoid nested directory structure)
        call cline%set('mkdir', 'no')
        ! copy command line
        cline_scale = cline
        ! prepare part-dependent parameters
        nstks = build%spproj%os_stk%get_noris()
        if( nstks == 0 ) stop 'os_stk field of spproj empty; commander_distr_wflows :: exec_scale_distr'
        if( cline%defined('nparts') )then
            nparts = min(params%nparts, nstks)
            call cline_scale%set('nparts', real(nparts))
        else
            nparts = 1
        endif
        smpd = build%spproj%get_smpd()
        box  = build%spproj%get_box()
        call cline_scale%set('smpd', smpd)
        call cline_scale%set('box',  real(box))
        params%nparts = nparts
        parts = split_nobjs_even(nstks, nparts)
        allocate(part_params(nparts))
        cnt = 0
        do ipart=1,nparts
            call part_params(ipart)%new(1)
            partsz = parts(ipart,2) - parts(ipart,1) + 1
            allocate(part_stks(partsz))
            ! creates part filetab
            filetab = 'scale_stktab_part'//int2str(ipart)//trim(TXT_EXT)
            do istk=1,partsz
                cnt = cnt + 1
                part_stks(istk) = build%spproj%get_stkname(cnt)
            enddo
            ! write part filetab & update part parameters
            call write_filetable( filetab, part_stks )
            call part_params(ipart)%set('filetab', filetab)
            deallocate(part_stks)
        end do
        deallocate(parts)
        ! setup the environment for distributed execution
        call qenv%new()
        ! prepare job description
        call cline_scale%gen_job_descr(job_descr)
        call job_descr%set('prg', 'scale')
        call job_descr%set('autoscale', 'no')
        ! schedule
        call qenv%gen_scripts_and_schedule_jobs( job_descr, part_params=part_params)
        ! clean
        call qsys_cleanup
        ! removes temporary split stktab lists
        do ipart=1,nparts
            filetab = 'scale_stktab_part'//int2str(ipart)//trim(TXT_EXT)
            call del_file( filetab )
        end do
        ! end gracefully
        call simple_end('**** SIMPLE_DISTR_SCALE NORMAL STOP ****')
    end subroutine exec_scale_project_distr

end module simple_commander_distr_wflows

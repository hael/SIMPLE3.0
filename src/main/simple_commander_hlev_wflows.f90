! concrete commander: high-level workflows
module simple_commander_hlev_wflows
include 'simple_lib.f08'
use simple_commander_base, only: commander_base
use simple_cmdline,        only: cmdline
use simple_sp_project,     only: sp_project
use simple_parameters,     only: parameters
implicit none

public :: cleanup2D_commander
public :: cleanup2D_nano_commander
public :: cluster2D_autoscale_commander
public :: initial_3Dmodel_commander
public :: cluster3D_commander
public :: cluster3D_refine_commander
private
#include "simple_local_flags.inc"

type, extends(commander_base) :: cleanup2D_commander
  contains
    procedure :: execute      => exec_cleanup2D
end type cleanup2D_commander
type, extends(commander_base) :: cleanup2D_nano_commander
  contains
    procedure :: execute      => exec_cleanup2D_nano
end type cleanup2D_nano_commander
type, extends(commander_base) :: cluster2D_autoscale_commander
  contains
    procedure :: execute      => exec_cluster2D_autoscale
end type cluster2D_autoscale_commander
type, extends(commander_base) :: initial_3Dmodel_commander
  contains
    procedure :: execute      => exec_initial_3Dmodel
end type initial_3Dmodel_commander
type, extends(commander_base) :: cluster3D_commander
  contains
    procedure :: execute      => exec_cluster3D
end type cluster3D_commander
type, extends(commander_base) :: cluster3D_refine_commander
  contains
    procedure :: execute      => exec_cluster3D_refine
end type cluster3D_refine_commander

contains

    ! !> for distributed CLEANUP2D with two-stage autoscaling
    subroutine exec_cleanup2D( self, cline )
        use simple_commander_distr_wflows, only: cluster2D_distr_commander,scale_project_distr_commander
        use simple_procimgfile,            only: random_selection_from_imgfile, random_cls_from_imgfile
        use simple_commander_cluster2D,    only: rank_cavgs_commander
        class(cleanup2D_commander), intent(inout) :: self
        class(cmdline),             intent(inout) :: cline
        ! commanders
        type(cluster2D_distr_commander)     :: xcluster2D_distr
        type(scale_project_distr_commander) :: xscale_distr
        type(rank_cavgs_commander)          :: xrank_cavgs
        ! command lines
        type(cmdline)                       :: cline_cluster2D1, cline_cluster2D2
        type(cmdline)                       :: cline_rank_cavgs, cline_scale
        ! other variables
        type(parameters)                    :: params
        type(sp_project)                    :: spproj, spproj_sc
        character(len=:),       allocatable :: projfile, orig_projfile
        character(len=LONGSTRLEN)           :: finalcavgs, finalcavgs_ranked, cavgs
        real                                :: scale_factor, smpd, msk, ring2, lp1, lp2
        integer                             :: last_iter, box, status
        logical                             :: do_scaling
        ! parameters
        character(len=STDLEN) :: orig_projfile_bak = 'orig_bak.simple'
        integer, parameter    :: MINBOX      = 92
        real,    parameter    :: TARGET_LP   = 15.
        real,    parameter    :: MINITS      = 5.
        real,    parameter    :: MAXITS      = 15.
        real                  :: SMPD_TARGET = 4.
        if( .not. cline%defined('lp')        ) call cline%set('lp',         15. )
        if( .not. cline%defined('ncls')      ) call cline%set('ncls',      200. )
        if( .not. cline%defined('cenlp')     ) call cline%set('cenlp',      20. )
        if( .not. cline%defined('center')    ) call cline%set('center',     'no')
        if( .not. cline%defined('maxits')    ) call cline%set('maxits',     15. )
        if( .not. cline%defined('center')    ) call cline%set('center',    'no' )
        if( .not. cline%defined('autoscale') ) call cline%set('autoscale', 'yes')
        if( .not. cline%defined('oritype')   ) call cline%set('oritype', 'ptcl2D')
        call params%new(cline)
        orig_projfile = params%projfile
        ! set mkdir to no (to avoid nested directory structure)
        call cline%set('mkdir', 'no')
        ! read project file
        call spproj%read(params%projfile)
        ! sanity checks
        if( spproj%get_nptcls() == 0 )then
            THROW_HARD('No particles found in project file: '//trim(params%projfile)//'; exec_cleanup2D_autoscale')
        endif
        ! delete any previous solution
        call spproj%os_ptcl2D%delete_2Dclustering
        call spproj%write_segment_inside(params%oritype)
        ! splitting
        call spproj%split_stk(params%nparts, dir=PATH_PARENT)
        ! first stage
        ! down-scaling for fast execution, greedy optimisation, no match filter, bi-linear interpolation,
        ! no incremental learning, objective function is standard cross-correlation (cc), no centering
        cline_cluster2D1 = cline
        cline_cluster2D2 = cline
        cline_scale      = cline
        call cline_cluster2D1%set('prg',        'cluster2D')
        call cline_cluster2D1%set('refine',     'greedy')
        call cline_cluster2D1%set('maxits',     MINITS)
        call cline_cluster2D1%set('objfun',     'cc')
        call cline_cluster2D1%set('match_filt', 'no')
        call cline_cluster2D1%set('center',     'no')
        call cline_cluster2D1%set('autoscale',  'no')
        call cline_cluster2D1%set('ptclw',      'no')
        call cline_cluster2D1%delete('update_frac')
        ! second stage
        ! down-scaling for fast execution, greedy optimisation, no match filter, bi-linear interpolation,
        ! objective function default is standard cross-correlation (cc)
        call cline_cluster2D2%set('prg',        'cluster2D')
        call cline_cluster2D2%set('refine',     'greedy')
        call cline_cluster2D2%set('match_filt', 'no')
        call cline_cluster2D2%set('autoscale',  'no')
        call cline_cluster2D2%set('trs',         MINSHIFT)
        call cline_cluster2D2%set('objfun',     'cc')
        if( .not.cline%defined('maxits') ) call cline_cluster2D2%set('maxits', MAXITS)
        if( cline%defined('update_frac') )call cline_cluster2D2%set('update_frac',params%update_frac)
        ! Scaling
        do_scaling = .true.
        if( params%box < MINBOX .or. params%autoscale.eq.'no')then
            do_scaling   = .false.
            smpd         = params%smpd
            scale_factor = 1.
            box          = params%box
            projfile     = trim(params%projfile)
        else
            call autoscale(params%box, params%smpd, SMPD_TARGET, box, smpd, scale_factor)
            if( box < MINBOX ) SMPD_TARGET = params%smpd * real(params%box) / real(MINBOX)
            call spproj%scale_projfile(SMPD_TARGET, projfile, cline_cluster2D1, cline_scale, dir=trim(STKPARTSDIR))
            call spproj%kill
            scale_factor = cline_scale%get_rarg('scale')
            smpd         = cline_scale%get_rarg('smpd')
            box          = nint(cline_scale%get_rarg('newbox'))
            call cline_scale%set('state',1.)
            call cline_scale%delete('smpd') !!
            call simple_mkdir(trim(STKPARTSDIR),errmsg="commander_hlev_wflows :: exec_cluster2D_autoscale;  ")
            call xscale_distr%execute( cline_scale )
            ! rename scaled projfile and stash original project file
            ! such that the scaled project file has the same name as the original and can be followed from the GUI
            call simple_copy_file(orig_projfile, orig_projfile_bak)
            call spproj%read_non_data_segments(projfile)
            call spproj%projinfo%set(1,'projname',get_fbody(orig_projfile,METADATA_EXT,separator=.false.))
            call spproj%projinfo%set(1,'projfile',orig_projfile)
            call spproj%write_non_data_segments(projfile)
            call spproj%kill
            status   = simple_rename(projfile,orig_projfile)
            projfile = trim(orig_projfile)
        endif
        if( cline%defined('msk') )then
            msk = params%msk*scale_factor
        else
            msk = real(box/2)-COSMSKHALFWIDTH
        endif
        ring2 = 0.8*msk
        lp1   = max(2.*smpd, max(params%lp,TARGET_LP))
        lp2   = max(2.*smpd, params%lp)
        ! execute initialiser
        params%refs = 'start2Drefs' // params%ext
        call spproj%read(projfile)
        if( params%avg.eq.'yes' )then
            call random_cls_from_imgfile(spproj, params%refs, params%ncls)
        else
            call random_selection_from_imgfile(spproj, params%refs, box, params%ncls)
        endif
        call spproj%kill
        ! updates command-lines
        call cline_cluster2D1%set('refs',   params%refs)
        call cline_cluster2D1%set('msk',    msk)
        call cline_cluster2D1%set('ring2',  ring2)
        call cline_cluster2D1%set('lp',     lp1)
        call cline_cluster2D2%set('msk',    msk)
        call cline_cluster2D2%set('lp',     lp2)
        ! execution 1
        write(logfhandle,'(A)') '>>>'
        write(logfhandle,'(A,F6.1)') '>>> STAGE 1, LOW-PASS LIMIT: ',lp1
        write(logfhandle,'(A)') '>>>'
        call cline_cluster2D1%set('projfile', trim(projfile))
        call xcluster2D_distr%execute(cline_cluster2D1)
        last_iter  = nint(cline_cluster2D1%get_rarg('endit'))
        finalcavgs = trim(CAVGS_ITER_FBODY)//int2str_pad(last_iter,3)//params%ext
        ! execution 2
        if( cline%defined('maxits') )then
            if( last_iter < params%maxits )then
                write(logfhandle,'(A)') '>>>'
                write(logfhandle,'(A,F6.1)') '>>> STAGE 2, LOW-PASS LIMIT: ',lp2
                write(logfhandle,'(A)') '>>>'
                call cline_cluster2D2%set('projfile', trim(projfile))
                call cline_cluster2D2%set('startit',  real(last_iter+1))
                call cline_cluster2D2%set('refs',     trim(finalcavgs))
                call xcluster2D_distr%execute(cline_cluster2D2)
                last_iter  = nint(cline_cluster2D2%get_rarg('endit'))
                finalcavgs = trim(CAVGS_ITER_FBODY)//int2str_pad(last_iter,3)//params%ext
            endif
        endif
        ! restores project file name
        params%projfile = trim(orig_projfile)
        ! update original project
        if( do_scaling )then
            call spproj_sc%read(projfile)
            call spproj%read(orig_projfile_bak)
            call spproj_sc%os_ptcl2D%mul_shifts(1./scale_factor)
            call rescale_cavgs(finalcavgs)
            cavgs = add2fbody(finalcavgs,params%ext,'_even')
            call rescale_cavgs(cavgs)
            cavgs = add2fbody(finalcavgs,params%ext,'_odd')
            call rescale_cavgs(cavgs)
            call spproj%add_cavgs2os_out(trim(finalcavgs), params%smpd, imgkind='cavg')
            spproj%os_ptcl2D = spproj_sc%os_ptcl2D
            spproj%os_cls2D  = spproj_sc%os_cls2D
            ! restores original project and deletes backup & scaled
            call spproj%write(params%projfile)
            call del_file(orig_projfile_bak)
        else
            call spproj%read_segment('out', params%projfile)
            call spproj%add_cavgs2os_out(trim(finalcavgs), params%smpd, imgkind='cavg')
            call spproj%add_frcs2os_out( trim(FRCS_FILE), 'frc2D')
            call spproj%write_segment_inside('out', params%projfile)
        endif
        call spproj_sc%kill
        call spproj%kill
        ! ranking
        finalcavgs_ranked = trim(CAVGS_ITER_FBODY)//int2str_pad(last_iter,3)//'_ranked'//params%ext
        call cline_rank_cavgs%set('projfile', trim(params%projfile))
        call cline_rank_cavgs%set('stk',      trim(finalcavgs))
        call cline_rank_cavgs%set('outstk',   trim(finalcavgs_ranked))
        call xrank_cavgs%execute(cline_rank_cavgs)
        ! cleanup
        if( do_scaling ) call simple_rmdir(STKPARTSDIR)
        ! end gracefully
        call simple_end('**** SIMPLE_CLEANUP2D NORMAL STOP ****')
        contains

            subroutine rescale_cavgs(cavgs)
                use simple_image, only: image
                character(len=*), intent(in) :: cavgs
                type(image)                  :: img, img_pad
                integer                      :: icls, iostat
                call img%new([box,box,1],smpd)
                call img_pad%new([params%box,params%box,1],params%smpd)
                do icls = 1,params%ncls
                    call img%read(cavgs,icls)
                    call img%fft
                    call img%pad(img_pad, backgr=0.)
                    call img_pad%ifft
                    call img_pad%write('tmp_cavgs.mrc',icls)
                enddo
                iostat = simple_rename('tmp_cavgs.mrc',cavgs)
                call img%kill
                call img_pad%kill
            end subroutine

    end subroutine exec_cleanup2D

    !> for distributed cleanup2D optimized for time-series of nanoparticles
    subroutine exec_cleanup2D_nano( self, cline )
        use simple_commander_distr_wflows, only: make_cavgs_distr_commander,cluster2D_distr_commander
        class(cleanup2D_nano_commander), intent(inout) :: self
        class(cmdline),                  intent(inout) :: cline
        ! commanders
        type(cluster2D_distr_commander) :: xcluster2D_distr
        ! other variables
        type(parameters)              :: params
        type(sp_project)              :: spproj
        character(len=:), allocatable :: orig_projfile
        character(len=LONGSTRLEN)     :: finalcavgs
        integer  :: nparts, last_iter_stage2
        call cline%set('center',    'yes')
        call cline%set('autoscale', 'no')
        call cline%set('refine',    'greedy')
        call cline%set('tseries',   'yes')
        if( .not. cline%defined('lp')      ) call cline%set('lp',     1.)
        if( .not. cline%defined('ncls')    ) call cline%set('ncls',   20.)
        if( .not. cline%defined('cenlp')   ) call cline%set('cenlp',  5.)
        if( .not. cline%defined('maxits')  ) call cline%set('maxits', 15.)
        if( .not. cline%defined('oritype') ) call cline%set('oritype', 'ptcl2D')
        call params%new(cline)
        nparts = params%nparts
        ! set mkdir to no (to avoid nested directory structure)
        call cline%set('mkdir', 'no')
        ! read project file
        call spproj%read(params%projfile)
        orig_projfile = trim(params%projfile)
        ! sanity checks
        if( spproj%get_nptcls() == 0 )then
            THROW_HARD('No particles found in project file: '//trim(params%projfile)//'; exec_cleanup2D_nano')
        endif
        ! delete any previous solution
        if( .not. spproj%is_virgin_field(params%oritype) )then
            ! removes previous cluster2D solution (states are preserved)
            call spproj%os_ptcl2D%delete_2Dclustering
            call spproj%write_segment_inside(params%oritype)
        endif
        ! splitting
        call spproj%split_stk(params%nparts, dir=PATH_PARENT)
        ! no auto-scaling
        call cline%set('prg', 'cluster2D')
        call xcluster2D_distr%execute(cline)
        last_iter_stage2 = nint(cline%get_rarg('endit'))
        finalcavgs       = trim(CAVGS_ITER_FBODY)//int2str_pad(last_iter_stage2,3)//params%ext
        ! adding cavgs & FRCs to project
        params%projfile = trim(orig_projfile)
        call spproj%read( params%projfile )
        call spproj%add_frcs2os_out( trim(FRCS_FILE), 'frc2D')
        call spproj%add_cavgs2os_out(trim(finalcavgs), spproj%get_smpd(), imgkind='cavg')
        ! transfer 2D shifts to 3D field
        call spproj%map2Dshifts23D
        call spproj%write
        call spproj%kill
        ! cleanup
        call del_file('start2Drefs'//params%ext)
        ! end gracefully
        call simple_end('**** SIMPLE_CLEANUP2D_NANO NORMAL STOP ****')
    end subroutine exec_cleanup2D_nano

    !> for distributed CLUSTER2D with two-stage autoscaling
    subroutine exec_cluster2D_autoscale( self, cline )
        use simple_commander_distr_wflows, only: make_cavgs_distr_commander,cluster2D_distr_commander,&
            &scale_project_distr_commander, prune_project_distr_commander
        use simple_commander_cluster2D,    only: rank_cavgs_commander
        use simple_commander_imgproc,      only: scale_commander
        class(cluster2D_autoscale_commander), intent(inout) :: self
        class(cmdline),                       intent(inout) :: cline
        ! constants
        integer,               parameter :: MAXITS_STAGE1      = 10
        integer,               parameter :: MAXITS_STAGE1_EXTR = 15
        character(len=STDLEN), parameter :: orig_projfile_bak  = 'orig_bak.simple'
        ! commanders
        type(prune_project_distr_commander) :: xprune_project
        type(make_cavgs_distr_commander)    :: xmake_cavgs
        type(cluster2D_distr_commander)     :: xcluster2D_distr
        type(rank_cavgs_commander)          :: xrank_cavgs
        type(scale_commander)               :: xscale
        type(scale_project_distr_commander) :: xscale_distr
        ! command lines
        type(cmdline) :: cline_cluster2D_stage1
        type(cmdline) :: cline_cluster2D_stage2
        type(cmdline) :: cline_scalerefs, cline_scale1, cline_scale2
        type(cmdline) :: cline_make_cavgs, cline_rank_cavgs, cline_prune_project
        ! other variables
        type(parameters)              :: params
        type(sp_project)              :: spproj, spproj_sc
        character(len=:), allocatable :: projfile_sc, orig_projfile
        character(len=LONGSTRLEN)     :: finalcavgs, finalcavgs_ranked, refs_sc
        real     :: scale_stage1, scale_stage2, trs_stage2
        integer  :: nparts, last_iter_stage1, last_iter_stage2, status
        integer  :: nptcls_sel
        logical  :: scaling
        if( .not. cline%defined('oritype') ) call cline%set('oritype', 'ptcl2D')
        if( .not. cline%defined('lpstart')   ) call cline%set('lpstart',    15. )
        if( .not. cline%defined('lpstop')    ) call cline%set('lpstop',      8. )
        if( .not. cline%defined('cenlp')     ) call cline%set('cenlp',      30. )
        if( .not. cline%defined('maxits')    ) call cline%set('maxits',     30. )
        if( .not. cline%defined('autoscale') ) call cline%set('autoscale', 'yes')
        call cline%delete('clip')
        ! master parameters
        call params%new(cline)
        nparts = params%nparts
        ! set mkdir to no (to avoid nested directory structure)
        call cline%set('mkdir', 'no')
        ! read project file
        call spproj%read(params%projfile)
        orig_projfile = trim(params%projfile)
        ! sanity checks
        if( spproj%get_nptcls() == 0 )then
            THROW_HARD('No particles found in project file: '//trim(params%projfile)//'; exec_cluster2D_autoscale')
        endif
        ! delete any previous solution
        if( .not. spproj%is_virgin_field(params%oritype) )then
            ! removes previous cluster2D solution (states are preserved)
            call spproj%os_ptcl2D%delete_2Dclustering
            call spproj%write_segment_inside(params%oritype)
        endif
        ! automated pruning
        nptcls_sel = spproj%os_ptcl2D%get_noris(consider_state=.true.)
        if( nptcls_sel < nint(PRUNE_FRAC*real(spproj%os_ptcl2D%get_noris())) )then
            write(logfhandle,'(A)')'>>> AUTO-PRUNING PROJECT FILE'
            call spproj%kill
            cline_prune_project = cline
            call xprune_project%execute(cline_prune_project)
            call spproj%read(params%projfile)
            params%nptcls = nptcls_sel
        endif
        ! refinement flag
        if(.not.cline%defined('refine')) call cline%set('refine','snhc')
        ! splitting
        call spproj%split_stk(params%nparts, dir=PATH_PARENT)
        ! general options planning
        if( params%l_autoscale )then
            ! this workflow executes two stages of CLUSTER2D
            ! Stage 1: high down-scaling for fast execution, hybrid extremal/SHC optimisation for
            !          improved population distribution of clusters, no incremental learning,
            !          objective function is standard cross-correlation (cc)
            cline_cluster2D_stage1 = cline
            call cline_cluster2D_stage1%set('objfun',     'cc')
            call cline_cluster2D_stage1%set('match_filt', 'no')
            if( params%l_frac_update )then
                call cline_cluster2D_stage1%delete('update_frac') ! no incremental learning in stage 1
                call cline_cluster2D_stage1%set('maxits', real(MAXITS_STAGE1_EXTR))
            else
                call cline_cluster2D_stage1%set('maxits', real(MAXITS_STAGE1))
            endif
            ! Scaling
            call spproj%scale_projfile(params%smpd_targets2D(1), projfile_sc,&
                &cline_cluster2D_stage1, cline_scale1, dir=trim(STKPARTSDIR))
            call spproj%kill
            scale_stage1 = cline_scale1%get_rarg('scale')
            scaling      = basename(projfile_sc) /= basename(orig_projfile)
            if( scaling )then
                call cline_scale1%delete('smpd') !!
                call cline_scale1%set('state',1.)
                call simple_mkdir(trim(STKPARTSDIR),errmsg="commander_hlev_wflows :: exec_cluster2D_autoscale;  ")
                call xscale_distr%execute( cline_scale1 )
                ! rename scaled projfile and stash original project file
                ! such that the scaled project file has the same name as the original and can be followed from the GUI
                call simple_copy_file(orig_projfile, orig_projfile_bak)
                call spproj%read_non_data_segments(projfile_sc)
                call spproj%projinfo%set(1,'projname',get_fbody(orig_projfile,METADATA_EXT,separator=.false.))
                call spproj%projinfo%set(1,'projfile',orig_projfile)
                call spproj%write_non_data_segments(projfile_sc)
                call spproj%kill
                status = simple_rename(projfile_sc,orig_projfile)
                deallocate(projfile_sc)
                ! scale references
                if( cline%defined('refs') )then
                    call cline_scalerefs%set('stk', trim(params%refs))
                    refs_sc = 'refs'//trim(SCALE_SUFFIX)//params%ext
                    call cline_scalerefs%set('outstk', trim(refs_sc))
                    call cline_scalerefs%set('smpd', params%smpd)
                    call cline_scalerefs%set('newbox', cline_scale1%get_rarg('newbox'))
                    call xscale%execute(cline_scalerefs)
                    call cline_cluster2D_stage1%set('refs',trim(refs_sc))
                endif
            endif
            ! execution
            call cline_cluster2D_stage1%set('projfile', trim(orig_projfile))
            call xcluster2D_distr%execute(cline_cluster2D_stage1)
            last_iter_stage1 = nint(cline_cluster2D_stage1%get_rarg('endit'))
            ! update original project backup and copy to original project file
            if( scaling )then
                call spproj_sc%read_segment('ptcl2D', orig_projfile)
                call spproj_sc%os_ptcl2D%mul_shifts(1./scale_stage1)
                call spproj%read(orig_projfile_bak)
                spproj%os_ptcl2D = spproj_sc%os_ptcl2D
                call spproj%write_segment_inside('ptcl2D',fname=orig_projfile_bak)
                call spproj%kill()
                call simple_copy_file(orig_projfile_bak, orig_projfile)
                ! clean stacks
                call simple_rmdir(STKPARTSDIR)
            endif
            ! Stage 2: refinement stage, less down-scaling, no extremal updates, incremental
            !          learning for acceleration
            cline_cluster2D_stage2 = cline
            call cline_cluster2D_stage2%delete('refs')
            call cline_cluster2D_stage2%set('startit', real(last_iter_stage1 + 1))
            if( cline%defined('update_frac') )then
                call cline_cluster2D_stage2%set('update_frac', params%update_frac)
            endif
            ! Scaling
            call spproj%read(orig_projfile)
            call spproj%scale_projfile( params%smpd_targets2D(2), projfile_sc,&
                &cline_cluster2D_stage2, cline_scale2, dir=trim(STKPARTSDIR))
            call spproj%kill
            scale_stage2 = cline_scale2%get_rarg('scale')
            scaling      = basename(projfile_sc) /= basename(orig_projfile)
            if( scaling )then
                call cline_scale2%delete('smpd') !!
                call cline_scale2%set('state',1.)
                call xscale_distr%execute( cline_scale2 )
                ! rename scaled projfile and stash original project file
                ! such that the scaled project file has the same name as the original and can be followed from the GUI
                call spproj%read_non_data_segments(projfile_sc)
                call spproj%projinfo%set(1,'projname',get_fbody(orig_projfile,METADATA_EXT,separator=.false.))
                call spproj%projinfo%set(1,'projfile',orig_projfile)
                call spproj%write_non_data_segments(projfile_sc)
                call spproj%kill
                status = simple_rename(projfile_sc,orig_projfile)
                deallocate(projfile_sc)
            endif
            trs_stage2 = MSK_FRAC*cline_cluster2D_stage2%get_rarg('msk')
            trs_stage2 = min(MAXSHIFT,max(MINSHIFT,trs_stage2))
            call cline_cluster2D_stage2%set('trs', trs_stage2)
            ! execution
            call cline_cluster2D_stage2%set('projfile', trim(orig_projfile))
            call xcluster2D_distr%execute(cline_cluster2D_stage2)
            last_iter_stage2 = nint(cline_cluster2D_stage2%get_rarg('endit'))
            finalcavgs       = trim(CAVGS_ITER_FBODY)//int2str_pad(last_iter_stage2,3)//params%ext
            ! Updates project and references
            if( scaling )then
                ! shift modulation
                call spproj_sc%read_segment('ptcl2D', orig_projfile)
                call spproj_sc%os_ptcl2D%mul_shifts(1./scale_stage2)
                call spproj%read(orig_projfile_bak)
                spproj%os_ptcl2D = spproj_sc%os_ptcl2D
                call spproj%write_segment_inside('ptcl2D',fname=orig_projfile_bak)
                call spproj%kill()
                call spproj_sc%kill()
                status = simple_rename(orig_projfile_bak,orig_projfile)
                ! clean stacks
                call simple_rmdir(STKPARTSDIR)
                ! original scale references
                cline_make_cavgs = cline ! ncls is transferred here
                call cline_make_cavgs%delete('autoscale')
                call cline_make_cavgs%delete('balance')
                call cline_make_cavgs%set('prg',      'make_cavgs')
                call cline_make_cavgs%set('projfile', orig_projfile)
                call cline_make_cavgs%set('nparts',   real(nparts))
                call cline_make_cavgs%set('refs',     trim(finalcavgs))
                call xmake_cavgs%execute(cline_make_cavgs)
            endif
        else
            ! no auto-scaling
            call xcluster2D_distr%execute(cline)
            last_iter_stage2 = nint(cline%get_rarg('endit'))
            finalcavgs       = trim(CAVGS_ITER_FBODY)//int2str_pad(last_iter_stage2,3)//params%ext
        endif
        ! adding cavgs & FRCs to project
        params%projfile = trim(orig_projfile)
        call spproj%read( params%projfile )
        call spproj%add_frcs2os_out( trim(FRCS_FILE), 'frc2D')
        call spproj%add_cavgs2os_out(trim(finalcavgs), spproj%get_smpd(), imgkind='cavg')
        call spproj%write_segment_inside('out')
        call spproj%kill()
        ! ranking
        finalcavgs_ranked = trim(CAVGS_ITER_FBODY)//int2str_pad(last_iter_stage2,3)//'_ranked'//params%ext
        call cline_rank_cavgs%set('projfile', trim(params%projfile))
        call cline_rank_cavgs%set('stk',      trim(finalcavgs))
        call cline_rank_cavgs%set('outstk',   trim(finalcavgs_ranked))
        call xrank_cavgs%execute( cline_rank_cavgs )
        ! cleanup
        call del_file('start2Drefs'//params%ext)
        ! end gracefully
        call simple_end('**** SIMPLE_CLUSTER2D NORMAL STOP ****')
    end subroutine exec_cluster2D_autoscale

    !> for generation of an initial 3d model from class averages
    subroutine exec_initial_3Dmodel( self, cline )
        use simple_commander_distr_wflows, only: reconstruct3D_distr_commander
        use simple_commander_distr_wflows, only: refine3D_distr_commander, scale_project_distr_commander
        use simple_oris,                   only: oris
        use simple_ori,                    only: ori
        use simple_image,                  only: image
        use simple_commander_volops,       only: reproject_commander, symaxis_search_commander, postprocess_commander
        use simple_parameters,             only: params_glob
        use simple_qsys_env,               only: qsys_env
        use simple_sym,                    only: sym
        class(initial_3Dmodel_commander), intent(inout) :: self
        class(cmdline),                   intent(inout) :: cline
        ! constants
        real,                  parameter :: SCALEFAC2_TARGET = 0.5
        real,                  parameter :: CENLP=30. !< consistency with refine3D
        integer,               parameter :: MAXITS_SNHC=30, MAXITS_INIT=15, MAXITS_REFINE=40
        integer,               parameter :: NSPACE_SNHC=1000, NSPACE_INIT=1000, NSPACE_REFINE=2500
        character(len=STDLEN), parameter :: ORIG_WORK_PROJFILE   = 'initial_3Dmodel_tmpproj.simple'
        character(len=STDLEN), parameter :: REC_FBODY            = 'rec_final'
        character(len=STDLEN), parameter :: REC_PPROC_FBODY      = trim(REC_FBODY)//trim(PPROC_SUFFIX)
        character(len=STDLEN), parameter :: REC_PPROC_MIRR_FBODY = trim(REC_PPROC_FBODY)//trim(MIRR_SUFFIX)
        character(len=2) :: str_state
        ! distributed commanders
        type(refine3D_distr_commander)      :: xrefine3D_distr
        type(scale_project_distr_commander) :: xscale_distr
        type(reconstruct3D_distr_commander) :: xreconstruct3D_distr
        ! shared-mem commanders
        type(symaxis_search_commander) :: xsymsrch
        type(reproject_commander)      :: xreproject
        type(postprocess_commander)    :: xpostprocess
        ! command lines
        type(cmdline) :: cline_refine3D_snhc, cline_refine3D_init, cline_refine3D_refine
        type(cmdline) :: cline_symsrch
        type(cmdline) :: cline_reconstruct3D, cline_postprocess
        type(cmdline) :: cline_reproject
        type(cmdline) :: cline_scale1, cline_scale2
        ! other variables
        character(len=:), allocatable :: stk, orig_stk, frcs_fname
        character(len=:), allocatable :: WORK_PROJFILE
        real,             allocatable :: res(:), tmp_rarr(:)
        integer,          allocatable :: states(:), tmp_iarr(:)
        type(qsys_env)        :: qenv
        type(parameters)      :: params
        type(ctfparams)       :: ctfvars ! ctf=no by default
        type(sp_project)      :: spproj, work_proj1, work_proj2
        type(oris)            :: os
        type(ori)             :: o_tmp
        type(sym)             :: se1,se2
        type(image)           :: img, vol
        character(len=STDLEN) :: vol_iter, pgrp_init, pgrp_refine
        real                  :: iter, smpd_target, lplims(2), msk, orig_msk, orig_smpd
        real                  :: scale_factor1, scale_factor2
        integer               :: icls, ncavgs, orig_box, box, istk, status, cnt
        logical               :: srch4symaxis, do_autoscale, symran_before_refine, l_lpset
        if( .not. cline%defined('autoscale') ) call cline%set('autoscale', 'yes')
        ! hard set oritype
        call cline%set('oritype', 'out') ! because cavgs are part of out segment
        ! auto-scaling prep
        do_autoscale = (cline%get_carg('autoscale').eq.'yes')
        ! now, remove autoscale flag from command line, since no scaled partial stacks
        ! will be produced (this program used shared-mem paralllelisation of scale)
        call cline%delete('autoscale')
        ! whether to perform perform ab-initio reconstruction with e/o class averages
        l_lpset = cline%defined('lpstart') .and. cline%defined('lpstop')
        ! make master parameters
        call params%new(cline)
        ! set mkdir to no (to avoid nested directory structure)
        call cline%set('mkdir', 'no')
        ! from now on we are in the ptcl3D segment, final report is in the cls3D segment
        call cline%set('oritype', 'ptcl3D')
        ! state string
        str_state = int2str_pad(1,2)
        ! decide wether to search for the symmetry axis
        pgrp_init    = trim(params%pgrp_start)
        pgrp_refine  = trim(params%pgrp)
        srch4symaxis = trim(pgrp_refine) .ne. trim(pgrp_init)
        symran_before_refine = .false.
        if( pgrp_init.ne.'c1' .or. pgrp_refine.ne.'c1' )then
            se1 = sym(pgrp_init)
            se2 = sym(pgrp_refine)
            if(se1%get_nsym() > se2%get_nsym())then
                ! ensure se2 is a subgroup of se1
                if( .not. se1%has_subgrp(pgrp_refine) )&
                    &THROW_HARD('Incompatible symmetry groups; simple_commander_hlev_wflows')
                ! set flag for symmetry randomisation before refinmement
                ! in case we are moving from a higher to lower group
                symran_before_refine = .true.
            else if(se2%get_nsym() > se1%get_nsym())then
                ! ensure se1 is a subgroup of se2
                if( .not. se2%has_subgrp(pgrp_init) )&
                    &THROW_HARD('Incompatible symmetry groups; simple_commander_hlev_wflows')
            endif
        endif
        ! read project & update sampling distance
        call spproj%read(params%projfile)
        ! retrieve cavgs stack & FRCS info
        call spproj%get_cavgs_stk(stk, ncavgs, orig_smpd)
        ctfvars%smpd = orig_smpd
        params%smpd  = orig_smpd
        orig_stk     = stk
        if( .not.spproj%os_cls2D%isthere('state') )then
            ! start from import
            allocate(states(ncavgs), source=1)
        else
            ! start from previous 2D
            states = nint(spproj%os_cls2D%get_all('state'))
        endif
        if( count(states==0) .eq. ncavgs )then
            THROW_HARD('no class averages detected in project file: '//trim(params%projfile)//'; initial_3Dmodel')
        endif
        ! SANITY CHECKS
        ! e/o
        if( l_lpset )then
            ! no filtering
        else
            call spproj%get_frcs(frcs_fname, 'frc2D', fail=.false.)
            if( .not.file_exists(frcs_fname) )then
                THROW_HARD('the project file does not contain enough information for e/o alignment, use a low-pass instead')
            endif
        endif
        ! set lplims
        lplims(1) = 20.
        lplims(2) = 8.
        if( l_lpset )then
            lplims(1) = params%lpstart
            lplims(2) = params%lpstop
        else
            if( cline%defined('lpstart') )then
                lplims(1) = params%lpstart
            else
                tmp_rarr  = spproj%os_cls2D%get_all('res')
                tmp_iarr  = nint(spproj%os_cls2D%get_all('state'))
                res       = pack(tmp_rarr, mask=(tmp_iarr>0))
                lplims(1) = max(median_nocopy(res), lplims(2))
                deallocate(res, tmp_iarr, tmp_rarr)
            endif
        endif
        ! prepare a temporary project file for the class average processing
        allocate(WORK_PROJFILE, source=trim(ORIG_WORK_PROJFILE))
        call del_file(WORK_PROJFILE)
        work_proj1%projinfo = spproj%projinfo
        work_proj1%compenv  = spproj%compenv
        if( spproj%jobproc%get_noris()  > 0 ) work_proj1%jobproc = spproj%jobproc
        call work_proj1%add_stk(trim(stk), ctfvars)
        call work_proj1%os_ptcl3D%set_all('state', real(states)) ! takes care of states
        ! name change
        call work_proj1%projinfo%delete_entry('projname')
        call work_proj1%projinfo%delete_entry('projfile')
        call cline%set('projfile', trim(WORK_PROJFILE))
        call cline%set('projname', trim(get_fbody(trim(WORK_PROJFILE),trim('simple'))))
        call work_proj1%update_projinfo(cline)
        ! split
        if(params%nparts == 1 )then
            call work_proj1%write()
        else
            call work_proj1%split_stk(params%nparts)
        endif
        ! down-scale
        orig_box      = work_proj1%get_box()
        orig_msk      = params%msk
        smpd_target   = max(params%smpd, lplims(2)*LP2SMPDFAC)
        do_autoscale  = do_autoscale .and. smpd_target > work_proj1%get_smpd()
        scale_factor1 = 1.
        if( do_autoscale )then
            deallocate(WORK_PROJFILE)
            call simple_mkdir(STKPARTSDIR,errmsg="commander_hlev_wflows :: exec_initial_3Dmodel;  ")
            call work_proj1%scale_projfile(smpd_target, WORK_PROJFILE, cline, cline_scale1, dir=trim(STKPARTSDIR))
            scale_factor1 = cline_scale1%get_rarg('scale')
            box           = nint(cline_scale1%get_rarg('newbox'))
            msk           = cline%get_rarg('msk')
            call cline_scale1%delete('smpd')
            call xscale_distr%execute( cline_scale1 )
        else
            box = orig_box
            msk = orig_msk
        endif
        ! prepare command lines from prototype
        ! projects names are subject to change depending on scaling and are updated individually
        call cline%delete('projname')
        call cline%delete('projfile')
        cline_reconstruct3D   = cline
        cline_refine3D_refine = cline
        cline_reproject       = cline
        cline_refine3D_snhc   = cline
        cline_refine3D_init   = cline
        cline_symsrch         = cline
        ! In shnc & stage 1 the objective function is always standard cross-correlation,
        ! in stage 2 it follows optional user input and defaults to cc
        call cline_refine3D_snhc%set('objfun', 'cc')
        call cline_refine3D_init%set('objfun', 'cc')
        ! reconstruct3D & project are not distributed executions, so remove the nparts flag
        call cline_reproject%delete('nparts')
        ! initialise command line parameters
        ! (1) INITIALIZATION BY STOCHASTIC NEIGHBORHOOD HILL-CLIMBING
        call cline_refine3D_snhc%set('projfile', trim(WORK_PROJFILE))
        call cline_refine3D_snhc%set('msk',      msk)
        call cline_refine3D_snhc%set('box',      real(box))
        call cline_refine3D_snhc%set('prg',    'refine3D')
        call cline_refine3D_snhc%set('refine',  'snhc')
        call cline_refine3D_snhc%set('lp',      lplims(1))
        call cline_refine3D_snhc%set('nspace',  real(NSPACE_SNHC))
        call cline_refine3D_snhc%set('maxits',  real(MAXITS_SNHC))
        call cline_refine3D_snhc%set('match_filt', 'no')
        call cline_refine3D_snhc%set('ptclw',      'no')  ! no soft particle weights in first phase
        call cline_refine3D_snhc%delete('update_frac') ! no fractional update in first phase
        ! (2) REFINE3D_INIT
        call cline_refine3D_init%set('prg',      'refine3D')
        call cline_refine3D_init%set('projfile', trim(WORK_PROJFILE))
        call cline_refine3D_init%set('msk',      msk)
        call cline_refine3D_init%set('box',      real(box))
        call cline_refine3D_init%set('maxits',   real(MAXITS_INIT))
        call cline_refine3D_init%set('vol1',     trim(SNHCVOL)//trim(str_state)//params%ext)
        call cline_refine3D_init%set('lp',       lplims(1))
        call cline_refine3D_init%set('match_filt','no')
        call cline_refine3D_init%set('ptclw',     'no')  ! no soft particle weights in init phase
        if( .not. cline_refine3D_init%defined('nspace') )then
            call cline_refine3D_init%set('nspace', real(NSPACE_INIT))
        endif
        ! (3) SYMMETRY AXIS SEARCH
        if( srch4symaxis )then
            ! need to replace original point-group flag with c1/pgrp_start
            call cline_refine3D_snhc%set('pgrp', trim(pgrp_init))
            call cline_refine3D_init%set('pgrp', trim(pgrp_init))
            ! symsrch
            call qenv%new(1, exec_bin='simple_exec')
            call cline_symsrch%set('prg',     'symaxis_search') ! needed for cluster exec
            call cline_symsrch%set('pgrp',     trim(pgrp_refine))
            call cline_symsrch%set('msk',      msk)
            call cline_symsrch%set('smpd',     work_proj1%get_smpd())
            call cline_symsrch%set('projfile', trim(WORK_PROJFILE))
            if( .not. cline_symsrch%defined('cenlp') ) call cline_symsrch%set('cenlp', CENLP)
            call cline_symsrch%set('hp',       params%hp)
            call cline_symsrch%set('lp',       lplims(1))
            call cline_symsrch%set('oritype',  'ptcl3D')
        endif
        ! (4) REFINE3D REFINE STEP
        call cline_refine3D_refine%set('prg',      'refine3D')
        call cline_refine3D_refine%set('pgrp',     trim(pgrp_refine))
        call cline_refine3D_refine%set('maxits',   real(MAXITS_REFINE))
        call cline_refine3D_refine%set('refine',   'single')
        call cline_refine3D_refine%set('trs',      real(MINSHIFT)) ! activates shift search
        if( l_lpset )then
            call cline_refine3D_refine%set('lp', lplims(2))
        else
            call cline_refine3D_refine%delete('lp')
            call cline_refine3D_refine%set('lplim_crit',  0.5)
            call cline_refine3D_refine%set('lpstop',      lplims(2))
            call cline_refine3D_refine%set('clsfrcs',    'yes')
            call cline_refine3D_refine%set('match_filt', 'yes')
        endif
        if( .not. cline_refine3D_refine%defined('nspace') )then
            call cline_refine3D_refine%set('nspace', real(NSPACE_REFINE))
        endif
        ! (5) RE-CONSTRUCT & RE-PROJECT VOLUME
        call cline_reconstruct3D%set('prg',     'reconstruct3D')
        call cline_reconstruct3D%set('msk',      orig_msk)
        call cline_reconstruct3D%set('box',      real(orig_box))
        call cline_reconstruct3D%set('projfile', ORIG_WORK_PROJFILE)
        call cline_postprocess%set('prg',       'postprocess')
        call cline_postprocess%set('projfile',   ORIG_WORK_PROJFILE)
        call cline_postprocess%set('mkdir',      'no')
        if( l_lpset )then
            call cline_postprocess%set('lp', lplims(2))
        else
            call cline_postprocess%delete('lp')
        endif
        call cline_reproject%set('prg',   'reproject')
        call cline_reproject%set('pgrp',   trim(pgrp_refine))
        call cline_reproject%set('outstk','reprojs'//params%ext)
        call cline_reproject%set('smpd',   params%smpd)
        call cline_reproject%set('msk',    orig_msk)
        call cline_reproject%set('box',    real(orig_box))
        ! execute commanders
        write(logfhandle,'(A)') '>>>'
        write(logfhandle,'(A)') '>>> INITIALIZATION WITH STOCHASTIC NEIGHBORHOOD HILL-CLIMBING'
        write(logfhandle,'(A,F6.1,A)') '>>> LOW-PASS LIMIT FOR ALIGNMENT: ', lplims(1),' ANGSTROMS'
        write(logfhandle,'(A)') '>>>'
        call xrefine3D_distr%execute(cline_refine3D_snhc)
        write(logfhandle,'(A)') '>>>'
        write(logfhandle,'(A)') '>>> INITIAL 3D MODEL GENERATION WITH REFINE3D'
        write(logfhandle,'(A)') '>>>'
        call xrefine3D_distr%execute(cline_refine3D_init)
        iter     = cline_refine3D_init%get_rarg('endit')
        vol_iter = trim(VOL_FBODY)//trim(str_state)//params%ext
        if( symran_before_refine )then
            call work_proj1%read_segment('ptcl3D', trim(WORK_PROJFILE))
            call se1%symrandomize(work_proj1%os_ptcl3D)
            call work_proj1%write_segment_inside('ptcl3D', trim(WORK_PROJFILE))
        endif
        if( srch4symaxis )then
            write(logfhandle,'(A)') '>>>'
            write(logfhandle,'(A)') '>>> SYMMETRY AXIS SEARCH'
            write(logfhandle,'(A)') '>>>'
            call cline_symsrch%set('vol1', trim(vol_iter))
            if( qenv%get_qsys() .eq. 'local' )then
                call xsymsrch%execute(cline_symsrch)
            else
                call qenv%exec_simple_prg_in_queue(cline_symsrch, 'SYMAXIS_SEARCH_FINISHED')
            endif
            call del_file('SYMAXIS_SEARCH_FINISHED')
        endif
        ! prep refinement stage
        call work_proj1%read_segment('ptcl3D', trim(WORK_PROJFILE))
        os = work_proj1%os_ptcl3D
        ! modulate shifts
        if( do_autoscale )then
            call os%mul_shifts( 1./scale_factor1 )
            ! clean stacks & project file & o_peaks on disc
            call work_proj1%read_segment('stk', trim(WORK_PROJFILE))
            do istk=1,work_proj1%os_stk%get_noris()
                call work_proj1%os_stk%getter(istk, 'stk', stk)
                call del_file(trim(stk))
            enddo
        endif
        call work_proj1%kill()
        call del_file(WORK_PROJFILE)
        deallocate(WORK_PROJFILE)
        call del_files(O_PEAKS_FBODY, params_glob%nparts, ext=BIN_EXT)
        ! re-create project
        call del_file(ORIG_WORK_PROJFILE)
        work_proj2%projinfo = spproj%projinfo
        work_proj2%compenv  = spproj%compenv
        if( spproj%jobproc%get_noris()  > 0 ) work_proj2%jobproc = spproj%jobproc
        if( l_lpset )then
            call work_proj2%add_stk(trim(orig_stk), ctfvars)
            work_proj2%os_ptcl3D = os
            call work_proj2%os_ptcl3D%set_all('state', real(states))
        else
            call prep_eo_stks_refine
            params_glob%nptcls = work_proj2%get_nptcls()
        endif
        call os%kill
        ! renaming
        allocate(WORK_PROJFILE, source=trim(ORIG_WORK_PROJFILE))
        call work_proj2%projinfo%delete_entry('projname')
        call work_proj2%projinfo%delete_entry('projfile')
        call cline%set('projfile', trim(WORK_PROJFILE))
        call cline%set('projname', trim(get_fbody(trim(WORK_PROJFILE),trim('simple'))))
        call work_proj2%update_projinfo(cline)
        call work_proj2%write
        ! split
        if( l_lpset )then
            if(params%nparts == 1)then
                ! all good
            else
                call work_proj2%split_stk(params%nparts)
            endif
        endif
        ! refinement scaling
        scale_factor2 = 1.0
        if( do_autoscale )then
            if( scale_factor1 < SCALEFAC2_TARGET )then
                smpd_target = orig_smpd / SCALEFAC2_TARGET
                call cline%set('msk',orig_msk)
                call work_proj2%scale_projfile(smpd_target, WORK_PROJFILE, cline, cline_scale2, dir=trim(STKPARTSDIR))
                scale_factor2 = cline_scale2%get_rarg('scale')
                box = nint(cline_scale2%get_rarg('newbox'))
                msk = cline%get_rarg('msk')
                call cline_scale2%delete('smpd') !!
                call xscale_distr%execute( cline_scale2 )
                call work_proj2%os_ptcl3D%mul_shifts(scale_factor2)
                call work_proj2%write
                if( .not.l_lpset ) call rescale_2Dfilter
            else
                do_autoscale = .false.
                box = orig_box
                msk = orig_msk
            endif
        endif
        call cline_refine3D_refine%set('msk', msk)
        call cline_refine3D_refine%set('box', real(box))
        call cline_refine3D_refine%set('projfile', WORK_PROJFILE)
        ! refinement stage
        write(logfhandle,'(A)') '>>>'
        write(logfhandle,'(A)') '>>> PROBABILISTIC REFINEMENT'
        write(logfhandle,'(A)') '>>>'
        call cline_refine3D_refine%set('startit', iter + 1.)
        call xrefine3D_distr%execute(cline_refine3D_refine)
        iter = cline_refine3D_refine%get_rarg('endit')
        ! updates shifts & deals with final volume
        call work_proj2%read_segment('ptcl3D', WORK_PROJFILE)
        if( do_autoscale )then
            write(logfhandle,'(A)') '>>>'
            write(logfhandle,'(A)') '>>> RECONSTRUCTION AT ORIGINAL SAMPLING'
            write(logfhandle,'(A)') '>>>'
            ! modulates shifts
            os = work_proj2%os_ptcl3D
            call os%mul_shifts(1./scale_factor2)
            call work_proj2%kill
            call work_proj2%read_segment('ptcl3D', ORIG_WORK_PROJFILE)
            work_proj2%os_ptcl3D = os
            call work_proj2%write_segment_inside('ptcl3D', ORIG_WORK_PROJFILE)
            ! reconstruction
            call xreconstruct3D_distr%execute(cline_reconstruct3D)
            vol_iter = trim(VOL_FBODY)//trim(str_state)//params%ext
            ! because postprocess only updates project file when mkdir=yes
            call work_proj2%read_segment('out', ORIG_WORK_PROJFILE)
            call work_proj2%add_vol2os_out(vol_iter, params%smpd, 1, 'vol')
            if( .not.l_lpset )then
                call work_proj2%add_fsc2os_out(FSC_FBODY//str_state//trim(BIN_EXT), 1, orig_box)
                call work_proj2%add_vol2os_out(ANISOLP_FBODY//str_state//params%ext, orig_smpd, 1, 'vol_filt', box=orig_box)
            endif
            call work_proj2%write_segment_inside('out',ORIG_WORK_PROJFILE)
            call xpostprocess%execute(cline_postprocess)
            call os%kill
        else
            iter     = cline_refine3D_refine%get_rarg('endit')
            vol_iter = trim(VOL_FBODY)//trim(str_state)//params%ext
            call vol%new([orig_box,orig_box,orig_box],orig_smpd)
            call vol%read(vol_iter)
            call vol%mirror('x')
            call vol%write(add2fbody(vol_iter,params%ext,trim(PPROC_SUFFIX)//trim(MIRR_SUFFIX)))
            call vol%kill
        endif
        status = simple_rename(vol_iter, trim(REC_FBODY)//params%ext)
        status = simple_rename(add2fbody(vol_iter,params%ext,PPROC_SUFFIX),&
            &trim(REC_PPROC_FBODY)//params%ext)
        status = simple_rename(add2fbody(vol_iter,params%ext,trim(PPROC_SUFFIX)//trim(MIRR_SUFFIX)),&
            &trim(REC_PPROC_MIRR_FBODY)//params%ext)
        ! updates original cls3D segment
        call work_proj2%os_ptcl3D%delete_entry('stkind')
        call work_proj2%os_ptcl3D%delete_entry('eo')
        params_glob%nptcls = ncavgs
        if( l_lpset )then
            spproj%os_cls3D = work_proj2%os_ptcl3D
        else
            call spproj%os_cls3D%new(ncavgs)
            do icls=1,ncavgs
                call work_proj2%os_ptcl3D%get_ori(icls, o_tmp)
                call spproj%os_cls3D%set_ori(icls, o_tmp)
            enddo
            call conv_eo(work_proj2%os_ptcl3D)
        endif
        call work_proj2%kill
        ! revert splitting
        call spproj%os_cls3D%set_all2single('stkind',1.)
        ! map the orientation parameters obtained for the clusters back to the particles
        call spproj%map2ptcls
        ! add rec_final to os_out
        call spproj%add_vol2os_out(trim(REC_FBODY)//params%ext, params%smpd, 1, 'vol_cavg')
        ! write results (this needs to be a full write as multiple segments are updated)
        call spproj%write()
        ! reprojections
        call spproj%os_cls3D%write('final_oris.txt')
        write(logfhandle,'(A)') '>>>'
        write(logfhandle,'(A)') '>>> RE-PROJECTION OF THE FINAL VOLUME'
        write(logfhandle,'(A)') '>>>'
        call cline_reproject%set('vol1',   trim(REC_PPROC_FBODY)//params%ext)
        call cline_reproject%set('oritab', 'final_oris.txt')
        call xreproject%execute(cline_reproject)
        ! write alternated stack
        call img%new([orig_box,orig_box,1], orig_smpd)
        cnt = -1
        do icls=1,ncavgs
            cnt = cnt + 2
            call img%read(orig_stk,icls)
            call img%norm
            call img%write('cavgs_reprojs.mrc',cnt)
            call img%read('reprojs.mrc',icls)
            call img%norm
            call img%write('cavgs_reprojs.mrc',cnt+1)
        enddo
        ! end gracefully
        call se1%kill
        call se2%kill
        call img%kill
        call spproj%kill
        call o_tmp%kill
        if( allocated(WORK_PROJFILE) ) call del_file(WORK_PROJFILE)
        call del_file(ORIG_WORK_PROJFILE)
        call simple_rmdir(STKPARTSDIR)
        call simple_end('**** SIMPLE_INITIAL_3DMODEL NORMAL STOP ****')

        contains

            subroutine prep_eo_stks_refine
                use simple_ori, only: ori
                type(ori)                     :: o, o_even, o_odd
                character(len=:), allocatable :: eostk, ext
                integer :: even_ind, odd_ind, state, icls
                call os%delete_entry('lp')
                call cline_refine3D_refine%set('frcs',frcs_fname)
                ! add stks
                ext   = '.'//fname2ext( stk )
                eostk = add2fbody(trim(orig_stk), trim(ext), '_even')
                call work_proj2%add_stk(eostk, ctfvars)
                eostk = add2fbody(trim(orig_stk), trim(ext), '_odd')
                call work_proj2%add_stk(eostk, ctfvars)
                ! update orientations parameters
                do icls=1,ncavgs
                    even_ind = icls
                    odd_ind  = ncavgs+icls
                    call os%get_ori(icls, o)
                    state    = os%get_state(icls)
                    call o%set('class', real(icls)) ! for mapping frcs in 3D
                    call o%set('state', real(state))
                    ! even
                    o_even = o
                    call o_even%set('eo', 0.)
                    call o_even%set('stkind', work_proj2%os_ptcl3D%get(even_ind,'stkind'))
                    call work_proj2%os_ptcl3D%set_ori(even_ind, o_even)
                    ! odd
                    o_odd = o
                    call o_odd%set('eo', 1.)
                    call o_odd%set('stkind', work_proj2%os_ptcl3D%get(odd_ind,'stkind'))
                    call work_proj2%os_ptcl3D%set_ori(odd_ind, o_odd)
                enddo
                ! cleanup
                deallocate(eostk, ext)
                call o%kill
                call o_even%kill
                call o_odd%kill
            end subroutine prep_eo_stks_refine

            subroutine rescale_2Dfilter
                use simple_projection_frcs, only: projection_frcs
                type(projection_frcs) :: projfrcs, projfrcs_sc
                call projfrcs%read(frcs_fname)
                call projfrcs%downscale(box, projfrcs_sc)
                frcs_fname = trim(FRCS_FILE)
                call projfrcs_sc%write(frcs_fname)
                call cline_refine3D_refine%set('frcs',frcs_fname)
                call projfrcs%kill
                call projfrcs_sc%kill
            end subroutine rescale_2Dfilter

            subroutine conv_eo( os )
                use simple_ori, only: ori
                class(oris), intent(inout) :: os
                type(sym) :: se
                type(ori) :: o_odd, o_even
                real      :: avg_euldist, euldist
                integer   :: icls, ncls
                call se%new(pgrp_refine)
                avg_euldist = 0.
                ncls = 0
                do icls=1,os%get_noris()/2
                    call os%get_ori(icls, o_even)
                    if( o_even%get_state() == 0 )cycle
                    ncls    = ncls + 1
                    call os%get_ori(ncavgs+icls, o_odd)
                    euldist = rad2deg(o_odd.euldist.o_even)
                    if( se%get_nsym() > 1 )then
                        call o_odd%mirror2d
                        call se%rot_to_asym(o_odd)
                        euldist = min(rad2deg(o_odd.euldist.o_even), euldist)
                    endif
                    avg_euldist = avg_euldist + euldist
                enddo
                avg_euldist = avg_euldist/real(ncls)
                write(logfhandle,'(A)')'>>>'
                write(logfhandle,'(A,F6.1)')'>>> EVEN/ODD AVERAGE ANGULAR DISTANCE: ', avg_euldist
            end subroutine conv_eo

    end subroutine exec_initial_3Dmodel

    !> for heterogeinity analysis
    subroutine exec_cluster3D( self, cline )
        use simple_o_peaks_io
        use simple_oris,                   only: oris
        use simple_sym,                    only: sym
        use simple_cluster_seed,           only: gen_labelling
        use simple_commander_distr_wflows, only: refine3D_distr_commander, reconstruct3D_distr_commander
        class(cluster3D_commander), intent(inout) :: self
        class(cmdline),             intent(inout) :: cline
        ! constants
        integer,           parameter :: MAXITS1        = 50
        integer,           parameter :: MAXITS2        = 40
        character(len=*),  parameter :: one            = '01'
        character(len=12), parameter :: cls3D_projfile = 'cls3D.simple'
        ! distributed commanders
        type(refine3D_distr_commander)         :: xrefine3D_distr
        type(reconstruct3D_distr_commander)    :: xreconstruct3D_distr
        ! command lines
        type(cmdline)                          :: cline_refine3D1, cline_refine3D2
        type(cmdline)                          :: cline_reconstruct3D_mixed_distr
        type(cmdline)                          :: cline_reconstruct3D_multi_distr
        ! other variables
        type(parameters)                       :: params
        type(sym)                              :: symop
        type(sp_project)                       :: spproj, work_proj
        type(oris)                             :: os, opeaks
        type(ctfparams)                        :: ctfparms
        character(len=:),          allocatable :: cavg_stk, orig_projfile, prev_vol, target_name
        character(len=LONGSTRLEN), allocatable :: list(:)
        real,                      allocatable :: corrs(:), x(:), z(:), res(:), tmp_rarr(:)
        integer,                   allocatable :: labels(:), states(:), tmp_iarr(:)
        real     :: trs, extr_init, lp_cls3D, smpdfoo
        integer  :: i, iter, startit, rename_stat, ncls, boxfoo, iptcl, ipart
        integer  :: nptcls_part, istate, n_nozero
        logical  :: fall_over, cavgs_import
        if( nint(cline%get_rarg('nstates')) <= 1 ) THROW_HARD('Non-sensical NSTATES argument for heterogeneity analysis!')
        if( .not. cline%defined('refine') )  call cline%set('refine', 'cluster')
        if( .not. cline%defined('oritype')) call cline%set('oritype', 'ptcl3D')
        ! make master parameters
        call params%new(cline)
        orig_projfile   = trim(params%projfile)
        params%projfile = trim(params%cwd)//'/'//trim(params%projname)//trim(METADATA_EXT)
        call cline%set('projfile',params%projfile)
        ! set mkdir to no
        call cline%set('mkdir', 'no')
        ! prep project
        cavgs_import = .false.
        fall_over    = .false.
        select case(trim(params%oritype))
            case('ptcl3D')
                call work_proj%read(params%projfile)
                fall_over = work_proj%get_nptcls() == 0
            case('cls3D')
                call spproj%read(params%projfile)
                fall_over = spproj%os_out%get_noris() == 0
        case DEFAULT
            write(logfhandle,*)'Unsupported ORITYPE; simple_commander_hlev_wflows::exec_cluster3D'
        end select
        if( fall_over ) THROW_HARD('no particles found! exec_cluster3D')
        if( params%oritype.eq.'ptcl3D' )then
            ! just splitting
            call work_proj%split_stk(params%nparts, dir=PATH_PARENT)
        else
            ! class-averages
            params%projfile = trim(cls3d_projfile)
            call cline%set('oritype', 'ptcl3D')
            call spproj%get_cavgs_stk(cavg_stk, ncls, ctfparms%smpd)
            cavgs_import = spproj%os_ptcl2D%get_noris() == 0
            if( cavgs_import )then
                ! start from import
                if(.not.params%l_lpset ) THROW_HARD('need LP=XXX for imported class-averages; cluster3D')
                lp_cls3D = params%lp
                allocate(states(ncls), source=1)
            else
                ! start from previous 2D
                states = nint(spproj%os_cls2D%get_all('state'))
                ! determines resolution limit
                if( params%l_lpset )then
                    lp_cls3D = params%lp
                else
                    tmp_rarr  = spproj%os_cls2D%get_all('res')
                    tmp_iarr  = nint(spproj%os_cls2D%get_all('state'))
                    res       = pack(tmp_rarr, mask=(tmp_iarr>0))
                    lp_cls3D  = median_nocopy(res)
                    deallocate(res, tmp_iarr, tmp_rarr)
                endif
                if(cline%defined('lpstop')) lp_cls3D = max(lp_cls3D, params%lpstop)
            endif
            if( count(states==0) .eq. ncls )then
                THROW_HARD('no class averages detected in project file: '//trim(params%projfile)//'; cluster3D')
            endif
            work_proj%projinfo = spproj%projinfo
            work_proj%compenv  = spproj%compenv
            if(spproj%jobproc%get_noris()  > 0) work_proj%jobproc = spproj%jobproc
            call work_proj%add_single_stk(trim(cavg_stk), ctfparms, spproj%os_cls3D)
            ! takes care of states
            call work_proj%os_ptcl3D%set_all('state', real(states))
            ! name change
            call work_proj%projinfo%delete_entry('projname')
            call work_proj%projinfo%delete_entry('projfile')
            call cline%set('projfile', trim(params%projfile))
            call cline%set('projname', trim(get_fbody(trim(params%projfile),trim('simple'))))
            call work_proj%update_projinfo(cline)
            ! splitting in CURRENT directory
            call work_proj%split_stk(params%nparts, dir=PATH_HERE)
            ! write
            call work_proj%write
        endif
        ! fetch project oris
        call work_proj%get_sp_oris('ptcl3D', os)
        ! wipe previous states
        labels = nint(os%get_all('state'))
        if( any(labels > 1) )then
            where(labels > 0) labels = 1
            call os%set_all('state', real(labels))
        endif
        deallocate(labels)

        ! e/o partition
        if( .not.params%l_lpset )then
            if( os%get_nevenodd() == 0 ) call os%partition_eo
        else
            call os%set_all2single('eo', -1.)
        endif
        if( trim(params%refine) .eq. 'sym' )then
            ! randomize projection directions with respect to symmetry
            symop = sym(params%pgrp)
            call symop%symrandomize(os)
            call symop%kill
        endif

        ! prepare command lines from prototype
        call cline%delete('refine')
        ! resolution limits
        if( trim(params%oritype).eq.'cls3D' )then
            params%l_lpset = .true.
            call cline%set('lp',lp_cls3D)
        else
            if(.not.cline%defined('lplim_crit'))call cline%set('lplim_crit', 0.5)
        endif
        cline_refine3D1                 = cline ! first stage, extremal optimization
        cline_refine3D2                 = cline ! second stage, stochastic refinement
        cline_reconstruct3D_mixed_distr = cline
        cline_reconstruct3D_multi_distr = cline
        ! first stage
        call cline_refine3D1%set('prg',       'refine3D')
        call cline_refine3D1%set('match_filt','no')
        call cline_refine3D1%set('maxits',     real(MAXITS1))
        call cline_refine3D1%set('neigh',     'yes') ! always consider neighbours
        if( .not.cline_refine3D1%defined('nnn') )then
            call cline_refine3D1%set('nnn', 0.05*real(params%nspace))
        endif
        call cline_refine3D1%delete('update_frac')  ! no update frac for extremal optimization
        ! second stage
        call cline_refine3D2%set('prg', 'refine3D')
        call cline_refine3D2%set('match_filt','no')
        call cline_refine3D2%set('refine', 'multi')
        if( .not.cline%defined('update_frac') )call cline_refine3D2%set('update_frac', 0.5)
        ! reconstructions
        call cline_reconstruct3D_mixed_distr%set('prg',    'reconstruct3D')
        call cline_reconstruct3D_mixed_distr%set('nstates', 1.)
        call cline_reconstruct3D_mixed_distr%delete('lp')
        call cline_reconstruct3D_multi_distr%set('prg', 'reconstruct3D')
        call cline_reconstruct3D_multi_distr%delete('lp')
        if( trim(params%refine) .eq. 'sym' )then
            call cline_reconstruct3D_multi_distr%set('pgrp','c1')
            call cline_reconstruct3D_mixed_distr%set('pgrp','c1')
        endif
        if( cline%defined('trs') )then
            ! all good
        else
            ! works out shift limits for in-plane search
            trs = MSK_FRAC*real(params%msk)
            trs = min(MAXSHIFT, max(MINSHIFT, trs))
            call cline_refine3D1%set('trs',trs)
            call cline_refine3D2%set('trs',trs)
        endif
        ! refinement specific section
        select case(trim(params%refine))
            case('soft')
                call cline_refine3D1%set('refine','clustersoft')
                call cline_refine3D1%set('neigh', 'no')
                call cline_reconstruct3D_mixed_distr%set('dir_refine',PATH_HERE)
                call cline_reconstruct3D_multi_distr%set('dir_refine',PATH_HERE)
            case('sym')
                call cline_refine3D1%set('refine','clustersym')
                call cline_refine3D2%set('pgrp','c1')
                call cline_refine3D2%delete('neigh') ! no neighbour mode for symmetry
                call cline_refine3D2%delete('nnn')
            case DEFAULT
                call cline_refine3D1%set('refine', 'cluster')
        end select

        ! copy the orientation peak distributions
        if( trim(params%refine).eq.'soft' )then
            call work_proj%get_vol('vol', 1, prev_vol, smpdfoo, boxfoo)
            params%dir_refine = get_fpath(prev_vol)
            call simple_list_files(trim(params%dir_refine)//'/oridistributions_part*', list)
            if( size(list) == 0 )then
                THROW_HARD('No peaks could be found in: '//trim(params%dir_refine))
            elseif( size(list) /= params%nparts )then
                THROW_HARD('# partitions not consistent with that in '//trim(params%dir_refine))
            endif
            do ipart=1,params%nparts
                target_name = PATH_HERE//basename(trim(list(ipart)))
                call simple_copy_file(trim(list(ipart)), target_name)
            end do
        endif

        ! MIXED MODEL RECONSTRUCTION
        ! retrieve mixed model Fourier components, normalization matrix, FSC & anisotropic filter
        if( .not.params%l_lpset )then
            work_proj%os_ptcl3D = os
            call work_proj%write
            call xreconstruct3D_distr%execute(cline_reconstruct3D_mixed_distr)
            rename_stat = simple_rename(trim(VOL_FBODY)//one//params%ext, trim(CLUSTER3D_VOL)//params%ext)
            rename_stat = simple_rename(trim(VOL_FBODY)//one//'_even'//params%ext, trim(CLUSTER3D_VOL)//'_even'//params%ext)
            rename_stat = simple_rename(trim(VOL_FBODY)//one//'_odd'//params%ext,  trim(CLUSTER3D_VOL)//'_odd'//params%ext)
            rename_stat = simple_rename(trim(FSC_FBODY)//one//BIN_EXT, trim(CLUSTER3D_FSC))
            rename_stat = simple_rename(FRCS_FILE, trim(CLUSTER3D_FRCS))
            rename_stat = simple_rename(trim(ANISOLP_FBODY)//one//params%ext, trim(CLUSTER3D_ANISOLP)//params%ext)
        endif

        ! calculate extremal initial ratio
        if( os%isthere('corr') )then
            labels    = nint(os%get_all('state'))
            corrs     = os%get_all('corr')
            x         = pack(corrs, mask=(labels>0))
            z         = robust_z_scores(x)
            extr_init = 2.*real(count(z<-1.)) / real(count(labels>0))
            extr_init = max(0.1,extr_init)
            extr_init = min(extr_init,EXTRINITHRESH)
            deallocate(x,z,corrs,labels)
        else
            extr_init = EXTRINITHRESH
        endif
        call cline_refine3D1%set('extr_init', extr_init)
        write(logfhandle,'(A,F5.2)') '>>> INITIAL EXTREMAL RATIO: ',extr_init

        ! randomize state labels
        write(logfhandle,'(A)') '>>>'
        call gen_labelling(os, params%nstates, 'squared_uniform')
        work_proj%os_ptcl3D = os
        ! writes for reconstruct3D,refine3D
        call work_proj%write
        call work_proj%kill

        if( trim(params%refine).eq.'soft' )then
            ! update states
            do ipart=1,params%nparts
                target_name = PATH_HERE//basename(trim(list(ipart)))
                nptcls_part = get_o_peak_filesz(target_name)
                call open_o_peaks_io(target_name)
                iptcl = 0
                do i = 1,nptcls_part
                    iptcl  = iptcl+1
                    istate = os%get_state(iptcl)
                    if( istate <= 1 )cycle
                    call opeaks%new(NPEAKS2REFINE)
                    call read_o_peak(opeaks, [1,nptcls_part], i, n_nozero)
                    call opeaks%set_all2single('state',real(istate))
                    call write_o_peak(opeaks, [1,nptcls_part], i)
                enddo
                call close_o_peaks_io
            enddo
            deallocate(list)
            call opeaks%kill
            ! reconstruct & updates starting volumes
            call xreconstruct3D_distr%execute(cline_reconstruct3D_multi_distr)
            do istate = 1,params%nstates
                call cline_refine3D1%set('vol'//int2str(istate), trim(VOL_FBODY)//int2str_pad(istate,2)//params%ext)
            enddo
        endif
        call os%kill

        ! STAGE1: extremal optimization, frozen orientation parameters
        write(logfhandle,'(A)')    '>>>'
        write(logfhandle,'(A,I3)') '>>> 3D CLUSTERING - STAGE 1'
        write(logfhandle,'(A)')    '>>>'
        call xrefine3D_distr%execute(cline_refine3D1)
        iter = nint(cline_refine3D1%get_rarg('endit'))
        ! for analysis purpose only
        call work_proj%read_segment('ptcl3D', params%projfile)
        call work_proj%kill

        ! STAGE2: soft multi-states refinement
        startit = iter + 1
        call cline_refine3D2%set('startit', real(startit))
        call cline_refine3D2%set('maxits',  real(min(params%maxits,startit+MAXITS2)))
        write(logfhandle,'(A)')    '>>>'
        write(logfhandle,'(A,I3)') '>>> 3D CLUSTERING - STAGE 2'
        write(logfhandle,'(A)')    '>>>'
        call xrefine3D_distr%execute(cline_refine3D2)

        ! class-averages mapping
        if( params%oritype.eq.'cls3D' )then
            call work_proj%read(params%projfile)
            spproj%os_cls3D = work_proj%os_ptcl3D
            if( cavgs_import )then
                ! no mapping
            else
                ! map to ptcl3D
                call spproj%map2ptcls
            endif
            call spproj%write
            call spproj%kill
            call del_file(cls3d_projfile)
        endif

        ! end gracefully
        call simple_end('**** SIMPLE_CLUSTER3D NORMAL STOP ****')
    end subroutine exec_cluster3D

    !> multi-particle refinement after cluster3D
    subroutine exec_cluster3D_refine( self, cline )
        use simple_oris,                   only: oris
        use simple_ori,                    only: ori
        use simple_parameters,             only: params_glob
        use simple_commander_distr_wflows, only: refine3D_distr_commander
        class(cluster3D_refine_commander), intent(inout) :: self
        class(cmdline),                    intent(inout) :: cline
        ! constants
        integer,                     parameter :: MAXITS = 40
        character(len=12),           parameter :: cls3D_projfile = 'cls3D.simple'
        ! distributed commanders
        type(refine3D_distr_commander)         :: xrefine3D_distr
        ! command lines
        type(cmdline),             allocatable :: cline_refine3D(:)
        ! other variables
        integer,                   allocatable :: state_pops(:), states(:), master_states(:)
        character(len=STDLEN),     allocatable :: dirs(:), projfiles(:)
        character(len=LONGSTRLEN), allocatable :: rel_stks(:), stks(:)
        character(len=:),          allocatable :: projname, cavg_stk, frcs_fname, orig_projfile, stk
        type(parameters)         :: params
        type(ctfparams)          :: ctfparms
        type(sp_project)         :: spproj, spproj_master
        class(oris),     pointer :: pos => null()
        type(ori)                :: o_tmp
        integer                  :: state, iptcl, nstates, single_state, ncls, istk, nstks
        logical                  :: l_singlestate, cavgs_import, fall_over
        if( .not. cline%defined('oritype') ) call cline%set('oritype', 'ptcl3D')
        call params%new(cline)
        ! set mkdir to no
        call cline%set('mkdir', 'no')
        ! sanity checks
        if( .not.cline%defined('maxits') )call cline%set('maxits',real(MAXITS))
        l_singlestate = cline%defined('state')
        if( l_singlestate )then
            single_state = nint(cline%get_rarg('state'))
        else
            single_state = 0
        endif
        orig_projfile = trim(params%projfile)
        cavgs_import  = .false.
        fall_over     = .false.
        select case(trim(params%oritype))
            case('ptcl3D')
                call spproj_master%read(params%projfile)
                fall_over = spproj_master%get_nptcls() == 0
            case('cls3D')
                call spproj%read(params%projfile)
                fall_over = spproj%os_out%get_noris() == 0
        case DEFAULT
            write(logfhandle,*)'Unsupported ORITYPE; simple_commander_hlev_wflows::exec_cluster3D_refine'
        end select
        if( fall_over ) THROW_HARD('no particles found! exec_cluster3D_refine')
        ! stash states
        if(params%oritype.eq.'cls3D')then
            master_states  = nint(spproj%os_cls3D%get_all('state'))
            call spproj%os_cls3D%get_pops(state_pops, 'state', consider_w=.false.)
        else
            master_states  = nint(spproj_master%os_ptcl3D%get_all('state'))
            call spproj_master%os_ptcl3D%get_pops(state_pops, 'state', consider_w=.false.)
        endif
        nstates        = maxval(master_states)
        params%nstates = nstates
        if( params%nstates==1 )then
            THROW_HARD('non-sensical # states: '//int2str(params%nstates)//' for multi-particle refinement')
        endif
        if( state_pops(params%state) == 0 )then
            THROW_HARD('state: '//int2str(params%state)//' is empty')
        endif
        ! state dependent variables
        allocate(projfiles(params%nstates), dirs(params%nstates), cline_refine3D(params%nstates))
        do state = 1, params%nstates
            if( state_pops(state) == 0 )cycle
            if( l_singlestate .and. single_state.ne.state )cycle
            ! name & directory
            projname         = 'state_'//trim(int2str_pad(state,2))
            projfiles(state) = trim(projname)//trim(METADATA_EXT)
            dirs(state)      = trim(int2str(state))//'_refine3D'
            ! command line
            cline_refine3D(state) = cline
            call cline_refine3D(state)%set('prg',     'refine3D')
            call cline_refine3D(state)%set('projname',trim(projname))
            call cline_refine3D(state)%set('projfile',trim(projfiles(state)))
            call cline_refine3D(state)%set('mkdir',   'yes')
            call cline_refine3D(state)%set('refine',  'single')
            call cline_refine3D(state)%delete('state')
            call cline_refine3D(state)%delete('nstates')
            if(params%oritype.eq.'cls3D') call cline_refine3D(state)%set('oritype', 'ptcl3D')
        enddo

        ! transfer cavgs to ptcl3D
        if(params%oritype.eq.'cls3D')then
            call spproj%get_cavgs_stk(cavg_stk, ncls, ctfparms%smpd)
            states       = nint(spproj%os_cls3D%get_all('state'))
            cavgs_import = spproj%os_ptcl2D%get_noris() == 0
            if( cavgs_import )then
                ! start from import
                if(.not.cline%defined('lp')) THROW_HARD('need LP=XXX for imported class-averages; cluster3D_refine')
            else
                call spproj%get_frcs(frcs_fname, 'frc2D', fail=.false.)
                if( .not.file_exists(frcs_fname) )then
                    THROW_HARD('the project file does not contain enough information for e/o alignment, use a low-pass instead')
                endif
            endif
            if( count(states==0) .eq. ncls )then
                THROW_HARD('no class averages detected in project file: '//trim(params%projfile)//'; cluster3D_refine')
            endif
            spproj_master%projinfo = spproj%projinfo
            spproj_master%compenv  = spproj%compenv
            if(spproj%jobproc%get_noris()  > 0) spproj_master%jobproc = spproj%jobproc
            if( cavgs_import )then
                call spproj_master%add_single_stk(trim(cavg_stk), ctfparms, spproj%os_cls3D)
                call spproj_master%os_ptcl3D%set_all('state', real(states))
            else
                call prep_eo_stks
                params_glob%nptcls = spproj_master%get_nptcls()
            endif
            ! name & oritype change
            call spproj_master%projinfo%delete_entry('projname')
            call spproj_master%projinfo%delete_entry('projfile')
            call cline%set('projfile', cls3D_projfile)
            call cline%set('projname', trim(get_fbody(trim(cls3D_projfile),trim('simple'))))
            call spproj_master%update_projinfo(cline)
            ! splitting in CURRENT directory
            call spproj_master%split_stk(params%nparts, dir=PATH_HERE)
            ! write
            call spproj_master%write
        endif

        ! states are lost from the project after this loop and stored in master_states
        nstks = spproj_master%os_stk%get_noris()
        allocate(stks(nstks), rel_stks(nstks))
        do istk = 1,nstks
            stk = spproj_master%get_stkname(istk)
            stks(istk) = NIL
            if( file_exists(stk) )then
                rel_stks(istk) = trim(stk)
                stks(istk)     = simple_abspath(stk)
            endif
            ! turns to absolute paths
            call spproj_master%os_stk%set(istk,'stk',stks(istk))
        enddo
        do state = 1, params%nstates
            if( state_pops(state) == 0 )cycle
            if( l_singlestate .and. single_state.ne.state )cycle
            ! states
            states = master_states
            where(states /= state) states = 0
            where(states /= 0)     states = 1
            call spproj_master%os_ptcl3D%set_all('state', real(states))
            ! write
            call spproj_master%update_projinfo(cline_refine3D(state))
            call spproj_master%write(projfiles(state))
            deallocate(states)
        enddo
        do istk = 1,nstks
            stk = spproj_master%get_stkname(istk)
            if( trim(stks(istk)) /= NIL )then
                ! restores path
                call spproj_master%os_stk%set(istk,'stk',rel_stks(istk))
            endif
        enddo
        deallocate(stks,rel_stks)
        ! restores name
        call spproj_master%update_projinfo(cline)

        ! Execute individual refine3D jobs
        do state = 1, nstates
            if( state_pops(state) == 0 )cycle
            if( l_singlestate .and. state.ne.single_state )cycle
            write(logfhandle,'(A)')   '>>>'
            write(logfhandle,'(A,I2,A,A)')'>>> REFINING STATE: ', state
            write(logfhandle,'(A)')   '>>>'
            params_glob%projname = 'state_'//trim(int2str_pad(state,2))
            params_glob%projfile = projfiles(state)
            params_glob%nstates = 1
            params_glob%state   = 1
            call xrefine3D_distr%execute(cline_refine3D(state))
            call simple_chdir(PATH_PARENT,errmsg="commander_hlev_wflows :: exec_cluster3D_refine;")
        enddo
        ! restores original values
        params_glob%projname = trim(get_fbody(trim(orig_projfile),trim('simple')))
        params_glob%projfile = trim(orig_projfile)
        params_glob%nstates  = nstates

        ! consolidates new orientations parameters & files
        ! gets original project back
        if(params%oritype.eq.'cls3D')then
            params_glob%nptcls = ncls
            call spproj_master%kill
            call spproj_master%read(params%projfile)
        endif
        do state=1,params%nstates
            if( state_pops(state) == 0 )cycle
            if( l_singlestate .and. state.ne.single_state ) cycle
            ! renames volumes and updates in os_out
            call stash_state(state)
            ! updates orientations
            call spproj%read_segment('ptcl3D',filepath(dirs(state),projfiles(state)))
            call spproj_master%ptr2oritype(params%oritype, pos)
            do iptcl=1,params%nptcls
                if( master_states(iptcl)==state )then
                    call spproj%os_ptcl3D%get_ori(iptcl, o_tmp)
                    call pos%set_ori(iptcl, o_tmp)
                    ! reset original states
                    call pos%set(iptcl,'state',real(state))
                endif
            enddo
            call spproj%kill
        enddo
        ! map to ptcls for non-imported class-averages
        if(params%oritype.eq.'cls3D' .and. .not.cavgs_import) call spproj_master%map2ptcls
        ! final write
        call spproj_master%write
        ! cleanup
        call spproj%kill
        call spproj_master%kill
        do state=1,params%nstates
            if( state_pops(state) == 0 )cycle
            if( l_singlestate .and. state.ne.single_state )cycle
            call del_file(projfiles(state))
        enddo
        if(params%oritype.eq.'cls3D') call del_file(cls3D_projfile)
        deallocate(master_states, dirs, projfiles)
        call o_tmp%kill
        ! end gracefully
        call simple_end('**** SIMPLE_CLUSTER3D_REFINE NORMAL STOP ****')

        contains

            ! stash docs, volumes , etc.
            subroutine stash_state(s)
                integer, intent(in) :: s
                character(len=2),            parameter :: one = '01'
                character(len=LONGSTRLEN), allocatable :: files(:)
                character(len=LONGSTRLEN) :: src, dest, vol, fsc, volfilt
                character(len=2)          :: str_state
                character(len=8)          :: str_iter
                integer                   :: i, final_it, stat, l, pos
                final_it  = nint(cline_refine3D(s)%get_rarg('endit'))
                str_state = int2str_pad(s,2)
                str_iter  = '_ITER'//int2str_pad(final_it,3)
                if( s == 1 )then
                    vol     = filepath(dirs(s), trim(VOL_FBODY)//one//trim(params%ext))
                    fsc     = filepath(dirs(s), trim(FSC_FBODY)//one//BIN_EXT)
                    volfilt = filepath(dirs(s), trim(ANISOLP_FBODY)//one//params%ext)
                else
                    ! renames all *state01* files
                     call simple_list_files(trim(dirs(s))//'/*state01*', files)
                     do i=1,size(files)
                         src  = files(i)
                         dest = basename(files(i))
                         l    = len_trim(dest)
                         pos  = index(dest(1:l),'_state01',back=.true.)
                         dest(pos:pos+7) = '_state' // str_state
                         stat = simple_rename(src, filepath(trim(dirs(s)),dest))
                     enddo
                     deallocate(files)
                     call simple_list_files(trim(dirs(s))//'/*STATE01*', files)
                     do i=1,size(files)
                         src  = files(i)
                         dest = basename(files(i))
                         l    = len_trim(dest)
                         pos  = index(dest(1:l),'_STATE01',back=.true.)
                         dest(pos:pos+7) = '_STATE' // str_state
                         stat = simple_rename(src, filepath(trim(dirs(s)),dest))
                     enddo
                     deallocate(files)
                     vol     = filepath(dirs(s), trim(VOL_FBODY)//str_state//trim(params%ext))
                     fsc     = filepath(dirs(s), trim(FSC_FBODY)//str_state//BIN_EXT)
                     volfilt = filepath(dirs(s), trim(ANISOLP_FBODY)//str_state//params%ext)
                endif
                ! updates os_out
                if(params%oritype.eq.'cls3D')then
                    call spproj%add_vol2os_out(vol, params%smpd, s, 'vol_cavg')
                else
                    call spproj_master%add_vol2os_out(vol, params%smpd, s, 'vol')
                endif
                call spproj_master%add_fsc2os_out(fsc, s, params%box)
                call spproj_master%add_vol2os_out(volfilt, params%smpd, s, 'vol_filt', box=params%box)
                call spproj_master%add_frcs2os_out(filepath(dirs(s),FRCS_FILE),'frc3D')
            end subroutine stash_state

            subroutine prep_eo_stks
                use simple_ori, only: ori
                type(ori)                     :: o, o_even, o_odd
                character(len=:), allocatable :: eostk, ext
                integer :: even_ind, odd_ind, state, icls
                do state=1,params%nstates
                    call cline_refine3D(state)%delete('lp')
                    call cline_refine3D(state)%set('frcs',trim(frcs_fname))
                    call cline_refine3D(state)%set('lplim_crit', 0.5)
                    call cline_refine3D(state)%set('clsfrcs',   'yes')
                enddo
                ! add stks
                ext   = '.'//fname2ext( cavg_stk )
                eostk = add2fbody(trim(cavg_stk), trim(ext), '_even')
                call spproj_master%add_stk(eostk, ctfparms)
                eostk = add2fbody(trim(cavg_stk), trim(ext), '_odd')
                call spproj_master%add_stk(eostk, ctfparms)
                ! update orientations parameters
                if(allocated(master_states))deallocate(master_states)
                allocate(master_states(2*ncls), source=0)
                do icls=1,ncls
                    even_ind = icls
                    odd_ind  = ncls+icls
                    call spproj%os_cls3D%get_ori(icls, o)
                    state    = spproj%os_cls3D%get_state(icls)
                    call o%set('class', real(icls)) ! for mapping frcs in 3D
                    call o%set('state', real(state))
                    ! even
                    o_even = o
                    call o_even%set('eo', 0.)
                    call o_even%set('stkind', spproj_master%os_ptcl3D%get(even_ind,'stkind'))
                    call spproj_master%os_ptcl3D%set_ori(even_ind, o_even)
                    master_states(even_ind) = state
                    ! odd
                    o_odd = o
                    call o_odd%set('eo', 1.)
                    call o_odd%set('stkind', spproj_master%os_ptcl3D%get(odd_ind,'stkind'))
                    call spproj_master%os_ptcl3D%set_ori(odd_ind, o_odd)
                    master_states(odd_ind) = state
                enddo
                ! cleanup
                deallocate(eostk, ext)
                call o%kill
                call o_even%kill
                call o_odd%kill
            end subroutine prep_eo_stks

    end subroutine exec_cluster3D_refine

end module simple_commander_hlev_wflows

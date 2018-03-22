! concrete commander: stream processing routines
module simple_commander_stream_wflows
#include "simple_lib.f08"
use simple_cmdline,              only: cmdline
use simple_chash,                only: chash
use simple_params,               only: params
use simple_commander_base,       only: commander_base
use simple_commander_preprocess, only: preprocess_commander
use simple_qsys_env,             only: qsys_env
use simple_jiffys,               only: simple_end
use simple_qsys_funs             ! use all in there
implicit none

public :: preprocess_stream_commander
public :: cluster2D_stream_distr_commander
private
#include "simple_local_flags.inc"

type, extends(commander_base) :: preprocess_stream_commander
  contains
    procedure :: execute      => exec_preprocess_stream
end type preprocess_stream_commander
type, extends(commander_base) :: cluster2D_stream_distr_commander
  contains
    procedure :: execute      => exec_cluster2D_stream_distr
end type cluster2D_stream_distr_commander

contains

    subroutine exec_preprocess_stream( self, cline )
        use simple_commander_preprocess, only: preprocess_commander
        use simple_moviewatcher,         only: moviewatcher
        use simple_sp_project,           only: sp_project
        class(preprocess_stream_commander), intent(inout) :: self
        class(cmdline),                     intent(inout) :: cline
        integer,               parameter   :: SHORTTIME = 60   ! folder watched every minute
        integer,               parameter   :: LONGTIME  = 900  ! 15 mins before processing a new movie
        ! type(merge_algndocs_commander)     :: xmerge_algndocs
        type(qsys_env)                     :: qenv
        type(chash)                        :: job_descr
        ! type(cmdline)                      :: cline_merge_algndocs
        type(params)                       :: p_master
        type(moviewatcher)                 :: movie_buff
        type(sp_project)                   :: spproj
        character(len=STDLEN), allocatable :: movies(:)
        character(len=:),      allocatable :: output_dir, output_dir_ctf_estimate
        character(len=:),      allocatable :: output_dir_motion_correct, output_dir_extract
        character(len=:),      allocatable :: output_dir_picker, fbody
        character(len=LONGSTRLEN)          :: movie
        integer                            :: nmovies, imovie, stacksz, prev_stacksz, iter
        logical                            :: l_pick
        ! set oritype
        if( .not. cline%defined('oritype') ) call cline%set('oritype', 'mic')
        ! make master parameters
        p_master  = params(cline)
        ! picking
        if( cline%defined('refs') )then
            l_pick = .true.
        else
            l_pick = .false.
        endif
        ! output directories
        if( cline%defined('dir') )then
            output_dir = trim(p_master%dir)//'/'
        else
            output_dir = trim(DIR_PREPROC)
        endif
        output_dir_ctf_estimate   = trim(output_dir)//trim(DIR_CTF_ESTIMATE)
        output_dir_motion_correct = trim(output_dir)//trim(DIR_MOTION_CORRECT)
        call mkdir(output_dir)
        call mkdir(output_dir_ctf_estimate)
        call mkdir(output_dir_motion_correct)
        if( l_pick )then
            output_dir_picker  = trim(output_dir)//trim(DIR_PICKER)
            output_dir_extract = trim(output_dir)//trim(DIR_EXTRACT)
            call mkdir(output_dir_picker)
            call mkdir(output_dir_extract)
        endif
        ! read in movies
        call spproj%read_segment( 'mic', p_master%projfile )
        ! main fork
        if( p_master%stream.eq.'yes' )then
            !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! TODO
            ! ! STREAMING
            ! ! set defaults
            ! p_master%numlen     = 5
            ! call cline%set('numlen', real(p_master%numlen))
            ! p_master%split_mode = 'stream'
            ! p_master%ncunits    = p_master%nparts
            ! ! setup the environment for distributed execution
            ! call qenv%new(p_master, stream=.true.)
            ! ! movie watcher init
            ! movie_buff = moviewatcher(p_master, longtime, print=.true.)
            ! ! start watching
            ! prev_stacksz = 0
            ! nmovies      = 0
            ! iter         = 0
            ! do
            !     if( file_exists(trim(TERM_STREAM)) )then
            !         write(*,'(A)')'>>> TERMINATING PREPROCESSING STREAM'
            !         exit
            !     endif
            !     iter = iter + 1
            !     call movie_buff%watch( nmovies, movies )
            !     ! append movies to processing stack
            !     if( nmovies > 0 )then
            !         do imovie = 1, nmovies
            !             movie = trim(adjustl(movies(imovie)))
            !             call create_individual_filetab
            !             call qenv%qscripts%add_to_streaming( cline )
            !         enddo
            !     endif
            !     ! manage stream scheduling
            !     call qenv%qscripts%schedule_streaming( qenv%qdescr )
            !     stacksz = qenv%qscripts%get_stacksz()
            !     if( stacksz .ne. prev_stacksz )then
            !         prev_stacksz = stacksz
            !         write(*,'(A,I5)')'>>> MOVIES TO PROCESS: ', stacksz
            !     endif
            !     ! wait
            !     call simple_sleep(SHORTTIME)
            ! end do
        else
            ! DISTRIBUTED EXECUTION
            ! p_master%nptcls = nlines(p_master%filetab)
            p_master%nptcls = spproj%os_mic%get_noris()
            if( p_master%nparts > p_master%nptcls ) stop 'nr of partitions (nparts) mjust be < number of entries in filetable'
            ! deal with numlen so that length matches JOB_FINISHED indicator files
            p_master%numlen = len(int2str(p_master%nptcls))
            call cline%set('numlen', real(p_master%numlen))
            ! output directory
            ! prepare merge_algndocs command line
            ! cline_merge_algndocs = cline
            ! call cline_merge_algndocs%set( 'nthr',     1.)
            ! call cline_merge_algndocs%set( 'fbody',    trim(fbody))
            ! call cline_merge_algndocs%set( 'nptcls',   real(p_master%nptcls))
            ! call cline_merge_algndocs%set( 'ndocs',    real(p_master%nparts))
            ! call cline_merge_algndocs%set( 'outfile',  trim(output_dir_unidoc)//trim(SIMPLE_UNIDOC))
            ! call cline_merge_algndocs%set( 'numlen',   real(p_master%numlen))
            ! setup the environment for distributed execution
            call qenv%new(p_master, numlen=p_master%numlen)
            ! prepare job description
            call cline%gen_job_descr(job_descr)
            ! schedule & clean
            call qenv%gen_scripts_and_schedule_jobs(p_master, job_descr, algnfbody=trim(ALGN_FBODY))
            ! merge docs
            call spproj%read(p_master%projfile)
            call spproj%merge_algndocs(p_master%nptcls, p_master%nparts, 'mic', ALGN_FBODY)
            call spproj%kill
        endif
        ! cleanup
        call qsys_cleanup(p_master)
        ! end gracefully
        call simple_end('**** SIMPLE_DISTR_PREPROCESS NORMAL STOP ****')
        contains

            subroutine create_individual_filetab
                use simple_fileio, only: fopen, fclose, fileio_errmsg
                integer               :: fnr, file_stat
                character(len=STDLEN) :: fname, ext, movie_here
                movie_here = remove_abspath(trim(movie))
                ext   = fname2ext(trim(movie_here))
                fname = 'preprocess_'//trim(get_fbody(trim(movie_here), trim(ext)))//'.txt'
                call fopen(fnr, status='replace', action='write', file=trim(fname), iostat=file_stat)
                call fileio_errmsg('exec_preprocess_stream :: create_individual_filetab '//trim(fname), file_stat)
                write(fnr,'(a)') trim(movie)
                call fclose(fnr, errmsg='exec_preprocess_stream closing filetab '//trim(fname))
                call cline%set('filetab', fname)
            end subroutine create_individual_filetab

    end subroutine exec_preprocess_stream

    subroutine exec_cluster2D_stream_distr( self, cline )
        use simple_defs_conv
        use simple_timer
        use simple_commander_distr_wflows, only: cluster2D_distr_commander, make_cavgs_distr_commander
        use simple_oris,                   only: oris
        use simple_image,                  only: image
        use simple_sp_project,             only: sp_project
        use simple_binoris_io              ! use all in there
        use simple_extractwatcher          ! use all in there
        use simple_commander_distr         ! use all in there
        use simple_fileio                  ! use all in there
        class(cluster2D_stream_distr_commander), intent(inout) :: self
        class(cmdline),                        intent(inout) :: cline
        character(len=*), parameter :: STK_FILETAB        = 'stkstreamtab.txt'
        character(len=*), parameter :: SCALE_FILETAB      = 'stkscale.txt'
        character(len=*), parameter :: DEFTAB             = 'deftab'//trim(METADATA_EXT)
        character(len=*), parameter :: FINALDOC           = 'cluster2Ddoc_final'//trim(METADATA_EXT)
        integer,          parameter :: SHIFTSRCH_PTCLSLIM = 2000  ! # of ptcls required to turn on shift search
        integer,          parameter :: SHIFTSRCH_ITERLIM  = 5     ! # of iterations prior to turn on shift search
        integer,          parameter :: CCRES_NPTCLS_LIM   = 10000 ! # of ptcls required to turn on objfun=ccres
        integer,          parameter :: WAIT_WATCHER       = 60    ! seconds prior to new stack detection
        integer,          parameter :: MAXNCLS            = 1000  ! maximum # of classes
        type(cluster2D_distr_commander)    :: xcluster2D_distr
        type(make_cavgs_distr_commander)   :: xmake_cavgs
        type(extractwatcher)               :: mic_watcher
        type(cmdline)                      :: cline_cluster2D, cline_scale, cline_make_cavgs
        type(params)                       :: p_master, p_scale
        type(sp_project)                   :: spproj
        class(oris), pointer               :: os => null()
        character(len=STDLEN), allocatable :: newstacks(:), stktab(:)
        character(len=STDLEN)              :: oritab_glob, str_iter, refs_glob, frcs_glob
        real    :: scale, smpd_glob, msk_glob, mul
        integer :: iter, ncls, n_newstks, ldim(3), nptcls, box_original
        integer :: nptcls_glob, nstacks_glob, ncls_glob, box_glob
        integer :: nptcls_glob_prev, ncls_glob_prev, last_injection, tnow
        ! seed the random number generator
        call seed_rnd
        ! output command line executed
        write(*,'(a)') '>>> COMMAND LINE EXECUTED'
        write(*,*) trim(cmdline_glob)
        ! set oritype
        if( .not. cline%defined('oritype') ) call cline%set('oritype', 'ptcl2D')
        ! make master parameters
        p_master = params(cline)
        ! init command-lines
        cline_scale      = cline
        cline_cluster2D  = cline
        cline_make_cavgs = cline
        call cline_cluster2D%set('prg',       'cluster2D')
        call cline_cluster2D%set('stktab',    STK_FILETAB)
        call cline_cluster2D%set('extr_iter', 100.) ! no extremal randomization
        if( p_master%ctf.ne.'no' )then
            call cline_cluster2D%set('deftab', DEFTAB)
        endif
        call cline_scale%set('prg', 'scale')
        call cline_scale%set('ctf','no') ! to clear up display
        call cline_scale%set('filetab', SCALE_FILETAB)
        call cline_scale%set('stream', 'yes')
        call cline_scale%set('numlen', 1.)
        call cline_make_cavgs%set('prg',    'make_cavgs')
        call cline_make_cavgs%set('stktab', STK_FILETAB)
        call cline_make_cavgs%set('refs',   'cavgs_final'//p_master%ext)
        call cline_make_cavgs%delete('autoscale')
        ! scope init
        ncls_glob        = 0
        ncls_glob_prev   = 0
        nptcls_glob      = 0
        nptcls_glob_prev = 0
        nstacks_glob     = 0
        ! prep scaling parameters
        if( p_master%autoscale.eq.'yes' )then
            smpd_glob = LP2SMPDFAC * p_master%lp
            scale     = p_master%smpd / smpd_glob
            call mkdir(trim(SCSTK_DIR))
        else
            msk_glob  = p_master%msk
            smpd_glob = p_master%smpd
            scale     = 1.
        endif
        ! Instantiate watcher
        mic_watcher = extractwatcher(p_master, 30, print=.true.)
        ! Wait for sufficient number of classes
        do
            call mic_watcher%watch(n_newstks)
            if(n_newstks > 0)then
                if( nptcls_glob .eq. 0 )then
                    ! determines & updates scaling parms
                    call mic_watcher%get_new_stacks(stktab)
                    call find_ldim_nptcls(stktab(1), ldim, nptcls)
                    box_original = ldim(1)
                    if( p_master%autoscale.eq.'yes' )then
                        box_glob  = max(64, min(64, find_magic_box(nint(scale*real(ldim(2)))))) ! TO PUT IN DEFS
                        scale     = real(box_glob) / real(box_original)
                        smpd_glob = p_master%smpd / scale
                        msk_glob  = p_master%msk * scale
                        call cline_scale%set('newbox', real(box_glob))
                    else
                        box_glob = box_original
                    endif
                    deallocate(stktab)
                    call cline_cluster2D%set('box',  real(box_glob))
                    call cline_cluster2D%set('smpd', real(smpd_glob))
                    call cline_cluster2D%set('msk',  real(msk_glob))
                endif
                nptcls_glob_prev = nptcls_glob
                call add_newstacks
                ncls = nint(real(nptcls_glob) / p_master%nptcls_per_cls)
                if(ncls >= p_master%ncls_start) exit
            endif
            call simple_sleep(WAIT_WATCHER) ! parameter instead
        enddo
        ncls_glob = ncls
        call cline_cluster2D%set('ncls', real(ncls_glob))
        last_injection = simple_gettime()
        ! Main loop
        do iter = 1, 999
            str_iter = int2str_pad(iter,3)
            ! time limit
            tnow = simple_gettime()
            if(tnow-last_injection > p_master%time_inactive)then
                write(*,*)'>>> TIME LIMIT WITHOUT NEW PARTICLES ADDITION REACHED'
                exit
            endif
            ! cluster2D
            call cline_cluster2D%set('startit', real(iter))
            call cline_cluster2D%set('maxits',  real(iter))
            call cline_cluster2D%delete('endit')
            call cline_cluster2D%set('ncls',    real(ncls_glob))
            call cline_cluster2D%set('nparts',  real(min(ncls,p_master%nparts)))
            if(nptcls_glob > SHIFTSRCH_PTCLSLIM .and. iter > SHIFTSRCH_ITERLIM)then
                call cline_cluster2D%set('trs', MINSHIFT)
            endif
            if(nptcls_glob > CCRES_NPTCLS_LIM)then
                call cline_cluster2D%set('objfun', 'ccres')
            endif
            call xcluster2D_distr%execute(cline_cluster2D)
            oritab_glob = trim(CLUSTER2D_ITER_FBODY)//trim(str_iter)//trim(METADATA_EXT)
            refs_glob   = trim(CAVGS_ITER_FBODY)//trim(str_iter)//trim(p_master%ext)
            frcs_glob   = trim(FRCS_ITER_FBODY)//trim(str_iter)//'.bin'
            call cline_cluster2D%set('oritab', trim(oritab_glob))
            call cline_cluster2D%set('refs',   trim(refs_glob))
            call remap_empty_classes
            ! user termination
            if( file_exists(trim(TERM_STREAM)) )then
                write(*,'(A)')'>>> TERMINATING CLUSTER2D STREAM'
                exit
            endif
            ! detects new images
            call mic_watcher%watch(n_newstks)
            if(n_newstks > 0)then
                nptcls_glob_prev = nptcls_glob
                call add_newstacks
                ! updates particles classes & references
                ncls_glob_prev = ncls_glob
                ncls_glob      = nint(real(nptcls_glob) / p_master%nptcls_per_cls)
                ncls_glob      = min(ncls_glob, MAXNCLS)
                call remap_new_classes
                last_injection = simple_gettime()
            endif
        enddo
        ! class averages at original sampling
        call spproj%new_seg_with_ptr(nptcls_glob, p_master%oritype, os)
        call binread_oritab(oritab_glob, spproj, os, [1,nptcls_glob])
        call os%mul_shifts(1./scale)
        call binwrite_oritab(FINALDOC, spproj, os, [1,nptcls_glob])
        call cline_make_cavgs%set('oritab',  trim(FINALDOC))
        call cline_make_cavgs%set('ncls', real(ncls_glob))
        call xmake_cavgs%execute(cline_make_cavgs)
        ! cleanup
        call qsys_cleanup(p_master)
        ! end gracefully
        call simple_end('**** SIMPLE_DISTR_CLUSTER2D_STREAM NORMAL STOP ****')

        contains

            subroutine add_newstacks
                use simple_commander_imgproc, only: scale_commander
                type(qsys_env)                     :: qenv
                type(sp_project)                   :: spproj_glob, spproj_here
                class(oris), pointer               :: deftab_glob=>null(), deftab_here=>null()
                character(len=STDLEN), allocatable :: new_deftabs(:), new_stacks(:), tmp(:)
                character(len=STDLEN) :: stk_scaled, fbody, ext
                integer               :: i, j, nl, nptcls, cnt, cnt2, n, ldim(3), iptcl
                call mic_watcher%get_new_stacks(new_stacks)
                ! number of new particles
                nptcls = 0
                do i = 1, n_newstks
                    call find_ldim_nptcls(new_stacks(i), ldim, n)
                    nptcls = nptcls + n
                enddo
                nptcls_glob = nptcls_glob + nptcls
                write(*,'(A,I6)')'>>> NEW PARTICLES COUNT: ', nptcls_glob
                if( p_master%ctf.ne.'no' )then
                    ! consolidate deftabs
                    call mic_watcher%get_new_deftabs(new_deftabs)
                    call spproj_glob%new_seg_with_ptr(nptcls_glob, p_master%oritype, deftab_glob)
                    if( nptcls_glob_prev > 0 )then
                        ! transfer previous ctf params to new object
                        call binread_oritab(trim(deftab), spproj_glob, deftab_glob, [1, nptcls_glob_prev])
                    endif
                    ! transfer new ctf params to new object
                    cnt = nptcls_glob_prev
                    do i = 1, n_newstks
                        nl = binread_nlines(p_master, new_deftabs(i))
                        call spproj_here%new_seg_with_ptr(nl, p_master%oritype, deftab_here)
                        call binread_oritab(trim(new_deftabs(i)), spproj_here, deftab_here, [1, nl])
                        cnt2 = 0
                        do j = cnt+1, cnt+nl
                            cnt2 = cnt2 + 1
                            call deftab_glob%set_ori(j, deftab_here%get_ori(cnt2))
                        enddo
                        cnt = cnt + nl
                    enddo
                    call deftab_here%kill
                    call binwrite_oritab(trim(deftab), spproj_glob, deftab_glob, [1, nptcls_glob])
                endif
                ! stacks
                if( nstacks_glob == 0 )then
                    allocate(stktab(n_newstks))
                else
                    ! updates stacks array
                    tmp = stktab
                    deallocate(stktab)
                    allocate(stktab(nstacks_glob+n_newstks))
                    stktab(1:nstacks_glob) = tmp(1:nstacks_glob)
                endif
                ! down-scaling and name updates
                if( p_master%autoscale.eq.'yes' )then
                    call write_filetable(SCALE_FILETAB, new_stacks)
                    call qenv%new(p_master)
                    cnt = 0
                    do i = nstacks_glob+1, nstacks_glob+n_newstks
                        cnt = cnt + 1
                        ext       = fname2ext(trim(remove_abspath(trim(new_stacks(cnt)))))
                        fbody     = get_fbody(trim(remove_abspath(trim(new_stacks(cnt)))), trim(ext))
                        stktab(i) = trim(SCSTK_DIR) // trim(fbody)// SCALE_SUFFIX // p_master%ext
                        call cline_scale%set('dir_target', trim(SCSTK_DIR))
                    enddo
                    call qenv%exec_simple_prg_in_queue(cline_scale, 'OUT1','JOB_FINISHED_1')
                    call qsys_cleanup(p_master)
                    call del_file(SCALE_FILETAB)
                else
                    cnt = 0
                    do i = nstacks_glob+1, nstacks_glob+n_newstks
                        cnt = cnt + 1
                        stktab(i) = trim(new_stacks(cnt))
                    enddo
                endif
                nstacks_glob = nstacks_glob + n_newstks
                call write_filetable(STK_FILETAB, stktab)
            end subroutine add_newstacks

            subroutine remap_empty_classes
                integer, allocatable  :: fromtocls(:,:)
                integer               :: icls
                class(oris), pointer  :: os => null()
                type(sp_project)      :: spproj
                type(image)           :: img_cavg
                character(len=STDLEN) :: stk
                call spproj%new_seg_with_ptr(nptcls_glob, p_master%oritype, os)
                call binread_oritab(oritab_glob, spproj, os, [1, nptcls_glob])
                call os%fill_empty_classes(ncls_glob, fromtocls)
                if( allocated(fromtocls) )then
                    ! updates document & classes
                    call binwrite_oritab(oritab_glob, spproj, os, [1, nptcls_glob])
                    call img_cavg%new([box_glob, box_glob,1], smpd_glob)
                    do icls = 1, size(fromtocls, dim=1)
                        ! cavg
                        call img_cavg%read(trim(refs_glob), fromtocls(icls, 1))
                        call img_cavg%write(trim(refs_glob), fromtocls(icls, 2))
                        ! even & odd
                        stk = add2fbody(trim(refs_glob),p_master%ext,'_even')
                        call img_cavg%read(stk, fromtocls(icls, 1))
                        call img_cavg%write(stk, fromtocls(icls, 2))
                        stk = add2fbody(trim(refs_glob),p_master%ext,'_odd')
                        call img_cavg%read(stk, fromtocls(icls, 1))
                        call img_cavg%write(stk, fromtocls(icls, 2))
                    enddo
                    ! stack size preservation
                    call img_cavg%read(trim(refs_glob), ncls_glob)
                    call img_cavg%write(trim(refs_glob), ncls_glob)
                    stk = add2fbody(trim(refs_glob),p_master%ext,'_even')
                    call img_cavg%read(stk, ncls_glob)
                    call img_cavg%write(stk, ncls_glob)
                    stk = add2fbody(trim(refs_glob),p_master%ext,'_odd')
                    call img_cavg%read(stk, ncls_glob)
                    call img_cavg%write(stk, ncls_glob)
                endif
            end subroutine remap_empty_classes

            subroutine remap_new_classes
                use simple_ran_tabu,        only: ran_tabu
                use simple_projection_frcs, only: projection_frcs
                type(ran_tabu)        :: rt
                class(oris), pointer  :: os => null()
                type(sp_project)      :: spproj
                type(projection_frcs) :: frcs_prev, frcs
                type(image)           :: img_cavg
                integer, allocatable  :: fromtocls(:,:), cls(:), pops(:)
                integer               :: icls, ncls_prev, n, iptcl, i, state
                character(len=STDLEN) :: stk
                call spproj%new_seg_with_ptr(nptcls_glob, p_master%oritype, os)
                call binread_oritab(oritab_glob, spproj, os, [1, nptcls_glob_prev])
                n = nptcls_glob - nptcls_glob_prev
                state = 1
                ! randomize new ptcls to previous references
                allocate(cls(n))
                rt = ran_tabu(n)
                call rt%balanced(ncls_glob_prev, cls)
                do i = 1, n
                    iptcl = nptcls_glob_prev + i
                    call os%set(iptcl, 'class', real(cls(i)))
                    call os%set(iptcl, 'w',     1.)
                    call os%set(iptcl, 'corr',  0.)
                enddo
                deallocate(cls)
                ! updates doc, references &FRCs
                if( ncls_glob.eq.ncls_glob_prev )then
                    ! nothing to do
                else
                    write(*,'(A,I6)')'>>> NEW CLASSES COUNT: ', ncls_glob
                    call os%fill_empty_classes(ncls_glob, fromtocls)
                    if( allocated(fromtocls) )then
                        ! references
                        call img_cavg%new([box_glob, box_glob,1], smpd_glob)
                        do icls = 1, size(fromtocls, dim=1)
                            ! cavg
                            call img_cavg%read(trim(refs_glob), fromtocls(icls, 1))
                            call img_cavg%write(trim(refs_glob), fromtocls(icls, 2))
                            ! even & odd
                            stk = add2fbody(trim(refs_glob),p_master%ext,'_even')
                            call img_cavg%read(stk, fromtocls(icls, 1))
                            call img_cavg%write(stk, fromtocls(icls, 2))
                            stk = add2fbody(trim(refs_glob),p_master%ext,'_odd')
                            call img_cavg%read(stk, fromtocls(icls, 1))
                            call img_cavg%write(stk, fromtocls(icls, 2))
                        enddo
                        ! stack size preservation
                        call img_cavg%read(trim(refs_glob), ncls_glob)
                        call img_cavg%write(trim(refs_glob), ncls_glob)
                        stk = add2fbody(trim(refs_glob),p_master%ext,'_even')
                        call img_cavg%read(stk, ncls_glob)
                        call img_cavg%write(stk, ncls_glob)
                        stk = add2fbody(trim(refs_glob),p_master%ext,'_odd')
                        call img_cavg%read(stk, ncls_glob)
                        call img_cavg%write(stk, ncls_glob)
                        ! FRCs
                        if( p_master%match_filt.eq.'yes')then
                            call frcs_prev%new(ncls_glob_prev, box_glob, smpd_glob, state)
                            call frcs%new(ncls_glob, box_glob, smpd_glob, state)
                            call frcs_prev%read(frcs_glob)
                            do icls = 1, ncls_glob_prev
                                call frcs%set_frc(icls,&
                                &frcs_prev%get_frc(icls, box_glob, state), state)
                            enddo
                            do icls = 1, size(fromtocls, dim=1)
                                call frcs%set_frc( fromtocls(icls,2),&
                                &frcs%get_frc(fromtocls(icls,1), box_glob, state), state)
                            enddo
                            call frcs%write(frcs_glob)
                        endif
                    endif
                endif
                ! document
                call binwrite_oritab(oritab_glob, spproj, os, [1, nptcls_glob])
            end subroutine remap_new_classes

    end subroutine exec_cluster2D_stream_distr

end module simple_commander_stream_wflows

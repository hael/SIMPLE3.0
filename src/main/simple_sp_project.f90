module simple_sp_project
include 'simple_lib.f08'
use simple_ori,     only: ori
use simple_oris,    only: oris
use simple_binoris, only: binoris
implicit none

public :: sp_project, transfer_sp_project_segment
private

integer, parameter :: MAXN_OS_SEG = 13
character(len=4)   :: NULL = 'null'

type sp_project
    ! ORIS REPRESENTATIONS OF BINARY FILE SEGMENTS
    ! segments 1-10 reserved for simple program outputs, orientations and files
    ! In segment 7 we stash class averages, ranked class averages, final volumes etc.
    type(oris)        :: os_mic    ! micrographs,              segment 1
    type(oris)        :: os_stk    ! per-micrograph stack os,  segment 2
    type(oris)        :: os_ptcl2D ! per-particle 2D os,       segment 3
    type(oris)        :: os_cls2D  ! per-cluster 2D os,        segment 4
    type(oris)        :: os_cls3D  ! per-cluster 3D os,        segment 5
    type(oris)        :: os_ptcl3D ! per-particle 3D os,       segment 6
    type(oris)        :: os_out    ! critical project outputs, segment 7

    ! ARRAY REPRESENTATIONS OF BINARY FILE SEGMENTS FOR FRCS & FSCS
    real, allocatable :: frcs(:,:) ! Fourier Ring  Corrs      segment 9
    real, allocatable :: fscs(:,:) ! Fourier Shell Corrs      segment 10

    ! ORIS REPRESENTATIONS OF PROJECT DATA / DISTRIBUTED SYSTEM INFO / SYSTEM MANAGEMENT STUFF
    ! segments 11-20 reserved for project info, job management etc.
    type(oris)        :: projinfo  ! project information      segment 11
    type(oris)        :: jobproc   ! jobid + PID + etc.       segment 12
    type(oris)        :: compenv   ! computing environment    segment 13

    ! binary file-handler
    type(binoris) :: bos
contains
    ! field constructor
    procedure          :: new_seg_with_ptr
    ! field updaters
    procedure          :: update_projinfo
    procedure          :: update_compenv
    ! index management
    procedure, private :: map_ptcl_ind2stk_ind
    procedure          :: add_single_movie
    procedure          :: add_movies
    ! project editing
    procedure          :: append_project
    ! os_stk related methods
    procedure          :: add_stk
    procedure          :: add_stktab
    procedure          :: add_single_stk
    procedure          :: get_stkname
    procedure          :: get_stkname_and_ind
    procedure, private :: add_scale_tag
    ! os_out related methods
    procedure          :: add_cavgs2os_out
    ! getters
    procedure          :: get_nptcls
    procedure          :: get_box
    procedure          :: get_smpd
    procedure          :: get_nmics
    procedure          :: get_nmovies
    procedure          :: get_ctfflag
    procedure          :: get_ctfflag_type
    procedure          :: get_ctfmode
    procedure          :: has_phaseplate
    procedure          :: get_ctfparams
    procedure          :: is_virgin_field
    ! modifiers
    procedure          :: split_stk
    procedure          :: set_sp_oris
    procedure          :: scale_projfile
    procedure          :: merge_algndocs
    procedure          :: map2ptcls
    ! printers
    procedure          :: print_info
    ! I/O
    ! readers
    procedure          :: read
    procedure          :: read_ctfparams_state_eo
    procedure          :: read_segment
    procedure, private :: segreader
    procedure, private :: read_2Darray_segment
    ! writers
    procedure          :: write
    procedure          :: write_segment
    procedure, private :: segwriter
    ! destructor
    procedure          :: kill
end type sp_project

contains

    ! file-handling

    subroutine transfer_sp_project_segment( fname_provider, fname_reciever, oritype )
        character(len=*), intent(in) :: fname_provider, fname_reciever, oritype
        type(sp_project) :: sp_provider, sp_reciever
        call sp_reciever%read(fname_reciever)
        call sp_provider%read_segment(oritype, fname_provider)
        select case(trim(oritype))
            case('mic')
                sp_reciever%os_mic    = sp_provider%os_mic
            case('stk')
                sp_reciever%os_stk    = sp_provider%os_stk
            case('ptcl2D')
                sp_reciever%os_ptcl2D = sp_provider%os_ptcl2D
            case('cls2D')
                sp_reciever%os_cls2D  = sp_provider%os_cls2D
            case('cls3D')
                sp_reciever%os_cls3D  = sp_provider%os_cls3D
            case('ptcl3D')
                sp_reciever%os_ptcl3D = sp_provider%os_ptcl3D
            case('out')
                sp_reciever%os_out    = sp_provider%os_out
            case DEFAULT
                write(*,*) 'oritype: ', trim(oritype)
                stop 'unsupported oritype; sp_project :: transfer_sp_project_segment'
        end select
        call sp_reciever%write(fname_reciever)
    end subroutine transfer_sp_project_segment

    ! field constructor

    subroutine new_seg_with_ptr( self, n, oritype, os_ptr )
        class(sp_project), target, intent(inout) :: self
        integer,                   intent(in)    :: n
        character(len=*),          intent(in)    :: oritype
        class(oris), pointer,      intent(inout) :: os_ptr
        select case(trim(oritype))
            case('mic')
                call self%os_mic%new_clean(n)
                os_ptr => self%os_mic
            case('stk')
                call self%os_stk%new_clean(n)
                os_ptr => self%os_stk
            case('ptcl2D')
                call self%os_ptcl2D%new_clean(n)
                os_ptr => self%os_ptcl2D
            case('cls2D')
                call self%os_cls2D%new_clean(n)
                os_ptr => self%os_cls2D
            case('cls3D')
                call self%os_cls3D%new_clean(n)
                os_ptr => self%os_cls3D
            case('ptcl3D')
                call self%os_ptcl3D%new_clean(n)
                os_ptr => self%os_ptcl3D
            case('out')
                call self%os_out%new_clean(n)
                os_ptr => self%os_out
            case DEFAULT
                write(*,*) 'oritype: ', trim(oritype)
                stop 'unsupported oritype; sp_project :: new_with_os_segptr'
        end select
    end subroutine new_seg_with_ptr

    ! field updaters

    subroutine update_projinfo( self, cline )
        use simple_cmdline, only: cmdline
        class(sp_project), intent(inout) :: self
        class(cmdline),    intent(in)    :: cline
        character(len=:), allocatable :: projname
        character(len=STDLEN)         :: projfile, cwd
        if( self%projinfo%get_noris() == 1 )then
            ! no need to construct field
        else
            call self%projinfo%new_clean(1)
        endif
        ! projname & profile
        if( self%projinfo%isthere('projname') )then
            if( cline%defined('projname') )then
                projname = cline%get_carg('projname')
                call self%projinfo%set(1, 'projname', trim(projname))
                call self%projinfo%set(1, 'projfile', trim(projname)//'.simple')
            endif
        else
            if( .not. cline%defined('projname') .and. .not. cline%defined('projfile') )then
                stop 'ERROR, the project needs a name, inputted via projname or projfile!'
            endif
            if( cline%defined('projfile') )then
                projfile = cline%get_carg('projfile')
                select case(fname2format(projfile))
                    case('O')
                        call self%projinfo%set(1, 'projfile', trim(projfile) )
                    case DEFAULT
                        write(*,*) 'Inputted projfile: ', trim(projfile)
                        stop 'has unsupported format'
                end select
                projname = get_fbody(projfile, 'simple')
                call self%projinfo%set(1, 'projname', trim(projname))
            endif
            if( cline%defined('projname') )then
                projname = cline%get_carg('projname')
                call self%projinfo%set(1, 'projname', trim(projname))
                call self%projinfo%set(1, 'projfile', trim(projname)//'.simple')
            endif
        endif
        ! it is assumed that the project is created in the root "project directory", i.e. stash cwd
        call simple_getcwd(cwd)
        call self%projinfo%set(1, 'cwd', trim(cwd))
    end subroutine update_projinfo

    subroutine update_compenv( self, cline )
        use simple_cmdline, only: cmdline
        class(sp_project), intent(inout) :: self
        class(cmdline),    intent(in)    :: cline
        character(len=STDLEN)            :: env_var
        character(len=:), allocatable    :: projname
        integer :: iostat
        if( self%compenv%get_noris() == 1 )then
            ! no need to construct field
        else
            call self%compenv%new_clean(1)
        endif
        ! compenv has to be filled as strings as it is used as a string only dictionnary
        ! get from environment
        iostat  = simple_getenv('SIMPLE_PATH', env_var)
        if( iostat /= 0 )then
            write(*,*) 'ERROR! SIMPLE_PATH is not defined in your shell environment!'
            write(*,*) 'Please refer to installation documentation for correct system configuration'
            stop
        else
            call self%compenv%set(1, 'simple_path', trim(env_var))
        endif
        iostat  = simple_getenv('SIMPLE_QSYS', env_var)
        if( iostat /= 0 )then
            stop 'SIMPLE_QSYS is not defined in your environment.'
        else
            iostat  = simple_getenv('SIMPLE_QSYS', env_var)
            call self%compenv%set(1, 'qsys_name', trim(env_var))
        endif
        iostat = simple_getenv('SIMPLE_EMAIL', env_var)
        if( iostat/=0 ) env_var = 'my.name@uni.edu'
        call self%compenv%set(1, 'user_email', trim(env_var))
        ! get from command line
        if( cline%defined('time_per_image') )then
            call self%compenv%set(1, 'time_per_image', real2str(cline%get_rarg('time_per_image')))
        else
            if( .not. self%compenv%isthere('time_per_image') )then
                call self%compenv%set(1, 'time_per_image', int2str(TIME_PER_IMAGE_DEFAULT))
            endif
        endif
        if( cline%defined('user_account') )then
            call self%compenv%set(1, 'user_account', cline%get_carg('user_account'))
        endif
        if( cline%defined('user_project') )then
            call self%compenv%set(1, 'user_project', cline%get_carg('user_project'))
        endif
        if( cline%defined('qsys_partition') )then
            call self%compenv%set(1, 'qsys_partition', cline%get_carg('qsys_partition'))
        endif
        if( cline%defined('qsys_qos') )then
            call self%compenv%set(1, 'qsys_qos', cline%get_carg('qsys_qos'))
        endif
        if( cline%defined('qsys_reservation') )then
            call self%compenv%set(1, 'qsys_reservation', cline%get_carg('qsys_reservation'))
        endif
        if( .not. self%compenv%isthere('job_name') )then
            call self%projinfo%getter(1, 'projname', projname)
            call self%compenv%set(1, 'job_name', 'simple_'//trim(projname) )
        endif
        if( cline%defined('job_memory_per_task') )then
            call self%compenv%set(1, 'job_memory_per_task', real2str(cline%get_rarg('job_memory_per_task')) )
        else
            if( .not. self%compenv%isthere('job_memory_per_task') )then
                call self%compenv%set(1, 'job_memory_per_task', int2str(JOB_MEMORY_PER_TASK_DEFAULT) )
            endif
        endif
    end subroutine update_compenv

    ! index management

    subroutine map_ptcl_ind2stk_ind( self, oritype, iptcl, stkind, ind_in_stk )
        class(sp_project), target, intent(inout) :: self
        character(len=*),          intent(in)    :: oritype
        integer,                   intent(in)    :: iptcl
        integer,                   intent(out)   :: stkind
        integer,                   intent(out)   :: ind_in_stk
        class(oris), pointer                     :: ptcl_field
        integer :: nptcls, fromp, top
        nullify(ptcl_field)
        ! set field pointer
        select case(trim(oritype))
            case('ptcl2D')
                ptcl_field => self%os_ptcl2D
            case('ptcl3D')
                ptcl_field => self%os_ptcl3D
            case DEFAULT
                write(*,*) 'oritype: ', trim(oritype), ' is not supported by this method'
                stop 'sp_project :: map_ptcl_ind2stk_ind'
        end select
        nptcls = ptcl_field%get_noris()
        ! first sanity check, range
        if( iptcl < 1 .or. iptcl > nptcls )then
            print *, 'iptcl : ', iptcl
            print *, 'nptcls: ', nptcls
            stop 'iptcl index out of range; sp_project :: map_ptcl_ind2stk_ind'
        endif
        ! second sanity check, stack index present in ptcl_field
        if( .not. ptcl_field%isthere(iptcl, 'stkind') )then
            print *, 'iptcl: ', iptcl
            print *, 'ERROR, stkind not present in field: ', trim(oritype)
            stop 'sp_project :: map_ptcl_ind2stk_ind'
        endif
        stkind = nint(ptcl_field%get(iptcl, 'stkind'))
        ! third sanity check, particle index in range
        fromp = nint(self%os_stk%get(stkind, 'fromp'))
        top   = nint(self%os_stk%get(stkind, 'top'))
        if( iptcl < fromp .or. iptcl > top )then
            print *, 'iptcl            : ', iptcl
            print *, 'prange for micstk: ', fromp, top
            stop 'iptcl index out of micstk range; sp_project :: map_ptcl_ind2stk_ind'
        endif
        ! output index in stack
        ind_in_stk = iptcl - fromp + 1
    end subroutine map_ptcl_ind2stk_ind

    ! project editing

    !> append segment to current project. BOTH projects must be read in first!
    subroutine append_project( self, proj, oritype )
        class(sp_project), target, intent(inout) :: self, proj
        character(len=*),          intent(in)    :: oritype
        class(oris),          pointer :: os_ptr, os_append_ptr
        type(oris)                    :: os
        type(ctfparams)               :: ctfvar
        character(len=:), allocatable :: stk
        real                          :: smpd, smpd_self
        integer                       :: i, cnt, n, n2append
        select case(trim(oritype))
            case('mic')
                os_ptr => self%os_mic
                os_append_ptr => proj%os_mic
            case('stk')
                os_ptr => self%os_stk
                os_append_ptr => proj%os_stk
            case DEFAULT
                write(*,*) 'oritype: ', trim(oritype)
                stop 'unsupported oritype for this purpose; sp_project :: append_project'
        end select
        n2append = os_append_ptr%get_noris()
        if( n2append == 0 )return
        smpd = os_append_ptr%get(1, 'smpd')
        n    = os_ptr%get_noris()
        if( n == 0 )then
            ! first entry
        else
            smpd_self = os_ptr%get(1, 'smpd')
            if( abs(smpd-smpd_self) > 0.001 )then
                write(*,*) 'smpd self', smpd_self
                write(*,*) 'smpd 2 append', smpd
                stop ' Only a project with the same smpd can be appended to the project; simple_sp_project :: append_project'
            endif
        endif
        select case(trim(oritype))
            case('mic')
                if( n == 0 )then
                    os_ptr = os_append_ptr
                else
                    ! append
                    call os%new_clean(n + n2append)
                    do i=1,n
                        call os%set_ori(i, os_ptr%get_ori(i))
                    enddo
                    cnt = n
                    do i=1,n2append
                        cnt = cnt + 1
                        call os%set_ori(cnt, os_append_ptr%get_ori(i))
                    enddo
                    os_ptr = os
                endif
            case('stk')
                call os_append_ptr%getter(1, 'stk', stk)
                ctfvar = proj%get_ctfparams('ptcl2D', 1)
                call self%add_stk(stk, ctfvar, proj%os_ptcl2D)
        end select
    end subroutine append_project

    ! os_mic related methods

    subroutine add_single_movie( self, moviename, ctfvars )
        class(sp_project), target, intent(inout) :: self
        character(len=*),          intent(in)    :: moviename
        type(ctfparams),           intent(in)    :: ctfvars
        class(oris),      pointer     :: os_ptr
        character(len=:), allocatable :: fname, prev_imgfmt
        character(len=STDLEN)         :: str
        character(len=3)              :: imgfmt
        integer :: n_os_mic, ldim(3), nframes
        ! oris object pointer
        os_ptr => self%os_mic
        ! check that stk field is empty
        n_os_mic = os_ptr%get_noris()
        if( n_os_mic > 0 )then
            write(*,*) 'stack field (self%os_stk) already populated with # entries: ', n_os_mic
            stop 'ABORTING! sp_project :: add_single_movie'
        endif
        ! update ori
        call os_ptr%new_clean(1)
        call simple_full_path(moviename, fname, 'simple_sp_project::add_single_movie')
        call find_ldim_nptcls(trim(fname), ldim, nframes)
        if( nframes <= 0 )then
            write(*,*) 'WARNING! # frames in movie ', trim(fname), ' <= zero, ommitting'
        else if( nframes > 1 )then
            call os_ptr%set(1, 'movie', trim(fname))
            call os_ptr%set(1, 'imgkind', 'movie')
            call os_ptr%set(1, 'nframes',    real(nframes))
        else
            call os_ptr%set(1, 'intg',  trim(fname))
            call os_ptr%set(1, 'imgkind', 'mic')
        endif
        ! image format
        str    = fname2ext(fname)
        imgfmt = str(1:3)
        if( self%projinfo%isthere('imgfmt') )then
            call self%projinfo%getter(1, 'imgfmt', prev_imgfmt)
            if( imgfmt(1:3).ne.trim(prev_imgfmt) )stop 'Cannot mix 2 image formats in one project! simple_sp_project::add_stk'
        else
            call self%projinfo%set(1,'imgfmt', trim(imgfmt))
        endif
        ! updates segment
        call os_ptr%set(1, 'xdim',       real(ldim(1)))
        call os_ptr%set(1, 'ydim',       real(ldim(2)))
        call os_ptr%set(1, 'smpd',       ctfvars%smpd)
        call os_ptr%set(1, 'kv',         ctfvars%kv)
        call os_ptr%set(1, 'cs',         ctfvars%cs)
        call os_ptr%set(1, 'fraca',      ctfvars%fraca)
        if( ctfvars%l_phaseplate )then
            call os_ptr%set(1, 'phaseplate', 'yes')
        else
            call os_ptr%set(1, 'phaseplate', 'no')
        endif
        select case(ctfvars%ctfflag)
            case(0)
                call os_ptr%set(1, 'ctf', 'no')
            case(1)
                call os_ptr%set(1, 'ctf', 'yes')
            case(2)
                call os_ptr%set(1, 'ctf', 'flip')
            case DEFAULT
                write(*,*) 'ctfvars%ctfflag: ', ctfvars%ctfflag
                stop 'ERROR, unsupported ctfflag; sp_project :: add_single_movie'
        end select
    end subroutine add_single_movie

    ! subroutine add_movies( self, filetab, smpd, kv, cs, fraca, phaseplate )
    subroutine add_movies( self, filetab, ctfvars )
        class(sp_project), target, intent(inout) :: self
        character(len=*),          intent(in)    :: filetab
        type(ctfparams),           intent(in)    :: ctfvars
        class(oris),           pointer     :: os_ptr
        character(len=STDLEN), allocatable :: movienames(:)
        character(len=:),      allocatable :: name, moviename, prev_imgfmt
        character(len=STDLEN) :: str
        character(len=3)      :: imgfmt
        integer               :: imic, ldim(3), nframes, nmics, nprev_mics, cnt, ntot
        logical               :: is_movie
        ! file exists?
        if( .not. file_exists(filetab) )then
            write(*,*) 'Inputted movie list (filetab): ', trim(filetab)
            stop 'does not exist in cwd; sp_project :: add_movies'
        endif
        ! oris object pointer
        os_ptr => self%os_mic
        ! read movie names
        call read_filetable(filetab, movienames)
        nmics = size(movienames)
        ! update oris
        nprev_mics = os_ptr%get_noris()
        ntot       = nmics + nprev_mics
        if( nprev_mics == 0 )then
            call os_ptr%new_clean(ntot)
        else
            call os_ptr%reallocate(ntot)
        endif
        cnt = 0
        do imic=nprev_mics + 1,ntot
            cnt = cnt + 1
            call simple_full_path(movienames(cnt), moviename, 'simple_sp_project::add_movies')
            call find_ldim_nptcls(trim(moviename), ldim, nframes)
            if( nframes <= 0 )then
                write(*,*) 'WARNING! # frames in movie ', trim(moviename), ' <= zero, ommitting'
                cycle
            else if( nframes > 1 )then
                call os_ptr%set(imic, 'movie', trim(moviename))
                call os_ptr%set(imic, 'imgkind', 'movie')
                is_movie = .false.
            else
                call os_ptr%set(imic, 'intg',  trim(moviename))
                call os_ptr%set(imic, 'imgkind', 'mic')
                is_movie = .true.
            endif
            ! image format
            str    = fname2ext(moviename)
            imgfmt = str(1:3)
            if( self%projinfo%isthere('imgfmt') )then
                call self%projinfo%getter(1, 'imgfmt', prev_imgfmt)
                if( imgfmt(1:3).ne.trim(prev_imgfmt) )stop 'Cannot mix 2 image formats in one project! simple_sp_project::add_stk'
                deallocate(prev_imgfmt)
            else
                call self%projinfo%set(1,'imgfmt', trim(imgfmt))
            endif
            ! updates segment
            call os_ptr%set(imic, 'xdim',       real(ldim(1)))
            call os_ptr%set(imic, 'ydim',       real(ldim(2)))
            call os_ptr%set(imic, 'nframes',    real(nframes))
            call os_ptr%set(imic, 'smpd',       ctfvars%smpd)
            call os_ptr%set(imic, 'kv',         ctfvars%kv)
            call os_ptr%set(imic, 'cs',         ctfvars%cs)
            call os_ptr%set(imic, 'fraca',      ctfvars%fraca)
            if( ctfvars%l_phaseplate )then
                call os_ptr%set(imic, 'phaseplate', 'yes')
            else
                call os_ptr%set(imic, 'phaseplate', 'no')
            endif
            select case(ctfvars%ctfflag)
                case(0)
                    call os_ptr%set(imic, 'ctf', 'no')
                case(1)
                    call os_ptr%set(imic, 'ctf', 'yes')
                case(2)
                    call os_ptr%set(imic, 'ctf', 'flip')
                case DEFAULT
                    write(*,*) 'ctfvars%ctfflag: ', ctfvars%ctfflag
                    stop 'ERROR, unsupported ctfflag; sp_project :: add_movies'
            end select
            deallocate(moviename)
        enddo
        if( is_movie )then
            name = 'MOVIE(S)'
        else
            name = 'MICROGRAPH(S)'
        endif
        write(*,'(A13,I6,A1,A)')'>>> IMPORTED ', nmics,' ', trim(name)
        write(*,'(A20,A,A1,I6)')'>>> TOTAL NUMBER OF ', trim(name),':',ntot
    end subroutine add_movies

    ! os_stk related methods

    subroutine add_stk( self, stk, ctfvars, os )
        class(sp_project),     intent(inout) :: self
        character(len=*),      intent(in)    :: stk
        type(ctfparams),       intent(in)    :: ctfvars ! CTF parameters associated with stk
        class(oris),           intent(inout) :: os      ! parameters associated with stk
        type(ori)                     :: o
        character(len=:), allocatable :: stk_abspath, prev_imgfmt
        character(len=STDLEN)         :: str
        character(len=3)              :: imgfmt
        integer :: ldim(3), nptcls, n_os, n_os_stk, n_os_ptcl2D, n_os_ptcl3D
        integer :: i, fromp, top
        ! fuul path and existence check
        call simple_full_path(stk, stk_abspath, 'sp_project :: add_stk')
        ! find dimension of inputted stack
        call find_ldim_nptcls(stk_abspath, ldim, nptcls)
        if( ldim(1) /= ldim(2) )then
            write(*,*) 'xdim: ', ldim(1)
            write(*,*) 'ydim: ', ldim(2)
            stop 'ERROR! nonsquare particle images not supported; sp_project :: add_stk'
        endif
        ! check that inputs are of conforming sizes
        n_os = os%get_noris()
        if( n_os /= nptcls )then
            write(*,*) '# input oris      : ', n_os
            write(*,*) '# ptcl imgs in stk: ', nptcls
            stop 'ERROR! nonconforming sizes of inputs; sp_project :: add_stk'
        endif
        ! existence of ctf/defocus values
        if( ctfvars%ctfflag > 0 )then
            if( .not.os%isthere(1,'dfx') )then
                stop 'ERROR! ctf .ne. no and input lacks dfx; sp_project :: add_stk'
            endif
        endif
        ! updates_fields
        n_os_stk    = self%os_stk%get_noris() + 1
        n_os_ptcl2D = self%os_ptcl2D%get_noris()
        n_os_ptcl3D = self%os_ptcl3D%get_noris()
        if( n_os_stk == 1 )then
            call self%os_stk%new_clean(1)
            call self%os_ptcl2D%new_clean(nptcls)
            call self%os_ptcl3D%new_clean(nptcls)
            fromp = 1
            top   = n_os
        else
            ! stk
            if( .not.self%os_stk%isthere(n_os_stk-1,'top') )then
                stop 'FROMP/TOP keys should always be informed; simple_sp_project :: add_stk'
            endif
            call self%os_stk%reallocate(n_os_stk)
            ! 2d
            n_os_ptcl2D = self%os_ptcl2D%get_noris()
            call self%os_ptcl2D%reallocate(n_os_ptcl2D + nptcls)
            ! 3d
            n_os_ptcl3D = self%os_ptcl3D%get_noris()
            call self%os_ptcl3D%reallocate(n_os_ptcl3D + nptcls)
            fromp = nint(self%os_stk%get(n_os_stk-1,'top')) + 1
            top   = fromp + n_os - 1
        endif
        ! image format
        str    = fname2ext(stk_abspath)
        imgfmt = str(1:3)
        if( self%projinfo%isthere('imgfmt') )then
            call self%projinfo%getter(1, 'imgfmt', prev_imgfmt)
            if( imgfmt(1:3).ne.trim(prev_imgfmt) )stop 'Cannot mix 2 image formats in one project! simple_sp_project::add_stk'
        else
            call self%projinfo%set(1,'imgfmt', trim(imgfmt))
        endif
        ! updates oris_objects
        call self%os_stk%set(n_os_stk, 'stk',     trim(stk_abspath))
        call self%os_stk%set(n_os_stk, 'box',     real(ldim(1)))
        call self%os_stk%set(n_os_stk, 'nptcls',  real(nptcls))
        call self%os_stk%set(n_os_stk, 'fromp',   real(fromp))
        call self%os_stk%set(n_os_stk, 'top',     real(top))
        call self%os_stk%set(n_os_stk, 'stkkind', 'split')
        call self%os_stk%set(n_os_stk, 'imgkind', 'ptcl')
        call self%os_stk%set(n_os_stk, 'smpd',    ctfvars%smpd)
        call self%os_stk%set(n_os_stk, 'kv',      ctfvars%kv)
        call self%os_stk%set(n_os_stk, 'cs',      ctfvars%cs)
        call self%os_stk%set(n_os_stk, 'fraca',   ctfvars%fraca)
        if( ctfvars%l_phaseplate )then
            call self%os_stk%set(n_os_stk, 'phaseplate', 'yes')
        else
            call self%os_stk%set(n_os_stk, 'phaseplate', 'no')
        endif
        select case(ctfvars%ctfflag)
            case(CTFFLAG_NO)
                call self%os_stk%set(n_os_stk, 'ctf', 'no')
            case(CTFFLAG_YES)
                call self%os_stk%set(n_os_stk, 'ctf', 'yes')
            case(CTFFLAG_FLIP)
                call self%os_stk%set(n_os_stk, 'ctf', 'flip')
            case DEFAULT
                write(*,*) 'ctfvars%ctfflag: ', ctfvars%ctfflag
                stop 'ERROR, unsupported ctfflag; sp_project :: add_stk'
        end select
        if( self%os_mic%get_noris() == n_os_stk)then
            call self%os_stk%set(n_os_stk, 'micind',  real(n_os_stk))
        endif
        ! update particle oris objects
        do i = 1, nptcls
            o = os%get_ori(i)
            call o%kill_chash()
            call o%delete_entry('kv')
            call o%delete_entry('cs')
            call o%delete_entry('fraca')
            call o%delete_entry('smpd')
            if( ctfvars%ctfflag > 0 )then
                if( .not.o%isthere('dfx') )then
                    stop 'ERROR! ctf .ne. no and input lacks dfx; sp_project :: add_stk'
                endif
            endif
            call o%set('stkind', real(n_os_stk))
            if( .not.o%isthere('state') ) call o%set('state',1.)
            call self%os_ptcl2D%set_ori(n_os_ptcl2D+i, o)
            call self%os_ptcl3D%set_ori(n_os_ptcl3D+i, o)
        enddo
    end subroutine add_stk

    subroutine add_single_stk( self, stk, ctfvars, os )
        class(sp_project),     intent(inout) :: self
        character(len=*),      intent(in)    :: stk
        type(ctfparams),       intent(in)    :: ctfvars ! CTF parameters associated with stk
        class(oris), optional, intent(inout) :: os   ! parameters associated with stk
        integer :: n_os_stk, n_os_ptcl2D, n_os_ptcl3D
        ! check that stk field is empty
        n_os_stk = self%os_stk%get_noris()
        if( n_os_stk > 0 )then
            write(*,*) 'stack field (self%os_stk) already populated with # entries: ', n_os_stk
            stop 'ABORTING! sp_project :: add_single_stk'
        endif
        ! check that particle fields are empty
        n_os_ptcl2D = self%os_ptcl2D%get_noris()
        if( n_os_ptcl2D > 0 )then
            write(*,*) 'ptcl2D field (self%os_ptcl2D) already populated with # entries: ', n_os_ptcl2D
            stop 'ABORTING! empty particle fields in project file assumed; sp_project :: add_single_stk'
        endif
        n_os_ptcl3D = self%os_ptcl3D%get_noris()
        if( n_os_ptcl3D > 0 )then
            write(*,*) 'ptcl3D field (self%os_ptcl3D) already populated with # entries: ', n_os_ptcl3D
            stop 'ABORTING! empty particle fields in project file assumed; sp_project :: add_single_stk'
        endif
        if( ctfvars%ctfflag > 0 )then
            if( .not.os%isthere(1,'dfx') )then
                stop 'ERROR! ctf .ne. no and input lacks dfx; sp_project :: add_single_stk'
            endif
        endif
        ! add stack
        call self%add_stk(stk, ctfvars, os)
        ! indicate single
        call self%os_stk%set(1, 'stkkind', 'single')
    end subroutine add_single_stk

    subroutine add_stktab( self, stktab, os )
        class(sp_project),   intent(inout) :: self
        character(len=*),    intent(in)    :: stktab
        class(oris),         intent(inout) :: os ! parameters associated with stktab
        type(ctfparams)                    :: ctfvars
        type(ori)                          :: o_stk
        type(oris)                         :: os_ptcls
        character(len=:), allocatable      :: phplate, ctfstr
        character(len=STDLEN), allocatable :: stknames(:)
        integer :: istk, ldim(3), ldim_here(3), nptcls, n_os, iptcl, nstks
        ! file exists?
        if( .not. file_exists(stktab) )then
            write(*,*) 'Inputted stack list (stktab): ', trim(stktab)
            stop 'does not exist in cwd; sp_project :: add_stktab'
        endif
        ! read micrograph stack names
        call read_filetable(stktab, stknames)
        nstks = size(stknames)
        ! check that inputs are of conforming sizes
        n_os = os%get_noris()
        if( n_os /= nstks )then
            write(*,*) '# input oris      : ', n_os
            write(*,*) '# stacks in stktab: ', nstks
            stop 'ERROR! nonconforming sizes of inputs; sp_project :: add_stktab'
        endif
        do istk=1,nstks
            if( .not.file_exists(stknames(istk)) )then
                write(*,*) 'Inputted stack: ', trim(stknames(istk))
                stop 'does not exist in cwd; sp_project :: add_stktab'
            endif
            o_stk = os%get_ori(istk)
            ! logical dimension management
            call find_ldim_nptcls(trim(stknames(istk)), ldim, nptcls)
            ldim(3) = 1
            if( istk == 1 )then
                ldim_here = ldim
            else
                if( .not. all(ldim_here == ldim) )then
                    write(*,*) 'micrograph stack #  : ', istk
                    write(*,*) 'stk name            : ', trim(stknames(istk))
                    write(*,*) 'ldim in object      : ', ldim_here
                    write(*,*) 'ldim read from stack: ', ldim
                    stop 'inconsistent logical dimensions; sp_project :: add_stktab'
                endif
            endif
            if( ldim(1) /= ldim(2) )then
                write(*,*) 'stk name: ', trim(stknames(istk))
                write(*,*) 'xdim:     ', ldim(1)
                write(*,*) 'ydim:     ', ldim(2)
                stop 'ERROR! nonsquare particle images not supported; sp_project :: add_stktab'
            endif
            ! prepare CTF vars
            call o_stk%getter('ctf', ctfstr)
            ctfvars%ctfflag = 1
            select case( trim(ctfstr) )
                case('no')
                    ctfvars%ctfflag = 0
                case('yes')
                    ctfvars%ctfflag = 1
                case('flip')
                    ctfvars%ctfflag = 2
            end select
            ctfvars%kv    = o_stk%get('kv')
            ctfvars%cs    = o_stk%get('cs')
            ctfvars%fraca = o_stk%get('fraca')
            if( o_stk%isthere('phaseplate'))then
                call o_stk%getter('phaseplate', phplate)
                ctfvars%l_phaseplate = trim(phplate) .eq. 'yes'
            else
                ctfvars%l_phaseplate = .false.
            endif
            ! import
            call os_ptcls%new_clean(nptcls)
            do iptcl=1,nptcls
                call os_ptcls%set_ori(iptcl, o_stk)
            end do
            call self%add_stk(stknames(istk), ctfvars, os_ptcls)
        enddo
    end subroutine add_stktab

    subroutine split_stk( self, nparts )
        use simple_map_reduce, only: split_nobjs_even
        use simple_image,      only: image
        class(sp_project),     intent(inout) :: self
        integer,               intent(in)    :: nparts
        type(image)                   :: img
        type(ori)                     :: orig_stk
        character(len=:), allocatable :: stk, tmp_dir, ext, imgkind, stkpart, dest_stkpart, ctfstr
        character(len=STDLEN) :: cwd
        integer    :: parts(nparts,2), ind_in_stk, iptcl, cnt, istk, box, n_os_stk
        integer    :: nptcls, nptcls_part, numlen, status
        real       :: smpd, cs, kv, fraca
        ! check that stk field is not empty
        n_os_stk = self%os_stk%get_noris()
        if( n_os_stk==0 )then
            stop 'No stack to split! sp_project :: split_single_stk'
        else if( n_os_stk >= nparts )then
            return
        endif
        smpd    = self%os_stk%get(1,'smpd')
        box     = nint(self%os_stk%get(1,'box'))
        call self%os_stk%getter(1,'stk',stk)
        ext     = fname2ext(stk)
        deallocate(stk)
        call self%os_stk%getter(1,'imgkind', imgkind)
        nptcls  = self%get_nptcls()
        parts   = split_nobjs_even( nptcls, nparts )
        numlen  = len_trim(int2str(nparts))
        ! images copy
        call img%new([box,box,1], smpd)
        call simple_getcwd(cwd)
        tmp_dir = trim(cwd) // '/tmp_stacks/'
        call simple_mkdir(trim(tmp_dir))
        do istk = 1,nparts
            allocate(stkpart, source=tmp_dir//'stack_part'//int2str_pad(istk,numlen)//'.'//trim(ext))
            cnt = 0
            do iptcl = parts(istk,1), parts(istk,2)
                cnt = cnt + 1
                call self%get_stkname_and_ind( 'ptcl2D', iptcl, stk, ind_in_stk )
                call img%read(stk, ind_in_stk)
                call img%write(stkpart, cnt)
                deallocate(stk)
            enddo
            deallocate(stkpart)
        enddo
        call img%kill
        if( n_os_stk > 1 )then
            ! wipe previous stack parts
            do istk = 1,n_os_stk
                call self%os_stk%getter(istk,'stk', stkpart)
                call del_file(stkpart)
                deallocate(stkpart)
            enddo
        endif
        ! updates new stack parts
        orig_stk = self%os_stk%get_ori(1)
        call self%os_stk%getter(1, 'ctf', ctfstr)
        cs    = self%os_stk%get(1,'cs')
        kv    = self%os_stk%get(1,'kv')
        fraca = self%os_stk%get(1,'fraca')
        call self%os_stk%new_clean(nparts)
        call simple_mkdir(trim(STKPARTSDIR), status=status)
        do istk = 1,nparts
            allocate(stkpart, source=tmp_dir//'stack_part'//int2str_pad(istk,numlen)//'.'//trim(ext))
            allocate(dest_stkpart, source=trim(STKPARTFBODY)//int2str_pad(istk,numlen)//'.'//trim(ext))
            status = simple_rename(trim(stkpart), trim(dest_stkpart))
            deallocate(stkpart)
            call simple_full_path(dest_stkpart, stkpart, 'sp_project :: split_stk')
            nptcls_part = parts(istk,2)-parts(istk,1)+1
            call self%os_stk%set(istk, 'ctf',   ctfstr)
            call self%os_stk%set(istk, 'cs',    cs)
            call self%os_stk%set(istk, 'kv',    kv)
            call self%os_stk%set(istk, 'fraca', fraca)
            call self%os_stk%set(istk, 'stk',     trim(stkpart))
            call self%os_stk%set(istk, 'box',     real(box))
            call self%os_stk%set(istk, 'smpd',    smpd)
            call self%os_stk%set(istk, 'nptcls',  real(nptcls_part))
            call self%os_stk%set(istk, 'fromp',   real(parts(istk,1)))
            call self%os_stk%set(istk, 'top',     real(parts(istk,2)))
            call self%os_stk%set(istk, 'imgkind', trim(imgkind))
            call self%os_stk%set(istk, 'stkkind', 'split')
            do iptcl=parts(istk,1),parts(istk,2)
                call self%os_ptcl2D%set(iptcl,'stkind',real(istk))
                call self%os_ptcl3D%set(iptcl,'stkind',real(istk))
            enddo
            deallocate(stkpart, dest_stkpart)
        enddo
        call self%write
    end subroutine split_stk

    function get_stkname( self, imic ) result( stkname )
        class(sp_project), intent(inout) :: self
        integer,           intent(in)    :: imic
        character(len=:), allocatable    :: stkname
        integer :: nmics
        nmics = self%os_stk%get_noris()
        if( imic < 1 .or. imic > nmics )then
            print *, 'imic : ', imic
            print *, 'nmics: ', nmics
            stop 'imic index out of range; sp_project :: get_stkname'
        endif
        call self%os_stk%getter(imic, 'stk', stkname)
    end function get_stkname

    subroutine get_stkname_and_ind( self, oritype, iptcl, stkname, ind_in_stk )
        class(sp_project), target,     intent(inout) :: self
        character(len=*),              intent(in)    :: oritype
        integer,                       intent(in)    :: iptcl
        character(len=:), allocatable, intent(out)   :: stkname
        integer,                       intent(out)   :: ind_in_stk
        integer :: stkind
        ! do the index mapping
        call self%map_ptcl_ind2stk_ind(oritype, iptcl, stkind, ind_in_stk )
        ! output name
        if( allocated(stkname) ) deallocate(stkname)
        call self%os_stk%getter(stkind, 'stk', stkname)
    end subroutine get_stkname_and_ind

    subroutine add_scale_tag( self )
        class(sp_project), intent(inout) :: self
        character(len=:), allocatable :: ext, newname, stkname
        integer :: imic, nmics
        nmics = self%os_stk%get_noris()
        do imic=1,nmics
            call self%os_stk%getter(imic, 'stk', stkname)
            ext     = fname2ext(trim(stkname))
            newname = add2fbody(stkname, '.'//ext, trim(SCALE_SUFFIX))
            call self%os_stk%set(imic, 'stk', newname)
        end do
    end subroutine add_scale_tag

    ! os_out related methods

    subroutine add_cavgs2os_out( self, stk, smpd)
        class(sp_project),     intent(inout) :: self
        character(len=*),      intent(in)    :: stk
        real,                  intent(in)    :: smpd ! sampling distance of images in stk
        character(len=:), allocatable :: cavg_stk
        integer :: ldim(3), nptcls, n_os_out
        ! fuul path and existence check
        call simple_full_path(stk, cavg_stk, 'sp_project :: add_cavgs2os_out')
        ! find dimension of inputted stack
        call find_ldim_nptcls(cavg_stk, ldim, nptcls)
        if( ldim(1) /= ldim(2) )then
            write(*,*) 'xdim: ', ldim(1)
            write(*,*) 'ydim: ', ldim(2)
            stop 'ERROR! nonsquare particle images not supported; sp_project :: add_os_out'
        endif
        ! check if field is empty
        n_os_out = self%os_out%get_noris()
        if( n_os_out == 0 )then
            n_os_out = 1
            call self%os_out%new_clean(n_os_out)
        else
            n_os_out = n_os_out + 1
            call self%os_out%reallocate(n_os_out)
        endif
        ! fill-in field
        call self%os_out%set(n_os_out , 'stk',     trim(cavg_stk))
        call self%os_out%set(n_os_out , 'box',     real(ldim(1)))
        call self%os_out%set(n_os_out , 'nptcls',  real(nptcls))
        call self%os_out%set(n_os_out , 'fromp',   1.0)
        call self%os_out%set(n_os_out , 'top',     real(nptcls))
        call self%os_out%set(n_os_out , 'smpd',    real(smpd))
        call self%os_out%set(n_os_out , 'stkkind', 'single')
        call self%os_out%set(n_os_out , 'imgkind', 'cavg')
        call self%os_out%set(n_os_out , 'ctf',     'no')
    end subroutine add_cavgs2os_out

    ! getters

    integer function get_nptcls( self )
        class(sp_project), target, intent(inout) :: self
        integer :: i, nos
        get_nptcls = 0
        nos        = self%os_stk%get_noris()
        do i=1,nos
            get_nptcls = get_nptcls + nint(self%os_stk%get(i,'nptcls'))
        enddo
        ! sanity check
        if( self%os_stk%isthere(nos,'top') )then
            if( nint(self%os_stk%get(nos,'top')) /=  get_nptcls )then
                write(*,*) 'nptcls from ptcls', get_nptcls
                write(*,*) 'nptcls from top', nint(self%os_stk%get(nos,'top'))
                stop 'ERROR! total # particles .ne. last top index; sp_project :: get_nptcls'
            endif
        endif
    end function get_nptcls

    integer function get_box( self )
        class(sp_project), target, intent(inout) :: self
        integer :: n_os_stk
        get_box  = 0
        n_os_stk = self%os_stk%get_noris()
        if( n_os_stk == 0 )then
            stop 'ERROR! empty os_stk field! sp_project :: get_box'
        endif
        get_box = nint( self%os_stk%get(1,'box') )
    end function get_box

    real function get_smpd( self )
        class(sp_project), target, intent(inout) :: self
        integer :: n_os_stk
        get_smpd  = 0.
        n_os_stk = self%os_stk%get_noris()
        if( n_os_stk == 0 )then
            stop 'ERROR! empty os_stk field! sp_project :: get_smpd'
        endif
        get_smpd = self%os_stk%get(1,'smpd')
    end function get_smpd

    integer function get_nmics( self )
        class(sp_project), target, intent(inout) :: self
        character(len=:), allocatable :: imgkind
        integer :: i
        get_nmics = 0
        do i=1,self%os_mic%get_noris()
            call self%os_mic%getter(i,'imgkind',imgkind)
            if( trim(imgkind).eq.'mic' ) get_nmics = get_nmics + 1
        enddo
    end function get_nmics

    integer function get_nmovies( self )
        class(sp_project), target, intent(inout) :: self
        character(len=:), allocatable :: imgkind
        integer :: i
        get_nmovies = 0
        do i=1,self%os_mic%get_noris()
            call self%os_mic%getter(i,'imgkind',imgkind)
            if( trim(imgkind).eq.'movie' ) get_nmovies = get_nmovies + 1
        enddo
    end function get_nmovies

    character(len=STDLEN) function get_ctfmode( self, oritype )
        class(sp_project), target, intent(inout) :: self
        character(len=*),          intent(in)    :: oritype
        class(oris), pointer          :: ptcl_field
        logical :: dfx_here, dfy_here
        nullify(ptcl_field)
        ! set field pointer
        select case(trim(oritype))
            case('ptcl2D')
                ptcl_field => self%os_ptcl2D
            case('ptcl3D')
                ptcl_field => self%os_ptcl3D
            case('cls2D', 'cls3D')
                get_ctfmode = 'no'
                return
            case DEFAULT
                write(*,*) 'oritype: ', trim(oritype), ' is not supported by this method'
                stop 'sp_project :: get_ctfmode'
        end select
        ! defocus
        dfx_here = ptcl_field%isthere(1, 'dfx')
        dfy_here = ptcl_field%isthere(1, 'dfy')
        if( dfx_here .and. dfy_here )then
            get_ctfmode = 'astig'
        else if( dfx_here )then
            get_ctfmode = 'noastig'
        else
            get_ctfmode = 'no'
        endif
    end function get_ctfmode

    character(len=STDLEN) function get_ctfflag( self, oritype )
        class(sp_project), target, intent(inout) :: self
        character(len=*),          intent(in)    :: oritype
        class(oris), pointer          :: ptcl_field
        character(len=:), allocatable :: ctfflag
        integer              :: stkind, ind_in_stk
        nullify(ptcl_field)
        ! set field pointer
        select case(trim(oritype))
            case('ptcl2D')
                ptcl_field => self%os_ptcl2D
            case('ptcl3D')
                ptcl_field => self%os_ptcl3D
            case('cls2D', 'cls3D')
                get_ctfflag = 'no'
                return
            case DEFAULT
                write(*,*) 'oritype: ', trim(oritype), ' is not supported by this method'
                stop 'sp_project :: get_ctfflag'
        end select
        ! do the index mapping
        call self%map_ptcl_ind2stk_ind(oritype, 1, stkind, ind_in_stk)
        ! CTF flag
        if( self%os_stk%isthere(stkind, 'ctf') )then
            call self%os_stk%getter(stkind, 'ctf', ctfflag)
        else if( ptcl_field%isthere(1, 'ctf') )then
            call ptcl_field%getter(1, 'ctf', ctfflag)
        else
            ctfflag = 'no'
        endif
        get_ctfflag = trim(ctfflag)
    end function get_ctfflag

    integer function get_ctfflag_type( self, oritype )
        class(sp_project), target, intent(inout) :: self
        character(len=*),          intent(in)    :: oritype
        character(len=:), allocatable :: ctfflag
        ctfflag = self%get_ctfflag(oritype)
        select case(trim(ctfflag))
            case('no')
                get_ctfflag_type = CTFFLAG_NO
            case('yes')
                get_ctfflag_type = CTFFLAG_YES
            case('mul')
                stop 'ERROR ctf=mul deprecated; simple_sp_project :: get_ctfflag_type'
            case('flip')
                get_ctfflag_type = CTFFLAG_FLIP
            case DEFAULT
                print *, 'ctf flag:', trim(ctfflag)
                stop 'Unsupported ctf flag; simple_sp_project :: get_ctfflag_type'
        end select
    end function get_ctfflag_type

    logical function has_phaseplate( self, oritype )
        class(sp_project), target, intent(inout) :: self
        character(len=*),          intent(in)    :: oritype
        class(oris), pointer          :: ptcl_field
        character(len=:), allocatable :: phaseplate
        integer              :: stkind, ind_in_stk
        nullify(ptcl_field)
        select case(trim(oritype))
            case('ptcl2D', 'ptcl3D')
                ! all good
            case('cls3D')
                has_phaseplate = .false.
                return
            case DEFAULT
                write(*,*) 'oritype: ', trim(oritype), ' is not supported by this method'
                stop 'sp_project :: has_phaseplate'
        end select
        ! do the index mapping
        call self%map_ptcl_ind2stk_ind(oritype, 1, stkind, ind_in_stk)
        ! set field pointer
        select case(trim(oritype))
            case('ptcl2D')
                ptcl_field => self%os_ptcl2D
            case('ptcl3D')
                ptcl_field => self%os_ptcl3D
        end select
        ! get info
        if( self%os_stk%isthere(stkind, 'phaseplate') )then
            call self%os_stk%getter(stkind, 'phaseplate', phaseplate)
        else if( ptcl_field%isthere(1, 'phaseplate') )then
            call ptcl_field%getter(1, 'phaseplate', phaseplate)
        else
            phaseplate = 'no'
        endif
        has_phaseplate = trim(phaseplate).eq.'yes'
    end function has_phaseplate

    function get_ctfparams( self, oritype, iptcl ) result( ctfvars )
        class(sp_project), target, intent(inout) :: self
        character(len=*),          intent(in)    :: oritype
        integer,                   intent(in)    :: iptcl
        class(oris), pointer          :: ptcl_field
        character(len=:), allocatable :: ctfflag
        type(ctfparams)      :: ctfvars
        integer              :: stkind, ind_in_stk
        logical              :: dfy_was_there, l_noctf
        nullify(ptcl_field)
        ! set field pointer
        select case(trim(oritype))
            case('ptcl2D')
                ptcl_field => self%os_ptcl2D
            case('ptcl3D')
                ptcl_field => self%os_ptcl3D
            case DEFAULT
                write(*,*) 'oritype: ', trim(oritype), ' is not supported by this method'
                stop 'sp_project :: get_ctfparams'
        end select
        ! extract the CTF parameters
        ! do the index mapping
        call self%map_ptcl_ind2stk_ind(oritype, iptcl, stkind, ind_in_stk)
        ! CTF flag
        if( self%os_stk%isthere(stkind, 'ctf') )then
            call self%os_stk%getter(stkind, 'ctf', ctfflag)
        else if( ptcl_field%isthere(iptcl, 'ctf') )then
            call ptcl_field%getter(iptcl, 'ctf', ctfflag)
        else
            ctfflag = NULL
        endif
        if( trim(ctfflag).eq.NULL )then
            write(*,*) 'ERROR! ctf key lacking in os_stk_field & ptcl fields'
            stop 'sp_project :: get_ctfparams'
        else
            l_noctf = .false.
            select case(trim(ctfflag))
                case('no')
                    ctfvars%ctfflag = CTFFLAG_NO
                    l_noctf = .true.
                case('yes')
                    ctfvars%ctfflag = CTFFLAG_YES
                case('mul')
                    stop 'ERROR ctf=mul deprecated; simple_classaverager :: cavger_new'
                case('flip')
                    ctfvars%ctfflag = CTFFLAG_FLIP
            end select
        endif
        ! sampling distance
        if( self%os_stk%isthere(stkind, 'smpd') )then
            ctfvars%smpd = self%os_stk%get(stkind, 'smpd')
        else if( ptcl_field%isthere(iptcl, 'smpd') )then
            ctfvars%smpd = ptcl_field%get(iptcl, 'smpd')
        else
            write(*,*) 'ERROR! smpd (sampling distance) lacking in os_stk_field'
            stop 'sp_project :: get_ctfparams'
        endif
        ! acceleration voltage
        if( self%os_stk%isthere(stkind, 'kv') )then
            ctfvars%kv = self%os_stk%get(stkind, 'kv')
        else if( ptcl_field%isthere(iptcl, 'kv') )then
            ctfvars%kv = ptcl_field%get(iptcl, 'kv')
        else
            write(*,*) 'ERROR! kv (acceleration voltage) lacking in os_stk_field'
            stop 'sp_project :: get_ctfparams'
        endif
        ! spherical aberration constant
        if( self%os_stk%isthere(stkind, 'cs') )then
            ctfvars%cs = self%os_stk%get(stkind, 'cs')
        else if( ptcl_field%isthere(iptcl, 'cs') )then
            ctfvars%cs = ptcl_field%get(iptcl, 'cs')
        else
            write(*,*) 'ERROR! cs (spherical aberration constant) lacking in os_stk_field'
            stop 'sp_project :: get_ctfparams'
        endif
        ! fraction of amplitude contrast
        if( self%os_stk%isthere(stkind, 'fraca') )then
            ctfvars%fraca = self%os_stk%get(stkind, 'fraca')
        else if( ptcl_field%isthere(iptcl, 'fraca') )then
            ctfvars%fraca = ptcl_field%get(iptcl, 'fraca')
        else
            write(*,*) 'ERROR! fraca (fraction of amplitude contrast) lacking in os_stk_field'
            stop 'sp_project :: get_ctfparams'
        endif
        if( l_noctf )then
            ctfvars%dfx     = 0.
            ctfvars%dfy     = 0.
            ctfvars%angast  = 0.
            ctfvars%phshift = 0.
            return
        endif
        ! defocus in x
        if( ptcl_field%isthere(iptcl, 'dfx') )then
            ctfvars%dfx = ptcl_field%get(iptcl, 'dfx')
        else
            write(*,*) 'ERROR! dfx (defocus in x) lacking in os_stk_field'
            stop 'sp_project :: get_ctfparams'
        endif
        ! defocus in y
        dfy_was_there = .false.
        if( ptcl_field%isthere(iptcl, 'dfy') )then
            ctfvars%dfy = ptcl_field%get(iptcl, 'dfy')
            dfy_was_there = .true.
        else
            ctfvars%dfy = ctfvars%dfx
        endif
        ! angle of astigmatism
        if( ptcl_field%isthere(iptcl, 'angast') )then
            ctfvars%angast = ptcl_field%get(iptcl, 'angast')
        else
            if( dfy_was_there )then
                write(*,*) 'ERROR! astigmatic CTF model requires angast (angle of astigmatism) lacking in os_stk field'
                stop 'sp_project :: get_ctfparams'
            else
                ctfvars%angast = 0.
            endif
        endif
        ! additional phase shift
        if( self%os_stk%isthere(stkind, 'phshift') )then
            ctfvars%phshift = self%os_stk%get(stkind, 'phshift')
        else if( ptcl_field%isthere(iptcl, 'phshift') )then
            ctfvars%phshift = ptcl_field%get(iptcl, 'phshift')
        else
            ctfvars%phshift = 0.
        endif
    end function get_ctfparams

    logical function is_virgin_field( self, oritype )
        class(sp_project), target, intent(inout) :: self
        character(len=*),          intent(in)    :: oritype
        class(oris), pointer :: os
        nullify(os)
        is_virgin_field = .false.
        ! set field pointer
        select case(trim(oritype))
            case('ptcl2D')
                os => self%os_ptcl2D
            case('ptcl3D')
                os => self%os_ptcl3D
            case('cls3D')
                os => self%os_cls3D
            case DEFAULT
                write(*,*) 'oritype: ', trim(oritype), ' is not supported by this method'
                stop 'sp_project :: is_virgin_field'
        end select
        if( any( abs(os%get_all('e3')  )>TINY) )return
        if( any( abs(os%get_all('e1')  )>TINY) )return
        if( any( abs(os%get_all('e2')  )>TINY) )return
        if( any( abs(os%get_all('corr'))>TINY) )return
        if( any( abs(os%get_all('x')   )>TINY) )return
        if( any( abs(os%get_all('y')   )>TINY) )return
        is_virgin_field = .true.
    end function is_virgin_field

    ! modifiers

    subroutine set_sp_oris( self, which, os )
        class(sp_project), intent(inout) :: self
        character(len=*),  intent(in)    :: which
        class(oris),       intent(inout) :: os
        select case(trim(which))
            case('mic')
                self%os_mic    = os
            case('stk')
                self%os_stk    = os
            case('ptcl2D')
                self%os_ptcl2D = os
            case('cls2D')
                self%os_cls2D  = os
            case('cls3D')
                self%os_cls3D  = os
            case('ptcl3D')
                self%os_ptcl3D = os
            case('out')
                self%os_out    = os
            case('projinfo')
                self%projinfo  = os
            case('jobproc')
                self%jobproc   = os
            case('compenv')
                self%compenv   = os
            case DEFAULT
                stop 'unsupported which flag; sp_project :: set_sp_oris'
        end select
    end subroutine set_sp_oris

    subroutine scale_projfile( self, smpd_target, new_projfile, cline, cline_scale )
        ! this probably needs an oritype input for dealing with scale class averages
        use simple_cmdline, only: cmdline
        class(sp_project),             intent(inout) :: self
        real,                          intent(inout) :: smpd_target
        character(len=:), allocatable, intent(out)   :: new_projfile
        class(cmdline),                intent(inout) :: cline
        class(cmdline),                intent(out)   :: cline_scale
        character(len=:), allocatable :: projfile, projname, new_projname
        real    :: scale_factor, smpd_sc, msk_sc, smpd, msk
        integer :: box, box_sc, istk, n_os_stk
        n_os_stk = self%os_stk%get_noris()
        if( n_os_stk == 0 )then
            stop 'Empty stack object! simple_sp_project :: scale_projfile'
        endif
        call self%projinfo%getter(1, 'projfile', projfile)
        call self%projinfo%getter(1, 'projname', projname)
        ! dimensions
        smpd = self%get_smpd()
        box  = self%get_box()
        call autoscale(box, smpd, smpd_target, box_sc, smpd_sc, scale_factor)
        call cline_scale%set('prg',      'scale_project')
        call cline_scale%set('scale',    scale_factor)
        call cline_scale%set('projfile', projfile)
        call cline_scale%set('smpd',     smpd_sc)
        if( box == box_sc )then
            ! no scaling
            new_projfile = trim(projfile)
            return
        endif
        ! parameter updates
        if( cline%defined('msk') )then
            msk = cline%get_rarg('msk')
            msk_sc = msk * scale_factor
            call cline%set('msk', msk_sc)
        endif
        do istk = 1,n_os_stk
            call self%os_stk%set(istk, 'smpd', real(smpd_sc))
            call self%os_stk%set(istk, 'box', real(box_sc))
        enddo
        call self%os_ptcl2D%mul_shifts(scale_factor)
        call self%os_ptcl3D%mul_shifts(scale_factor)
        ! name changes and list for scaling job
        new_projname = trim(projname)//SCALE_SUFFIX
        new_projfile = trim(new_projname)//'.simple'
        call cline%set('projname', trim(new_projname))
        call cline%delete('projfile')
        call self%update_projinfo( cline )
        call self%add_scale_tag
        ! save
        call self%write()
        ! command line for scaling
        call cline_scale%set('newbox',  real(box_sc))
        if( cline%defined('nthr') )   call cline_scale%set('nthr', cline%get_rarg('nthr'))
        if( cline%defined('nparts') ) call cline_scale%set('nparts', cline%get_rarg('nparts'))
    end subroutine scale_projfile

    !> for merging alignment documents from SIMPLE runs in distributed mode
    subroutine merge_algndocs( self, nptcls, ndocs, oritype, fbody, numlen_in )
        use simple_map_reduce, only: split_nobjs_even
        class(sp_project), intent(inout) :: self
        integer,           intent(in)    :: nptcls, ndocs
        character(len=*),  intent(in)    :: oritype, fbody
        integer, optional, intent(in)    :: numlen_in
        class(oris),          pointer :: os_ptr
        integer,          allocatable :: parts(:,:)
        character(len=:), allocatable :: fname
        type(binoris) :: bos_doc
        type(oris)    :: os_part
        integer       :: i, iptcl, cnt, numlen, n_records, partsz, isegment
        numlen = len(int2str(ndocs))
        if( present(numlen_in) ) numlen = numlen_in
        parts  = split_nobjs_even(nptcls, ndocs)
        ! convert from flag to enumerator to integer
        isegment = which_flag2segment(oritype)
        ! allocate merged oris
        call self%new_seg_with_ptr( nptcls, oritype, os_ptr )
        ! read & transfer
        do i=1,ndocs
            ! read part
            fname     = trim(adjustl(fbody))//int2str_pad(i,numlen)//'.simple'
            call bos_doc%open(trim(fname))
            n_records = bos_doc%get_n_records(isegment)
            partsz    = parts(i,2) - parts(i,1) + 1
            if( n_records /= partsz )then
                write(*,*) 'ERROR, # records does not match expectation'
                write(*,*) 'EXTRACTED FROM file: ', trim(fname)
                write(*,*) 'n_records: ', n_records
                write(*,*) 'CALCULATED FROM input p%nptcls/p%ndocs'
                write(*,*) 'fromto: ', parts(i,1), parts(i,2)
                write(*,*) 'partsz: ', partsz
                stop
            endif
            call os_part%new_clean(n_records)
            call bos_doc%read_segment(isegment, os_part)
            call bos_doc%close()
            ! transfer to self
            cnt = 0
            do iptcl = parts(i,1), parts(i,2)
                cnt = cnt + 1
                call os_ptr%set_ori(iptcl, os_part%get_ori(cnt))
            enddo
        end do
        call self%write()
    end subroutine merge_algndocs

    ! this map2ptcls routine assumes that any selection of class averages is done
    ! exclusively by state=0 flagging without any physical deletion
    subroutine map2ptcls( self )
        class(sp_project), intent(inout) :: self
        type state_organiser
            integer, allocatable :: particles(:)
            type(ori)            :: ori3d
        end type state_organiser
        type(state_organiser), allocatable :: labeler(:)
        type(ori) :: ori2d, ori_comp, o
        integer   :: ncls, icls, iptcl, pind, ncls_cls3D
        real      :: corr, rproj, rstate
        if( self%is_virgin_field('cls3D') )then
            write(*,*) 'ERROR! os_cls3D is virgin field; nothing to map back'
            stop 'sp_project :: map2ptcls'
        endif
        if( self%is_virgin_field('ptcl2D') )then
            write(*,*) 'ERROR! os_ptcl2D is virgin field; nothing to map back to'
            stop 'sp_project :: map2ptcls'
        endif
        ncls       = self%os_ptcl2D%get_n('class')
        ncls_cls3D = self%os_cls3D%get_noris()
        if( ncls /= ncls_cls3D )then
            write(*,*) 'ncls from ptcl2D field:      ', ncls
            write(*,*) 'ncls as sizeof(cls3D field): ', ncls_cls3D
            stop 'ERROR! inconsistent ncls in ptcl2D/cls3D fields; sp_project :: map2ptcls'
        endif
        allocate(labeler(ncls))
        do icls=1,ncls
            call self%os_ptcl2D%get_pinds(icls, 'class', labeler(icls)%particles)
        end do
        do icls=1,ncls
            ! get 3d ori info
            o      = self%os_cls3D%get_ori(icls)
            rproj  = o%get('proj')
            rstate = o%get('state')
            corr   = o%get('corr')
            if( allocated(labeler(icls)%particles) )then
                do iptcl=1,size(labeler(icls)%particles)
                    ! get particle index
                    pind  = labeler(icls)%particles(iptcl)
                    ! get 2d ori
                    ori2d = self%os_ptcl2D%get_ori(pind)
                    ! transfer original parameters in self%os_ptcl2D
                    ori_comp = self%os_ptcl2D%get_ori(pind)
                    ! compose ori3d and ori2d
                    call o%compose3d2d(ori2d, ori_comp)
                    ! set parameters in self%os_ptcl2D
                    call self%os_ptcl2D%set_ori(pind, ori_comp)
                    call self%os_ptcl2D%set(pind, 'corr',  corr)
                    call self%os_ptcl2D%set(pind, 'proj',  rproj)
                    call self%os_ptcl2D%set(pind, 'state', rstate)
                end do
            endif
        end do
    end subroutine map2ptcls

    ! printers

    subroutine print_info( self )
        class(sp_project), intent(in) :: self
        integer :: n
        n = self%os_mic%get_noris()
        if( n > 0 ) write(*,'(a,1x,i10)') '# entries in micrographs          segment (1) :', n
        n = self%os_stk%get_noris()
        if( n > 0 ) write(*,'(a,1x,i10)') '# entries in per-micrograph stack segment (2) :', n
        n = self%os_ptcl2D%get_noris()
        if( n > 0 ) write(*,'(a,1x,i10)') '# entries in per-particle 2D      segment (3) :', n
        n = self%os_cls2D%get_noris()
        if( n > 0 ) write(*,'(a,1x,i10)') '# entries in per-cluster  2D      segment (4) :', n
        n = self%os_cls3D%get_noris()
        if( n > 0 ) write(*,'(a,1x,i10)') '# entries in per-cluster  3D      segment (5) :', n
        n = self%os_ptcl3D%get_noris()
        if( n > 0 ) write(*,'(a,1x,i10)') '# entries in per-particle 3D      segment (6) :', n
        n = self%os_out%get_noris()
        if( n > 0 ) write(*,'(a,1x,i10)') '# entries in out                  segment (7) :', n
        n = 0
        if( allocated(self%frcs) ) n = size(self%frcs,1)
        if( n > 0 ) write(*,'(a,1x,i10)') '# entries in FRCs                 segment (9) :', n
        n = 0
        if( allocated(self%fscs) ) n = size(self%fscs,1)
        if( n > 0 ) write(*,'(a,1x,i10)') '# entries in FSCs                 segment (10):', n
        n = self%projinfo%get_noris()
        if( n > 0 ) write(*,'(a,1x,i10)') '# entries in project info         segment (11):', n
        n = self%jobproc%get_noris()
        if( n > 0 ) write(*,'(a,1x,i10)') '# entries in jobproc              segment (12):', n
        n = self%compenv%get_noris()
        if( n > 0 ) write(*,'(a,1x,i10)') '# entries in compenv              segment (13):', n
    end subroutine print_info

    ! readers

    subroutine read( self, fname )
        class(sp_project),          intent(inout) :: self
        character(len=*), optional, intent(in)    :: fname
        character(len=:), allocatable :: projfile
        integer :: isegment
        if( present(fname) )then
            if( fname2format(fname) .ne. 'O' )then
                write(*,*) 'fname: ', trim(fname)
                stop 'file format not supported; sp_project :: read'
            endif
            projfile = trim(fname)
        else
            call self%projinfo%getter(1, 'projfile', projfile)
        endif
        if( .not. file_exists(trim(projfile)) )then
            write(*,*) 'fname: ', trim(projfile)
            stop 'inputted file does not exist; sp_project :: read'
        endif
        call self%bos%open(projfile)
        do isegment=1,self%bos%get_n_segments()
            call self%segreader(isegment)
        end do
        call self%bos%close
    end subroutine read

    subroutine read_ctfparams_state_eo( self, fname )
        class(sp_project), intent(inout) :: self
        character(len=*),  intent(in)    :: fname
        integer :: isegment
        if( .not. file_exists(trim(fname)) )then
            write(*,*) 'fname: ', trim(fname)
            stop 'inputted file does not exist; sp_project :: read'
        endif
        if( fname2format(fname) .ne. 'O' )then
            write(*,*) 'fname: ', trim(fname)
            stop 'file format not supported; sp_project :: read'
        endif
        call self%bos%open(fname)
        do isegment=1,self%bos%get_n_segments()
            call self%segreader(isegment, only_ctfparams_state_eo=.true.)
        end do
        call self%bos%close
    end subroutine read_ctfparams_state_eo

    subroutine read_segment( self, which, fname, fromto )
        class(sp_project), intent(inout) :: self
        character(len=*),  intent(in)    :: which
        character(len=*),  intent(in)    :: fname
        integer, optional, intent(in)    :: fromto(2)
        integer :: isegment
        if( .not. file_exists(trim(fname)) )then
            write(*,*) 'fname: ', trim(fname)
            stop 'inputted file does not exist; sp_project :: read_segment'
        endif
        select case(fname2format(fname))
            case('O')
                ! *.simple project file
                isegment = which_flag2segment(which)
                call self%bos%open(fname)
                call self%segreader(isegment)
                call self%bos%close
            case('T')
                ! *.txt plain text ori file
                select case(trim(which))
                    case('mic')
                        call self%os_mic%read(fname)
                    case('stk')
                        call self%os_stk%read(fname)
                    case('ptcl2D')
                        call self%os_ptcl2D%read(fname, fromto)
                    case('cls2D')
                        call self%os_cls2D%read(fname)
                    case('cls3D')
                        call self%os_cls3D%read(fname,  fromto)
                    case('ptcl3D')
                        call self%os_ptcl3D%read(fname, fromto)
                    case('out')
                        call self%os_out%read(fname)
                    case('projinfo')
                        call self%projinfo%read(fname)
                    case('jobproc')
                        call self%jobproc%read(fname)
                    case('compenv')
                        call self%compenv%read(fname)
                    case DEFAULT
                        stop 'unsupported which flag; sp_project :: read_segment'
                end select
            case DEFAULT
                write(*,*) 'fname: ', trim(fname)
                stop 'file format not supported; sp_project :: read_segment'
        end select
    end subroutine read_segment

    subroutine segreader( self, isegment, only_ctfparams_state_eo )
        class(sp_project), intent(inout) :: self
        integer,           intent(in)    :: isegment
        logical, optional, intent(in)    :: only_ctfparams_state_eo
        integer :: n
        n = self%bos%get_n_records(isegment)
        select case(isegment)
            case(MIC_SEG)
                call self%os_mic%new_clean(n)
                call self%bos%read_segment(isegment, self%os_mic)
            case(STK_SEG)
                call self%os_stk%new_clean(n)
                call self%bos%read_segment(isegment, self%os_stk,    only_ctfparams_state_eo=only_ctfparams_state_eo)
            case(PTCL2D_SEG)
                call self%os_ptcl2D%new_clean(n)
                call self%bos%read_segment(isegment, self%os_ptcl2D, only_ctfparams_state_eo=only_ctfparams_state_eo)
            case(CLS2D_SEG)
                call self%os_cls2D%new_clean(n)
                call self%bos%read_segment(isegment, self%os_cls2D)
            case(CLS3D_SEG)
                call self%os_cls3D%new_clean(n)
                call self%bos%read_segment(isegment, self%os_cls3D)
            case(PTCL3D_SEG)
                call self%os_ptcl3D%new_clean(n)
                call self%bos%read_segment(isegment, self%os_ptcl3D, only_ctfparams_state_eo=only_ctfparams_state_eo)
            case(OUT_SEG)
                call self%os_out%new_clean(n)
                call self%bos%read_segment(isegment, self%os_out)
            case(FRCS_SEG)
                call self%read_2Darray_segment(FRCS_SEG, self%frcs)
            case(FSCS_SEG)
                call self%read_2Darray_segment(FSCS_SEG, self%fscs)
            case(PROJINFO_SEG)
                call self%projinfo%new_clean(n)
                call self%bos%read_segment(isegment, self%projinfo)
            case(JOBPROC_SEG)
                call self%jobproc%new_clean(n)
                call self%bos%read_segment(isegment, self%jobproc)
            case(COMPENV_SEG)
                call self%compenv%new_clean(n)
                call self%bos%read_segment(isegment, self%compenv)
        end select
    end subroutine segreader

    subroutine read_2Darray_segment( self, isegment, array )
        class(sp_project), intent(inout) :: self
        integer,           intent(in)    :: isegment
        real, allocatable, intent(out)   :: array(:,:)
        real    :: rval
        integer :: ndim1, ndim2
        ndim1 = self%bos%get_n_records(isegment)
        ndim2 = int(self%bos%get_n_bytes_per_record(isegment) / sizeof(rval))
        if( allocated(array) ) deallocate(array)
        allocate( array(ndim1,ndim2), source=0. )
        call self%bos%read_segment(isegment, array)
    end subroutine read_2Darray_segment

    ! writers

    subroutine write( self, fname, fromto, isegment )
        class(sp_project), intent(inout) :: self
        character(len=*), optional, intent(in) :: fname
        integer,          optional, intent(in) :: fromto(2)
        integer,          optional, intent(in) :: isegment
        character(len=:), allocatable :: projfile
        integer :: iseg
        if( present(fname) )then
            if( fname2format(fname) .ne. 'O' )then
                write(*,*) 'fname: ', trim(fname)
                stop 'file format not supported; sp_project :: write'
            endif
            projfile = trim(fname)
        else
            call self%projinfo%getter(1, 'projfile', projfile)
        endif
        call self%bos%open(projfile, del_if_exists=.true.)
        if( present(isegment) )then
            call self%segwriter(isegment, fromto)
        else
            do iseg=1,MAXN_OS_SEG
                call self%segwriter(iseg, fromto)
            end do
        endif
        ! update header
        call self%bos%write_header
        call self%bos%close
    end subroutine write

    subroutine write_segment( self, which, fname, fromto )
        class(sp_project), intent(inout) :: self
        character(len=*),  intent(in)    :: which
        character(len=*),  intent(in)    :: fname
        integer, optional, intent(in)    :: fromto(2)
        select case(fname2format(fname))
            case('O')
                stop 'write_segment is not supported for *.simple project files; sp_project :: write_segment'
            case('T')
                ! *.txt plain text ori file
                select case(trim(which))
                    case('mic')
                        if( self%os_mic%get_noris() > 0 )then
                            call self%os_mic%write(fname)
                        else
                            write(*,*) 'WARNING, no mic-type oris available to write; sp_project :: write_segment'
                        endif
                    case('stk')
                        if( self%os_stk%get_noris() > 0 )then
                            call self%os_stk%write(fname)
                        else
                            write(*,*) 'WARNING, no stk-type oris available to write; sp_project :: write_segment'
                        endif
                    case('ptcl2D')
                        if( self%os_ptcl2D%get_noris() > 0 )then
                            call self%os_ptcl2D%write(fname, fromto)
                        else
                            write(*,*) 'WARNING, no ptcl2D-type oris available to write; sp_project :: write_segment'
                        endif
                    case('cls2D')
                        if( self%os_cls2D%get_noris() > 0 )then
                            call self%os_cls2D%write(fname)
                        else
                            write(*,*) 'WARNING, no cls2D-type oris available to write; sp_project :: write_segment'
                        endif
                    case('cls3D')
                        if( self%os_cls3D%get_noris() > 0 )then
                            call self%os_cls3D%write(fname,  fromto)
                        else
                            write(*,*) 'WARNING, no cls3D-type oris available to write; sp_project :: write_segment'
                        endif
                    case('ptcl3D')
                        if( self%os_ptcl3D%get_noris() > 0 )then
                            call self%os_ptcl3D%write(fname, fromto)
                        else
                            write(*,*) 'WARNING, no ptcl3D-type oris available to write; sp_project :: write_segment'
                        endif
                    case('out')
                        if( self%os_out%get_noris() > 0 )then
                            call self%os_out%write(fname)
                        else
                            write(*,*) 'WARNING, no out-type oris available to write; sp_project :: write_segment'
                        endif
                    case('projinfo')
                        if( self%projinfo%get_noris() > 0 )then
                            call self%projinfo%write(fname, fromto)
                        else
                            write(*,*) 'WARNING, no projinfo-type oris available to write; sp_project :: write_segment'
                        endif
                    case('jobproc')
                        if( self%jobproc%get_noris() > 0 )then
                            call self%jobproc%write(fname)
                        else
                            write(*,*) 'WARNING, no jobproc-type oris available to write; sp_project :: write_segment'
                        endif
                    case('compenv')
                        if( self%compenv%get_noris() > 0 )then
                            call self%compenv%write(fname)
                        else
                            write(*,*) 'WARNING, no compenv-type oris available to write; sp_project :: write_segment'
                        endif
                    case DEFAULT
                        stop 'unsupported which flag; sp_project :: write_segment'
                end select
            case DEFAULT
                write(*,*) 'fname: ', trim(fname)
                stop 'file format not supported; sp_project :: write_segment'
        end select
    end subroutine write_segment

    subroutine segwriter( self, isegment, fromto )
        class(sp_project), intent(inout) :: self
        integer,           intent(in)    :: isegment
        integer, optional, intent(in)    :: fromto(2)
        select case(isegment)
            case(MIC_SEG)
                call self%bos%write_segment(isegment, self%os_mic, fromto)
            case(STK_SEG)
                call self%bos%write_segment(isegment, self%os_stk)
            case(PTCL2D_SEG)
                call self%bos%write_segment(isegment, self%os_ptcl2D, fromto)
            case(CLS2D_SEG)
                call self%bos%write_segment(isegment, self%os_cls2D)
            case(CLS3D_SEG)
                call self%bos%write_segment(isegment, self%os_cls3D, fromto)
            case(PTCL3D_SEG)
                call self%bos%write_segment(isegment, self%os_ptcl3D, fromto)
            case(OUT_SEG)
                call self%bos%write_segment(isegment, self%os_out)
            case(FRCS_SEG)
                call self%bos%write_segment(FRCS_SEG, self%frcs)
            case(FSCS_SEG)
                call self%bos%write_segment(FSCS_SEG, self%fscs)
            case(PROJINFO_SEG)
                call self%bos%write_segment(isegment, self%projinfo)
            case(JOBPROC_SEG)
                call self%bos%write_segment(isegment, self%jobproc)
            case(COMPENV_SEG)
                call self%bos%write_segment(isegment, self%compenv)
        end select
    end subroutine segwriter

    ! destructor

    subroutine kill( self )
        class(sp_project), intent(inout) :: self
        call self%os_stk%kill
        call self%os_ptcl2D%kill
        call self%os_cls2D%kill
        call self%os_cls3D%kill
        call self%os_ptcl3D%kill
        call self%os_out%kill
        call self%projinfo%kill
        call self%jobproc%kill
        call self%compenv%kill
    end subroutine kill

    ! private supporting subroutines / functions

    integer function which_flag2segment( which )
        character(len=*),  intent(in) :: which
        integer :: isegment
        select case(trim(which))
            case('mic')
                which_flag2segment = MIC_SEG
            case('stk')
                which_flag2segment = STK_SEG
            case('ptcl2D')
                which_flag2segment = PTCL2D_SEG
            case('cls2D')
                which_flag2segment = CLS2D_SEG
            case('cls3D')
                which_flag2segment = CLS3D_SEG
            case('ptcl3D')
                which_flag2segment = PTCL3D_SEG
            case('out')
                which_flag2segment = OUT_SEG
            case('frcs')
                which_flag2segment = FRCS_SEG
            case('fscs')
                which_flag2segment = FSCS_SEG
            case('projinfo')
                which_flag2segment = PROJINFO_SEG
            case('jobproc')
                which_flag2segment = JOBPROC_SEG
            case('compenv')
                which_flag2segment = COMPENV_SEG
            case DEFAULT
                stop 'unsupported which flag; sp_project :: which_flag2isgement'
        end select
    end function which_flag2segment

end module simple_sp_project

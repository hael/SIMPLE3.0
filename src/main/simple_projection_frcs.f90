module simple_projection_frcs
use simple_filterer, only: resample_filter
use simple_oris,     only: oris
use simple_syslib,   only: alloc_errchk
implicit none

type projection_frcs
    private
    integer           :: nprojs     = 0
    integer           :: filtsz     = 0 
    integer           :: box_target = 0
    integer           :: nstates    = 1
    real              :: smpd       = 0.0
    real, allocatable :: res_target(:)
    real, allocatable :: frcs(:,:,:)
    logical           :: l_frcs_set = .false.
    logical           :: exists     = .false.
contains
    ! constructor
    procedure          :: new
    ! exception
    procedure, private :: raise_exception
    ! setters/getters
    procedure          :: is_set
    procedure          :: set_frc
    procedure          :: get_frc
    procedure, private :: estimate_res_1
    procedure, private :: estimate_res_2
    generic            :: estimate_res => estimate_res_1, estimate_res_2
    ! I/O
    procedure          :: read
    procedure          :: write
    ! destructor
    procedure          :: kill
end type projection_frcs

contains

    ! constructor

    subroutine new( self, nprojs, box_target, smpd, nstates )
        use simple_math, only: fdim, get_resarr
        class(projection_frcs), intent(inout) :: self
        integer,                intent(in)    :: nprojs
        integer,                intent(in)    :: box_target
        real,                   intent(in)    :: smpd
        integer, optional,      intent(in)    :: nstates
        integer :: alloc_stat
        call self%kill
        self%nprojs     = nprojs
        self%box_target = box_target
        self%smpd       = smpd
        self%filtsz     = fdim(box_target)-1
        self%res_target = get_resarr(self%box_target, self%smpd)
        self%nstates    = 1
        if( present(nstates) ) self%nstates = nstates
        allocate( self%frcs(self%nstates,self%nprojs,self%filtsz), stat=alloc_stat)
        call alloc_errchk('new; simple_projection_frcs', alloc_stat)
        self%frcs   = 1.0
        self%exists = .true.
    end subroutine new

    ! exception

    subroutine raise_exception( self, proj, state, msg )
        class(projection_frcs), intent(in) :: self
        integer,                intent(in) :: proj, state
        character(len=*),       intent(in) :: msg
        logical :: l_outside
        l_outside = .false.
        if( proj  < 1 .or. proj  > self%nprojs  )then
            write(*,*) 'proj: ', proj
            l_outside = .true.
        endif
        if( state < 1 .or. state > self%nstates ) then
            write(*,*) 'state: ', state
            l_outside = .true.
        endif
        if( l_outside )then
            write(*,'(a)') msg
            stop 'simple_projection_frcs :: raise_exception'
        endif
    end subroutine raise_exception

    ! setters/getters

    logical function is_set( self )
        class(projection_frcs), intent(in) :: self
        is_set = self%l_frcs_set
    end function is_set

    subroutine set_frc( self, box, proj, frc, state )
        use simple_math, only: get_resarr
        class(projection_frcs), intent(inout) :: self
        integer,                intent(in)    :: box, proj
        real,                   intent(in)    :: frc(:)
        integer, optional,      intent(in)    :: state
        real, allocatable :: res(:)
        integer :: sstate
        sstate = 1
        if( present(state) ) sstate = state
        call self%raise_exception( proj, sstate, 'ERROR, out of bounds in set_frc')
        if( box /= self%box_target )then
            res = get_resarr(box, self%smpd)
            self%frcs(sstate,proj,:) = resample_filter(frc, res, self%res_target) 
        else
            self%frcs(sstate,proj,:) = frc
        endif
        self%l_frcs_set = .true.
    end subroutine set_frc

    function get_frc( self, proj, state ) result( frc )
        class(projection_frcs), intent(in) :: self
        integer,                intent(in) :: proj
        integer, optional,      intent(in) :: state
        real, allocatable :: frc(:)
        integer :: sstate
        sstate = 1
        if( present(state) ) sstate = state
        call self%raise_exception( proj, sstate, 'ERROR, out of bounds in get_frc')
        allocate(frc(self%filtsz), source=self%frcs(sstate,proj,:))
    end function get_frc

    subroutine estimate_res_1( self, proj, frc05, frc0143, state )
        use simple_math, only: get_resolution
        class(projection_frcs), intent(in)  :: self
        integer,                intent(in)  :: proj
        real,                   intent(out) :: frc05, frc0143
        integer, optional,      intent(in)  :: state
        integer :: sstate
        sstate = 1
        if( present(state) ) sstate = state
        call self%raise_exception( proj, sstate, 'ERROR, out of bounds in estimate_res')
        call get_resolution(self%frcs(sstate,proj,:), self%res_target, frc05, frc0143 )
    end subroutine estimate_res_1

    subroutine estimate_res_2( self, frc, res, frc05, frc0143, state )
        use simple_math, only: get_resolution
        class(projection_frcs), intent(in)  :: self
        real, allocatable,      intent(out) :: frc(:)
        real, allocatable,      intent(out) :: res(:)
        real,                   intent(out) :: frc05, frc0143
        integer, optional,      intent(in)  :: state
        integer :: alloc_stat, sstate
        if( allocated(frc) ) deallocate(frc)
        if( allocated(res) ) deallocate(res)
        allocate( frc(self%filtsz), res(self%filtsz), stat=alloc_stat )
        call alloc_errchk( 'estimate_res_2; simple_projection_frcs', alloc_stat )
        sstate = 1
        if( present(state) ) sstate = state
        frc = sum(self%frcs(sstate,:,:),dim=1)/real(self%nprojs)
        call get_resolution(frc, self%res_target, frc05, frc0143)
        res = self%res_target
    end subroutine estimate_res_2

    ! I/O

    subroutine read( self, fname )
        use simple_fileio, only: fopen, fclose, fileio_errmsg
        class(projection_frcs), intent(inout) :: self
        character(len=*),       intent(in)    :: fname
        integer          :: funit, io_stat
        character(len=7) :: stat_str
        if(.not.fopen(funit,fname,access='STREAM',action='READ',status='OLD', iostat=io_stat))&
        &call fileio_errmsg('projection_frcs; read; open for read '//trim(fname), io_stat)
        read(unit=funit,pos=1,iostat=io_stat) self%frcs
        call fileio_errmsg('projection_frcs; read; actual read', io_stat)
        if(.not.fclose(funit, iostat=io_stat))&
        &call fileio_errmsg('projection_frcs; read; fhandle cose', io_stat)
        self%l_frcs_set = .true.
    end subroutine read

    subroutine write( self, fname )
        use simple_fileio, only: fopen, fclose, fileio_errmsg
        class(projection_frcs), intent(in) :: self
        character(len=*),       intent(in) :: fname
        integer          :: funit, io_stat
        character(len=7) :: stat_str
        if(.not.fopen(funit,fname,access='STREAM',action='WRITE',status='REPLACE', iostat=io_stat))&
        &call fileio_errmsg('projection_frcs; write; open for write '//trim(fname), io_stat)
        write(unit=funit,pos=1,iostat=io_stat) self%frcs
        call fileio_errmsg('projection_frcs; write; actual write', io_stat)
        if(.not.fclose(funit, iostat=io_stat))&
        &call fileio_errmsg('projection_frcs; write; fhandle cose', io_stat)
    end subroutine write

    ! destructor

    subroutine kill( self )
        class(projection_frcs), intent(inout) :: self
        if( self%exists )then
            deallocate(self%res_target, self%frcs)
            self%nprojs     = 0 
            self%filtsz     = 0
            self%box_target = 0
            self%exists     = .false.
        endif
    end subroutine kill

end module simple_projection_frcs

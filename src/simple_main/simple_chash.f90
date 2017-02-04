module simple_chash
use simple_defs
implicit none

public :: chash
private

type :: chash
    private
    character(len=32),     allocatable :: keys(:)   !< chash keys
    character(len=STDLEN), allocatable :: values(:) !< chash values
    integer :: nmax        = 0                      !< maximum number of entries in chash
    integer :: chash_index = 0                      !< current highest index in hash
    logical :: exists      = .false.                !< to indicate existence
  contains
    ! CONSTRUCTORS
    procedure          :: new
    procedure, private :: copy
    procedure, private :: assign
    generic            :: assignment(=) => assign
    procedure          :: parse_cmdline
    procedure          :: gen_job_descr
    ! SETTERS 
    procedure          :: push
    procedure          :: set
    procedure          :: delete
    ! GETTERS
    procedure          :: isthere
    procedure          :: lookup
    procedure, private :: get_1
    procedure, private :: get_2
    generic            :: get => get_1, get_2
    procedure          :: get_key
    procedure          :: chash2str
    procedure          :: size_of_chash
    ! MODIFIERS
    procedure          :: sort
    ! PRINTERS
    procedure, private :: print_key_val_pair_1
    procedure, private :: print_key_val_pair_2
    generic            :: print_key_val_pair => print_key_val_pair_1, print_key_val_pair_2
    procedure          :: print_key_val_pairs
    ! I/O
    procedure          :: read
    procedure          :: write
    ! DESTRUCTOR
    procedure          :: kill
end type chash

interface chash
    module procedure constructor
end interface 

contains
    
    ! CONSTRUCTORS
    
    !>  \brief  is a constructor
    function constructor( nmax ) result( self )
        integer, intent(in) :: nmax !< max nr of entries in hash table
        type(chash)         :: self
        call self%new(nmax)
    end function constructor
    
    !>  \brief  is a constructor
    subroutine new( self, nmax )
        use simple_jiffys, only: alloc_err
        class(chash), intent(inout) :: self !< instance
        integer,      intent(in)    :: nmax !< max nr of entries in hash table
        integer :: alloc_stat
        call self%kill
        self%nmax = nmax
        allocate(self%keys(nmax), self%values(nmax), stat=alloc_stat)
        call alloc_err("In: simple_chash :: new", alloc_stat)
        self%exists = .true.
    end subroutine new
    
    !>  \brief  copies a chash instance
    subroutine copy( self_out, self_in )
        class(chash), intent(inout) :: self_out
        class(chash), intent(in)    :: self_in
        integer :: i        
        call self_out%new(self_in%nmax)
        if( self_in%chash_index > 0 )then
            do i=1,self_in%chash_index
                self_out%keys(i)   = self_in%keys(i)
                self_out%values(i) = self_in%values(i)
            end do
        endif
        self_out%chash_index = self_in%chash_index
    end subroutine copy
    
    !>  \brief  is a polymorphic assigner
    subroutine assign( self_out, self_in )
        class(chash), intent(inout) :: self_out
        class(chash), intent(in)    :: self_in 
        call self_out%copy(self_in)
    end subroutine assign

    !>  \brief  parse the ke-value pairs in the command line into chash
    subroutine parse_cmdline( self )
        class(chash), intent(inout) :: self
        character(len=STDLEN)       :: arg
        integer, parameter          :: NMAX=60
        integer :: cmdstat, cmdlen, i, argcnt, pos1
        argcnt  = command_argument_count()
        if( .not. self%exists ) call self%new(NMAX)
        do i=1,argcnt 
            call get_command_argument(i, arg, cmdlen, cmdstat)
            if( cmdstat == -1 )then
                write(*,*) 'ERROR! while parsing the command line; simple_chash :: parse_cmdline'
                write(*,*) 'The string length of argument: ', arg, 'is: ', cmdlen
                write(*,*) 'which likely exeeds the length limit STDLEN'
                write(*,*) 'Create a symbolic link with shorter name in the cwd'
                stop
            endif
            pos1 = index(arg, '=') ! position of '='
            ! parse everyting containing '='
            if( pos1 /= 0 ) call self%push(arg(:pos1-1), trim(arg(pos1+1:)))
        end do
    end subroutine parse_cmdline

    !>  \brief  for generating a job description for distributed execution
    subroutine gen_job_descr( self, prg )
         class(chash),    intent(inout) :: self
        character(len=*), intent(in)    :: prg
        call self%parse_cmdline
        call self%set('prg', prg)
    end subroutine gen_job_descr
    
    ! SETTERS
    
    !>  \brief  pushes values to the chash
    subroutine push( self, key, val )
        class(chash),     intent(inout) :: self
        character(len=*), intent(in)    :: key
        character(len=*), intent(in)    :: val
        self%chash_index = self%chash_index+1
        if( self%chash_index > self%nmax )then
            write(*,*) 'nmax: ', self%nmax
            write(*,*) 'chash_index: ', self%chash_index
            write(*,*) 'chash table full; push; simple_chash, nentries:', self%chash_index
            stop
        endif
        self%keys(self%chash_index)   = trim(adjustl(key))
        self%values(self%chash_index) = trim(adjustl(val))
    end subroutine push
    
    !>  \brief  sets a value in the chash 
    subroutine set( self, key, val )
        class(chash),     intent(inout) :: self
        character(len=*), intent(in)    :: key, val
        integer :: i
        if( self%chash_index >= 1 )then
            do i=1,self%chash_index
                if( trim(self%keys(i)) .eq. trim(key) )then
                    self%values(i) = trim(adjustl(val))
                    return
                endif
            end do
        endif
        call self%push(key, val)
    end subroutine set

    !>  \brief  sets a value in the chash 
    subroutine delete( self, key )
        class(chash),     intent(inout) :: self
        character(len=*), intent(in)    :: key
        integer :: i, ind
        ind = self%lookup( key )
        if( ind==0 .or. ind>self%chash_index )then
            write(*,*)'Nothing to delete; key:',key,'; simple_chash::delete'
            return
        endif
        do i=ind,self%chash_index-1
            self%keys(i)   = self%keys(i+1)
            self%values(i) = self%values(i+1)
        enddo
        self%keys(   self%chash_index ) = ''
        self%values( self%chash_index ) = ''
        self%chash_index = self%chash_index-1
    end subroutine delete

    ! GETTERS
    
    !>  \brief  check for presence of key in the chash
    function isthere( self, key ) result( found )
        class(chash),     intent(inout) :: self
        character(len=*), intent(in)    :: key
        integer :: i
        logical :: found
        found = .false.
        if( self%chash_index >= 1 )then
            do i=1,self%chash_index
                if( trim(self%keys(i)) .eq. trim(key) )then
                    found = .true.
                    return
                endif
            end do
        endif
    end function isthere
    
    !>  \brief  looks up the index of a key value in the chash
    function lookup( self, key ) result( which )
        class(chash),     intent(in) :: self
        character(len=*), intent(in) :: key
        integer :: ikey, which
        which = 0
        do ikey=1,self%chash_index
            if( trim(key) .eq. trim(self%keys(ikey)) )then
                which = ikey
                return
            endif
        end do
    end function lookup
    
    !>  \brief  gets a value in the chash
    function get_1( self, key ) result( val ) 
        class(chash),     intent(in)  :: self
        character(len=*), intent(in)  :: key
        character(len=:), allocatable :: val
        integer :: i
        do i=1,self%chash_index
            if( trim(self%keys(i)) .eq. trim(key) )then
                allocate(val, source=trim(self%values(i)))
                return
            endif
        end do
    end function get_1
    
    !>  \brief  gets a value in the chash
    function get_2( self, ival ) result( val ) 
        class(chash), intent(in)      :: self
        integer,      intent(in)      :: ival
        character(len=:), allocatable :: val
        allocate(val, source=trim(self%values(ival)))
    end function get_2
    
    !>  \brief  gets a key in the chash
    function get_key( self, ikey ) result( val ) 
        class(chash), intent(in)      :: self
        integer,      intent(in)      :: ikey
        character(len=:), allocatable :: val
        allocate(val, source=trim(self%keys(ikey)))
    end function get_key

    !>  \brief  concatenates the chash into a string
    function chash2str( self ) result( str )
        class(chash), intent(in)      :: self
        character(len=:), allocatable :: str, str_moving
        integer :: i
        if( self%chash_index == 1 )then
            allocate(str, source=trim(self%keys(1))//'='//trim(self%values(1)))
            return
        endif
        allocate(str_moving, source=trim(self%keys(1))//'='//trim(self%values(1))//' ') 
        if( self%chash_index > 2 )then
            do i=2,self%chash_index-1
                allocate(str, source=str_moving//trim(self%keys(i))//'='//trim(self%values(i))//' ')
                deallocate(str_moving)
                allocate(str_moving,source=str)
                deallocate(str)
            end do
        endif
        allocate(str,source=trim(str_moving//trim(self%keys(self%chash_index))//'='//trim(self%values(self%chash_index))))
    end function chash2str
    
    !>  \brief  returns size of chash
    function size_of_chash( self ) result( sz )
        class(chash), intent(in) :: self
        integer :: sz 
        sz = self%chash_index
    end function size_of_chash
    
    ! MODIFIERS

    !>  \brief  sort chash lexographically based on the keys
    subroutine sort( self )
        use simple_strings, only: lexSort
        class(chash), intent(inout)    :: self
        character(len=32), allocatable :: keys_sorted(:)
        character(len=:), allocatable  :: val
        character(len=32) :: key
        type(chash)       :: tmp
        integer           :: ikey
        if( self%chash_index > 1 )then
            call tmp%new(self%nmax)
            ! fill in keys
            allocate(keys_sorted(self%chash_index))
            keys_sorted = self%keys(:self%chash_index)
            ! sort keys
            call lexSort(keys_sorted)
            ! generate the sorted hash
            do ikey=1,self%chash_index
                val = self%get(keys_sorted(ikey))
                call tmp%push(keys_sorted(ikey), val)
                deallocate(val)
            end do
            self = tmp
            call tmp%kill
        endif
    end subroutine sort

    ! PRINTERS
    
    !>  \brief  pretty printing of a key-value pair
    subroutine print_key_val_pair_1( self, key, maxlen, fhandle, advance )
        class(chash), intent(in)      :: self
        character(len=*),  intent(in) :: key
        integer,           intent(in) :: maxlen
        integer, optional, intent(in) :: fhandle
        logical, optional, intent(in) :: advance
        character(len=maxlen) :: key_padded
        integer               :: which
        logical               :: aadvance
        aadvance = .true.
        if( present(advance) ) aadvance = .false.
        which = self%lookup(key)
        if( which > 0 )then
            if( present(advance) )then
                ! print one-liner (for command-line execution)
                if( present(fhandle) )then
                    if( aadvance )then
                        write(fhandle,'(a)') trim(key)//'='//trim(self%values(which))
                    else
                        write(fhandle,'(a)',advance='no') trim(key)//'='//trim(self%values(which))//' '
                    endif
                else
                    if( aadvance )then
                        write(*,'(a)') trim(key)//'='//trim(self%values(which))
                    else
                        write(*,'(a)',advance='no') trim(key)//'='//trim(self%values(which))//' '
                    endif
                endif
            else
                ! print table (for easy to read instructions)
                key_padded = trim(self%keys(which))
                do while(len(key_padded) < maxlen)
                    key_padded = key_padded//' '
                end do
                if( present(fhandle) )then
                    write(fhandle,'(a,1x,a)') key_padded, '= '//trim(self%values(which))
                else
                    write(*,'(a,1x,a)') key_padded, '= '//trim(self%values(which))
                endif
            endif
        else
            write(*,*) 'key: ', trim(key), ' does not exist in the chash'
            stop 'simple_chash :: print_key_val'
        endif 
    end subroutine print_key_val_pair_1
    
    !>  \brief  pretty printing of a key-value pair
    subroutine print_key_val_pair_2( self, ikey, maxlen, fhandle )
        class(chash), intent(in)      :: self
        integer,           intent(in) :: ikey
        integer,           intent(in) :: maxlen
        integer, optional, intent(in) :: fhandle
        character(len=maxlen) :: key_padded
        key_padded = trim(self%keys(ikey))
        do while(len(key_padded) < maxlen)
            key_padded = key_padded//' '
        end do
        if( present(fhandle) )then
            write(fhandle,'(a,1x,a)') key_padded, '= '//trim(self%values(ikey))
        else
            write(*,'(a,1x,a)') key_padded, '= '//trim(self%values(ikey))
        endif
    end subroutine print_key_val_pair_2
    
    !>  \brief  pretty printing of all key-value pairs
    subroutine print_key_val_pairs( self, keys2print, fhandle, oneline )
        class(chash),               intent(in) :: self
        character(len=*), optional, intent(in) :: keys2print(:)
        integer,          optional, intent(in) :: fhandle
        logical,          optional, intent(in) :: oneline
        logical :: ooneline=.false.
        integer :: maxlen=0, ikey=0, sz=0, keylen=0
        ooneline = .false.
        if( present(oneline) ) ooneline = oneline
        if( present(keys2print) )then
            sz = size(keys2print)
            if( ooneline )then
                ! non-advancing printing
                do ikey=1,sz
                    call self%print_key_val_pair_1(keys2print(ikey), maxlen, fhandle, advance=.false.)
                end do
            else
                ! find max key len in keys2print
                maxlen = 0
                do ikey=1,sz
                    keylen = len_trim(keys2print(ikey))
                    if( keylen > maxlen ) maxlen = keylen 
                end do
                ! print selected key-value pairs
                do ikey=1,sz
                    call self%print_key_val_pair_1(keys2print(ikey), maxlen, fhandle )
                end do
            endif
        else
            if( self%chash_index > 0 )then
                ! find max key len among all keys in chash
                maxlen = 0
                do ikey=1,self%chash_index
                    keylen = len_trim(self%keys(ikey))
                    if( keylen > maxlen ) maxlen = keylen 
                end do
                ! print all key-value pairs
                do ikey=1,self%chash_index
                    call self%print_key_val_pair_2(ikey, maxlen, fhandle )
                end do
            endif
        endif
    end subroutine print_key_val_pairs
    
    ! I/O
    
    !>  \brief  for reading key-vals from a text file
    subroutine read( self, fname )
        use simple_filehandling, only: get_fileunit
        use simple_strings,      only: strIsComment, strIsBlank
        class(chash), intent(inout)  :: self   !< instance
        character(len=*), intent(in) :: fname  !< name of file
        character(len=line_max_len)  :: buffer !< will hold a line from the file
        character(len=32)            :: key
        character(len=STDLEN)        :: val
        integer :: ios, pos, funit
        funit = get_fileunit()
        open(unit=funit, file=fname, iostat=ios, status='old')
        if( ios .ne. 0 )then
            close(funit)
            write(*,'(a)') 'simple_chash :: read; Error when opening file for reading: ', trim(fname)
            stop
        endif
        do
            read(funit, '(a)', iostat=ios) buffer
            if ( ios == 0 ) then
                if( strIsComment(buffer) .or. strIsBlank(buffer) )then
                    ! don't do anything
                else
                    pos = index(buffer, '=') ! position of '='
                    key = trim(adjustl(buffer(:pos-1)))
                    val = trim(adjustl(buffer(pos+1:)))
                    if( .not. strIsBlank(val) ) call self%set(key, val)
                endif
            else
                exit ! we found the end...
            endif
        enddo
        close(funit)
    end subroutine read
    
    !>  \brief  for writing key-vals to a text file
    subroutine write( self, fname )
        use simple_filehandling, only: get_fileunit
        class(chash), intent(inout)  :: self   !< instance
        character(len=*), intent(in) :: fname  !< name of file
        character(len=line_max_len)  :: buffer !< will hold a line from the file
        character(len=512)           :: io_msg !< will hold the io error message
        integer :: ios, pos, funit
        funit = get_fileunit()
        open(unit=funit, file=fname, iostat=ios, status='replace', iomsg=io_msg)
        if( ios .ne. 0 )then
            close(funit)
            write(*,'(a)') 'simple_chash :: read; Error when opening file for writing: '&
            //trim(fname)//' ; '//trim(io_msg)
            stop
        endif
        call self%print_key_val_pairs(fhandle=funit)
        close(funit)
    end subroutine write
        
    ! DESTRUCTOR
    
    !>  \brief  is a destructor
    subroutine kill( self )
         class(chash), intent(inout) :: self !< instance
         if( self%exists )then
             deallocate(self%keys, self%values)
             self%nmax        = 0
             self%chash_index = 0
             self%exists      = .false.
         endif
    end subroutine kill

end module simple_chash

! real hash data structure
module simple_hash
use simple_defs
use simple_strings, only: real2str, parsestr
implicit none

public :: hash!, test_hash
private

integer, parameter :: BUFFSZ_DEFAULT = 10

!> hash stuct
type :: hash
    private
    character(len=KEYLEN), allocatable :: keys(:)   !< hash keys
    real,                  allocatable :: values(:) !< hash values
    integer :: buffsz     = BUFFSZ_DEFAULT          !< size of first buffer and subsequent allocation increments
    integer :: hash_index = 0                       !< index
    logical :: exists     = .false.
  contains
    !< CONSTRUCTORS
    procedure, private :: new_1
    procedure, private :: new_2
    generic            :: new => new_1, new_2
    procedure, private :: alloc_hash
    procedure, private :: realloc_hash
    procedure, private :: copy
    procedure, private :: assign
    generic            :: assignment(=) => assign
    !< SETTERS
    procedure          :: push
    procedure          :: set
    procedure          :: delete
    !< GETTERS
    procedure          :: isthere
    procedure          :: lookup
    procedure          :: get
    procedure          :: get_keys
    procedure          :: get_values
    procedure          :: hash2str
    procedure          :: size_of
    ! I/O
    procedure          :: print
    ! procedure          :: read
    ! procedure          :: write
    !< DESTRUCTORS
    procedure          :: kill
    procedure, private :: dealloc_hash
end type hash

interface hash
    module procedure constructor_1
    module procedure constructor_2
end interface hash

contains

    ! CONSTRUCTORS

    !>  \brief  is a constructor
    function constructor_1( ) result( self )
        type(hash) :: self
        call self%new_1
    end function constructor_1

    !>  \brief  is a constructor
    function constructor_2( sz, buffsz ) result( self )
        integer,           intent(in)    :: sz     !< initial size
        integer, optional, intent(in)    :: buffsz !< size of subsequent allocation increments
        type(hash) :: self
        call self%new_2(sz, buffsz)
    end function constructor_2

    !>  \brief  is a constructor
    subroutine new_1( self )
        class(hash), intent(inout) :: self
        call self%kill
        self%buffsz = BUFFSZ_DEFAULT
        call self%alloc_hash(self%buffsz)
        self%exists = .true.
    end subroutine new_1

    !>  \brief  is a constructor
    subroutine new_2( self, sz, buffsz )
        class(hash),       intent(inout) :: self   !< instance
        integer,           intent(in)    :: sz     !< initial size
        integer, optional, intent(in)    :: buffsz !< size of subsequent allocation increments
        call self%kill
        if( present(buffsz) )then
            self%buffsz = buffsz
        else
            self%buffsz = BUFFSZ_DEFAULT
        endif
        call self%alloc_hash(sz)
        self%exists = .true.
    end subroutine new_2

    !>  \brief  allocates keys and values without touching buffsz and hash_index
    subroutine alloc_hash( self, sz )
        class(hash), intent(inout) :: self !< instance
        integer,      intent(in)   :: sz   !< total size
        call self%dealloc_hash
        allocate(self%keys(sz), self%values(sz))
    end subroutine alloc_hash

    !>  \brief  re-allocates keys and values without touching buffsz and hash_index and preserving previous key-value pairs
    subroutine realloc_hash( self )
        class(hash), intent(inout) :: self
        character(len=KEYLEN), allocatable :: keys_copy(:)
        real,                  allocatable :: values_copy(:)
        integer :: newsz, oldsz, i
        if( self%exists )then
            ! old/new size
            oldsz = size(self%keys)
            newsz = oldsz + self%buffsz
            ! copy key-value pairs
            allocate(keys_copy(oldsz), values_copy(oldsz))
            keys_copy   = self%keys
            values_copy = self%values
            ! allocate extended size
            call self%alloc_hash(newsz)
            ! set back the copied key-value pairs
            self%keys(:oldsz)   = keys_copy
            self%values(:oldsz) = values_copy
        else
            stop 'cannot reallocate non-existent hash; simple_hash :: realloc_hash'
        endif
    end subroutine realloc_hash

    !>  \brief  copies a hash instance
    subroutine copy( self_out, self_in )
        class(hash), intent(inout) :: self_out
        class(hash), intent(in)    :: self_in
        integer :: i, sz
        sz = size(self_in%keys)
        call self_out%alloc_hash(sz)
        self_out%buffsz     = self_in%buffsz
        self_out%hash_index = self_in%hash_index
        self_out%exists     = .true.
        if( self_in%hash_index > 0 )then
            do i=1,self_in%hash_index
                self_out%keys(i)   = self_in%keys(i)
                self_out%values(i) = self_in%values(i)
            end do
        endif
    end subroutine copy

    !>  \brief  is a polymorphic assigner
    subroutine assign( self_out, self_in )
        class(hash), intent(inout) :: self_out
        class(hash), intent(in)    :: self_in
        call self_out%copy(self_in)
    end subroutine assign

    ! SETTERS

    !>  \brief  pushes values to the hash
    subroutine push( self, key, val )
        class(hash),      intent(inout) :: self
        character(len=*), intent(in)    :: key
        real,             intent(in)    :: val
        integer :: sz
        self%hash_index = self%hash_index + 1
        sz              = size(self%keys)
        if( self%hash_index > sz ) call self%realloc_hash
        self%keys(self%hash_index)   = trim(key)
        self%values(self%hash_index) = val
    end subroutine push

    !>  \brief  sets a value in the hash
    subroutine set( self, key, val )
        class(hash),      intent(inout) :: self
        character(len=*), intent(in)    :: key
        real,             intent(in)    :: val
        integer :: i
        if( self%hash_index >= 1 )then
            do i=1,self%hash_index
                if( trim(self%keys(i)) .eq. trim(key) )then
                    self%values(i) = val
                    return
                endif
            end do
        endif
        call self%push(key, val)
    end subroutine set

    !>  \brief  deletes a value in the hash
    subroutine delete( self, key )
        class(hash),      intent(inout) :: self
        character(len=*), intent(in)    :: key
        integer :: i, ind
        ind = self%lookup( key )
        if( ind==0 .or. ind > self%hash_index ) return
        do i=ind,self%hash_index - 1
            self%keys(i)   = self%keys(i +1)
            self%values(i) = self%values(i + 1)
        enddo
        self%keys( self%hash_index ) = ''
        self%values( self%hash_index ) = 0.
        self%hash_index = self%hash_index - 1
    end subroutine delete

    ! GETTERS

    !>  \brief  check for presence of key in the hash
    function isthere( self, key ) result( found )
        class(hash),      intent(inout) :: self
        character(len=*), intent(in)    :: key
        integer :: i
        logical :: found
        found = .false.
        if( self%hash_index >= 1 )then
            do i=1,self%hash_index
                if( trim(self%keys(i)) .eq. trim(key) )then
                    found = .true.
                    return
                endif
            end do
        endif
    end function isthere

    !>  \brief  gets the index to a key
    integer function lookup( self, key )
        class(hash),      intent(inout) :: self
        character(len=*), intent(in)    :: key
        integer :: i
        do i=1,self%hash_index
            if( trim(self%keys(i)) .eq. trim(key) )then
                lookup = i
                return
            endif
        end do
    end function lookup

    !>  \brief  gets a value in the hash
    function get( self, key ) result( val )
        class(hash),      intent(inout) :: self
        character(len=*), intent(in)    :: key
        real    :: val
        integer :: i
        val = 0.
        do i=1,self%hash_index
            if( trim(self%keys(i)) .eq. trim(key) )then
                val = self%values(i)
                return
            endif
        end do
    end function get

    !>  \brief  returns the keys of the hash
    function get_keys( self ) result( keys )
        class(hash), intent(inout) :: self
        character(len=KEYLEN), allocatable :: keys(:)
        allocate(keys(self%hash_index), source=self%keys(:self%hash_index))
    end function get_keys

    !>  \brief  returns the values of the hash
    function get_values( self ) result( values )
        class(hash), intent(inout) :: self
        real, allocatable  :: values(:)
        allocate(values(self%hash_index), source=self%values(:self%hash_index))
    end function get_values

    !>  \brief  convert hash to string
    function hash2str( self ) result( str )
        class(hash), intent(inout)    :: self
        character(len=:), allocatable :: str, str_moving
        integer :: i
        if( self%hash_index > 0 )then
            if( self%hash_index == 1 )then
                allocate(str, source=trim(self%keys(1))//'='//trim(real2str(self%values(1))))
                return
            endif
            allocate(str_moving, source=trim(self%keys(1))//'='//trim(real2str(self%values(1)))//' ')
            if( self%hash_index > 2 )then
                do i=2,self%hash_index - 1
                    allocate(str, source=str_moving//trim(self%keys(i))//'='//trim(real2str(self%values(i)))//' ')
                    deallocate(str_moving)
                    allocate(str_moving,source=str,stat=alloc_stat)
                    deallocate(str)
                end do
            endif
            allocate(str,source=trim(str_moving//trim(self%keys(self%hash_index))&
                &//'='//trim(real2str(self%values(self%hash_index)))))
        endif
    end function hash2str

    !>  \brief  returns size of hash
    function size_of( self ) result( sz )
        class(hash), intent(in) :: self
        integer :: sz
        sz = self%hash_index
    end function size_of

    ! I/O

    !>  \brief  prints the hash
    subroutine print( self )
        class(hash), intent(inout) :: self
        integer :: i
        do i=1,self%hash_index-1
            write(*,"(1X,A,A)", advance="no") trim(self%keys(i)), '='
            write(*,"(A)", advance="no") trim(real2str(self%values(i)))
        end do
        write(*,"(1X,A,A)", advance="no") trim(self%keys(self%hash_index)), '='
        write(*,"(A)") trim(real2str(self%values(self%hash_index)))
    end subroutine print

    !>  \brief  reads a row of a text-file into the inputted hash, assuming key=value pairs
    ! subroutine read( self, fnr )
    !     use simple_math, only: is_a_number
    !     class(hash), intent(inout) :: self
    !     integer,     intent(in)    :: fnr
    !     character(len=1024)        :: line
    !     character(len=64)          :: keyvalpairs(NMAX)
    !     character(len=64)          :: keyvalpair
    !     character(len=KEYLEN)      :: key
    !     character(len=100)         :: io_message
    !     real    :: val
    !     integer :: j, pos1, nkeyvalpairs, io_stat
    !     read(fnr,fmt='(A)',advance='no',eor=100) line
    !     100 call parsestr(line, ' ', keyvalpairs, nkeyvalpairs)
    !     do j=1,nkeyvalpairs
    !         keyvalpair = keyvalpairs(j)
    !         pos1 = index(keyvalpair, '=') ! position of '='
    !         if( pos1 /= 0 )then
    !             key = keyvalpair(:pos1-1) ! key
    !             read(keyvalpair(pos1+1:),*,iostat=io_stat,iomsg=io_message) val
    !             ! Check the read was successful
    !             if( io_stat .ne. 0 )then
    !                 write(*,*) 'key = ', key
    !                 write(*,*) 'value = ', val
    !                 write(*,'(a,i0)') '**ERROR(simple_hash::read): I/O error ', io_stat
    !                 write(*,'(2a)') 'IO error message was: ', io_message
    !                 stop 'I/O error; read; simple_hash'
    !             endif
    !         endif
    !         if( .not. is_a_number(val) ) val = 0.
    !         call self%set(key, val)
    !     end do
    ! end subroutine read

    !>  \brief  writes the hash to file
    ! subroutine write( self, fnr )
    !     class(hash), intent(inout) :: self
    !     integer, intent(in)        :: fnr
    !     integer                    :: i
    !     do i=1,self%hash_index-1
    !         write(fnr,"(1X,A,A)", advance="no") trim(self%keys(i)), '='
    !         write(fnr,"(A)", advance="no") trim(real2str(self%values(i)))
    !     end do
    !     write(fnr,"(1X,A,A)", advance="no") trim(self%keys(self%hash_index)), '='
    !     write(fnr,"(A)") trim(real2str(self%values(self%hash_index)))
    ! end subroutine write

    ! DESTRUCTORS

    subroutine kill( self )
        class(hash), intent(inout) :: self
        if( self%exists )then
            call self%dealloc_hash
            self%buffsz     = 0
            self%hash_index = 0
            self%exists     = .false.
        endif
    end subroutine kill

    subroutine dealloc_hash( self )
        class(hash), intent(inout) :: self
        integer :: i
        if(allocated(self%keys))   deallocate(self%keys)
        if(allocated(self%values)) deallocate(self%values)
    end subroutine dealloc_hash

    ! UNIT TEST

    !>  \brief  is the hash unit test
    ! subroutine test_hash
    !     use simple_fileio      , only: fopen, fclose, fileio_errmsg
    !     type(hash) :: htab, htab2
    !     integer    :: fnr, file_stat
    !     write(*,'(a)') '**info(simple_hash_unit_test: testing all functionality'
    !     call htab%push('hans',  1.)
    !     call htab%push('donia', 2.)
    !     call htab%push('kenji', 3.)
    !     call htab%push('ralph', 4.)
    !     call htab%push('kyle',  5.)
    !     call htab%print
    !     call fopen(fnr, status='replace', action='write', file='hashtest.txt', iostat=file_stat)
    !     call fileio_errmsg("simple_hash_unit_test: test failed to open hastest.txt",file_stat)
    !     call htab%write(fnr)
    !     call fclose(fnr,errmsg="simple_hash_unit_test: test failed to close hastest.txt")
    !     call fopen(fnr, status='old', action='read', file='hashtest.txt', iostat=file_stat)
    !     call fileio_errmsg("simple_hash_unit_test: test failed to open 2nd  hastest.txt",file_stat)
    !     call htab2%read(fnr)
    !     call fclose(fnr,errmsg="simple_hash_unit_test: test failed to close 2nd hastest.txt")
    !     call htab2%print
    !     write(*,'(a)') 'SIMPLE_HASH_UNIT_TEST COMPLETED SUCCESSFULLY ;-)'
    ! end subroutine test_hash

end module simple_hash

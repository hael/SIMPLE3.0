program simple_test_install
use simple_defs              ! use all in there
use simple_testfuns          ! use all in there
use simple_rnd               ! use all in there
use simple_syscalls          ! use all in there
use simple_jiffys,           only: simple_end
use simple_image,            only: image
use simple_commander_volops, only: projvol_commander
use simple_strings,          only: real2str, int2str
implicit none
type( image )         :: cube, img
real                  :: smpd
integer               :: box, nspace, msk
character(8)          :: date
character(len=STDLEN) :: folder, cmd
character(len=300)    :: command
call seed_rnd
call date_and_time(date=date)
folder = './SIMPLE_TEST_INSTALL_'//date
command = 'mkdir ' // trim( folder )
call exec_cmdline( trim(command) )
call chdir( trim(folder) )
! dummy data
box    = 96
smpd   = 2.
nspace = 64
msk    = nint(real(box)/3.) 
! volume
call img%new( [box,box,box], smpd )
call img%square( nint(real(box)/12.) )
call cube%new( [box,box,box], smpd )
call cube%square( nint(real(box)/16.) )
call cube%shift( 16.,16.,16. )
call img%add( cube )
call cube%new( [box,box,box], smpd )
call cube%square( nint(real(box)/10.) )
call cube%shift( 4.,-16.,0. )
call img%add( cube )
call cube%kill
call img%write( 'cubes.mrc' )
call img%kill
write(*,*)'>>> WROTE TEST VOLUME cubes.mrc'
! test units
command = 'simple_test_units'
call exec_cmdline( trim(command) )
! test search
command = 'simple_test_srch vol1=cubes.mrc msk='//int2str(msk)//&
    & ' smpd='//real2str(smpd)//' verbose=no'
call exec_cmdline( trim(command) )
! end
call chdir('../')
call simple_end('**** SIMPLE_TEST_INSTALL NORMAL STOP ****')
end program simple_test_install

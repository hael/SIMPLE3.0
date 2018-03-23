!------------------------------------------------------------------------------!
! SIMPLE , Elmlund & Elmlund Lab,     simplecryoem.com                         !
!------------------------------------------------------------------------------!
!> test module for simple_timer_omp
!!
!! Test the OpenMP timing functions in the SIMPLE library.
!!
!! @author
!! Michael Eager 2017
!
! The code is distributed with the hope that it will be useful, but WITHOUT ANY
! WARRANTY. Redistribution and modification is regulated by the GNU General
! Public License.
! -----------------------------------------------------------------------------!
#if defined  _WIN32
#define DEV_NULL "nul"
#else
#define DEV_NULL "/dev/null"
#endif

#define NREP_MAX INT(100000,dp)

#include "simple_timer.h"

module simple_timer_omp_test
   use simple_defs
   use simple_timer_omp
   implicit none

   public:: exec_OpenMP_timer_test
   private
#include "simple_local_flags.inc"
contains

   subroutine exec_OpenMP_timer_test(be_verbose)
      logical, optional, intent(in)    :: be_verbose
      integer(dp), parameter :: nrep = NREP_MAX
      real(dp)    :: xx, c, cfac, b
      real(dp)    :: etime
      real(dp) ::  t1, t2
      integer(dp) :: i
      integer :: io_stat
      c = .1
      cfac = .25
      b = 1.
      xx = 12.0_dp
      if(present(be_verbose)) verbose = be_verbose
      VerbosePrint 'OpenMP Fortran Timer'
      VerbosePrint 'Note: in debug, OpenMP may not be present, timer defaults to cpu_time'
      VerbosePrint "1. Simple timestamp and diff "
      t1 = tic_omp()
      VerbosePrint  "    t1 = ", real(t1, dp)
      do i = 1, nrep
         c = cfac*c + b
      end do
      t2 = tic_omp()
      VerbosePrint  "    t2 = ", real(t2, dp)
      etime = tdiff_omp(t2, t1)
      VerbosePrint '    Time for simple evaluation (s) = ', etime

      call reset_timer_omp()
      VerbosePrint "  "
      VerbosePrint "2. Simple tic toc usage "
      VerbosePrint "    t1=TIC ... etime=TOC(T1)"

      t1 = tic_omp()
      VerbosePrint  "    t1 = ", real(t1, dp)
      c = .1
      do i = 1, nrep
         c = cfac*c + b
      end do
      etime = toc_omp(t1)
      VerbosePrint  '    toc(t1) = ', etime
      VerbosePrint  "  "

      call reset_timer_omp()
      VerbosePrint  "3. Simple tic toc "
      t1 = tic_omp()
      VerbosePrint "    t1 = ", real(t1, dp)
      c = .1
      do i = 1, nrep
         c = cfac*c + b
      end do
      etime = toc_omp()
      VerbosePrint '    toc() = ', etime
      VerbosePrint ' '

      call reset_timer_omp()
      VerbosePrint "4.  Testing return of toc in write cmd "
      t1 = tic_omp()
      VerbosePrint "     t1 = ", real(t1, dp)
      c = .1
      do i = 1, nrep
         c = cfac*c + b
      end do
      VerbosePrint '    toc in write ', toc_omp(t1)
      VerbosePrint "  "

      call reset_timer_omp()
      VerbosePrint "5.  Testing empty tic() lhs "
      open (10, file=DEV_NULL, IOSTAT=io_stat)
      if (be_verbose) write (10, '(A,1d20.10)') "     inline tic ", tic_omp()
      ! if(be_verbose) write (*, '(A,1d20.10)') "2. t1 = ", real(t1, dp)
      c = .1
      do i = 1, nrep
         c = cfac*c + b
      end do
      VerbosePrint "    tic/toc in write ", toc_omp()

      call reset_timer_omp()
      VerbosePrint ' '
      VerbosePrint '6.  Testing tic toc in preprocessor macro  '
      TBLOCK_omp()
      c = .1
      do i = 1, nrep
         c = cfac*c + b
      end do
      TSTOP_omp()
      VerbosePrint ' '

      call reset_timer_omp()
      VerbosePrint ' '
      VerbosePrint '7.  Testing tic toc in preprocessor macro with subroutine  '
      TBLOCK_omp()
      c = saxy(c)
      TSTOP_omp()
      VerbosePrint ' '

      call reset_timer_omp()
      VerbosePrint ' '
      VerbosePrint '8.  Testing timed_loop macro - must be in own subroutine '
      c = test_loop()

   end subroutine exec_OpenMP_timer_test

   function saxy(c_in) result(c)
      real(dp), intent(in) :: c_in
      integer(dp), parameter :: nrep = NREP_MAX
      real(dp)              :: c, cfac, b
      integer(dp)           :: i
      b = 1.
      c = c_in
      c = .1
      cfac = .25
      do i = 1, nrep
         c = cfac*c + b
      end do
   end function saxy

   !> Loop macro has to declare an array and an int
   !! -- this means it has to be at the top or in
   !!    its own function
   function test_loop() result(cloop)
      real(dp) :: cloop
      real(dp) :: timestamp
      real(dp), dimension(3):: elapsed
      integer :: ii
      do ii = 1, 3
         timestamp = tic_omp()
         cloop = REAL(.1, dp)
         cloop = saxy(cloop)
         elapsed(ii) = toc_omp(timestamp)
      end do
      write (*, '(A,A,1i4,A)') __FILENAME__, ":", __LINE__, ' *** Timed loop *** '
      write (*, '(A,1d20.10)') "    Average over 3 (sec):", SUM(elapsed, DIM=1)/REAL(3., dp)
      write (*, '(A,1d20.10)') "    Min time (sec) ", MINVAL(elapsed, DIM=1)
      write (*, "(A)") ' '

   end function test_loop

end module simple_timer_omp_test
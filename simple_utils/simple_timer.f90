!==Module simple_timer
!
!>\brief High resolution timer in fortran
!
! Version 0.1:  64 bit INT implementation of system_clock
!  present in gfortran and pgfortran
! Version 0.2: Special loop and profiling timers added May 2017
!
! Michael Eager 2017
!<------------------------------------
module simple_timer
!     use simple_jiffys ! singleton
!     use simple_defs   ! singleton
   use precision_m
   implicit none
!  private :: raise_sys_error
   private
   integer(dp), public   :: clock_ticks_per_second = INT(0, dp) !< Number of counts per second
   integer(dp), public   :: last_time_point = INT(0, dp) !< Current timesamp
   integer, public       :: idx_elapsed = 0, num_elapsed = 3
   integer, public       :: num_profile_loops, num_profile_vars
   logical, public       :: inloop = .false.
   integer, public       :: profile_counter
   integer, parameter, public :: ic_profile = 5 ! number of entries in language dictionary
   integer, parameter, public :: lc_profile = 30 ! max length of tokens
   real(dp), allocatable, public :: elapsed_times(:)
   real(dp), allocatable, public :: profile_matrix(:, :)
   integer(dp), dimension(ic_profile), public :: profile_last_timerstamp
   character(len=lc_profile), dimension(ic_profile), public :: profile_labels = ""

   public :: tic, tickrate
   public :: toc, tdiff, tocprint
   public :: now, reset_timer
   public :: timer_loop_start, in_timer_loop, timer_loop_end
   public :: timer_profile_setup, timer_profile_start, timer_profile_break, timer_profile_report

contains

!< Force timestamps and clock rate to zero
   subroutine reset_timer
      last_time_point = INT(0, dp)
      if (allocated(elapsed_times)) deallocate (elapsed_times)
   end subroutine reset_timer

!< Get system_clock timestamp
   integer(dp) function tic()
      call system_clock(count=tic)
      last_time_point = tic
   end function tic

!< Get the clock tick count per second
   integer(dp) function tickrate()
      tickrate = INT(0, dp)
      if (clock_ticks_per_second .eq. 0) call system_clock(count_rate=tickrate)
      clock_ticks_per_second = tickrate
#ifdef _DEBUG
      write (*, '(A,1d20.10)') " CLOCK_RATE(ticks/sec) ", REAL(clock_ticks_per_second, dp)
#endif
   end function tickrate

!< Calculate the time from two timestamps
   real(dp) function tdiff(tfinal, tstart)
      integer(dp), intent(in) :: tfinal
      integer(dp), intent(in) :: tstart
! integer(dp)                       ::  end_point
! if(present(tstart)) last_time_point = tstart
! if(.not. present(tfinal)) then
!    call system_clock(count=end_point)
!    tfinal = end_point
! end if
      if (clock_ticks_per_second .eq. INT(0, dp)) call system_clock(count_rate=clock_ticks_per_second)
! Calulate the time difference
      tdiff = REAL(tfinal - tstart, dp)/REAL(clock_ticks_per_second, dp)
!      last_time_point = tfinal
   end function tdiff

!< Complete the timing regime using a reference timestamp or the one
!  in last_time_point
   real(dp) function toc(tstart)
      integer(dp), intent(in), optional ::  tstart
      integer(dp)                       ::  end_point
      if (present(tstart)) last_time_point = tstart
      call system_clock(count=end_point)
      toc = tdiff(end_point, last_time_point)
      last_time_point = end_point
   end function toc

!< Complete the timing regime using a reference timestamp or the one
!  in last_time_point
   subroutine tocprint(tstart, comment)
      character(len=*), intent(inout), optional :: comment
      integer(dp), intent(in), optional ::  tstart
      integer(dp)                     ::  end_point
      real(dp)                        :: elapsed
      if (.not. present(comment)) comment = " Simple timer "

      if (present(tstart)) last_time_point = tstart
      call system_clock(count=end_point)
#ifdef _DEBUG
      write (*, '(A,1d20.10)') " TOC Time stamp ", REAL(end_point, dp)
#endif
      elapsed = tdiff(end_point, last_time_point)
      last_time_point = end_point
      write (*, '(A,A,1F20.10)') trim(comment), " Elapsed time ", elapsed
   end subroutine tocprint

!> print current time and date
   subroutine now
      character(len=8)  :: date
      character(len=10) :: time
      print *, "System_clock: ", tic()
      call date_and_time(date, time)
      write (*, '(A,A,A,A,A,A,A)') 'Date: ', date(7:8), '-', date(5:6), '-', date(1:4), '\n'
      write (*, '(A,A,A,A,A,A,A)') 'Time: ', time(1:2), ':', time(3:4), ':', time(5:10), '\n'
   end subroutine now

!< in_timer_loop checks the time within a timer loop
! It does not start the timer or set the inloop variable
! It returns false on the final loop- so that timer_loop_end can finish
   logical function in_timer_loop()
      in_timer_loop = .false.
      if (.not. inloop) then
         print *, "Failed timer_loop: Timer loop did not start"
      else
         if (idx_elapsed .lt. num_elapsed) then
            elapsed_times(idx_elapsed) = toc()
            idx_elapsed = idx_elapsed + 1
            in_timer_loop = .true.
         end if
      end if
   end function in_timer_loop
!<Begin timer loop
   subroutine timer_loop_start(num)
      integer, intent(in), optional :: num
      integer(dp)  :: dummytimestamp
      num_elapsed = 3
      if (present(num)) num_elapsed = num
      call reset_timer()
      if (num_elapsed .gt. 1) then
         allocate (elapsed_times(num_elapsed))
         idx_elapsed = 1
         dummytimestamp = tic()
         inloop = .true.
      end if
#ifdef _DEBUG
      print *, 'Size of elapsed array ', size(elapsed_times)
#endif
   end subroutine timer_loop_start
!< end timer loop
   subroutine timer_loop_end(COMMENT)
      character(len=*), intent(in), optional :: COMMENT
      character(len=128) :: strcomment
      if (.not. present(COMMENT)) then
         strcomment = ' no comment '
      else
         if (len_trim(COMMENT) .le. 128) then
            strcomment = trim(adjustl(COMMENT))
         else
            stop "Timer loop error - comment string must be less than 128 characters"
         end if
      end if
      if (.not. inloop) then
         print *, "Failed timer_loop_end: Timer loop did not start"
      else
         write (*, '(A,A)') "******* TIMER LOOP ", trim(strcomment)
         write (*, '(A,1i8)') '*** Iterations:  ', num_elapsed
         if (idx_elapsed .eq. num_elapsed) then
            elapsed_times(idx_elapsed) = toc()
            write (*, '(A,1d20.10)') "*** Average (sec):", &
               SUM(elapsed_times, DIM=1)/REAL(num_elapsed, dp)
            write (*, '(A,1d20.10,A,1i3)') "*** Longest run(sec) ", &
               MAXVAL(elapsed_times, DIM=1), &
               '    at ', MAXLOC(elapsed_times, DIM=1)
            write (*, '(A,1d20.10,A,1i3)') "*** Shortest run(sec) ", &
               MINVAL(elapsed_times, DIM=1), &
               '   at ', MINLOC(elapsed_times, DIM=1)
         else
            write (*, '(A,1i8)') '*** Failed at iteration ', idx_elapsed
         end if
         write (*, '(A)') "******* TIMER LOOP **************"
         inloop = .false.
         if (allocated(elapsed_times)) then
            deallocate (elapsed_times)
         end if
      end if
   end subroutine timer_loop_end
!< Setup profiling
   subroutine timer_profile_setup(nLoops, nVars, v) !1,v2,v3,v4,v5)
      integer(dp), intent(in) :: nLoops
      integer, intent(in) :: nVars
      character(len=*), intent(in) :: v(:)
      if (nLoops .lt. 1) then
         print *, "timer_profile_setup error -- must have more than 1 loop"
         return
      end if
!      nVars = size(v)
      if (nVars .gt. 5 .or. nVars .le. 0) then
         stop "timer_profile_setup error -- maximum 5 labels, minimum 1"
      else
         !      allocate (character(len=lc_profile) :: profile_labels(5))
         ! profile_labels are a fixed size
         if (nVars .ge. 1 .and. v(1) .ne. "") then
            if (len_trim(v(1)) .le. lc_profile) then
               profile_labels(1) = trim(adjustl(v(1)))
               num_profile_vars = 1
            else
               stop'Error: Timer profile token 1 too long'
            end if
         end if
         if (nVars .ge. 2 .and. v(2) .ne. "") then
            if (len_trim(v(2)) .le. lc_profile) then
               profile_labels(2) = trim(adjustl(v(2)))
               num_profile_vars = 2
            else
               stop'Error: Timer profile token 2 too long'
            end if
         end if
         if (nVars .ge. 3 .and. v(3) .ne. "") then
            if (len_trim(v(3)) .le. lc_profile) then
               profile_labels(3) = trim(adjustl(v(3)))
               num_profile_vars = 3
            else
               stop'Error: Timer profile token 3 too long'
            end if
         end if
         if (nVars .ge. 4 .and. v(4) .ne. "") then
            if (len_trim(v(4)) .le. lc_profile) then
               profile_labels(4) = trim(adjustl(v(4)))
               num_profile_vars = 4
            else
               stop'Error: Timer profile token 4 too long'
            end if
         end if
         if (nVars .ge. 5 .and. v(5) .ne. "") then
            if (len_trim(v(5)) .le. lc_profile) then
               profile_labels(5) = trim(adjustl(v(5)))
               num_profile_vars = 5
            else
               stop'Error: Timer profile token 5 too long'
            end if
         end if
      end if
      if (nVars .ne. num_profile_vars) then
         stop'timer profile setup error: vars input > internal num_profile_vars'
      end if
      num_profile_loops = nLoops
      if (allocated(profile_matrix)) deallocate (profile_matrix)
!if (allocated(profile_last_timerstamp)) deallocate (profile_last_timerstamp)
! allocate (profile_last_timerstamp(num_profile_loops))
      allocate (profile_matrix(num_profile_loops, num_profile_vars))
      profile_matrix = REAL(0.0, dp)
      profile_last_timerstamp = INT(0, dp)
#ifdef _DEBUG
#if _DEBUG > 1
      print *, " Profile matrix size ", size(profile_matrix, 1), size(profile_matrix, 2)
      print *, profile_matrix(1:10, 1:2)
#endif
#endif
   end subroutine timer_profile_setup

!< Within profile loop - start timer with token 'LABEL'
   subroutine timer_profile_start(LABEL)
      character(len=*), intent(in) :: LABEL
      integer ::  ival
      do ival = 1, num_profile_vars
         if (.not. (INDEX(profile_labels(ival), trim(adjustl(LABEL))) == 0)) then
            profile_last_timerstamp(ival) = tic()
            exit
         end if
      end do
#ifdef _DEBUG
      if (ival .gt. num_profile_vars) then
         write (*, '(A,A,A,1i10)') "Error Timer_Profile_start:", &
            trim(adjustl(LABEL)), " label index outside range ", ival
      else
         print *, "Label: ", profile_labels(ival), " time stamp "
      end if
#endif
   end subroutine timer_profile_start

!< Within profile loop - get elapsed time for token 'LABEL' and reset
   subroutine timer_profile_break(LABEL)
      character(len=*), intent(in) :: LABEL
      integer(dp) :: tmp_tstamp = INT(0, dp)
      integer ::  ival = 0, iloop = 0
!
! Need bounds checking of timestamps and matrix
      do ival = 1, num_profile_vars
         iloop = 0
         if (.not. (INDEX(profile_labels(ival), trim(adjustl(LABEL))) == 0)) then

#ifdef _DEBUG
#if _DEBUG > 1
            print *, 'Timer profile break: Found label ', profile_labels(ival)
#endif
#endif

            do iloop = 1, num_profile_loops
               if (profile_matrix(iloop, ival) .eq. 0) then
                  tmp_tstamp = tic()
                  profile_matrix(iloop, ival) = tdiff(tmp_tstamp, profile_last_timerstamp(ival))
                  profile_last_timerstamp(ival) = tmp_tstamp
                  exit
               end if
            end do
            exit
         end if
      end do
      if (tmp_tstamp .eq. 0) then
       write (*, '(A,2i8,A)') "Error Timer_Profile_break: No time stamp created. loop,val,label:", iloop, ival, trim(adjustl(LABEL))
      end if
      if (ival .gt. num_profile_vars + 1) then
         write (*, '(A,1i8)') "Error Timer_Profile_break: label index outside range ", ival
      end if
      if (iloop .gt. num_profile_loops + 1) then
         write (*, '(A,1i8)') "Error Timer_Profile_break: loop index outside range ", iloop
      end if
#ifdef _DEBUG
#if _DEBUG > 1
      if ((ival .gt. num_profile_vars) .or. (iloop .gt. num_profile_loops)) then
         write (*, '(A,2i10)') "Timer_Profile_break: label/loop index outside range ", ival, iloop
      else
         print *, "Label: ", profile_labels(ival), " time ", profile_matrix(iloop, ival)
      end if
#endif
#endif
   end subroutine timer_profile_break

!< Profile report
   subroutine timer_profile_report(COMMENT, totaltime)
      character(len=*), intent(in) :: COMMENT
      real(dp), intent(in):: totaltime
      integer :: ival, iloop
!    if (.not.present(COMMENT)) COMMENT="PROFILE"
      write (*, '(A,A,A)') "** PROFILE REPORT : ", trim(adjustl(COMMENT))
      write (*, '(A,A,A,1i4)') '** FILE:LINE: ', __FILE__, ":", __LINE__
      write (*, '(A,1i8,A)') '** Iterations: ', num_profile_loops, ' timed loops'

      do ival = 1, num_profile_vars
         write (*, '(A,A)') '**** Label name: ', trim(profile_labels(ival))
         write (*, '(A,1d20.10)') "**** Average (sec):", &
            SUM(profile_matrix(:, ival), MASK=(profile_matrix(:, ival) /= 0.), DIM=1)/REAL(num_profile_loops, dp)
         write (*, '(A,1d20.10,A,1i3)') "**** Longest run(sec) ", &
            MAXVAL(profile_matrix(:, ival), MASK=(profile_matrix(:, ival) /= 0.), DIM=1), &
            '    at ', MAXLOC(profile_matrix(:, ival), MASK=(profile_matrix(:, ival) /= 0.), DIM=1)
         write (*, '(A,1d20.10,A,1i3)') "**** Shortest run(sec) ", &
            MINVAL(profile_matrix(:, ival), MASK=(profile_matrix(:, ival) /= 0.), DIM=1), &
            '   at ', MINLOC(profile_matrix(:, ival), MASK=(profile_matrix(:, ival) /= 0.), DIM=1)
      end do
      write (*, '(A,1d20.10)') "** Total time (sec):", totaltime
      write (*, '(A,1d20.10)') "** Average iteration (sec):", totaltime/REAL(num_profile_loops, dp)

      write (*, '(A,A,A)') "******* END ", trim(COMMENT), " REPORT **************"
      deallocate (profile_matrix)

! unset labels
      profile_labels = ""
      profile_last_timerstamp = INT(0, dp)
   end subroutine timer_profile_report

end module simple_timer


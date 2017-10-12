program simple_test_gencorrs_fft
use simple_polarft_corrcalc, only: polarft_corrcalc
use simple_cmdline,          only: cmdline
use simple_build,            only: build
use simple_params,           only: params
use simple_timer
implicit none
type(params)            :: p
type(polarft_corrcalc)  :: pftcc
type(cmdline)           :: cline
type(build)             :: b
real, allocatable       :: cc(:), cc_fft(:)
integer                 :: iptcl, jptcl, irot, loc_cc(1), loc_cc_fft(1), nerrors, cnt
integer(timer_int_kind) :: torig, tfft
real                    :: err, erravg, errmax
if( command_argument_count() < 3 )then
    write(*,'(a)',advance='no') 'simple_test_srch stk=<particles.mrc> msk=<mask radius(in pixels)>'
    write(*,'(a)') ' smpd=<sampling distance(in A)>'
    stop
endif
call cline%parse
call cline%checkvar('stk',  1)
call cline%checkvar('msk',  2)
call cline%checkvar('smpd', 3)
call cline%check
p = params(cline)
p%kfromto(1) = 2
p%kfromto(2) = 100
call b%build_general_tbox(p, cline)
call pftcc%new(p%nptcls, p)
call b%img_match%init_polarizer(pftcc)
do iptcl=1,p%nptcls
	call b%img_match%read(p%stk, iptcl)
	call b%img_match%fwd_ft
	! transfer to polar coordinates
    call b%img_match%polarize(pftcc, iptcl, isptcl=.false.)
    call b%img_match%polarize(pftcc, iptcl)
end do
allocate(cc(pftcc%get_nrots()), cc_fft(pftcc%get_nrots()))

!### TIMING


tfft = tic()
do iptcl=1,p%nptcls - 1
	do jptcl=iptcl + 1, p%nptcls
		cc_fft = pftcc%gencorrs(iptcl, jptcl)
	end do
end do
print *, 'time of fft_mod: ', toc(tfft)

! erravg = 0.
! errmax = 0.
! cnt    = 0
! do iptcl=1,p%nptcls - 1
! 	do jptcl=iptcl + 1, p%nptcls
! 		cc = pftcc%gencorrs(iptcl, jptcl)
! 		cc_fft = pftcc%gencorrs_fft(iptcl, jptcl)
! 		do irot=1,pftcc%get_nrots()
! 			err    = abs(cc(irot) - cc_fft(irot))

! 			print *, cc(irot), cc_fft(irot), err

! 			if( err > errmax ) errmax = err
! 			erravg = erravg + err
! 			cnt = cnt + 1
! 		end do
! 		stop
! 	end do
! end do
! print *, 'errmax: ', errmax
! print *, 'erravg: ', erravg
end program simple_test_gencorrs_fft

program simple_test_sp_project
use simple_oris,       only: oris
use simple_sp_project, only: sp_project
use simple_binoris,    only: binoris
implicit none

type(sp_project) :: myproject
type(binoris)    :: bos

! prepare stack oris in project
call myproject%os_stk%new_clean(2)
call myproject%os_stk%set(1, 'movie',       'movie1.mrc')
call myproject%os_stk%set(1, 'intg',        'movie1_intg.mrc')
call myproject%os_stk%set(1, 'forctf',      'movie1_forctf.mrc')
call myproject%os_stk%set(1, 'pspec',       'movie1_pspec.mrc')
call myproject%os_stk%set(1, 'thumb',       'movie1_thumb.mrc')
call myproject%os_stk%set(1, 'intg_frames', 'movie1_intg_frames1-14.mrc')
call myproject%os_stk%set(1, 'smpd',        1.3)
call myproject%os_stk%set(2, 'movie',       'movie2.mrc')
call myproject%os_stk%set(2, 'intg',        'movie2_intg.mrc')
call myproject%os_stk%set(2, 'forctf',      'movie2_forctf.mrc')
call myproject%os_stk%set(2, 'pspec',       'movie2_pspec.mrc')
call myproject%os_stk%set(2, 'thumb',       'movie2_thumb.mrc')
call myproject%os_stk%set(2, 'intg_frames', 'movie2_intg_frames1-14.mrc')
call myproject%os_stk%set(2, 'smpd',        1.3)
! write/read
call myproject%write('myproject.simple')
call myproject%read('myproject.simple')
! call myproject%print_header
call myproject%write_sp_oris('stk', 'myproject_os_stk_1.txt')
end program simple_test_sp_project

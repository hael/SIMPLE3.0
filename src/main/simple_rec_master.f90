! 3D reconstruction - master module
module simple_rec_master
include 'simple_lib.f08'
use simple_build,     only: build
use simple_params,    only: params
use simple_cmdline,   only: cmdline
use simple_qsys_funs, only: qsys_job_finished
implicit none

public :: exec_rec_master
private
#include "simple_local_flags.inc"

contains

    subroutine exec_rec_master( b, p, cline, fbody_in )
        class(build),               intent(inout) :: b
        class(params),              intent(inout) :: p
        class(cmdline),             intent(inout) :: cline
        character(len=*), optional, intent(in)    :: fbody_in
        if( cline%defined('mul') ) call b%a%mul_shifts(p%mul)
        select case(p%eo)
            case( 'yes', 'aniso' )
                call exec_eorec_distr( b, p, cline, fbody_in )
            case( 'no' )
                call exec_rec( b, p, cline, fbody_in )
            case DEFAULT
                call simple_stop('unknonw eo flag; simple_rec_master :: exec_rec_master')
        end select
        if( cline%defined('mul') ) stop 'mul flag no longer supported; rec_master :: exec_rec_master'
    end subroutine exec_rec_master

    subroutine exec_rec( b, p, cline, fbody_in )
        use simple_timer
        class(build),               intent(inout) :: b
        class(params),              intent(inout) :: p
        class(cmdline),             intent(inout) :: cline
        character(len=*), optional, intent(in)    :: fbody_in
        character(len=:), allocatable :: fbody
        character(len=STDLEN)         :: rho_name
        integer :: s
        ! rebuild b%vol according to box size (beacuse it is otherwise boxmatch)
        call b%vol%new([p%box,p%box,p%box], p%smpd)
        do s=1,p%nstates
            if( b%a%get_pop(s, 'state') == 0 ) cycle ! empty state
            if( p%l_distr_exec )then ! embarrasingly parallel rec
                if( present(fbody_in) )then
                    allocate(fbody, source=trim(adjustl(fbody_in))//&
                    &'_state'//int2str_pad(s,2)//'_part'//int2str_pad(p%part,p%numlen))
                else
                    allocate(fbody, source='recvol_state'//int2str_pad(s,2)//&
                    &'_part'//int2str_pad(p%part,p%numlen))
                endif
                p%vols(s)%str = fbody//p%ext
                rho_name      = 'rho_'//fbody//p%ext
                call b%recvol%rec(p, b%spproj, b%a, b%se, s, part=p%part)
                call b%recvol%compress_exp
                call b%recvol%write(p%vols(s)%str, del_if_exists=.true.)
                call b%recvol%write_rho(trim(rho_name))
            else ! shared-mem parallel rec
                if( present(fbody_in) )then
                    allocate(fbody, source=trim(adjustl(fbody_in))//'_state')
                else
                    allocate(fbody, source='recvol_state')
                endif
                p%vols(s)%str = fbody//int2str_pad(s,2)//p%ext
                call b%recvol%rec(p, b%spproj, b%a, b%se, s)
                call b%recvol%clip(b%vol)
                call b%vol%write(p%vols(s)%str, del_if_exists=.true.)
            endif
            deallocate(fbody)
        end do
        write(*,'(a)') "GENERATED VOLUMES: reconstruct3D*.ext"
        call qsys_job_finished( p, 'simple_rec_master :: exec_rec')
    end subroutine exec_rec

    subroutine exec_eorec_distr( b, p, cline, fbody_in )
        use simple_strings, only: int2str_pad
        class(build),               intent(inout) :: b
        class(params),              intent(inout) :: p
        class(cmdline),             intent(inout) :: cline
        character(len=*), optional, intent(in)    :: fbody_in
        character(len=:), allocatable :: fbody, fname
        integer :: s
        if( .not. p%l_distr_exec ) stop 'eo .ne. no not supported here, use simple_distr_exec!'
        ! rebuild b%vol according to box size (beacuse it is otherwise boxmatch)
        call b%vol%new([p%box,p%box,p%box], p%smpd)
        do s=1,p%nstates
            DebugPrint  'processing state: ', s
            if( b%a%get_pop(s, 'state') == 0 ) cycle ! empty state
            if( present(fbody_in) )then
                allocate(fbody, source=trim(adjustl(fbody_in))//'_state')
            else
                allocate(fbody, source='recvol_state')
            endif
            call b%eorecvol%eorec_distr(p, b%spproj, b%a, b%se, s, fbody=fbody)
            deallocate(fbody)
        end do
        call qsys_job_finished( p, 'simple_rec_master :: exec_eorec')
        write(*,'(a,1x,a)') "GENERATED VOLUMES: reconstruct3D*.ext"
    end subroutine exec_eorec_distr

end module simple_rec_master

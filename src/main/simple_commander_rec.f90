! concrete commander: 3D reconstruction routines
module simple_commander_rec
include 'simple_lib.f08'
use simple_parameters,          only: parameters
use simple_builder,             only: builder
use simple_cmdline,             only: cmdline
use simple_commander_base,      only: commander_base
use simple_projection_frcs,     only: projection_frcs
use simple_strategy2D3D_common, only: gen_projection_frcs
implicit none

public :: reconstruct3D_commander
public :: volassemble_eo_commander
public :: volassemble_commander
private
#include "simple_local_flags.inc"

type, extends(commander_base) :: reconstruct3D_commander
  contains
    procedure :: execute      => exec_reconstruct3D
end type reconstruct3D_commander
type, extends(commander_base) :: volassemble_eo_commander
  contains
    procedure :: execute      => exec_volassemble_eo
end type volassemble_eo_commander
type, extends(commander_base) :: volassemble_commander
  contains
    procedure :: execute      => exec_volassemble
end type volassemble_commander


integer(timer_int_kind) :: tcommrec
contains

    !> for reconstructing volumes from image stacks and their estimated orientations
    subroutine exec_reconstruct3D( self, cline )
        use simple_rec_master, only: exec_rec_master
        class(reconstruct3D_commander), intent(inout) :: self
        class(cmdline),                 intent(inout) :: cline
        type(parameters) :: params
        type(builder)    :: build
        tcommrec=tic()
        DebugPrint ' In exec_reconstruct3D'
        call build%init_params_and_build_general_tbox(cline, params)
        DebugPrint ' In exec_reconstruct3D init and build'

        select case(params%eo)
            case( 'yes', 'aniso' )
                call build%build_rec_eo_tbox(params) ! eo_reconstruction objs built
            case( 'no' )
                call build%build_rec_tbox(params)    ! reconstruction objects built
            case DEFAULT
                stop 'unknown eo flag; simple_commander_rec :: exec_reconstruct3D'
        end select
        DebugPrint ' In exec_reconstruct3D; built rec tboxes'
        call exec_rec_master
        DebugPrint ' In exec_reconstructor; done                                 ', toc(tcommrec), ' secs'

        ! end gracefully
        call simple_end('**** SIMPLE_RECONSTRUCT3D NORMAL STOP ****', print_simple=.false.)
    end subroutine exec_reconstruct3D

    !> for assembling even/odd volumes generated with distributed execution
    subroutine exec_volassemble_eo( self, cline )
        use simple_reconstructor_eo, only: reconstructor_eo
        use simple_filterer,         only: gen_anisotropic_optlp
        class(volassemble_eo_commander), intent(inout) :: self
        class(cmdline),                  intent(inout) :: cline
        type(parameters)              :: params
        type(builder)                 :: build
        type(reconstructor_eo)        :: eorecvol_read
        character(len=:), allocatable :: finished_fname, recname, volname
        character(len=32)             :: eonames(2), resmskname, benchfname
        real, allocatable             :: res05s(:), res0143s(:)
        real                          :: res
        integer                       :: part, s, n, ss, state, find4eoavg, fnr
        logical, parameter            :: L_BENCH = .false.
        integer(timer_int_kind)       :: t_init, t_assemble, t_sum_eos, t_sampl_dens_correct_eos
        integer(timer_int_kind)       :: t_gen_projection_frcs, t_gen_anisotropic_optlp
        integer(timer_int_kind)       :: t_sampl_dens_correct_sum, t_eoavg, t_tot
        real(timer_int_kind)          :: rt_init, rt_assemble, rt_sum_eos, rt_sampl_dens_correct_eos
        real(timer_int_kind)          :: rt_gen_projection_frcs, rt_gen_anisotropic_optlp
        real(timer_int_kind)          :: rt_sampl_dens_correct_sum, rt_eoavg, rt_tot
        if( L_BENCH )then
            t_init = tic()
            t_tot  = t_init
        endif
        DebugPrint ' In exec_volassemble_eo; build_general_tbox'
        call build%init_params_and_build_general_tbox(cline,params)
        DebugPrint ' In exec_volassemble_eo; build rec eo'
        call build%build_rec_eo_tbox(params) ! reconstruction toolbox built
        call build%eorecvol%kill_exp         ! reduced meory usage
        allocate(res05s(params%nstates), res0143s(params%nstates), stat=alloc_stat)
        if(alloc_stat.ne.0)call allocchk("In: simple_eo_volassemble res05s res0143s",alloc_stat)
        res0143s = 0.
        res05s   = 0.
        ! rebuild build%vol according to box size (beacuse it is otherwise boxmatch)
        call build%vol%new([params%box,params%box,params%box], params%smpd)
        call eorecvol_read%new( build%spproj)
        call eorecvol_read%kill_exp ! reduced memory usage
        n = params%nstates*params%nparts
        if( L_BENCH )then
            ! end of init
            rt_init = toc(t_init)
            ! initialise incremental timers before loop
            rt_assemble                = 0.
            rt_sum_eos                 = 0.
            rt_sampl_dens_correct_eos  = 0.
            rt_gen_projection_frcs     = 0.
            rt_gen_anisotropic_optlp   = 0.
            rt_sampl_dens_correct_sum  = 0.
            rt_eoavg                   = 0.
        endif
        do ss=1,params%nstates
            if( cline%defined('state') )then
                s     = 1        ! index in reconstruct3D
                state = params%state  ! actual state
            else
                s     = ss
                state = ss
            endif
            if( L_BENCH ) t_assemble = tic()
            call build%eorecvol%reset_all
            ! assemble volumes
            do part=1,params%nparts
                call eorecvol_read%read_eos(trim(VOL_FBODY)//int2str_pad(state,2)//'_part'//int2str_pad(part,params%numlen))
                ! sum the Fourier coefficients
                call build%eorecvol%sum_reduce(eorecvol_read)
            end do
            if( L_BENCH ) rt_assemble = rt_assemble + toc(t_assemble)
            ! correct for sampling density and estimate resolution
            allocate(recname, source=trim(VOL_FBODY)//int2str_pad(state,2))
            allocate(volname, source=recname//params%ext)
            eonames(1) = trim(recname)//'_even'//params%ext
            eonames(2) = trim(recname)//'_odd'//params%ext
            resmskname = 'resmask'//params%ext
            if( L_BENCH ) t_sum_eos = tic()
            call build%eorecvol%sum_eos
            if( L_BENCH )then
                rt_sum_eos               = rt_sum_eos + toc(t_sum_eos)
                t_sampl_dens_correct_eos = tic()
            endif
            call build%eorecvol%sampl_dens_correct_eos(state, eonames(1), eonames(2), resmskname, find4eoavg)
            if( L_BENCH )then
                rt_sampl_dens_correct_eos = rt_sampl_dens_correct_eos + toc(t_sampl_dens_correct_eos)
                t_gen_projection_frcs     = tic()
            endif
            call gen_projection_frcs( cline, eonames(1), eonames(2), resmskname, s, build%projfrcs)
            if( L_BENCH ) rt_gen_projection_frcs = rt_gen_projection_frcs + toc(t_gen_projection_frcs)
            call build%projfrcs%write('frcs_state'//int2str_pad(state,2)//'.bin')
            if( L_BENCH ) t_gen_anisotropic_optlp = tic()
            call gen_anisotropic_optlp(build%vol2, build%projfrcs, build%eulspace_red, s, &
                &params%pgrp, params%hpind_fsc, params%l_phaseplate)
            if( L_BENCH ) rt_gen_anisotropic_optlp = rt_gen_anisotropic_optlp + toc(t_gen_anisotropic_optlp)
            call build%vol2%write('aniso_optlp_state'//int2str_pad(state,2)//params%ext)
            call build%eorecvol%get_res(res05s(s), res0143s(s))
            if( L_BENCH ) t_sampl_dens_correct_sum = tic()
            call build%eorecvol%sampl_dens_correct_sum( build%vol )
            if( L_BENCH ) rt_sampl_dens_correct_sum = rt_sampl_dens_correct_sum + toc(t_sampl_dens_correct_sum)
            call build%vol%write( volname, del_if_exists=.true. )
            call wait_for_closure( volname )
            ! need to put the sum back at lowres for the eo pairs
            if( L_BENCH ) t_eoavg = tic()
            call build%vol%fft()
            call build%vol2%zero_and_unflag_ft
            call build%vol2%read(eonames(1))
            call build%vol2%fft()
            call build%vol2%insert_lowres(build%vol, find4eoavg)
            call build%vol2%ifft()
            call build%vol2%write(eonames(1), del_if_exists=.true.)
            call build%vol2%zero_and_unflag_ft
            call build%vol2%read(eonames(2))
            call build%vol2%fft()
            call build%vol2%insert_lowres(build%vol, find4eoavg)
            call build%vol2%ifft()
            call build%vol2%write(eonames(2), del_if_exists=.true.)
            if( L_BENCH ) rt_eoavg = rt_eoavg + toc(t_eoavg)
            deallocate(recname, volname)
            if( cline%defined('state') )exit
        end do
        ! set the resolution limit according to the worst resolved model
        res  = maxval(res0143s)
        params%lp = max( params%lpstop,res )
        write(*,'(a,1x,F6.2)') '>>> LOW-PASS LIMIT:', params%lp
        call eorecvol_read%kill
        ! end gracefully
        call simple_end('**** SIMPLE_VOLASSEMBLE_EO NORMAL STOP ****', print_simple=.false.)
        ! indicate completion (when run in a qsys env)
        if( cline%defined('state') )then
            allocate( finished_fname, source='VOLASSEMBLE_FINISHED_STATE'//int2str_pad(state,2))
        else
            allocate( finished_fname, source='VOLASSEMBLE_FINISHED' )
        endif
        call simple_touch( finished_fname , errmsg='In: commander_rec::volassemble_eo')
        if( L_BENCH )then
            rt_tot     = toc(t_tot)
            benchfname = 'VOLASSEMBLE_EO_BENCH.txt'
            call fopen(fnr, FILE=trim(benchfname), STATUS='REPLACE', action='WRITE')
            write(fnr,'(a)') '*** TIMINGS (s) ***'
            write(fnr,'(a,1x,f9.2)') 'initialisation           : ', rt_init
            write(fnr,'(a,1x,f9.2)') 'assemble of volumes (I/O): ', rt_assemble
            write(fnr,'(a,1x,f9.2)') 'sum of eo-paris          : ', rt_sum_eos
            write(fnr,'(a,1x,f9.2)') 'gridding correction (eos): ', rt_sampl_dens_correct_eos
            write(fnr,'(a,1x,f9.2)') 'projection FRCs          : ', rt_gen_projection_frcs
            write(fnr,'(a,1x,f9.2)') 'anisotropic filter       : ', rt_gen_anisotropic_optlp
            write(fnr,'(a,1x,f9.2)') 'gridding correction (sum): ', rt_sampl_dens_correct_sum
            write(fnr,'(a,1x,f9.2)') 'averaging eo-pairs       : ', rt_eoavg
            write(fnr,'(a,1x,f9.2)') 'total time               : ', rt_tot
            write(fnr,'(a)') ''
            write(fnr,'(a)') '*** RELATIVE TIMINGS (%) ***'
            write(fnr,'(a,1x,f9.2)') 'initialisation           : ', (rt_init/rt_tot)                   * 100.
            write(fnr,'(a,1x,f9.2)') 'assemble of volumes (I/O): ', (rt_assemble/rt_tot)               * 100.
            write(fnr,'(a,1x,f9.2)') 'sum of eo-paris          : ', (rt_sum_eos/rt_tot)                * 100.
            write(fnr,'(a,1x,f9.2)') 'gridding correction (eos): ', (rt_sampl_dens_correct_eos/rt_tot) * 100.
            write(fnr,'(a,1x,f9.2)') 'projection FRCs          : ', (rt_gen_projection_frcs/rt_tot)    * 100.
            write(fnr,'(a,1x,f9.2)') 'anisotropic filter       : ', (rt_gen_anisotropic_optlp/rt_tot)  * 100.
            write(fnr,'(a,1x,f9.2)') 'gridding correction (sum): ', (rt_sampl_dens_correct_sum/rt_tot) * 100.
            write(fnr,'(a,1x,f9.2)') 'averaging eo-pairs       : ', (rt_eoavg/rt_tot)                  * 100.
            write(fnr,'(a,1x,f9.2)') '% accounted for          : ',&
            &((rt_init+rt_assemble+rt_sum_eos+rt_sampl_dens_correct_eos+rt_gen_projection_frcs+&
            &rt_gen_anisotropic_optlp+rt_sampl_dens_correct_sum+rt_eoavg)/rt_tot) * 100.
            call fclose(fnr)
        endif
    end subroutine exec_volassemble_eo

    !> for assembling a volume generated with distributed execution
    subroutine exec_volassemble( self, cline )
        !$ use omp_lib
        use simple_reconstructor, only: reconstructor
        class(volassemble_commander), intent(inout) :: self
        class(cmdline),               intent(inout) :: cline
        character(len=:), allocatable :: fbody, finished_fname
        type(parameters)              :: params
        type(builder)                 :: build
        character(len=STDLEN)         :: recvolname, rho_name
        integer                       :: part, s, ss, state, num_threads, max_threads
        type(reconstructor)           :: recvol_read
        tcommrec = tic()
        DebugPrint ' In exec_volassemble; '
        max_threads = omp_get_max_threads()
        call build%init_params_and_build_general_tbox(cline,params,boxmatch_off=.true.)
        call build%build_rec_tbox(params) ! reconstruction toolbox built
        DebugPrint ' In exec_volassemble; tbox done                              ', toc()
        DebugPrint ' In exec_volassemble; NTHR ', params%nthr, ' NPARTS ', params%nparts

        !$omp parallel
        num_threads =  omp_get_num_threads()
        !$omp end parallel
        DebugPrint ' CURRENT THREADS ', num_threads, ' MAX THREADS ', max_threads
        !$ call omp_set_num_threads(max_threads)
        !$omp parallel
        num_threads =  omp_get_num_threads()
        !$omp end parallel
        DebugPrint ' NEW CURRENT THREADS ', num_threads

        call recvol_read%new([params%boxpd,params%boxpd,params%boxpd], params%smpd)
        call recvol_read%alloc_rho( build%spproj)
         DebugPrint ' In exec_volassemble; read done                             ', toc()
        do ss=1,params%nstates
            if( cline%defined('state') )then
                s     = 1        ! index in reconstruct3D
                state = params%state  ! actual state
            else
                s     = ss
                state = ss
            endif
            call build%recvol%reset
            do part=1,params%nparts
                allocate(fbody, source=trim(VOL_FBODY)//int2str_pad(state,2)//'_part'//int2str_pad(part,params%numlen))
                params%vols(s) = fbody//params%ext
                rho_name      = 'rho_'//fbody//params%ext
                call assemble(params%vols(s), trim(rho_name))
                deallocate(fbody)
            end do
            DebugPrint ' In exec_volassemble; assemble done                     ', toc()
            if( params%nstates == 1 .and. cline%defined('outvol') )then
                recvolname = trim(params%outvol)
            else
                recvolname = 'recvol_state'//int2str_pad(state,2)//params%ext
            endif
            call correct_for_sampling_density(trim(recvolname))
            if( cline%defined('state') )exit
        end do
        DebugPrint ' In exec_volassemble; sample correction done                 ', toc()
        call recvol_read%dealloc_rho
        call recvol_read%kill
        ! end gracefully
        call simple_end('**** SIMPLE_VOLASSEMBLE NORMAL STOP ****', print_simple=.false.)
        ! indicate completion (when run in a qsys env)
        if( cline%defined('state') )then
            allocate( finished_fname, source='VOLASSEMBLE_FINISHED_STATE'//int2str_pad(state,2) )
        else
            allocate( finished_fname, source='VOLASSEMBLE_FINISHED' )
        endif
        call simple_touch( finished_fname, errmsg='In: commander_rec :: volassemble')
        DebugPrint ' In exec_volassemble; Completed in                           ', toc(tcommrec), ' secs'
        contains

            subroutine assemble( recnam, kernam )
                character(len=*), intent(in) :: recnam
                character(len=*), intent(in) :: kernam
                logical                      :: here(2)
                here(1)=file_exists(recnam)
                here(2)=file_exists(kernam)
                if( all(here) )then
                    call recvol_read%read(recnam)
                    call recvol_read%read_rho(kernam)
                    call build%recvol%sum_reduce(recvol_read)
                else
                    if( .not. here(1) ) write(*,'(A,A,A)') 'WARNING! ', adjustl(trim(recnam)), ' missing'
                    if( .not. here(2) ) write(*,'(A,A,A)') 'WARNING! ', adjustl(trim(kernam)), ' missing'
                    return
                endif
            end subroutine assemble

            subroutine correct_for_sampling_density( recname )
                character(len=*), intent(in) :: recname
                call build%recvol%sampl_dens_correct()
                call build%recvol%ifft()
                call build%recvol%clip(build%vol)
                call build%vol%write(recname, del_if_exists=.true.)
            end subroutine correct_for_sampling_density

    end subroutine exec_volassemble

end module simple_commander_rec

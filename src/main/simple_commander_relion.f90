module simple_commander_relion
include 'simple_lib.f08'
use simple_commander_base, only: commander_base
use simple_cmdline,        only: cmdline
use simple_sp_project,     only: sp_project
use simple_relion,         only: relion_project
use simple_oris,           only: oris
use simple_binoris_io,     only: binread_nlines, binread_oritab
use simple_parameters,     only: parameters, params_glob
implicit none

public :: export_relion_commander
private

type, extends(commander_base) :: export_relion_commander
contains
    procedure :: execute      => exec_export_relion
end type export_relion_commander

#include "simple_local_flags.inc"
contains

    subroutine exec_export_relion( self, cline )
        class(export_relion_commander), intent(inout) :: self
        class(cmdline), intent(inout) :: cline
        type(parameters)     :: params
        type(sp_project)     :: spproj
        type(relion_project) :: relionproj
        if( .not. cline%defined('mkdir') ) call cline%set('mkdir', 'yes')
        if( .not. cline%defined('eputiltgroups') ) call cline%set('eputiltgroups', 'no')
        if( .not. cline%defined('reliongroups') ) call cline%set('reliongroups', 'no')
        if( .not. cline%defined('relion3.1') ) call cline%set('relion3.1', 'yes')
        call params%new(cline)
        if( file_exists(params%projfile) )then
            call spproj%read(params%projfile)
        endif
        if( cline%get_rarg('reliongroups_count') .eq. 0.0) call cline%set('reliongroups_count', real(spproj%os_mic%get_noris()))
        call relionproj%create(cline, spproj)
        call spproj%kill
        call simple_end('**** export_relion NORMAL STOP ****')
    end subroutine exec_export_relion

end module simple_commander_relion

! high-level routines for sp-project updates
module simple_spproj_hlev
include 'simple_lib.f08'
use simple_sp_project, only: sp_project
use simple_parameters, only: params_glob
use simple_cmdline,    only: cmdline
use simple_chash,      only: chash
implicit none

public :: update_job_descriptions_in_project
private

contains

    subroutine update_job_descriptions_in_project( cline )
        class(cmdline), intent(in) :: cline
        character(len=:), allocatable :: exec, name
        type(chash)      :: job_descr
        type(sp_project) :: spproj
        logical          :: did_update
        if( .not. associated(params_glob)         ) return
        if( .not. associated(params_glob%ptr2prg) ) return
        exec = params_glob%ptr2prg%get_executable()
        if( str_has_substr(exec, 'private') ) return
        name = params_glob%ptr2prg%get_name()
        if( str_has_substr(name, 'print')   ) return
        if( str_has_substr(name, 'info')    ) return
        call cline%gen_job_descr(job_descr, name)
        if( file_exists(params_glob%projfile) )then
            call spproj%read_segment('jobproc', params_glob%projfile)
            call spproj%append_job_descr2jobproc(params_glob%exec_dir, job_descr, did_update)
            if( did_update ) call spproj%write_segment_inside('jobproc', params_glob%projfile)
        endif
    end subroutine update_job_descriptions_in_project

end module simple_spproj_hlev
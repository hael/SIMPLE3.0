! iterator for motion_correct (a program for motion correction, dose-weighting and frame-weighting of DDD movies)
module simple_motion_correct_iter
include 'simple_lib.f08'
use simple_image,        only: image
use simple_cmdline,      only: cmdline
use simple_parameters,   only: params_glob
use simple_ori,          only: ori
use simple_stackops,     only: frameavg_stack
use simple_motion_correct
implicit none

public :: motion_correct_iter
private
#include "simple_local_flags.inc"

logical,          parameter :: DO_ANISO   = .false.
logical,          parameter :: DO_PATCHED = .false.
character(len=*), parameter :: speckind   = 'sqrt'

type :: motion_correct_iter
    private
    ! these image objects are part of the instance to avoid excessive memory re-allocations
    type(image) :: moviesum, moviesum_corrected, moviesum_corrected_frames
    type(image) :: moviesum_ctf, pspec_sum, pspec_ctf, img_jpg
    type(image) :: pspec_half_n_half, thumbnail
    ! these strings are part of the instance for reporting purposes
    character(len=STDLEN) :: moviename, moviename_intg, moviename_intg_frames
    character(len=STDLEN) :: moviename_forctf, moviename_thumb, moviename_pspec
    character(len=STDLEN) :: moviename_aniso_intg, moviename_aniso_intg_frames
    character(len=STDLEN) :: moviename_aniso_forctf, moviename_aniso_thumb, moviename_aniso_pspec
    character(len=STDLEN) :: moviename_patched_intg, moviename_patched_intg_frames
    character(len=STDLEN) :: moviename_patched_forctf, moviename_patched_thumb, moviename_patched_pspec
  contains
    procedure :: iterate
    procedure :: get_moviename
end type motion_correct_iter

contains

    subroutine iterate( self, cline, ctfvars, orientation, fbody, frame_counter, moviename, dir_out, gainref_fname )
        class(motion_correct_iter), intent(inout) :: self
        class(cmdline),             intent(inout) :: cline
        type(ctfparams),            intent(inout) :: ctfvars
        class(ori),                 intent(inout) :: orientation
        integer,                    intent(inout) :: frame_counter
        character(len=*),           intent(in)    :: moviename, fbody, dir_out
        character(len=*), optional, intent(in)    :: gainref_fname
        character(len=:), allocatable :: fbody_here, ext, fname
        real,             allocatable :: shifts(:,:), aniso_shifts(:,:)
        type(stats_struct)        :: shstats(2)
        character(len=LONGSTRLEN) :: rel_fname
        integer :: ldim(3), ldim_thumb(3)
        real    :: scale, var
        logical :: err
        ! check, increment counter & print
        if( .not. file_exists(moviename) )then
            write(logfhandle,*) 'inputted movie stack does not exist: ', trim(moviename)
        endif
        ! make filenames
        fbody_here = basename(trim(moviename))
        ext        = fname2ext(trim(fbody_here))
        if( fbody.ne.'' )then
            fbody_here = trim(fbody)//'_'//get_fbody(trim(fbody_here), trim(ext))
        else
            fbody_here = get_fbody(trim(fbody_here), trim(ext))
        endif
        ! isotropic ones
        self%moviename_intg   = trim(dir_out)//trim(adjustl(fbody_here))//INTGMOV_SUFFIX//trim(params_glob%ext)
        self%moviename_forctf = trim(dir_out)//trim(adjustl(fbody_here))//FORCTF_SUFFIX//trim(params_glob%ext)
        self%moviename_pspec  = trim(dir_out)//trim(adjustl(fbody_here))//POWSPEC_SUFFIX//trim(params_glob%ext)
        self%moviename_thumb  = trim(dir_out)//trim(adjustl(fbody_here))//THUMBNAIL_SUFFIX//trim(JPG_EXT)
        if( cline%defined('tof') )then
            self%moviename_intg_frames = trim(dir_out)//trim(adjustl(fbody_here))//'_frames'//int2str(params_glob%fromf)//'-'&
            &//int2str(params_glob%tof)//INTGMOV_SUFFIX//params_glob%ext
        endif
        ! anisotropic ones
        self%moviename_aniso_intg   = trim(dir_out)//trim(adjustl(fbody_here))//'_aniso'//INTGMOV_SUFFIX//trim(params_glob%ext)
        self%moviename_aniso_forctf = trim(dir_out)//trim(adjustl(fbody_here))//'_aniso'//FORCTF_SUFFIX//trim(params_glob%ext)
        self%moviename_aniso_pspec  = trim(dir_out)//trim(adjustl(fbody_here))//'_aniso'//POWSPEC_SUFFIX//trim(params_glob%ext)
        self%moviename_aniso_thumb  = trim(dir_out)//trim(adjustl(fbody_here))//'_aniso'//THUMBNAIL_SUFFIX//trim(JPG_EXT)
        if( cline%defined('tof') )then
            self%moviename_aniso_intg_frames = trim(dir_out)//trim(adjustl(fbody_here))//'_frames'//&
            &int2str(params_glob%fromf)//'-'//int2str(params_glob%tof)//'_aniso_'//INTGMOV_SUFFIX//params_glob%ext
        endif
        ! patched ones
        self%moviename_patched_intg   = trim(dir_out)//trim(adjustl(fbody_here))//'_patched'//INTGMOV_SUFFIX//trim(params_glob%ext)
        self%moviename_patched_forctf = trim(dir_out)//trim(adjustl(fbody_here))//'_patched'//FORCTF_SUFFIX//trim(params_glob%ext)
        self%moviename_patched_pspec  = trim(dir_out)//trim(adjustl(fbody_here))//'_patched'//POWSPEC_SUFFIX//trim(params_glob%ext)
        self%moviename_patched_thumb  = trim(dir_out)//trim(adjustl(fbody_here))//'_patched'//THUMBNAIL_SUFFIX//trim(JPG_EXT)
        patched_shift_fname           = trim(dir_out)//trim(adjustl(fbody_here))//'_patched_shifts.eps'
        if( cline%defined('tof') )then
            self%moviename_patched_intg_frames = trim(dir_out)//trim(adjustl(fbody_here))//'_frames'//&
            &int2str(params_glob%fromf)//'-'//int2str(params_glob%tof)//'_patched_'//INTGMOV_SUFFIX//params_glob%ext
        endif
        ! check, increment counter & print
        write(logfhandle,'(a,1x,a)') '>>> PROCESSING MOVIE:', trim(moviename)
        ! averages frames as a pre-processing step (Falcon 3 with long exposures)
        if( params_glob%nframesgrp > 0 )then
            self%moviename = 'tmpnframesgrpmovie'//params_glob%ext
            call frameavg_stack(trim(moviename), trim(self%moviename), params_glob%nframesgrp, ctfvars%smpd)
        else
            self%moviename = trim(moviename)
        endif
        motion_correct_with_aniso   = (DO_ANISO .or. DO_PATCHED)
        motion_correct_with_patched = DO_PATCHED
        ! execute the motion_correction
        call motion_correct_iso(self%moviename, ctfvars, shifts, gainref_fname)
        ! return shift stats
        call moment(shifts(:,1), shstats(1)%avg, shstats(1)%sdev, var, err)
        call moment(shifts(:,2), shstats(2)%avg, shstats(2)%sdev, var, err)
        call orientation%set('xavg',  shstats(1)%avg)
        call orientation%set('xsdev', shstats(1)%sdev)
        call orientation%set('xmax',  maxval(shifts(:,1)))
        call orientation%set('xmin',  minval(shifts(:,1)))
        call orientation%set('yavg',  shstats(2)%avg)
        call orientation%set('ysdev', shstats(2)%sdev)
        call orientation%set('ymax',  maxval(shifts(:,2)))
        call orientation%set('ymin',  minval(shifts(:,2)))
        ! generate sums
        if( params_glob%tomo .eq. 'yes' )then
            call motion_correct_iso_calc_sums_tomo(frame_counter, params_glob%time_per_frame,&
            &self%moviesum, self%moviesum_corrected, self%moviesum_ctf)
        else
            if( cline%defined('tof') )then
                ! order matters here, if anisotropic correction is on the subsum needs to be generated first
                call motion_correct_iso_calc_sums(self%moviesum_corrected_frames, [params_glob%fromf,params_glob%tof])
                call motion_correct_iso_calc_sums(self%moviesum, self%moviesum_corrected, self%moviesum_ctf)
            else
                call motion_correct_iso_calc_sums(self%moviesum, self%moviesum_corrected, self%moviesum_ctf)
            endif
        endif
        ! destruct before anisotropic correction
        call motion_correct_iso_kill
        ! generate power-spectra
        !!!!!!!!!!!!!!!!!!!CHIARA!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
        print *, '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>.'
        print *, 'params_glob%pspecsz before', params_glob%pspecsz
        params_glob%pspecsz = 512
        print *, 'params_glob%pspecsz after', params_glob%pspecsz
        print *, '>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>.'
        self%pspec_sum = self%moviesum%mic2spec(params_glob%pspecsz, speckind, LP_PSPEC_BACKGR_SUBTR)
        self%pspec_ctf = self%moviesum_ctf%mic2spec(params_glob%pspecsz, speckind, LP_PSPEC_BACKGR_SUBTR)
        self%pspec_half_n_half = self%pspec_sum%before_after(self%pspec_ctf)
        call self%pspec_half_n_half%scale_pspec4viz
        ! write output
        if( cline%defined('tof') ) call self%moviesum_corrected_frames%write(self%moviename_intg_frames)
        call self%moviesum_corrected%write(self%moviename_intg)
        call self%moviesum_ctf%write(self%moviename_forctf)
        call self%pspec_ctf%write(self%moviename_pspec)
        ! generate thumbnail
        ldim          = self%moviesum_corrected%get_ldim()
        scale         = real(params_glob%pspecsz)/real(ldim(1))
        ldim_thumb(1) = round2even(real(ldim(1))*scale)
        ldim_thumb(2) = round2even(real(ldim(2))*scale)
        ldim_thumb(3) = 1
        call orientation%set('xdim', real(ldim(1)))
        call orientation%set('ydim', real(ldim(2)))
        call self%thumbnail%new(ldim_thumb, ctfvars%smpd)
        call self%moviesum_corrected%fft()
        call self%moviesum_corrected%clip(self%thumbnail)
        call self%thumbnail%ifft()
        ! jpeg output
        call self%pspec_half_n_half%collage(self%thumbnail, self%img_jpg)
        call self%img_jpg%write_jpg(self%moviename_thumb, norm=.true., quality=90)
        ! report to ori object
        call orientation%set('smpd',   ctfvars%smpd)
        call make_relativepath(CWD_GLOB,self%moviename,rel_fname)
        call orientation%set('movie',  trim(rel_fname))
        call make_relativepath(CWD_GLOB,self%moviename_intg,rel_fname)
        call orientation%set('intg',   trim(rel_fname))
        call make_relativepath(CWD_GLOB,self%moviename_forctf,rel_fname)
        call orientation%set('forctf', trim(rel_fname))
        call make_relativepath(CWD_GLOB,self%moviename_thumb,rel_fname)
        call orientation%set('thumb',  trim(rel_fname))
        call orientation%set('imgkind', 'mic')
        if( cline%defined('tof') )then
            call make_relativepath(CWD_GLOB,self%moviename_intg_frames,rel_fname)
            call orientation%set('intg_frames',  trim(rel_fname))
        endif
        if( DO_ANISO )then
            call motion_correct_aniso(aniso_shifts)
            if( cline%defined('tof') )then
                call motion_correct_aniso_calc_sums(self%moviesum_corrected_frames, [params_glob%fromf,params_glob%tof])
                call motion_correct_aniso_calc_sums(self%moviesum_corrected, self%moviesum_ctf)
            else
                call motion_correct_aniso_calc_sums(self%moviesum_corrected, self%moviesum_ctf)
            endif
            call motion_correct_aniso_kill
            ! generate power-spectra
            self%pspec_ctf = self%moviesum_ctf%mic2spec(params_glob%pspecsz, speckind, LP_PSPEC_BACKGR_SUBTR)
            self%pspec_half_n_half = self%pspec_sum%before_after(self%pspec_ctf)
            call self%pspec_half_n_half%scale_pspec4viz
            ! write output
            if( cline%defined('tof') ) call self%moviesum_corrected_frames%write(self%moviename_aniso_intg_frames)
            call self%moviesum_corrected%write(self%moviename_aniso_intg)
            call self%moviesum_ctf%write(self%moviename_aniso_forctf)
            call self%pspec_ctf%write(self%moviename_aniso_pspec)
            ! generate thumbnail
            call self%thumbnail%new(ldim_thumb, ctfvars%smpd)
            call self%moviesum_corrected%fft()
            call self%moviesum_corrected%clip(self%thumbnail)
            call self%thumbnail%ifft()
            ! jpeg output
            call self%pspec_half_n_half%collage(self%thumbnail, self%img_jpg)
            call self%img_jpg%write_jpg(self%moviename_aniso_thumb, norm=.true., quality=90)
            ! report to ori object
            fname = simple_abspath(self%moviename_aniso_intg, errmsg='simple_motion_correct_iter::iterate 6')
            call make_relativepath(CWD_GLOB,fname,rel_fname)
            call orientation%set('aniso_intg',   trim(rel_fname))
            fname = simple_abspath(self%moviename_aniso_forctf, errmsg='simple_motion_correct_iter::iterate 7')
            call make_relativepath(CWD_GLOB,fname,rel_fname)
            call orientation%set('aniso_forctf', trim(rel_fname))
            fname = simple_abspath(self%moviename_aniso_thumb, errmsg='simple_motion_correct_iter::iterate 8')
            call make_relativepath(CWD_GLOB,fname,rel_fname)
            call orientation%set('aniso_thumb',  trim(rel_fname))
            call orientation%set('imgkind', 'mic')
            if( cline%defined('tof') )then
                fname = simple_abspath(self%moviename_aniso_intg_frames, errmsg='simple_motion_correct_iter::iterate 9')
                call make_relativepath(CWD_GLOB,fname,rel_fname)
                call orientation%set('aniso_intg_frames', trim(rel_fname))
            endif
        endif
        if(DO_PATCHED) then
            call motion_correct_patched
            if( cline%defined('tof') )then
                call motion_correct_patched_calc_sums(self%moviesum_corrected_frames, [params_glob%fromf,params_glob%tof])
                call motion_correct_patched_calc_sums(self%moviesum_corrected, self%moviesum_ctf)
            else
                call motion_correct_patched_calc_sums(self%moviesum_corrected, self%moviesum_ctf)
            endif
            call motion_correct_patched_kill
            ! generate power-spectra
            self%pspec_ctf = self%moviesum_ctf%mic2spec(params_glob%pspecsz, speckind, LP_PSPEC_BACKGR_SUBTR)
            self%pspec_half_n_half = self%pspec_sum%before_after(self%pspec_ctf)
            call self%pspec_half_n_half%scale_pspec4viz
            ! write output
            if( cline%defined('tof') ) call self%moviesum_corrected_frames%write(self%moviename_patched_intg_frames)
            call self%moviesum_corrected%write(self%moviename_patched_intg)
            call self%moviesum_ctf%write(self%moviename_patched_forctf)
            call self%pspec_ctf%write(self%moviename_patched_pspec)
            ! generate thumbnail
            call self%thumbnail%new(ldim_thumb, ctfvars%smpd)
            call self%moviesum_corrected%fft()
            call self%moviesum_corrected%clip(self%thumbnail)
            call self%thumbnail%ifft()
            ! jpeg output
            call self%pspec_half_n_half%collage(self%thumbnail, self%img_jpg)
            call self%img_jpg%write_jpg(self%moviename_patched_thumb, norm=.true., quality=90)
            ! report to ori object
            fname = simple_abspath(self%moviename_patched_intg, errmsg='simple_motion_correct_iter::iterate 6')
            call make_relativepath(CWD_GLOB,fname,rel_fname)
            call orientation%set('patched_intg',   trim(rel_fname))
            fname = simple_abspath(self%moviename_patched_forctf, errmsg='simple_motion_correct_iter::iterate 7')
            call make_relativepath(CWD_GLOB,fname,rel_fname)
            call orientation%set('patched_forctf', trim(rel_fname))
            fname = simple_abspath(self%moviename_patched_thumb, errmsg='simple_motion_correct_iter::iterate 8')
            call make_relativepath(CWD_GLOB,fname,rel_fname)
            call orientation%set('patched_thumb',  trim(rel_fname))
            call orientation%set('imgkind', 'mic')
            if( cline%defined('tof') )then
                fname = simple_abspath(self%moviename_patched_intg_frames, errmsg='simple_motion_correct_iter::iterate 9')
                call make_relativepath(CWD_GLOB,fname,rel_fname)
                call orientation%set('patched_intg_frames', trim(rel_fname))
            endif
        endif
        call motion_correct_kill_common
        ! deallocate
        if( allocated(shifts) )       deallocate(shifts)
        if( allocated(aniso_shifts) ) deallocate(aniso_shifts)
    end subroutine iterate

    function get_moviename( self, which ) result( moviename )
        class(motion_correct_iter), intent(in) :: self
        character(len=*),           intent(in) :: which
        character(len=:), allocatable  :: moviename
        select case( which )
            case('intg')
                allocate(moviename, source=trim(self%moviename_intg))
            case('intg_frames')
                allocate(moviename, source=trim(self%moviename_intg_frames))
            case('forctf')
                allocate(moviename, source=trim(self%moviename_forctf))
            case('thumb')
                allocate(moviename, source=trim(self%moviename_thumb))
            case('aniso_intg')
                allocate(moviename, source=trim(self%moviename_aniso_intg))
            case('aniso_intg_frames')
                allocate(moviename, source=trim(self%moviename_aniso_intg_frames))
            case('aniso_forctf')
                allocate(moviename, source=trim(self%moviename_aniso_forctf))
            case('aniso_thumb')
                allocate(moviename, source=trim(self%moviename_aniso_thumb))
            case('patched_intg')
                allocate(moviename, source=trim(self%moviename_patched_intg))
            case('patched_intg_frames')
                allocate(moviename, source=trim(self%moviename_patched_intg_frames))
            case('patched_forctf')
                allocate(moviename, source=trim(self%moviename_patched_forctf))
            case('patched_thumb')
                allocate(moviename, source=trim(self%moviename_patched_thumb))
            case DEFAULT
                THROW_HARD('unsupported which flag; get_self%moviename')
        end select
    end function get_moviename

end module  simple_motion_correct_iter

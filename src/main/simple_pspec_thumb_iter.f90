! iterator for pspec_thumb (a program for motion correction, dose-weighting and frame-weighting of DDD movies)
module simple_pspec_thumb_iter
include 'simple_lib.f08'
use simple_image,      only: image
use simple_cmdline,    only: cmdline
use simple_parameters, only: params_glob
use simple_ori,        only: ori
implicit none

public :: pspec_thumb_iter
private
#include "simple_local_flags.inc"

type :: pspec_thumb_iter
    private
    character(len=4)      :: speckind = 'sqrt'
    character(len=STDLEN) :: moviename_thumb, moviename_pspec
    type(image)           :: moviesum, pspec, thumbnail
  contains
    procedure :: iterate
end type pspec_thumb_iter

contains

    subroutine iterate( self, orientation, moviename_intg, dir_out )
        class(pspec_thumb_iter), intent(inout) :: self
        class(ori),              intent(inout) :: orientation
        character(len=*),        intent(in)    :: moviename_intg, dir_out
        character(len=:), allocatable :: fbody_here, ext, fname
        type(image) :: img_jpg
        integer     :: ldim(3), ldim_thumb(3), nframes
        real        :: scale, smpd
        ! check, increment counter & print
        if( .not. file_exists(moviename_intg) )then
            write(*,*) 'inputted integrated movie does not exist: ', trim(moviename_intg)
        endif
        ! make filenames
        fbody_here = basename(trim(moviename_intg))
        ext        = fname2ext(trim(fbody_here))
        fbody_here = get_fbody(trim(fbody_here), trim(ext))
        self%moviename_pspec = trim(dir_out)//trim(adjustl(fbody_here))//POWSPEC_SUFFIX//trim(params_glob%ext)
        self%moviename_thumb = trim(dir_out)//trim(adjustl(fbody_here))//THUMBNAIL_SUFFIX//trim(JPG_EXT)
        write(*,'(a,1x,a)') '>>> PROCESSING INTEGRATED MOVIE:', trim(moviename_intg)
        call find_ldim_nptcls(trim(moviename_intg), ldim, nframes)
        if( nframes /= 1 ) THROW_HARD('imported movie assumed to be integrated but nframes /= 1, aborting; simple_pspec_thumb_iter :: iterate')
        if( .not. orientation%isthere('smpd') ) THROW_HARD('smpd assumed to be set in input orientation, aborting; simple_pspec_thumb_iter :: iterate')
        smpd = orientation%get('smpd')
        call self%moviesum%new(ldim, smpd)
        call self%moviesum%read(trim(moviename_intg))
        ! generate power-spectra
        self%pspec = self%moviesum%mic2spec(params_glob%pspecsz, self%speckind, LP_PSPEC_BACKGR_SUBTR)
        call self%pspec%write(self%moviename_pspec)
        ! generate thumbnail
        scale         = real(params_glob%pspecsz)/real(ldim(1))
        ldim_thumb(1) = round2even(real(ldim(1))*scale)
        ldim_thumb(2) = round2even(real(ldim(2))*scale)
        ldim_thumb(3) = 1
        call self%thumbnail%new(ldim_thumb, smpd)
        call self%moviesum%fft()
        call self%moviesum%clip(self%thumbnail)
        call self%thumbnail%ifft()
        ! jpeg output
        call self%pspec%collage(self%thumbnail, img_jpg)
        call img_jpg%write_jpg(self%moviename_thumb, quality=90)
        ! report to ori object
        fname = simple_abspath(moviename_intg, errmsg='simple_pspec_thumb_iter::iterate 1')
        call orientation%set('intg',   trim(fname))
        fname = simple_abspath(self%moviename_thumb, errmsg='simple_pspec_thumb_iter::iterate 2')
        call orientation%set('thumb',  trim(fname))
        call orientation%set('imgkind', 'intg')
        ! destruct
        call self%pspec%kill
        call self%moviesum%kill
        call img_jpg%kill
        call self%thumbnail%kill
    end subroutine iterate

end module  simple_pspec_thumb_iter

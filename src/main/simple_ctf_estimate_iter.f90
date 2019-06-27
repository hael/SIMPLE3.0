! ctf_estimate iterator
module simple_ctf_estimate_iter
include 'simple_lib.f08'
use simple_parameters, only: params_glob
use simple_image,      only: image
implicit none

public :: ctf_estimate_iter
private
#include "simple_local_flags.inc"

logical, parameter :: L_PATCH = .false.

type :: ctf_estimate_iter
    type(image) :: micrograph, pspec, thumbnail, img_jpg, pspec4viz
  contains
      procedure :: iterate
      procedure :: kill
end type ctf_estimate_iter

contains

    subroutine iterate( self, ctfvars, moviename_forctf, orientation, dir_out, l_gen_thumb )
        use simple_ori,              only: ori
        use simple_ctf_estimate_fit, only: ctf_estimate_fit
        class(ctf_estimate_iter), intent(inout) :: self
        class(ctfparams),         intent(inout) :: ctfvars
        character(len=*),         intent(in)    :: moviename_forctf
        class(ori),               intent(inout) :: orientation
        character(len=*),         intent(in)    :: dir_out
        logical,                  intent(in)    :: l_gen_thumb
        type(ctf_estimate_fit)        :: ctffit
        character(len=:), allocatable :: fname_diag
        character(len=LONGSTRLEN)     :: moviename_thumb, rel_moviename_thumb, rel_fname, epsname, docname
        real                          :: ctfscore, scale
        integer                       :: nframes, ldim(3), ldim_thumb(3)
        if( .not. file_exists(moviename_forctf) )&
        & write(logfhandle,*) 'inputted micrograph does not exist: ', trim(adjustl(moviename_forctf))
        call find_ldim_nptcls(trim(adjustl(moviename_forctf)), ldim, nframes)
        if( nframes /= 1 )then
            write(logfhandle,*) 'nframes: ', nframes
            THROW_HARD('single frame input to ctf_estimate assumed; iterate')
        endif
        ldim(3) = 1
        call self%micrograph%new(ldim, ctfvars%smpd)
        call self%micrograph%read(trim(adjustl(moviename_forctf)), 1)
        ! filter out frequencies lower than the box can express to avoid aliasing
        call self%micrograph%bp(real(params_glob%pspecsz) * ctfvars%smpd, 0.)
        call self%micrograph%ifft
        ! deal with output
        fname_diag = trim(get_fbody(basename(trim(moviename_forctf)), params_glob%ext, separator=.false.))
        if( str_has_substr(fname_diag, FORCTF_SUFFIX) )then
            fname_diag = swap_suffix(fname_diag, '_ctf_estimate_diag', FORCTF_SUFFIX)
        else if( str_has_substr(fname_diag, INTGMOV_SUFFIX) )then
            fname_diag = swap_suffix(fname_diag, '_ctf_estimate_diag', INTGMOV_SUFFIX)
        endif
        fname_diag = filepath(trim(dir_out),trim(fname_diag)//trim(JPG_EXT))
        ! global fitting
        call ctffit%new(self%micrograph, params_glob%pspecsz, ctfvars, [params_glob%dfmin,params_glob%dfmax],&
            &[params_glob%hp,params_glob%lp], params_glob%astigtol)
        call ctffit%fit( ctfvars )
        ctfscore = ctffit%get_ctfscore()
        if( l_gen_thumb )then
            ! generate thumbnail
            scale         = real(params_glob%pspecsz)/real(ldim(1))
            ldim_thumb(1) = round2even(real(ldim(1))*scale)
            ldim_thumb(2) = round2even(real(ldim(2))*scale)
            ldim_thumb(3) = 1
            call self%thumbnail%new(ldim_thumb, ctfvars%smpd)
            call self%micrograph%fft()
            call self%micrograph%clip(self%thumbnail)
            call self%thumbnail%ifft
            ! jpeg output
            call ctffit%get_pspec(self%pspec4viz)
            call self%pspec4viz%scale_pspec4viz
            call self%pspec4viz%collage(self%thumbnail, self%img_jpg)
            moviename_thumb = trim(get_fbody(basename(trim(moviename_forctf)), params_glob%ext, separator=.false.))
            moviename_thumb = trim(dir_out)//trim(adjustl(moviename_thumb))//trim(THUMBNAIL_SUFFIX)//trim(JPG_EXT)
            call self%img_jpg%write_jpg(moviename_thumb, norm=.true., quality=92)
            call make_relativepath(CWD_GLOB,moviename_thumb, rel_moviename_thumb)
            call orientation%set('thumb', trim(rel_moviename_thumb))
        endif
        ! patch based fitting
        if( L_PATCH )then
            call ctffit%fit_patches
            epsname = trim(get_fbody(basename(trim(moviename_forctf)), params_glob%ext, separator=.false.))
            epsname = trim(dir_out)//trim(adjustl(epsname))//'_ctf.eps'//C_NULL_CHAR
            docname = trim(get_fbody(basename(trim(moviename_forctf)), params_glob%ext, separator=.false.))
            docname = trim(dir_out)//trim(adjustl(docname))//'_ctf'//trim(TXT_EXT)
            !docname = trim(dir_out)//trim(adjustl(docname))//trim(TXT_EXT)//C_NULL_CHAR ! for future use of star format?
            call ctffit%plot_parms(epsname)
            call ctffit%write_diagnostic_patch(fname_diag)
            call ctffit%write_doc(moviename_forctf, docname)
            call make_relativepath(CWD_GLOB,docname,rel_fname)
            call orientation%set('ctfdoc', rel_fname)
        else
            call ctffit%write_diagnostic(fname_diag)
        endif
        call make_relativepath(CWD_GLOB,fname_diag, rel_fname)
        ! reporting
        call orientation%set('dfx',            ctfvars%dfx)
        call orientation%set('dfy',            ctfvars%dfy)
        call orientation%set('angast',         ctfvars%angast)
        call orientation%set('phshift',        ctfvars%phshift)
        call orientation%set('ctf_estimatecc', ctffit%get_ccfit())
        call orientation%set('ctfscore',       ctfscore)
        call orientation%set('ctfres',         ctffit%get_ctfres())
        call orientation%set('ctfjpg',         rel_fname)
        ! clean
        call ctffit%kill
    end subroutine iterate

    subroutine kill( self )
        class(ctf_estimate_iter), intent(inout) :: self
        call self%micrograph%kill
        call self%pspec%kill
        call self%thumbnail%kill
        call self%img_jpg%kill
        call self%pspec4viz%kill
    end subroutine kill

end module simple_ctf_estimate_iter

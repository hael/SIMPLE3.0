!------------------------------------------------------------------------------!
! SIMPLE v3.0         Elmlund & Elmlund Lab          simplecryoem.com          !
!------------------------------------------------------------------------------!
!> Simple commander module: mask interface
!
!! This class contains the set of concrete mask commanders of the SIMPLE
!! library. This class provides the glue between the reciver (main reciever is
!! simple_exec program) and the abstract action, which is simply execute
!! (defined by the base class: simple_commander_base). Later we can use the
!! composite pattern to create MacroCommanders (or workflows)
!
! The code is distributed with the hope that it will be useful, but _WITHOUT_ _ANY_ _WARRANTY_.
! Redistribution and modification is regulated by the GNU General Public License.
! *Authors:* Cyril Reboul & Hans Elmlund 2016
!
module simple_commander_mask
use simple_defs
use simple_cmdline,        only: cmdline
use simple_params,         only: params
use simple_build,          only: build
use simple_commander_base, only: commander_base
use simple_filehandling    ! use all in there
use simple_jiffys          ! use all in there
implicit none

public :: mask_commander
public :: automask2D_commander
private

type, extends(commander_base) :: mask_commander
 contains
   procedure :: execute      => exec_mask
end type mask_commander
type, extends(commander_base) :: automask2D_commander
  contains
    procedure :: execute      => exec_automask2D
end type automask2D_commander

contains

    !> mask is a program for masking images and volumes.
    !! If you want to mask your images with a spherical mask with a soft
    !! falloff, set msk to the radius in pixels
    subroutine exec_mask( self, cline )
        use simple_image,       only: image
        use simple_procimgfile, only: mask_imgfile
        class(mask_commander), intent(inout) :: self
        class(cmdline),        intent(inout) :: cline
        type(build)                :: b
        type(params)               :: p
        type(automask2D_commander) :: automask2D
        type(image)                :: mskvol
        logical                    :: here
        integer                    :: ldim(3)
        p = params(cline)                   ! parameters generated
        p%boxmatch = p%box                  ! turns off boxmatch logics
        call b%build_general_tbox(p, cline) ! general objects built
        if( cline%defined('stk') .and. cline%defined('vol1') )stop 'Cannot operate on images AND volume at once'
        if( p%automsk.eq.'yes' .and..not.cline%defined('mw')  )stop 'Missing mw argument for automasking'
        if( p%msktype.ne.'soft' .and. p%msktype.ne.'hard' .and. p%msktype.ne.'cavg' )stop 'Invalid mask type'
        call b%vol%new([p%box,p%box,p%box], p%smpd) ! reallocate vol (boxmatch issue)
        if( cline%defined('stk') )then
            ! 2D
            if( p%automsk.eq.'yes' )then
                ! auto
                if( .not. cline%defined('amsklp') )call cline%set('amsklp', 25.)
                if( .not. cline%defined('edge')   )call cline%set('edge', 20.)
                call exec_automask2D( automask2D, cline )
            else if( cline%defined('msk') .or. cline%defined('inner') )then
                ! spherical
                if( cline%defined('inner') )then
                    if( cline%defined('width') )then
                        call mask_imgfile(p%stk, p%outstk, p%msk, p%smpd, inner=p%inner, width=p%width, which=p%msktype)
                    else
                        call mask_imgfile(p%stk, p%outstk, p%msk, p%smpd, inner=p%inner, which=p%msktype)
                    endif
                else
                    call mask_imgfile(p%stk, p%outstk, p%msk, p%smpd, which=p%msktype)
                endif
            else
                stop 'Nothing to do!'
            endif
        else if( cline%defined('vol1') )then
            ! 3D
            here = .false.
            inquire(FILE=p%vols(1), EXIST=here)
            if( .not.here )stop 'Cannot find input volume'
            call b%vol%read(p%vols(1))
            if( cline%defined('mskfile') )then
                ! from file
                here = .false.
                inquire(FILE=p%mskfile, EXIST=here)
                if( .not. here ) stop 'Cannot find input mskfile'
                ldim = b%vol%get_ldim()
                call mskvol%new(ldim, p%smpd)
                call mskvol%read(p%mskfile)
                call b%vol%mul(mskvol)
                if( p%outvol .ne. '' )call b%vol%write(p%outvol, del_if_exists=.true.)
            else if( p%automsk.eq.'yes' )then
                stop '3D automasking now deferred to program: postproc_vol'
            else if( cline%defined('msk') )then
                ! spherical
                if( cline%defined('inner') )then
                    if( cline%defined('width') )then
                        call b%vol%mask(p%msk, p%msktype, inner=p%inner, width=p%width)
                    else
                        call b%vol%mask(p%msk, p%msktype, inner=p%inner)
                    endif
                else
                    call b%vol%mask(p%msk, p%msktype)
                endif
                if( p%outvol .ne. '' )call b%vol%write(p%outvol, del_if_exists=.true.)
            else
                stop 'Nothing to do!'
            endif
        else
            stop 'No input images(s) or volume provided'
        endif
        ! end gracefully
        call simple_end('**** SIMPLE_MASK NORMAL STOP ****')
    end subroutine exec_mask
    
    !> automask2D is a program for solvent flattening of class averages.
    !! The algorithm for backgro und removal is based on low-pass filtering and
    !! binarization. First, the class averages are low-pass filtered to amsklp.
    !! Binary representatives are then generate d by assigning foreground pixels
    !! using sortmeans. A cosine function softens the edge of the binary mask
    !! before it is multiplied with the unmasked input average
    subroutine exec_automask2D( self, cline )
        !use simple_masker, only: automask2D
        class(automask2D_commander), intent(inout) :: self
        class(cmdline),              intent(inout) :: cline
        type(params) :: p
        type(build)  :: b
        integer      :: iptcl
        p = params(cline)                   ! parameters generated
        p%boxmatch = p%box                  ! turns off boxmatch logics
        call b%build_general_tbox(p, cline) ! general objects built
        write(*,'(A,F8.2,A)') '>>> AUTOMASK LOW-PASS:',        p%amsklp, ' ANGSTROMS'
        write(*,'(A,I3,A)')   '>>> AUTOMASK SOFT EDGE WIDTH:', p%edge,   ' PIXELS'
        p%outstk = add2fbody(p%stk, p%ext, 'msk')
        call b%mskimg%init2D(p, p%nptcls)
        do iptcl=1,p%nptcls
            call b%img%read(p%stk, iptcl)
            call b%mskimg%apply_2Denvmask22Dref(b%img, iptcl)
            call b%img%write(p%outstk, iptcl)
        end do
        ! end gracefully
        call simple_end('**** SIMPLE_AUTOMASK2D NORMAL STOP ****')
    end subroutine exec_automask2D

end module simple_commander_mask

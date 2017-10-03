! common PRIME2D/PRIME3D routines used primarily by the Hadamard matchers
module simple_hadamard_common
#include "simple_lib.f08"
use simple_image,    only: image
use simple_cmdline,  only: cmdline
use simple_build,    only: build
use simple_params,   only: params
use simple_ori,      only: ori
use simple_oris,     only: oris
use simple_gridding, only: prep4cgrid
implicit none

public :: read_img_from_stk, set_bp_range, set_bp_range2D, grid_ptcl, prepimg4align,&
&eonorm_struct_facts, norm_struct_facts, preprefvol, prep2Dref, gen2Dclassdoc,&
&preprecvols, killrecvols, gen_projection_frcs
private
#include "simple_local_flags.inc"

real, parameter :: SHTHRESH  = 0.0001
real, parameter :: CENTHRESH = 0.5    ! threshold for performing volume/cavg centering in pixels
    
contains

    subroutine read_img_from_stk( b, p, iptcl )
        class(build),  intent(inout)  :: b
        class(params), intent(inout)  :: p
        integer,       intent(in)     :: iptcl
        character(len=:), allocatable :: stkname
        integer :: ind
        if( p%l_stktab_input )then
            call p%stkhandle%get_stkname_and_ind(iptcl, stkname, ind)
            call b%img%read(stkname, ind)
        else
            if( p%l_distr_exec )then
                call b%img%read(p%stk_part, iptcl - p%fromp + 1)
            else
                call b%img%read(p%stk, iptcl)
            endif
        endif
        call b%img%norm
    end subroutine read_img_from_stk

    subroutine set_bp_range( b, p, cline )
        use simple_math, only: calc_fourier_index
        class(build),   intent(inout) :: b
        class(params),  intent(inout) :: p
        class(cmdline), intent(inout) :: cline
        real, allocatable     :: resarr(:), tmp_arr(:)
        real                  :: fsc0143, fsc05, mapres(p%nstates)
        integer               :: s, loc(1), lp_ind
        character(len=STDLEN) :: fsc_fname
        logical               :: fsc_bin_exists(p%nstates), all_fsc_bin_exist
        select case(p%eo)
            case('yes','aniso')
                ! check all fsc_state*.bin exist
                all_fsc_bin_exist = .true.
                fsc_bin_exists    = .false.
                do s=1,p%nstates
                    fsc_fname = 'fsc_state'//int2str_pad(s,2)//'.bin'
                    if( file_exists(trim(adjustl(fsc_fname))) )fsc_bin_exists( s ) = .true.
                    if( b%a%get_pop(s, 'state') > 0 .and. .not.fsc_bin_exists(s))&
                        & all_fsc_bin_exist = .false.
                enddo
                if( p%oritab .eq. '' )all_fsc_bin_exist = (count(fsc_bin_exists)==p%nstates)
                ! set low-pass Fourier index limit
                if( all_fsc_bin_exist )then
                    ! we need the worst resolved fsc
                    resarr = b%img%get_res()
                    do s=1,p%nstates
                        if( fsc_bin_exists(s) )then
                            ! these are the 'classical' resolution measures
                            fsc_fname   = 'fsc_state'//int2str_pad(s,2)//'.bin'
                            tmp_arr     = file2rarr(trim(adjustl(fsc_fname)))
                            b%fsc(s,:)  = tmp_arr(:)
                            deallocate(tmp_arr)
                            call get_resolution(b%fsc(s,:), resarr, fsc05, fsc0143)
                            mapres(s)   = fsc0143
                        else
                            ! empty state
                            mapres(s)   = 0.
                            b%fsc(s,:)  = 0.
                        endif
                    end do
                    loc    = maxloc(mapres)
                    lp_ind = get_lplim(b%fsc(loc(1),:))
                    p%kfromto(2) = calc_fourier_index( resarr(lp_ind), p%boxmatch, p%smpd )
                    if( p%kfromto(2) == 1 )then
                        stop 'simple_math::get_lplim gives nonsensical result (==1)'
                    endif
                    DebugPrint ' extracted FSC info'
                else if( cline%defined('lp') )then
                    p%kfromto(2) = calc_fourier_index( p%lp, p%boxmatch, p%smpd )
                else if( cline%defined('find') )then
                    p%kfromto(2) = min(p%find,p%tofny)
                else if( b%a%isthere(p%fromp,'lp') )then
                    p%kfromto(2) = calc_fourier_index( b%a%get(p%fromp,'lp'), p%boxmatch, p%smpd )
                else
                    write(*,*) 'no method available for setting the low-pass limit'
                    stop 'need fsc file, lp, or find; set_bp_range; simple_hadamard_common'
                endif
                if( p%kfromto(2)-p%kfromto(1) <= 2 )then
                    write(*,*) 'fromto:', p%kfromto(1), p%kfromto(2)
                    stop 'resolution range too narrow; set_bp_range; simple_hadamard_common'
                endif
                ! lpstop overrides any other method for setting the low-pass limit
                if( cline%defined('lpstop') )then
                    p%kfromto(2) = min(p%kfromto(2), calc_fourier_index( p%lpstop, p%boxmatch, p%smpd ))
                endif
                ! set high-pass Fourier index limit
                p%kfromto(1) = max(2,calc_fourier_index( p%hp, p%boxmatch, p%smpd ))
                ! re-set the low-pass limit
                p%lp = calc_lowpass_lim( p%kfromto(2), p%boxmatch, p%smpd )
                p%lp_dyn = p%lp
                call b%a%set_all2single('lp',p%lp)
            case('no')
                ! set Fourier index range
                p%kfromto(1) = max(2, calc_fourier_index( p%hp, p%boxmatch, p%smpd ))
                if( cline%defined('lpstop') )then
                    p%kfromto(2) = min(calc_fourier_index(p%lp, p%boxmatch, p%smpd),&
                    &calc_fourier_index(p%lpstop, p%boxmatch, p%smpd))
                else
                    p%kfromto(2) = calc_fourier_index(p%lp, p%boxmatch, p%smpd)
                endif
                p%lp_dyn = p%lp
                call b%a%set_all2single('lp',p%lp)
            case DEFAULT
                stop 'Unsupported eo flag; simple_hadamard_common'
        end select
        ! set highest Fourier index for coarse grid search
        p%kstop_grid = calc_fourier_index(p%lp_grid, p%boxmatch, p%smpd)
        if( p%kstop_grid > p%kfromto(2) ) p%kstop_grid = p%kfromto(2)
        DebugPrint '*** simple_hadamard_common ***: did set Fourier index range'
    end subroutine set_bp_range

    subroutine set_bp_range2D( b, p, cline, which_iter, frac_srch_space )
        use simple_estimate_ssnr, only: fsc2ssnr
        class(build),   intent(inout) :: b
        class(params),  intent(inout) :: p
        class(cmdline), intent(inout) :: cline
        integer,        intent(in)    :: which_iter
        real,           intent(in)    :: frac_srch_space
        real :: lplim
        p%kfromto(1) = max(2, calc_fourier_index(p%hp, p%boxmatch, p%smpd))
        if( cline%defined('lp') )then
            p%kfromto(2) = calc_fourier_index(p%lp, p%boxmatch, p%smpd)
            p%lp_dyn     = p%lp
            call b%a%set_all2single('lp',p%lp)
        else
            if( which_iter <= LPLIM1ITERBOUND )then
                lplim = p%lplims2D(1)
            else if( frac_srch_space >= FRAC_SH_LIM .and. which_iter > LPLIM3ITERBOUND )then
                lplim = p%lplims2D(3)
            else
                lplim = p%lplims2D(2)
            endif
            p%kfromto(2) = calc_fourier_index(lplim, p%boxmatch, p%smpd)
            p%lp_dyn = lplim
            call b%a%set_all2single('lp',lplim)
        endif
        DebugPrint  '*** simple_hadamard_common ***: did set Fourier index range'
    end subroutine set_bp_range2D

    !>  \brief  grids one particle image to the volume
    subroutine grid_ptcl( b, p, orientation, os )
        use simple_kbinterpol, only: kbinterpol
        class(build),          intent(inout) :: b
        class(params),         intent(inout) :: p
        class(ori),            intent(inout) :: orientation
        class(oris), optional, intent(inout) :: os
        type(ori)        :: orisoft, o_sym
        type(kbinterpol) :: kbwin
        real             :: pw, w, eopart
        integer          :: jpeak, s, k, npeaks
        logical          :: l_softrec
        if( p%eo .ne. 'no' )then
            kbwin = b%eorecvols(1)%get_kbwin()
        else
            kbwin = b%recvols(1)%get_kbwin()
        endif
        l_softrec = .false.
        npeaks    = 1
        if( present(os) )then
            l_softrec = .true.
            npeaks    = os%get_noris()
        endif
        pw = 1.0
        if( orientation%isthere('w') ) pw = orientation%get('w')
        if( pw > TINY )then
            ! pre-gridding correction for the kernel convolution
            call prep4cgrid(b%img, b%img_pad, p%msk, kbwin)
            DebugPrint  '*** simple_hadamard_common ***: prepared image for gridding'
            if( p%eo .ne. 'no' )then
                ! even/odd partitioning
                eopart = ran3()
                if( orientation%isthere('eo') )then
                    if( orientation%isevenodd() )eopart = orientation%get('eo')
                endif
            endif
            ! weighted interpolation
            orisoft = orientation
            do jpeak=1,npeaks
                DebugPrint  '*** simple_hadamard_common ***: gridding, iteration:', jpeak
                ! get ori info
                if( l_softrec )then
                    orisoft = os%get_ori(jpeak)
                    w = orisoft%get('ow')
                else
                    w = 1.
                endif
                s = nint(orisoft%get('state'))
                DebugPrint  '*** simple_hadamard_common ***: got orientation'
                if( p%frac < 0.99 ) w = w*pw
                if( w > TINY )then
                    if( p%pgrp == 'c1' )then
                        if( p%eo .ne. 'no' )then
                            call b%eorecvols(s)%grid_fplane(orisoft, b%img_pad, pwght=w, ran=eopart)
                        else
                            call b%recvols(s)%inout_fplane(orisoft, .true., b%img_pad, pwght=w)
                        endif
                    else
                        do k=1,b%se%get_nsym()
                            o_sym = b%se%apply(orisoft, k)
                            if( p%eo .ne. 'no' )then
                                call b%eorecvols(s)%grid_fplane(o_sym, b%img_pad, pwght=w, ran=eopart)
                            else
                                call b%recvols(s)%inout_fplane(o_sym, .true., b%img_pad, pwght=w)
                            endif
                        end do
                    endif
                endif
                DebugPrint  '*** simple_hadamard_common ***: gridded ptcl'
            end do
        endif
    end subroutine grid_ptcl

    !>  \brief  prepares one particle image for alignment
    subroutine prepimg4align( b, p, o, is3D )
        use simple_estimate_ssnr, only: fsc2optlp
        use simple_ctf,           only: ctf
        class(build),  intent(inout) :: b
        class(params), intent(inout) :: p
        type(ori),     intent(inout) :: o
        logical,       intent(in)    :: is3D
        real, allocatable :: filter(:), frc(:)
        type(ctf)         :: tfun
        real              :: x, y, dfx, dfy, angast
        integer           :: cls, frcind
        x      = o%get('x')
        y      = o%get('y')
        cls    = nint(o%get('class'))
        frcind = 0 
        if( is3D )then
            if( p%nspace /= NSPACE_BALANCE )then
                frcind = b%e_bal%find_closest_proj(o)
            else
                frcind = nint(o%get('proj'))
            endif
        endif
        ! move to Fourier space
        call b%img%fwd_ft
        ! set CTF parameters
        if( p%ctf .ne. 'no' )then
            ! we here need to re-create the CTF object as kV/cs/fraca are now per-particle params
            ! that these parameters are part of the doc is checked in the params class
            tfun = ctf(p%smpd, o%get('kv'), o%get('cs'), o%get('fraca'))
            select case(p%tfplan%mode)
                case('astig') ! astigmatic CTF
                    dfx    = o%get('dfx')
                    dfy    = o%get('dfy')
                    angast = o%get('angast')
                case('noastig') ! non-astigmatic CTF
                    dfx    = o%get('dfx')
                    dfy    = dfx
                    angast = 0.
                case DEFAULT
                    write(*,*) 'Unsupported p%tfplan%mode: ', trim(p%tfplan%mode)
                    stop 'simple_hadamard_common :: prepimg4align'
            end select
        endif
        ! deal with CTF
        select case(p%ctf)
            case('mul')  ! images have been multiplied with the CTF, no CTF-dependent weighting of the correlations
                stop 'ctf=mul is not supported; simple_hadamard_common :: prepimg4align'
            case('no')   ! do nothing
            case('yes')  ! do nothing
            case('flip') ! flip back
                call tfun%apply(b%img, dfx, 'flip', dfy, angast)
            case DEFAULT
                stop 'Unsupported ctf mode; simple_hadamard_common :: prepimg4align'
        end select
        ! shift image to rotational origin
        if(abs(x) > SHTHRESH .or. abs(y) > SHTHRESH) call b%img%shift([-x,-y,0.])
        if( is3D .and. frcind > 0 )then
            ! anisotropic matched filter
            frc = b%projfrcs%get_frc(frcind, p%box)
            if( any(frc > 0.143) )then
                filter = fsc2optlp(frc)
                call b%img%shellnorm()
                call b%img%apply_filter(filter)
            endif
        endif
        ! back to real-space
        call b%img%bwd_ft
        ! clip image if needed
        call b%img%clip(b%img_match) ! SQUARE DIMS ASSUMED
        ! MASKING
        ! soft-edged mask
        if( p%l_innermsk )then
            call b%img_match%mask(p%msk, 'soft', inner=p%inner, width=p%width)
        else
            call b%img_match%mask(p%msk, 'soft')
        endif
        ! return in Fourier space
        call b%img_match%fwd_ft
        DebugPrint  '*** simple_hadamard_common ***: finished prepimg4align'
    end subroutine prepimg4align

    !>  \brief  prepares one cluster centre image for alignment
    subroutine prep2Dref( b, p, icls, center )
        use simple_estimate_ssnr, only: fsc2optlp
        class(build),      intent(inout) :: b
        class(params),     intent(in)    :: p
        integer,           intent(in)    :: icls
        logical, optional, intent(in)    :: center
        real, allocatable :: filter(:), frc(:), res(:)
        real    :: xyz(3), sharg, frc05, frc0143
        logical :: do_center
        ! normalise
        call b%img%norm
        do_center = (p%center .eq. 'yes')
        ! centering only performed if p%center.eq.'yes'
        if( present(center) ) do_center = do_center .and. center
        if( do_center )then
            ! typically you'd want to center the class averages
            ! even though they're not good enough to search shifts
            xyz   = b%img%center(p%cenlp, 'no', p%msk, doshift=.false.)
            sharg = arg(xyz)
            if( sharg > CENTHRESH )then
                ! apply shift and update the corresponding class parameters
                call b%img%fwd_ft
                call b%img%shift(xyz(1), xyz(2))
                call b%a%add_shift2class(icls, -xyz(1:2))
            endif
        endif
        if( p%l_match_filt )then
            ! anisotropic matched filter
            frc = b%projfrcs%get_frc(icls, p%box)
            if( any(frc > 0.143) )then
                call b%img%fwd_ft ! needs to be here in case the shift was never applied (above)
                filter = fsc2optlp(frc)
                call b%img%shellnorm()
                call b%img%apply_filter(filter)
            endif
        endif
        ! ensure we are in real-space before clipping
        call b%img%bwd_ft
        ! clip image if needed
        call b%img%clip(b%img_match)
        ! apply mask
        if( p%l_envmsk .and. p%automsk .eq. 'cavg' )then
            ! automasking
            call b%mskimg%apply_2Denvmask22Dref(b%img_match)
            if( p%l_chunk_distr )then
                call b%img_match%write(trim(p%chunktag)//'automasked_refs'//p%ext, icls)
            else if( (p%l_distr_exec .and. p%part.eq.1) .or. (.not. p%l_distr_exec) )then
                call b%img_match%write('automasked_refs'//p%ext, icls)
            endif
        else
            ! soft masking
            if( p%l_innermsk )then
                call b%img_match%mask(p%msk, 'soft', inner=p%inner, width=p%width)
            else
                call b%img_match%mask(p%msk, 'soft')
            endif
        endif
        ! move to Fourier space
        call b%img_match%fwd_ft
    end subroutine prep2Dref

    !>  \brief prepares a 2D class document with class index, resolution, 
    !!         poulation, average correlation and weight
    subroutine gen2Dclassdoc( b, p, fname )
        class(build),     intent(inout) :: b
        class(params),    intent(inout) :: p
        character(len=*), intent(in)    :: fname
        integer    :: icls, pop
        real       :: frc05, frc0143
        type(oris) :: classdoc
        call classdoc%new_clean(p%ncls)            
        do icls=1,p%ncls
            call b%projfrcs%estimate_res(icls, frc05, frc0143)
            call classdoc%set(icls, 'class', real(icls))
            pop = b%a%get_pop(icls, 'class')
            call classdoc%set(icls, 'pop',   real(pop))
            call classdoc%set(icls, 'res',   frc0143)
            if( pop > 1 )then
                call classdoc%set(icls, 'corr',  b%a%get_avg('corr', class=icls))
                call classdoc%set(icls, 'w',     b%a%get_avg('w',    class=icls))
            else
                call classdoc%set(icls, 'corr', -1.0)
                call classdoc%set(icls, 'w',     0.0)
            endif
            call classdoc%write(fname)
        end do
        call classdoc%kill
    end subroutine gen2Dclassdoc
            
    !>  \brief  initializes all volumes for reconstruction
    subroutine preprecvols( b, p )
        class(build),   intent(inout) :: b
        class(params),  intent(inout) :: p
        integer :: istate
        select case(p%eo)
            case('yes','aniso')
                do istate = 1, p%nstates
                    if( b%a%get_pop(istate, 'state') > 0)then
                        call b%eorecvols(istate)%new(p)
                        call b%eorecvols(istate)%reset_all
                    endif
                end do
            case DEFAULT
                do istate = 1, p%nstates
                    if( b%a%get_pop(istate, 'state') > 0)then
                        call b%recvols(istate)%new([p%boxpd, p%boxpd, p%boxpd], p%smpd)
                        call b%recvols(istate)%alloc_rho(p)
                        call b%recvols(istate)%reset
                    endif
                end do
        end select
    end subroutine preprecvols

    !>  \brief  destructs all volumes for reconstruction
    subroutine killrecvols( b, p )
        class(build),   intent(inout) :: b
        class(params),  intent(inout) :: p
        integer :: istate
        if( p%eo .ne. 'no' )then
            do istate = 1, p%nstates
                call b%eorecvols(istate)%kill
            end do
        else
            do istate = 1, p%nstates
                call b%recvols(istate)%dealloc_rho
                call b%recvols(istate)%kill
            end do
        endif
    end subroutine killrecvols

    !>  \brief  prepares one volume for references extraction
    subroutine preprefvol( b, p, cline, s, doexpand )
        use simple_estimate_ssnr, only: fsc2optlp
        class(build),      intent(inout) :: b
        class(params),     intent(inout) :: p
        class(cmdline),    intent(inout) :: cline
        integer,           intent(in)    :: s
        logical, optional, intent(in)    :: doexpand
        type(image)                   :: vol_filter
        real,             allocatable :: filter(:)
        character(len=:), allocatable :: fname_vol_filter
        logical                       :: l_doexpand, do_center
        real                          :: shvec(3)
        l_doexpand = .true.
        if( present(doexpand) ) l_doexpand = doexpand
        if( p%boxmatch < p%box )call b%vol%new([p%box,p%box,p%box],p%smpd) ! ensure correct dim
        call b%vol%read(p%vols(s))
        call b%vol%norm ! because auto-normalisation on read is taken out
        ! centering            
        do_center = .true.
        if( p%center .eq. 'no' .or. p%nstates > 1 .or. .not. p%doshift .or.&
        &p%pgrp(:1) .ne. 'c' .or. cline%defined('mskfile') ) do_center = .false.
        if( do_center )then
            shvec = b%vol%center(p%cenlp,'no',p%msk,doshift=.false.) ! find center of mass shift
            if( arg(shvec) > CENTHRESH )then
                call b%vol%fwd_ft
                if( p%pgrp .ne. 'c1' ) shvec(1:2) = 0.         ! shifts only along z-axis for C2 and above
                call b%vol%shift([shvec(1),shvec(2),shvec(3)]) ! performs shift
                ! map back to particle oritentations
                if( cline%defined('oritab') )call b%a%map3dshift22d(-shvec(:), state=s)
            endif
        endif
        ! Volume filtering
        if( p%eo.ne.'no' )then
            ! anisotropic matched filter
            allocate(fname_vol_filter, source='aniso_optlp_state'//int2str_pad(s,2)//p%ext)
            if( file_exists(fname_vol_filter) )then
                call vol_filter%new([p%box,p%box,p%box],p%smpd)
                call vol_filter%read(fname_vol_filter)
                call b%vol%fwd_ft ! needs to be here in case the shift was never applied (above)
                call b%vol%shellnorm()
                call b%vol%apply_filter(vol_filter)
                call vol_filter%kill
            else
                ! matched filter based on Rosenthal & Henderson, 2003 
                if( any(b%fsc(s,:) > 0.143) )then
                    call b%vol%fwd_ft ! needs to be here in case the shift was never applied (above)
                    call b%vol%shellnorm()
                    filter = fsc2optlp(b%fsc(s,:))
                    call b%vol%apply_filter(filter)
                endif
            endif
            deallocate(fname_vol_filter)
        endif
        ! back to real space
        call b%vol%bwd_ft
        ! clip
        if( p%boxmatch < p%box )then
            call b%vol%clip_inplace([p%boxmatch,p%boxmatch,p%boxmatch]) ! SQUARE DIMS ASSUMED
        endif
        ! masking
        if( cline%defined('mskfile') )then
            ! mask provided
            call b%mskvol%new([p%box, p%box, p%box], p%smpd)
            call b%mskvol%read(p%mskfile)
            call b%mskvol%clip_inplace([p%boxmatch,p%boxmatch,p%boxmatch])
            call b%vol%zero_background(p%msk)
            call b%vol%mul(b%mskvol)
        else
            ! circular masking
            if( p%l_innermsk )then
                call b%vol%mask(p%msk, 'soft', inner=p%inner, width=p%width)
            else
                call b%vol%mask(p%msk, 'soft')
            endif
        endif
        ! FT volume
        call b%vol%fwd_ft
        ! expand for fast interpolation
        if( l_doexpand ) call b%vol%expand_cmat     
    end subroutine preprefvol

    subroutine norm_struct_facts( b, p, which_iter )
        class(build),      intent(inout) :: b
        class(params),     intent(inout) :: p
        integer, optional, intent(in)    :: which_iter
        integer :: s
        character(len=:), allocatable :: fbody
        character(len=STDLEN) :: pprocvol
        do s=1,p%nstates
            if( b%a%get_pop(s, 'state') == 0 )then
                ! empty space
                cycle
            endif
            if( p%l_distr_exec )then
                allocate(fbody, source='recvol_state'//int2str_pad(s,2)//'_part'//int2str_pad(p%part,p%numlen))
                p%vols(s)  = trim(adjustl(fbody))//p%ext
                call b%recvols(s)%compress_exp
                call b%recvols(s)%write(p%vols(s), del_if_exists=.true.)
                call b%recvols(s)%write_rho('rho_'//trim(adjustl(fbody))//p%ext)
                deallocate(fbody)
            else
                if( p%refine .eq. 'snhc' )then
                     p%vols(s) = trim(SNHCVOL)//int2str_pad(s,2)//p%ext
                else
                    if( present(which_iter) )then
                        p%vols(s) = 'recvol_state'//int2str_pad(s,2)//'_iter'//int2str_pad(which_iter,3)//p%ext
                    else
                        p%vols(s) = 'startvol_state'//int2str_pad(s,2)//p%ext
                    endif
                endif
                call b%recvols(s)%compress_exp
                call b%recvols(s)%sampl_dens_correct
                call b%recvols(s)%bwd_ft
                call b%recvols(s)%clip(b%vol)
                call b%vol%write(p%vols(s), del_if_exists=.true.)
                if( present(which_iter) )then
                    ! post-process volume
                    pprocvol = add2fbody(trim(p%vols(s)), p%ext, 'pproc')
                    call b%vol%fwd_ft
                    ! low-pass filter
                    call b%vol%bp(0., p%lp)
                    call b%vol%bwd_ft
                    ! mask
                    call b%vol%mask(p%msk, 'soft')
                    call b%vol%write(pprocvol)
                endif
            endif
        end do
    end subroutine norm_struct_facts
    
    subroutine eonorm_struct_facts( b, p, res, which_iter )
        use simple_filterer, only: gen_anisotropic_optlp
        class(build),      intent(inout) :: b
        class(params),     intent(inout) :: p
        real,              intent(inout) :: res
        integer, optional, intent(in)    :: which_iter
        real,     allocatable :: invctfsq(:)
        integer               :: s
        real                  :: res05s(p%nstates), res0143s(p%nstates)
        character(len=STDLEN) :: pprocvol
        character(len=32)     :: eonames(2)
        ! init
        res0143s = 0.
        res05s   = 0.
        ! cycle through states
        do s=1,p%nstates
            if( b%a%get_pop(s, 'state') == 0 )then
                ! empty state
                if( present(which_iter) )b%fsc(s,:) = 0.
                cycle
            endif
            call b%eorecvols(s)%compress_exp
            if( p%l_distr_exec )then
                call b%eorecvols(s)%write_eos('recvol_state'//int2str_pad(s,2)//'_part'//int2str_pad(p%part,p%numlen))
            else
                if( present(which_iter) )then
                    p%vols(s) = 'recvol_state'//int2str_pad(s,2)//'_iter'//int2str_pad(which_iter,3)//p%ext
                else
                    p%vols(s) = 'startvol_state'//int2str_pad(s,2)//p%ext
                endif
                call b%eorecvols(s)%sum_eos
                eonames(1) = add2fbody(p%vols(s), p%ext, '_odd')
                eonames(2) = add2fbody(p%vols(s),  p%ext, '_even')
                ! anisotropic resolution model
                call b%eorecvols(s)%sampl_dens_correct_eos(s, eonames)
                call gen_projection_frcs( p, eonames(1), eonames(2), s, b%projfrcs)
                call b%projfrcs%write('frcs_state'//int2str_pad(s,2)//'.bin')
                ! generate the anisotropic 3D optimal low-pass filter
                call gen_anisotropic_optlp(b%vol, b%projfrcs, b%e_bal, s, p%pgrp)
                call b%vol%write('aniso_optlp_state'//int2str_pad(s,2)//p%ext)
                call b%eorecvols(s)%sampl_dens_correct_sum(b%vol)
                call b%vol%write(p%vols(s), del_if_exists=.true.)
                ! update resolutions for local execution mode
                call b%eorecvols(s)%get_res(res05s(s), res0143s(s))
                if( present(which_iter) )then
                    ! post-process volume
                    pprocvol = add2fbody(trim(p%vols(s)), p%ext, 'pproc')
                    b%fsc(s,:) = file2rarr('fsc_state'//int2str_pad(s,2)//'.bin')
                    call b%vol%fwd_ft
                    ! low-pass filter
                    call b%vol%bp(0., p%lp)
                    call b%vol%bwd_ft
                    ! mask
                    call b%vol%mask(p%msk, 'soft')
                    call b%vol%write(pprocvol)
                endif
            endif
        end do
        if( .not. p%l_distr_exec )then
            ! set the resolution limit according to the worst resolved model
            res  = maxval(res0143s)
            p%lp = min(p%lp,max(p%lpstop,res))
        endif
    end subroutine eonorm_struct_facts

    !>  \brief generate projection FRCs from even/odd pairs
    subroutine gen_projection_frcs( p, ename, oname, state, projfrcs )
        use simple_params,          only: params
        use simple_oris,            only: oris
        use simple_projector_hlev,  only: projvol
        use simple_projection_frcs, only: projection_frcs
        class(params),          intent(inout) :: p
        character(len=*),       intent(in)    :: ename, oname
        integer,                intent(in)    :: state
        class(projection_frcs), intent(inout) :: projfrcs
        type(oris)               :: e_space
        type(image)              :: even, odd
        type(image), allocatable :: even_imgs(:), odd_imgs(:)
        real,        allocatable :: frc(:), res(:)
        integer :: iproj
        ! read even/odd pair
        call even%new([p%box,p%box,p%box], p%smpd)
        call odd%new([p%box,p%box,p%box], p%smpd)
        call even%read(ename)
        call odd%read(oname)
        ! create e_space
        call e_space%new(NSPACE_BALANCE)
        call e_space%spiral(p%nsym, p%eullims)
        ! generate even/odd projections
        even_imgs = projvol(even, e_space, p)
        odd_imgs  = projvol(odd, e_space, p)
        ! calculate FRCs and fill-in projfrcs object
        !$omp parallel do default(shared) private(iproj,res,frc) schedule(static) proc_bind(close)
        do iproj=1,NSPACE_BALANCE
            call even_imgs(iproj)%fwd_ft
            call odd_imgs(iproj)%fwd_ft
            call even_imgs(iproj)%fsc(odd_imgs(iproj), res, frc, serial=.true.)
            call projfrcs%set_frc(iproj, frc, state)
            call even_imgs(iproj)%kill
            call odd_imgs(iproj)%kill
        end do
        !$omp end parallel do
        deallocate(even_imgs, odd_imgs)
        call even%kill
        call odd%kill
        call e_space%kill
    end subroutine gen_projection_frcs

end module simple_hadamard_common

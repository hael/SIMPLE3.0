module simple_symsrcher
use simple_cmdline, only: cmdline
use simple_params,  only: params
use simple_build,   only: build
use simple_oris,    only: oris
use simple_ori,     only: ori
use simple_sym,     only: sym
use simple_jiffys,  only: alloc_err, find_ldim_nptcls
implicit none

public :: symsrch_master
private

type(ori)                     :: orientation
type(oris)                    :: subgrps_oris
type(sym)                     :: symobj
integer                       :: i, s, n_subgrps, bestind, iptcl, nptcls, lfoo(3)
character(len=3), allocatable :: subgrps(:)
real                          :: shvec(3)
character(len=32), parameter  :: SYMSHTAB = 'sym_3dshift.txt'

contains

    subroutine symsrch_master( cline, p, b, os )
        use simple_filehandling,   only: nlines
        use simple_projector_hlev, only: projvol
        class(cmdline), intent(inout) :: cline
        class(params),  intent(inout) :: p
        class(build),   intent(inout) :: b
        class(oris),    intent(out)   :: os
        type(oris) :: oshift
        type(ori)  :: o         
        ! center volume
        call b%vol%read(p%vols(1))
        shvec = b%vol%center(p%cenlp,'no',p%msk)
        if(p%l_distr_exec .and. p%part.eq.1)then
            ! writes shifts for distributed execution
            call oshift%new(1)
            call oshift%set(1,'x',shvec(1))
            call oshift%set(1,'y',shvec(2))
            call oshift%set(1,'z',shvec(3))
            call oshift%write(trim(SYMSHTAB))
            call oshift%kill
        endif
        ! main fork
        if( p%compare .eq. 'no' )then
            ! single symmetry search
            ! generate projections
            call b%vol%mask(p%msk, 'soft')
            b%ref_imgs(1,:) = projvol(b%vol, b%e, p)
            ! do the symmetry search
            call single_symsrch( b, p, orientation )
        else
            ! generate projections
            call b%vol%mask(p%msk, 'soft')
            b%ref_imgs(1,:) = projvol(b%vol, b%e, p)
            ! symmetry subgroup scan
            ! get subgroups
            subgrps      = b%se%get_all_subgrps()
            n_subgrps    = size(subgrps)
            subgrps_oris = oris(n_subgrps)
            ! loop over subgroups
            do i=1,n_subgrps
                symobj = sym( subgrps(i) )         ! current symmetry object
                call updates_tboxs( b, p, symobj ) ! updates symmetry variables in builder
                write(*,'(A,A3)') '>>> PERFORMING SYMMETRY SEARCH FOR POINT GROUP ', p%pgrp
                ! do the search
                call single_symsrch( b, p, orientation )
                call subgrps_oris%set_ori( i, orientation ) ! stashes result
                write(*,'(A)') '>>> '
            enddo
            ! aggregates correlations & probabilities
            call sym_probs( bestind )
            orientation = subgrps_oris%get_ori(bestind)
        endif
        if( p%l_distr_exec )then
            ! alles klar
        else ! we have 3D shifts to deal with
            ! rotate the orientations & transfer the 3d shifts to 2d
            shvec = -1.*shvec
            os    = oris(nlines(p%oritab))
            call os%read(p%oritab)
            if( cline%defined('state') )then
                do i=1,os%get_noris()
                    s = nint(os%get(i, 'state'))
                    if(s .ne. p%state)cycle
                    call os%map3dshift22d(i, shvec)
                    call os%rot(i,orientation)
                    o = os%get_ori(i)
                    call b%se%rot_to_asym(o)
                    call os%set_ori(i, o) 
                end do
            else
                call os%map3dshift22d( shvec ) 
                call os%rot(orientation)
                call b%se%rotall_to_asym(os)
            endif
        endif
    end subroutine symsrch_master

    !>  \brief  Updates general and common lines toolboxes with current symmetry
    subroutine updates_tboxs( b, p, so )
        use simple_comlin, only: comlin
        type(build)  :: b
        type(params) :: p
        type(sym)    :: so
        integer      :: i, k, alloc_stat
        ! Update general toolbox sym functionality
        p%pgrp    = so%get_pgrp()
        call b%se%new(p%pgrp)
        p%nsym    = b%se%get_nsym()
        p%eullims = b%se%srchrange()
        call b%a%new(p%nptcls)
        call b%a%spiral(p%nsym, p%eullims)
        call b%e%new(p%nspace)
        call b%e%spiral(p%nsym, p%eullims)
        ! Update common lines toolbox
        if( p%pgrp /= 'c1' )then
            call b%a%symmetrize(p%nsym)
            do i=1,size(b%imgs_sym)
                call b%imgs_sym(i)%kill
            enddo
            do k=1,p%nstates
                do i=1,p%nspace
                    call b%ref_imgs(k,i)%kill
                enddo
            enddo
            deallocate(b%imgs_sym, b%ref_imgs)
            allocate( b%imgs_sym(1:p%nsym*p%nptcls), b%ref_imgs(p%nstates,p%nspace), stat=alloc_stat )
            call alloc_err( 'build_update_tboxs; simple_symsrch, 1', alloc_stat )            
            do i=1,p%nptcls*p%nsym
                call b%imgs_sym(i)%new([p%box,p%box,1], p%smpd)
            end do 
            b%clins = comlin(b%a, b%imgs_sym, p%lp)
        endif
    end subroutine updates_tboxs
    
    !>  \brief does common lines symmetry search over one symmetry pointgroup
    subroutine single_symsrch( b, p, best_o)
        use simple_comlin_sym  ! use all in there
        type(build)  :: b
        type(params) :: p
        type(ori)    :: best_o
        integer      :: i, j, cnt
        ! expand over symmetry group
        cnt = 0
        do i=1,p%nptcls
            do j=1,p%nsym
                cnt = cnt+1
                b%imgs_sym(cnt) = b%ref_imgs(1,i)
                call b%imgs_sym(cnt)%fwd_ft
            end do
        end do
        ! search for the axis
        call comlin_sym_init(b, p)
        call comlin_sym_axis(p, best_o, 'sym', doprint=.true.)
    end subroutine single_symsrch

    !>  \brief does common lines symmetry search over one symmetry pointgroup
    subroutine single_symsrch_oldschool( b, p, best_o )
        use simple_comlin_symsrch, only: comlin_srch_symaxis ! use all in there
        type(build)  :: b
        type(params) :: p
        type(ori)    :: best_o
        integer      :: i, j, cnt
        ! expand over symmetry group
        cnt = 0
        do i=1,p%nptcls
            do j=1,p%nsym
                cnt = cnt+1
                b%imgs_sym(cnt) = b%ref_imgs(1,i)
                call b%imgs_sym(cnt)%fwd_ft
            end do
        end do
        ! search for the axis
        call comlin_srch_symaxis(b, best_o, .true.)
    end subroutine single_symsrch_oldschool
    
    !>  \brief  calculates probabilities and returns best axis index
    subroutine sym_probs( bestind )
        integer           :: bestind
        type(sym)         :: se, subse
        real, allocatable :: probs(:)
        character(len=3)  :: pgrp
        real              :: bestp
        integer           :: i, j, k, alloc_stat
        allocate( probs(n_subgrps), stat=alloc_stat)
        call alloc_err( 'sym_probs; simple_sym', alloc_stat )            
        probs = 0.
        do i=1,n_subgrps
            pgrp = subgrps(i)
            se = sym(pgrp)
            do j=1,se%get_nsubgrp()
                subse = se%get_subgrp(j)
                do k=1,n_subgrps
                    if( subse%get_pgrp().eq.subgrps(k) )then
                        probs(i) = probs(i)+subgrps_oris%get(k,'corr') 
                    endif
                enddo
            enddo
            probs(i) = probs(i)/real(se%get_nsubgrp())
        enddo
        probs   = probs/sum(probs) 
        bestp   = -1.
        bestind = 0
        do i=1,n_subgrps
            write(*,'(A,A3,A,F4.2)')'>>> PROBABILITY FOR POINT-GROUP ',&
            subgrps(i),': ',probs(i)
            if( probs(i).gt.bestp )then
                bestp   = probs(i)
                bestind = i
            endif
        enddo
        deallocate(probs)
    end subroutine sym_probs
    
end module simple_symsrcher
module simple_volpft_symsrch
include 'simple_lib.f08'
!$ use omp_lib
!$ use omp_lib_kinds
use simple_opt_spec,        only: opt_spec
use simple_volpft_corrcalc, only: volpft_corrcalc
use simple_optimizer,       only: optimizer
use simple_oris,            only: oris
use simple_ori,             only: ori, euler2m
use simple_sym,             only: sym
implicit none

public :: volpft_symsrch_init, volpft_srch4symaxis
private
#include "simple_local_flags.inc"

logical, parameter :: DEBUG_HERE = .false.
integer, parameter :: NPROJ      = 500
integer, parameter :: NBEST      = 20
integer, parameter :: ANGSTEP    = 7

type opt4openMP
    type(opt_spec)            :: ospec              !< optimizer specification object
    class(optimizer), pointer :: nlopt => null()    !< optimizer object
end type opt4openMP

type(opt4openMP), allocatable :: opt_symaxes(:)     !< parallel optimisation, symmetry axes
real,             allocatable :: sym_rmats(:,:,:)   !< symmetry operations rotation matrices
type(volpft_corrcalc)         :: vpftcc             !< corr calculator
type(ori)                     :: saxis_glob         !< best symaxis solution found so far
integer                       :: nrestarts = 3      !< simplex restarts (randomized bounds)
integer                       :: nsym      = 0      !< # symmetry ops
integer                       :: nspace    = 0      !< # complex vectors in vpftcc
integer                       :: kfromto(2)         !< Fourier index range

contains

    subroutine volpft_symsrch_init( vol, pgrp, hp, lp, nrestarts_in )
        use simple_projector,    only: projector
         use simple_opt_factory, only: opt_factory
        class(projector),  intent(in) :: vol
        character(len=*),  intent(in) :: pgrp
        real,              intent(in) :: hp, lp
        integer, optional, intent(in) :: nrestarts_in
        type(opt_factory) :: ofac
        type(ori)         :: o
        type(sym)         :: symobj
        integer :: isym, ithr
        real    :: lims(3,2)
        call volpft_symsrch_kill
        ! create the correlator
        call vpftcc%new(vol, hp, lp, KBALPHA)
        nspace  = vpftcc%get_nspace()
        kfromto = vpftcc%get_kfromto()
        if( DEBUG_HERE ) write(logfhandle,*) 'nspace : ', nspace
        if( DEBUG_HERE ) write(logfhandle,*) 'kfromto: ', kfromto
        ! create the symmetry object
        call symobj%new(pgrp)
        nsym = symobj%get_nsym()
        ! allocate
        allocate(sym_rmats(nsym,3,3), source=0.0)
        ! extract the rotation matrices for the symops
        do isym=1,nsym
            o = symobj%get_symori(isym)
            sym_rmats(isym,:,:) = o%get_mat()
        end do
        ! set nrestarts
        nrestarts = 3
        if( present(nrestarts_in) ) nrestarts = nrestarts_in
        ! make optimizer specs
        lims      = 0.
        lims(1,2) = 359.99
        lims(2,2) = 180.
        lims(3,2) = 359.99
        ! make parallel optimiser struct
        allocate(opt_symaxes(nthr_glob))
        do ithr=1,nthr_glob
            ! optimiser spec
            call opt_symaxes(ithr)%ospec%specify("simplex",ndim=3,limits=lims,nrestarts=nrestarts,maxits=30)
            ! point to costfun
            call opt_symaxes(ithr)%ospec%set_costfun(volpft_symsrch_costfun)
            ! generate optimizer object with the factory
            call ofac%new(opt_symaxes(ithr)%ospec, opt_symaxes(ithr)%nlopt)
        end do
        ! create global symaxis
        call saxis_glob%new
        if( DEBUG_HERE ) write(logfhandle,*) '***DEBUG_HERE(volpft_symsrch)***; volpft_symsrch_init, DONE'
    end subroutine volpft_symsrch_init

    subroutine volpft_srch4symaxis( symaxis_best, fromto )
        class(ori),        intent(out) :: symaxis_best
        integer, optional, intent(in)  :: fromto(2)
        real,    allocatable :: inpl_angs(:), rmats(:,:,:,:), corrs(:,:)
        integer, allocatable :: order(:)
        class(*), pointer    :: fun_self => null()
        type(ori)  :: symaxis
        type(oris) :: espace, cand_axes
        integer    :: ffromto(2), ntot, inpl, iproj, iproj_best
        integer    :: inpl_best, istop, ithr, iloc, n_inpls
        real       :: eul(3), corr_best, cost
        logical    :: distr_exec
        ! flag distributed/shmem exec & set range
        distr_exec = present(fromto)
        if( distr_exec )then
            ffromto = fromto
        else
            ffromto(1) = 1
            ffromto(2) = NPROJ
        endif
        if( ffromto(1) < 1 .or. ffromto(2) > NPROJ )then
           THROW_HARD('range out of bound; volpft_srch4symaxis')
        endif
        ntot = ffromto(2) - ffromto(1) + 1
        if( DEBUG_HERE ) write(logfhandle,*) 'ffromto: ', ffromto
        if( DEBUG_HERE ) write(logfhandle,*) 'ntot   : ', ntot
        ! create
        ! container for candidate symmetry axes
        call cand_axes%new(NPROJ)
        call cand_axes%set_all2single('corr', -1.0) ! for later ordering
        ! projection directions in discrete search
        call espace%new(NPROJ)
        call espace%spiral
        ! count # in-plane angles
        n_inpls = 0
        do inpl=0,359,ANGSTEP
            n_inpls = n_inpls + 1
        end do
        ! allocate
        allocate(inpl_angs(n_inpls), rmats(ffromto(1):ffromto(2),n_inpls,3,3),&
            &corrs(ffromto(1):ffromto(2),n_inpls))
        ! fill-in the in-plane angles
        n_inpls = 0
        do inpl=0,359,ANGSTEP
            n_inpls = n_inpls + 1
            inpl_angs(n_inpls) = real(inpl)
        end do
        ! fill-in the rotation matrices
        do iproj=ffromto(1),ffromto(2)
            eul = espace%get_euler(iproj)
            do inpl=1,n_inpls
                eul(3) = inpl_angs(inpl)
                rmats(iproj,inpl,:,:) = euler2m(eul)
            end do
        end do
        ! grid search using the spiral geometry & ANGSTEP degree in-plane resolution
        corrs  = -1.
        !$omp parallel do schedule(static) default(shared) private(iproj,inpl) proc_bind(close) collapse(2)
        do iproj=ffromto(1),ffromto(2)
            do inpl=1,n_inpls
                corrs(iproj,inpl) = volpft_symsrch_scorefun(rmats(iproj,inpl,:,:))
            end do
        end do
        !$omp end parallel do
        if( DEBUG_HERE ) write(logfhandle,*) '***DEBUG_HERE(volpft_symsrch)***; grid search, DONE'
        ! identify the best candidates (serial code)
        do iproj=ffromto(1),ffromto(2)
            corr_best  = -1.0
            iproj_best = 0
            inpl_best  = 0
            do inpl=1,n_inpls
                if( corrs(iproj,inpl) > corr_best )then
                    corr_best  = corrs(iproj,inpl)
                    iproj_best = iproj
                    inpl_best  = inpl
                endif
            end do
            symaxis = espace%get_ori(iproj_best)
            call symaxis%e3set(inpl_angs(inpl_best))
            call symaxis%set('corr', corr_best)
            call cand_axes%set_ori(iproj,symaxis)
        end do
        if( DEBUG_HERE ) write(logfhandle,*) '***DEBUG_HERE(volpft_symsrch)***; identify the best candidates, DONE'
        ! refine local optima
        ! order the local optima according to correlation
        order = cand_axes%order_corr()
        ! determine end of range
        istop = min(ffromto(2) - ffromto(1) + 1,NBEST)
        !$omp parallel do schedule(static) default(shared) private(iloc,ithr,cost) proc_bind(close)
        do iloc=1,istop
            ithr = omp_get_thread_num() + 1
            opt_symaxes(ithr)%ospec%x = cand_axes%get_euler(order(iloc))
            call opt_symaxes(ithr)%nlopt%minimize(opt_symaxes(ithr)%ospec, fun_self, cost)
            call cand_axes%set_euler(order(iloc), opt_symaxes(ithr)%ospec%x)
            call cand_axes%set(order(iloc), 'corr', -cost)
        end do
        !$omp end parallel do
        ! order the local optima according to correlation
        order = cand_axes%order_corr()
        ! update global symaxis
        saxis_glob = cand_axes%get_ori(order(1))
        ! return best
        symaxis_best = cand_axes%get_ori(order(1))
    end subroutine volpft_srch4symaxis

    function volpft_symsrch_costfun( fun_self, vec, D ) result( cost )
        class(*), intent(inout) :: fun_self
        integer,  intent(in)    :: D
        real,     intent(in)    :: vec(D)
        real :: cost, rmat(3,3)
        rmat = euler2m(vec(1:3))
        cost = -volpft_symsrch_scorefun(rmat)
    end function volpft_symsrch_costfun

    function volpft_symsrch_scorefun( rmat_symaxis ) result( cc )
        real, intent(in) :: rmat_symaxis(3,3)
        real    :: cc, rmat(3,3)
        integer :: isym
        cc = 0.
        do isym=1,nsym
            ! extracts Fourier component distribution @ symaxis @ symop isym
            ! ROTATION MATRICES DO NOT COMMUTE
            ! this is the correct order
            rmat = matmul(sym_rmats(isym,:,:), rmat_symaxis)
            cc = cc + vpftcc%corr(rmat)
        end do
        cc = cc / real(nsym)
    end function volpft_symsrch_scorefun

    subroutine volpft_symsrch_kill
        integer :: ithr
        if( allocated(sym_rmats)   ) deallocate(sym_rmats)
        if( allocated(opt_symaxes) )then
            do ithr=1,size(opt_symaxes)
                call opt_symaxes(ithr)%ospec%kill
                if( associated(opt_symaxes(ithr)%nlopt) )then
                    call opt_symaxes(ithr)%nlopt%kill
                    nullify(opt_symaxes(ithr)%nlopt)
                endif
            end do
            deallocate(opt_symaxes)
        endif
        call vpftcc%kill
        call saxis_glob%kill
    end subroutine volpft_symsrch_kill

end module simple_volpft_symsrch

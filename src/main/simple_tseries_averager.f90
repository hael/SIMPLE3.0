module simple_tseries_averager
include 'simple_lib.f08'
use simple_parameters, only: params_glob
use simple_image,      only: image
implicit none

public :: init_tseries_averager, tseries_average, kill_tseries_averager
private
#include "simple_local_flags.inc"

logical, parameter :: DEBUG_HERE = .true.
integer, parameter :: MAXITS = 5

type(image), allocatable :: ptcl_imgs(:)        ! all particles in the time-series
type(image)              :: ptcl_avg            ! average over time window
type(stats_struct)       :: cstats              ! correlation statistics
type(stats_struct)       :: wstats              ! weight statistics
logical,     allocatable :: corr_mask(:,:,:)    ! logical mask for corr calc
real,        allocatable :: corrs(:)            ! correlations to weighted average over time window
real,        allocatable :: rmat_sum(:,:,:)     ! for OpenMP reduction
integer                  :: ldim(3)             ! logical dimension of 2D image
integer                  :: nz = 0              ! size of time window
logical                  :: existence = .false. ! to flag existence

contains

    subroutine init_tseries_averager
        integer     :: i, fromto(2)
        type(image) :: img_tmp
        ! first, kill pre-existing
        call kill_tseries_averager
        ! create image objects & arrays
        fromto(1) = 1 - params_glob%nframesgrp/2
        fromto(2) = 1 + params_glob%nframesgrp/2 - 1
        nz        = fromto(2) - fromto(1) + 1
        if( .not. is_even(nz) ) THROW_HARD('Z-dim: '//int2str(nz)//' of time window volume must be even, please change nframesgrp; init_tseries_averager')
        allocate(ptcl_imgs(params_glob%nptcls), corrs(nz))
        do i=1,params_glob%nptcls
            call ptcl_imgs(i)%new([params_glob%box,params_glob%box,1],  params_glob%smpd)
            call ptcl_imgs(i)%read(params_glob%stk, i)
        end do
        call ptcl_avg%new([params_glob%box,params_glob%box,1], params_glob%smpd)
        ! make logical mask for real-space corr calc
        call img_tmp%new([params_glob%box,params_glob%box,1], params_glob%smpd)
        img_tmp   = 1.0
        call img_tmp%mask(params_glob%msk, 'hard')
        corr_mask = img_tmp%bin2logical()
        call img_tmp%kill
        ! allocate real matrix for OpenMP reduction
        ldim = ptcl_avg%get_ldim()
        allocate(rmat_sum(ldim(1),ldim(2),ldim(3)), source=0.)
        ! flag existence
        existence = .true.
    end subroutine init_tseries_averager

    subroutine tseries_average
        real, allocatable :: weights(:)
        integer :: fromto(2), i, iframe, ind, ref_ind, n_nonzero
        real    :: w, sumw
        604 format(A,1X,F8.3,1X,F8.3,1X,F8.3,1X,F8.3)
        do iframe=1,params_glob%nptcls
            ! set time window
            fromto(1) = iframe - params_glob%nframesgrp/2
            fromto(2) = iframe + params_glob%nframesgrp/2 - 1
            ! shift the window if it's outside the time-series
            do while(fromto(1) < 1)
                fromto = fromto + 1
            end do
            do while(fromto(2) > params_glob%nptcls)
                fromto = fromto - 1
            end do
            ! set average to the particle in the current frame to initialize the process
            call ptcl_avg%copy(ptcl_imgs(iframe))
            ! de-noise through weighted averaging in time window
            do i=1,MAXITS
                ! correlate to average
                call calc_corrs
                ! calculate weights
                call calc_weights
                ! calculate weighted average
                call calc_wavg
            end do
            n_nonzero = count(weights > TINY)
            call calc_stats(corrs,   cstats)
            call calc_stats(weights, wstats)
            write(logfhandle,'(A,1X,I7)') '>>> FRAME', iframe
            write(logfhandle,604)         '>>> CORR    AVG/SDEV/MIN/MAX:', cstats%avg, cstats%sdev, cstats%minv, cstats%maxv
            write(logfhandle,604)         '>>> WEIGHT  AVG/SDEV/MIN/MAX:', wstats%avg, wstats%sdev, wstats%minv, wstats%maxv
            write(logfhandle,'(A,1X,I5)') '>>> # NONZERO WEIGHTS:       ', n_nonzero
            call ptcl_avg%write(params_glob%outstk, iframe)
        end do

        contains

            subroutine calc_corrs
                integer :: i, ind
                real    :: sxx
                call ptcl_avg%prenorm4real_corr(sxx, corr_mask)
                !$omp parallel do default(shared) private(i,ind) schedule(static) proc_bind(close)
                do i=fromto(1),fromto(2)
                    ind = i - fromto(1) + 1
                    corrs(ind) = ptcl_avg%real_corr_prenorm(ptcl_imgs(i), sxx, corr_mask)
                end do
                !$omp end parallel do
            end subroutine calc_corrs

            subroutine calc_weights
                logical :: renorm
                integer :: i, ind
                ! calculate weights
                if( params_glob%l_rankw )then
                    weights = corrs2weights(corrs, params_glob%ccw_crit, params_glob%rankw_crit, norm_sigm=.false.)
                else
                    weights = corrs2weights(corrs, params_glob%ccw_crit, norm_sigm=.false.)
                endif
                ! check weights backward in time
                renorm = .false.
                do i=fromto(1) + nz/2,fromto(1),-1
                    ind = i - fromto(1) + 1
                    if( weights(ind) <= TINY )then
                        weights(:ind) = 0.
                        renorm = .true.
                        exit
                    endif
                end do
                ! check weights forward in time
                do i=fromto(1) + nz/2,fromto(2)
                    ind = i - fromto(1) + 1
                    if( weights(ind) <= TINY )then
                        weights(ind:) = 0.
                        renorm = .true.
                        exit
                    endif
                end do
                sumw = sum(weights)
                if( renorm ) weights = weights / sumw
            end subroutine calc_weights

            subroutine calc_wavg
                integer :: i, ind
                real(kind=c_float), pointer :: rmat_ptr(:,:,:) => null()
                rmat_sum = 0.
                !$omp parallel do default(shared) private(i,ind,rmat_ptr) proc_bind(close) schedule(static) reduction(+:rmat_sum)
                do i=fromto(1),fromto(2)
                    ind = i - fromto(1) + 1
                    call ptcl_imgs(i)%get_rmat_ptr(rmat_ptr)
                    rmat_sum = rmat_sum + rmat_ptr(:ldim(1),:ldim(2),:ldim(3)) * weights(ind)
                end do
                !$omp end parallel do
                call ptcl_avg%set_rmat(rmat_sum)
            end subroutine calc_wavg

    end subroutine tseries_average

    subroutine kill_tseries_averager
        integer :: i
        if( existence )then
            do i=1,size(ptcl_imgs)
                call ptcl_imgs(i)%kill
            end do
            deallocate(ptcl_imgs, corr_mask, corrs, rmat_sum)
            call ptcl_avg%kill
        endif
    end subroutine kill_tseries_averager

end module simple_tseries_averager
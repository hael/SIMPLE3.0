! symmetry search routines
module simple_symsrcher
use simple_defs     ! use all in there
use simple_math     ! use all in there
use simple_cmdline, only: cmdline
use simple_params,  only: params
use simple_oris,    only: oris
use simple_image,   only: image
use simple_sym,     only: sym
implicit none

public :: dsym_cylinder
private

contains

    !>  dsym_cylinder search intended for symmetry of order D
    subroutine dsym_cylinder(p, dsym_os, cylinder)
        class(params), intent(in)    :: p
        class(oris),   intent(inout) :: dsym_os
        class(image),  intent(out)   :: cylinder
        type(image)          :: read_img, img_msk, dist_img, roavg_img, topview
        type(sym)            :: se
        real,    allocatable :: corrs(:), forsort(:), e2(:), radii(:)
        integer, allocatable :: labels(:)
        integer  :: halfnoris, cnt1, cnt2, i, l, noris
        real     :: cen1, cen2, sum1, sum2, sumvals
        real     :: minmax(2), width, height, sh1(3), ang
        if(p%pgrp(1:1).ne.'d' .and. p%pgrp(1:1).ne.'D')&
        &stop 'only intended for symmetry of order D; simple_symsrcher%dsym_cylinder'
        ! init
        noris = dsym_os%get_noris()
        allocate(corrs(noris),  source=-1.)
        allocate(radii(noris),  source=0.)
        allocate(e2(noris),     source=0.)
        allocate(labels(noris), source=0)
        call se%new(p%pgrp)
        call cylinder%new( [p%box, p%box, p%box], p%smpd)
        call read_img%new( [p%box, p%box, 1], p%smpd)
        call topview%new( [p%box, p%box, 1], p%smpd)
        call roavg_img%new([p%box, p%box, 1], p%smpd)
        call dist_img%new( [p%box, p%box, 1], p%smpd)
        call dist_img%cendist
        ang = 360. / real(se%get_nsym()/2)
        ! prep mask
        call img_msk%new([p%box,p%box,1],p%smpd)
        img_msk = 1.
        call img_msk%mask(p%msk, 'hard')
        ! centers, calculates self to rotational averages images & radii
        do i = 1, noris
            call read_img%read(p%stk,i)
            ! center image
            sh1 = read_img%center(p%cenlp, 'no', p%msk)
            call dsym_os%set(i, 'x', -sh1(1))
            call dsym_os%set(i, 'y', -sh1(2))
            ! rotational image
            call read_img%roavg(ang, roavg_img)
            call roavg_img%write('roavg.mrc',i)
            corrs(i) = read_img%real_corr(roavg_img, img_msk)
            ! radii
            call read_img%bp(0., p%cenlp)
            call read_img%mask(p%msk, 'hard')
            call read_img%bin_kmeans
            call read_img%write('bin.mrc',i)
            call read_img%mul(dist_img)
            minmax = read_img%minmax()
            radii(i) = min(p%msk, minmax(2))
        enddo
        call dsym_os%set_all('corr', corrs)
        ! indentify views along z and x-/y- axes
        forsort = corrs
        call hpsort(noris, forsort)
        halfnoris = nint(real(noris)/2.)
        cen1      = sum(forsort(1:halfnoris)) / real(halfnoris)
        cen2      = sum(forsort(halfnoris+1:noris)) / real(noris-halfnoris)
        sumvals   = sum(forsort)
        ! do 100 iterations of k-means
        do l = 1, 100
            sum1 = 0.
            cnt1 = 0
            do i = 1, noris
                if( (cen1-forsort(i))**2. < (cen2-forsort(i))**2. )then
                    cnt1 = cnt1 + 1
                    sum1 = sum1 + forsort(i)
                endif
            end do
            cnt2 = noris - cnt1
            sum2 = sumvals - sum1
            cen1 = sum1 / real(cnt1)
            cen2 = sum2 / real(cnt2)
        end do
        ! label views
        if(cen1 > cen2)then
            ! cen1: along z-axis
            labels = 2
            where( (cen1-corrs)**2. < (cen2-corrs)**2. )labels = 1
        else
            ! cen2: along z-axis
            labels = 1
            where( (cen1-corrs)**2. < (cen2-corrs)**2. )labels = 2
        endif
        e2 = 90.
        where(labels == 1) e2 = 0.
        call dsym_os%set_all('e2', e2)
        call dsym_os%set_all('class', real(labels))
        ! rotates input oris to asymmetric unit
        call se%rotall_to_asym(dsym_os)
        ! estimate height and cylinder radius (0.9 to account for overestimation)
        width  = 0.9 * (sum(radii, mask=(labels==1)) / real(count(labels==1)))
        height = 0.9 * (2. * sum(radii, mask=(labels==2)) / real(count(labels==2)))
        !call cylinder%bin_cylinder(width, height)
        ! dummy top view
        topview = 0.
        do i=1,noris
            if(labels(i)==1)then
                call read_img%read(p%stk,i)
                call read_img%rtsq(0., -dsym_os%get(i,'x'), -dsym_os%get(i,'y'))
                call topview%add(read_img)
            endif
        enddo
        call topview%div( real(count(labels==1)) )
        call topview%roavg(ang, roavg_img)
        topview = roavg_img
        call topview%norm
        call topview%mask(p%msk, 'soft')
        cylinder = 0.     
        do i=1,p%box
            if( abs( real(i-1)-real(p%box)/2. ) < height/2.)then
                call cylinder%set_slice( i, topview )
            endif
        enddo
        ! cleanup
        deallocate(corrs, e2, radii, labels)
        call dist_img%kill
        call img_msk%kill
        call read_img%kill
        call se%kill
        call roavg_img%kill
        call topview%kill
    end subroutine dsym_cylinder

end module simple_symsrcher

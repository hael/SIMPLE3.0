! concrete commander: operations on orientations
module simple_commander_oris
include 'simple_lib.f08'
use simple_ori,            only: ori
use simple_oris,           only: oris
use simple_cmdline,        only: cmdline
use simple_params,         only: params
use simple_build,          only: build
use simple_sp_project,     only: sp_project
use simple_commander_base, only: commander_base
use simple_binoris_io,     only: binwrite_oritab, binread_nlines, binread_oritab
implicit none

public :: cluster_oris_commander
public :: make_oris_commander
public :: orisops_commander
public :: oristats_commander
public :: rotmats2oris_commander
public :: vizoris_commander
private

type, extends(commander_base) :: cluster_oris_commander
  contains
    procedure :: execute      => exec_cluster_oris
end type cluster_oris_commander
type, extends(commander_base) :: make_oris_commander
  contains
    procedure :: execute      => exec_make_oris
end type make_oris_commander
type, extends(commander_base) :: orisops_commander
  contains
    procedure :: execute      => exec_orisops
end type orisops_commander
type, extends(commander_base) :: oristats_commander
  contains
    procedure :: execute      => exec_oristats
end type oristats_commander
type, extends(commander_base) :: rotmats2oris_commander
  contains
    procedure :: execute      => exec_rotmats2oris
end type rotmats2oris_commander
type, extends(commander_base) :: vizoris_commander
  contains
    procedure :: execute      => exec_vizoris
end type vizoris_commander

contains

    !> cluster_oris is a program for clustering orientations based on geodesic distance
    subroutine exec_cluster_oris( self, cline )
        !use simple_cluster_shc, only: cluster_shc
        use simple_clusterer,   only: cluster_shc_oris
        class(cluster_oris_commander), intent(inout) :: self
        class(cmdline),                intent(inout) :: cline
        type(build)          :: b
        type(params)         :: p
        type(oris)           :: os_class
        integer              :: icls, iptcl, numlen
        real                 :: avgd, sdevd, maxd, mind
        integer, allocatable :: clsarr(:)
        p = params(cline)
        call b%build_general_tbox(p, cline, do3d=.false.)
        call cluster_shc_oris(b%a, p%ncls)
        ! calculate distance statistics
        call b%a%cluster_diststat(avgd, sdevd, maxd, mind)
        write(*,'(a,1x,f15.6)') 'AVG      GEODESIC DIST WITHIN CLUSTERS(degrees): ', rad2deg(avgd)
        write(*,'(a,1x,f15.6)') 'AVG SDEV GEODESIC DIST WITHIN CLUSTERS(degrees): ', rad2deg(sdevd)
        write(*,'(a,1x,f15.6)') 'AVG MAX  GEODESIC DIST WITHIN CLUSTERS(degrees): ', rad2deg(maxd)
        write(*,'(a,1x,f15.6)') 'AVG MIN  GEODESIC DIST WITHIN CLUSTERS(degrees): ', rad2deg(mind)
        ! generate the class documents
        numlen = len(int2str(p%ncls))
        do icls=1,p%ncls
            call b%a%get_pinds(icls, 'class', clsarr)
            if( allocated(clsarr) )then
                call os_class%new(size(clsarr))
                do iptcl=1,size(clsarr)
                    call os_class%set_ori(iptcl, b%a%get_ori(clsarr(iptcl)))
                end do
                call os_class%write('oris_class'//int2str_pad(icls,numlen)//trim(TXT_EXT), [1,size(clsarr)])
                deallocate(clsarr)
                call os_class%kill
            endif
        end do
        ! end gracefully
        call simple_end('**** SIMPLE_CLUSTER_ORIS NORMAL STOP ****')
    end subroutine exec_cluster_oris

    !> for making SIMPLE orientation/parameter files
    subroutine exec_make_oris( self, cline )
        class(make_oris_commander), intent(inout) :: self
        class(cmdline),             intent(inout) :: cline
        type(build)  :: b
        type(ori)    :: orientation
        type(oris)   :: os_even
        type(params) :: p
        real         :: e3, x, y
        integer      :: i, class
        p = params(cline)
        call b%build_general_tbox(p, cline, do3d=.false.)
        if( cline%defined('ncls') )then
            os_even = oris(p%ncls)
            call os_even%spiral(p%nsym, p%eullims)
            call b%a%new(p%nptcls)
            do i=1,p%nptcls
                class = irnd_uni(p%ncls)
                orientation = os_even%get_ori(class)
                call b%a%set_ori(i, orientation)
                e3 = ran3()*2.*p%angerr-p%angerr
                x  = ran3()*2.0*p%sherr-p%sherr
                y  = ran3()*2.0*p%sherr-p%sherr
                call b%a%set(i, 'x', x)
                call b%a%set(i, 'y', y)
                call b%a%e3set(i, e3)
                call b%a%set(i, 'class', real(class))
            end do
        else if( cline%defined('ndiscrete') )then
            if( p%ndiscrete > 0 )then
                call b%a%rnd_oris_discrete(p%ndiscrete, p%nsym, p%eullims)
            endif
            call b%a%rnd_inpls(p%sherr)
        else if( p%even .eq. 'yes' )then
            call b%a%spiral(p%nsym, p%eullims)
            call b%a%rnd_inpls(p%sherr)
        else
            call b%a%rnd_oris(p%sherr)
            if( p%doprint .eq. 'yes' )then
                call b%a%print_matrices
            endif
        endif
        if( p%nstates > 1 ) call b%a%rnd_states(p%nstates)
        call binwrite_oritab(p%outfile, b%spproj, b%a, [1,b%a%get_noris()])
        ! end gracefully
        call simple_end('**** SIMPLE_MAKE_ORIS NORMAL STOP ****')
    end subroutine exec_make_oris

    subroutine exec_orisops( self, cline )
        class(orisops_commander), intent(inout) :: self
        class(cmdline),           intent(inout) :: cline
        type(build)  :: b
        type(ori)    :: orientation
        type(params) :: p
        integer      :: s, i
        p = params(cline)
        call b%build_general_tbox(p, cline, do3d=.false.)
        if( p%errify .eq. 'yes' )then
            ! introduce error in input orientations
            call b%a%introd_alig_err(p%angerr, p%sherr)
            if( p%ctf .ne. 'no' ) call b%a%introd_ctf_err(p%dferr)
        endif
        if( cline%defined('e1') .or.&
            cline%defined('e2') .or.&
            cline%defined('e3') )then
            ! rotate input Eulers
            call orientation%new
            call orientation%set_euler([p%e1,p%e2,p%e3])
            if( cline%defined('state') )then
                do i=1,b%a%get_noris()
                    s = nint(b%a%get(i, 'state'))
                    if( s == p%state )then
                        call b%a%rot(i,orientation)
                    endif
                end do
            else
                call b%a%rot(orientation)
            endif
        endif
        if( cline%defined('mul') )       call b%a%mul_shifts(p%mul)
        if( p%zero .eq. 'yes' )          call b%a%zero_shifts
        if( cline%defined('ndiscrete') ) call b%a%discretize(p%ndiscrete)
        if( p%symrnd .eq. 'yes' )        call b%se%symrandomize(b%a)
        if( cline%defined('nstates') )   call b%a%rnd_states(p%nstates)
        if( cline%defined('mirr') )then
            select case(trim(p%mirr))
                case('2d')
                    call b%a%mirror2d()
                case('3d')
                    call b%a%mirror3d()
                case('no')
                    ! nothing to do
                case DEFAULT
                    write(*,*) 'mirr flag: ', trim(p%mirr)
                    stop 'unsupported mirr flag; commander_oris :: exec_orisops'
            end select
        endif
        call binwrite_oritab(p%outfile, b%spproj, b%a, [1,b%a%get_noris()])
        call simple_end('**** SIMPLE_ORISOPS NORMAL STOP ****')
    end subroutine exec_orisops

    !> for analyzing SIMPLE orientation/parameter files
    subroutine exec_oristats( self, cline )
        class(oristats_commander), intent(inout) :: self
        class(cmdline),            intent(inout) :: cline
        type(build)          :: b
        type(sp_project)     :: spproj
        class(oris), pointer :: o => null()
        type(oris)           :: osubspace
        type(ori)            :: o_single
        type(params)         :: p
        real                 :: mind, maxd, avgd, sdevd, sumd, vard, scale
        real                 :: mind2, maxd2, avgd2, sdevd2, vard2
        real                 :: popmin, popmax, popmed, popave, popsdev, popvar, frac_populated, szmax
        integer              :: nprojs, iptcl, icls, j
        integer              :: noris, ncls
        real,    allocatable :: clustszs(:)
        integer, allocatable :: clustering(:), pops(:), tmp(:)
        logical, allocatable :: ptcl_mask(:)
        integer, parameter   :: hlen=50
        logical              :: err
        p = params(cline)
        call b%build_general_tbox(p, cline, do3d=.false.)
        if( cline%defined('oritab2') )then
            ! Comparison
            if( .not. cline%defined('oritab') ) stop 'need oritab for comparison'
            if( binread_nlines(p, p%oritab) .ne. binread_nlines(p, p%oritab2) )then
                stop 'inconsistent number of lines in the two oritabs!'
            endif
            call spproj%new_seg_with_ptr(p%nptcls, p%oritype, o)
            call binread_oritab(p%oritab2, spproj, o, [1,p%nptcls])
            call b%a%diststat(o, sumd, avgd, sdevd, mind, maxd)
            write(*,'(a,1x,f15.6)') 'SUM OF ANGULAR DISTANCE BETWEEN ORIENTATIONS  :', sumd
            write(*,'(a,1x,f15.6)') 'AVERAGE ANGULAR DISTANCE BETWEEN ORIENTATIONS :', avgd
            write(*,'(a,1x,f15.6)') 'STANDARD DEVIATION OF ANGULAR DISTANCES       :', sdevd
            write(*,'(a,1x,f15.6)') 'MINIMUM ANGULAR DISTANCE                      :', mind
            write(*,'(a,1x,f15.6)') 'MAXIMUM ANGULAR DISTANCE                      :', maxd
        else if( cline%defined('oritab') )then
            if( p%ctfstats .eq. 'yes' )then
                call b%a%stats('ctfres', avgd, sdevd, vard, err )
                call b%a%minmax('ctfres', mind, maxd)
                write(*,'(a,1x,f8.2)') 'AVERAGE CTF RESOLUTION               :', avgd
                write(*,'(a,1x,f8.2)') 'STANDARD DEVIATION OF CTF RESOLUTION :', sdevd
                write(*,'(a,1x,f8.2)') 'MINIMUM CTF RESOLUTION (BEST)        :', mind
                write(*,'(a,1x,f8.2)') 'MAXIMUM CTF RESOLUTION (WORST)       :', maxd
                call b%a%stats('dfx', avgd, sdevd, vard, err )
                call b%a%minmax('dfx', mind, maxd)
                call b%a%stats('dfy', avgd2, sdevd2, vard2, err )
                call b%a%minmax('dfy', mind2, maxd2)
                write(*,'(a,1x,f8.2)') 'AVERAGE DF                           :', (avgd+avgd2)/2.
                write(*,'(a,1x,f8.2)') 'STANDARD DEVIATION OF DF             :', (sdevd+sdevd2)/2.
                write(*,'(a,1x,f8.2)') 'MINIMUM DF                           :', (mind+mind2)/2.
                write(*,'(a,1x,f8.2)') 'MAXIMUM DF                           :', (maxd+maxd2)/2.
                goto 999
            endif
            if( p%classtats .eq. 'yes' )then
                noris = b%a%get_noris()
                ncls  = b%a%get_n('class')
                ! setup weights
                if( p%weights2D.eq.'yes' )then
                    if( noris <= SPECWMINPOP )then
                        call b%a%set_all2single('w', 1.0)
                    else
                        ! frac is one by default in prime2D (no option to set frac)
                        ! so spectral weighting is done over all images
                        call b%a%calc_spectral_weights(1.0)
                    endif
                else
                    ! defaults to unitary weights
                    call b%a%set_all2single('w', 1.0)
                endif
                ! generate class stats
                call b%a%get_pops(pops, 'class', consider_w=.true.)
                popmin         = minval(pops)
                popmax         = maxval(pops)
                popmed         = median(real(pops))
                call moment(real(pops), popave, popsdev, popvar, err)
                write(*,'(a,1x,f8.2)') 'MINIMUM POPULATION :', popmin
                write(*,'(a,1x,f8.2)') 'MAXIMUM POPULATION :', popmax
                write(*,'(a,1x,f8.2)') 'MEDIAN  POPULATION :', popmed
                write(*,'(a,1x,f8.2)') 'AVERAGE POPULATION :', popave
                write(*,'(a,1x,f8.2)') 'SDEV OF POPULATION :', popsdev
                ! produce a histogram of class populations
                szmax = maxval(pops)
                ! scale to max 50 *:s
                scale = 1.0
                do while( nint(scale*szmax) > hlen )
                    scale = scale - 0.001
                end do
                write(*,'(a)') '>>> HISTOGRAM OF CLASS POPULATIONS'
                do icls=1,ncls
                    write(*,*) pops(icls),"|",('*', j=1,nint(real(pops(icls)*scale)))
                end do
            endif
            if( p%projstats .eq. 'yes' )then
                if( .not. cline%defined('nspace') ) stop 'need nspace command line arg to provide projstats'
                noris = b%a%get_noris()
                ! setup weights
                if( p%weights3D.eq.'yes' )then
                    if( noris <= SPECWMINPOP )then
                        call b%a%calc_hard_weights(p%frac)
                    else
                        call b%a%calc_spectral_weights(p%frac)
                    endif
                else
                    call b%a%calc_hard_weights(p%frac)
                endif
                ! generate population stats
                call b%a%get_pops(tmp, 'proj', consider_w=.true.)
                nprojs         = size(tmp)
                pops           = pack(tmp, tmp > 0.5)                   !! realloc warning
                frac_populated = real(size(pops))/real(p%nspace)
                popmin         = minval(pops)
                popmax         = maxval(pops)
                popmed         = median(real(pops))
                call moment(real(pops), popave, popsdev, popvar, err)
                write(*,'(a)') '>>> STATISTICS BEFORE CLUSTERING'
                write(*,'(a,1x,f8.2)') 'FRAC POPULATED DIRECTIONS :', frac_populated
                write(*,'(a,1x,f8.2)') 'MINIMUM POPULATION        :', popmin
                write(*,'(a,1x,f8.2)') 'MAXIMUM POPULATION        :', popmax
                write(*,'(a,1x,f8.2)') 'MEDIAN  POPULATION        :', popmed
                write(*,'(a,1x,f8.2)') 'AVERAGE POPULATION        :', popave
                write(*,'(a,1x,f8.2)') 'SDEV OF POPULATION        :', popsdev
                ! produce a histogram based on clustering into NSPACE_BALANCE even directions
                ! first, generate a mask based on state flag and w
                ptcl_mask = b%a%included(consider_w=.true.)
                allocate(clustering(noris), clustszs(NSPACE_BALANCE))
                call osubspace%new(NSPACE_BALANCE)
                call osubspace%spiral(p%nsym, p%eullims)
                call osubspace%write('even_pdirs'//trim(TXT_EXT), [1,NSPACE_BALANCE])
                do iptcl=1,b%a%get_noris()
                    if( ptcl_mask(iptcl) )then
                        o_single = b%a%get_ori(iptcl)
                        clustering(iptcl) = osubspace%find_closest_proj(o_single)
                    else
                        clustering(iptcl) = 0
                    endif
                end do
                ! determine cluster sizes
                do icls=1,NSPACE_BALANCE
                    clustszs(icls) = real(count(clustering == icls))
                end do
                frac_populated = real(count(clustszs > 0.5))/real(NSPACE_BALANCE)
                popmin         = minval(clustszs)
                popmax         = maxval(clustszs)
                popmed         = median_nocopy(clustszs)
                call moment(clustszs, popave, popsdev, popvar, err)
                write(*,'(a)') '>>> STATISTICS AFTER CLUSTERING'
                write(*,'(a,1x,f8.2)') 'FRAC POPULATED DIRECTIONS :', frac_populated
                write(*,'(a,1x,f8.2)') 'MINIMUM POPULATION        :', popmin
                write(*,'(a,1x,f8.2)') 'MAXIMUM POPULATION        :', popmax
                write(*,'(a,1x,f8.2)') 'MEDIAN  POPULATION        :', popmed
                write(*,'(a,1x,f8.2)') 'AVERAGE POPULATION        :', popave
                write(*,'(a,1x,f8.2)') 'SDEV OF POPULATION        :', popsdev
                ! scale to max 50 *:s
                scale = 1.0
                do while( nint(scale * popmax) > hlen )
                    scale = scale - 0.001
                end do
                write(*,'(a)') '>>> HISTOGRAM OF SUBSPACE POPULATIONS (FROM NORTH TO SOUTH)'
                do icls=1,NSPACE_BALANCE
                    write(*,*) nint(clustszs(icls)),"|",('*', j=1,nint(clustszs(icls)*scale))
                end do
            endif
            if( p%trsstats .eq. 'yes' )then
                call b%a%stats('x', avgd, sdevd, vard, err )
                call b%a%minmax('x', mind, maxd)
                call b%a%stats('y', avgd2, sdevd2, vard2, err )
                call b%a%minmax('y', mind2, maxd2)
                write(*,'(a,1x,f8.2)') 'AVERAGE TRS               :', (avgd+avgd2)/2.
                write(*,'(a,1x,f8.2)') 'STANDARD DEVIATION OF TRS :', (sdevd+sdevd2)/2.
                write(*,'(a,1x,f8.2)') 'MINIMUM TRS               :', (mind+mind2)/2.
                write(*,'(a,1x,f8.2)') 'MAXIMUM TRS               :', (maxd+maxd2)/2.
                goto 999
            endif
        endif
        999 call simple_end('**** SIMPLE_ORISTATS NORMAL STOP ****')
    end subroutine exec_oristats

    !> convert rotation matrix to orientation oris class
    subroutine exec_rotmats2oris( self, cline )
        use simple_nrtxtfile, only: nrtxtfile
        class(rotmats2oris_commander),  intent(inout) :: self
        class(cmdline),                 intent(inout) :: cline
        type(nrtxtfile) :: rotmats
        type(params)    :: p
        type(ori)       :: o
        type(oris)      :: os_out
        integer         :: nrecs_per_line, iline, ndatlines
        real            :: rline(9), rmat(3,3)
        p = params(cline)
        if( cline%defined('infile') )then
            call rotmats%new(p%infile, 1)
            ndatlines = rotmats%get_ndatalines()
        else
            stop 'Need infile defined on command line: text file with 9 &
            &records per line defining a rotation matrix (11) (12) (13) (21) etc.'
        endif
        if( fname2format(trim(p%outfile)) .eq. '.simple' )then
            stop '*.simple outfile not supported; commander_oris :: rotmats2oris'
        endif
        nrecs_per_line = rotmats%get_nrecs_per_line()
        if( nrecs_per_line /= 9 ) stop 'need 9 records (real nrs) per&
        &line of file (infile) describing rotation matrices'
        call os_out%new(ndatlines)
        do iline=1,ndatlines
            call rotmats%readNextDataLine(rline)
            rmat(1,1) = rline(1)
            rmat(1,2) = rline(2)
            rmat(1,3) = rline(3)
            rmat(2,1) = rline(4)
            rmat(2,2) = rline(5)
            rmat(2,3) = rline(6)
            rmat(3,1) = rline(7)
            rmat(3,2) = rline(8)
            rmat(3,3) = rline(9)
            rmat = transpose(rmat)
            call o%ori_from_rotmat(rmat)
            call os_out%set_ori(iline,o)
        end do
        call os_out%swape1e3
        call os_out%write(p%outfile, [1,ndatlines])
        call rotmats%kill
        call simple_end('**** ROTMATS2ORIS NORMAL STOP ****')
    end subroutine exec_rotmats2oris

    subroutine exec_vizoris( self, cline )
        class(vizoris_commander),  intent(inout) :: self
        class(cmdline),            intent(inout) :: cline
        type(build)           :: b
        type(params)          :: p
        type(ori)             :: o, o_prev
        real,    allocatable  :: euldists(:)
        integer, allocatable  :: pops(:)
        character(len=STDLEN) :: fname, ext
        integer               :: i, n, maxpop, funit, closest,io_stat
        real                  :: radius, maxradius, ang, scale, col, avg_geodist,avg_euldist,geodist
        real                  :: xyz(3), xyz_end(3), xyz_start(3), vec(3)
        p = params(cline)
        call b%build_general_tbox(p, cline, do3d=.false.)
        ! BELOW IS FOR TESTING ONLY
        ! call b%a%spiral
        ! call a%new(2*b%a%get_noris()-1)
        ! do i = 1, b%a%get_noris()
        !     call a%set_ori(i,b%a%get_ori(i))
        ! enddo
        ! do i = b%a%get_noris()+1, 2*b%a%get_noris()-1
        !     call a%set_ori(i,b%a%get_ori(2*b%a%get_noris()-i))
        ! enddo
        ! b%a = a
        n = b%a%get_noris()
        if( .not.cline%defined('fbody') )then
            fname = basename(trim(adjustl(p%oritab)))
            ext   = trim(fname2ext(fname))
            p%fbody = trim(get_fbody(trim(fname), trim(ext)))
        endif
        if( p%tseries.eq.'no' )then
            ! Discretization of the projection directions
            ! init
            allocate(pops(p%nspace), source=0,stat=alloc_stat)
            if(alloc_stat.ne.0)call allocchk("In commander_oris:: vizoris allocating pops ", alloc_stat)
            ang = 3.6 / sqrt(real(p%nsym*p%nspace))
            maxradius = 0.75 * sqrt( (1.-cos(ang))**2. + sin(ang)**2. )
            ! projection direction attribution
            n = b%a%get_noris()
            do i = 1, n
                o = b%a%get_ori(i)
                if( o%isstatezero() )cycle
                call progress(i, n)
                closest = b%e%find_closest_proj(o)
                pops(closest) = pops(closest) + 1
            enddo
            maxpop = maxval(pops)
            write(*,'(A,I6)')'>>> NUMBER OF POPULATED PROJECTION DIRECTIONS:', count(pops>0)
            write(*,'(A,I6)')'>>> NUMBER OF EMPTY     PROJECTION DIRECTIONS:', count(pops==0)
            ! output
            fname = trim(p%fbody)//'.bild'
            call fopen(funit, status='REPLACE', action='WRITE', file=trim(fname),iostat=io_stat)
             if(io_stat/=0)call fileiochk("simple_commander_oris::exec_vizoris fopen failed "//trim(fname), io_stat)
            ! header
            write(funit,'(A)')".translate 0.0 0.0 0.0"
            write(funit,'(A)')".scale 10"
            write(funit,'(A)')".comment -- unit sphere --"
            write(funit,'(A)')".color 0.8 0.8 0.8"
            write(funit,'(A)')".sphere 0 0 0 1.0"
            write(funit,'(A)')".comment -- planes --"
            write(funit,'(A)')".color 0.3 0.3 0.3"
            write(funit,'(A)')".cylinder -0.02 0 0 0.02 0 0 1.02"
            write(funit,'(A)')".cylinder 0 -0.02 0 0 0.02 0 1.02"
            write(funit,'(A)')".cylinder 0 0 -0.02 0 0 0.02 1.02"
            write(funit,'(A)')".comment -- x-axis --"
            write(funit,'(A)')".color 1 0 0"
            write(funit,'(A)')".cylinder -1.5 0 0 1.5 0 0 0.02"
            write(funit,'(A)')".comment -- y-axis --"
            write(funit,'(A)')".color 0 1 0"
            write(funit,'(A)')".cylinder 0 -1.5 0 0 1.5 0 0.02"
            write(funit,'(A)')".comment -- z-axis --"
            write(funit,'(A)')".color 0 0 1"
            write(funit,'(A)')".cylinder 0 0 -1.5 0 0 1.5 0.02"
            ! body
            write(funit,'(A)')".comment -- projection firections --"
            write(funit,'(A)')".color 0.4 0.4 0.4"
            do i = 1, p%nspace
                if( pops(i) == 0 )cycle
                scale     = real(pops(i)) / real(maxpop)
                xyz_start = b%e%get_normal(i)
                xyz_end   = (1.05 + scale/4.) * xyz_start
                radius    = max(maxradius * scale, 0.002)
                write(funit,'(A,F7.3,F7.3,F7.3,F7.3,F7.3,F7.3,F6.3)')&
                &'.cylinder ', xyz_start, xyz_end, radius
            enddo
            call fclose(funit, errmsg="simple_commander_oris::exec_vizoris closing "//trim(fname))
        else
            ! time series
            ! unit sphere tracking
            fname  = trim(p%fbody)//'_motion.bild'
            radius = 0.02
            call fopen(funit, status='REPLACE', action='WRITE', file=trim(fname), iostat=io_stat)
             if(io_stat/=0)call fileiochk("simple_commander_oris::exec_vizoris fopen failed ", io_stat)
            write(funit,'(A)')".translate 0.0 0.0 0.0"
            write(funit,'(A)')".scale 1"
            do i = 1, n
                o   = b%a%get_ori(i)
                xyz = o%get_normal()
                col = real(i-1)/real(n-1)
                write(funit,'(A,F6.2,F6.2)')".color 1.0 ", col, col
                if( i==1 )then
                    write(funit,'(A,F7.3,F7.3,F7.3,A)')".sphere ", xyz, " 0.08"
                else
                    vec = xyz - xyz_start
                    if( sqrt(dot_product(vec, vec)) > 0.01 )then
                        write(funit,'(A,F7.3,F7.3,F7.3,A)')".sphere ", xyz, " 0.02"
                        !write(funit,'(A,F7.3,F7.3,F7.3,F7.3,F7.3,F7.3,F6.3)')&
                        !&'.cylinder ', xyz_start, xyz, radius
                    endif
                endif
                xyz_start = xyz
            enddo
            write(funit,'(A,F7.3,F7.3,F7.3,A)')".sphere ", xyz, " 0.08"
            call fclose(funit, errmsg="simple_commander_oris::exec_vizoris closing "//trim(fname))
            ! distance output
            avg_geodist = 0.
            avg_euldist = 0.
            allocate(euldists(n), stat=alloc_stat)
            fname  = trim(p%fbody)//'_motion.csv'
            call fopen(funit, status='REPLACE', action='WRITE', file=trim(fname), iostat=io_stat)
            if(io_stat/=0)call fileiochk("simple_commander_oris::exec_vizoris fopen failed "//trim(fname), io_stat)
            do i = 1, n
                o = b%a%get_ori(i)
                if( i==1 )then
                    ang     = 0.
                    geodist = 0.
                else
                    ang     = rad2deg(o_prev.euldist.o)
                    geodist = o_prev.geod.o
                    call o_prev%mirror2d
                    ang     = min(ang, rad2deg(o_prev.euldist.o))
                    geodist = min(geodist, o_prev.geod.o)
                    avg_euldist = avg_euldist + ang
                    avg_geodist = avg_geodist + geodist
                endif
                euldists(i) = ang
                write(funit,'(I7,A1,F8.3,A1,F8.3)')i, ',', ang, ',', geodist
                o_prev = o
            enddo
            call fclose(funit, errmsg="simple_commander_oris::exec_vizoris closing "//trim(fname))
            avg_geodist = avg_geodist / real(n-1)
            avg_euldist = avg_euldist / real(n-1)
            write(*,'(A,F8.3)')'>>> AVERAGE EULER    DISTANCE: ',avg_euldist
            write(*,'(A,F8.3)')'>>> AVERAGE GEODESIC DISTANCE: ',avg_geodist
            ! movie output
            ! setting Rprev to south pole as it where chimera opens
            ! call o_prev%new
            ! call o_prev%mirror3d
            ! Rprev = o_prev%get_mat()
            ! fname = trim(p%fbody)//'_movie.cmd'
            ! call fopen(funit, status='REPLACE', action='WRITE', file=trim(fname), iostat=io_stat)
            ! call fileiochk("simple_commander_oris::exec_vizoris fopen failed "//trim(fname), io_stat)
            ! do i = 1, n
            !     o  = b%a%get_ori(i)
            !     Ri = o%get_mat()
            !     R  = matmul(Ri,transpose(Rprev))
            !     call rotmat2axis(R, axis)
            !     if( abs(euldists(i)) > 0.01 )then
            !         if(i==1)then
            !             euldists(1) = rad2deg(o.euldist.o_prev)
            !             write(funit,'(A,A,A1,A,A1,A,A1,F8.2,A2)')&
            !             &'roll ', trim(real2str(axis(1))),',', trim(real2str(axis(2))),',', trim(real2str(axis(3))),' ',&
            !             &euldists(i), ' 1'
            !         else
            !             write(funit,'(A,A,A1,A,A1,A,A1,F8.2,A)')&
            !             &'roll ', trim(real2str(axis(1))),',', trim(real2str(axis(2))),',', trim(real2str(axis(3))),' ',&
            !             &euldists(i), ' 2; wait 2'
            !         endif
            !         o_prev = o
            !         Rprev  = Ri
            !     endif
            ! enddo
            ! call fclose(funit, errmsg="simple_commander_oris::exec_vizoris closing "//trim(fname))
        endif
        call simple_end('**** VIZORIS NORMAL STOP ****')
    end subroutine exec_vizoris

end module simple_commander_oris

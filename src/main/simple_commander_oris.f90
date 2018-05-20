! concrete commander: operations on orientations
module simple_commander_oris
include 'simple_lib.f08'
use simple_ori,            only: ori
use simple_oris,           only: oris
use simple_cmdline,        only: cmdline
use simple_sp_project,     only: sp_project
use simple_commander_base, only: commander_base
use simple_binoris_io,     only: binwrite_oritab, binread_nlines, binread_oritab
use simple_parameters,     only: parameters
use simple_builder,        only: builder
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
        use simple_clusterer,   only: cluster_shc_oris
        class(cluster_oris_commander), intent(inout) :: self
        class(cmdline),                intent(inout) :: cline
        type(parameters)     :: params
        type(builder)        :: build
        type(oris)           :: os_class
        integer              :: icls, iptcl, numlen
        real                 :: avgd, sdevd, maxd, mind
        integer, allocatable :: clsarr(:)
        call build%init_params_and_build_general_tbox(cline,params,do3d=.false.)
        call cluster_shc_oris(build%a, params%ncls)
        ! calculate distance statistics
        call build%a%cluster_diststat(avgd, sdevd, maxd, mind)
        write(*,'(a,1x,f15.6)') 'AVG      GEODESIC DIST WITHIN CLUSTERS(degrees): ', rad2deg(avgd)
        write(*,'(a,1x,f15.6)') 'AVG SDEV GEODESIC DIST WITHIN CLUSTERS(degrees): ', rad2deg(sdevd)
        write(*,'(a,1x,f15.6)') 'AVG MAX  GEODESIC DIST WITHIN CLUSTERS(degrees): ', rad2deg(maxd)
        write(*,'(a,1x,f15.6)') 'AVG MIN  GEODESIC DIST WITHIN CLUSTERS(degrees): ', rad2deg(mind)
        ! generate the class documents
        numlen = len(int2str(params%ncls))
        do icls=1,params%ncls
            call build%a%get_pinds(icls, 'class', clsarr)
            if( allocated(clsarr) )then
                call os_class%new(size(clsarr))
                do iptcl=1,size(clsarr)
                    call os_class%set_ori(iptcl, build%a%get_ori(clsarr(iptcl)))
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
        type(parameters) :: params
        type(builder)    :: build
        type(ori)        :: orientation
        type(oris)       :: os_even
        real             :: e3, x, y
        integer          :: i, class
        call build%init_params_and_build_general_tbox(cline,params,do3d=.false.)
        if( cline%defined('ncls') )then
            os_even = oris(params%ncls)
            call os_even%spiral(params%nsym, params%eullims)
            call build%a%new(params%nptcls)
            do i=1,params%nptcls
                class = irnd_uni(params%ncls)
                orientation = os_even%get_ori(class)
                call build%a%set_ori(i, orientation)
                e3 = ran3()*2.*params%angerr-params%angerr
                x  = ran3()*2.0*params%sherr-params%sherr
                y  = ran3()*2.0*params%sherr-params%sherr
                call build%a%set(i, 'x', x)
                call build%a%set(i, 'y', y)
                call build%a%e3set(i, e3)
                call build%a%set(i, 'class', real(class))
            end do
        else if( cline%defined('ndiscrete') )then
            if( params%ndiscrete > 0 )then
                call build%a%rnd_oris_discrete(params%ndiscrete, params%nsym, params%eullims)
            endif
            call build%a%rnd_inpls(params%sherr)
        else if( params%even .eq. 'yes' )then
            call build%a%spiral(params%nsym, params%eullims)
            call build%a%rnd_inpls(params%sherr)
        else
            call build%a%rnd_oris(params%sherr)
            if( params%doprint .eq. 'yes' )then
                call build%a%print_matrices
            endif
        endif
        if( params%nstates > 1 ) call build%a%rnd_states(params%nstates)
        call binwrite_oritab(params%outfile, build%spproj, build%a, [1,build%a%get_noris()])
        ! end gracefully
        call simple_end('**** SIMPLE_MAKE_ORIS NORMAL STOP ****')
    end subroutine exec_make_oris

    subroutine exec_orisops( self, cline )
        class(orisops_commander), intent(inout) :: self
        class(cmdline),           intent(inout) :: cline
        type(parameters) :: params
        type(builder)    :: build
        type(ori)        :: orientation
        integer          :: s, i
        call build%init_params_and_build_general_tbox(cline,params,do3d=.false.)
        if( params%errify .eq. 'yes' )then
            ! introduce error in input orientations
            call build%a%introd_alig_err(params%angerr, params%sherr)
            if( params%ctf .ne. 'no' ) call build%a%introd_ctf_err(params%dferr)
        endif
        if( cline%defined('e1') .or.&
            cline%defined('e2') .or.&
            cline%defined('e3') )then
            ! rotate input Eulers
            call orientation%new
            call orientation%set_euler([params%e1,params%e2,params%e3])
            if( cline%defined('state') )then
                do i=1,build%a%get_noris()
                    s = nint(build%a%get(i, 'state'))
                    if( s == params%state )then
                        call build%a%rot(i,orientation)
                    endif
                end do
            else
                call build%a%rot(orientation)
            endif
        endif
        if( cline%defined('mul') )       call build%a%mul_shifts(params%mul)
        if( params%zero .eq. 'yes' )          call build%a%zero_shifts
        if( cline%defined('ndiscrete') ) call build%a%discretize(params%ndiscrete)
        if( params%symrnd .eq. 'yes' )        call build%se%symrandomize(build%a)
        if( cline%defined('nstates') )   call build%a%rnd_states(params%nstates)
        if( cline%defined('mirr') )then
            select case(trim(params%mirr))
                case('2d')
                    call build%a%mirror2d()
                case('3d')
                    call build%a%mirror3d()
                case('no')
                    ! nothing to do
                case DEFAULT
                    write(*,*) 'mirr flag: ', trim(params%mirr)
                    stop 'unsupported mirr flag; commander_oris :: exec_orisops'
            end select
        endif
        call binwrite_oritab(params%outfile, build%spproj, build%a, [1,build%a%get_noris()])
        call simple_end('**** SIMPLE_ORISOPS NORMAL STOP ****')
    end subroutine exec_orisops

    !> for analyzing SIMPLE orientation/parameter files
    subroutine exec_oristats( self, cline )
        class(oristats_commander), intent(inout) :: self
        class(cmdline),            intent(inout) :: cline
        type(parameters)     :: params
        type(builder)        :: build
        type(sp_project)     :: spproj
        class(oris), pointer :: o => null()
        type(oris)           :: osubspace
        type(ori)            :: o_single
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
        call build%init_params_and_build_general_tbox(cline,params,do3d=.false.)
        if( cline%defined('oritab2') )then
            ! Comparison
            if( .not. cline%defined('oritab') ) stop 'need oritab for comparison'
            if( binread_nlines( params%oritab) .ne. binread_nlines( params%oritab2) )then
                stop 'inconsistent number of lines in the two oritabs!'
            endif
            call spproj%new_seg_with_ptr(params%nptcls, params%oritype, o)
            call binread_oritab(params%oritab2, spproj, o, [1,params%nptcls])
            call build%a%diststat(o, sumd, avgd, sdevd, mind, maxd)
            write(*,'(a,1x,f15.6)') 'SUM OF ANGULAR DISTANCE BETWEEN ORIENTATIONS  :', sumd
            write(*,'(a,1x,f15.6)') 'AVERAGE ANGULAR DISTANCE BETWEEN ORIENTATIONS :', avgd
            write(*,'(a,1x,f15.6)') 'STANDARD DEVIATION OF ANGULAR DISTANCES       :', sdevd
            write(*,'(a,1x,f15.6)') 'MINIMUM ANGULAR DISTANCE                      :', mind
            write(*,'(a,1x,f15.6)') 'MAXIMUM ANGULAR DISTANCE                      :', maxd
        else if( cline%defined('oritab') )then
            if( params%ctfstats .eq. 'yes' )then
                call build%a%stats('ctfres', avgd, sdevd, vard, err )
                call build%a%minmax('ctfres', mind, maxd)
                write(*,'(a,1x,f8.2)') 'AVERAGE CTF RESOLUTION               :', avgd
                write(*,'(a,1x,f8.2)') 'STANDARD DEVIATION OF CTF RESOLUTION :', sdevd
                write(*,'(a,1x,f8.2)') 'MINIMUM CTF RESOLUTION (BEST)        :', mind
                write(*,'(a,1x,f8.2)') 'MAXIMUM CTF RESOLUTION (WORST)       :', maxd
                call build%a%stats('dfx', avgd, sdevd, vard, err )
                call build%a%minmax('dfx', mind, maxd)
                call build%a%stats('dfy', avgd2, sdevd2, vard2, err )
                call build%a%minmax('dfy', mind2, maxd2)
                write(*,'(a,1x,f8.2)') 'AVERAGE DF                           :', (avgd+avgd2)/2.
                write(*,'(a,1x,f8.2)') 'STANDARD DEVIATION OF DF             :', (sdevd+sdevd2)/2.
                write(*,'(a,1x,f8.2)') 'MINIMUM DF                           :', (mind+mind2)/2.
                write(*,'(a,1x,f8.2)') 'MAXIMUM DF                           :', (maxd+maxd2)/2.
                goto 999
            endif
            if( params%classtats .eq. 'yes' )then
                noris = build%a%get_noris()
                ncls  = build%a%get_n('class')
                ! setup weights
                if( params%weights2D.eq.'yes' )then
                    if( noris <= SPECWMINPOP )then
                        call build%a%set_all2single('w', 1.0)
                    else
                        ! frac is one by default in prime2D (no option to set frac)
                        ! so spectral weighting is done over all images
                        call build%a%calc_spectral_weights(1.0)
                    endif
                else
                    ! defaults to unitary weights
                    call build%a%set_all2single('w', 1.0)
                endif
                ! generate class stats
                call build%a%get_pops(pops, 'class', consider_w=.true.)
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
            if( params%projstats .eq. 'yes' )then
                if( .not. cline%defined('nspace') ) stop 'need nspace command line arg to provide projstats'
                noris = build%a%get_noris()
                ! setup weights
                if( params%weights3D.eq.'yes' )then
                    if( noris <= SPECWMINPOP )then
                        call build%a%calc_hard_weights(params%frac)
                    else
                        call build%a%calc_spectral_weights(params%frac)
                    endif
                else
                    call build%a%calc_hard_weights(params%frac)
                endif
                ! generate population stats
                call build%a%get_pops(tmp, 'proj', consider_w=.true.)
                nprojs         = size(tmp)
                pops           = pack(tmp, tmp > 0.5)                   !! realloc warning
                frac_populated = real(size(pops))/real(params%nspace)
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
                ptcl_mask = build%a%included(consider_w=.true.)
                allocate(clustering(noris), clustszs(NSPACE_BALANCE))
                call osubspace%new(NSPACE_BALANCE)
                call osubspace%spiral(params%nsym, params%eullims)
                call osubspace%write('even_pdirs'//trim(TXT_EXT), [1,NSPACE_BALANCE])
                do iptcl=1,build%a%get_noris()
                    if( ptcl_mask(iptcl) )then
                        o_single = build%a%get_ori(iptcl)
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
            if( params%trsstats .eq. 'yes' )then
                call build%a%stats('x', avgd, sdevd, vard, err )
                call build%a%minmax('x', mind, maxd)
                call build%a%stats('y', avgd2, sdevd2, vard2, err )
                call build%a%minmax('y', mind2, maxd2)
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
        type(parameters) :: params
        type(nrtxtfile) :: rotmats
        type(ori)       :: o
        type(oris)      :: os_out
        integer         :: nrecs_per_line, iline, ndatlines
        real            :: rline(9), rmat(3,3)
        params = parameters(cline)
        if( cline%defined('infile') )then
            call rotmats%new(params%infile, 1)
            ndatlines = rotmats%get_ndatalines()
        else
            stop 'Need infile defined on command line: text file with 9 &
            &records per line defining a rotation matrix (11) (12) (13) (21) etc.'
        endif
        if( fname2format(trim(params%outfile)) .eq. '.simple' )then
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
        call os_out%write(params%outfile, [1,ndatlines])
        call rotmats%kill
        call simple_end('**** ROTMATS2ORIS NORMAL STOP ****')
    end subroutine exec_rotmats2oris

    subroutine exec_vizoris( self, cline )
        class(vizoris_commander),  intent(inout) :: self
        class(cmdline),            intent(inout) :: cline
        type(parameters)      :: params
        type(builder)         :: build
        type(ori)             :: o, o_prev
        real,    allocatable  :: euldists(:)
        integer, allocatable  :: pops(:)
        character(len=STDLEN) :: fname, ext
        integer               :: i, n, maxpop, funit, closest,io_stat
        real                  :: radius, maxradius, ang, scale, col, avg_geodist,avg_euldist,geodist
        real                  :: xyz(3), xyz_end(3), xyz_start(3), vec(3)
        call build%init_params_and_build_general_tbox(cline,params,do3d=.false.)
        n = build%a%get_noris()
        if( .not.cline%defined('fbody') )then
            fname = basename(trim(adjustl(params%oritab)))
            ext   = trim(fname2ext(fname))
            params%fbody = trim(get_fbody(trim(fname), trim(ext)))
        endif
        if( params%tseries.eq.'no' )then
            ! Discretization of the projection directions
            ! init
            allocate(pops(params%nspace), source=0,stat=alloc_stat)
            if(alloc_stat.ne.0)call allocchk("In commander_oris:: vizoris allocating pops ", alloc_stat)
            ang = 3.6 / sqrt(real(params%nsym*params%nspace))
            maxradius = 0.75 * sqrt( (1.-cos(ang))**2. + sin(ang)**2. )
            ! projection direction attribution
            n = build%a%get_noris()
            do i = 1, n
                o = build%a%get_ori(i)
                if( o%isstatezero() )cycle
                call progress(i, n)
                closest = build%e%find_closest_proj(o)
                pops(closest) = pops(closest) + 1
            enddo
            maxpop = maxval(pops)
            write(*,'(A,I6)')'>>> NUMBER OF POPULATED PROJECTION DIRECTIONS:', count(pops>0)
            write(*,'(A,I6)')'>>> NUMBER OF EMPTY     PROJECTION DIRECTIONS:', count(pops==0)
            ! output
            fname = trim(params%fbody)//'.bild'
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
            do i = 1, params%nspace
                if( pops(i) == 0 )cycle
                scale     = real(pops(i)) / real(maxpop)
                xyz_start = build%e%get_normal(i)
                xyz_end   = (1.05 + scale/4.) * xyz_start
                radius    = max(maxradius * scale, 0.002)
                write(funit,'(A,F7.3,F7.3,F7.3,F7.3,F7.3,F7.3,F6.3)')&
                &'.cylinder ', xyz_start, xyz_end, radius
            enddo
            call fclose(funit, errmsg="simple_commander_oris::exec_vizoris closing "//trim(fname))
        else
            ! time series
            ! unit sphere tracking
            fname  = trim(params%fbody)//'_motion.bild'
            radius = 0.02
            call fopen(funit, status='REPLACE', action='WRITE', file=trim(fname), iostat=io_stat)
             if(io_stat/=0)call fileiochk("simple_commander_oris::exec_vizoris fopen failed ", io_stat)
            write(funit,'(A)')".translate 0.0 0.0 0.0"
            write(funit,'(A)')".scale 1"
            do i = 1, n
                o   = build%a%get_ori(i)
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
            fname  = trim(params%fbody)//'_motion.csv'
            call fopen(funit, status='REPLACE', action='WRITE', file=trim(fname), iostat=io_stat)
            if(io_stat/=0)call fileiochk("simple_commander_oris::exec_vizoris fopen failed "//trim(fname), io_stat)
            do i = 1, n
                o = build%a%get_ori(i)
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
        endif
        call simple_end('**** VIZORIS NORMAL STOP ****')
    end subroutine exec_vizoris

end module simple_commander_oris

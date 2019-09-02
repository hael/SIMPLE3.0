program simple_test_simnano
include 'simple_lib.f08'
use simple_oris,       only: oris
use simple_ori,        only: ori
use simple_image,      only: image
use simple_kbinterpol, only: kbinterpol
use simple_projector,  only: projector
use simple_ctf,        only: ctf
use simple_simulator,  only: simimg
use simple_parameters, only: parameters
use simple_cmdline,    only: cmdline
use simple_commander_sim, only: simulate_atoms_commander
implicit none
type(simulate_atoms_commander) :: xsim_atoms
type(parameters) :: params
type(cmdline)    :: cline, cline_graphene, cline_particle
type(image)      :: graphene, graphene_vol, particle_vol, particle, img, imgpd
type(ori)        :: orientation
type(oris)       :: spiral
type(ctf)        :: tfun
type(projector)  :: vol_pad
character(len=:), allocatable :: path
real             :: snr_pink, snr_detector, x,y
integer          :: i,envstat
character(len=LONGSTRLEN), parameter :: graphene_fname = 'sheet.mrc'
character(len=LONGSTRLEN), parameter :: particle_fname = 'ptcl.mrc'
call cline%set('prg','simnano')
call cline%set('ctf','yes')
call cline%set('box', 512.)
call cline%checkvar('smpd',      1)
call cline%checkvar('nptcls',    2)
call cline%checkvar('snr',       3)
call cline%checkvar('nthr',      4)
call cline%checkvar('bfac',      5)
call cline%checkvar('moldiam',   6)
call cline%checkvar('element',   7)
call cline%checkvar('outstk',    8)
call cline%parse_oldschool
call cline%check
call params%new(cline)
! init
snr_pink     = params%snr/0.2
snr_detector = params%snr/0.8
call spiral%new(params%nptcls)
call spiral%spiral
! simulate graphene
path = simple_getenv('SIMPLE_PATH',envstat)
path = trim(path)//'/../production/tests/test_simnano/graphene_trans.pdb'
call cline_graphene%set('prg','simulate_atoms')
call cline_graphene%set('smpd',params%smpd)
call cline_graphene%set('pdbfile', trim(path))
call cline_graphene%set('outvol',  graphene_fname)
call cline_graphene%set('box',real(params%box))
call cline_graphene%set('nthr',real(params%nthr))
call xsim_atoms%execute(cline_graphene)
! simulate nano-particle
call cline_particle%set('prg','simulate_atoms')
call cline_particle%set('smpd',params%smpd)
call cline_particle%set('element', trim(params%element))
call cline_particle%set('outvol',  trim(particle_fname))
call cline_particle%set('moldiam', real(params%moldiam))
call cline_particle%set('box',real(params%box))
call cline_particle%set('nthr',real(params%nthr))
call xsim_atoms%execute(cline_particle)
! graphene slice
call graphene_vol%new([params%box,params%box,params%box],params%smpd)
call graphene%new([params%boxpd,params%boxpd,1],params%smpd)
call orientation%new
call orientation%set_euler([0.,0.,0.])
call graphene_vol%read(graphene_fname)
call vol_pad%new([params%boxpd, params%boxpd, params%boxpd], params%smpd)
call graphene_vol%pad(vol_pad)
call graphene_vol%kill
call del_file(graphene_fname)
call vol_pad%fft
call vol_pad%expand_cmat(params%alpha)
call vol_pad%fproject(orientation, graphene)
! prep particle
tfun = ctf(params%smpd, 200., 0.0, 0.5)
call vol_pad%new([params%boxpd, params%boxpd, params%boxpd], params%smpd)
call particle_vol%new([params%box,params%box,params%box],params%smpd)
call particle%new([params%boxpd,params%boxpd,1],params%smpd)
call img%new([params%box,params%box,1],params%smpd)
call particle_vol%read(particle_fname)
call particle_vol%pad(vol_pad)
call particle_vol%kill
call del_file(particle_fname)
call vol_pad%fft
call vol_pad%expand_cmat(params%alpha)
do i=1,params%nptcls
    call progress(i,params%nptcls)
    ! zero images
    particle = cmplx(0.,0.)
    img = 0.
    ! extract ori
    call spiral%set(i,'dfx',0.05+(ran3()-0.5)/1000.)
    call spiral%get_ori(i, orientation)
    ! project vol
    call vol_pad%fproject(orientation, particle)
    ! shift
    x = 20.*cos(real(i-1)/real(params%nptcls)*PI)        +(ran3()-0.5)/2.
    y = 15.*cos(real(i-1)/real(params%nptcls)*PI+PI*0.25)+(ran3()-0.5)/2.
    call spiral%set(i,'x',x)
    call spiral%set(i,'y',y)
    call particle%shift([x,y,0.])
    ! add
    call particle%add(graphene)
    ! simulate
    call simimg(particle, orientation, tfun, params%ctf, params%snr, snr_pink, snr_detector, params%bfac)
    call particle%ifft
    ! clip & write
    call particle%clip(img)
    call img%write(params%outstk, i)
end do
call spiral%write('trajectory.txt')
end program simple_test_simnano

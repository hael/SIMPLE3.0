!==Program simple_distr_exec
!
! <simple_distr_exec/begin> executes the parallel (or distributed workflows) of SIMPLE <simple_distr_exec/end>
!
! The code is distributed with the hope that it will be useful, but WITHOUT ANY WARRANTY.
! Redistribution and modification is regulated by the GNU General Public License.
! Authors: Cyril Reboul & Hans Elmlund 2016
!
program simple_distr_exec
use simple_defs  
use simple_cmdline, only: cmdline
use simple_strings, only: str_has_substr
use simple_jiffys,  only: cmdline_err
use simple_commander_distr_wflows
use simple_commander_hlev_wflows
implicit none

! DISTRIBUTED COMMANDERS
type(unblur_movies_distr_commander)      :: xunblur_movies_distr
type(unblur_tomo_movies_distr_commander) :: xunblur_tomo_movies_distr
type(ctffind_distr_commander)            :: xctffind_distr
type(shellweight3D_distr_commander)      :: xshellweight3D_distr
type(recvol_distr_commander)             :: xrecvol_distr
type(prime3D_init_distr_commander)       :: xprime3D_init_distr
type(prime3D_distr_commander)            :: xprime3D_distr
type(prime2D_init_distr_commander)       :: xprime2D_init_distr
type(prime2D_distr_commander)            :: xprime2D_distr
type(find_nnimgs_distr_commander)        :: xfind_nnimgs_distr
type(ini3D_from_cavgs_commander)         :: xini3D_from_cavgs

! OTHER DECLARATIONS
integer, parameter    :: MAXNKEYS=100, KEYLEN=32
character(len=KEYLEN) :: keys_required(MAXNKEYS)='', keys_optional(MAXNKEYS)=''
character(len=STDLEN) :: arg, prg, entire_line
type(cmdline)         :: cline
integer               :: cmdstat, cmdlen, pos
call get_command_argument(1, arg, cmdlen, cmdstat)
call get_command(entire_line)
pos = index(arg, '=') ! position of '='
call cmdline_err( cmdstat, cmdlen, arg, pos )
prg = arg(pos+1:) ! this is the program name
if( str_has_substr(prg, 'simple_') ) stop 'giving program names with simple_* prefix is depreciated'
select case(prg)

    ! UNBLUR_MOVIES

    case( 'unblur_movies' )
        !==Program unblur_movies
        !
        ! <unblur_movies/begin> is a program for movie alignment or unblurring.
        ! Input is a textfile with absolute paths to movie files in addition to a few obvious input
        ! parameters. <unblur_movies/end>
        !
        ! set required keys
        keys_required(1)  = 'filetab'
        keys_required(2)  = 'smpd'
        keys_required(3)  = 'nthr'
        keys_required(4)  = 'nparts'
        ! set optional keys
        keys_optional(1)  = 'ncunits'
        keys_optional(2)  = 'fbody'
        keys_optional(3)  = 'lpstart'
        keys_optional(4)  = 'lpstop'
        keys_optional(5)  = 'trs'
        keys_optional(6)  = 'exp_time'
        keys_optional(7)  = 'dose_rate'
        keys_optional(8)  = 'kv'
        keys_optional(9)  = 'pspecsz'
        keys_optional(10) = 'numlen'
        keys_optional(11) = 'startit'
        keys_optional(12) = 'scale'
        keys_optional(13) = 'frameavg'
        ! parse command line
        call cline%parse(keys_required(:4), keys_optional(:13))
        ! set defaults
        if( .not. cline%defined('trs')     ) call cline%set('trs',      5.)
        if( .not. cline%defined('lpstart') ) call cline%set('lpstart', 15.)
        if( .not. cline%defined('lpstop')  ) call cline%set('lpstop',   8.)
        ! execute
        call xunblur_movies_distr%execute(cline)
    case( 'unblur_tomo_movies' )
        !==Program unblur_movies
        !
        ! <unblur_tomo_movies/begin> is a program for movie alignment or unblurring of tomographic movies.
        ! Input is a textfile with absolute paths to movie files in addition to a few obvious input
        ! parameters. <unblur_movies/end>
        !
        ! set required keys
        keys_required(1)  = 'tomoseries'
        keys_required(2)  = 'exp_doc'
        keys_required(3)  = 'smpd'
        keys_required(4)  = 'nthr'
        keys_required(5)  = 'nparts'
        ! set optional keys
        keys_optional(1)  = 'ncunits'
        keys_optional(2)  = 'lpstart'
        keys_optional(3)  = 'lpstop'
        keys_optional(4)  = 'trs'
        keys_optional(5)  = 'kv'
        keys_optional(6)  = 'pspecsz'
        keys_optional(7)  = 'numlen'
        keys_optional(8)  = 'startit'
        keys_optional(9)  = 'scale'
        keys_optional(10) = 'frameavg'
        ! parse command line
        call cline%parse(keys_required(:5), keys_optional(:9))
        ! set defaults
        if( .not. cline%defined('trs')     ) call cline%set('trs',      5.)
        if( .not. cline%defined('lpstart') ) call cline%set('lpstart', 15.)
        if( .not. cline%defined('lpstop')  ) call cline%set('lpstop',   8.)
        if( .not. cline%defined('tomo')    ) call cline%set('tomo',  'yes')
        ! execute
        call xunblur_tomo_movies_distr%execute(cline)
    case( 'ctffind' )
        !==Program ctffind
        !
        ! <ctffind/begin> is a wrapper program for CTFFIND4 (Grigorieff lab) <ctffind/end> 
        !
        ! set required keys
        keys_required(1) = 'filetab'
        keys_required(2) = 'smpd'
        keys_required(3) = 'kv'
        keys_required(4) = 'cs'
        keys_required(5) = 'fraca'
        keys_required(6) = 'nthr'
        keys_required(7) = 'nparts'
        ! set optional keys
        keys_optional(1) = 'ncunits'
        keys_optional(2) = 'pspecsz'
        keys_optional(3) = 'hp'
        keys_optional(4) = 'lp'
        keys_optional(5) = 'dfmin'
        keys_optional(6) = 'dfmax'
        keys_optional(7) = 'astigstep'
        keys_optional(8) = 'expastig'
        keys_optional(9) = 'phaseplate'
        ! parse command line
        call cline%parse(keys_required(:7), keys_optional(:8))
        ! set defaults
        if( .not. cline%defined('pspecsz') ) call cline%set('pspecsz', 1024.)
        if( .not. cline%defined('hp')      ) call cline%set('hp',        30.)
        if( .not. cline%defined('lp')      ) call cline%set('lp',         5.)
        ! execute
        call xctffind_distr%execute(cline)

    ! PRIME3D

    case('shellweight3D')
        !==Program shellweight3D
        !
        ! <shellweight3D/begin> is a program for calculating the shell-by-shell resolution weights in a global sense, so that 
        ! particles that do contribute with higher resolution information (as measure by the FRC) are given the appropriate 
        ! weight. <shellweight3D/end>
        !
        ! set required keys     
        keys_required(1) = 'stk'
        keys_required(2) = 'vol1'
        keys_required(3) = 'smpd'
        keys_required(4) = 'msk' 
        keys_required(5) = 'oritab'
        keys_required(6) = 'ctf'
        keys_required(7) = 'nthr'
        keys_required(8) = 'nparts'
        ! set optional keys
        keys_optional(1) = 'ncunits'
        keys_optional(2) = 'deftab'
        keys_optional(3) = 'automsk'
        keys_optional(4) = 'mw'
        keys_optional(5) = 'amsklp'
        keys_optional(6) = 'edge'
        keys_optional(7) = 'binwidth'
        keys_optional(8) = 'inner'
        keys_optional(9) = 'width'        
        ! parse command line
        call cline%parse(keys_required(:8), keys_optional(:9))
        ! execute
        call xshellweight3D_distr%execute(cline)
        ! set defaults
        call cline%set('outfile', 'shellweight3D_doc.txt')
    case('prime3D_init')
        !==Program prime3D_init
        !
        ! <prime3D_init/begin> is a program for generating a random initial model for initialisation of PRIME3D.
        ! If the data set is large (>5000 images), generating a random model can be slow. To speedup, set 
        ! nran to some smaller number, resulting in nran images selected randomly for 
        ! reconstruction. <prime3D_init/end> 
        !
        ! set required keys
        keys_required(1) = 'stk'
        keys_required(2) = 'smpd'
        keys_required(3) = 'msk'
        keys_required(4) = 'ctf'
        keys_required(5) = 'pgrp'
        keys_required(6) = 'nthr'
        keys_required(7) = 'nparts'
        ! set optional keys
        keys_optional(1) = 'ncunits'
        keys_optional(2) = 'deftab'
        keys_optional(3) = 'lp'
        keys_optional(4) = 'inner'
        keys_optional(5) = 'width'
        keys_optional(6) = 'nspace'
        keys_optional(7) = 'nran'
        keys_optional(8) = 'npeaks'
        keys_optional(9) = 'xfel'        
        ! parse command line
        call cline%parse(keys_required(:7), keys_optional(:9))
        ! set defaults
        if( .not. cline%defined('nspace') ) call cline%set('nspace', 1000.)
        ! execute
        call xprime3D_init_distr%execute( cline )
    case('prime3D')
        !==Program prime3D
        !
        ! <prime3D/begin> is an ab inito reconstruction/refinement program based on probabilistic
        ! projection matching. PRIME is short for PRobabilistic Initial 3D Model generation for Single-
        ! particle cryo-Electron microscopy. Do not search the origin shifts initially, when the model is 
        ! of very low quality. If your images are far off centre, use stackops with option
        ! shalgn=yes instead to shiftalign the images beforehand (the algorithm implemented is the 
        ! same as EMANs cenalignint program). We recommend running the first round of PRIME with 
        ! the default dynamic resolution stepping dynlp=yes. The dynlp option implements 
        ! a heuristic resolution weighting/update scheme. The initial low-pass limit is set so that each
        ! image receives ten nonzero orientation weights. When quasi-convergence has been reached, the limit 
        ! is updated one Fourier index at the time until PRIME reaches the condition where six nonzero 
        ! orientation weights are assigned to each image. FSC-based filtering is unfortunately not possible
        ! to do in the ab initio reconstruction step, because when the orientations are mostly random, the 
        ! FSC overestimates the resolution. Once the initial model has converged, we recommend start searching 
        ! the shifts (by setting trs to some nonzero value) and applying the FSC for resolution-
        ! weighting (by setting eo=yes). In order to be able to use Wiener restoration, give the 
        ! ctf flag on the command line to indicate what has been done to the images. You then also 
        ! need to input CTF parameters, for example via deftab=defocus_values.txt. Remember that the 
        ! defocus values should be given in microns and the astigmatism angle in degrees (one row of the file
        ! defocus_values.txt may look like: dfx=3.5 dfy=3.3 angast=20.0).
        ! Note that we do not assume any point-group symmetry in the initial runs. However, the 
        ! symsrch program can be used to align the 3D reconstruction to its symmetry axis so that 
        ! future searches can be restricted to the asymmetric unit. Less commonly used and less obvious input 
        ! parameters are nspace, which  controls the number of reference projections, 
        ! amsklp, which controls the low-pass limit used in the automask routine, maxits, 
        ! which controls the maximum number of iterations executed, pgrp, which controls the point-
        ! group symmetry, assuming that the starting volume is aligned to its principal symmetry axis, 
        ! edge, which controls the size of the softening edge in the automask routine. <prime3D/end>
        !
        ! set required keys
        keys_required(1)  = 'stk'
        keys_required(2)  = 'smpd'
        keys_required(3)  = 'msk'
        keys_required(4)  = 'ctf'
        keys_required(5)  = 'pgrp'
        keys_required(6)  = 'nthr'
        keys_required(7)  = 'nparts'
        ! set optional keys
        keys_optional(1)  = 'ncunits'
        keys_optional(2)  = 'deftab'
        keys_optional(3)  = 'vol2'
        keys_optional(4)  = 'oritab'
        keys_optional(5)  = 'trs'
        keys_optional(6)  = 'hp'
        keys_optional(7)  = 'lp'
        keys_optional(8)  = 'dynlp'
        keys_optional(9)  = 'lpstart'
        keys_optional(10) = 'lpstop'
        keys_optional(11) = 'eo'
        keys_optional(12) = 'refine'
        keys_optional(13) = 'frac'
        keys_optional(14) = 'automsk'
        keys_optional(15) = 'mw'
        keys_optional(16) = 'amsklp'
        keys_optional(17) = 'edge'
        keys_optional(18) = 'binwidth'
        keys_optional(19) = 'inner'
        keys_optional(20) = 'width'
        keys_optional(21) = 'nspace'
        keys_optional(22) = 'nstates'
        keys_optional(23) = 'npeaks'
        keys_optional(24) = 'startit'
        keys_optional(25) = 'maxits'
        keys_optional(26) = 'shbarrier'
        keys_optional(27) = 'noise'
        keys_optional(28) = 'xfel'
        keys_optional(29) = 'nnn'
        keys_optional(30) = 'shellw'  
        ! parse command line
        call cline%parse(keys_required(:7), keys_optional(:30))
        ! set defaults
        if( .not. cline%defined('nspace')                  ) call cline%set('nspace', 1000.)
        if( cline%defined('lp') .or. cline%defined('find') ) call cline%set('dynlp',   'no')
        if( .not. cline%defined('refine')                  ) call cline%set('refine',  'no')
        if( .not. cline%defined('eo') )then
            call cline%set('eo', 'no')
        else
            if( cline%get_carg('eo').eq.'yes' )call cline%set('dynlp','no')
        endif
        ! execute
        call xprime3D_distr%execute(cline)

    ! PRIME2D

    case( 'prime2D_init' )
        !==Program simple_prime2D_init
        !
        ! <prime2D/begin> is a reference-free 2D alignment/clustering algorithm adopted from the prime3D 
        ! probabilistic  ab initio 3D reconstruction algorithm. Do not search the origin shifts initially,
        ! when the cluster centers are of low quality. If your images are far off centre, use XXX
        ! instead to shiftalign the images beforehand. <prime2D/end>
        !
        ! set required keys
        keys_required(1) = 'stk'
        keys_required(2) = 'smpd'
        keys_required(3) = 'ncls'
        keys_required(4) = 'ctf'
        keys_required(5) = 'nthr'
        keys_required(6) = 'nparts'
        ! set optional keys
        keys_optional(1) = 'ncunits'
        keys_optional(2) = 'oritab'
        keys_optional(3) = 'deftab'
        keys_optional(4) = 'filwidth'
        keys_optional(5) = 'srch_inpl'        
        ! parse command line
        call cline%parse(keys_required(:6), keys_optional(:5))
        ! execute
        call xprime2D_init_distr%execute(cline)
    case( 'prime2D' )
        !==Program simple_prime2D
        !
        ! <prime2D/begin> is a reference-free 2D alignment/clustering algorithm adopted from the prime3D 
        ! probabilistic  ab initio 3D reconstruction algorithm. Do not search the origin shifts initially,
        ! when the cluster centers are of low quality. If your images are far off centre, use XXX
        ! instead to shiftalign the images beforehand. <prime2D/end>
        !
        ! set required keys
        keys_required(1)  = 'stk'
        keys_required(2)  = 'smpd'
        keys_required(3)  = 'msk'
        keys_required(4)  = 'ncls'
        keys_required(5)  = 'ctf'
        keys_required(6)  = 'nparts'
        keys_required(7)  = 'nthr'
        ! set optional keys
        keys_optional(1)  = 'ncunits'
        keys_optional(2)  = 'deftab'
        keys_optional(3)  = 'refine'
        keys_optional(4)  = 'refs'
        keys_optional(5)  = 'oritab'
        keys_optional(6)  = 'hp'
        keys_optional(7)  = 'lp'
        keys_optional(8)  = 'trs'
        keys_optional(9)  = 'automsk'
        keys_optional(10) = 'amsklp'
        keys_optional(11) = 'inner'
        keys_optional(12) = 'width'
        keys_optional(13) = 'startit'
        keys_optional(14) = 'maxits'
        keys_optional(15) = 'filwidth'
        keys_optional(16) = 'srch_inpl'
        keys_optional(17) = 'nnn'
        keys_optional(18) = 'minp'        
        ! parse command line
        call cline%parse(keys_required(:7), keys_optional(:18))
        ! set defaults
        if( .not. cline%defined('lp')     ) call cline%set('lp',     20.)
        if( .not. cline%defined('eo')     ) call cline%set('eo',    'no')
        if( .not. cline%defined('amsklp') ) call cline%set('amsklp', 25.)
        if( .not. cline%defined('edge')   ) call cline%set('edge',   20.)
        ! execute
        call xprime2D_distr%execute(cline)
    case( 'find_nnimgs' )
        !==Program find_nnimgs
        !
        ! <find_nnimgs/begin> is a program for cidentifying the nnn nearest neighbor
        ! images for each image in the inputted stack. <find_nnimgs/end>
        !
        ! set required keys
        keys_required(1) = 'stk'
        keys_required(2) = 'smpd'
        keys_required(3) = 'msk'
        keys_required(4) = 'nthr'
        keys_required(5) = 'nparts'
        ! set optional keys
        keys_optional(1) = 'ncunits'
        keys_optional(2) = 'nnn'
        keys_optional(3) = 'lp'
        keys_optional(4) = 'hp'
        ! parse command line
        call cline%parse(keys_required(:5), keys_optional(:4))
        ! execute
        call xfind_nnimgs_distr%execute(cline)
    case( 'recvol' )
        !==Program recvol
        !
        ! <recvol/begin>  <recvol/end> 
        !
        ! set required keys
        keys_required(1) = 'stk'
        keys_required(2) = 'smpd'
        keys_required(3) = 'oritab'
        keys_required(4) = 'msk'
        keys_required(5) = 'ctf'
        keys_required(6) = 'pgrp'
        keys_required(7) = 'nthr'
        keys_required(8) = 'nparts'
        ! set optional keys
        keys_optional(1) = 'ncunits'
        keys_optional(2) = 'eo'
        keys_optional(3) = 'deftab'
        keys_optional(4) = 'frac'
        keys_optional(5) = 'mw'
        keys_optional(6) = 'mul'
        keys_optional(7) = 'state'
        keys_optional(8) = 'shellw'
        keys_optional(9) = 'vol1'        
        ! parse command line
        call cline%parse(keys_required(:8), keys_optional(:9))
        ! set defaults
        if( .not. cline%defined('trs') ) call cline%set('trs', 5.) ! to assure that shifts are being used
        if( .not. cline%defined('eo')  ) call cline%set('eo', 'no')
        ! execute
        call xrecvol_distr%execute( cline )

    ! HIGH-LEVEL DISTRIBUTED WORKFLOWS

    case( 'ini3D_from_cavgs' )
        !==Program ini3D_from_cavgs
        !
        ! <ini3D_from_cavgs/begin>  <ini3D_from_cavgs/end> 
        !
        ! set required keys
        keys_required(1) = 'stk'
        keys_required(2) = 'smpd'
        keys_required(3) = 'msk'
        keys_required(4) = 'pgrp'
        keys_required(5) = 'nthr'
        keys_required(6) = 'nparts'
        ! set optional keys
        keys_optional(1) = 'ncunits'
        keys_optional(2) = 'nthr_master'
        ! parse command line
        call cline%parse(keys_required(:6), keys_optional(:2))
        ! execute
        call xini3D_from_cavgs%execute( cline )
    case DEFAULT
        write(*,'(a,a)') 'program key (prg) is: ', trim(prg)
        stop 'unsupported program'
    end select
end program simple_distr_exec

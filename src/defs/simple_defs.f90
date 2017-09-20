module simple_defs
use, intrinsic :: iso_c_binding
use, intrinsic :: iso_fortran_env, only: &
stderr=>ERROR_UNIT,&
stdout=>OUTPUT_UNIT,&
stdin=>INPUT_UNIT
implicit none
integer,  parameter :: MAXS         = 99   !< maximum number of states
integer,  parameter :: STDLEN       = 256  !< standard string length
integer,  parameter :: LONGSTRLEN   = 2048 !< longer string length
integer,  parameter :: short        = selected_int_kind(4)
integer,  parameter :: long         = selected_int_kind(9)
integer,  parameter :: longer       = selected_int_kind(16)
integer,  parameter :: I4B          = selected_int_kind(9)
integer,  parameter :: I2B          = selected_int_kind(4)
integer,  parameter :: I1B          = selected_int_kind(2)
integer,  parameter :: SP           = kind(1.0)
integer,  parameter :: DP           = kind(1.0d0)
integer,  parameter :: DOUBLE       = kind(1.0d0)
integer,  parameter :: SPC          = kind((1.0,1.0))
integer,  parameter :: DPC          = kind((1.0d0,1.0d0))
integer,  parameter :: LGT          = kind(.true.)
integer,  parameter :: LINE_MAX_LEN = 8192
real(sp), parameter :: PI           = acos(-1.)
real(dp), parameter :: DPI          = acos(-1.d0)
real(sp), parameter :: PIO2         = acos(-1.)/2.
real(sp), parameter :: TWOPI        = 2.*acos(-1.)
real(sp), parameter :: DTWOPI       = 2.d0*acos(-1.d0)
real(sp), parameter :: FOURPI       = 4.*acos(-1.)
real(sp), parameter :: SQRT2        = sqrt(2.)
real(sp), parameter :: EUL          = 0.5772156649015328606065120900824024310422_sp
real(sp), parameter :: TINY         = 1e-10
real(dp), parameter :: DTINY        = 1e-10
real(sp), parameter :: SMALL        = 1e-6
real(sp), parameter :: FTOL         = 1e-4
real(dp), parameter :: DSMALL       = 1e-6
real(dp), parameter :: PISQR        = PI*PI
real(sp), parameter :: ATHRES_LIM   = 5.

! plan for the CTF
type :: ctfplan
    character(len=STDLEN) :: mode=''                 !< astig/noastig
    character(len=STDLEN) :: flag=''                 !< flag: <mul|flip|no>
end type ctfplan

! constants for picker
real,    parameter :: PICKER_SHRINK        = 4.      !< picker shrink factor
real,    parameter :: PICKER_SHRINK_REFINE = 2.      !< picker shrink factor, peak refine step
integer, parameter :: PICKER_OFFSET        = 3       !< picker offset for grid search

! constants for masking/interpolation
real, parameter :: COSMSKHALFWIDTH         = 3.0     !< spherical soft masking
real, parameter :: KBWINSZ                 = 1.5     !< interpolation window size
real, parameter :: KBALPHA                 = 2.0     !< interpolation alpha (smoothing constant)
              
! real constants that control search and convergence
real, parameter :: FRAC_SH_LIM             = 80.0    !< at what frac to turn on the shift search
real, parameter :: FRAC_INTERPOL           = 60.0    !< at what frac to turn on the gridding interpolation (2D)
real, parameter :: EXTRINITHRESH           = 0.5     !< initial randomization threshold for extremal search
real, parameter :: EXTRTHRESH_CONST        = 0.2     !< threshold for factorial decay in extremal search
real, parameter :: LP2SMPDFAC              = 0.4125  !< low-pass limit scaling constant
real, parameter :: NPEAKSATHRES            = 12.0    !< angular threshold for determining npeaks (PRIME3D)

! integer #/threshold constants
integer, parameter :: LPLIM1ITERBOUND      = 5       !< # iteration bound lplim stage 1 (PRIME2D)
integer, parameter :: LPLIM3ITERBOUND      = 7       !< # iteration bound lplim stage 2 (PRIME2D)
integer, parameter :: MINCLSPOPLIM         = 5       !< limit for adaptive cluster splitting/spreading (PRIME2D)
integer, parameter :: SPECWMINPOP          = 2000    !< minimum population for spectral weighting (PRIME2D/3D)
integer, parameter :: GRIDNPEAKS           = 3       !< # peaks to consider in angular grid search (PRIME3D)
integer, parameter :: MAXNPEAKS            = 40      !< maximum # peaks to be assigned weights (PRIME3D)
integer, parameter :: NSPACE_BALANCE       = 600     !< # projection directions for the balancing constraint (PRIME3D)
integer, parameter :: HETNREPEATS          = 1       !< # repeats het_ensemble
integer, parameter :: GRIDCORR_MAXITS      = 5       !< # iterations for reconstruction gridding correction

! constants for SHC inplane grid search
real,    parameter :: SHC_INPL_TRSHWDTH    = 2.0     !< shift search halfwidht (pixels)
real,    parameter :: SHC_INPL_TRSSTEPSZ   = 0.2     !< shift search step size (pixels)
integer, parameter :: SHC_INPL_INPLHWDTH   = 2       !< in-plane rotation halfwidth (rotation index)

! global  variables
integer(kind=c_int)       :: nthr_glob               !< number of threads global variable
logical                   :: l_distr_exec_glob       !< global distributed execution flag
character(len=LONGSTRLEN) :: cmdline_glob            !< global command line string

! stack part related and file format constants
character(len=32),     parameter :: STKPARTSDIR         = 'stack_parts'
character(len=STDLEN), parameter :: STKPARTFBODY        = trim(STKPARTSDIR)//'/stack_part'
character(len=STDLEN), parameter :: STKPARTFBODY_SC     = trim(STKPARTSDIR)//'/stack_part_sc'
character(len=4),      parameter :: METADATEXT          = '.txt'
character(len=1),      parameter :: DEFAULT_FILE_FORMAT = 'M'

! SNHC-related global constants, PRIME3D, refine=snhc
character(len=32), parameter :: SNHCDOC   = 'snhc_oris'//METADATEXT    
character(len=32), parameter :: SNHCVOL   = 'snhc_recvol_state' 
integer,           parameter :: SZSN_INIT = 5               
integer,           parameter :: SZSN_STEP = 3                  
integer,           parameter :: SZSN_MAX  = 20 

! precision constants
#ifndef IMAGE_SINGLE_PRECISION
integer, parameter :: img_kind = DP
#else
integer, parameter :: img_kind = SP
#endif
integer, parameter :: fp_kind = DP

! debugging and print verbosity flags
#ifdef _DEBUG
logical :: global_debug   = .true.  !< global debugging flag
logical :: global_verbose = .true.  !< global flag for verbosity set to TRUE in debug mode
#else
logical :: global_debug   = .false. !< global flag for debugging disabled
#ifdef VERBOSE
logical :: global_verbose = .true.  !< global flag for verbosity TRUE with VERBOSE compilation flag
#else
logical :: global_verbose = .false. !< global flag for verbosity FALSE by default
#endif
#endif
logical :: global_warn    = .false. !< warning flag

! append SIMPLE_VERSION and SIMPLE_GIT_VERSION strings to simple_defs
#include "SimpleGitVersion.h"

end module simple_defs

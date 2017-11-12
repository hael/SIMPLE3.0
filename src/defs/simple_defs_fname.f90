module simple_defs_fname
! PRIME2D
character(len=11), parameter :: PRIME2D_ITER_FBODY   = 'prime2Ddoc_'
character(len=10), parameter :: CAVGS_ITER_FBODY     = 'cavgs_iter'
! PRIME2D STREAM
character(len=10), parameter :: SCSTK_DIR            = 'stacks_sc/'
! PRIME3D
character(len=11), parameter :: PRIME3D_ITER_FBODY   = 'prime3Ddoc_'
character(len=12), parameter :: VOL_FBODY            = 'recvol_state'
! PRIME COMMON
character(len=9),  parameter :: FRCS_ITER_FBODY      = 'frcs_iter'
character(len=8),  parameter :: ALGN_FBODY           = 'algndoc_'
! EXTRACT
character(len=11), parameter :: EXTRACT_STK_FBODY    = 'ptcls_from_'
character(len=20), parameter :: EXTRACT_PARAMS_FBODY = 'extract_params_'
! SUFFIXES
character(len=3),  parameter :: SCALE_SUFFIX         = '_sc'
character(len=6),  parameter :: PREP4CGRID_SUFFIX    = '_cgrid'
! MISC
character(len=10), parameter :: STDERROUT_DIR        = 'stderrout/'
end module simple_defs_fname
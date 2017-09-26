
#if defined(HALT)
#else
# define HALT(X) call simple_stop (X,__FILENAME__, __LINE__)
#endif

#if defined(allocchk)
#else
#define allocchk( X ) call alloc_errchk (X, alloc_stat, __FILENAME__, __LINE__)
#endif
    use, intrinsic :: iso_fortran_env, only: stderr=>ERROR_UNIT, stdout=>OUTPUT_UNIT, stdin=>INPUT_UNIT
    ! use ISO_C_BINDING
    use simple_defs
    use simple_jiffys
    use simple_strings
    use simple_syslib
    use simple_fileio
    use simple_math
    use simple_rnd
    use simple_stat
    use simple_combinatorics
    use simple_magic_boxes
    use simple_hash,    only: hash
    use simple_sll,     only: sll
    use simple_chash,   only: chash
    use simple_arr,     only: arr
    use simple_imghead, only: find_ldim_nptcls
    

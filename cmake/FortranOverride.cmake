# This overrides the default CMake Debug and Release compiler options.
# The user can still specify different options by setting the
# CMAKE_Fortran_FLAGS_[RELEASE,DEBUG] variables (on the command line or in the
# CMakeList.txt). This files serves as better CMake defaults and should only be
# modified if the default values are to be changed. Project specific compiler
# flags should be set in the CMakeList.txt by setting the CMAKE_Fortran_FLAGS_*
# variables.

# Override CMakeDetermineFortranCompiler default fortran of f95 
if(NOT $ENV{FC} STREQUAL "")
  set(CMAKE_Fortran_COMPILER_NAMES $ENV{FC})
else()
  set(CMAKE_Fortran_COMPILER_NAMES gfortran)
  set(ENV{FC} "gfortran")
endif()
# Override preprocessor in CMakeDetermineCompiler default cpp

if(NOT $ENV{CPP} STREQUAL "")
  set(CMAKE_CPP_COMPILER_NAMES $ENV{CPP})
else()
  find_file (CMAKE_CPP_COMPILER_NAMES
    NAMES cpp- cpp-4.9 cpp-5 cpp-6 cpp5 cpp6 cpp
    PATHS /usr/local/bin /opt/local/bin /sw/bin /usr/bin
    #  [PATH_SUFFIXES suffix1 [suffix2 ...]]
    DOC "GNU cpp preprocessor "
    #  [NO_DEFAULT_PATH]
    #  [NO_CMAKE_ENVIRONMENT_PATH]
    #  [NO_CMAKE_PATH]
    # NO_SYSTEM_ENVIRONMENT_PATH
    #  [NO_CMAKE_SYSTEM_PATH]
    #  [CMAKE_FIND_ROOT_PATH_BOTH |
    #   ONLY_CMAKE_FIND_ROOT_PATH |
    #   NO_CMAKE_FIND_ROOT_PATH]
    )
  if(NOT EXISTS ${CMAKE_CPP_COMPILER_NAMES})
    set(CMAKE_CPP_COMPILER_NAMES cpp-5)
  endif()
  set(ENV{CPP} ${CMAKE_CPP_COMPILER_NAMES})
endif()
enable_language(Fortran C)
include(CMakeDetermineFortranCompiler)
include(CMakeDetermineCompiler)


# Try to identify the ABI and configure it into CMakeFortranCompiler.cmake
include(${CMAKE_ROOT}/Modules/CMakeDetermineCompilerABI.cmake)
CMAKE_DETERMINE_COMPILER_ABI(Fortran ${CMAKE_ROOT}/Modules/CMakeFortranCompilerABI.F)

# Test for Fortran 2008 support by using a F2008 specific construct.
if(NOT DEFINED CMAKE_Fortran_COMPILER_SUPPORTS_F08)
  message(STATUS "Checking whether ${CMAKE_Fortran_COMPILER} supports Fortran 2008")
  file(WRITE ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeTmp/testFortranCompilerF08.f90 "
! BLOCK should be rejected without F2008.
PROGRAM main
  IMPLICIT NONE
  BLOCK
    INTEGER :: i
  END BLOCK
END PROGRAM 
")
  try_compile(CMAKE_Fortran_COMPILER_SUPPORTS_F08 ${CMAKE_BINARY_DIR}
    ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeTmp/testFortranCompilerF08.f90
    OUTPUT_VARIABLE OUTPUT)
  if(CMAKE_Fortran_COMPILER_SUPPORTS_F08)
    message(STATUS "Checking whether ${CMAKE_Fortran_COMPILER} supports Fortran 2008 -- yes")
    file(APPEND ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeOutput.log
      "Determining if the Fortran compiler supports Fortran 2008 passed with "
      "the following output:\n${OUTPUT}\n\n")
    set(CMAKE_Fortran_COMPILER_SUPPORTS_F08 1)
  else()
    message(STATUS "Checking whether ${CMAKE_Fortran_COMPILER} supports Fortran 2008 -- no")
    file(APPEND ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeError.log
      "Determining if the Fortran compiler supports Fortran 2008 failed with "
      "the following output:\n${OUTPUT}\n\n")
    set(CMAKE_Fortran_COMPILER_SUPPORTS_F08 0)
  endif()
  unset(CMAKE_Fortran_COMPILER_SUPPORTS_F08 CACHE)
endif()


# Test for Fortran preprocessor support for variadic macros
if(NOT DEFINED CMAKE_Fortran_COMPILER_SUPPORTS_VARIADIC)
  message(STATUS "Checking whether ${CMAKE_Fortran_COMPILER} supports variadic macros")
  file(WRITE ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeTmp/testFortranCPPCompilerVariadic.f90 "
#define c99_count(...)    _c99_count1 ( , ##__VA_ARGS__)/* */
#define _c99_count1(...)  _c99_count2 (__VA_ARGS__,10,9,8,7,6,5,4,3,2,1,0)
#define _c99_count2(_,x0,x1,x2,x3,x4,x5,x6,x7,x8,x9,n,...) n
program dummyprog
 integer i
 integer,parameter :: nv=c99_count (__VA_ARGS__);
 character(255)::p_tokens= #__VA_ARGS__ ;
 i = 5
end program dummyprog
")
  try_compile(CMAKE_Fortran_COMPILER_SUPPORTS_VARIADIC ${CMAKE_BINARY_DIR}
    ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeTmp/testFortranCPPCompilerVariadic.f90
    OUTPUT_VARIABLE OUTPUT)
  if(CMAKE_Fortran_COMPILER_SUPPORTS_VARIADIC)
    message(STATUS "Checking whether ${CMAKE_Fortran_COMPILER} supports variadic macros -- yes")
    file(APPEND ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeOutput.log
      "Determining if the Fortran compiler supports variadic macros passed with "
      "the following output:\n${OUTPUT}\n\n")
    set(CMAKE_Fortran_COMPILER_SUPPORTS_VARIADIC 1)
  else()
    message(STATUS "Checking whether ${CMAKE_Fortran_COMPILER} supports Fortran variadic macros -- no")
    file(APPEND ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeError.log
      "Determining if the Fortran compiler supports variadic macros failed with "
      "the following output:\n${OUTPUT}\n\n")
    set(CMAKE_Fortran_COMPILER_SUPPORTS_VARIADIC 0)
  endif()
  unset(CMAKE_Fortran_COMPILER_SUPPORTS_VARIADIC CACHE)
endif()





# If user specifies the build type, use theirs, otherwise use release
if (NOT DEFINED CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RELEASE CACHE STRING "")
endif()

# Disable in-source builds to prevent source tree corruption.
if(" ${CMAKE_SOURCE_DIR}" STREQUAL " ${CMAKE_BINARY_DIR}")
  message(FATAL_ERROR "
FATAL: In-source builds are not allowed.
       You should create separate directory for build files.
")
endif()


# Look at system to see what if any options are available because
# of build environment
#include(SystemDefines)

# Turn on all compiler warnings
#include(EnableAllWarnings)

# Bring in helper functions for dealing with CACHE INTERNAL variables
include(CacheInternalHelpers)

# We want to create static libraries
set(BUILD_SHARED_LIBS OFF)
include(GNUInstallDirs)
if("${CMAKE_INSTALL_PREFIX}" STREQUAL "/usr/local")
  set(CMAKE_INSTALL_PREFIX ${CMAKE_BINARY_DIR})
endif()
# There is some bug where -march=native doesn't work on Mac
IF(APPLE)
  SET(GNUNATIVE "-mtune=native")
ELSE()
  SET(GNUNATIVE "-march=native")
ENDIF(APPLE)
###########  SETTING UP PREPROCESSOR ################
#include(PlatformDefines)
message( STATUS "CMAKE_Fortran_COMPILER_ID: ${CMAKE_Fortran_COMPILER_ID}")
if (CMAKE_Fortran_COMPILER_ID STREQUAL "GNU")
  # gfortran
  set(preproc  "-cpp -P ")                                                                      # preprocessor flags
  set(dialect  "-ffree-form  -fimplicit-none  -ffree-line-length-none -fno-second-underscore")  # language style
  set(warn     "-Wampersand -Wsurprising -Wtabs -Wline-truncation -Winteger-division -Wreal-q-constant ")
  set(forspeed "-O3")                                                                           # optimisation
  set(forpar   "-fopenmp  ")                                                                    # parallel flags
  set(target   "${GNUNATIVE} -fPIC ")                                                           # target platform
  set(common   "${preproc} ${dialect} ${target} -DGNU ")
  set(checks   "-fcheck-array-temporaries -frange-check -fstack-protector -fstack-check -fbounds-check") # checks
  set(warnDebug "-Wall -Wextra -Wimplicit-interface -Wdangling-else ${checks}")                 # extra warning flags
  set(fordebug "-O0 -g -pedantic -fno-inline -fno-f2c -Og -ggdb -fbacktrace  ${warnDebug} ")    # debug flags
  # -O0 -g3 -Warray-bounds -Wcharacter-truncation -Wline-truncation -Wimplicit-interface
  # -Wimplicit-procedure -Wunderflow -Wuninitialized -fcheck=all -fmodule-private -fbacktrace -dump-core -finit-real=nan -ffpe-trap=invalid,zero,overflow
  #
elseif (CMAKE_Fortran_COMPILER_ID STREQUAL "PGI")
  # pgfortran
  set(preproc  "-Mpreprocess ")
  set(dialect  "-Mfreeform -Mstandard -Mallocatable=03 -Mextend -Mnosecond_underscore")
  set(checks   "-Mdclchk -Mchkptr -Mchkstk  -Munixlogical -Mlarge_arrays -Mflushz -Mdaz -Mfpmisalign")
  set(warn     "-Minform=warn -Minfo=all,ftn ${checks}")
  # bounds checking cannot be done in CUDA fortran or OpenACC GPU
  set(fordebug "${warn}  -traceback -gopt -Mneginfo=all,ftn -Mnodwarf -Mpgicoff -traceback -Mprof  ")
  set(forspeed "-O3 " ) # -Munroll -O4  -Mipa=fast -fast -Mcuda=fastmath,unroll -Mvect=nosizelimit,short,simd,sse  ")
  set(forpar   " -mp -acc -Mcuda=cc60") # -Mconcur=bind,allcores -Mcuda=cuda8.0,cc60,flushz,fma
  set(target   " -m64 -fPIC ")
  set(common   "${preproc} ${dialect} ${target}  -DPGI")
  #
  set(FFTWDIR "/usr/local/pgi/src/fftw/")

elseif (CMAKE_Fortran_COMPILER_ID STREQUAL "Intel")
  # ifort
  # set(FC "ifort" CACHE PATH "Intel Fortran compiler")
  set(preproc  "-fpp")
  set(dialect  "-free -implicitnone -std08  -list-line-len=264 -diag-disable 6477  -gen-interfaces  ")
  set(checks   "-check bounds -check uninit -assume buffered_io ") # -mcmodel=medium -shared-intel
  set(warn     "-warn all ")
  set(fordebug "-debug -O0 -ftrapuv -debug all -check all ${warn} -assume byterecl -align sequence  -diag-disable 6477  -gen-interfaces ")
  set(forspeed "-O3 -fp-model fast=2 -inline all -unroll-aggressive ")
  set(forpar   "-qopenmp")
  set(target   "-no-prec-div -static -fPIC")
  set(common   "${preproc} ${dialect} ${checks} ${target} -DINTEL")
  # else()
  #   message(" Fortran compiler not supported. Set FC environment variable")
  set(MKLROOT $ENV{MKLROOT})

endif ()
set(CMAKE_Fortran_FLAGS_RELEASE_INIT "${common} ${forspeed} ${forpar}"  CACHE STRING "Default release flags -- this cannot be edited (see cmake/FortranOverride.cmake) -- Use CMAKE_Fortran_FLAGS_RELEASE instead" FORCE)
set(CMAKE_Fortran_FLAGS_DEBUG_INIT  "${common} ${fordebug} ${forpar} -g"  CACHE STRING "Default debug flags -- this cannot be edited (see cmake/FortranOverride.cmake -- Use CMAKE_Fortran_FLAGS_DEBUG instead)" FORCE)
message( STATUS "CMAKE_Fortran_FLAGS_RELEASE_INIT: ${CMAKE_Fortran_FLAGS_RELEASE_INIT}") 
message( STATUS "CMAKE_Fortran_FLAGS_DEBUG_INIT: ${CMAKE_Fortran_FLAGS_DEBUG_INIT}")
# 
# Make recent cmake not spam about stuff
if(POLICY CMP0063)
  cmake_policy(SET CMP0063 OLD)
endif()
if(POLICY CMP0004)
  cmake_policy(SET CMP0004 OLD)
endif()


## Remove EMAN bin and possible library paths from PATH
set(TMPPATH $ENV{PATH})
string(REGEX REPLACE  "[^:]\+EMAN[2]*/extlib[^:]\+" "" TMPPATH ${TMPPATH})
set(ENV{PATH} ${TMPPATH})

# Make sure the build type is uppercase
string(TOUPPER "${CMAKE_BUILD_TYPE}" BT)

#################################################################
# CONFIGURATION TYPES & BUILD MODE
#################################################################
set(CMAKE_CONFIGURATION_TYPES DEBUG RELEASE RELWITHDEBINFO )
if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE RELEASE CACHE STRING
    "Choose the type of build, options are: NONE DEBUG RELEASE RELWITHDEBINFO"
    FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS NONE DEBUG RELEASE RELWITHDEBINFO)
endif(NOT CMAKE_BUILD_TYPE)

if(BT STREQUAL "RELEASE")
  set(CMAKE_BUILD_TYPE RELEASE CACHE STRING
    "Choose the type of build, options are DEBUG, RELEASE, RELWITHDEBINFO or TESTING."
    FORCE)
elseif(BT STREQUAL "DEBUG")
  set (CMAKE_BUILD_TYPE DEBUG CACHE STRING
    "Choose the type of build, options are DEBUG, RELEASE, RELWITHDEBINFO or TESTING."
    FORCE)
elseif(BT STREQUAL "RELWITHDEBINFO")
  set (CMAKE_BUILD_TYPE RELWITHDEBINFO CACHE STRING
    "Choose the type of build, options are DEBUG, RELEASE, RELWITHDEBINFO  or TESTING."
    FORCE)
elseif(BT STREQUAL "TESTING")
  set (CMAKE_BUILD_TYPE TESTING CACHE STRING
    "Choose the type of build, options are DEBUG, RELEASE, RELWITHDEBINFO or TESTING."
    FORCE)
elseif(NOT BT)
  set(CMAKE_BUILD_TYPE RELEASE CACHE STRING
    "Choose the type of build, options are DEBUG, RELEASE, RELWITHDEBINFO or TESTING."
    FORCE)
  message(STATUS "CMAKE_BUILD_TYPE not given, defaulting to RELEASE")
else()
  message(FATAL_ERROR "CMAKE_BUILD_TYPE not valid, choices are DEBUG, RELEASE, RELWITHDEBINFO or TESTING")
endif(BT STREQUAL "RELEASE")



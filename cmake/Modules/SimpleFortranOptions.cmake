

####################################################################
# Make sure that the default build type is RELEASE if not specified.
####################################################################
include(${CMAKE_MODULE_PATH}/SetCompileFlag.cmake)

# Make sure the build type is uppercase
string(TOUPPER "${CMAKE_BUILD_TYPE}" BT)

if(BT STREQUAL "RELEASE")
  set(CMAKE_BUILD_TYPE RELEASE CACHE STRING
    "Choose the type of build, options are DEBUG, RELEASE, or TESTING."
    FORCE)
elseif(BT STREQUAL "DEBUG")
  set (CMAKE_BUILD_TYPE DEBUG CACHE STRING
    "Choose the type of build, options are DEBUG, RELEASE, or TESTING."
    FORCE)
elseif(BT STREQUAL "TESTING")
  set (CMAKE_BUILD_TYPE TESTING CACHE STRING
    "Choose the type of build, options are DEBUG, RELEASE, or TESTING."
    FORCE)
elseif(NOT BT)
  set(CMAKE_BUILD_TYPE RELEASE CACHE STRING
    "Choose the type of build, options are DEBUG, RELEASE, or TESTING."
    FORCE)
  message(STATUS "CMAKE_BUILD_TYPE not given, defaulting to RELEASE")
else()
  message(FATAL_ERROR "CMAKE_BUILD_TYPE not valid, choices are DEBUG, RELEASE, or TESTING")
endif(BT STREQUAL "RELEASE")


#################################################################
# Setting up options
#################################################################
get_filename_component (Fortran_COMPILER_NAME ${CMAKE_Fortran_COMPILER} NAME)
set(CMAKE_Fortran_SOURCE_FILE_EXTENSIONS ${CMAKE_Fortran_SOURCE_FILE_EXTENSIONS} "f03;F03;f08;F08")
message(STATUS "Fortran compiler: ${Fortran_COMPILER_NAME}")
option(ENABLE_F03STD "To force strict conformance to the Fortran 2003 standard" OFF)
option(ENABLE_HARD_OPTIMIZE "To activate aggressive optimization flags" OFF)
#option(${PROJECT_NAME}_ENABLE_OPENMP "To activate the OpenMP extensions for Fortran" OFF)
#option(${PROJECT_NAME}_ENABLE_MPI "To compile MPI tests and link against MPI library" OFF)
#option(${PROJECT_NAME}_ENABLE_R16P "To define a real precission type with 128 bits" OFF)
#option(${PROJECT_NAME}_ENABLE_HUGE "To use 64 bit instead 32 bit integer as a bit counter" OFF)

option(EXECUTION_PROFILER "Enable the execution profiler" OFF)
option(ENABLE_SSP "Enabled GCC/LLVM stack-smashing protection" OFF)
#option(STATIC_CXX_LIB "Statically link libstd++ and libgcc." OFF)
option(ENABLE_AVX2 "Enable the use of AVX2 instructions" OFF)
option(CLANG_FORCE_LIBSTDCXX "Force libstdc++ when building against Clang/LLVM" OFF)
option(ENABLE_TRACE "Enable tracing in release build" OFF)
option(CPACK_GENERATOR "Enable build of distribution packages using CPack" OFF)
option(ENABLE_SPLIT_DWARF "Reduce linker memory usage by putting debugging information into .dwo files" OFF)

#################################################################
# FFLAGS depend on the compiler and the build type
#################################################################
set(EXTRA_FLAGS "${EXTRA_FLAGS} -fPIC")

if (${ENABLE_F03STD})
  if (${CMAKE_Fortran_COMPILER_ID} STREQUAL "GNU" OR Fortran_COMPILER_NAME MATCHES "gfortran*")
    set(EXTRA_FLAGS "${EXTRA_FLAGS}  -std=f2003 -fall-intrinsics")
  elseif (${CMAKE_Fortran_COMPILER_ID} STREQUAL "Intel" OR Fortran_COMPILER_NAME MATCHES "ifort*")
    set(EXTRA_FLAGS "${EXTRA_FLAGS}  -stand f03")
  else()
    message(STATUS )
  endif ()
endif ()

if (${ENABLE_HARD_OPTIMIZE})
  if (${CMAKE_Fortran_COMPILER_ID} STREQUAL "GNU" AND Fortran_COMPILER_NAME MATCHES "gfortran*")
    set(EXTRA_FLAGS "${EXTRA_FLAGS}  -O3 -ffast-math -funroll-all-loops")
  elseif (${CMAKE_Fortran_COMPILER_ID} STREQUAL "PGI" OR Fortran_COMPILER_NAME MATCHES "pgf*")
    set(EXTRA_FLAGS "${EXTRA_FLAGS}  -O3 -fast ")
  elseif (${CMAKE_Fortran_COMPILER_ID} STREQUAL "Intel" OR Fortran_COMPILER_NAME MATCHES "ifort*")
    set(EXTRA_FLAGS "${EXTRA_FLAGS}  -O3 -inline all -unroll-aggressive -fast ")
  endif ()
endif ()

#if (${${PROJECT_NAME}_ENABLE_OPENMP})
#  find_package( OpenMP )
#  if (${OPENMP_FOUND})
#    set(EXTRA_FLAGS ${OpenMP_Fortran_FLAGS})
#    add_definitions("-DOPENMP")
#  else ()
#    option(${PROJECT_NAME}_ENABLE_OPENMP "To activate the OpenMP extensions for Fortran" OFF)
#  endif ()
#endif ()

# if (${${PROJECT_NAME}_ENABLE_MPI})
#   find_package(MPI)
#   if(${MPI_FOUND})
#     include(CMakeForceCompiler)
#     CMAKE_FORCE_Fortran_COMPILER(${MPI_Fortran_COMPILER} ${CMAKE_Fortran_COMPILER_ID})
#     add_definitions(${MPI_Fortran_COMPILE_FLAGS})
#     include_directories(${MPI_Fortran_INCLUDE_PATH})
#     link_directories(${MPI_Fortran_LIBRARIES})
#     add_definitions("-DMPI2")
#   else ()
#     option(${PROJECT_NAME}_ENABLE_MPI "To compile MPI tests and link against MPI library" OFF)
#   endif ()
# endif ()

# if (${${PROJECT_NAME}_ENABLE_R16P})
#   add_definitions("-Dr16p")
# endif ()

# if (${${PROJECT_NAME}_ENABLE_HUGE})
#   add_definitions("-DHUGE")
# endif ()


##############################################
# Linker            (FROM FACEBOOK HHVM)
#############################################
set(GOLD_FOUND FALSE)
mark_as_advanced(GOLD_FOUND)
#############################################
## DEBUG is used as a variable in some files so use _ as prefix
#############################################
if(CMAKE_BUILD_TYPE STREQUAL "DEBUG")
  add_definitions("-D_DEBUG")
endif()
#############################################
add_definitions(-D${CMAKE_Fortran_COMPILER_ID})
message(STATUS "Fortran compiler ${CMAKE_Fortran_COMPILER_ID}")
#############################################
## COMPLER SPECIFIC SETTINGS
#############################################
if (${CMAKE_Fortran_COMPILER_ID} STREQUAL "GNU" ) #AND Fortran_COMPILER_NAME MATCHES "gfortran*")
  #############################################
  #
  ## GNU fortran
  #
  #############################################
  execute_process(
    COMMAND ${CMAKE_Fortran_COMPILER} -dumpversion OUTPUT_VARIABLE GFC_VERSION)
  if (NOT (GFC_VERSION VERSION_GREATER 4.8 OR GFC_VERSION VERSION_EQUAL 4.8))
    message(FATAL_ERROR "${PROJECT_NAME} requires gfortran 4.8 or greater.")
  endif ()
  set(EXTRA_FLAGS "${EXTRA_FLAGS}  -fimplicit-none -fall-intrinsics -ffree-line-length-none ")
  set(CMAKE_FCPP_COMPILER                "cpp -E -w -C -P")
  set(CMAKE_Fortran_FLAGS                "${CMAKE_Fortran_FLAGS_RELEASE_INIT} ${EXTRA_FLAGS} -cpp ")
  set(CMAKE_Fortran_FLAGS_DEBUG          "${CMAKE_Fortran_FLAGS_DEBUG_INIT} -O0 -g3 -Warray-bounds -Wcharacter-truncation -Wline-truncation -Wimplicit-interface -Wimplicit-procedure -Wunderflow -Wuninitialized -fcheck=all -fmodule-private -fbacktrace -dump-core -finit-real=nan " CACHE STRING "" FORCE)
  set(CMAKE_Fortran_FLAGS_MINSIZEREL     "-Os ${CMAKE_Fortran_FLAGS_RELEASE_INIT}")
  set(CMAKE_Fortran_FLAGS_RELEASE        "-O3 ${CMAKE_Fortran_FLAGS_RELEASE_INIT}")
  set(CMAKE_Fortran_FLAGS_RELWITHDEBINFO "${CMAKE_Fortran_FLAGS_RELEASE_INIT} ${CMAKE_Fortran_FLAGS_DEBUG_INIT}")
  
  #  CMAKE_EXE_LINKER_FLAGS
  if (LINK_TIME_OPTIMISATION)
    set(CMAKE_EXE_LINKER_FLAGS             "${CMAKE_EXE_LINKER_FLAGS_INIT} -flto ")
    set(CMAKE_SHARED_LINKER_FLAGS           "${CMAKE_EXE_LINKER_FLAGS_INIT} -flto -flto=${NUM_JOBS}")
  endif(LINK_TIME_OPTIMISATION)

  ## use gold as linker (from HVVM)

  find_program(GOLD_EXECUTABLE NAMES gold ld.gold DOC "path to gold")
  mark_as_advanced(GOLD_EXECUTABLE)
  if(GOLD_EXECUTABLE)
    set(GOLD_FOUND TRUE)
    execute_process(COMMAND ${GOLD_EXECUTABLE} --version
      OUTPUT_VARIABLE GOLD_VERSION
      OUTPUT_STRIP_TRAILING_WHITESPACE)
    message(STATUS "Found gold: ${GOLD_EXECUTABLE}")
    add_definitions(" -fuse-ld=gold -Wl,--threads")
  else()
    message(STATUS "Could not find gold linker. Using the default")
  endif()


elseif (${CMAKE_Fortran_COMPILER_ID} STREQUAL "Intel" OR Fortran_COMPILER_NAME MATCHES "ifort*")
  #############################################
  #
  ## INTEL fortran
  #
  #############################################
  set(FORTRAN_FLAGS " ${EXTRA_FLAGS} -I${MKLROOT}/include  -assume realloc_lhs -assume source_include")
  #-fpe-all=0 -fp-stack-check -fstack-protector-all -ftrapuv -no-ftz -std03
  set(CMAKE_AR                           "xiar")
  set(CMAKE_FCPP_COMPILER                "ifort -E ")
  set(CMAKE_Fortran_FLAGS                "${CMAKE_Fortran_FLAGS_INIT} -fpp ${FORTRAN_FLAGS}")
  set(CMAKE_Fortran_FLAGS_DEBUG          "${CMAKE_Fortran_FLAGS_DEBUG_INIT} -O0 -debug all -check all -warn all -extend-source 132 -traceback -gen-interfaces")
  set(CMAKE_Fortran_FLAGS_MINSIZEREL     "-Os ${CMAKE_Fortran_FLAGS_RELEASE_INIT}")
  set(CMAKE_Fortran_FLAGS_RELEASE        "-O3 ${CMAKE_Fortran_FLAGS_RELEASE_INIT}")
  set(CMAKE_Fortran_FLAGS_RELWITHDEBINFO "${CMAKE_Fortran_FLAGS_RELEASE_INIT} ${CMAKE_Fortran_FLAGS_DEBUG_INIT}")
  set(CMAKE_EXE_LINKER_FLAGS             "${CMAKE_EXE_LINKER_FLAGS_INIT}")
  set(CMAKE_SHARED_LINKER_FLAGS          "${CMAKE_SHARED_LINKER_FLAGS_INIT} ${EXTRA_LIBS}")
  set(CMAKE_STATIC_LINKER_FLAGS          "${CMAKE_STATIC_LINKER_FLAGS_INIT} ${EXTRA_LIBS}")
  if (LINK_TIME_OPTIMISATION)
    set(CMAKE_EXE_LINKER_FLAGS           "${CMAKE_EXE_LINKER_FLAGS} -ipo-separate -ipo-jobs=${NUM_JOBS}")
    set(CMAKE_SHARED_LINKER_FLAGS        "${CMAKE_SHARED_LINKER_FLAGS} -ip -ipo-separate -ipo-jobs=${NUM_JOBS}")
    set(CMAKE_STATIC_LINKER_FLAGS        "${CMAKE_STATIC_LINKER_FLAGS} -ip -ipo")
  endif(LINK_TIME_OPTIMISATION)


elseif(${CMAKE_Fortran_COMPILER_ID} STREQUAL "PGI" OR Fortran_COMPILER_NAME MATCHES "pgfortran.*")
  #############################################
  #
  ## Portland Group fortran
  #
  #############################################
  message(STATUS "NVIDIA PGI Linux compiler")
  set(PGICOMPILER ON)
  set(EXTRA_FLAGS "${EXTRA_FLAGS} -Mpreprocess -module ${CMAKE_Fortran_MODULE_DIRECTORY} -I${CMAKE_Fortran_MODULE_DIRECTORY}")
  # NVIDIA PGI Linux compiler
  set(CMAKE_FCPP_COMPILER                "pgcc -E ")
  set(CMAKE_Fortran_FLAGS                "${CMAKE_Fortran_FLAGS_INIT} ${EXTRA_FLAGS}")
  set(CMAKE_Fortran_FLAGS_DEBUG          "${CMAKE_Fortran_FLAGS_DEBUG_INIT} -Minfo -Minform -Mneginfo")
  set(CMAKE_Fortran_FLAGS_MINSIZEREL     "${CMAKE_Fortran_FLAGS_RELEASE_INIT}")
  set(CMAKE_Fortran_FLAGS_RELEASE        "-O3  ${CMAKE_Fortran_FLAGS_RELEASE_INIT}")
  set(CMAKE_Fortran_FLAGS_RELWITHDEBINFO "-gopt ${CMAKE_Fortran_FLAGS_RELEASE_INIT} -Mneginfo=all")
  set(CMAKE_EXE_LINKER_FLAGS             "${CMAKE_EXE_LINKER_FLAGS_INIT} -acclibs -cudalibs -Mcudalib=cufft,curand")
  #  CMAKE_SHARED_LINKER_FLAG

  ################################################################
  # CUDA PGI Default options
  ################################################################
  # default PGI library
  set(CUDA_USE_STATIC_CUDA_RUNTIME OFF)
  set(CUDA_rt_LIBRARY  /usr/lib/x86_64-linux-gnu/librt.so)
  add_definitions("-Dproc_bind\\(close\\)=\"\"")  # disable proc_bind in OMP 
#  add_definitions("-module ${CMAKE_Fortran_MODULE_DIRECTORY}") # pgc++ doesn't have -module
  set(CMAKE_SHARED_LINKER_FLAGS          "${CMAKE_SHARED_LINKER_FLAGS_INIT} ${EXTRA_LIBS}  -module ${CMAKE_Fortran_MODULE_DIRECTORY}")
  set(CMAKE_STATIC_LINKER_FLAGS        "${CMAKE_STATIC_LINKER_FLAGS_INIT} ${EXTRA_LIBS}  -module ${CMAKE_Fortran_MODULE_DIRECTORY}")

  #  CMAKE_EXE_LINKER_FLAGS
  if (LINK_TIME_OPTIMISATION)
    set(CMAKE_Fortran_FLAGS                "${CMAKE_Fortran_FLAGS} -Mipa=fast ")
    set(CMAKE_EXE_LINKER_FLAGS           "${CMAKE_EXE_LINKER_FLAGS} -Mipa=fast")
    set(CMAKE_SHARED_LINKER_FLAGS        "${CMAKE_SHARED_LINKER_FLAGS} -Mipa=fast")
    set(CMAKE_STATIC_LINKER_FLAGS        "${CMAKE_STATIC_LINKER_FLAGS} -Mipa=fast")
  endif(LINK_TIME_OPTIMISATION)


elseif ("${CMAKE_Fortran_COMPILER_ID}" MATCHES "Clang")

  #############################################
  ## APPLE Clang
  #############################################
   message ("Clang is not supported.  Please use GNU toolchain with either Homebrew, MacPorts or Fink.")
  # find_package(LLVM REQUIRED CONFIG)

  # set(CMAKE_Fortran_FLAGS                "${CMAKE_Fortran_FLAGS_RELEASE_INIT} -Wno-mismatched-tags -Qunused-arguments")
  # if(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
  #   # In OSX, clang requires "-stdlib=libc++" to support C++11
  #   set(CMAKE_Fortran_FLAGS              "${CMAKE_Fortran_FLAGS} -stdlib=f2003")
  #   set(CMAKE_EXE_LINKER_FLAGS           "-stdlib=libc++")
  # endif()

else ()
  #############################################
  ## UNKNOWN fortran
  #############################################
  message (STATUS " Fortran_COMPILER_NAME ${CMAKE_Fortran_COMPILER_ID}")
  message (STATUS " Set environment variable FC to fortran compiler and rebuild cache.")
  set (CMAKE_Fortran_FLAGS_RELEASE "-O2")
  set (CMAKE_Fortran_FLAGS_DEBUG   "-O0 -g")
endif () # COMPILER_ID



if (IMAGE_TYPE_DOUBLE)
  set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -DIMAGETYPEDOUBLE" )
endif()


################################################################
# Compiler-specific C++11/Modern fortran activation.
################################################################
# IF(UNIX)
# if ()
# elseif ("${CMAKE_Fortran_COMPILER_ID}" MATCHES "Clang")
#   set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -Wno-mismatched-tags -Qunused-arguments")
#   if(${CMAKE_SYSTEM_NAME} MATCHES "Darwin")
#     # In OSX, clang requires "-stdlib=libc++" to support C++11
#     set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS} -stdlib=f95")
#     set(SIMPLE_EXTRA_LINKER_FLAGS "-stdlib=libc++")
#   endif ()
# else ()
#   message(FATAL_ERROR "Your C++ compiler does not support C++11.")
# endif ()

# ELSE(UNIX)
#   IF(WIN32)
#     SET(GUI "Win32")
#   ELSE(WIN32)
#     SET(GUI "Unknown")
#   ENDIF(WIN32)
# ENDIF(UNIX)

# SET(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -pg")
# SET(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -pg")
# SET(CMAKE_SHARED_LINKER_FLAGS "${CMAKE_SHARED_LINKER_FLAGS} -pg")

if (APPLE)
  message(STATUS "Applied CUDA OpenMP macOS workaround")
  set(CUDA_PROPAGATE_HOST_FLAGS OFF)
  set(CMAKE_SHARED_LIBRARY_CXX_FLAGS_BACKUP "${CMAKE_SHARED_LIBRARY_CXX_FLAGS}")
  set(CMAKE_SHARED_LIBRARY_CXX_FLAGS "${CMAKE_SHARED_LIBRARY_CXX_FLAGS} ${CMAKE_CXX_FLAGS} -Wno-unused-function")
  string(REGEX REPLACE "-fopenmp[^ ]*" "" CMAKE_SHARED_LIBRARY_CXX_FLAGS "${CMAKE_SHARED_LIBRARY_CXX_FLAGS}")
endif()



################################################################
# FFTW  -- MKL core already inlcuded in Intel config
################################################################
if (${CMAKE_Fortran_COMPILER_ID} STREQUAL "Intel")
  # Append MKL FFTW interface libs
  set(CMAKE_SHARED_LINKER_FLAGS           "${CMAKE_SHARED_LINKER_FLAGS} -L${MKLROOT}/lib/intel64 -lmkl_intel_ilp64 -lmkl_intel_thread -lmkl_core -liomp5 -lpthread -lm -ldl ")
  set(CMAKE_STATIC_LINKER_FLAGS           "${CMAKE_STATIC_LINKER_FLAGS} -Wl,--start-group ${MKLROOT}/lib/intel64/libmkl_intel_ilp64.a ${MKLROOT}/lib/intel64/libmkl_intel_thread.a ${MKLROOT}/lib/intel64/libmkl_core.a -Wl,--end-group -liomp5 -lpthread -lm -ldl")
  set(FFTW_FOUND ON)
else()
  if (FFTW_DIR)
    set(FFTW_LIBRARIES " -lfftw3 -lfftw3f -lfftw3f_omp " )
    set(FFTW_INCLUDE_DIRS "-I${FFTW_DIR}/include" )
    include_directories(${FFTW_INCLUDE_DIRS})
    link_directories(${FFTW_DIR}/lib)
    set(FFTW_SINGLE_PRECISION_LIBRARIES_FOUND ON)
    set(FFTW_FOUND ON)
  else()
    find_package(FFTW QUIET)
    if (NOT FFTW_FOUND)
      message(FATAL_ERROR "Unable to find FFTW")
    else()
      message(STATUS "fftw3 found")
      message(STATUS "lib: ${FFTW_LIBRARIES}")
      include_directories(${FFTW_INCLUDE_DIRS})
      set(EXTRA_LIBS ${EXTRA_LIBS} ${FFTW_LIBRARIES} -lfftw3f -lfftw3f_omp)
    endif()
  endif(FFTW_DIR)
endif()


# There is some bug where -march=native doesn't work on Mac
IF(APPLE)
  SET(GNUNATIVE "-mtune=native")
ELSE()
  SET(GNUNATIVE "-march=native")
ENDIF(APPLE)

################################################################
# Generic Flags 
################################################################

# Don't add underscores in symbols for C-compatability
message(STATUS "Testing flag no underscore")
SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS}"
  Fortran
  "-fnosecond-underscore"     # GNU
  "-Mnosecond_underscore" # PGI
  "-assume nounderscore"  # Intel
  )


# Optimize for the host's architecture
message(STATUS "Testing flag host arch")
SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS}"
  Fortran 
  "-xHost"        # Intel
  "/QxHost"       # Intel Windows
  ${GNUNATIVE}    # GNU
  #  "-ta=host"      # Portland Group
  )

# Preprocessing
# message(STATUS "Testing flag cpp")
# SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS}"
#   Fortran REQUIRED
#   "-fpp"                # Intel
#   "-cpp"                # GNU
#   "-Mpreprocess"        # PGI
#   )
# free form
message(STATUS "Testing flag free-form")
SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS}"
  Fortran 
  "-ffree-form"       # GNU
  "-free"             # Intel
  "-Mfreeform"        # PGI
  )
# line length
message(STATUS "Testing flag no line length")
SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS}"
  Fortran
  "-ffree-line-length-none"    # GNU
  "-Mextend"                   # PGI
  "-extend-source"            # Intel
  "-list-line-len=264"        # Intel
  )

###################
### DEBUG FLAGS ###
###################
## Disable optimizations
message(STATUS "Testing debug flags")
SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS_DEBUG "${CMAKE_Fortran_FLAGS_DEBUG}"
  Fortran 
  "-O0" # All compilers not on Windows
  "/Od" # Intel Windows
  )

# Turn on all warnings
message(STATUS "Testing warn all flags")
SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS_DEBUG "${CMAKE_Fortran_FLAGS_DEBUG}"
  Fortran
  "/warn:all" # Intel Windows
  "-Wall"     # GNU
  "-warn all" # Intel
  )

# Traceback
message(STATUS "Testing flags traceback ")
SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS_DEBUG "${CMAKE_Fortran_FLAGS_DEBUG}"
  Fortran
  "-traceback"   # Intel/Portland Group
  "/traceback"   # Intel Windows
  "-fbacktrace"  # GNU (gfortran)
  "-ftrace=full" # GNU (g95)
  )

# Check array bounds
message(STATUS "Testing flags array bounds check")
SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS_DEBUG "${CMAKE_Fortran_FLAGS_DEBUG}"
  Fortran 
  "-fbounds-check" # GNU (Old style)
  "-fcheck=bounds" # GNU (New style)
  "-Mbounds"       # Portland Group
  "/check:bounds"  # Intel Windows
  "-check bounds"  # Intel
  )


#####################
### TESTING FLAGS ###
#####################

# Optimizations
#SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS_TESTING "${CMAKE_Fortran_FLAGS_TESTING}"
#  Fortran REQUIRED
#  "-O2" # All compilers not on Windows
#  "/O2" # Intel Windows
#  )

#####################
### RELEASE FLAGS ###
#####################

# Unroll loops
#message(STATUS "Testing flags unroll")
#SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS_RELEASE "${CMAKE_Fortran_FLAGS_RELEASE}"
#  Fortran
#  "-unroll-aggressive"        # Intel
#  "-funroll-loops"            # GNU, Intel, Clang
#  "/unroll"                   # Intel Windows
#  "-Munroll"                  # Portland Group
#  )


# Inline functions
SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS_RELEASE "${CMAKE_Fortran_FLAGS_RELEASE}"
  Fortran
  "-inline"            # Intel
  "/Qinline"           # Intel Windows
  "-finline-functions" # GNU, Intel
  "-Minline"           # Portland Group
  )
if(LINK_TIME_OPTIMISATION)
  # Interprocedural (link-time) optimizations
  SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS_RELEASE "${CMAKE_Fortran_FLAGS_RELEASE}"
    Fortran
    "-ipo-separate"     # Intel
    "/Qipo"             # Intel Windows
    "-flto "            # GNU
    "-Mipa=fast,inline"    # Portland Group
    )

  # Single-file optimizations
  SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS_RELEASE "${CMAKE_Fortran_FLAGS_RELEASE}"
    Fortran
    "-ip"           # Intel
    "/Qip"          # Intel Windows
    "-fipa-profile" # GNU
    # PGI
    )
endif(LINK_TIME_OPTIMISATION)


# # Fast math code
# SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS_RELEASE "${CMAKE_Fortran_FLAGS_RELEASE}"
#   Fortran
#   "-fastmath"        # Intel
#   "-ffast-math"      # GNU
#   "-Mcuda=fastmath"  # Portland Group
#   )

# # Vectorize code
# SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS_RELEASE "${CMAKE_Fortran_FLAGS_RELEASE}"
#   Fortran
#   "-fast"    # Intel, PGI
#   "/Qvec-report0"    # Intel Windows
#   "-ftree-vectorize" # GNU
#   "-Mvect"           # Portland Group
#   "-fvectorize"      # Clang
#   )

# Auto parallelize
if (USE_AUTO_PARALLELISE)
SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS_RELEASE "${CMAKE_Fortran_FLAGS_RELEASE}"
  Fortran
  "-parallel"            # Intel
  "-Mconcur"             # PGI
  )
endif()
# Auto parallelize with OpenACC
if (USE_OPENACC)
SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS_RELEASE "${CMAKE_Fortran_FLAGS_RELEASE}"
  Fortran
  "-acc"                 # PGI
  "-fopenacc"            # GNU
  )
endif()

# Instrumentation
if (USE_INSTRUMENTATION)
SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS_RELEASE "${CMAKE_Fortran_FLAGS_RELEASE}"
  Fortran
  "-Minstrument"            # PGI
  "-finstrument"            # GNU
  )
endif()

# Profile-feedback optimisation
if(USE_PROFILE_OPTIMISATION)
SET_COMPILE_FLAG(CMAKE_Fortran_FLAGS_RELEASE "${CMAKE_Fortran_FLAGS_RELEASE}"
  Fortran
  "-Mpfo"                 # PGI
  "-fpfo"            # GNU
  )
endif()
#set(CMAKE_Fortran_FLAGS "${CMAKE_Fortran_FLAGS}  ")
#set(CMAKE_FCPP_FLAGS " -C -P ") # Retain comments due to fortran slash-slash
#set(CMAKE_Fortran_CREATE_PREPROCESSED_SOURCE "${CMAKE_FCPP_COMPILER} <DEFINES> <INCLUDES> <FLAGS> -E <SOURCE> > <PREPROCESSED_SOURCE>")

# Override Fortran preprocessor
set(CMAKE_Fortran_COMPILE_OBJECT "grep --silent '#include' <SOURCE> && ( ${CMAKE_FCPP_COMPILER} -DOPENMP <DEFINES> <INCLUDES> <SOURCE> |  tr \"\;\" \"\\n\" > <OBJECT>.f08 &&  <CMAKE_Fortran_COMPILER> <DEFINES> <INCLUDES> <FLAGS> -c <OBJECT>.f08 -o <OBJECT> ) || <CMAKE_Fortran_COMPILER> <DEFINES> <INCLUDES> <FLAGS> -c <SOURCE> -o <OBJECT>")




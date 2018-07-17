# - Finds OpenMP support
# This module can be used to detect OpenMP support in a compiler.
# If the compiler supports OpenMP, the flags required to compile with
# openmp support are set.
#
# This module was modified from the standard FindOpenMP module to find Fortran
# flags.
#
# The following variables are set:
#   OpenMP_Fortran_FLAGS - flags to add to the Fortran compiler for OpenMP
#                          support.  In general, you must use these at both
#                          compile- and link-time.
#   OMP_NUM_PROCS - the max number of processors available to OpenMP

#=============================================================================
# Copyright 2009 Kitware, Inc.
# Copyright 2008-2009 Andr\`e Rigland Brodtkorb <Andre.Brodtkorb@ifi.uio.no>
#
# Distributed under the OSI-approved BSD License (the "License");
# see accompanying file Copyright.txt for details.
#
# This software is distributed WITHOUT ANY WARRANTY; without even the
# implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
# See the License for more information.
#=============================================================================
# (To distribute this file outside of CMake, substitute the full
#  License text for the above reference.)

INCLUDE (${CMAKE_ROOT}/Modules/FindPackageHandleStandardArgs.cmake)

SET (OpenMP_Fortran_FLAG_CANDIDATES
     #Gnu
     "-fopenmp"
     #Microsoft Visual Studio
     "/openmp"
     #Intel windows
     "/Qopenmp"
     #Intel
     "-qopenmp"
     #Sun
     "-xopenmp"
     #HP
     "+Oopenmp"
     #IBM XL C/c++
     "-qsmp"
     #Portland Group
     "-mp"
    #Empty, if compiler automatically accepts openmp
     " "
     )
if(APPLE)
message(STATUS " Testing OpenMP affinity <<<<<<<<>>>>>>>")
endif()

IF (DEFINED OpenMP_Fortran_FLAGS)
    SET (OpenMP_Fortran_FLAG_CANDIDATES)
ENDIF (DEFINED OpenMP_Fortran_FLAGS)

# check fortran compiler. also determine number of processors
FOREACH (FLAG ${OpenMP_Fortran_FLAG_CANDIDATES})
    SET (SAFE_CMAKE_REQUIRED_FLAGS "${CMAKE_REQUIRED_FLAGS}")
    SET (CMAKE_REQUIRED_FLAGS "${FLAG}")
    UNSET (OpenMP_FLAG_DETECTED CACHE)
    MESSAGE (STATUS "Try OpenMP Fortran flag = [${FLAG}]")
    FILE (WRITE ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeTmp/testFortranOpenMP.f90 "
program TestOpenMP
   use omp_lib
write(*,'(I2)',ADVANCE='NO') omp_get_num_procs()
end program TestOpenMP
")
    SET (MACRO_CHECK_FUNCTION_DEFINITIONS
      "-DOpenMP_FLAG_DETECTED ${CMAKE_REQUIRED_FLAGS}")
if(APPLE)
    try_compile(OpenMP_FLAG_DETECTED ${CMAKE_BINARY_DIR}
      ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeTmp/testFortranOpenMP.f90
      COMPILE_DEFINITIONS ${CMAKE_REQUIRED_DEFINITIONS}
      CMAKE_FLAGS -DCOMPILE_DEFINITIONS:STRING=${MACRO_CHECK_FUNCTION_DEFINITIONS}
      COMPILE_OUTPUT_VARIABLE OUTPUT
      RUN_OUTPUT_VARIABLE OMP_NUM_PROCS_INTERNAL)
else()
     TRY_RUN (OpenMP_RUN_FAILED OpenMP_FLAG_DETECTED ${CMAKE_BINARY_DIR}
         ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeTmp/testFortranOpenMP.f90
         COMPILE_DEFINITIONS ${CMAKE_REQUIRED_DEFINITIONS}
         CMAKE_FLAGS -DCOMPILE_DEFINITIONS:STRING=${MACRO_CHECK_FUNCTION_DEFINITIONS}
         COMPILE_OUTPUT_VARIABLE OUTPUT
         RUN_OUTPUT_VARIABLE OMP_NUM_PROCS_INTERNAL)
endif()
    IF (OpenMP_FLAG_DETECTED)
       FILE (APPEND ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeOutput.log
             "Determining if the Fortran compiler supports OpenMP passed with "
             "the following output:\n${OMP_NUM_PROCS_INTERNAL}\n\n")
       SET (OpenMP_FLAG_DETECTED 1)
       # IF (OpenMP_RUN_FAILED)
       #     MESSAGE (FATAL_ERROR "OpenMP found, but test code did not run")
       # ENDIF (OpenMP_RUN_FAILED)
       STRING(REGEX MATCH "^[^0-9]*$" OMP_ERROR "${OMP_NUM_PROCS_INTERNAL}")

       if ("${OMP_ERROR} " STREQUAL " ")
         SET (OMP_NUM_PROCS ${OMP_NUM_PROCS_INTERNAL} CACHE
           STRING "Number of processors OpenMP may use" FORCE)
         SET (OpenMP_Fortran_FLAGS_INTERNAL "${FLAG}")
       else()
         message(STATUS " OMP NUM PROCS ERROR ${OMP_ERROR}" )
         STRING(REGEX REPLACE ".* \([0-9]+\)$" "\\1" OMP_NUM_PROCS_INTERNAL "${OMP_NUM_PROCS_INTERNAL}")
         message(STATUS " OMP NUM PROCS OUTPUT set to ${OMP_NUM_PROCS_INTERNAL}" )
         SET (OMP_NUM_PROCS ${OMP_NUM_PROCS_INTERNAL} CACHE
           STRING "Number of processors OpenMP may use" FORCE)
         SET (OpenMP_Fortran_FLAGS_INTERNAL "${FLAG}")
       endif()
       BREAK ()
      ELSE ()
        FILE (APPEND ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeError.log
             "Determining if the Fortran compiler supports OpenMP failed with "
             "the following output:\n${OMP_NUM_PROCS_INTERNAL}\n\n")
        SET (OpenMP_FLAG_DETECTED 0)
    ENDIF (OpenMP_FLAG_DETECTED)
ENDFOREACH (FLAG ${OpenMP_Fortran_FLAG_CANDIDATES})

SET (OpenMP_Fortran_FLAGS "${OpenMP_Fortran_FLAGS_INTERNAL}"
     CACHE STRING "Fortran compiler flags for OpenMP parallelism")


   UNSET (OpenMP_Version_DETECTED CACHE)
   MESSAGE (STATUS "Try OpenMP version")

    FILE (WRITE ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeTmp/testFortranOpenMPVersion.f90 "
program TestOpenMPVersion
   use omp_lib
write(*,'(I6)',ADVANCE='NO') openmp_version()
end program TestOpenMPVersion
")

if(APPLE)
    try_compile(OpenMP_Version_DETECTED ${CMAKE_BINARY_DIR}
      ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeTmp/testFortranOpenMPVersion.f90
      COMPILE_DEFINITIONS ${OpenMP_Fortran_FLAGS}
      CMAKE_FLAGS -DCOMPILE_DEFINITIONS:STRING=${MACRO_CHECK_FUNCTION_DEFINITIONS}
      COMPILE_OUTPUT_VARIABLE OUTPUT
      RUN_OUTPUT_VARIABLE OMP_VERSION_INTERNAL)
else()
     TRY_RUN (OpenMP_RUN_FAILED OpenMP_Version_DETECTED ${CMAKE_BINARY_DIR}
         ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeTmp/testFortranOpenMPVersion.f90
         COMPILE_DEFINITIONS ${OpenMP_Fortran_FLAGS}
         CMAKE_FLAGS -DCOMPILE_DEFINITIONS:STRING=${MACRO_CHECK_FUNCTION_DEFINITIONS}
         COMPILE_OUTPUT_VARIABLE OUTPUT
         RUN_OUTPUT_VARIABLE OMP_VERSION_INTERNAL)
endif()
    IF (OpenMP_Version_DETECTED)
       FILE (APPEND ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeOutput.log
             "Determining the Fortran compiler version of OpenMP passed with "
             "the following output:\n${OMP_VERSION_INTERNAL}\n\n")
       SET (OpenMP_Version_DETECTED 1)
       # IF (OpenMP_RUN_FAILED)
       #     MESSAGE (FATAL_ERROR "OpenMP found, but test code did not run")
       # ENDIF (OpenMP_RUN_FAILED)
       STRING(REGEX MATCH "^[^0-9]*$" OMP_ERROR "${OMP_VERSION_INTERNAL}")

       if ("${OMP_ERROR} " STREQUAL " ")
         SET (OpenMP_Fortran_VERSION ${OMP_VERSION_INTERNAL}  CACHE
           STRING " OpenMP version " FORCE)
       else()
         message(STATUS " OMP VERSION ERROR ${OMP_ERROR}" )
         STRING(REGEX REPLACE ".* \([0-9]+\)$" "\\1" OMP_VERSION_INTERNAL "${OMP_VERSION_INTERNAL}")
         message(STATUS " OMP NUM PROCS OUTPUT set to ${OMP_VERSION_INTERNAL}" )
         SET (OpenMP_Fortran_VERSION ${OMP_VERSION_INTERNAL} CACHE
           STRING " OpenMP version" FORCE)
       endif()
       BREAK ()
      ELSE ()
        FILE (APPEND ${CMAKE_BINARY_DIR}${CMAKE_FILES_DIRECTORY}/CMakeError.log
             "Determining the Fortran compiler version of OpenMP failed with "
             "the following output:\n${OMP_NUM_PROCS_INTERNAL}\n\n")
        SET (OpenMP_Version_DETECTED 0)
    ENDIF (OpenMP_Version_DETECTED)


# handle the standard arguments for FIND_PACKAGE
FIND_PACKAGE_HANDLE_STANDARD_ARGS (OpenMP_Fortran DEFAULT_MSG
    OpenMP_Fortran_FLAGS)

MARK_AS_ADVANCED(OpenMP_Fortran_FLAGS, OpenMP_Fortran_VERSION)

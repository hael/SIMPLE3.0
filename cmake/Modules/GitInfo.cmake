SET(SIMPLE_GIT_VERSION "not known")
IF(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/.git)
  FIND_PACKAGE(Git)
  
  IF(GIT_FOUND)
    EXECUTE_PROCESS(
      COMMAND ${GIT_EXECUTABLE} describe --abbrev=8 --dirty=-release2.5 --always
      WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}"
      OUTPUT_VARIABLE "SIMPLE_GIT_VERSION"
      ERROR_QUIET
      OUTPUT_STRIP_TRAILING_WHITESPACE)
  ELSE(GIT_FOUND)
#    MESSAGE( STATUS "Git not found: ${SIMPLE_GIT_VERSION}" )
ENDIF(GIT_FOUND)
ELSE()
SET(SIMPLE_GIT_VERSION "-release2.5")
ENDIF(EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/.git)

MESSAGE( STATUS "Git version: ${SIMPLE_GIT_VERSION}" )
MESSAGE( STATUS "Git version template : ${CMAKE_SOURCE_DIR}/cmake/Modules/GitVersion.h.in" )
MESSAGE( STATUS "Git version template : ${CMAKE_INSTALL_PREFIX}/lib/simple/SimpleGitVersion.h")
CONFIGURE_FILE(${CMAKE_SOURCE_DIR}/cmake/Modules/GitVersion.h.in  ${CMAKE_BINARY_DIR}/lib/simple/SimpleGitVersion.h @ONLY)

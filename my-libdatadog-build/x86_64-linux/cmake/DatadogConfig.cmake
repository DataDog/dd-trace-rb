# Copyright 2021-Present Datadog, Inc. https://www.datadoghq.com/
# SPDX-License-Identifier: Apache-2.0
include(FindPackageHandleStandardArgs)

if(DEFINED ENV{Datadog_ROOT})
  set(Datadog_ROOT "$ENV{Datadog_ROOT}")
else()
  # If the environment variable is not set, maybe we are part of a build
  set(Datadog_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/..")
endif()

find_path(Datadog_INCLUDE_DIR datadog/profiling.h HINTS ${Datadog_ROOT}/include)

set(DD_LIB_NAME "datadog_profiling")

if(CMAKE_CXX_COMPILER_ID MATCHES "MSVC")
  # Prefer static linking over dynamic unless specified
  set(LINK_TYPE "static")
  if (DEFINED VCRUNTIME_LINK_TYPE)
    string(TOLOWER ${VCRUNTIME_LINK_TYPE} LINK_TYPE)
  endif()

  set(BUILD_TYPE "release")
  if (DEFINED CMAKE_BUILD_TYPE)
    string(TOLOWER ${CMAKE_BUILD_TYPE} BUILD_TYPE)
  endif()

  find_library(
      Datadog_LIBRARY
      # Windows artifacts publish the library as datadog_profiling_ffi
      # in {build_type}/{link_type} directory
      NAMES ${DD_LIB_NAME} datadog_profiling_ffi
      HINTS ${Datadog_ROOT}/lib ${Datadog_ROOT}/${BUILD_TYPE}/${LINK_TYPE})

  # It could be either datadog_profiling or datadog_profiling_ffi, set it to the
  # one that is found
  get_filename_component(DD_LIB_NAME ${Datadog_LIBRARY} NAME_WE)
  message(STATUS "Datadog library name: ${DD_LIB_NAME}")
else()
  find_library(
    Datadog_LIBRARY
    NAMES ${DD_LIB_NAME}
    HINTS ${Datadog_ROOT}/lib)
endif()

find_package_handle_standard_args(Datadog DEFAULT_MSG Datadog_LIBRARY
                                  Datadog_INCLUDE_DIR)

if(Datadog_FOUND)
  set(Datadog_INCLUDE_DIRS ${Datadog_INCLUDE_DIR})
  set(Datadog_LIBRARIES ${Datadog_LIBRARY} "-ldl -lrt -lpthread -lc -lm -lrt -lpthread -lutil -ldl -lutil")
  mark_as_advanced(Datadog_ROOT Datadog_LIBRARY Datadog_INCLUDE_DIR)

  add_library(${DD_LIB_NAME} INTERFACE)
  target_include_directories(${DD_LIB_NAME}
                             INTERFACE ${Datadog_INCLUDE_DIRS})
  target_link_libraries(${DD_LIB_NAME} INTERFACE ${Datadog_LIBRARIES})
  target_compile_features(${DD_LIB_NAME} INTERFACE c_std_11)

  if(CMAKE_CXX_COMPILER_ID MATCHES "MSVC")
    target_link_libraries(
      ${DD_LIB_NAME}
      INTERFACE NtDll
                UserEnv
                Bcrypt
                crypt32
                wsock32
                ws2_32
                shlwapi
                Secur32
                Ncrypt
                PowrProf
                Version)
  endif()

  add_library(Datadog::Profiling ALIAS ${DD_LIB_NAME})
else()
  set(Datadog_ROOT
      ""
      CACHE STRING "Directory containing libdatadog")
endif()

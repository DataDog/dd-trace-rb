#pragma once

#include "datadog_ruby_common.h"

// Raises a Ruby error if the `ddog_VoidResult` indicates an error.
// The error message in `result.err` is appended to the provided `message`.
//
// @param[in] message (const char *) The error message
// @param[in] result (ddog_VoidResult) A result to check
#define CHECK_VOID_RESULT(message, result)                             \
  do {                                                                         \
    if (result.tag == DDOG_VOID_RESULT_ERR) {                                 \
      raise_lib_error(message, result);                                        \
    }                                                                          \
  } while (0)

// Raises a Ruby error for the error result.
// The error message in `result.err` is appended to the provided `message`.
//
// @param[in] message (const char *) The error message
// @param[in] result (struct { ddog_Error res; ... }) Any type of result
#define raise_lib_error(message, result)                                        \
  do {                                                                         \
    raise_error(eNativeRuntimeError, message PRIsVALUE, get_error_details_and_drop(&result.err)); \
  } while (0)

#pragma once

#include "datadog_ruby_common.h"

// Macro to raise an error from a ddog_VoidResult with error details
// @param[in] result (uint8_t)  ddog_Error
// @param[in] result (struct { ddog_Error res; ... }) A result with an error.
#define raise_lib_error(message, result)                                        \
  do {                                                                         \
    raise_error(eNativeRuntimeError, message, get_error_details_and_drop(&result.err)); \
  } while (0)

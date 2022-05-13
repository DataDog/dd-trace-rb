#pragma once

#include <stdbool.h>

// The private_vm_api_access.c includes the RUBY_MJIT_HEADER which replaces and conflicts with any other Ruby headers;
// so we use PRIVATE_VM_API_ACCESS_SKIP_RUBY_INCLUDES to be able to include private_vm_api_access.h on that file
// without also dragging the incompatible includes
#ifndef PRIVATE_VM_API_ACCESS_SKIP_RUBY_INCLUDES
  #ifdef RUBY_2_1_WORKAROUND
    #include <thread_native.h>
  #else
    #include <ruby/thread_native.h>
  #endif
#endif

#include "extconf.h"

rb_nativethread_id_t pthread_id_for(VALUE thread);
ptrdiff_t stack_depth_for(VALUE thread);
VALUE ddtrace_thread_list();
void self_test_thread_list();

int ddtrace_rb_profile_frames(VALUE thread, int start, int limit, VALUE *buff, int *lines, bool* is_ruby_frame);

// Ruby 3.0 finally added support for showing CFUNC frames (frames for methods written using native code)
// in stack traces gathered via `rb_profile_frames` (https://github.com/ruby/ruby/pull/3299).
// To access this information on older Rubies, beyond using our custom `ddtrace_rb_profile_frames` above, we also need
// to backport the Ruby 3.0+ version of `rb_profile_frame_method_name`.
#ifdef USE_BACKPORTED_RB_PROFILE_FRAME_METHOD_NAME
  VALUE ddtrace_rb_profile_frame_method_name(VALUE frame);
#else // Ruby > 3.0, just use the stock functionality
  #define ddtrace_rb_profile_frame_method_name rb_profile_frame_method_name
#endif

// See comment on `record_placeholder_stack_in_native_code` for a full explanation of what this means (and why we don't just return 0)
#define PLACEHOLDER_STACK_IN_NATIVE_CODE -1

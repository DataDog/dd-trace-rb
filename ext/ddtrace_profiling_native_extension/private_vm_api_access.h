#pragma once

#ifdef RUBY_2_1_WORKAROUND
#include <thread_native.h>
#else
#include <ruby/thread_native.h>
#endif

rb_nativethread_id_t pthread_id_for(VALUE thread);
int ddtrace_rb_profile_frames(VALUE thread, int start, int limit, VALUE *buff, int *lines, bool* is_ruby_frame);

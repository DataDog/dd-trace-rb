#pragma once

#ifdef RUBY_2_1_WORKAROUND
#include <thread_native.h>
#else
#include <ruby/thread_native.h>
#endif

rb_nativethread_id_t pthread_id_for(VALUE thread);

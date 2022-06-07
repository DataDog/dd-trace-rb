#include "extconf.h"

// This file is the dual of clock_id_from_pthread.c for systems where that info
// is not available.
#ifndef HAVE_PTHREAD_GETCPUCLOCKID

#include <ruby.h>

#include "clock_id.h"

void self_test_clock_id(void) { } // Nothing to check
VALUE clock_id_for(VALUE self, VALUE thread) { return Qnil; } // Nothing to return

#endif

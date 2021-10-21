#include "extconf.h"

// This file is only compiled on systems where pthread_getcpuclockid() is available;
// Otherwise we compile clock_id_noop.c
#if defined(HAVE_PTHREAD_GETCPUCLOCKID) && defined(USE_MJIT_HEADER)

#include <pthread.h>
#include <time.h>

#include <ruby.h>
#include <ruby/thread_native.h>

#include "private_vm_api_access.h"

#include "clock_id.h"

// Validate that our home-cooked pthread_id_for() matches pthread_self() for the current thread
void self_test_clock_id() {
  rb_nativethread_id_t expected_pthread_id = pthread_self();
  rb_nativethread_id_t actual_pthread_id = pthread_id_for(rb_thread_current());

  if (expected_pthread_id != actual_pthread_id) rb_raise(rb_eRuntimeError, "pthread_id_for() self-test failed");
}

VALUE clock_id_for(VALUE self, VALUE thread) {
  rb_nativethread_id_t thread_id = pthread_id_for(thread);

  clockid_t clock_id;
  int error = pthread_getcpuclockid(thread_id, &clock_id);

  if (!error) {
    return CLOCKID2NUM(clock_id);
  } else {
    rb_exc_raise(rb_syserr_new(error, "Failed to get clock_id for given thread"));
  }
}

#endif

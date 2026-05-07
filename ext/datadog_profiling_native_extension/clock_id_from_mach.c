#include "extconf.h"

// This file is only compiled on macOS where Mach thread APIs are available;
// Otherwise we compile clock_id_from_pthread.c (Linux)
#ifdef HAVE_MACH_THREAD_INFO

#include <pthread.h>
#include <mach/mach.h>
#include <mach/thread_info.h>

#include "clock_id.h"
#include "helpers.h"
#include "private_vm_api_access.h"
#include "ruby_helpers.h"
#include "time_helpers.h"

// Validate that our home-cooked pthread_id_for() matches pthread_self() for the current thread
void self_test_clock_id(void) {
  rb_nativethread_id_t expected_pthread_id = pthread_self();
  rb_nativethread_id_t actual_pthread_id = pthread_id_for(rb_thread_current());

  if (expected_pthread_id != actual_pthread_id) raise_error(rb_eRuntimeError, "pthread_id_for() self-test failed");

  // Also validate that we can get a valid mach thread port for the current thread
  mach_port_t mach_thread = pthread_mach_thread_np(expected_pthread_id);
  if (mach_thread == MACH_PORT_NULL) raise_error(rb_eRuntimeError, "pthread_mach_thread_np() self-test failed");
}

// Safety: This function is assumed never to raise exceptions by callers
thread_cpu_time_id thread_cpu_time_id_for(VALUE thread) {
  rb_nativethread_id_t thread_id = pthread_id_for(thread);

  if (thread_id == 0) return (thread_cpu_time_id) {.valid = false};

  mach_port_t mach_thread = pthread_mach_thread_np(thread_id);

  if (mach_thread == MACH_PORT_NULL) {
    return (thread_cpu_time_id) {.valid = false};
  }

  return (thread_cpu_time_id) {.valid = true, .clock_id = mach_thread};
}

thread_cpu_time thread_cpu_time_for(thread_cpu_time_id time_id) {
  thread_cpu_time error = (thread_cpu_time) {.valid = false};

  if (!time_id.valid) return error;

  struct thread_basic_info info;
  mach_msg_type_number_t count = THREAD_BASIC_INFO_COUNT;
  kern_return_t kr = thread_info(time_id.clock_id, THREAD_BASIC_INFO, (thread_info_t)&info, &count);

  if (kr != KERN_SUCCESS) return error;

  long user_ns = SECONDS_AS_NS(info.user_time.seconds) + MICROS_AS_NS(info.user_time.microseconds);
  long system_ns = SECONDS_AS_NS(info.system_time.seconds) + MICROS_AS_NS(info.system_time.microseconds);

  return (thread_cpu_time) {.valid = true, .result_ns = user_ns + system_ns};
}

#endif

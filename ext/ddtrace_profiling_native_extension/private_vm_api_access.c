#include "extconf.h"

// This file exports functions used to access private Ruby VM APIs and internals.
// To do this, it imports a few VM internal (private) headers.
// Be very careful when changing things here :)
#ifdef USE_MJIT_HEADER
#include RUBY_MJIT_HEADER

static const rb_data_type_t *thread_data_type = NULL;

// MRI has a similar rb_thread_ptr() function which we can't call it directly
// because Ruby does not expose the thread_data_type publicly.
// Instead, we have our own version of that function, and we lazily initialize the thread_data_type pointer
// from a known-correct object: the current thread.
//
// Note that beyond returning the rb_thread_struct*, rb_check_typeddata() raises an exception
// if the argument passed in is not actually a `Thread` instance.
static inline struct rb_thread_struct *thread_struct_from_object(VALUE thread) {
  if (thread_data_type == NULL) thread_data_type = RTYPEDDATA_TYPE(rb_thread_current());

  return (struct rb_thread_struct *) rb_check_typeddata(thread, thread_data_type);
}

rb_nativethread_id_t pthread_id_for(VALUE thread) {
  return thread_struct_from_object(thread)->thread_id;
}
#endif

#include <ruby.h>
#include <ruby/thread.h>
#include <errno.h>

#include "clock_id.h"
#include "helpers.h"
#include "private_vm_api_access.h"
#include "ruby_helpers.h"
#include "setup_signal_handler.h"
#include "time_helpers.h"

// Each class/module here is implemented in their separate file
void collectors_cpu_and_wall_time_worker_init(VALUE profiling_module);
void collectors_dynamic_sampling_rate_init(VALUE profiling_module);
void collectors_idle_sampling_helper_init(VALUE profiling_module);
void collectors_stack_init(VALUE profiling_module);
void collectors_thread_context_init(VALUE profiling_module);
void http_transport_init(VALUE profiling_module);
void stack_recorder_init(VALUE profiling_module);

static VALUE native_working_p(VALUE self);
static VALUE _native_grab_gvl_and_raise(DDTRACE_UNUSED VALUE _self, VALUE exception_class, VALUE test_message, VALUE test_message_arg, VALUE release_gvl);
static void *trigger_grab_gvl_and_raise(void *trigger_args);
static VALUE _native_grab_gvl_and_raise_syserr(DDTRACE_UNUSED VALUE _self, VALUE syserr_errno, VALUE test_message, VALUE test_message_arg, VALUE release_gvl);
static void *trigger_grab_gvl_and_raise_syserr(void *trigger_args);
static VALUE _native_ddtrace_rb_ractor_main_p(DDTRACE_UNUSED VALUE _self);
static VALUE _native_is_current_thread_holding_the_gvl(DDTRACE_UNUSED VALUE _self);
static VALUE _native_release_gvl_and_call_is_current_thread_holding_the_gvl(DDTRACE_UNUSED VALUE _self);
static void *testing_is_current_thread_holding_the_gvl(DDTRACE_UNUSED void *_unused);
static VALUE _native_install_holding_the_gvl_signal_handler(DDTRACE_UNUSED VALUE _self);
static void holding_the_gvl_signal_handler(DDTRACE_UNUSED int _signal, DDTRACE_UNUSED siginfo_t *_info, DDTRACE_UNUSED void *_ucontext);
static VALUE _native_trigger_holding_the_gvl_signal_handler_on(DDTRACE_UNUSED VALUE _self, VALUE background_thread);
static VALUE _native_enforce_success(DDTRACE_UNUSED VALUE _self, VALUE syserr_errno, VALUE with_gvl);
static void *trigger_enforce_success(void *trigger_args);

void DDTRACE_EXPORT Init_ddtrace_profiling_native_extension(void) {
  VALUE datadog_module = rb_define_module("Datadog");
  VALUE profiling_module = rb_define_module_under(datadog_module, "Profiling");
  VALUE native_extension_module = rb_define_module_under(profiling_module, "NativeExtension");

  rb_define_singleton_method(native_extension_module, "native_working?", native_working_p, 0);
  rb_funcall(native_extension_module, rb_intern("private_class_method"), 1, ID2SYM(rb_intern("native_working?")));

  rb_define_singleton_method(native_extension_module, "clock_id_for", clock_id_for, 1); // from clock_id.h

  collectors_cpu_and_wall_time_worker_init(profiling_module);
  collectors_dynamic_sampling_rate_init(profiling_module);
  collectors_idle_sampling_helper_init(profiling_module);
  collectors_stack_init(profiling_module);
  collectors_thread_context_init(profiling_module);
  http_transport_init(profiling_module);
  stack_recorder_init(profiling_module);

  // Hosts methods used for testing the native code using RSpec
  VALUE testing_module = rb_define_module_under(native_extension_module, "Testing");
  rb_define_singleton_method(testing_module, "_native_grab_gvl_and_raise", _native_grab_gvl_and_raise, 4);
  rb_define_singleton_method(testing_module, "_native_grab_gvl_and_raise_syserr", _native_grab_gvl_and_raise_syserr, 4);
  rb_define_singleton_method(testing_module, "_native_ddtrace_rb_ractor_main_p", _native_ddtrace_rb_ractor_main_p, 0);
  rb_define_singleton_method(testing_module, "_native_is_current_thread_holding_the_gvl", _native_is_current_thread_holding_the_gvl, 0);
  rb_define_singleton_method(
    testing_module,
    "_native_release_gvl_and_call_is_current_thread_holding_the_gvl",
    _native_release_gvl_and_call_is_current_thread_holding_the_gvl,
    0
  );
  rb_define_singleton_method(testing_module, "_native_install_holding_the_gvl_signal_handler", _native_install_holding_the_gvl_signal_handler, 0);
  rb_define_singleton_method(testing_module, "_native_trigger_holding_the_gvl_signal_handler_on", _native_trigger_holding_the_gvl_signal_handler_on, 1);
  rb_define_singleton_method(testing_module, "_native_enforce_success", _native_enforce_success, 2);
}

static VALUE native_working_p(DDTRACE_UNUSED VALUE _self) {
  self_test_clock_id();

  return Qtrue;
}

struct trigger_grab_gvl_and_raise_arguments {
  VALUE exception_class;
  char *test_message;
  int test_message_arg;
};

static VALUE _native_grab_gvl_and_raise(DDTRACE_UNUSED VALUE _self, VALUE exception_class, VALUE test_message, VALUE test_message_arg, VALUE release_gvl) {
  ENFORCE_TYPE(test_message, T_STRING);

  struct trigger_grab_gvl_and_raise_arguments args;

  args.exception_class = exception_class;
  args.test_message = StringValueCStr(test_message);
  args.test_message_arg = test_message_arg != Qnil ? NUM2INT(test_message_arg) : -1;

  if (RTEST(release_gvl)) {
    rb_thread_call_without_gvl(trigger_grab_gvl_and_raise, &args, NULL, NULL);
  } else {
    grab_gvl_and_raise(args.exception_class, "%s", args.test_message);
  }

  rb_raise(rb_eRuntimeError, "Failed to raise exception in _native_grab_gvl_and_raise; this should never happen");
}

static void *trigger_grab_gvl_and_raise(void *trigger_args) {
  struct trigger_grab_gvl_and_raise_arguments *args = (struct trigger_grab_gvl_and_raise_arguments *) trigger_args;

  if (args->test_message_arg >= 0) {
    grab_gvl_and_raise(args->exception_class, "%s%d", args->test_message, args->test_message_arg);
  } else {
    grab_gvl_and_raise(args->exception_class, "%s", args->test_message);
  }

  return NULL;
}

struct trigger_grab_gvl_and_raise_syserr_arguments {
  int syserr_errno;
  char *test_message;
  int test_message_arg;
};

static VALUE _native_grab_gvl_and_raise_syserr(DDTRACE_UNUSED VALUE _self, VALUE syserr_errno, VALUE test_message, VALUE test_message_arg, VALUE release_gvl) {
  ENFORCE_TYPE(test_message, T_STRING);

  struct trigger_grab_gvl_and_raise_syserr_arguments args;

  args.syserr_errno = NUM2INT(syserr_errno);
  args.test_message = StringValueCStr(test_message);
  args.test_message_arg = test_message_arg != Qnil ? NUM2INT(test_message_arg) : -1;

  if (RTEST(release_gvl)) {
    rb_thread_call_without_gvl(trigger_grab_gvl_and_raise_syserr, &args, NULL, NULL);
  } else {
    grab_gvl_and_raise_syserr(args.syserr_errno, "%s", args.test_message);
  }

  rb_raise(rb_eRuntimeError, "Failed to raise exception in _native_grab_gvl_and_raise_syserr; this should never happen");
}

static void *trigger_grab_gvl_and_raise_syserr(void *trigger_args) {
  struct trigger_grab_gvl_and_raise_syserr_arguments *args = (struct trigger_grab_gvl_and_raise_syserr_arguments *) trigger_args;

  if (args->test_message_arg >= 0) {
    grab_gvl_and_raise_syserr(args->syserr_errno, "%s%d", args->test_message, args->test_message_arg);
  } else {
    grab_gvl_and_raise_syserr(args->syserr_errno, "%s", args->test_message);
  }

  return NULL;
}

static VALUE _native_ddtrace_rb_ractor_main_p(DDTRACE_UNUSED VALUE _self) {
  return ddtrace_rb_ractor_main_p() ? Qtrue : Qfalse;
}

static VALUE _native_is_current_thread_holding_the_gvl(DDTRACE_UNUSED VALUE _self) {
  return ((bool) testing_is_current_thread_holding_the_gvl(NULL)) ? Qtrue : Qfalse;
}

static VALUE _native_release_gvl_and_call_is_current_thread_holding_the_gvl(DDTRACE_UNUSED VALUE _self) {
  return ((bool) rb_thread_call_without_gvl(testing_is_current_thread_holding_the_gvl, NULL, NULL, NULL)) ? Qtrue : Qfalse;
}

static void *testing_is_current_thread_holding_the_gvl(DDTRACE_UNUSED void *_unused) {
  return (void *) is_current_thread_holding_the_gvl();
}

static VALUE _native_install_holding_the_gvl_signal_handler(DDTRACE_UNUSED VALUE _self) {
  install_sigprof_signal_handler(holding_the_gvl_signal_handler, "holding_the_gvl_signal_handler");
  return Qtrue;
}

static pthread_mutex_t holding_the_gvl_signal_handler_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t holding_the_gvl_signal_handler_executed = PTHREAD_COND_INITIALIZER;
static VALUE holding_the_gvl_signal_handler_result[3];

// Ruby VM API that is exported but not present in the header files. Only used by holding_the_gvl_signal_handler below and SHOULD NOT
// be used in any other situation. See the comments on is_current_thread_holding_the_gvl for details.
int ruby_thread_has_gvl_p(void);

static void holding_the_gvl_signal_handler(DDTRACE_UNUSED int _signal, DDTRACE_UNUSED siginfo_t *_info, DDTRACE_UNUSED void *_ucontext) {
  pthread_mutex_lock(&holding_the_gvl_signal_handler_mutex);

  VALUE test_executed = Qtrue;
  VALUE ruby_thread_has_gvl_p_result = ruby_thread_has_gvl_p() ? Qtrue : Qfalse;
  VALUE is_current_thread_holding_the_gvl_result = is_current_thread_holding_the_gvl() ? Qtrue : Qfalse;

  holding_the_gvl_signal_handler_result[0] = test_executed;
  holding_the_gvl_signal_handler_result[1] = ruby_thread_has_gvl_p_result;
  holding_the_gvl_signal_handler_result[2] = is_current_thread_holding_the_gvl_result;

  pthread_cond_broadcast(&holding_the_gvl_signal_handler_executed);
  pthread_mutex_unlock(&holding_the_gvl_signal_handler_mutex);
}

static VALUE _native_trigger_holding_the_gvl_signal_handler_on(DDTRACE_UNUSED VALUE _self, VALUE background_thread) {
  holding_the_gvl_signal_handler_result[0] = Qfalse;
  holding_the_gvl_signal_handler_result[1] = Qfalse;
  holding_the_gvl_signal_handler_result[2] = Qfalse;

  rb_nativethread_id_t thread = pthread_id_for(background_thread);

  ENFORCE_SUCCESS_GVL(pthread_mutex_lock(&holding_the_gvl_signal_handler_mutex));

  // We keep trying for ~5 seconds (500 x 10ms) to try to avoid any flakiness if the test machine is a bit slow
  for (int tries = 0; holding_the_gvl_signal_handler_result[0] == Qfalse && tries < 500; tries++) {
    pthread_kill(thread, SIGPROF);

    // pthread_cond_timedwait is simply awful -- the deadline is based on wall-clock using a struct timespec, so we need
    // all of the below complexity just to tell it "timeout is 10ms". The % limit dance below is needed because the
    // `tv_nsec` part of a timespec can't go over the limit.
    struct timespec deadline;
    clock_gettime(CLOCK_REALTIME, &deadline);

    unsigned int timeout_ns = MILLIS_AS_NS(10);
    unsigned int tv_nsec_limit = SECONDS_AS_NS(1);
    if ((deadline.tv_nsec + timeout_ns) < tv_nsec_limit) {
      deadline.tv_nsec += timeout_ns;
    } else {
      deadline.tv_nsec = (deadline.tv_nsec + timeout_ns) % tv_nsec_limit;
      deadline.tv_sec++;
    }

    int error = pthread_cond_timedwait(&holding_the_gvl_signal_handler_executed, &holding_the_gvl_signal_handler_mutex, &deadline);
    if (error && error != ETIMEDOUT) ENFORCE_SUCCESS_GVL(error);
  }

  ENFORCE_SUCCESS_GVL(pthread_mutex_unlock(&holding_the_gvl_signal_handler_mutex));

  replace_sigprof_signal_handler_with_empty_handler(holding_the_gvl_signal_handler);

  if (holding_the_gvl_signal_handler_result[0] == Qfalse) rb_raise(rb_eRuntimeError, "Could not signal background_thread");

  VALUE result = rb_hash_new();
  rb_hash_aset(result, ID2SYM(rb_intern("ruby_thread_has_gvl_p")), holding_the_gvl_signal_handler_result[1]);
  rb_hash_aset(result, ID2SYM(rb_intern("is_current_thread_holding_the_gvl")), holding_the_gvl_signal_handler_result[2]);
  return result;
}

static VALUE _native_enforce_success(DDTRACE_UNUSED VALUE _self, VALUE syserr_errno, VALUE with_gvl) {
  if (RTEST(with_gvl)) {
    ENFORCE_SUCCESS_GVL(NUM2INT(syserr_errno));
  } else {
    rb_thread_call_without_gvl(trigger_enforce_success, (void *) (intptr_t) NUM2INT(syserr_errno), NULL, NULL);
  }

  return Qtrue;
}

static void *trigger_enforce_success(void *trigger_args) {
  intptr_t syserr_errno = (intptr_t) trigger_args;
  ENFORCE_SUCCESS_NO_GVL(syserr_errno);
  return NULL;
}

#include <ruby.h>
#include <ruby/thread.h>
#include <ruby/thread_native.h>
#include <ruby/debug.h>
#include <stdbool.h>
#include <signal.h>
#include "helpers.h"
#include "ruby_helpers.h"
#include "collectors_cpu_and_wall_time.h"

// Used to trigger the periodic execution of Collectors::CpuAndWallTime, which implements all of the sampling logic
// itself; this class only implements the "doing it periodically" part.
//
// This file implements the native bits of the Datadog::Profiling::Collectors::CpuAndWallTimeWorker class

// ---
// Here be dragons: This component is quite fiddly and probably one of the more complex in the profiler as it deals with
// multiple threads, signal handlers, global state, etc.
//
// ## Design notes for this class:
//
// ### Constraints
//
// Currently, sampling Ruby threads requires calling Ruby VM APIs that are only safe to call while holding on to the
// global VM lock (and are not async-signal safe).
//
// @ivoanjo: As a note, I don't we should think of this constraint is set in stone. Since can reach into the Ruby
// internals, we may be able to figure out a way of overcoming it. But it's definitely going to be hard so for now
// we're considering it as a given.
//
// ### Flow for triggering samples
//
// The flow for triggering samples is as follows:
//
// 1. Inside the `run_sampling_trigger_loop` function (running in the `CpuAndWallTimeWorker` background thread),
// a `SIGPROF` signal gets sent to the current process.
//
// 2. The `handle_sampling_signal` signal handler function gets called to handle the `SIGPROF` signal.
//
//   Which thread the signal handler function gets called by the operating system is quite important. We need to perform
// an operation -- calling the `rb_postponed_job_register_one` API -- that can only be called from the thread that
// is holding on to the global VM lock. So this is the thread we're "hoping" our signal lands on.
//
//   The signal never lands on the `CpuAndWallTimeWorker` background thread because we explicitly block it off from that
// thread in `block_sigprof_signal_handler_from_running_in_current_thread`.
//
//   If the signal lands on a thread that is not holding onto the global VM lock, we can't proceed to the next step,
// and we need to restart the sampling flow from step 1. (There's still quite a few improvements we can make here,
// but this is the current state of the implementation).
//
// 3. Inside `handle_sampling_signal`, if it's getting executed by the Ruby thread that is holding the global VM lock,
// we can call `rb_postponed_job_register_one` to ask the Ruby VM to call our `sample_from_postponed_job` function
// "as soon as it can".
//
// 4. The Ruby VM calls our `sample_from_postponed_job` from a thread holding the global VM lock. A sample is recorded by
// calling `cpu_and_wall_time_collector_sample`.
//
// ---

// Contains state for a single CpuAndWallTimeWorker instance
struct cpu_and_wall_time_worker_state {
  // Important: This is not atomic nor is it guaranteed to replace memory barriers and the like. Aka this works for
  // telling the sampling trigger loop to stop, but if we ever need to communicate more, we should move to actual
  // atomic operations. stdatomic.h seems a nice thing to reach out for.
  volatile bool should_run;

  VALUE cpu_and_wall_time_collector_instance;
  // When something goes wrong during sampling, we record the Ruby exception here, so that it can be "re-raised" on
  // the CpuAndWallTimeWorker thread
  VALUE failure_exception;
};

static VALUE _native_new(VALUE klass);
static VALUE _native_initialize(DDTRACE_UNUSED VALUE _self, VALUE self_instance, VALUE cpu_and_wall_time_collector_instance);
static void cpu_and_wall_time_worker_typed_data_mark(void *state_ptr);
static VALUE _native_sampling_loop(VALUE self, VALUE instance);
static void install_sigprof_signal_handler(void);
static void remove_sigprof_signal_handler(void);
static void block_sigprof_signal_handler_from_running_in_current_thread(void);
static void handle_sampling_signal(DDTRACE_UNUSED int _signal, DDTRACE_UNUSED siginfo_t *_info, DDTRACE_UNUSED void *_ucontext);
static void *run_sampling_trigger_loop(void *state_ptr);
static void interrupt_sampling_trigger_loop(void *state_ptr);
static void sample_from_postponed_job(DDTRACE_UNUSED void *_unused);
static VALUE handle_sampling_failure(VALUE self_instance, VALUE exception);

// Global state -- be very careful when accessing or modifying it

// This needs to be global because we access it from the signal handler. This MUST only be written from a thread holding
// the global VM lock (e.g. we piggy back on it to ensure correctness).
//
// TODO: This MUST be reset when the Ruby VM forks
static VALUE active_sampler_instance = Qnil;

void collectors_cpu_and_wall_time_worker_init(VALUE profiling_module) {
  VALUE collectors_module = rb_define_module_under(profiling_module, "Collectors");
  VALUE collectors_cpu_and_wall_time_worker_class = rb_define_class_under(collectors_module, "CpuAndWallTimeWorker", rb_cObject);

  // Instances of the CpuAndWallTimeWorker class are "TypedData" objects.
  // "TypedData" objects are special objects in the Ruby VM that can wrap C structs.
  // In this case, it wraps the cpu_and_wall_time_worker_state.
  //
  // Because Ruby doesn't know how to initialize native-level structs, we MUST override the allocation function for objects
  // of this class so that we can manage this part. Not overriding or disabling the allocation function is a common
  // gotcha for "TypedData" objects that can very easily lead to VM crashes, see for instance
  // https://bugs.ruby-lang.org/issues/18007 for a discussion around this.
  rb_define_alloc_func(collectors_cpu_and_wall_time_worker_class, _native_new);

  rb_define_singleton_method(collectors_cpu_and_wall_time_worker_class, "_native_initialize", _native_initialize, 2);
  rb_define_singleton_method(collectors_cpu_and_wall_time_worker_class, "_native_sampling_loop", _native_sampling_loop, 1);
}

// This structure is used to define a Ruby object that stores a pointer to a struct cpu_and_wall_time_worker_state
// See also https://github.com/ruby/ruby/blob/master/doc/extension.rdoc for how this works
static const rb_data_type_t cpu_and_wall_time_worker_typed_data = {
  .wrap_struct_name = "Datadog::Profiling::Collectors::CpuAndWallTimeWorker",
  .function = {
    .dmark = cpu_and_wall_time_worker_typed_data_mark,
    .dfree = RUBY_DEFAULT_FREE,
    .dsize = NULL, // We don't track profile memory usage (although it'd be cool if we did!)
    //.dcompact = NULL, // FIXME: Add support for compaction
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE _native_new(VALUE klass) {
  struct cpu_and_wall_time_worker_state *state = ruby_xcalloc(1, sizeof(struct cpu_and_wall_time_worker_state));

  state->should_run = false;
  state->cpu_and_wall_time_collector_instance = Qnil;
  state->failure_exception = Qnil;

  return TypedData_Wrap_Struct(klass, &cpu_and_wall_time_worker_typed_data, state);
}

static VALUE _native_initialize(DDTRACE_UNUSED VALUE _self, VALUE self_instance, VALUE cpu_and_wall_time_collector_instance) {
  enforce_cpu_and_wall_time_collector_instance(cpu_and_wall_time_collector_instance);

  struct cpu_and_wall_time_worker_state *state;
  TypedData_Get_Struct(self_instance, struct cpu_and_wall_time_worker_state, &cpu_and_wall_time_worker_typed_data, state);

  state->cpu_and_wall_time_collector_instance = cpu_and_wall_time_collector_instance;

  return Qtrue;
}

// Since our state contains references to Ruby objects, we need to tell the Ruby GC about them
static void cpu_and_wall_time_worker_typed_data_mark(void *state_ptr) {
  struct cpu_and_wall_time_worker_state *state = (struct cpu_and_wall_time_worker_state *) state_ptr;

  rb_gc_mark(state->cpu_and_wall_time_collector_instance);
  rb_gc_mark(state->failure_exception);
}

// Called in a background thread created in CpuAndWallTimeWorker#start
static VALUE _native_sampling_loop(DDTRACE_UNUSED VALUE _self, VALUE instance) {
  if (active_sampler_instance != Qnil) {
    rb_raise(rb_eRuntimeError, "Could not start CpuAndWallTimeWorker: There's already another instance of CpuAndWallTimeWorker active");
  }

  struct cpu_and_wall_time_worker_state *state;
  TypedData_Get_Struct(instance, struct cpu_and_wall_time_worker_state, &cpu_and_wall_time_worker_typed_data, state);

  // This write to a global is thread-safe BECAUSE we're still holding on to the global VM lock at this point
  active_sampler_instance = instance;

  state->should_run = true;

  block_sigprof_signal_handler_from_running_in_current_thread(); // We want to interrupt the thread with the global VM lock, never this one

  install_sigprof_signal_handler();

  // Release the global VM lock, and start the sampling loop
  rb_thread_call_without_gvl(run_sampling_trigger_loop, state, interrupt_sampling_trigger_loop, state);

  // Once run_sampling_trigger_loop returns, sampling has either failed with some issue or we were asked to stop, so let's clean up
  remove_sigprof_signal_handler();

  active_sampler_instance = Qnil;

  // If we stopped sampling due to an exception, re-raise it (in the background thread)
  if (state->failure_exception != Qnil) rb_exc_raise(state->failure_exception);

  // Ensure that instance is not garbage collected while the native sampling loop is running; this is probably not needed, but just in case
  RB_GC_GUARD(instance);

  return Qnil;
}

static void install_sigprof_signal_handler(void) {
  struct sigaction existing_signal_handler_config = {0};
  struct sigaction signal_handler_config = {
    .sa_flags = SA_RESTART | SA_SIGINFO,
    .sa_sigaction = handle_sampling_signal
  };
  sigemptyset(&signal_handler_config.sa_mask);

  if (sigaction(SIGPROF, &signal_handler_config, &existing_signal_handler_config) != 0) {
    rb_sys_fail("Could not start CpuAndWallTimeWorker: Could not install signal handler");
  }

  if (existing_signal_handler_config.sa_handler != NULL || existing_signal_handler_config.sa_sigaction != NULL) {
    // A previous signal handler already existed. Currently we don't support this situation, so let's just back out
    // of the installation.

    if (sigaction(SIGPROF, &existing_signal_handler_config, NULL) != 0) {
      rb_sys_fail(
        "Could not start CpuAndWallTimeWorker: Could not re-install pre-existing SIGPROF signal handler. This may break the component had installed it."
      );
    }

    rb_raise(rb_eRuntimeError, "Could not start CpuAndWallTimeWorker: There's a pre-existing SIGPROF signal handler");
  }
}

static void remove_sigprof_signal_handler(void) {
  struct sigaction signal_handler_config = {
    .sa_handler = SIG_DFL, // Reset back to default
    .sa_flags = SA_RESTART // Unclear if this is actually needed/does anything at all
  };
  sigemptyset(&signal_handler_config.sa_mask);

  if (sigaction(SIGPROF, &signal_handler_config, NULL) != 0) rb_sys_fail("Failure while removing the signal handler");
}

static void block_sigprof_signal_handler_from_running_in_current_thread(void) {
  sigset_t signals_to_block;
  sigemptyset(&signals_to_block);
  sigaddset(&signals_to_block, SIGPROF);
  pthread_sigmask(SIG_BLOCK, &signals_to_block, NULL);
}

static void handle_sampling_signal(DDTRACE_UNUSED int _signal, DDTRACE_UNUSED siginfo_t *_info, DDTRACE_UNUSED void *_ucontext) {
  if (!ruby_native_thread_p() && !ruby_thread_has_gvl_p()) {
    return; // Not safe to enqueue a sample from this thread
  }

  // We implicitly assume there can be no nested calls to handle_sampling_signal because
  // a) we get triggered using SIGPROF, and the docs state second SIGPROF will not interrupt this one
  // b) we validate we are in the thread that has the global VM lock; if a different thread gets a signal, it will return early
  //    because it will not have the global VM lock
  // TODO: Validate that this does not impact Ractors

  // Note: rb_postponed_job_register_one ensures that if there's a previous sample_from_postponed_job queued for execution
  // then we will not queue a second one. It does this by doing a linear scan on the existing jobs; in the future we
  // may wat to implement that check ourselves.
  int result = rb_postponed_job_register_one(0, sample_from_postponed_job, NULL);
  // TODO: Do something with result (potentially update tracking counters?)
}

// The actual sampling trigger loop always runs **without** the global vm lock.
static void *run_sampling_trigger_loop(void *state_ptr) {
  struct cpu_and_wall_time_worker_state *state = (struct cpu_and_wall_time_worker_state *) state_ptr;

  struct timespec time_between_signals = {.tv_nsec = 10 * 1000 * 1000 /* 10ms */};

  while (state->should_run) {
    // TODO: This is still a placeholder for a more complex mechanism. In particular:
    // * We probably want to signal a particular thread or threads, not the process in general
    // * We probably want to track if a signal landed on the thread holding the global vm lock and do something about it
    // * We want to do more than having a fixed sampling rate

    kill(getpid(), SIGPROF);
    nanosleep(&time_between_signals, NULL);
  }

  return NULL; // Unused
}

// This is called by the Ruby VM when it wants to shut down the background thread
static void interrupt_sampling_trigger_loop(void *state_ptr) {
  struct cpu_and_wall_time_worker_state *state = (struct cpu_and_wall_time_worker_state *) state_ptr;

  state->should_run = false;
}

static void sample_from_postponed_job(DDTRACE_UNUSED void *_unused) {
  VALUE instance = active_sampler_instance;

  // This can potentially happen if the CpuAndWallTimeWorker was stopped while the postponed job was waiting to be executed; nothing to do
  if (instance == Qnil) return;

  struct cpu_and_wall_time_worker_state *state;
  TypedData_Get_Struct(instance, struct cpu_and_wall_time_worker_state, &cpu_and_wall_time_worker_typed_data, state);

  // Trigger sampling using the Collectors::CpuAndWallTime; rescue against any exceptions that happen during sampling
  VALUE (*function_to_call_safely)(VALUE) = cpu_and_wall_time_collector_sample;
  VALUE function_to_call_safely_arg = state->cpu_and_wall_time_collector_instance;
  VALUE (*exception_handler_function)(VALUE, VALUE) = handle_sampling_failure;
  VALUE exception_handler_function_arg = instance;
  rb_rescue2(
    function_to_call_safely,
    function_to_call_safely_arg,
    exception_handler_function,
    exception_handler_function_arg,
    rb_eException, // rb_eException is the base class of all Ruby exceptions
    0 // Required by API to be the last argument
  );
}

static VALUE handle_sampling_failure(VALUE self_instance, VALUE exception) {
  struct cpu_and_wall_time_worker_state *state;
  TypedData_Get_Struct(self_instance, struct cpu_and_wall_time_worker_state, &cpu_and_wall_time_worker_typed_data, state);

  state->should_run = false;
  state->failure_exception = exception;

  return Qnil;
}

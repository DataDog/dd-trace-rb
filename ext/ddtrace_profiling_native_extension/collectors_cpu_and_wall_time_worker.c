#include <ruby.h>
#include <ruby/thread.h>
#include <ruby/thread_native.h>
#include <ruby/debug.h>
#include <stdbool.h>
#include <signal.h>
#include "helpers.h"
#include "ruby_helpers.h"
#include "collectors_cpu_and_wall_time.h"
#include "private_vm_api_access.h"

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
// global VM lock (and are not async-signal safe -- cannot be called from a signal handler).
//
// @ivoanjo: As a note, I don't think we should think of this constraint as set in stone. Since can reach into the Ruby
// internals, we may be able to figure out a way of overcoming it. But it's definitely going to be hard so for now
// we're considering it as a given.
//
// ### Flow for triggering CPU/Wall-time samples
//
// The flow for triggering samples is as follows:
//
// 1. Inside the `run_sampling_trigger_loop` function (running in the `CpuAndWallTimeWorker` background thread),
// a `SIGPROF` signal gets sent to the current process.
//
// 2. The `handle_sampling_signal` signal handler function gets called to handle the `SIGPROF` signal.
//
//   Which thread the signal handler function gets called on by the operating system is quite important. We need to perform
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
// ### TracePoints and Forking
//
// When the Ruby VM forks, the CPU/Wall-time profiling stops naturally because it's triggered by a background thread
// that doesn't get automatically restarted by the VM on the child process. (The profiler does trigger its restart at
// some point -- see `Profiling::Tasks::Setup` for details).
//
// But this doesn't apply to any `TracePoint`s this class may use, which will continue to be active. Thus, we need to
// always remember consider this case of -- the worker thread may not be alive but the `TracePoint`s can continue to
// trigger samples.
//
// ---

// Contains state for a single CpuAndWallTimeWorker instance
struct cpu_and_wall_time_worker_state {
  // Important: This is not atomic nor is it guaranteed to replace memory barriers and the like. Aka this works for
  // telling the sampling trigger loop to stop, but if we ever need to communicate more, we should move to actual
  // atomic operations. stdatomic.h seems a nice thing to reach out for.
  volatile bool should_run;
  bool gc_profiling_enabled;
  VALUE cpu_and_wall_time_collector_instance;

  // When something goes wrong during sampling, we record the Ruby exception here, so that it can be "re-raised" on
  // the CpuAndWallTimeWorker thread
  VALUE failure_exception;

  // Used to get gc start/finish information
  VALUE gc_tracepoint;
};

static VALUE _native_new(VALUE klass);
static VALUE _native_initialize(
  DDTRACE_UNUSED VALUE _self,
  VALUE self_instance,
  VALUE cpu_and_wall_time_collector_instance,
  VALUE gc_profiling_enabled
);
static void cpu_and_wall_time_worker_typed_data_mark(void *state_ptr);
static VALUE _native_sampling_loop(VALUE self, VALUE instance);
static VALUE _native_stop(DDTRACE_UNUSED VALUE _self, VALUE self_instance);
static VALUE stop(VALUE self_instance, VALUE optional_exception);
static void install_sigprof_signal_handler(void (*signal_handler_function)(int, siginfo_t *, void *));
static void remove_sigprof_signal_handler(void);
static void block_sigprof_signal_handler_from_running_in_current_thread(void);
static void handle_sampling_signal(DDTRACE_UNUSED int _signal, DDTRACE_UNUSED siginfo_t *_info, DDTRACE_UNUSED void *_ucontext);
static void *run_sampling_trigger_loop(void *state_ptr);
static void interrupt_sampling_trigger_loop(void *state_ptr);
static void sample_from_postponed_job(DDTRACE_UNUSED void *_unused);
static VALUE handle_sampling_failure(VALUE self_instance, VALUE exception);
static VALUE _native_current_sigprof_signal_handler(DDTRACE_UNUSED VALUE self);
static VALUE release_gvl_and_run_sampling_trigger_loop(VALUE instance);
static VALUE _native_is_running(DDTRACE_UNUSED VALUE self, VALUE instance);
static void testing_signal_handler(DDTRACE_UNUSED int _signal, DDTRACE_UNUSED siginfo_t *_info, DDTRACE_UNUSED void *_ucontext);
static VALUE _native_install_testing_signal_handler(DDTRACE_UNUSED VALUE self);
static VALUE _native_remove_testing_signal_handler(DDTRACE_UNUSED VALUE self);
static VALUE _native_trigger_sample(DDTRACE_UNUSED VALUE self);
static VALUE _native_gc_tracepoint(DDTRACE_UNUSED VALUE self, VALUE instance);
static void on_gc_event(VALUE tracepoint_data, DDTRACE_UNUSED void *unused);
static void after_gc_from_postponed_job(DDTRACE_UNUSED void *_unused);
static void safely_call(VALUE (*function_to_call_safely)(VALUE), VALUE function_to_call_safely_arg, VALUE instance);
static VALUE _native_simulate_handle_sampling_signal(DDTRACE_UNUSED VALUE self);
static VALUE _native_simulate_sample_from_postponed_job(DDTRACE_UNUSED VALUE self);
static VALUE _native_reset_after_fork(DDTRACE_UNUSED VALUE self, VALUE instance);

// Global state -- be very careful when accessing or modifying it

// Note: Global state must only be mutated while holding the global VM lock (we piggy back on it to ensure correctness).
// The active_sampler_instance needs to be global because we access it from the signal handler.
static VALUE active_sampler_instance = Qnil;
// ...We also store active_sampler_owner_thread to be able to tell who the active_sampler_instance belongs to (and also
// to detect when it is outdated)
static VALUE active_sampler_owner_thread = Qnil;

void collectors_cpu_and_wall_time_worker_init(VALUE profiling_module) {
  rb_global_variable(&active_sampler_instance);
  rb_global_variable(&active_sampler_owner_thread);

  VALUE collectors_module = rb_define_module_under(profiling_module, "Collectors");
  VALUE collectors_cpu_and_wall_time_worker_class = rb_define_class_under(collectors_module, "CpuAndWallTimeWorker", rb_cObject);
  // Hosts methods used for testing the native code using RSpec
  VALUE testing_module = rb_define_module_under(collectors_cpu_and_wall_time_worker_class, "Testing");

  // Instances of the CpuAndWallTimeWorker class are "TypedData" objects.
  // "TypedData" objects are special objects in the Ruby VM that can wrap C structs.
  // In this case, it wraps the cpu_and_wall_time_worker_state.
  //
  // Because Ruby doesn't know how to initialize native-level structs, we MUST override the allocation function for objects
  // of this class so that we can manage this part. Not overriding or disabling the allocation function is a common
  // gotcha for "TypedData" objects that can very easily lead to VM crashes, see for instance
  // https://bugs.ruby-lang.org/issues/18007 for a discussion around this.
  rb_define_alloc_func(collectors_cpu_and_wall_time_worker_class, _native_new);

  rb_define_singleton_method(collectors_cpu_and_wall_time_worker_class, "_native_initialize", _native_initialize, 3);
  rb_define_singleton_method(collectors_cpu_and_wall_time_worker_class, "_native_sampling_loop", _native_sampling_loop, 1);
  rb_define_singleton_method(collectors_cpu_and_wall_time_worker_class, "_native_stop", _native_stop, 1);
  rb_define_singleton_method(collectors_cpu_and_wall_time_worker_class, "_native_reset_after_fork", _native_reset_after_fork, 1);
  rb_define_singleton_method(testing_module, "_native_current_sigprof_signal_handler", _native_current_sigprof_signal_handler, 0);
  rb_define_singleton_method(testing_module, "_native_is_running?", _native_is_running, 1);
  rb_define_singleton_method(testing_module, "_native_install_testing_signal_handler", _native_install_testing_signal_handler, 0);
  rb_define_singleton_method(testing_module, "_native_remove_testing_signal_handler", _native_remove_testing_signal_handler, 0);
  rb_define_singleton_method(testing_module, "_native_trigger_sample", _native_trigger_sample, 0);
  rb_define_singleton_method(testing_module, "_native_gc_tracepoint", _native_gc_tracepoint, 1);
  rb_define_singleton_method(testing_module, "_native_simulate_handle_sampling_signal", _native_simulate_handle_sampling_signal, 0);
  rb_define_singleton_method(testing_module, "_native_simulate_sample_from_postponed_job", _native_simulate_sample_from_postponed_job, 0);
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
  state->gc_profiling_enabled = false;
  state->cpu_and_wall_time_collector_instance = Qnil;
  state->failure_exception = Qnil;
  state->gc_tracepoint = Qnil;

  return TypedData_Wrap_Struct(klass, &cpu_and_wall_time_worker_typed_data, state);
}

static VALUE _native_initialize(
  DDTRACE_UNUSED VALUE _self,
  VALUE self_instance,
  VALUE cpu_and_wall_time_collector_instance,
  VALUE gc_profiling_enabled
) {
  ENFORCE_BOOLEAN(gc_profiling_enabled);

  struct cpu_and_wall_time_worker_state *state;
  TypedData_Get_Struct(self_instance, struct cpu_and_wall_time_worker_state, &cpu_and_wall_time_worker_typed_data, state);

  state->gc_profiling_enabled = (gc_profiling_enabled == Qtrue);
  state->cpu_and_wall_time_collector_instance = enforce_cpu_and_wall_time_collector_instance(cpu_and_wall_time_collector_instance);
  state->gc_tracepoint = rb_tracepoint_new(Qnil, RUBY_INTERNAL_EVENT_GC_ENTER | RUBY_INTERNAL_EVENT_GC_EXIT, on_gc_event, NULL /* unused */);

  return Qtrue;
}

// Since our state contains references to Ruby objects, we need to tell the Ruby GC about them
static void cpu_and_wall_time_worker_typed_data_mark(void *state_ptr) {
  struct cpu_and_wall_time_worker_state *state = (struct cpu_and_wall_time_worker_state *) state_ptr;

  rb_gc_mark(state->cpu_and_wall_time_collector_instance);
  rb_gc_mark(state->failure_exception);
  rb_gc_mark(state->gc_tracepoint);
}

// Called in a background thread created in CpuAndWallTimeWorker#start
static VALUE _native_sampling_loop(DDTRACE_UNUSED VALUE _self, VALUE instance) {
  struct cpu_and_wall_time_worker_state *state;
  TypedData_Get_Struct(instance, struct cpu_and_wall_time_worker_state, &cpu_and_wall_time_worker_typed_data, state);

  if (active_sampler_owner_thread != Qnil) {
    if (is_thread_alive(active_sampler_owner_thread)) {
      rb_raise(
        rb_eRuntimeError,
        "Could not start CpuAndWallTimeWorker: There's already another instance of CpuAndWallTimeWorker active in a different thread"
      );
    } else {
      // The previously active thread seems to have died without cleaning up after itself.
      // In this case, we can still go ahead and start the profiler BUT we make sure to disable any existing GC tracepoint
      // first as:
      // a) If this is a new instance of the CpuAndWallTimeWorker, we don't want the tracepoint from the old instance
      //    being kept around
      // b) If this is the same instance of the CpuAndWallTimeWorker if we call enable on a tracepoint that is already
      //    enabled, it will start firing more than once, see https://bugs.ruby-lang.org/issues/19114 for details.

      struct cpu_and_wall_time_worker_state *old_state;
      TypedData_Get_Struct(active_sampler_instance, struct cpu_and_wall_time_worker_state, &cpu_and_wall_time_worker_typed_data, old_state);
      rb_tracepoint_disable(old_state->gc_tracepoint);
    }
  }

  // This write to a global is thread-safe BECAUSE we're still holding on to the global VM lock at this point
  active_sampler_instance = instance;
  active_sampler_owner_thread = rb_thread_current();

  state->should_run = true;

  block_sigprof_signal_handler_from_running_in_current_thread(); // We want to interrupt the thread with the global VM lock, never this one

  install_sigprof_signal_handler(handle_sampling_signal);
  if (state->gc_profiling_enabled) rb_tracepoint_enable(state->gc_tracepoint);

  // Release GVL, get to the actual work!
  int exception_state;
  rb_protect(release_gvl_and_run_sampling_trigger_loop, instance, &exception_state);

  // The sample trigger loop finished (either cleanly or with an error); let's clean up

  rb_tracepoint_disable(state->gc_tracepoint);
  remove_sigprof_signal_handler();
  active_sampler_instance = Qnil;
  active_sampler_owner_thread = Qnil;

  // Ensure that instance is not garbage collected while the native sampling loop is running; this is probably not needed, but just in case
  RB_GC_GUARD(instance);

  if (exception_state) rb_jump_tag(exception_state); // Re-raise any exception that happened

  return Qnil;
}

static VALUE _native_stop(DDTRACE_UNUSED VALUE _self, VALUE self_instance) {
  return stop(self_instance, /* optional_exception: */ Qnil);
}

static VALUE stop(VALUE self_instance, VALUE optional_exception) {
  struct cpu_and_wall_time_worker_state *state;
  TypedData_Get_Struct(self_instance, struct cpu_and_wall_time_worker_state, &cpu_and_wall_time_worker_typed_data, state);

  state->should_run = false;
  state->failure_exception = optional_exception;

  // Disable the GC tracepoint as soon as possible, so the VM doesn't keep on calling it
  rb_tracepoint_disable(state->gc_tracepoint);

  return Qtrue;
}

static void install_sigprof_signal_handler(void (*signal_handler_function)(int, siginfo_t *, void *)) {
  struct sigaction existing_signal_handler_config = {.sa_sigaction = NULL};
  struct sigaction signal_handler_config = {
    .sa_flags = SA_RESTART | SA_SIGINFO,
    .sa_sigaction = signal_handler_function
  };
  sigemptyset(&signal_handler_config.sa_mask);

  if (sigaction(SIGPROF, &signal_handler_config, &existing_signal_handler_config) != 0) {
    rb_sys_fail("Could not start CpuAndWallTimeWorker: Could not install signal handler");
  }

  // In some corner cases (e.g. after a fork), our signal handler may still be around, and that's ok
  if (existing_signal_handler_config.sa_sigaction == handle_sampling_signal) return;

  if (existing_signal_handler_config.sa_handler != NULL || existing_signal_handler_config.sa_sigaction != NULL) {
    // A previous signal handler already existed. Currently we don't support this situation, so let's just back out
    // of the installation.

    if (sigaction(SIGPROF, &existing_signal_handler_config, NULL) != 0) {
      rb_sys_fail(
        "Could not start CpuAndWallTimeWorker: Could not re-install pre-existing SIGPROF signal handler. " \
        "This may break the component had installed it."
      );
    }

    rb_raise(rb_eRuntimeError, "Could not start CpuAndWallTimeWorker: There's a pre-existing SIGPROF signal handler");
  }
}

static void remove_sigprof_signal_handler(void) {
  struct sigaction signal_handler_config = {
    .sa_handler = SIG_DFL, // Reset back to default
    .sa_flags = SA_RESTART // TODO: Unclear if this is actually needed/does anything at all
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

// NOTE: Remember that this will run in the thread and within the scope of user code, including user C code.
// We need to be careful not to change any state that may be observed OR to restore it if we do. For instance, if anything
// we do here can set `errno`, then we must be careful to restore the old `errno` after the fact.
static void handle_sampling_signal(DDTRACE_UNUSED int _signal, DDTRACE_UNUSED siginfo_t *_info, DDTRACE_UNUSED void *_ucontext) {
  if (!ruby_thread_has_gvl_p()) {
    return; // Not safe to enqueue a sample from this thread
  }
  if (!ddtrace_rb_ractor_main_p()) {
    return; // We're not on the main Ractor; we currently don't support profiling non-main Ractors
  }

  // We implicitly assume there can be no concurrent nor nested calls to handle_sampling_signal because
  // a) we get triggered using SIGPROF, and the docs state second SIGPROF will not interrupt an existing one
  // b) we validate we are in the thread that has the global VM lock; if a different thread gets a signal, it will return early
  //    because it will not have the global VM lock
  // TODO: Validate that this does not impact Ractors

  // Note: rb_postponed_job_register_one ensures that if there's a previous sample_from_postponed_job queued for execution
  // then we will not queue a second one. It does this by doing a linear scan on the existing jobs; in the future we
  // may want to implement that check ourselves.

  // TODO: Do something with result (potentially update tracking counters?)
  /*int result =*/ rb_postponed_job_register_one(0, sample_from_postponed_job, NULL);
}

// The actual sampling trigger loop always runs **without** the global vm lock.
static void *run_sampling_trigger_loop(void *state_ptr) {
  struct cpu_and_wall_time_worker_state *state = (struct cpu_and_wall_time_worker_state *) state_ptr;

  struct timespec time_between_signals = {.tv_nsec = 10 * 1000 * 1000 /* 10ms */};

  while (state->should_run) {
    // TODO: This is still a placeholder for a more complex mechanism. In particular:
    // * We want to signal a particular thread or threads, not the process in general
    // * We want to track if a signal landed on the thread holding the global VM lock and do something about it
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
  VALUE instance = active_sampler_instance; // Read from global variable

  // This can potentially happen if the CpuAndWallTimeWorker was stopped while the postponed job was waiting to be executed; nothing to do
  if (instance == Qnil) return;

  // @ivoanjo: I'm not sure this can ever happen because `handle_sampling_signal` only enqueues this callback if
  // it's running on the main Ractor, but just in case...
  if (!ddtrace_rb_ractor_main_p()) {
    return; // We're not on the main Ractor; we currently don't support profiling non-main Ractors
  }

  struct cpu_and_wall_time_worker_state *state;
  TypedData_Get_Struct(instance, struct cpu_and_wall_time_worker_state, &cpu_and_wall_time_worker_typed_data, state);

  // Trigger sampling using the Collectors::CpuAndWallTime; rescue against any exceptions that happen during sampling
  safely_call(cpu_and_wall_time_collector_sample, state->cpu_and_wall_time_collector_instance, instance);
}

static VALUE handle_sampling_failure(VALUE self_instance, VALUE exception) { return stop(self_instance, exception); }

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTimeWorker behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_current_sigprof_signal_handler(DDTRACE_UNUSED VALUE self) {
  struct sigaction existing_signal_handler_config = {.sa_sigaction = NULL};
  if (sigaction(SIGPROF, NULL, &existing_signal_handler_config) != 0) {
    rb_sys_fail("Failed to probe existing handler");
  }

  if (existing_signal_handler_config.sa_sigaction == handle_sampling_signal) {
    return ID2SYM(rb_intern("profiling"));
  } else if (existing_signal_handler_config.sa_sigaction != NULL) {
    return ID2SYM(rb_intern("other"));
  } else {
    return Qnil;
  }
}

static VALUE release_gvl_and_run_sampling_trigger_loop(VALUE instance) {
  struct cpu_and_wall_time_worker_state *state;
  TypedData_Get_Struct(instance, struct cpu_and_wall_time_worker_state, &cpu_and_wall_time_worker_typed_data, state);

  rb_thread_call_without_gvl(run_sampling_trigger_loop, state, interrupt_sampling_trigger_loop, state);

  // If we stopped sampling due to an exception, re-raise it (now in the worker thread)
  if (state->failure_exception != Qnil) rb_exc_raise(state->failure_exception);

  return Qnil;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTimeWorker behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_is_running(DDTRACE_UNUSED VALUE self, VALUE instance) {
  return \
    (active_sampler_owner_thread != Qnil && is_thread_alive(active_sampler_owner_thread) && active_sampler_instance == instance) ?
    Qtrue : Qfalse;
}

static void testing_signal_handler(DDTRACE_UNUSED int _signal, DDTRACE_UNUSED siginfo_t *_info, DDTRACE_UNUSED void *_ucontext) {
  /* Does nothing on purpose */
}

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTimeWorker behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_install_testing_signal_handler(DDTRACE_UNUSED VALUE self) {
  install_sigprof_signal_handler(testing_signal_handler);
  return Qtrue;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTimeWorker behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_remove_testing_signal_handler(DDTRACE_UNUSED VALUE self) {
  remove_sigprof_signal_handler();
  return Qtrue;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTimeWorker behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_trigger_sample(DDTRACE_UNUSED VALUE self) {
  sample_from_postponed_job(NULL);
  return Qtrue;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTimeWorker behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_gc_tracepoint(DDTRACE_UNUSED VALUE self, VALUE instance) {
  struct cpu_and_wall_time_worker_state *state;
  TypedData_Get_Struct(instance, struct cpu_and_wall_time_worker_state, &cpu_and_wall_time_worker_typed_data, state);

  return state->gc_tracepoint;
}

// Implements tracking of cpu-time and wall-time spent doing GC. This function is called by Ruby from the `gc_tracepoint`
// when the RUBY_INTERNAL_EVENT_GC_ENTER and RUBY_INTERNAL_EVENT_GC_EXIT events are triggered.
//
// See the comments on
// * cpu_and_wall_time_collector_on_gc_start
// * cpu_and_wall_time_collector_on_gc_finish
// * cpu_and_wall_time_collector_sample_after_gc
//
// For the expected times in which to call them, and their assumptions.
//
// Safety: This function gets called while Ruby is doing garbage collection. While Ruby is doing garbage collection,
// *NO ALLOCATION* is allowed. This function, and any it calls must never trigger memory or object allocation.
// This includes exceptions and use of ruby_xcalloc (because xcalloc can trigger GC)!
static void on_gc_event(VALUE tracepoint_data, DDTRACE_UNUSED void *unused) {
  if (!ddtrace_rb_ractor_main_p()) {
    return; // We're not on the main Ractor; we currently don't support profiling non-main Ractors
  }

  int event = rb_tracearg_event_flag(rb_tracearg_from_tracepoint(tracepoint_data));
  if (event != RUBY_INTERNAL_EVENT_GC_ENTER && event != RUBY_INTERNAL_EVENT_GC_EXIT) return; // Unknown event

  VALUE instance = active_sampler_instance; // Read from global variable

  // This should not happen in a normal situation because the tracepoint is always enabled after the instance is set
  // and disabled before it is cleared, but just in case...
  if (instance == Qnil) return;

  struct cpu_and_wall_time_worker_state *state;
  if (!rb_typeddata_is_kind_of(instance, &cpu_and_wall_time_worker_typed_data)) return;
  // This should never fail the the above check passes
  TypedData_Get_Struct(instance, struct cpu_and_wall_time_worker_state, &cpu_and_wall_time_worker_typed_data, state);

  if (event == RUBY_INTERNAL_EVENT_GC_ENTER) {
    cpu_and_wall_time_collector_on_gc_start(state->cpu_and_wall_time_collector_instance);
  } else if (event == RUBY_INTERNAL_EVENT_GC_EXIT) {
    // Design: In an earlier iteration of this feature (see https://github.com/DataDog/dd-trace-rb/pull/2308) we
    // actually had a single method to implement the behavior of both cpu_and_wall_time_collector_on_gc_finish
    // and cpu_and_wall_time_collector_sample_after_gc (the latter is called via after_gc_from_postponed_job).
    //
    // Unfortunately, then we discovered the safety issue around no allocations, and thus decided to separate them -- so that
    // the sampling could run outside the tight safety constraints of the garbage collection process.
    //
    // There is a downside: The sample is now taken very very shortly afterwards the GC finishes, and not immediately
    // as the GC finishes, which means the stack captured may by affected by "skid", e.g. point slightly after where
    // it should be pointing at.
    // Alternatives to solve this would be to capture no stack for garbage collection (as we do for Java and .net);
    // making the sampling process allocation-safe (very hard); or separate stack sampling from sample recording,
    // e.g. enabling us to capture the stack in cpu_and_wall_time_collector_on_gc_finish and do the rest later
    // (medium hard).

    cpu_and_wall_time_collector_on_gc_finish(state->cpu_and_wall_time_collector_instance);
    // We use rb_postponed_job_register_one to ask Ruby to run cpu_and_wall_time_collector_sample_after_gc after if
    // fully finishes the garbage collection, so that one is allowed to do allocations and throw exceptions as usual.
    rb_postponed_job_register_one(0, after_gc_from_postponed_job, NULL);
  }
}

static void after_gc_from_postponed_job(DDTRACE_UNUSED void *_unused) {
  VALUE instance = active_sampler_instance; // Read from global variable

  // This can potentially happen if the CpuAndWallTimeWorker was stopped while the postponed job was waiting to be executed; nothing to do
  if (instance == Qnil) return;

  // @ivoanjo: I'm not sure this can ever happen because `on_gc_event` only enqueues this callback if
  // it's running on the main Ractor, but just in case...
  if (!ddtrace_rb_ractor_main_p()) {
    return; // We're not on the main Ractor; we currently don't support profiling non-main Ractors
  }

  struct cpu_and_wall_time_worker_state *state;
  TypedData_Get_Struct(instance, struct cpu_and_wall_time_worker_state, &cpu_and_wall_time_worker_typed_data, state);

  // Trigger sampling using the Collectors::CpuAndWallTime; rescue against any exceptions that happen during sampling
  safely_call(cpu_and_wall_time_collector_sample_after_gc, state->cpu_and_wall_time_collector_instance, instance);
}

// Equivalent to Ruby begin/rescue call, where we call a C function and jump to the exception handler if an
// exception gets raised within
static void safely_call(VALUE (*function_to_call_safely)(VALUE), VALUE function_to_call_safely_arg, VALUE instance) {
  VALUE exception_handler_function_arg = instance;
  rb_rescue2(
    function_to_call_safely,
    function_to_call_safely_arg,
    handle_sampling_failure,
    exception_handler_function_arg,
    rb_eException, // rb_eException is the base class of all Ruby exceptions
    0 // Required by API to be the last argument
  );
}

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTimeWorker behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_simulate_handle_sampling_signal(DDTRACE_UNUSED VALUE self) {
  handle_sampling_signal(0, NULL, NULL);
  return Qtrue;
}

// This method exists only to enable testing Datadog::Profiling::Collectors::CpuAndWallTimeWorker behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_simulate_sample_from_postponed_job(DDTRACE_UNUSED VALUE self) {
  sample_from_postponed_job(NULL);
  return Qtrue;
}

// After the Ruby VM forks, this method gets called in the child process to clean up any leftover state from the parent.
//
// Assumption: This method gets called BEFORE restarting profiling. Note that profiling-related tracepoints may still
// be active, so we make sure to disable them before calling into anything else, so that there are no components
// attempting to trigger samples at the same time as the reset is done.
//
// In the future, if we add more other components with tracepoints, we will need to coordinate stopping all such
// tracepoints before doing the other cleaning steps.
static VALUE _native_reset_after_fork(DDTRACE_UNUSED VALUE self, VALUE instance) {
  struct cpu_and_wall_time_worker_state *state;
  TypedData_Get_Struct(instance, struct cpu_and_wall_time_worker_state, &cpu_and_wall_time_worker_typed_data, state);

  // Disable all tracepoints, so that there are no more attempts to mutate the profile
  rb_tracepoint_disable(state->gc_tracepoint);

  // Remove all state from the `Collectors::CpuAndWallTime` and connected downstream components
  rb_funcall(state->cpu_and_wall_time_collector_instance, rb_intern("reset_after_fork"), 0);

  return Qtrue;
}

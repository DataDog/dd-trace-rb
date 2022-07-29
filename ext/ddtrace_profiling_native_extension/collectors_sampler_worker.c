#include <ruby.h>
#include <ruby/thread.h>
#include <ruby/thread_native.h>
#include <ruby/debug.h>
#include <stdbool.h>
#include <signal.h>
#include "helpers.h"
#include "ruby_helpers.h"
#include "collectors_cpu_and_wall_time.h"

// Contains state for a single SamplerWorker instance
struct sampler_worker_collector_state {
  volatile bool should_run;

  VALUE cpu_and_wall_time_collector_instance;
};

static VALUE _native_new(VALUE klass);
static VALUE _native_initialize(DDTRACE_UNUSED VALUE _self, VALUE self_instance, VALUE cpu_and_wall_time_collector_instance);
static void sampler_worker_collector_typed_data_mark(void *state_ptr);
static VALUE _native_sampling_loop(VALUE self, VALUE instance);
static void install_sigprof_signal_handler(void);
static void remove_sigprof_signal_handler(void);
static void block_sigprof_signal_handler_from_running_in_current_thread(void);
static void handle_sampling_signal(DDTRACE_UNUSED int _signal, DDTRACE_UNUSED siginfo_t *_info, DDTRACE_UNUSED void *_ucontext);
static void *run_sampling_trigger_loop(void *state_ptr);
static void interrupt_sampling_trigger_loop(void *state_ptr);
static void called_from_postponed_job(void *data);

// Global state -- be very careful when accessing or modifying it

// This needs to be global because we access it from the signal handler. This MUST only be written from a thread holding
// the global VM lock (e.g. we piggy back on it to ensure correctness).
static VALUE active_sampler_instance = Qnil;

void collectors_sampler_worker_init(VALUE profiling_module) {
  VALUE collectors_module = rb_define_module_under(profiling_module, "Collectors");
  VALUE collectors_sampler_worker_class = rb_define_class_under(collectors_module, "SamplerWorker", rb_cObject);

  // Instances of the SamplerWorker class are "TypedData" objects.
  // "TypedData" objects are special objects in the Ruby VM that can wrap C structs.
  // In this case, it wraps the sampler_worker_collector_state.
  //
  // Because Ruby doesn't know how to initialize native-level structs, we MUST override the allocation function for objects
  // of this class so that we can manage this part. Not overriding or disabling the allocation function is a common
  // gotcha for "TypedData" objects that can very easily lead to VM crashes, see for instance
  // https://bugs.ruby-lang.org/issues/18007 for a discussion around this.
  rb_define_alloc_func(collectors_sampler_worker_class, _native_new);

  rb_define_singleton_method(collectors_sampler_worker_class, "_native_initialize", _native_initialize, 2);
  rb_define_singleton_method(collectors_sampler_worker_class, "_native_sampling_loop", _native_sampling_loop, 1);
}

// This structure is used to define a Ruby object that stores a pointer to a struct sampler_worker_collector_state
// See also https://github.com/ruby/ruby/blob/master/doc/extension.rdoc for how this works
static const rb_data_type_t sampler_worker_collector_typed_data = {
  .wrap_struct_name = "Datadog::Profiling::Collectors::SamplerWorker",
  .function = {
    .dmark = sampler_worker_collector_typed_data_mark,
    .dfree = RUBY_DEFAULT_FREE,
    .dsize = NULL, // We don't track profile memory usage (although it'd be cool if we did!)
    //.dcompact = NULL, // FIXME: Add support for compaction
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE _native_new(VALUE klass) {
  struct sampler_worker_collector_state *state = ruby_xcalloc(1, sizeof(struct sampler_worker_collector_state));

  state->should_run = false;
  state->cpu_and_wall_time_collector_instance = Qnil;

  return TypedData_Wrap_Struct(klass, &sampler_worker_collector_typed_data, state);
}

static VALUE _native_initialize(DDTRACE_UNUSED VALUE _self, VALUE self_instance, VALUE cpu_and_wall_time_collector_instance) {
  enforce_cpu_and_wall_time_collector_instance(cpu_and_wall_time_collector_instance);

  struct sampler_worker_collector_state *state;
  TypedData_Get_Struct(self_instance, struct sampler_worker_collector_state, &sampler_worker_collector_typed_data, state);

  state->cpu_and_wall_time_collector_instance = cpu_and_wall_time_collector_instance;

  return Qtrue;
}

static void sampler_worker_collector_typed_data_mark(void *state_ptr) {
  struct sampler_worker_collector_state *state = (struct sampler_worker_collector_state *) state_ptr;

  rb_gc_mark(state->cpu_and_wall_time_collector_instance);
}

static VALUE _native_sampling_loop(DDTRACE_UNUSED VALUE _self, VALUE instance) {
  if (active_sampler_instance != Qnil) {
    rb_raise(rb_eRuntimeError, "Cannot start SamplerWorker: There's already another instance of SamplerWorker active");
  }

  struct sampler_worker_collector_state *state;
  TypedData_Get_Struct(instance, struct sampler_worker_collector_state, &sampler_worker_collector_typed_data, state);

  // This write to a global is thread-safe BECAUSE we're still holding on to the global VM lock at this point
  active_sampler_instance = instance;

  fprintf(stderr, "Started native sampling loop\n");

  state->should_run = true;

  install_sigprof_signal_handler();
  block_sigprof_signal_handler_from_running_in_current_thread(); // We want to interrupt the thread with the global VM lock, never this one

  // Release the global VM lock, and start the sampling loop
  rb_thread_call_without_gvl(run_sampling_trigger_loop, state, interrupt_sampling_trigger_loop, state);

  // Once run_sampling_trigger_loop returns, sampling has either failed in some issue or was asked to stop, let's clean up
  remove_sigprof_signal_handler();

  active_sampler_instance = Qnil;

  // Ensure that instance is not garbage collected while the native sampling loop is running; this is probably not needed, but just in case
  RB_GC_GUARD(instance);

  return Qnil;
}

static void install_sigprof_signal_handler(void) {
  struct sigaction signal_handler_config;
  struct sigaction existing_signal_handler_config; // TODO: Do something with this

  sigemptyset(&signal_handler_config.sa_mask);
  signal_handler_config.sa_handler = NULL;
  signal_handler_config.sa_flags = SA_RESTART | SA_SIGINFO;
  signal_handler_config.sa_sigaction = handle_sampling_signal;

  if (sigaction(SIGPROF, &signal_handler_config, &existing_signal_handler_config) != 0) {
    rb_sys_fail("Could not install signal handler");
  }
}

static void remove_sigprof_signal_handler(void) {
  // TODO
}

static void block_sigprof_signal_handler_from_running_in_current_thread(void) {
  sigset_t signals_to_block;
  sigemptyset(&signals_to_block);

  sigaddset(&signals_to_block, SIGPROF);

  pthread_sigmask(SIG_BLOCK, &signals_to_block, NULL);
}

static void handle_sampling_signal(DDTRACE_UNUSED int _signal, DDTRACE_UNUSED siginfo_t *_info, DDTRACE_UNUSED void *_ucontext) {
  fprintf(stderr, "Got sampling signal in %p in a ruby_thread=%d!\n", rb_thread_current(), ruby_native_thread_p());

  if (!ruby_native_thread_p() && !ruby_thread_has_gvl_p()) {
    return; // Not safe to enqueue a sample from this thread
  }

  rb_postponed_job_register_one(0, called_from_postponed_job, NULL);
}

// The actual sampling trigger loop always runs **without** the global vm lock.
static void *run_sampling_trigger_loop(void *state_ptr) {
  struct sampler_worker_collector_state *state = (struct sampler_worker_collector_state *) state_ptr;

  while (state->should_run) {
    fprintf(stderr, "Hello from the sampling trigger loop in %p\n", rb_thread_current());
    kill(getpid(), SIGPROF); // TODO Improve this
    sleep(1);
  }

  fprintf(stderr, "should_run was false, stopping\n");

  return NULL; // Unused
}

static void interrupt_sampling_trigger_loop(void *state_ptr) {
  struct sampler_worker_collector_state *state = (struct sampler_worker_collector_state *) state_ptr;

  state->should_run = false;
}

static void called_from_postponed_job(void *data) {
  fprintf(stderr, "Called from postponed job in %p and have_gvl=%d!\n", rb_thread_current(), ruby_thread_has_gvl_p());

  VALUE instance = active_sampler_instance;

  // This can potentially happen when the SamplerWorker was stopped while the postponed job was waiting to be executed; nothing to do
  if (instance == Qnil) return;

  struct sampler_worker_collector_state *state;
  TypedData_Get_Struct(instance, struct sampler_worker_collector_state, &sampler_worker_collector_typed_data, state);

  cpu_and_wall_time_collector_sample(state->cpu_and_wall_time_collector_instance);
  fprintf(stderr, "Sampling finished\n");
}


// TODO: COUNTERS

// signal handler
  // ensure GVL
  // enqueue sample for later

// sampler for later handler
  // ensure GVL (?)
  // handle exceptions
  // trigger cpu_and_wall_time collector

#include <ruby.h>
#include <ruby/thread.h>
#include <pthread.h>
#include <errno.h>
#include "helpers.h"
#include "stack_recorder.h"
#include "libdatadog_helpers.h"
#include "ruby_helpers.h"

// Used to wrap a ddog_prof_Profile in a Ruby object and expose Ruby-level serialization APIs
// This file implements the native bits of the Datadog::Profiling::StackRecorder class

// ---
// ## Synchronization mechanism for safe parallel access design notes
//
// The state of the StackRecorder is managed using a set of locks to avoid concurrency issues.
//
// This is needed because the state is expected to be accessed, in parallel, by two different threads.
//
// 1. The thread that is taking a stack sample and that called `record_sample`, let's call it the **sampler thread**.
// In the current implementation of the profiler, there can only exist one **sampler thread** at a time; if this
// constraint changes, we should revise the design of the StackRecorder.
//
// 2. The thread that serializes and reports profiles, let's call it the **serializer thread**. We enforce that there
// cannot be more than one thread attempting to serialize profiles at a time.
//
// If both the sampler and serializer threads are trying to access the same `ddog_prof_Profile` in parallel, we will
// have a concurrency issue. Thus, the StackRecorder has an added mechanism to avoid this.
//
// As an additional constraint, the **sampler thread** has absolute priority and must never block while
// recording a sample.
//
// ### The solution: Keep two profiles at the same time
//
// To solve for the constraints above, the StackRecorder keeps two `ddog_prof_Profile` profile instances inside itself.
// They are called the `slot_one_profile` and `slot_two_profile`.
//
// Each profile is paired with its own mutex. `slot_one_profile` is protected by `slot_one_mutex` and `slot_two_profile`
// is protected by `slot_two_mutex`.
//
// We additionally introduce the concept of **active** and **inactive** profile slots. At any point, the sampler thread
// can probe the mutexes to discover which of the profiles corresponds to the active slot, and then records samples in it.
// When the serializer thread is ready to serialize data, it flips the active and inactive slots; it reports the data
// on the previously-active profile slot, and the sampler thread can continue to record in the previously-inactive
// profile slot.
//
// Thus, the sampler and serializer threads never cross paths, avoiding concurrency issues. The sampler thread writes to
// the active profile slot, and the serializer thread reads from the inactive profile slot.
//
// ### Locking protocol, high-level
//
// The active profile slot is the slot for which its corresponding mutex **is unlocked**. That is, if the sampler
// thread can grab a lock for a profile slot, then that slot is the active one. (Here you see where the constraint
// stated above that only one sampler thread can exist kicks in -- this part would need to be more complex if multiple
// sampler threads were in play.)
//
// As a counterpart, the inactive profile slot mutex is **kept locked** until such time the serializer
// thread is ready to work and decides to flip the slots.
//
// When a new StackRecorder is initialized, the `slot_one_mutex` is unlocked, and the `slot_two_mutex` is kept locked,
// that is, a new instance always starts with slot one active.
//
// Additionally, an `active_slot` field is kept, containing a `1` or `2`; this is only kept for the serializer thread
// to use as a simplification, as well as for testing and debugging; the **sampler thread must never use the `active_slot`
// field**.
//
// ### Locking protocol, from the sampler thread side
//
// When the sampler thread wants to record a sample, it goes through the following steps to discover which is the
// active profile slot:
//
// 1. `pthread_mutex_trylock(slot_one_mutex)`. If it succeeds to grab the lock, this means the active profile slot is
// slot one. If it fails, we move to the next step.
//
// 2. `pthread_mutex_trylock(slot_two_mutex)`. If it succeeds to grab the lock, this means the active profile slot is
// slot two. If it fails, we move to the next step.
//
// 3. What does it mean for the sampler thread to have observed both `slot_one_mutex` as well as `slot_two_mutex` as
// being locked? There are two options:
//   a. The sampler thread got really unlucky. When it tried to grab the `slot_one_mutex`, the active profile slot was
//     the second one BUT then the serializer thread flipped the slots, and by the time the sampler thread probed the
//     `slot_two_mutex`, that one was taken. Since the serializer thread is expected only to work once a minute,
//     we retry steps 1. and 2. and should be able to find an active slot.
//   b. Something is incorrect in the StackRecorder state. In this situation, the sampler thread should give up on
//     sampling and enter an error state.
//
// Note that in the steps above, and because the sampler thread uses `trylock` to probe the mutexes, that the
// sampler thread never blocks. It either is able to find an active profile slot in a bounded amount of steps or it
// enters an error state.
//
// This guarantees that sampler performance is never constrained by serializer performance.
//
// ### Locking protocol, from the serializer thread side
//
// When the serializer thread wants to serialize a profile, it first flips the active and inactive profile slots.
//
// The flipping action is described below. Consider previously-inactive and previously-active as the state of the slots
// before the flipping happens.
//
// The flipping steps are the following:
//
// 1. Release the mutex for the previously-inactive profile slot. That slot, as seen by the sampler thread, is now
// active.
//
// 2. Grab the mutex for the previously-active profile slot. Note that this can lead to the serializer thread blocking,
// if the sampler thread is holding this mutex. After the mutex is grabbed, the previously-active slot becomes inactive,
// as seen by the sampler thread.
//
// 3. Update `active_slot`.
//
// After flipping the profile slots, the serializer thread is now free to serialize the inactive profile slot. The slot
// is kept inactive until the next time the serializer thread wants to serialize data.
//
// Note there can be a brief period between steps 1 and 2 where the serializer thread holds no lock, which means that
// the sampler thread can pick either slot. This is OK: if the sampler thread picks the previously-inactive slot, the
// samples will be reported on the next serialization; if the sampler thread picks the previously-active slot, the
// samples are still included in the current serialization. Either option is correct.
//
// ### Additional notes
//
// Q: Can the sampler thread and the serializer thread ever be the same thread? (E.g. sampling in interrupt handler)
// A: No; the current profiler design requires that sampling happens only on the thread that is holding the Global VM
// Lock (GVL). The serializer thread flipping occurs after the serializer thread releases the GVL, and thus the
// serializer thread will not be able to host the sampling process.
//
// ---

static VALUE ok_symbol = Qnil; // :ok in Ruby
static VALUE error_symbol = Qnil; // :error in Ruby

static VALUE stack_recorder_class = Qnil;

// Contains native state for each instance
struct stack_recorder_state {
  pthread_mutex_t slot_one_mutex;
  ddog_prof_Profile *slot_one_profile;

  pthread_mutex_t slot_two_mutex;
  ddog_prof_Profile *slot_two_profile;

  short active_slot; // MUST NEVER BE ACCESSED FROM record_sample; this is NOT for the sampler thread to use.
};

// Used to return a pair of values from sampler_lock_active_profile()
struct active_slot_pair {
  pthread_mutex_t *mutex;
  ddog_prof_Profile *profile;
};

struct call_serialize_without_gvl_arguments {
  // Set by caller
  struct stack_recorder_state *state;
  ddog_Timespec finish_timestamp;

  // Set by callee
  ddog_prof_Profile *profile;
  ddog_prof_Profile_SerializeResult result;

  // Set by both
  bool serialize_ran;
};

static VALUE _native_new(VALUE klass);
static void initialize_slot_concurrency_control(struct stack_recorder_state *state);
static void stack_recorder_typed_data_free(void *data);
static VALUE _native_serialize(VALUE self, VALUE recorder_instance);
static VALUE ruby_time_from(ddog_Timespec ddprof_time);
static void *call_serialize_without_gvl(void *call_args);
static struct active_slot_pair sampler_lock_active_profile();
static void sampler_unlock_active_profile(struct active_slot_pair active_slot);
static ddog_prof_Profile *serializer_flip_active_and_inactive_slots(struct stack_recorder_state *state);
static VALUE _native_active_slot(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);
static VALUE _native_is_slot_one_mutex_locked(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);
static VALUE _native_is_slot_two_mutex_locked(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);
static VALUE test_slot_mutex_state(VALUE recorder_instance, int slot);
static ddog_Timespec time_now(void);
static VALUE _native_reset_after_fork(DDTRACE_UNUSED VALUE self, VALUE recorder_instance);
static void serializer_set_start_timestamp_for_next_profile(struct stack_recorder_state *state, ddog_Timespec timestamp);
static VALUE _native_record_endpoint(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance, VALUE local_root_span_id, VALUE endpoint);

void stack_recorder_init(VALUE profiling_module) {
  stack_recorder_class = rb_define_class_under(profiling_module, "StackRecorder", rb_cObject);
  // Hosts methods used for testing the native code using RSpec
  VALUE testing_module = rb_define_module_under(stack_recorder_class, "Testing");

  // Instances of the StackRecorder class are "TypedData" objects.
  // "TypedData" objects are special objects in the Ruby VM that can wrap C structs.
  // In this case, it wraps the stack_recorder_state.
  //
  // Because Ruby doesn't know how to initialize native-level structs, we MUST override the allocation function for objects
  // of this class so that we can manage this part. Not overriding or disabling the allocation function is a common
  // gotcha for "TypedData" objects that can very easily lead to VM crashes, see for instance
  // https://bugs.ruby-lang.org/issues/18007 for a discussion around this.
  rb_define_alloc_func(stack_recorder_class, _native_new);

  rb_define_singleton_method(stack_recorder_class, "_native_serialize",  _native_serialize, 1);
  rb_define_singleton_method(stack_recorder_class, "_native_reset_after_fork", _native_reset_after_fork, 1);
  rb_define_singleton_method(testing_module, "_native_active_slot", _native_active_slot, 1);
  rb_define_singleton_method(testing_module, "_native_slot_one_mutex_locked?", _native_is_slot_one_mutex_locked, 1);
  rb_define_singleton_method(testing_module, "_native_slot_two_mutex_locked?", _native_is_slot_two_mutex_locked, 1);
  rb_define_singleton_method(testing_module, "_native_record_endpoint", _native_record_endpoint, 3);

  ok_symbol = ID2SYM(rb_intern_const("ok"));
  error_symbol = ID2SYM(rb_intern_const("error"));
}

// This structure is used to define a Ruby object that stores a pointer to a ddog_prof_Profile instance
// See also https://github.com/ruby/ruby/blob/master/doc/extension.rdoc for how this works
static const rb_data_type_t stack_recorder_typed_data = {
  .wrap_struct_name = "Datadog::Profiling::StackRecorder",
  .function = {
    .dfree = stack_recorder_typed_data_free,
    .dsize = NULL, // We don't track profile memory usage (although it'd be cool if we did!)
    // No need to provide dmark nor dcompact because we don't directly reference Ruby VALUEs from inside this object
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE _native_new(VALUE klass) {
  struct stack_recorder_state *state = ruby_xcalloc(1, sizeof(struct stack_recorder_state));

  ddog_prof_Slice_ValueType sample_types = {.ptr = enabled_value_types, .len = ENABLED_VALUE_TYPES_COUNT};

  initialize_slot_concurrency_control(state);

  // Note: Don't raise exceptions after this point, since it'll lead to libdatadog memory leaking!

  state->slot_one_profile = ddog_prof_Profile_new(sample_types, NULL /* period is optional */, NULL /* start_time is optional */);
  state->slot_two_profile = ddog_prof_Profile_new(sample_types, NULL /* period is optional */, NULL /* start_time is optional */);

  return TypedData_Wrap_Struct(klass, &stack_recorder_typed_data, state);
}

static void initialize_slot_concurrency_control(struct stack_recorder_state *state) {
  state->slot_one_mutex = (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;
  state->slot_two_mutex = (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;

  // A newly-created StackRecorder starts with slot one being active for samples, so let's lock slot two
  ENFORCE_SUCCESS_GVL(pthread_mutex_lock(&state->slot_two_mutex));

  state->active_slot = 1;
}

static void stack_recorder_typed_data_free(void *state_ptr) {
  struct stack_recorder_state *state = (struct stack_recorder_state *) state_ptr;

  pthread_mutex_destroy(&state->slot_one_mutex);
  ddog_prof_Profile_drop(state->slot_one_profile);

  pthread_mutex_destroy(&state->slot_two_mutex);
  ddog_prof_Profile_drop(state->slot_two_profile);

  ruby_xfree(state);
}

static VALUE _native_serialize(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) {
  struct stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, struct stack_recorder_state, &stack_recorder_typed_data, state);

  ddog_Timespec finish_timestamp = time_now();
  // Need to do this while still holding on to the Global VM Lock; see comments on method for why
  serializer_set_start_timestamp_for_next_profile(state, finish_timestamp);

  // We'll release the Global VM Lock while we're calling serialize, so that the Ruby VM can continue to work while this
  // is pending
  struct call_serialize_without_gvl_arguments args = {.state = state, .finish_timestamp = finish_timestamp, .serialize_ran = false};

  while (!args.serialize_ran) {
    // Give the Ruby VM an opportunity to process any pending interruptions (including raising exceptions).
    // Note that it's OK to do this BEFORE call_serialize_without_gvl runs BUT NOT AFTER because afterwards
    // there's heap-allocated memory that MUST be cleaned before raising any exception.
    //
    // Note that we run this in a loop because `rb_thread_call_without_gvl2` may return multiple times due to
    // pending interrupts until it actually runs our code.
    process_pending_interruptions(Qnil);

    // We use rb_thread_call_without_gvl2 here because unlike the regular _gvl variant, gvl2 does not process
    // interruptions and thus does not raise exceptions after running our code.
    rb_thread_call_without_gvl2(call_serialize_without_gvl, &args, NULL /* No interruption function needed in this case */, NULL /* Not needed */);
  }

  ddog_prof_Profile_SerializeResult serialized_profile = args.result;

  if (serialized_profile.tag == DDOG_PROF_PROFILE_SERIALIZE_RESULT_ERR) {
    VALUE err_details = ruby_string_from_prof_vec_u8(serialized_profile.err);
    ddog_prof_Profile_SerializeResult_drop(serialized_profile);
    return rb_ary_new_from_args(2, error_symbol, err_details);
  }

  VALUE encoded_pprof = ruby_string_from_prof_vec_u8(serialized_profile.ok.buffer);

  ddog_Timespec ddprof_start = serialized_profile.ok.start;
  ddog_Timespec ddprof_finish = serialized_profile.ok.end;

  // Clean up libdatadog object to avoid leaking in case ruby_time_from raises an exception
  ddog_prof_Profile_SerializeResult_drop(serialized_profile);

  VALUE start = ruby_time_from(ddprof_start);
  VALUE finish = ruby_time_from(ddprof_finish);

  if (!ddog_prof_Profile_reset(args.profile, NULL /* start_time is optional */ )) {
    return rb_ary_new_from_args(2, error_symbol, rb_str_new_cstr("Failed to reset profile"));
  }

  return rb_ary_new_from_args(2, ok_symbol, rb_ary_new_from_args(3, start, finish, encoded_pprof));
}

static VALUE ruby_time_from(ddog_Timespec ddprof_time) {
  const int utc = INT_MAX - 1; // From Ruby sources
  struct timespec time = {.tv_sec = ddprof_time.seconds, .tv_nsec = ddprof_time.nanoseconds};
  return rb_time_timespec_new(&time, utc);
}

void record_sample(VALUE recorder_instance, ddog_prof_Sample sample) {
  struct stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, struct stack_recorder_state, &stack_recorder_typed_data, state);

  struct active_slot_pair active_slot = sampler_lock_active_profile(state);

  uint64_t success = ddog_prof_Profile_add(active_slot.profile, sample);

  sampler_unlock_active_profile(active_slot);

  if (!success) rb_raise(rb_eArgError, "Failed to record sample: ddog_prof_Profile_add returned failure status code");
}

void record_endpoint(VALUE recorder_instance, uint64_t local_root_span_id, ddog_CharSlice endpoint) {
  struct stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, struct stack_recorder_state, &stack_recorder_typed_data, state);

  struct active_slot_pair active_slot = sampler_lock_active_profile(state);

  ddog_prof_Profile_set_endpoint(active_slot.profile, local_root_span_id, endpoint);

  sampler_unlock_active_profile(active_slot);
}

static void *call_serialize_without_gvl(void *call_args) {
  struct call_serialize_without_gvl_arguments *args = (struct call_serialize_without_gvl_arguments *) call_args;

  args->profile = serializer_flip_active_and_inactive_slots(args->state);
  args->result = ddog_prof_Profile_serialize(args->profile, &args->finish_timestamp, NULL /* duration_nanos is optional */);
  args->serialize_ran = true;

  return NULL; // Unused
}

VALUE enforce_recorder_instance(VALUE object) {
  Check_TypedStruct(object, &stack_recorder_typed_data);
  return object;
}

static struct active_slot_pair sampler_lock_active_profile(struct stack_recorder_state *state) {
  int error;

  for (int attempts = 0; attempts < 2; attempts++) {
    error = pthread_mutex_trylock(&state->slot_one_mutex);
    if (error && error != EBUSY) ENFORCE_SUCCESS_GVL(error);

    // Slot one is active
    if (!error) return (struct active_slot_pair) {.mutex = &state->slot_one_mutex, .profile = state->slot_one_profile};

    // If we got here, slot one was not active, let's try slot two

    error = pthread_mutex_trylock(&state->slot_two_mutex);
    if (error && error != EBUSY) ENFORCE_SUCCESS_GVL(error);

    // Slot two is active
    if (!error) return (struct active_slot_pair) {.mutex = &state->slot_two_mutex, .profile = state->slot_two_profile};
  }

  // We already tried both multiple times, and we did not succeed. This is not expected to happen. Let's stop sampling.
  rb_raise(rb_eRuntimeError, "Failed to grab either mutex in sampler_lock_active_profile");
}

static void sampler_unlock_active_profile(struct active_slot_pair active_slot) {
  ENFORCE_SUCCESS_GVL(pthread_mutex_unlock(active_slot.mutex));
}

static ddog_prof_Profile *serializer_flip_active_and_inactive_slots(struct stack_recorder_state *state) {
  int previously_active_slot = state->active_slot;

  if (previously_active_slot != 1 && previously_active_slot != 2) {
    grab_gvl_and_raise(rb_eRuntimeError, "Unexpected active_slot state %d in serializer_flip_active_and_inactive_slots", previously_active_slot);
  }

  pthread_mutex_t *previously_active = (previously_active_slot == 1) ? &state->slot_one_mutex : &state->slot_two_mutex;
  pthread_mutex_t *previously_inactive = (previously_active_slot == 1) ? &state->slot_two_mutex : &state->slot_one_mutex;

  // Release the lock, thus making this slot active
  ENFORCE_SUCCESS_NO_GVL(pthread_mutex_unlock(previously_inactive));

  // Grab the lock, thus making this slot inactive
  ENFORCE_SUCCESS_NO_GVL(pthread_mutex_lock(previously_active));

  // Update active_slot
  state->active_slot = (previously_active_slot == 1) ? 2 : 1;

  // Return profile for previously active slot (now inactive)
  return (previously_active_slot == 1) ? state->slot_one_profile : state->slot_two_profile;
}

// This method exists only to enable testing Datadog::Profiling::StackRecorder behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_active_slot(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) {
  struct stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, struct stack_recorder_state, &stack_recorder_typed_data, state);

  return INT2NUM(state->active_slot);
}

// This method exists only to enable testing Datadog::Profiling::StackRecorder behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_is_slot_one_mutex_locked(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) { return test_slot_mutex_state(recorder_instance, 1); }

// This method exists only to enable testing Datadog::Profiling::StackRecorder behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_is_slot_two_mutex_locked(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) { return test_slot_mutex_state(recorder_instance, 2); }

static VALUE test_slot_mutex_state(VALUE recorder_instance, int slot) {
  struct stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, struct stack_recorder_state, &stack_recorder_typed_data, state);

  pthread_mutex_t *slot_mutex = (slot == 1) ? &state->slot_one_mutex : &state->slot_two_mutex;

  // Like Heisenberg's uncertainty principle, we can't observe without affecting...
  int error = pthread_mutex_trylock(slot_mutex);

  if (error == 0) {
    // Mutex was unlocked
    ENFORCE_SUCCESS_GVL(pthread_mutex_unlock(slot_mutex));
    return Qfalse;
  } else if (error == EBUSY) {
    // Mutex was locked
    return Qtrue;
  } else {
    ENFORCE_SUCCESS_GVL(error);
    rb_raise(rb_eRuntimeError, "Failed to raise exception in test_slot_mutex_state; this should never happen");
  }
}

// Note that this is using CLOCK_REALTIME (e.g. actual time since unix epoch) and not the CLOCK_MONOTONIC as we use in
// monotonic_wall_time_now_ns (used in other parts of the codebase)
static ddog_Timespec time_now(void) {
  struct timespec current_time;

  if (clock_gettime(CLOCK_REALTIME, &current_time) != 0) ENFORCE_SUCCESS_GVL(errno);

  return (ddog_Timespec) {.seconds = current_time.tv_sec, .nanoseconds = (uint32_t) current_time.tv_nsec};
}

// After the Ruby VM forks, this method gets called in the child process to clean up any leftover state from the parent.
//
// Assumption: This method gets called BEFORE restarting profiling -- e.g. there are no components attempting to
// trigger samples at the same time.
static VALUE _native_reset_after_fork(DDTRACE_UNUSED VALUE self, VALUE recorder_instance) {
  struct stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, struct stack_recorder_state, &stack_recorder_typed_data, state);

  // In case the fork happened halfway through `serializer_flip_active_and_inactive_slots` execution and the
  // resulting state is inconsistent, we make sure to reset it back to the initial state.
  initialize_slot_concurrency_control(state);

  ddog_prof_Profile_reset(state->slot_one_profile, /* start_time: */ NULL);
  ddog_prof_Profile_reset(state->slot_two_profile, /* start_time: */ NULL);

  return Qtrue;
}

// Assumption 1: This method is called with the GVL being held, because `ddog_prof_Profile_reset` mutates the profile and should
// not be interrupted part-way through by a VM fork.
static void serializer_set_start_timestamp_for_next_profile(struct stack_recorder_state *state, ddog_Timespec timestamp) {
  // Before making this profile active, we reset it so that it uses the correct timestamp for its start
  ddog_prof_Profile *next_profile = (state->active_slot == 1) ? state->slot_two_profile : state->slot_one_profile;

  if (!ddog_prof_Profile_reset(next_profile, &timestamp)) rb_raise(rb_eRuntimeError, "Failed to reset profile");
}

static VALUE _native_record_endpoint(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance, VALUE local_root_span_id, VALUE endpoint) {
  ENFORCE_TYPE(local_root_span_id, T_FIXNUM);
  record_endpoint(recorder_instance, NUM2ULL(local_root_span_id), char_slice_from_ruby_string(endpoint));
  return Qtrue;
}

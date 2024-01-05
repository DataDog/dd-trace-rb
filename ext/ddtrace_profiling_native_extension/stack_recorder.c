#include <ruby.h>
#include <ruby/thread.h>
#include <pthread.h>
#include <errno.h>
#include "helpers.h"
#include "stack_recorder.h"
#include "libdatadog_helpers.h"
#include "ruby_helpers.h"
#include "time_helpers.h"
#include "heap_recorder.h"

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

// Note: Please DO NOT use `VALUE_STRING` anywhere else, instead use `DDOG_CHARSLICE_C`.
// `VALUE_STRING` is only needed because older versions of gcc (4.9.2, used in our Ruby 2.2 CI test images)
// tripped when compiling `enabled_value_types` using `-std=gnu99` due to the extra cast that is included in
// `DDOG_CHARSLICE_C` with the following error:
//
// ```
// compiling ../../../../ext/ddtrace_profiling_native_extension/stack_recorder.c
// ../../../../ext/ddtrace_profiling_native_extension/stack_recorder.c:23:1: error: initializer element is not constant
// static const ddog_prof_ValueType enabled_value_types[] = {CPU_TIME_VALUE, CPU_SAMPLES_VALUE, WALL_TIME_VALUE};
// ^
// ```
#define VALUE_STRING(string) {.ptr = "" string, .len = sizeof(string) - 1}

#define CPU_TIME_VALUE          {.type_ = VALUE_STRING("cpu-time"),          .unit = VALUE_STRING("nanoseconds")}
#define CPU_TIME_VALUE_ID 0
#define CPU_SAMPLES_VALUE       {.type_ = VALUE_STRING("cpu-samples"),       .unit = VALUE_STRING("count")}
#define CPU_SAMPLES_VALUE_ID 1
#define WALL_TIME_VALUE         {.type_ = VALUE_STRING("wall-time"),         .unit = VALUE_STRING("nanoseconds")}
#define WALL_TIME_VALUE_ID 2
#define ALLOC_SAMPLES_VALUE     {.type_ = VALUE_STRING("alloc-samples"),     .unit = VALUE_STRING("count")}
#define ALLOC_SAMPLES_VALUE_ID 3
#define HEAP_SAMPLES_VALUE      {.type_ = VALUE_STRING("heap-live-samples"), .unit = VALUE_STRING("count")}
#define HEAP_SAMPLES_VALUE_ID 4
#define HEAP_SIZE_VALUE         {.type_ = VALUE_STRING("heap-live-size"),    .unit = VALUE_STRING("bytes")}
#define HEAP_SIZE_VALUE_ID 5
#define TIMELINE_VALUE          {.type_ = VALUE_STRING("timeline"),          .unit = VALUE_STRING("nanoseconds")}
#define TIMELINE_VALUE_ID 6

static const ddog_prof_ValueType all_value_types[] =
  {CPU_TIME_VALUE, CPU_SAMPLES_VALUE, WALL_TIME_VALUE, ALLOC_SAMPLES_VALUE, HEAP_SAMPLES_VALUE, HEAP_SIZE_VALUE, TIMELINE_VALUE};

// This array MUST be kept in sync with all_value_types above and is intended to act as a "hashmap" between VALUE_ID and the position it
// occupies on the all_value_types array.
// E.g. all_value_types_positions[CPU_TIME_VALUE_ID] => 0, means that CPU_TIME_VALUE was declared at position 0 of all_value_types.
static const uint8_t all_value_types_positions[] =
  {CPU_TIME_VALUE_ID, CPU_SAMPLES_VALUE_ID, WALL_TIME_VALUE_ID, ALLOC_SAMPLES_VALUE_ID, HEAP_SAMPLES_VALUE_ID, HEAP_SIZE_VALUE_ID, TIMELINE_VALUE_ID};

#define ALL_VALUE_TYPES_COUNT (sizeof(all_value_types) / sizeof(ddog_prof_ValueType))

// Contains native state for each instance
struct stack_recorder_state {
  // Heap recorder instance
  heap_recorder *heap_recorder;

  pthread_mutex_t slot_one_mutex;
  ddog_prof_Profile slot_one_profile;

  pthread_mutex_t slot_two_mutex;
  ddog_prof_Profile slot_two_profile;

  short active_slot; // MUST NEVER BE ACCESSED FROM record_sample; this is NOT for the sampler thread to use.

  uint8_t position_for[ALL_VALUE_TYPES_COUNT];
  uint8_t enabled_values_count;
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
  size_t gc_count_before_serialize;

  // Set by callee
  ddog_prof_Profile *profile;
  ddog_prof_Profile_SerializeResult result;

  // Set by both
  bool serialize_ran;
};

static VALUE _native_new(VALUE klass);
static void initialize_slot_concurrency_control(struct stack_recorder_state *state);
static void initialize_profiles(struct stack_recorder_state *state, ddog_prof_Slice_ValueType sample_types);
static void stack_recorder_typed_data_free(void *data);
static VALUE _native_initialize(
  DDTRACE_UNUSED VALUE _self,
  VALUE recorder_instance,
  VALUE cpu_time_enabled,
  VALUE alloc_samples_enabled,
  VALUE heap_samples_enabled,
  VALUE heap_size_enabled,
  VALUE heap_sample_every,
  VALUE timeline_enabled
);
static VALUE _native_serialize(VALUE self, VALUE recorder_instance);
static VALUE ruby_time_from(ddog_Timespec ddprof_time);
static void *call_serialize_without_gvl(void *call_args);
static struct active_slot_pair sampler_lock_active_profile(struct stack_recorder_state *state);
static void sampler_unlock_active_profile(struct active_slot_pair active_slot);
static ddog_prof_Profile *serializer_flip_active_and_inactive_slots(struct stack_recorder_state *state);
static VALUE _native_active_slot(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);
static VALUE _native_is_slot_one_mutex_locked(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);
static VALUE _native_is_slot_two_mutex_locked(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);
static VALUE test_slot_mutex_state(VALUE recorder_instance, int slot);
static ddog_Timespec system_epoch_now_timespec(void);
static VALUE _native_reset_after_fork(DDTRACE_UNUSED VALUE self, VALUE recorder_instance);
static void serializer_set_start_timestamp_for_next_profile(struct stack_recorder_state *state, ddog_Timespec start_time);
static VALUE _native_record_endpoint(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance, VALUE local_root_span_id, VALUE endpoint);
static void reset_profile(ddog_prof_Profile *profile, ddog_Timespec *start_time /* Can be null */);
static VALUE _native_track_object(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance, VALUE new_obj, VALUE weight, VALUE alloc_class);
static VALUE _native_check_heap_hashes(DDTRACE_UNUSED VALUE _self, VALUE locations);
static VALUE _native_start_fake_slow_heap_serialization(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);
static VALUE _native_end_fake_slow_heap_serialization(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);
static VALUE _native_debug_heap_recorder(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);


void stack_recorder_init(VALUE profiling_module) {
  VALUE stack_recorder_class = rb_define_class_under(profiling_module, "StackRecorder", rb_cObject);
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

  rb_define_singleton_method(stack_recorder_class, "_native_initialize", _native_initialize, 7);
  rb_define_singleton_method(stack_recorder_class, "_native_serialize",  _native_serialize, 1);
  rb_define_singleton_method(stack_recorder_class, "_native_reset_after_fork", _native_reset_after_fork, 1);
  rb_define_singleton_method(testing_module, "_native_active_slot", _native_active_slot, 1);
  rb_define_singleton_method(testing_module, "_native_slot_one_mutex_locked?", _native_is_slot_one_mutex_locked, 1);
  rb_define_singleton_method(testing_module, "_native_slot_two_mutex_locked?", _native_is_slot_two_mutex_locked, 1);
  rb_define_singleton_method(testing_module, "_native_record_endpoint", _native_record_endpoint, 3);
  rb_define_singleton_method(testing_module, "_native_track_object", _native_track_object, 4);
  rb_define_singleton_method(testing_module, "_native_check_heap_hashes", _native_check_heap_hashes, 1);
  rb_define_singleton_method(testing_module, "_native_start_fake_slow_heap_serialization",
      _native_start_fake_slow_heap_serialization, 1);
  rb_define_singleton_method(testing_module, "_native_end_fake_slow_heap_serialization",
      _native_end_fake_slow_heap_serialization, 1);
  rb_define_singleton_method(testing_module, "_native_debug_heap_recorder",
      _native_debug_heap_recorder, 1);

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

  // Note: Any exceptions raised from this note until the TypedData_Wrap_Struct call will lead to the state memory
  // being leaked.

  ddog_prof_Slice_ValueType sample_types = {.ptr = all_value_types, .len = ALL_VALUE_TYPES_COUNT};

  initialize_slot_concurrency_control(state);
  for (uint8_t i = 0; i < ALL_VALUE_TYPES_COUNT; i++) { state->position_for[i] = all_value_types_positions[i]; }
  state->enabled_values_count = ALL_VALUE_TYPES_COUNT;

  // Note: At this point, slot_one_profile and slot_two_profile contain null pointers. Libdatadog validates pointers
  // before using them so it's ok for us to go ahead and create the StackRecorder object.

  VALUE stack_recorder = TypedData_Wrap_Struct(klass, &stack_recorder_typed_data, state);

  // NOTE: We initialize this because we want a new recorder to be operational even without initialization and our
  //       default is everything enabled. However, if during recording initialization it turns out we don't want
  //       heap samples, we will free and reset heap_recorder to NULL, effectively disabling all behaviour specific
  //       to heap profiling (all calls to heap_recorder_* with a NULL heap recorder are noops).
  state->heap_recorder = heap_recorder_new();

  // Note: Don't raise exceptions after this point, since it'll lead to libdatadog memory leaking!

  initialize_profiles(state, sample_types);

  return stack_recorder;
}

static void initialize_slot_concurrency_control(struct stack_recorder_state *state) {
  state->slot_one_mutex = (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;
  state->slot_two_mutex = (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;

  // A newly-created StackRecorder starts with slot one being active for samples, so let's lock slot two
  ENFORCE_SUCCESS_GVL(pthread_mutex_lock(&state->slot_two_mutex));

  state->active_slot = 1;
}

static void initialize_profiles(struct stack_recorder_state *state, ddog_prof_Slice_ValueType sample_types) {
  ddog_prof_Profile_NewResult slot_one_profile_result =
    ddog_prof_Profile_new(sample_types, NULL /* period is optional */, NULL /* start_time is optional */);

  if (slot_one_profile_result.tag == DDOG_PROF_PROFILE_NEW_RESULT_ERR) {
    rb_raise(rb_eRuntimeError, "Failed to initialize slot one profile: %"PRIsVALUE, get_error_details_and_drop(&slot_one_profile_result.err));
  }

  ddog_prof_Profile_NewResult slot_two_profile_result =
    ddog_prof_Profile_new(sample_types, NULL /* period is optional */, NULL /* start_time is optional */);

  if (slot_two_profile_result.tag == DDOG_PROF_PROFILE_NEW_RESULT_ERR) {
    // Uff! Though spot. We need to make sure to properly clean up the other profile as well first
    ddog_prof_Profile_drop(&slot_one_profile_result.ok);
    // And now we can raise...
    rb_raise(rb_eRuntimeError, "Failed to initialize slot two profile: %"PRIsVALUE, get_error_details_and_drop(&slot_two_profile_result.err));
  }

  state->slot_one_profile = slot_one_profile_result.ok;
  state->slot_two_profile = slot_two_profile_result.ok;
}

static void stack_recorder_typed_data_free(void *state_ptr) {
  struct stack_recorder_state *state = (struct stack_recorder_state *) state_ptr;

  pthread_mutex_destroy(&state->slot_one_mutex);
  ddog_prof_Profile_drop(&state->slot_one_profile);

  pthread_mutex_destroy(&state->slot_two_mutex);
  ddog_prof_Profile_drop(&state->slot_two_profile);

  heap_recorder_free(state->heap_recorder);

  ruby_xfree(state);
}

static VALUE _native_initialize(
  DDTRACE_UNUSED VALUE _self,
  VALUE recorder_instance,
  VALUE cpu_time_enabled,
  VALUE alloc_samples_enabled,
  VALUE heap_samples_enabled,
  VALUE heap_size_enabled,
  VALUE heap_sample_every,
  VALUE timeline_enabled
) {
  ENFORCE_BOOLEAN(cpu_time_enabled);
  ENFORCE_BOOLEAN(alloc_samples_enabled);
  ENFORCE_BOOLEAN(heap_samples_enabled);
  ENFORCE_BOOLEAN(heap_size_enabled);
  ENFORCE_TYPE(heap_sample_every, T_FIXNUM);
  ENFORCE_BOOLEAN(timeline_enabled);

  struct stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, struct stack_recorder_state, &stack_recorder_typed_data, state);

  heap_recorder_set_sample_rate(state->heap_recorder, NUM2INT(heap_sample_every));

  uint8_t requested_values_count = ALL_VALUE_TYPES_COUNT -
    (cpu_time_enabled == Qtrue ? 0 : 1) -
    (alloc_samples_enabled == Qtrue? 0 : 1) -
    (heap_samples_enabled == Qtrue ? 0 : 1) -
    (heap_size_enabled == Qtrue ? 0 : 1) -
    (timeline_enabled == Qtrue ? 0 : 1);

  if (requested_values_count == ALL_VALUE_TYPES_COUNT) return Qtrue; // Nothing to do, this is the default

  // When some sample types are disabled, we need to reconfigure libdatadog to record less types,
  // as well as reconfigure the position_for array to push the disabled types to the end so they don't get recorded.
  // See record_sample for details on the use of position_for.

  state->enabled_values_count = requested_values_count;

  ddog_prof_ValueType enabled_value_types[ALL_VALUE_TYPES_COUNT];
  uint8_t next_enabled_pos = 0;
  uint8_t next_disabled_pos = requested_values_count;

  // CPU_SAMPLES_VALUE is always enabled
  enabled_value_types[next_enabled_pos] = (ddog_prof_ValueType) CPU_SAMPLES_VALUE;
  state->position_for[CPU_SAMPLES_VALUE_ID] = next_enabled_pos++;

  // WALL_TIME_VALUE is always enabled
  enabled_value_types[next_enabled_pos] = (ddog_prof_ValueType) WALL_TIME_VALUE;
  state->position_for[WALL_TIME_VALUE_ID] = next_enabled_pos++;

  if (cpu_time_enabled == Qtrue) {
    enabled_value_types[next_enabled_pos] = (ddog_prof_ValueType) CPU_TIME_VALUE;
    state->position_for[CPU_TIME_VALUE_ID] = next_enabled_pos++;
  } else {
    state->position_for[CPU_TIME_VALUE_ID] = next_disabled_pos++;
  }

  if (alloc_samples_enabled == Qtrue) {
    enabled_value_types[next_enabled_pos] = (ddog_prof_ValueType) ALLOC_SAMPLES_VALUE;
    state->position_for[ALLOC_SAMPLES_VALUE_ID] = next_enabled_pos++;
  } else {
    state->position_for[ALLOC_SAMPLES_VALUE_ID] = next_disabled_pos++;
  }

  if (heap_samples_enabled == Qtrue) {
    enabled_value_types[next_enabled_pos] = (ddog_prof_ValueType) HEAP_SAMPLES_VALUE;
    state->position_for[HEAP_SAMPLES_VALUE_ID] = next_enabled_pos++;
  } else {
    state->position_for[HEAP_SAMPLES_VALUE_ID] = next_disabled_pos++;
  }

  if (heap_size_enabled == Qtrue) {
    enabled_value_types[next_enabled_pos] = (ddog_prof_ValueType) HEAP_SIZE_VALUE;
    state->position_for[HEAP_SIZE_VALUE_ID] = next_enabled_pos++;
  } else {
    state->position_for[HEAP_SIZE_VALUE_ID] = next_disabled_pos++;
  }
  heap_recorder_set_size_enabled(state->heap_recorder, heap_size_enabled);

  if (heap_samples_enabled == Qfalse && heap_size_enabled == Qfalse) {
    // Turns out heap sampling is disabled but we initialized everything in _native_new
    // assuming all samples were enabled. We need to deinitialize the heap recorder.
    heap_recorder_free(state->heap_recorder);
    state->heap_recorder = NULL;
  }

  if (timeline_enabled == Qtrue) {
    enabled_value_types[next_enabled_pos] = (ddog_prof_ValueType) TIMELINE_VALUE;
    state->position_for[TIMELINE_VALUE_ID] = next_enabled_pos++;
  } else {
    state->position_for[TIMELINE_VALUE_ID] = next_disabled_pos++;
  }

  ddog_prof_Profile_drop(&state->slot_one_profile);
  ddog_prof_Profile_drop(&state->slot_two_profile);

  ddog_prof_Slice_ValueType sample_types = {.ptr = enabled_value_types, .len = state->enabled_values_count};
  initialize_profiles(state, sample_types);

  return Qtrue;
}

static VALUE _native_serialize(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) {
  struct stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, struct stack_recorder_state, &stack_recorder_typed_data, state);

  ddog_Timespec finish_timestamp = system_epoch_now_timespec();
  // Need to do this while still holding on to the Global VM Lock; see comments on method for why
  serializer_set_start_timestamp_for_next_profile(state, finish_timestamp);

  // Prepare the iteration on heap recorder we'll be doing outside the GVL. The preparation needs to
  // happen while holding on to the GVL.
  heap_recorder_prepare_iteration(state->heap_recorder);

  // We'll release the Global VM Lock while we're calling serialize, so that the Ruby VM can continue to work while this
  // is pending
  struct call_serialize_without_gvl_arguments args = {
    .state = state,
    .finish_timestamp = finish_timestamp,
    .gc_count_before_serialize = rb_gc_count(),
    .serialize_ran = false
  };

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

  // Cleanup after heap recorder iteration. This needs to happen while holding on to the GVL.
  heap_recorder_finish_iteration(state->heap_recorder);

  ddog_prof_Profile_SerializeResult serialized_profile = args.result;

  if (serialized_profile.tag == DDOG_PROF_PROFILE_SERIALIZE_RESULT_ERR) {
    return rb_ary_new_from_args(2, error_symbol, get_error_details_and_drop(&serialized_profile.err));
  }

  VALUE encoded_pprof = ruby_string_from_vec_u8(serialized_profile.ok.buffer);

  ddog_Timespec ddprof_start = serialized_profile.ok.start;
  ddog_Timespec ddprof_finish = serialized_profile.ok.end;

  ddog_prof_EncodedProfile_drop(&serialized_profile.ok);

  VALUE start = ruby_time_from(ddprof_start);
  VALUE finish = ruby_time_from(ddprof_finish);

  return rb_ary_new_from_args(2, ok_symbol, rb_ary_new_from_args(3, start, finish, encoded_pprof));
}

static VALUE ruby_time_from(ddog_Timespec ddprof_time) {
  const int utc = INT_MAX - 1; // From Ruby sources
  struct timespec time = {.tv_sec = ddprof_time.seconds, .tv_nsec = ddprof_time.nanoseconds};
  return rb_time_timespec_new(&time, utc);
}

void record_sample(VALUE recorder_instance, ddog_prof_Slice_Location locations, sample_values values, sample_labels labels) {
  struct stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, struct stack_recorder_state, &stack_recorder_typed_data, state);

  struct active_slot_pair active_slot = sampler_lock_active_profile(state);

  // Note: We initialize this array to have ALL_VALUE_TYPES_COUNT but only tell libdatadog to use the first
  // state->enabled_values_count values. This simplifies handling disabled value types -- we still put them on the
  // array, but in _native_initialize we arrange so their position starts from state->enabled_values_count and thus
  // libdatadog doesn't touch them.
  int64_t metric_values[ALL_VALUE_TYPES_COUNT] = {0};
  uint8_t *position_for = state->position_for;

  metric_values[position_for[CPU_TIME_VALUE_ID]]      = values.cpu_time_ns;
  metric_values[position_for[CPU_SAMPLES_VALUE_ID]]   = values.cpu_or_wall_samples;
  metric_values[position_for[WALL_TIME_VALUE_ID]]     = values.wall_time_ns;
  metric_values[position_for[ALLOC_SAMPLES_VALUE_ID]] = values.alloc_samples;
  metric_values[position_for[TIMELINE_VALUE_ID]]      = values.timeline_wall_time_ns;

  if (values.alloc_samples != 0) {
    // If we got an allocation sample end the heap allocation recording to commit the heap sample.
    // FIXME: Heap sampling currently has to be done in 2 parts because the construction of locations is happening
    //        very late in the allocation-sampling path (which is shared with the cpu sampling path). This can
    //        be fixed with some refactoring but for now this leads to a less impactful change.
    end_heap_allocation_recording(state->heap_recorder, locations);
  }

  ddog_prof_Profile_Result result = ddog_prof_Profile_add(
    active_slot.profile,
    (ddog_prof_Sample) {
      .locations = locations,
      .values = (ddog_Slice_I64) {.ptr = metric_values, .len = state->enabled_values_count},
      .labels = labels.labels
    },
    labels.end_timestamp_ns
  );

  sampler_unlock_active_profile(active_slot);

  if (result.tag == DDOG_PROF_PROFILE_RESULT_ERR) {
    rb_raise(rb_eArgError, "Failed to record sample: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }
}

void track_object(VALUE recorder_instance, VALUE new_object, unsigned int sample_weight, ddog_CharSlice *alloc_class) {
  struct stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, struct stack_recorder_state, &stack_recorder_typed_data, state);
  // FIXME: Heap sampling currently has to be done in 2 parts because the construction of locations is happening
  //        very late in the allocation-sampling path (which is shared with the cpu sampling path). This can
  //        be fixed with some refactoring but for now this leads to a less impactful change.
  start_heap_allocation_recording(state->heap_recorder, new_object, sample_weight, alloc_class);
}

void record_endpoint(VALUE recorder_instance, uint64_t local_root_span_id, ddog_CharSlice endpoint) {
  struct stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, struct stack_recorder_state, &stack_recorder_typed_data, state);

  struct active_slot_pair active_slot = sampler_lock_active_profile(state);

  ddog_prof_Profile_Result result = ddog_prof_Profile_set_endpoint(active_slot.profile, local_root_span_id, endpoint);

  sampler_unlock_active_profile(active_slot);

  if (result.tag == DDOG_PROF_PROFILE_RESULT_ERR) {
    rb_raise(rb_eArgError, "Failed to record endpoint: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }
}

#define MAX_LEN_HEAP_ITERATION_ERROR_MSG 256

// Heap recorder iteration context allows us access to stack recorder state and profile being serialized
// during iteration of heap recorder live objects.
typedef struct heap_recorder_iteration_context {
  struct stack_recorder_state *state;
  ddog_prof_Profile *profile;

  bool error;
  char error_msg[MAX_LEN_HEAP_ITERATION_ERROR_MSG];

  size_t profile_gen;
} heap_recorder_iteration_context;

static bool add_heap_sample_to_active_profile_without_gvl(heap_recorder_iteration_data iteration_data, void *extra_arg) {
  heap_recorder_iteration_context *context = (heap_recorder_iteration_context*) extra_arg;

  live_object_data *object_data = &iteration_data.object_data;

  int64_t metric_values[ALL_VALUE_TYPES_COUNT] = {0};
  uint8_t *position_for = context->state->position_for;

  metric_values[position_for[HEAP_SAMPLES_VALUE_ID]] = object_data->weight;
  metric_values[position_for[HEAP_SIZE_VALUE_ID]] = object_data->size * object_data->weight;

  ddog_prof_Label labels[2];
  size_t label_offset = 0;

  if (object_data->class != NULL) {
    labels[label_offset++] = (ddog_prof_Label) {
      .key = DDOG_CHARSLICE_C("allocation class"),
      .str = (ddog_CharSlice) {
        .ptr = object_data->class,
        .len = strlen(object_data->class),
      },
      .num = 0, // This shouldn't be needed but the tracer-2.7 docker image ships a buggy gcc that complains about this
    };
  }
  labels[label_offset++] = (ddog_prof_Label) {
    .key = DDOG_CHARSLICE_C("gc gen age"),
    .num = context->profile_gen - object_data->alloc_gen,
  };

  ddog_prof_Profile_Result result = ddog_prof_Profile_add(
    context->profile,
    (ddog_prof_Sample) {
      .locations = iteration_data.locations,
      .values = (ddog_Slice_I64) {.ptr = metric_values, .len = context->state->enabled_values_count},
      .labels = (ddog_prof_Slice_Label) {
        .ptr = labels,
        .len = label_offset,
      }
    },
    0
  );

  if (result.tag == DDOG_PROF_PROFILE_RESULT_ERR) {
    read_ddogerr_string_and_drop(&result.err, context->error_msg, MAX_LEN_HEAP_ITERATION_ERROR_MSG);
    context->error = true;
    // By returning false we cancel the iteration
    return false;
  }

  // Keep on iterating to next item!
  return true;
}

static void build_heap_profile_without_gvl(struct stack_recorder_state *state, ddog_prof_Profile *profile, size_t gc_count_before_serialize) {
  heap_recorder_iteration_context iteration_context = {
    .state = state,
    .profile = profile,
    .error = false,
    .error_msg = {0},
    .profile_gen = gc_count_before_serialize,
  };
  bool iterated = heap_recorder_for_each_live_object(state->heap_recorder, add_heap_sample_to_active_profile_without_gvl, (void*) &iteration_context);
  // We wait until we're out of the iteration to grab the gvl and raise. This is important because during
  // iteration we may potentially acquire locks in the heap recorder and we could reach a deadlock if the
  // same locks are acquired by the heap recorder while holding the gvl (since we'd be operating on the
  // same locks but acquiring them in different order).
  if (!iterated) {
    grab_gvl_and_raise(rb_eRuntimeError, "Failure during heap profile building: iteration cancelled");
  }
  else if (iteration_context.error) {
    grab_gvl_and_raise(rb_eRuntimeError, "Failure during heap profile building: %s", iteration_context.error_msg);
  }
}

static void *call_serialize_without_gvl(void *call_args) {
  struct call_serialize_without_gvl_arguments *args = (struct call_serialize_without_gvl_arguments *) call_args;

  args->profile = serializer_flip_active_and_inactive_slots(args->state);

  // Now that we have the inactive profile with all but heap samples, lets fill it with heap data
  // without needing to race with the active sampler
  build_heap_profile_without_gvl(args->state, args->profile, args->gc_count_before_serialize);

  // Note: The profile gets reset by the serialize call
  args->result = ddog_prof_Profile_serialize(args->profile, &args->finish_timestamp, NULL /* duration_nanos is optional */, NULL /* start_time is optional */);
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
    if (!error) return (struct active_slot_pair) {.mutex = &state->slot_one_mutex, .profile = &state->slot_one_profile};

    // If we got here, slot one was not active, let's try slot two

    error = pthread_mutex_trylock(&state->slot_two_mutex);
    if (error && error != EBUSY) ENFORCE_SUCCESS_GVL(error);

    // Slot two is active
    if (!error) return (struct active_slot_pair) {.mutex = &state->slot_two_mutex, .profile = &state->slot_two_profile};
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
  return (previously_active_slot == 1) ? &state->slot_one_profile : &state->slot_two_profile;
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

static ddog_Timespec system_epoch_now_timespec(void) {
  long now_ns = system_epoch_time_now_ns(RAISE_ON_FAILURE);
  return (ddog_Timespec) {.seconds = now_ns / SECONDS_AS_NS(1), .nanoseconds = now_ns % SECONDS_AS_NS(1)};
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

  reset_profile(&state->slot_one_profile, /* start_time: */ NULL);
  reset_profile(&state->slot_two_profile, /* start_time: */ NULL);

  heap_recorder_after_fork(state->heap_recorder);

  return Qtrue;
}

// Assumption 1: This method is called with the GVL being held, because `ddog_prof_Profile_reset` mutates the profile and must
// not be interrupted part-way through by a VM fork.
static void serializer_set_start_timestamp_for_next_profile(struct stack_recorder_state *state, ddog_Timespec start_time) {
  // Before making this profile active, we reset it so that it uses the correct start_time for its start
  ddog_prof_Profile *next_profile = (state->active_slot == 1) ? &state->slot_two_profile : &state->slot_one_profile;
  reset_profile(next_profile, &start_time);
}

static VALUE _native_record_endpoint(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance, VALUE local_root_span_id, VALUE endpoint) {
  ENFORCE_TYPE(local_root_span_id, T_FIXNUM);
  record_endpoint(recorder_instance, NUM2ULL(local_root_span_id), char_slice_from_ruby_string(endpoint));
  return Qtrue;
}

static VALUE _native_track_object(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance, VALUE new_obj, VALUE weight, VALUE alloc_class) {
  ENFORCE_TYPE(weight, T_FIXNUM);
  ddog_CharSlice alloc_class_slice = char_slice_from_ruby_string(alloc_class);
  track_object(recorder_instance, new_obj, NUM2UINT(weight), &alloc_class_slice);
  return Qtrue;
}

static VALUE _native_check_heap_hashes(DDTRACE_UNUSED VALUE _self, VALUE locations) {
  ENFORCE_TYPE(locations, T_ARRAY);
  size_t locations_len = rb_array_len(locations);
  ddog_prof_Location locations_arr[locations_len];
  for (size_t i = 0; i < locations_len; i++) {
    VALUE location = rb_ary_entry(locations, i);
    ENFORCE_TYPE(location, T_ARRAY);
    VALUE name = rb_ary_entry(location, 0);
    VALUE filename = rb_ary_entry(location, 1);
    VALUE line = rb_ary_entry(location, 2);
    ENFORCE_TYPE(name, T_STRING);
    ENFORCE_TYPE(filename, T_STRING);
    ENFORCE_TYPE(line, T_FIXNUM);
    locations_arr[i] = (ddog_prof_Location) {
      .line = line,
        .function = (ddog_prof_Function) {
          .name = char_slice_from_ruby_string(name),
          .filename = char_slice_from_ruby_string(filename),
        }
    };
  }
  ddog_prof_Slice_Location ddog_locations = {
    .len = locations_len,
    .ptr = locations_arr,
  };
  heap_recorder_testonly_assert_hash_matches(ddog_locations);

  return Qnil;
}

static void reset_profile(ddog_prof_Profile *profile, ddog_Timespec *start_time /* Can be null */) {
  ddog_prof_Profile_Result reset_result = ddog_prof_Profile_reset(profile, start_time);
  if (reset_result.tag == DDOG_PROF_PROFILE_RESULT_ERR) {
    rb_raise(rb_eRuntimeError, "Failed to reset profile: %"PRIsVALUE, get_error_details_and_drop(&reset_result.err));
  }
}

// This method exists only to enable testing Datadog::Profiling::StackRecorder behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_start_fake_slow_heap_serialization(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) {
  struct stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, struct stack_recorder_state, &stack_recorder_typed_data, state);

  heap_recorder_prepare_iteration(state->heap_recorder);

  return Qnil;
}

// This method exists only to enable testing Datadog::Profiling::StackRecorder behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_end_fake_slow_heap_serialization(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) {
  struct stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, struct stack_recorder_state, &stack_recorder_typed_data, state);

  heap_recorder_finish_iteration(state->heap_recorder);

  return Qnil;
}

// This method exists only to enable testing Datadog::Profiling::StackRecorder behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_debug_heap_recorder(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) {
  struct stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, struct stack_recorder_state, &stack_recorder_typed_data, state);

  return heap_recorder_testonly_debug(state->heap_recorder);
}

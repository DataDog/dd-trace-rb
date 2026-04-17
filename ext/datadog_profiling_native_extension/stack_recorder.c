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
#include "encoded_profile.h"

_Static_assert(
  sizeof(ddog_prof_FunctionId2) == sizeof(uintptr_t),
  "ddog_prof_FunctionId2 must fit in uintptr_t to be stored as a Ruby Integer");

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

#define CPU_TIME_VALUE_ID 0
#define CPU_SAMPLES_VALUE_ID 1
#define WALL_TIME_VALUE_ID 2
#define ALLOC_SAMPLES_VALUE_ID 3
#define ALLOC_SAMPLES_UNSCALED_VALUE_ID 4
#define HEAP_SAMPLES_VALUE_ID 5
#define HEAP_SIZE_VALUE_ID 6
#define TIMELINE_VALUE_ID 7

static const ddog_prof_SampleType all_sample_types[] = {
  DDOG_PROF_SAMPLE_TYPE_CPU_TIME,
  DDOG_PROF_SAMPLE_TYPE_CPU_SAMPLES,
  DDOG_PROF_SAMPLE_TYPE_WALL_TIME,
  DDOG_PROF_SAMPLE_TYPE_ALLOC_SAMPLES,
  DDOG_PROF_SAMPLE_TYPE_ALLOC_SAMPLES_UNSCALED,
  DDOG_PROF_SAMPLE_TYPE_HEAP_LIVE_SAMPLES,
  DDOG_PROF_SAMPLE_TYPE_HEAP_LIVE_SIZE,
  DDOG_PROF_SAMPLE_TYPE_TIMELINE,
};

// This array MUST be kept in sync with all_sample_types above and is intended to act as a "hashmap" between VALUE_ID and the position it
// occupies on the all_sample_types array.
static const uint8_t all_value_types_positions[] =
  {CPU_TIME_VALUE_ID, CPU_SAMPLES_VALUE_ID, WALL_TIME_VALUE_ID, ALLOC_SAMPLES_VALUE_ID, ALLOC_SAMPLES_UNSCALED_VALUE_ID, HEAP_SAMPLES_VALUE_ID, HEAP_SIZE_VALUE_ID, TIMELINE_VALUE_ID};

#define ALL_VALUE_TYPES_COUNT (sizeof(all_sample_types) / sizeof(ddog_prof_SampleType))

// Struct for storing stats related to a profile in a particular slot.
// These stats will share the same lifetime as the data in that profile slot.
typedef struct {
  // How many individual samples were recorded into this slot (un-weighted)
  uint64_t recorded_samples;
} stats_slot;

typedef struct {
  ddog_prof_Profile profile;
  stats_slot stats;
  ddog_Timespec start_timestamp;
} profile_slot;

// Contains native state for each instance
typedef struct {
  // Heap recorder instance
  heap_recorder *heap_recorder;
  bool heap_clean_after_gc_enabled;

  pthread_mutex_t mutex_slot_one;
  profile_slot profile_slot_one;
  pthread_mutex_t mutex_slot_two;
  profile_slot profile_slot_two;

  ddog_prof_ProfilesDictionaryHandle dict_handle;
  ddog_prof_StringId2 label_key_allocation_class;
  ddog_prof_StringId2 label_key_gc_gen_age;

  // Caches mapping frame identity -> FunctionId2.
  // iseq_cache: st_table* (pointer-comparison hash). Keys are raw iseq VALUEs (T_IMEMO objects);
  //   values are raw ddog_prof_FunctionId2 pointers, both stored as st_data_t (uintptr_t).
  //   Using st_table avoids calling Ruby's #hash on keys (T_IMEMO doesn't implement it) and
  //   avoids any Ruby allocation on lookup/insert (safe inside NEWOBJ tracepoint hooks).
  //   The GC mark function marks each key via rb_gc_mark, which also pins iseqs in place so
  //   the compactor cannot move them (which would silently invalidate our st_table keys).
  // native_id_cache: st_table* (integer-keyed). Keys are Ruby IDs (method_id); values are
  //   raw ddog_prof_FunctionId2 pointers stored as st_data_t. Native frames always use
  //   file_name="" so a single FunctionId2 per method_id is sufficient.
  st_table *iseq_cache;
  st_table *native_id_cache;

  // Pre-allocated FunctionId2 for the synthetic "Truncated Frames" placeholder injected at the
  // bottom of stacks that exceeded max_frames. Matches the entry that
  // add_truncated_frames_placeholder injects into buffer->locations[0].
  ddog_prof_FunctionId2 truncated_frames_function_id;

  short active_slot; // MUST NEVER BE ACCESSED FROM record_sample; this is NOT for the sampler thread to use.

  uint8_t position_for[ALL_VALUE_TYPES_COUNT];
  uint8_t enabled_values_count;

  // Struct for storing stats related to behaviour of a stack recorder instance during its entire lifetime.
  struct lifetime_stats {
    // How many profiles have we serialized successfully so far
    uint64_t serialization_successes;
    // How many profiles have we serialized unsuccessfully so far
    uint64_t serialization_failures;
    // Stats on profile serialization time
    long serialization_time_ns_min;
    long serialization_time_ns_max;
    uint64_t serialization_time_ns_total;
  } stats_lifetime;

  // When non-zero, rotate the ProfilesDictionary (and caches) every this many successful serializations.
  // Intended for testing only — not for production use.
  uint64_t dictionary_rotation_period;
} stack_recorder_state;

// Used to group mutex and the corresponding profile slot for easy unlocking after work is done.
typedef struct {
  pthread_mutex_t *mutex;
  profile_slot *data;
} locked_profile_slot;

typedef struct {
  // Set by caller
  stack_recorder_state *state;
  ddog_Timespec finish_timestamp;

  // Set by callee
  profile_slot *slot;
  ddog_prof_Profile_SerializeResult result;
  long heap_profile_build_time_ns;
  long serialize_no_gvl_time_ns;

  // Set by both
  bool serialize_ran;
} call_serialize_without_gvl_arguments;

static VALUE _native_new(VALUE klass);
static void initialize_slot_concurrency_control(stack_recorder_state *state);
static void stack_recorder_typed_data_mark(void *data);
static void initialize_profiles(stack_recorder_state *state, ddog_prof_Slice_SampleType sample_types);
static void stack_recorder_typed_data_free(void *data);
static VALUE _native_initialize(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self);
static VALUE _native_serialize(VALUE self, VALUE recorder_instance);
static VALUE ruby_time_from(ddog_Timespec ddprof_time);
static void *call_serialize_without_gvl(void *call_args);
static locked_profile_slot sampler_lock_active_profile(stack_recorder_state *state);
static void sampler_unlock_active_profile(locked_profile_slot active_slot);
static profile_slot* serializer_flip_active_and_inactive_slots(stack_recorder_state *state);
static VALUE _native_active_slot(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);
static VALUE _native_is_slot_one_mutex_locked(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);
static VALUE _native_is_slot_two_mutex_locked(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);
static VALUE test_slot_mutex_state(VALUE recorder_instance, int slot);
static ddog_Timespec system_epoch_now_timespec(void);
static VALUE _native_reset_after_fork(DDTRACE_UNUSED VALUE self, VALUE recorder_instance);
static void serializer_set_start_timestamp_for_next_profile(stack_recorder_state *state, ddog_Timespec start_time);
static VALUE _native_record_endpoint(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance, VALUE local_root_span_id, VALUE endpoint);
static void reset_profile_slot(profile_slot *slot, ddog_Timespec start_timestamp);
static VALUE _native_track_object(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance, VALUE new_obj, VALUE weight, VALUE alloc_class);
static VALUE _native_start_fake_slow_heap_serialization(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);
static VALUE _native_end_fake_slow_heap_serialization(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);
static VALUE _native_debug_heap_recorder(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);
static VALUE _native_stats(DDTRACE_UNUSED VALUE self, VALUE instance);
static VALUE build_profile_stats(profile_slot *slot, long serialization_time_ns, long heap_iteration_prep_time_ns, long heap_profile_build_time_ns);
static VALUE _native_is_object_recorded(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance, VALUE object_id);
static VALUE _native_heap_recorder_reset_last_update(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);
static VALUE _native_recorder_after_gc_step(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);
static VALUE _native_benchmark_intern(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance, VALUE string, VALUE times, VALUE use_all);
static VALUE _native_finalize_pending_heap_recordings(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance);
static void rotate_profiles_dictionary(stack_recorder_state *state);

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

  rb_define_singleton_method(stack_recorder_class, "_native_initialize", _native_initialize, -1);
  rb_define_singleton_method(stack_recorder_class, "_native_serialize",  _native_serialize, 1);
  rb_define_singleton_method(stack_recorder_class, "_native_reset_after_fork", _native_reset_after_fork, 1);
  rb_define_singleton_method(stack_recorder_class, "_native_stats", _native_stats, 1);
  rb_define_singleton_method(testing_module, "_native_active_slot", _native_active_slot, 1);
  rb_define_singleton_method(testing_module, "_native_slot_one_mutex_locked?", _native_is_slot_one_mutex_locked, 1);
  rb_define_singleton_method(testing_module, "_native_slot_two_mutex_locked?", _native_is_slot_two_mutex_locked, 1);
  rb_define_singleton_method(testing_module, "_native_record_endpoint", _native_record_endpoint, 3);
  rb_define_singleton_method(testing_module, "_native_track_object", _native_track_object, 4);
  rb_define_singleton_method(testing_module, "_native_start_fake_slow_heap_serialization",
      _native_start_fake_slow_heap_serialization, 1);
  rb_define_singleton_method(testing_module, "_native_end_fake_slow_heap_serialization",
      _native_end_fake_slow_heap_serialization, 1);
  rb_define_singleton_method(testing_module, "_native_debug_heap_recorder",
      _native_debug_heap_recorder, 1);
  rb_define_singleton_method(testing_module, "_native_is_object_recorded?", _native_is_object_recorded, 2);
  rb_define_singleton_method(testing_module, "_native_heap_recorder_reset_last_update", _native_heap_recorder_reset_last_update, 1);
  rb_define_singleton_method(testing_module, "_native_recorder_after_gc_step", _native_recorder_after_gc_step, 1);
  rb_define_singleton_method(testing_module, "_native_benchmark_intern", _native_benchmark_intern, 4);
  rb_define_singleton_method(testing_module, "_native_finalize_pending_heap_recordings", _native_finalize_pending_heap_recordings, 1);

  ok_symbol = ID2SYM(rb_intern_const("ok"));
  error_symbol = ID2SYM(rb_intern_const("error"));
}

// This structure is used to define a Ruby object that stores a pointer to a ddog_prof_Profile instance
// See also https://github.com/ruby/ruby/blob/master/doc/extension.rdoc for how this works
static const rb_data_type_t stack_recorder_typed_data = {
  .wrap_struct_name = "Datadog::Profiling::StackRecorder",
  .function = {
    .dmark = stack_recorder_typed_data_mark,
    .dfree = stack_recorder_typed_data_free,
    .dsize = NULL, // We don't track profile memory usage (although it'd be cool if we did!)
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE _native_new(VALUE klass) {
  stack_recorder_state *state = ruby_xcalloc(1, sizeof(stack_recorder_state));

  // Note: Any exceptions raised from this note until the TypedData_Wrap_Struct call will lead to the state memory
  // being leaked.

  state->heap_clean_after_gc_enabled = false;

  ddog_prof_Slice_SampleType sample_types = {.ptr = all_sample_types, .len = ALL_VALUE_TYPES_COUNT};

  initialize_slot_concurrency_control(state);
  for (uint8_t i = 0; i < ALL_VALUE_TYPES_COUNT; i++) { state->position_for[i] = all_value_types_positions[i]; }
  state->enabled_values_count = ALL_VALUE_TYPES_COUNT;
  state->stats_lifetime = (struct lifetime_stats) {
    .serialization_time_ns_min = INT64_MAX,
  };

  // Note: At this point, slot_one_profile/slot_two_profile/dict_handle contain null pointers. Libdatadog validates pointers
  // before using them so it's ok for us to go ahead and create the StackRecorder object.

  VALUE stack_recorder = TypedData_Wrap_Struct(klass, &stack_recorder_typed_data, state);

  ddog_prof_Status s = ddog_prof_ProfilesDictionary_new(&state->dict_handle);
  if (s.err != NULL) raise_status_error("Failed to create ProfilesDictionary", &s);

  s = ddog_prof_ProfilesDictionary_insert_str(
      &state->label_key_allocation_class, state->dict_handle,
      DDOG_CHARSLICE_C("allocation class"), DDOG_PROF_UTF8_OPTION_ASSUME);
  if (s.err != NULL) raise_status_error("Failed to insert allocation class key", &s);

  s = ddog_prof_ProfilesDictionary_insert_str(
      &state->label_key_gc_gen_age, state->dict_handle,
      DDOG_CHARSLICE_C("gc gen age"), DDOG_PROF_UTF8_OPTION_ASSUME);
  if (s.err != NULL) raise_status_error("Failed to insert gc gen age key", &s);

  // Pre-populate the "Truncated Frames" function so that stacks exceeding max_frames get the same
  // placeholder in the heap profile as in the CPU/wall profile (where add_truncated_frames_placeholder
  // patches buffer->locations[0] with this name).
  {
    ddog_prof_StringId2 truncated_name_sid = NULL, empty_sid = NULL;
    s = ddog_prof_ProfilesDictionary_insert_str(&truncated_name_sid, state->dict_handle, DDOG_CHARSLICE_C("Truncated Frames"), DDOG_PROF_UTF8_OPTION_ASSUME);
    if (s.err != NULL) raise_status_error("Failed to insert Truncated Frames name", &s);

    s = ddog_prof_ProfilesDictionary_insert_str(&empty_sid, state->dict_handle, DDOG_CHARSLICE_C(""), DDOG_PROF_UTF8_OPTION_ASSUME);
    if (s.err != NULL) raise_status_error("Failed to insert empty string", &s);

    ddog_prof_Function2 truncated_func = { .name = truncated_name_sid, .system_name = NULL, .file_name = empty_sid };
    s = ddog_prof_ProfilesDictionary_insert_function(&state->truncated_frames_function_id, state->dict_handle, &truncated_func);
    if (s.err != NULL) raise_status_error("Failed to insert Truncated Frames function", &s);
  }

  initialize_profiles(state, sample_types);

  state->iseq_cache = st_init_numtable();        // pointer-comparison; keys are iseq VALUEs
  state->native_id_cache = st_init_numtable();  // integer-keyed; keys are Ruby method IDs

  // NOTE: We initialize this because we want a new recorder to be operational even before #initialize runs and our
  //       default is everything enabled. However, if during recording initialization it turns out we don't want
  //       heap samples, we will free and reset heap_recorder back to NULL.
  state->heap_recorder = heap_recorder_new();

  return stack_recorder;
}

static void initialize_slot_concurrency_control(stack_recorder_state *state) {
  state->mutex_slot_one = (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;
  state->mutex_slot_two = (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;

  // A newly-created StackRecorder starts with slot one being active for samples, so let's lock slot two
  ENFORCE_SUCCESS_GVL(pthread_mutex_lock(&state->mutex_slot_two));

  state->active_slot = 1;
}

static void initialize_profiles(stack_recorder_state *state, ddog_prof_Slice_SampleType sample_types) {
  ddog_Timespec start_timestamp = system_epoch_now_timespec();
  ddog_prof_Status s;

  // Use ddog_prof_Profile_with_dictionary so that profiles support both ddog_prof_Profile_add (for
  // cpu/wall-time/allocation samples) and ddog_prof_Profile_add2 (for heap serialization).
  s = ddog_prof_Profile_with_dictionary(&state->profile_slot_one.profile, &state->dict_handle, sample_types, NULL /* period is optional */);
  if (s.err != NULL) raise_status_error("Failed to initialize slot one profile", &s);
  state->profile_slot_one.start_timestamp = start_timestamp;

  // Note: No need to take any special care of slot one on error; it'll get cleaned up by stack_recorder_typed_data_free
  s = ddog_prof_Profile_with_dictionary(&state->profile_slot_two.profile, &state->dict_handle, sample_types, NULL /* period is optional */);
  if (s.err != NULL) raise_status_error("Failed to initialize slot two profile", &s);
  state->profile_slot_two.start_timestamp = start_timestamp;
}

static int mark_iseq_cache_key(st_data_t key, DDTRACE_UNUSED st_data_t value, DDTRACE_UNUSED st_data_t extra) {
  // rb_gc_mark (not rb_gc_mark_movable) pins the iseq at its current address, preventing the
  // compactor from moving it and silently invalidating our st_table key.
  rb_gc_mark((VALUE) key);
  return ST_CONTINUE;
}

static void stack_recorder_typed_data_mark(void *state_ptr) {
  stack_recorder_state *state = (stack_recorder_state *) state_ptr;

  heap_recorder_mark_pending_recordings(state->heap_recorder);
  st_foreach(state->iseq_cache, mark_iseq_cache_key, 0);
}

static void stack_recorder_typed_data_free(void *state_ptr) {
  stack_recorder_state *state = (stack_recorder_state *) state_ptr;

  pthread_mutex_destroy(&state->mutex_slot_one);
  ddog_prof_Profile_drop(&state->profile_slot_one.profile);

  pthread_mutex_destroy(&state->mutex_slot_two);
  ddog_prof_Profile_drop(&state->profile_slot_two.profile);

  heap_recorder_free(state->heap_recorder);

  ddog_prof_ProfilesDictionary_drop(&state->dict_handle);

  st_free_table(state->iseq_cache);
  st_free_table(state->native_id_cache);

  ruby_xfree(state);
}

static VALUE _native_initialize(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self) {
  VALUE options;
  rb_scan_args(argc, argv, "0:", &options);
  if (options == Qnil) options = rb_hash_new();

  VALUE recorder_instance = rb_hash_fetch(options, ID2SYM(rb_intern("self_instance")));
  VALUE cpu_time_enabled = rb_hash_fetch(options, ID2SYM(rb_intern("cpu_time_enabled")));
  VALUE alloc_samples_enabled = rb_hash_fetch(options, ID2SYM(rb_intern("alloc_samples_enabled")));
  VALUE heap_samples_enabled = rb_hash_fetch(options, ID2SYM(rb_intern("heap_samples_enabled")));
  VALUE heap_size_enabled = rb_hash_fetch(options, ID2SYM(rb_intern("heap_size_enabled")));
  VALUE heap_sample_every = rb_hash_fetch(options, ID2SYM(rb_intern("heap_sample_every")));
  VALUE timeline_enabled = rb_hash_fetch(options, ID2SYM(rb_intern("timeline_enabled")));
  VALUE heap_clean_after_gc_enabled = rb_hash_fetch(options, ID2SYM(rb_intern("heap_clean_after_gc_enabled")));
  VALUE dictionary_rotation_period = rb_hash_fetch(options, ID2SYM(rb_intern("dictionary_rotation_period")));

  ENFORCE_BOOLEAN(cpu_time_enabled);
  ENFORCE_BOOLEAN(alloc_samples_enabled);
  ENFORCE_BOOLEAN(heap_samples_enabled);
  ENFORCE_BOOLEAN(heap_size_enabled);
  ENFORCE_TYPE(heap_sample_every, T_FIXNUM);
  ENFORCE_BOOLEAN(timeline_enabled);
  ENFORCE_BOOLEAN(heap_clean_after_gc_enabled);
  ENFORCE_TYPE(dictionary_rotation_period, T_FIXNUM);

  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);

  state->heap_clean_after_gc_enabled = (heap_clean_after_gc_enabled == Qtrue);
  state->dictionary_rotation_period = (uint64_t) NUM2ULONG(dictionary_rotation_period);

  heap_recorder_set_sample_rate(state->heap_recorder, NUM2INT(heap_sample_every));

  uint8_t requested_values_count = ALL_VALUE_TYPES_COUNT -
    (cpu_time_enabled == Qtrue ? 0 : 1) -
    (alloc_samples_enabled == Qtrue? 0 : 2) -
    (heap_samples_enabled == Qtrue ? 0 : 1) -
    (heap_size_enabled == Qtrue ? 0 : 1) -
    (timeline_enabled == Qtrue ? 0 : 1);

  if (requested_values_count == ALL_VALUE_TYPES_COUNT) return Qtrue; // Nothing to do, this is the default

  // When some sample types are disabled, we need to reconfigure libdatadog to record less types,
  // as well as reconfigure the position_for array to push the disabled types to the end so they don't get recorded.
  // See record_sample for details on the use of position_for.

  state->enabled_values_count = requested_values_count;

  ddog_prof_SampleType enabled_sample_types[ALL_VALUE_TYPES_COUNT];
  uint8_t next_enabled_pos = 0;
  uint8_t next_disabled_pos = requested_values_count;

  // CPU_SAMPLES is always enabled
  enabled_sample_types[next_enabled_pos] = DDOG_PROF_SAMPLE_TYPE_CPU_SAMPLES;
  state->position_for[CPU_SAMPLES_VALUE_ID] = next_enabled_pos++;

  // WALL_TIME is always enabled
  enabled_sample_types[next_enabled_pos] = DDOG_PROF_SAMPLE_TYPE_WALL_TIME;
  state->position_for[WALL_TIME_VALUE_ID] = next_enabled_pos++;

  if (cpu_time_enabled == Qtrue) {
    enabled_sample_types[next_enabled_pos] = DDOG_PROF_SAMPLE_TYPE_CPU_TIME;
    state->position_for[CPU_TIME_VALUE_ID] = next_enabled_pos++;
  } else {
    state->position_for[CPU_TIME_VALUE_ID] = next_disabled_pos++;
  }

  if (alloc_samples_enabled == Qtrue) {
    enabled_sample_types[next_enabled_pos] = DDOG_PROF_SAMPLE_TYPE_ALLOC_SAMPLES;
    state->position_for[ALLOC_SAMPLES_VALUE_ID] = next_enabled_pos++;

    enabled_sample_types[next_enabled_pos] = DDOG_PROF_SAMPLE_TYPE_ALLOC_SAMPLES_UNSCALED;
    state->position_for[ALLOC_SAMPLES_UNSCALED_VALUE_ID] = next_enabled_pos++;
  } else {
    state->position_for[ALLOC_SAMPLES_VALUE_ID] = next_disabled_pos++;
    state->position_for[ALLOC_SAMPLES_UNSCALED_VALUE_ID] = next_disabled_pos++;
  }

  if (heap_samples_enabled == Qtrue) {
    enabled_sample_types[next_enabled_pos] = DDOG_PROF_SAMPLE_TYPE_HEAP_LIVE_SAMPLES;
    state->position_for[HEAP_SAMPLES_VALUE_ID] = next_enabled_pos++;
  } else {
    state->position_for[HEAP_SAMPLES_VALUE_ID] = next_disabled_pos++;
  }

  if (heap_size_enabled == Qtrue) {
    enabled_sample_types[next_enabled_pos] = DDOG_PROF_SAMPLE_TYPE_HEAP_LIVE_SIZE;
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
    enabled_sample_types[next_enabled_pos] = DDOG_PROF_SAMPLE_TYPE_TIMELINE;
    state->position_for[TIMELINE_VALUE_ID] = next_enabled_pos++;
  } else {
    state->position_for[TIMELINE_VALUE_ID] = next_disabled_pos++;
  }

  ddog_prof_Profile_drop(&state->profile_slot_one.profile);
  ddog_prof_Profile_drop(&state->profile_slot_two.profile);

  ddog_prof_Slice_SampleType sample_types = {.ptr = enabled_sample_types, .len = state->enabled_values_count};
  initialize_profiles(state, sample_types);

  return Qtrue;
}

static VALUE _native_serialize(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) {
  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);

  ddog_Timespec finish_timestamp = system_epoch_now_timespec();
  // Need to do this while still holding on to the Global VM Lock; see comments on method for why
  serializer_set_start_timestamp_for_next_profile(state, finish_timestamp);

  long heap_iteration_prep_start_time_ns = monotonic_wall_time_now_ns(DO_NOT_RAISE_ON_FAILURE);
  // Prepare the iteration on heap recorder we'll be doing outside the GVL. The preparation needs to
  // happen while holding on to the GVL.
  // NOTE: While rare, it's possible for the GVL to be released inside this function (see comments on `heap_recorder_update`)
  // and thus don't assume this is an "atomic" step -- other threads may get some running time in the meanwhile.
  heap_recorder_prepare_iteration(state->heap_recorder);
  long heap_iteration_prep_time_ns = monotonic_wall_time_now_ns(DO_NOT_RAISE_ON_FAILURE) - heap_iteration_prep_start_time_ns;

  // We'll release the Global VM Lock while we're calling serialize, so that the Ruby VM can continue to work while this
  // is pending
  call_serialize_without_gvl_arguments args = {
    .state = state,
    .finish_timestamp = finish_timestamp,
    .serialize_ran = false,
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

  // NOTE: We are focusing on the serialization time outside of the GVL in this stat here. This doesn't
  //       really cover the full serialization process but it gives a more useful number since it bypasses
  //       the noise of acquiring GVLs and dealing with interruptions which is highly specific to runtime
  //       conditions and over which we really have no control about.
  state->stats_lifetime.serialization_time_ns_max = long_max_of(state->stats_lifetime.serialization_time_ns_max, args.serialize_no_gvl_time_ns);
  state->stats_lifetime.serialization_time_ns_min = long_min_of(state->stats_lifetime.serialization_time_ns_min, args.serialize_no_gvl_time_ns);
  state->stats_lifetime.serialization_time_ns_total += args.serialize_no_gvl_time_ns;

  ddog_prof_Profile_SerializeResult serialized_profile = args.result;

  if (serialized_profile.tag == DDOG_PROF_PROFILE_SERIALIZE_RESULT_ERR) {
    state->stats_lifetime.serialization_failures++;
    return rb_ary_new_from_args(2, error_symbol, get_error_details_and_drop(&serialized_profile.err));
  }

  // Note: If we got here, the profile serialized correctly.
  // Once we wrap this into a Ruby object, our `EncodedProfile` class will automatically manage memory for it and we
  // can raise exceptions without worrying about leaking the profile.
  state->stats_lifetime.serialization_successes++;

  // Rotate the ProfilesDictionary every N exports — for testing only, not for production.
  if (state->dictionary_rotation_period > 0 &&
      state->stats_lifetime.serialization_successes % state->dictionary_rotation_period == 0) {
    rotate_profiles_dictionary(state);
  }

  VALUE encoded_profile = from_ddog_prof_EncodedProfile(serialized_profile.ok);

  VALUE start = ruby_time_from(args.slot->start_timestamp);
  VALUE finish = ruby_time_from(finish_timestamp);
  VALUE profile_stats = build_profile_stats(args.slot, args.serialize_no_gvl_time_ns, heap_iteration_prep_time_ns, args.heap_profile_build_time_ns);

  return rb_ary_new_from_args(2, ok_symbol, rb_ary_new_from_args(4, start, finish, encoded_profile, profile_stats));
}

static VALUE ruby_time_from(ddog_Timespec ddprof_time) {
  const int utc = INT_MAX - 1; // From Ruby sources
  struct timespec time = {.tv_sec = ddprof_time.seconds, .tv_nsec = ddprof_time.nanoseconds};
  return rb_time_timespec_new(&time, utc);
}

// Populate locations2 from the frame_info entries in stack_buffer, looking up or creating
// FunctionId2 handles in state->dict_handle via two caches:
//   state->iseq_cache      – st_table* keyed by iseq VALUE (pointer comparison)
//   state->native_id_cache – st_table* keyed by Ruby method ID (integer)
// Native frames use file_name="" and line=0 (we don't have definition-site info from Ruby).
// Returns true on success, false if any ProfilesDictionary insertion fails.
// Must be called with the GVL held (record_sample already guarantees this).
static bool build_location2_from_iseqs(
    ddog_prof_Location2 *locations2,
    uint16_t count,
    const frame_info *stack_buffer,
    stack_recorder_state *state,
    bool truncated  // true when captured_frames == buffer->max_frames (stack was cut short)
) {
  // ddtrace_rb_profile_frames iterates OLDEST first: stack_buffer[0] = bottom of call stack
  // (oldest/deepest), stack_buffer[count-1] = top of call stack (newest, currently executing).
  // libdatadog uses newest-first: locations2[0] = top of stack (newest), locations2[count-1] = oldest.
  // We process stack_buffer from OLDEST (sb=0) to NEWEST (sb=count-1) and write to
  // locations2[count-1-sb].
  //
  // When truncated (captured_frames == max_frames), add_truncated_frames_placeholder sets
  // locations[0] (the newest slot) to a "Truncated Frames" placeholder representing missing
  // top-of-stack frames. We mirror that here and skip stack_buffer[count-1] (the newest captured
  // frame), whose slot locations2[0] is already occupied by the placeholder.

  if (truncated) {
    locations2[0] = (ddog_prof_Location2) {
      .mapping  = NULL,
      .function = state->truncated_frames_function_id,
      .address  = 0,
      .line     = 0,
    };
  }

  // When truncated, skip the newest frame -- its slot (locations2[0]) holds the placeholder.
  uint16_t frames_to_process = truncated ? count - 1 : count;

  for (uint16_t sb = 0; sb < frames_to_process; sb++) {
    uint16_t l2_idx = count - 1 - sb;
    ddog_prof_FunctionId2 function_id = NULL;

    if (stack_buffer[sb].is_ruby_frame) {
      VALUE iseq = stack_buffer[sb].as.ruby_frame.iseq;

      st_data_t cached_id;
      if (st_lookup(state->iseq_cache, (st_data_t) iseq, &cached_id)) {
        function_id = (ddog_prof_FunctionId2) cached_id;
      } else {
        // Cache miss: resolve name/filename and insert a new Function into the ProfilesDictionary.
        VALUE name_val     = ddtrace_iseq_base_label((const void *) iseq);
        VALUE filename_val = ddtrace_iseq_path((const void *) iseq);

        ddog_CharSlice name_slice     = NIL_P(name_val)     ? DDOG_CHARSLICE_C("") : char_slice_from_ruby_string(name_val);
        ddog_CharSlice filename_slice = NIL_P(filename_val) ? DDOG_CHARSLICE_C("") : char_slice_from_ruby_string(filename_val);

        ddog_prof_StringId2 name_sid = NULL, filename_sid = NULL;
        ddog_prof_Status s;

        s = ddog_prof_ProfilesDictionary_insert_str(&name_sid, state->dict_handle, name_slice, DDOG_PROF_UTF8_OPTION_ASSUME);
        if (s.err != NULL) { ddog_prof_Status_drop(&s); return false; }
        ddog_prof_Status_drop(&s);

        s = ddog_prof_ProfilesDictionary_insert_str(&filename_sid, state->dict_handle, filename_slice, DDOG_PROF_UTF8_OPTION_ASSUME);
        if (s.err != NULL) { ddog_prof_Status_drop(&s); return false; }
        ddog_prof_Status_drop(&s);

        ddog_prof_Function2 func = { .name = name_sid, .system_name = NULL, .file_name = filename_sid };
        s = ddog_prof_ProfilesDictionary_insert_function(&function_id, state->dict_handle, &func);
        if (s.err != NULL) { ddog_prof_Status_drop(&s); return false; }
        ddog_prof_Status_drop(&s);

        // st_insert is pure C (no Ruby allocation), safe inside NEWOBJ tracepoint hooks.
        st_insert(state->iseq_cache, (st_data_t) iseq, (st_data_t) function_id);
      }

      locations2[l2_idx] = (ddog_prof_Location2) {
        .mapping  = NULL,
        .function = function_id,
        .address  = 0,
        .line     = stack_buffer[sb].as.ruby_frame.line,
      };
    } else {
      ID method_id = stack_buffer[sb].as.native_frame.method_id;

      st_data_t cached_id;
      if (st_lookup(state->native_id_cache, (st_data_t) method_id, &cached_id)) {
        function_id = (ddog_prof_FunctionId2) cached_id;
      } else {
        // Cache miss: look up the method name and insert a Function with file_name="".
        // We don't have a definition-site location for native (C) frames.
        // rb_id2name returns a const char* (no Ruby allocation), safe inside NEWOBJ tracepoint hooks.
        const char *name_cstr = rb_id2name(method_id);
        ddog_CharSlice name_slice = name_cstr != NULL ? (ddog_CharSlice) { .ptr = name_cstr, .len = strlen(name_cstr) } : DDOG_CHARSLICE_C("");

        ddog_prof_StringId2 name_sid = NULL, filename_sid = NULL;
        ddog_prof_Status s;

        s = ddog_prof_ProfilesDictionary_insert_str(&name_sid, state->dict_handle, name_slice, DDOG_PROF_UTF8_OPTION_ASSUME);
        if (s.err != NULL) { ddog_prof_Status_drop(&s); return false; }
        ddog_prof_Status_drop(&s);

        s = ddog_prof_ProfilesDictionary_insert_str(&filename_sid, state->dict_handle, DDOG_CHARSLICE_C(""), DDOG_PROF_UTF8_OPTION_ASSUME);
        if (s.err != NULL) { ddog_prof_Status_drop(&s); return false; }
        ddog_prof_Status_drop(&s);

        ddog_prof_Function2 func = { .name = name_sid, .system_name = NULL, .file_name = filename_sid };
        s = ddog_prof_ProfilesDictionary_insert_function(&function_id, state->dict_handle, &func);
        if (s.err != NULL) { ddog_prof_Status_drop(&s); return false; }
        ddog_prof_Status_drop(&s);

        st_insert(state->native_id_cache, (st_data_t) method_id, (st_data_t) function_id);
      }

      locations2[l2_idx] = (ddog_prof_Location2) {
        .mapping  = NULL,
        .function = function_id,
        .address  = 0,
        .line     = 0,
      };
    }
  }
  return true;
}

void record_sample(VALUE recorder_instance, ddog_prof_Slice_Location locations, sample_values values, sample_labels labels, sampling_buffer *buffer) {
  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);

  locked_profile_slot active_slot = sampler_lock_active_profile(state);

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
  metric_values[position_for[ALLOC_SAMPLES_UNSCALED_VALUE_ID]] = values.alloc_samples_unscaled;
  metric_values[position_for[TIMELINE_VALUE_ID]]      = values.timeline_wall_time_ns;

  if (values.heap_sample) {
    // If we got an allocation sample end the heap allocation recording to commit the heap sample.
    // FIXME: Heap sampling currently has to be done in 2 parts because the construction of locations is happening
    //        very late in the allocation-sampling path (which is shared with the cpu sampling path). This can
    //        be fixed with some refactoring but for now this leads to a less impactful change.
    //
    // NOTE: The heap recorder is allowed to raise exceptions if something's wrong. But we also need to handle it
    // on this side to make sure we properly unlock the active slot mutex on our way out. Otherwise, this would
    // later lead to deadlocks (since the active slot mutex is not expected to be locked forever).
    //
    // NOTE: heap_sample is only set when sampling via trigger_sample_for_thread (the allocation tracepoint path),
    // which always provides a valid buffer. Callers that pass buffer=NULL (e.g. record_placeholder_stack for GC
    // frames) always have heap_sample=false, so this branch is never reached with a NULL buffer.
    if (buffer == NULL) rb_bug("[ddtrace] record_sample: heap_sample=true but buffer is NULL");

    if (state->heap_recorder != NULL) {
      if (buffer->locations2 == NULL) {
        buffer->locations2 = calloc(buffer->max_frames, sizeof(ddog_prof_Location2));
        if (buffer->locations2 == NULL) {
          sampler_unlock_active_profile(active_slot);
          rb_raise(rb_eNoMemError, "Failed to allocate locations2 for heap sample");
        }
      }

      uint16_t frame_count = (uint16_t) locations.len;
      // Detect stack truncation: add_truncated_frames_placeholder runs when captured_frames == max_frames,
      // replacing locations[0] with a synthetic "Truncated Frames" entry. We mirror that in locations2.
      bool truncated = (frame_count == buffer->max_frames);
      if (!build_location2_from_iseqs(buffer->locations2, frame_count, buffer->stack_buffer, state, truncated)) {
        // ProfilesDictionary insertion failed for this heap sample. Discard the in-progress
        // recording and skip this sample rather than stopping the entire profiler.
        heap_recorder_discard_active_recording(state->heap_recorder);
        sampler_unlock_active_profile(active_slot);
        return;
      }

      int exception_state = end_heap_allocation_recording_with_rb_protect(
        state->heap_recorder,
        (ddog_prof_Slice_Location2) {.ptr = buffer->locations2, .len = frame_count}
      );
      if (exception_state) {
        sampler_unlock_active_profile(active_slot);
        rb_jump_tag(exception_state);
      }
    }
  }

  ddog_prof_Profile_Result result = ddog_prof_Profile_add(
    &active_slot.data->profile,
    (ddog_prof_Sample) {
      .locations = locations,
      .values = (ddog_Slice_I64) {.ptr = metric_values, .len = state->enabled_values_count},
      .labels = labels.labels
    },
    labels.end_timestamp_ns
  );

  active_slot.data->stats.recorded_samples++;

  sampler_unlock_active_profile(active_slot);

  if (result.tag == DDOG_PROF_PROFILE_RESULT_ERR) {
    raise_error(rb_eArgError, "Failed to record sample: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }
}

// Returns needs_after_allocation: true whenever an after_sample callback is required
bool track_object(VALUE recorder_instance, VALUE new_object, unsigned int sample_weight, ddog_CharSlice alloc_class) {
  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);
  // FIXME: Heap sampling currently has to be done in 2 parts because the construction of locations is happening
  //        very late in the allocation-sampling path (which is shared with the cpu sampling path). This can
  //        be fixed with some refactoring but for now this leads to a less impactful change.
  return start_heap_allocation_recording(state->heap_recorder, new_object, sample_weight, alloc_class);
}

void discard_heap_sample(VALUE recorder_instance) {
  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);
  heap_recorder_discard_active_recording(state->heap_recorder);
}

void record_endpoint(VALUE recorder_instance, uint64_t local_root_span_id, ddog_CharSlice endpoint) {
  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);

  locked_profile_slot active_slot = sampler_lock_active_profile(state);

  ddog_prof_Profile_Result result = ddog_prof_Profile_set_endpoint(&active_slot.data->profile, local_root_span_id, endpoint);

  sampler_unlock_active_profile(active_slot);

  if (result.tag == DDOG_PROF_PROFILE_RESULT_ERR) {
    raise_error(rb_eArgError, "Failed to record endpoint: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }
}

void recorder_after_gc_step(VALUE recorder_instance) {
  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);

  if (state->heap_clean_after_gc_enabled) heap_recorder_update_young_objects(state->heap_recorder);
}

void recorder_after_sample(VALUE recorder_instance) {
  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);

  heap_recorder_finalize_pending_recordings(state->heap_recorder);
}

#define MAX_LEN_HEAP_ITERATION_ERROR_MSG 256

// Heap recorder iteration context allows us access to stack recorder state and profile being serialized
// during iteration of heap recorder live objects.
typedef struct heap_recorder_iteration_context {
  stack_recorder_state *state;
  profile_slot *slot;

  bool error;
  char error_msg[MAX_LEN_HEAP_ITERATION_ERROR_MSG];
} heap_recorder_iteration_context;

static bool add_heap_sample_to_active_profile_without_gvl(heap_recorder_iteration_data iteration_data, void *extra_arg) {
  heap_recorder_iteration_context *context = (heap_recorder_iteration_context*) extra_arg;

  live_object_data *object_data = &iteration_data.object_data;

  int64_t metric_values[ALL_VALUE_TYPES_COUNT] = {0};
  uint8_t *position_for = context->state->position_for;

  metric_values[position_for[HEAP_SAMPLES_VALUE_ID]] = object_data->weight;
  metric_values[position_for[HEAP_SIZE_VALUE_ID]] = object_data->size * object_data->weight;

  ddog_prof_Label2 labels[2];
  size_t label_offset = 0;

  if (object_data->class_name != NULL) {
    labels[label_offset++] = (ddog_prof_Label2) {
      .key = context->state->label_key_allocation_class,
      .str = (ddog_CharSlice){ .ptr = object_data->class_name, .len = object_data->class_len },
      .num = 0,
    };
  }
  labels[label_offset++] = (ddog_prof_Label2) {
    .key = context->state->label_key_gc_gen_age,
    .num = (int64_t) object_data->gen_age,
  };

  ddog_prof_Status result = ddog_prof_Profile_add2(
    &context->slot->profile,
    (ddog_prof_Sample2) {
      .locations = iteration_data.locations,
      .values = (ddog_Slice_I64) {.ptr = metric_values, .len = context->state->enabled_values_count},
      .labels = (ddog_prof_Slice_Label2) {.ptr = labels, .len = label_offset},
    },
    0
  );

  context->slot->stats.recorded_samples++;

  if (result.err != NULL) {
    snprintf(context->error_msg, MAX_LEN_HEAP_ITERATION_ERROR_MSG, "%s", result.err);
    ddog_prof_Status_drop(&result);
    context->error = true;
    // By returning false we cancel the iteration
    return false;
  }
  ddog_prof_Status_drop(&result);

  // Keep on iterating to next item!
  return true;
}

static void build_heap_profile_without_gvl(stack_recorder_state *state, profile_slot *slot) {
  heap_recorder_iteration_context iteration_context = {
    .state = state,
    .slot = slot,
    .error = false,
    .error_msg = {0},
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

static void rotate_profiles_dictionary(stack_recorder_state *state) {
  // Step 1: Create a new ProfilesDictionary.
  ddog_prof_ProfilesDictionaryHandle new_dict = {0};
  ddog_prof_Status s = ddog_prof_ProfilesDictionary_new(&new_dict);
  if (s.err != NULL) raise_status_error("rotate_profiles_dictionary: failed to create new dict", &s);

  // Step 2: Re-insert the well-known strings and functions that stack_recorder_state caches.
  // This mirrors the initialization code in _native_new.
  ddog_prof_StringId2 new_alloc_class_key = NULL, new_gc_gen_age_key = NULL;

  s = ddog_prof_ProfilesDictionary_insert_str(
      &new_alloc_class_key, new_dict,
      DDOG_CHARSLICE_C("allocation class"), DDOG_PROF_UTF8_OPTION_ASSUME);
  if (s.err != NULL) raise_status_error("rotate_profiles_dictionary: failed to insert allocation class key", &s);

  s = ddog_prof_ProfilesDictionary_insert_str(
      &new_gc_gen_age_key, new_dict,
      DDOG_CHARSLICE_C("gc gen age"), DDOG_PROF_UTF8_OPTION_ASSUME);
  if (s.err != NULL) raise_status_error("rotate_profiles_dictionary: failed to insert gc gen age key", &s);

  ddog_prof_FunctionId2 new_truncated_frames_function_id = NULL;
  {
    ddog_prof_StringId2 truncated_name_sid = NULL, empty_sid = NULL;

    s = ddog_prof_ProfilesDictionary_insert_str(&truncated_name_sid, new_dict, DDOG_CHARSLICE_C("Truncated Frames"), DDOG_PROF_UTF8_OPTION_ASSUME);
    if (s.err != NULL) raise_status_error("rotate_profiles_dictionary: failed to insert Truncated Frames", &s);

    s = ddog_prof_ProfilesDictionary_insert_str(&empty_sid, new_dict, DDOG_CHARSLICE_C(""), DDOG_PROF_UTF8_OPTION_ASSUME);
    if (s.err != NULL) raise_status_error("rotate_profiles_dictionary: failed to insert empty string", &s);

    ddog_prof_Function2 truncated_func = { .name = truncated_name_sid, .system_name = NULL, .file_name = empty_sid };
    s = ddog_prof_ProfilesDictionary_insert_function(&new_truncated_frames_function_id, new_dict, &truncated_func);
    if (s.err != NULL) raise_status_error("rotate_profiles_dictionary: failed to insert Truncated Frames function", &s);
  }

  // Step 3: Migrate all live heap_record frame function_ids to the new dict, then rebuild
  // the heap_records st_table (whose hash/cmp depends on function_id pointer values).
  // Must be called before we drop the old dict (old FunctionId2 pointers must still be live).
  heap_recorder_migrate_dictionary(state->heap_recorder, state->dict_handle, new_dict);

  // Step 4: Clear the iseq and native caches — their FunctionId2 values point into the old dict.
  st_free_table(state->iseq_cache);
  state->iseq_cache = st_init_numtable();
  st_free_table(state->native_id_cache);
  state->native_id_cache = st_init_numtable();

  // Step 5: Drop the old dict handle. The existing profile slots each hold their own refcount on
  // the old dict, so it stays alive until those profiles are naturally reset — no samples are lost.
  ddog_prof_ProfilesDictionary_drop(&state->dict_handle);

  // Step 6: Install the new dict and well-known IDs.
  state->dict_handle = new_dict;
  state->label_key_allocation_class = new_alloc_class_key;
  state->label_key_gc_gen_age = new_gc_gen_age_key;
  state->truncated_frames_function_id = new_truncated_frames_function_id;

  // Step 7: Reinitialize the inactive slot (just serialized and empty) with the new dict.
  // The active slot keeps the old dict via its own refcount and continues collecting samples;
  // it will be reinitialized on the next rotation after it is serialized.
  profile_slot *inactive = (state->active_slot == 1) ? &state->profile_slot_two : &state->profile_slot_one;
  ddog_prof_Profile_drop(&inactive->profile);

  ddog_prof_SampleType enabled_sample_types[ALL_VALUE_TYPES_COUNT];
  for (uint8_t i = 0; i < ALL_VALUE_TYPES_COUNT; i++) {
    if (state->position_for[i] < state->enabled_values_count) {
      enabled_sample_types[state->position_for[i]] = all_sample_types[i];
    }
  }
  ddog_prof_Slice_SampleType sample_types = {.ptr = enabled_sample_types, .len = state->enabled_values_count};
  s = ddog_prof_Profile_with_dictionary(&inactive->profile, &state->dict_handle, sample_types, NULL);
  if (s.err != NULL) raise_status_error("rotate_profiles_dictionary: failed to reinitialize inactive slot", &s);
  inactive->start_timestamp = system_epoch_now_timespec();
  inactive->stats = (stats_slot) {};
}

static void *call_serialize_without_gvl(void *call_args) {
  call_serialize_without_gvl_arguments *args = (call_serialize_without_gvl_arguments *) call_args;

  long serialize_no_gvl_start_time_ns = monotonic_wall_time_now_ns(DO_NOT_RAISE_ON_FAILURE);

  profile_slot *slot_now_inactive = serializer_flip_active_and_inactive_slots(args->state);
  args->slot = slot_now_inactive;

  // Now that we have the inactive profile with all but heap samples, lets fill it with heap data
  // without needing to race with the active sampler
  build_heap_profile_without_gvl(args->state, args->slot);
  args->heap_profile_build_time_ns = monotonic_wall_time_now_ns(DO_NOT_RAISE_ON_FAILURE) - serialize_no_gvl_start_time_ns;

  // Note: The profile gets reset by the serialize call
  args->result = ddog_prof_Profile_serialize(&args->slot->profile, &args->slot->start_timestamp, &args->finish_timestamp);
  args->serialize_ran = true;
  args->serialize_no_gvl_time_ns = long_max_of(0, monotonic_wall_time_now_ns(DO_NOT_RAISE_ON_FAILURE) - serialize_no_gvl_start_time_ns);

  return NULL; // Unused
}

VALUE enforce_recorder_instance(VALUE object) {
  ENFORCE_TYPED_DATA(object, &stack_recorder_typed_data);
  return object;
}

static locked_profile_slot sampler_lock_active_profile(stack_recorder_state *state) {
  int error;

  for (int attempts = 0; attempts < 2; attempts++) {
    error = pthread_mutex_trylock(&state->mutex_slot_one);
    if (error && error != EBUSY) ENFORCE_SUCCESS_GVL(error);

    // Slot one is active
    if (!error) return (locked_profile_slot) {.mutex = &state->mutex_slot_one, .data = &state->profile_slot_one};

    // If we got here, slot one was not active, let's try slot two

    error = pthread_mutex_trylock(&state->mutex_slot_two);
    if (error && error != EBUSY) ENFORCE_SUCCESS_GVL(error);

    // Slot two is active
    if (!error) return (locked_profile_slot) {.mutex = &state->mutex_slot_two, .data = &state->profile_slot_two};
  }

  // We already tried both multiple times, and we did not succeed. This is not expected to happen. Let's stop sampling.
  raise_error(rb_eRuntimeError, "Failed to grab either mutex in sampler_lock_active_profile");
}

static void sampler_unlock_active_profile(locked_profile_slot active_slot) {
  ENFORCE_SUCCESS_GVL(pthread_mutex_unlock(active_slot.mutex));
}

static profile_slot* serializer_flip_active_and_inactive_slots(stack_recorder_state *state) {
  int previously_active_slot = state->active_slot;

  if (previously_active_slot != 1 && previously_active_slot != 2) {
    grab_gvl_and_raise(rb_eRuntimeError, "Unexpected active_slot state %d in serializer_flip_active_and_inactive_slots", previously_active_slot);
  }

  pthread_mutex_t *previously_active = (previously_active_slot == 1) ? &state->mutex_slot_one : &state->mutex_slot_two;
  pthread_mutex_t *previously_inactive = (previously_active_slot == 1) ? &state->mutex_slot_two : &state->mutex_slot_one;

  // Release the lock, thus making this slot active
  ENFORCE_SUCCESS_NO_GVL(pthread_mutex_unlock(previously_inactive));

  // Grab the lock, thus making this slot inactive
  ENFORCE_SUCCESS_NO_GVL(pthread_mutex_lock(previously_active));

  // Update active_slot
  state->active_slot = (previously_active_slot == 1) ? 2 : 1;

  // Return pointer to previously active slot (now inactive)
  return (previously_active_slot == 1) ? &state->profile_slot_one : &state->profile_slot_two;
}

// This method exists only to enable testing Datadog::Profiling::StackRecorder behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_active_slot(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) {
  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);

  return INT2NUM(state->active_slot);
}

// This method exists only to enable testing Datadog::Profiling::StackRecorder behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_is_slot_one_mutex_locked(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) { return test_slot_mutex_state(recorder_instance, 1); }

// This method exists only to enable testing Datadog::Profiling::StackRecorder behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_is_slot_two_mutex_locked(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) { return test_slot_mutex_state(recorder_instance, 2); }

static VALUE test_slot_mutex_state(VALUE recorder_instance, int slot) {
  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);

  pthread_mutex_t *slot_mutex = (slot == 1) ? &state->mutex_slot_one : &state->mutex_slot_two;

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
    raise_error(rb_eRuntimeError, "Failed to raise exception in test_slot_mutex_state; this should never happen");
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
  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);

  // In case the fork happened halfway through `serializer_flip_active_and_inactive_slots` execution and the
  // resulting state is inconsistent, we make sure to reset it back to the initial state.
  initialize_slot_concurrency_control(state);
  ddog_Timespec start_timestamp = system_epoch_now_timespec();
  reset_profile_slot(&state->profile_slot_one, start_timestamp);
  reset_profile_slot(&state->profile_slot_two, start_timestamp);

  heap_recorder_after_fork(state->heap_recorder);

  return Qtrue;
}

// Assumption 1: This method is called with the GVL being held, because `ddog_prof_Profile_reset` mutates the profile and must
// not be interrupted part-way through by a VM fork.
static void serializer_set_start_timestamp_for_next_profile(stack_recorder_state *state, ddog_Timespec start_time) {
  // Before making this profile active, we reset it so that it uses the correct start_time for its start
  profile_slot *next_profile_slot = (state->active_slot == 1) ? &state->profile_slot_two : &state->profile_slot_one;
  reset_profile_slot(next_profile_slot, start_time);
}

static VALUE _native_record_endpoint(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance, VALUE local_root_span_id, VALUE endpoint) {
  ENFORCE_TYPE(local_root_span_id, T_FIXNUM);
  record_endpoint(recorder_instance, NUM2ULL(local_root_span_id), char_slice_from_ruby_string(endpoint));
  return Qtrue;
}

static VALUE _native_track_object(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance, VALUE new_obj, VALUE weight, VALUE alloc_class) {
  ENFORCE_TYPE(weight, T_FIXNUM);
  bool needs_after_allocation = track_object(recorder_instance, new_obj, NUM2UINT(weight), char_slice_from_ruby_string(alloc_class));

  // We could instead choose to automatically trigger the after allocation here; yet, it seems kinda nice to keep it manual for
  // the tests so we can pull on each lever separately and observe "the sausage being made" in steps
  return needs_after_allocation ? Qtrue : Qfalse;
}

static void reset_profile_slot(profile_slot *slot, ddog_Timespec start_timestamp) {
  ddog_prof_Profile_Result reset_result = ddog_prof_Profile_reset(&slot->profile);
  if (reset_result.tag == DDOG_PROF_PROFILE_RESULT_ERR) {
    raise_error(rb_eRuntimeError, "Failed to reset profile: %"PRIsVALUE, get_error_details_and_drop(&reset_result.err));
  }
  slot->start_timestamp = start_timestamp;
  slot->stats = (stats_slot) {};
}

// This method exists only to enable testing Datadog::Profiling::StackRecorder behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_start_fake_slow_heap_serialization(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) {
  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);

  heap_recorder_prepare_iteration(state->heap_recorder);

  return Qnil;
}

// This method exists only to enable testing Datadog::Profiling::StackRecorder behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_end_fake_slow_heap_serialization(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) {
  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);

  heap_recorder_finish_iteration(state->heap_recorder);

  return Qnil;
}

// This method exists only to enable testing Datadog::Profiling::StackRecorder behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_debug_heap_recorder(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) {
  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);

  return heap_recorder_testonly_debug(state->heap_recorder);
}

static VALUE _native_stats(DDTRACE_UNUSED VALUE self, VALUE recorder_instance) {
  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);

  uint64_t total_serializations = state->stats_lifetime.serialization_successes + state->stats_lifetime.serialization_failures;

  VALUE heap_recorder_snapshot = state->heap_recorder ?
    heap_recorder_state_snapshot(state->heap_recorder) : Qnil;

  VALUE stats_as_hash = rb_hash_new();
  VALUE arguments[] = {
    ID2SYM(rb_intern("serialization_successes")), /* => */ ULL2NUM(state->stats_lifetime.serialization_successes),
    ID2SYM(rb_intern("serialization_failures")),  /* => */ ULL2NUM(state->stats_lifetime.serialization_failures),

    ID2SYM(rb_intern("serialization_time_ns_min")),   /* => */ RUBY_NUM_OR_NIL(state->stats_lifetime.serialization_time_ns_min, != INT64_MAX, LONG2NUM),
    ID2SYM(rb_intern("serialization_time_ns_max")),   /* => */ RUBY_NUM_OR_NIL(state->stats_lifetime.serialization_time_ns_max, > 0, LONG2NUM),
    ID2SYM(rb_intern("serialization_time_ns_total")), /* => */ RUBY_NUM_OR_NIL(state->stats_lifetime.serialization_time_ns_total, > 0, LONG2NUM),
    ID2SYM(rb_intern("serialization_time_ns_avg")),   /* => */ RUBY_AVG_OR_NIL(state->stats_lifetime.serialization_time_ns_total, total_serializations),

    ID2SYM(rb_intern("heap_recorder_snapshot")), /* => */ heap_recorder_snapshot,
  };
  for (long unsigned int i = 0; i < VALUE_COUNT(arguments); i += 2) rb_hash_aset(stats_as_hash, arguments[i], arguments[i+1]);
  return stats_as_hash;
}

static VALUE build_profile_stats(profile_slot *slot, long serialization_time_ns, long heap_iteration_prep_time_ns, long heap_profile_build_time_ns) {
  VALUE stats_as_hash = rb_hash_new();
  VALUE arguments[] = {
    ID2SYM(rb_intern("recorded_samples")), /* => */ ULL2NUM(slot->stats.recorded_samples),
    ID2SYM(rb_intern("serialization_time_ns")), /* => */ LONG2NUM(serialization_time_ns),
    ID2SYM(rb_intern("heap_iteration_prep_time_ns")), /* => */ LONG2NUM(heap_iteration_prep_time_ns),
    ID2SYM(rb_intern("heap_profile_build_time_ns")), /* => */ LONG2NUM(heap_profile_build_time_ns),
  };
  for (long unsigned int i = 0; i < VALUE_COUNT(arguments); i += 2) rb_hash_aset(stats_as_hash, arguments[i], arguments[i+1]);
  return stats_as_hash;
}

static VALUE _native_is_object_recorded(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance, VALUE obj_id) {
  ENFORCE_TYPE(obj_id, T_FIXNUM);

  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);

  return heap_recorder_testonly_is_object_recorded(state->heap_recorder, obj_id);
}

static VALUE _native_heap_recorder_reset_last_update(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) {
  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);

  heap_recorder_testonly_reset_last_update(state->heap_recorder);

  return Qtrue;
}

static VALUE _native_recorder_after_gc_step(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) {
  recorder_after_gc_step(recorder_instance);
  return Qtrue;
}

static VALUE _native_benchmark_intern(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance, VALUE string, VALUE times, VALUE use_all) {
  ENFORCE_TYPE(string, T_STRING);
  ENFORCE_TYPE(times, T_FIXNUM);
  ENFORCE_BOOLEAN(use_all);

  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);

  heap_recorder_testonly_benchmark_intern(state->heap_recorder, char_slice_from_ruby_string(string), FIX2INT(times), use_all == Qtrue);

  return Qtrue;
}


static VALUE _native_finalize_pending_heap_recordings(DDTRACE_UNUSED VALUE _self, VALUE recorder_instance) {
  stack_recorder_state *state;
  TypedData_Get_Struct(recorder_instance, stack_recorder_state, &stack_recorder_typed_data, state);

  heap_recorder_finalize_pending_recordings(state->heap_recorder);

  return Qtrue;
}

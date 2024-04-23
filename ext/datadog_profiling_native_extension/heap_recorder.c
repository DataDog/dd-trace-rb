#include "heap_recorder.h"
#include <pthread.h>
#include "ruby/st.h"
#include "ruby_helpers.h"
#include <errno.h>
#include "collectors_stack.h"
#include "libdatadog_helpers.h"

#if (defined(HAVE_WORKING_RB_GC_FORCE_RECYCLE) && ! defined(NO_SEEN_OBJ_ID_FLAG))
  #define CAN_APPLY_GC_FORCE_RECYCLE_BUG_WORKAROUND
#endif

// Minimum age (in GC generations) of heap objects we want to include in heap
// recorder iterations. Object with age 0 represent objects that have yet to undergo
// a GC and, thus, may just be noise/trash at instant of iteration and are usually not
// relevant for heap profiles as the great majority should be trivially reclaimed
// during the next GC.
#define ITERATION_MIN_AGE 1

// A compact representation of a stacktrace frame for a heap allocation.
typedef struct {
  u_int32_t name;
  u_int32_t filename;
  int32_t line;
} heap_frame;
static st_index_t heap_frame_hash(heap_frame*, st_index_t seed);

// A compact representation of a stacktrace for a heap allocation.
//
// We could use a ddog_prof_Slice_Location instead but it has a lot of
// unused fields. Because we have to keep these stacks around for at
// least the lifetime of the objects allocated therein, we would be
// incurring a non-negligible memory overhead for little purpose.
typedef struct {
  uint16_t frames_len;
  heap_frame frames[];
} heap_stack;
static heap_stack* heap_stack_new(heap_recorder*, ddog_prof_Slice_Location);
static void heap_stack_free(heap_recorder*, heap_stack*);
static st_index_t heap_stack_hash(heap_stack*, st_index_t);

#if MAX_FRAMES_LIMIT > UINT16_MAX
  #error Frames len type not compatible with MAX_FRAMES_LIMIT
#endif

static int heap_stack_cmp_st(st_data_t, st_data_t);
static st_index_t heap_stack_hash_st(st_data_t);
static const struct st_hash_type st_hash_type_heap_stack = {
    heap_stack_cmp_st,
    heap_stack_hash_st,
};

// A heap record is used for deduping heap allocation stacktraces across multiple
// objects sharing the same allocation location.
typedef struct {
  // How many objects are currently tracked by the heap recorder for this heap record.
  uint32_t num_tracked_objects;
  // stack is owned by the associated record and gets cleaned up alongside it
  heap_stack *stack;
} heap_record;
static heap_record* heap_record_new(heap_stack*);
static void heap_record_free(heap_recorder*, heap_record*);

// An object record is used for storing data about currently tracked live objects
typedef struct {
  long obj_id;
  heap_record *heap_record;
  live_object_data object_data;
} object_record;
static object_record* object_record_new(long, heap_record*, live_object_data);
static void object_record_free(heap_recorder*, object_record*);
static VALUE object_record_inspect(heap_recorder*, object_record*);
static object_record SKIPPED_RECORD = {0};

// A wrapper around an object record that is in the process of being recorded and was not
// yet committed.
typedef struct {
  // Pointer to the (potentially partial) object_record containing metadata about an ongoing recording.
  // When NULL, this symbolizes an unstarted/invalid recording.
  object_record *object_record;
  // A flag to track whether we had to force set the RUBY_FL_SEEN_OBJ_ID flag on this object
  // as part of our workaround around rb_gc_force_recycle issues.
  bool did_recycle_workaround;
} recording;

struct heap_recorder {
  // Config
  // Whether the recorder should try to determine approximate sizes for tracked objects.
  bool size_enabled;
  uint sample_rate;

  // Map[key: heap_stack*, record: heap_record*]
  // NOTE: This table is currently only protected by the GVL since we never interact with it
  // outside the GVL.
  // NOTE: This table has ownership of both its heap_stacks and heap_records.
  st_table *heap_records;

  // Map[obj_id: long, record: object_record*]
  // NOTE: This table is currently only protected by the GVL since we never interact with it
  // outside the GVL.
  // NOTE: This table has ownership of its object_records. The keys are longs and so are
  // passed as values.
  st_table *object_records;

  // Map[obj_id: long, record: object_record*]
  // NOTE: This is a snapshot of object_records built ahead of a iteration. Outside of an
  // iteration context, this table will be NULL. During an iteration, there will be no
  // mutation of the data so iteration can occur without acquiring a lock.
  // NOTE: Contrary to object_records, this table has no ownership of its data.
  st_table *object_records_snapshot;
  // The GC gen/epoch/count in which we prepared the current iteration.
  //
  // This enables us to calculate the age of iterated objects in the above snapshot by
  // comparing it against an object's alloc_gen.
  size_t iteration_gen;

  // Data for a heap recording that was started but not yet ended
  recording active_recording;

  // Reusable location array, implementing a flyweight pattern for things like iteration.
  ddog_prof_Location *reusable_locations;

  // Sampling state
  uint num_recordings_skipped;

  struct stats_last_update {
    size_t objects_alive;
    size_t objects_dead;
    size_t objects_skipped;
    size_t objects_frozen;
  } stats_last_update;

  // String storage
  const ddog_prof_ManagedStringStorage *string_storage;
};

struct end_heap_allocation_args {
  struct heap_recorder *heap_recorder;
  ddog_prof_Slice_Location locations;
};

static heap_record* get_or_create_heap_record(heap_recorder*, ddog_prof_Slice_Location);
static void cleanup_heap_record_if_unused(heap_recorder*, heap_record*);
static void on_committed_object_record_cleanup(heap_recorder *heap_recorder, object_record *record);
static int st_heap_record_entry_free(st_data_t, st_data_t, st_data_t);
static int st_object_record_entry_free(st_data_t, st_data_t, st_data_t);
static int st_object_record_update(st_data_t, st_data_t, st_data_t);
static int st_object_records_iterate(st_data_t, st_data_t, st_data_t);
static int st_object_records_debug(st_data_t key, st_data_t value, st_data_t extra);
static int update_object_record_entry(st_data_t*, st_data_t*, st_data_t, int);
static void commit_recording(heap_recorder*, heap_record*, recording);
static VALUE end_heap_allocation_recording(VALUE end_heap_allocation_args);
static u_int32_t intern_or_raise(heap_recorder*, const ddog_CharSlice*);
static void unintern_or_raise(heap_recorder *, u_int32_t);
static VALUE get_ruby_string_or_raise(heap_recorder*, u_int32_t);

// ==========================
// Heap Recorder External API
//
// WARN: All these APIs should support receiving a NULL heap_recorder, resulting in a noop.
//
// WARN: Except for ::heap_recorder_for_each_live_object, we always assume interaction with these APIs
// happens under the GVL.
//
// ==========================
heap_recorder* heap_recorder_new(const ddog_prof_ManagedStringStorage *string_storage) {
  heap_recorder *recorder = ruby_xcalloc(1, sizeof(heap_recorder));

  recorder->heap_records = st_init_table(&st_hash_type_heap_stack);
  recorder->object_records = st_init_numtable();
  recorder->object_records_snapshot = NULL;
  recorder->reusable_locations = ruby_xcalloc(MAX_FRAMES_LIMIT, sizeof(ddog_prof_Location));
  recorder->active_recording = (recording) {0};
  recorder->size_enabled = true;
  recorder->sample_rate = 1; // By default do no sampling on top of what allocation profiling already does
  recorder->string_storage = string_storage;

  return recorder;
}

void heap_recorder_free(heap_recorder *heap_recorder) {
  if (heap_recorder == NULL) {
    return;
  }

  if (heap_recorder->object_records_snapshot != NULL) {
    // if there's an unfinished iteration, clean it up now
    // before we clean up any other state it might depend on
    heap_recorder_finish_iteration(heap_recorder);
  }

  // Clean-up all object records
  st_foreach(heap_recorder->object_records, st_object_record_entry_free, (st_data_t) heap_recorder);
  st_free_table(heap_recorder->object_records);

  // Clean-up all heap records (this includes those only referred to by queued_samples)
  st_foreach(heap_recorder->heap_records, st_heap_record_entry_free, (st_data_t) heap_recorder);
  st_free_table(heap_recorder->heap_records);

  if (heap_recorder->active_recording.object_record != NULL && heap_recorder->active_recording.object_record != &SKIPPED_RECORD) {
    // If there's a partial object record, clean it up as well
    object_record_free(heap_recorder, heap_recorder->active_recording.object_record);
  }

  ruby_xfree(heap_recorder->reusable_locations);

  ruby_xfree(heap_recorder);
}

void heap_recorder_set_size_enabled(heap_recorder *heap_recorder, bool size_enabled) {
  if (heap_recorder == NULL) {
    return;
  }

  heap_recorder->size_enabled = size_enabled;
}

void heap_recorder_set_sample_rate(heap_recorder *heap_recorder, int sample_rate) {
  if (heap_recorder == NULL) {
    return;
  }

  if (sample_rate <= 0) {
    rb_raise(rb_eArgError, "Heap sample rate must be a positive integer value but was %d", sample_rate);
  }

  heap_recorder->sample_rate = sample_rate;
  heap_recorder->num_recordings_skipped = 0;
}

// WARN: Assumes this gets called before profiler is reinitialized on the fork
void heap_recorder_after_fork(heap_recorder *heap_recorder) {
  if (heap_recorder == NULL) {
    return;
  }

  // When forking, the child process gets a copy of the entire state of the parent process, minus
  // threads.
  //
  // This means anything the heap recorder is tracking will still be alive after the fork and
  // should thus be kept. Because this heap recorder implementation does not rely on free
  // tracepoints to track liveness, any frees that happen until we fully reinitialize, will
  // simply be noticed on next heap_recorder_prepare_iteration.
  //
  // There is one small caveat though: fork only preserves one thread and in a Ruby app, that
  // will be the thread holding on to the GVL. Since we support iteration on the heap recorder
  // outside of the GVL, any state specific to that interaction may be incosistent after fork
  // (e.g. an acquired lock for thread safety). Iteration operates on object_records_snapshot
  // though and that one will be updated on next heap_recorder_prepare_iteration so we really
  // only need to finish any iteration that might have been left unfinished.
  if (heap_recorder->object_records_snapshot != NULL) {
    heap_recorder_finish_iteration(heap_recorder);
  }
}

void start_heap_allocation_recording(heap_recorder *heap_recorder, VALUE new_obj, unsigned int weight, ddog_CharSlice *alloc_class) {
  if (heap_recorder == NULL) {
    return;
  }

  if (heap_recorder->active_recording.object_record != NULL) {
    rb_raise(rb_eRuntimeError, "Detected consecutive heap allocation recording starts without end.");
  }

  if (heap_recorder->num_recordings_skipped + 1 < heap_recorder->sample_rate) {
    heap_recorder->active_recording.object_record = &SKIPPED_RECORD;
    heap_recorder->num_recordings_skipped++;
    return;
  }

  heap_recorder->num_recordings_skipped = 0;

  VALUE ruby_obj_id = rb_obj_id(new_obj);
  if (!FIXNUM_P(ruby_obj_id)) {
    rb_raise(rb_eRuntimeError, "Detected a bignum object id. These are not supported by heap profiling.");
  }

  bool did_recycle_workaround = false;

  #ifdef CAN_APPLY_GC_FORCE_RECYCLE_BUG_WORKAROUND
    // If we are in a ruby version that has a working rb_gc_force_recycle implementation,
    // its usage may lead to an object being re-used outside of the typical GC cycle.
    //
    // This re-use is in theory invisible to us unless we're lucky enough to sample both
    // the original object and the replacement that uses the recycled slot.
    //
    // In practice, we've observed (https://github.com/DataDog/dd-trace-rb/pull/3366)
    // that non-noop implementations of rb_gc_force_recycle have an implementation bug
    // which results in the object that re-used the recycled slot inheriting the same
    // object id without setting the FL_SEEN_OBJ_ID flag. We rely on this knowledge to
    // "observe" implicit frees when an object we are tracking is force-recycled.
    //
    // However, it may happen that we start tracking a new object and that object was
    // allocated on a recycled slot. Due to the bug, this object would be missing the
    // FL_SEEN_OBJ_ID flag even though it was not recycled itself. If we left it be,
    // when we're doing our liveness check, the absence of the flag would trigger our
    // implicit free workaround and the object would be inferred as recycled even though
    // it might still be alive.
    //
    // Thus, if we detect that this new allocation is already missing the flag at the start
    // of the heap allocation recording, we force-set it. This should be safe since we
    // just called rb_obj_id on it above and the expectation is that any flaggable object
    // that goes through it ends up with the flag set (as evidenced by the GC_ASSERT
    // lines in https://github.com/ruby/ruby/blob/4a8d7246d15b2054eacb20f8ab3d29d39a3e7856/gc.c#L4050C14-L4050C14).
    if (RB_FL_ABLE(new_obj) && !RB_FL_TEST(new_obj, RUBY_FL_SEEN_OBJ_ID)) {
      RB_FL_SET(new_obj, RUBY_FL_SEEN_OBJ_ID);
      did_recycle_workaround = true;
    }
  #endif

  uint32_t alloc_class_id = intern_or_raise(heap_recorder, alloc_class);

  heap_recorder->active_recording = (recording) {
    .object_record = object_record_new(FIX2LONG(ruby_obj_id), NULL, (live_object_data) {
        .weight =  weight * heap_recorder->sample_rate,
        .class = alloc_class_id,
        .alloc_gen = rb_gc_count(),
        }),
    .did_recycle_workaround = did_recycle_workaround,
  };
}

// end_heap_allocation_recording_with_rb_protect gets called while the stack_recorder is holding one of the profile
// locks. To enable us to correctly unlock the profile on exception, we wrap the call to end_heap_allocation_recording
// with an rb_protect.
__attribute__((warn_unused_result))
int end_heap_allocation_recording_with_rb_protect(struct heap_recorder *heap_recorder, ddog_prof_Slice_Location locations) {
  int exception_state;
  struct end_heap_allocation_args end_heap_allocation_args = {
    .heap_recorder = heap_recorder,
    .locations = locations,
  };
  rb_protect(end_heap_allocation_recording, (VALUE) &end_heap_allocation_args, &exception_state);
  return exception_state;
}

static VALUE end_heap_allocation_recording(VALUE end_heap_allocation_args) {
  struct end_heap_allocation_args *args = (struct end_heap_allocation_args *) end_heap_allocation_args;

  struct heap_recorder *heap_recorder = args->heap_recorder;
  ddog_prof_Slice_Location locations = args->locations;

  if (heap_recorder == NULL) {
    return Qnil;
  }

  recording active_recording = heap_recorder->active_recording;

  if (active_recording.object_record == NULL) {
    // Recording ended without having been started?
    rb_raise(rb_eRuntimeError, "Ended a heap recording that was not started");
  }
  // From now on, mark the global active recording as invalid so we can short-circuit at any point
  // and not end up with a still active recording. the local active_recording still holds the
  // data required for committing though.
  heap_recorder->active_recording = (recording) {0};

  if (active_recording.object_record == &SKIPPED_RECORD) { // special marker when we decided to skip due to sampling
    return Qnil;
  }

  heap_record *heap_record = get_or_create_heap_record(heap_recorder, locations);

  // And then commit the new allocation.
  commit_recording(heap_recorder, heap_record, active_recording);

  return Qnil;
}

void heap_recorder_prepare_iteration(heap_recorder *heap_recorder) {
  if (heap_recorder == NULL) {
    return;
  }

  heap_recorder->iteration_gen = rb_gc_count();

  if (heap_recorder->object_records_snapshot != NULL) {
    // we could trivially handle this but we raise to highlight and catch unexpected usages.
    rb_raise(rb_eRuntimeError, "New heap recorder iteration prepared without the previous one having been finished.");
  }

  // Reset last update stats, we'll be building them from scratch during the st_foreach call below
  heap_recorder->stats_last_update = (struct stats_last_update) {};

  st_foreach(heap_recorder->object_records, st_object_record_update, (st_data_t) heap_recorder);

  heap_recorder->object_records_snapshot = st_copy(heap_recorder->object_records);
  if (heap_recorder->object_records_snapshot == NULL) {
    rb_raise(rb_eRuntimeError, "Failed to create heap snapshot.");
  }
}

void heap_recorder_finish_iteration(heap_recorder *heap_recorder) {
  if (heap_recorder == NULL) {
    return;
  }

  if (heap_recorder->object_records_snapshot == NULL) {
    // we could trivially handle this but we raise to highlight and catch unexpected usages.
    rb_raise(rb_eRuntimeError, "Heap recorder iteration finished without having been prepared.");
  }

  st_free_table(heap_recorder->object_records_snapshot);
  heap_recorder->object_records_snapshot = NULL;
}

// Internal data we need while performing iteration over live objects.
typedef struct {
  // The callback we need to call for each object.
  bool (*for_each_callback)(heap_recorder_iteration_data stack_data, void *extra_arg);
  // The extra arg to pass as the second parameter to the callback.
  void *for_each_callback_extra_arg;
  // A reference to the heap recorder so we can access extra stuff like reusable_locations.
  heap_recorder *heap_recorder;
} iteration_context;

// WARN: Assume iterations can run without the GVL for performance reasons. Do not raise, allocate or
// do NoGVL-unsafe interactions with the Ruby runtime. Any such interactions should be done during
// heap_recorder_prepare_iteration or heap_recorder_finish_iteration.
bool heap_recorder_for_each_live_object(
    heap_recorder *heap_recorder,
    bool (*for_each_callback)(heap_recorder_iteration_data stack_data, void *extra_arg),
    void *for_each_callback_extra_arg) {
  if (heap_recorder == NULL) {
    return true;
  }

  if (heap_recorder->object_records_snapshot == NULL) {
    return false;
  }

  iteration_context context;
  context.for_each_callback = for_each_callback;
  context.for_each_callback_extra_arg = for_each_callback_extra_arg;
  context.heap_recorder = heap_recorder;
  st_foreach(heap_recorder->object_records_snapshot, st_object_records_iterate, (st_data_t) &context);
  return true;
}

VALUE heap_recorder_state_snapshot(heap_recorder *heap_recorder) {
  VALUE arguments[] = {
    ID2SYM(rb_intern("num_object_records")), /* => */ LONG2NUM(heap_recorder->object_records->num_entries),
    ID2SYM(rb_intern("num_heap_records")),   /* => */ LONG2NUM(heap_recorder->heap_records->num_entries),

    // Stats as of last update
    ID2SYM(rb_intern("last_update_objects_alive")), /* => */ LONG2NUM(heap_recorder->stats_last_update.objects_alive),
    ID2SYM(rb_intern("last_update_objects_dead")), /* => */ LONG2NUM(heap_recorder->stats_last_update.objects_dead),
    ID2SYM(rb_intern("last_update_objects_skipped")), /* => */ LONG2NUM(heap_recorder->stats_last_update.objects_skipped),
    ID2SYM(rb_intern("last_update_objects_frozen")), /* => */ LONG2NUM(heap_recorder->stats_last_update.objects_frozen),
  };
  VALUE hash = rb_hash_new();
  for (long unsigned int i = 0; i < VALUE_COUNT(arguments); i += 2) rb_hash_aset(hash, arguments[i], arguments[i+1]);
  return hash;
}

typedef struct debug_context {
  heap_recorder *recorder;
  VALUE debug_str;
} debug_context;

VALUE heap_recorder_testonly_debug(heap_recorder *heap_recorder) {
  if (heap_recorder == NULL) {
    return rb_str_new2("NULL heap_recorder");
  }

  VALUE debug_str = rb_str_new2("object records:\n");

  debug_context context = (debug_context) {
    .recorder = heap_recorder,
    .debug_str = debug_str,
  };

  st_foreach(heap_recorder->object_records, st_object_records_debug, (st_data_t) &context);
  return debug_str;
}

// ==========================
// Heap Recorder Internal API
// ==========================
static int st_heap_record_entry_free(DDTRACE_UNUSED st_data_t key, st_data_t value, st_data_t extra_arg) {
  heap_recorder *recorder = (heap_recorder *) extra_arg;
  heap_record_free(recorder, (heap_record *) value);
  return ST_DELETE;
}

static int st_object_record_entry_free(DDTRACE_UNUSED st_data_t key, st_data_t value, st_data_t extra_arg) {
  heap_recorder *recorder = (heap_recorder *) extra_arg;
  object_record_free(recorder, (object_record *) value);
  return ST_DELETE;
}

// Check to see if an object should not be included in a heap recorder iteration.
// This centralizes the checking logic to ensure it's equally applied between
// preparation and iteration codepaths.
static inline bool should_exclude_from_iteration(object_record *obj_record) {
  return obj_record->object_data.gen_age < ITERATION_MIN_AGE;
}

static int st_object_record_update(st_data_t key, st_data_t value, st_data_t extra_arg) {
  long obj_id = (long) key;
  object_record *record = (object_record*) value;
  heap_recorder *recorder = (heap_recorder*) extra_arg;

  VALUE ref;

  size_t iteration_gen = recorder->iteration_gen;
  size_t alloc_gen = record->object_data.alloc_gen;
  // Guard against potential overflows given unsigned types here.
  record->object_data.gen_age = alloc_gen < iteration_gen ? iteration_gen - alloc_gen : 0;

  if (should_exclude_from_iteration(record)) {
    // If an object won't be included in the current iteration, there's
    // no point checking for liveness or updating its size, so exit early.
    // NOTE: This means that there should be an equivalent check during actual
    //       iteration otherwise we'd iterate/expose stale object data.
    recorder->stats_last_update.objects_skipped++;
    return ST_CONTINUE;
  }

  if (!ruby_ref_from_id(LONG2NUM(obj_id), &ref)) {
    // Id no longer associated with a valid ref. Need to delete this object record!
    on_committed_object_record_cleanup(recorder, record);
    recorder->stats_last_update.objects_dead++;
    return ST_DELETE;
  }

  // If we got this far, then we found a valid live object for the tracked id.

  #ifdef CAN_APPLY_GC_FORCE_RECYCLE_BUG_WORKAROUND
    // If we are in a ruby version that has a working rb_gc_force_recycle implementation,
    // its usage may lead to an object being re-used outside of the typical GC cycle.
    //
    // This re-use is in theory invisible to us and would mean that the ref from which we
    // collected the object_record metadata may not be the same as the current ref and
    // thus any further reporting would be innacurately attributed to stale metadata.
    //
    // In practice, there is a way for us to notice that this happened because of a bug
    // in the implementation of rb_gc_force_recycle. Our heap profiler relies on object
    // ids and id2ref to detect whether objects are still alive. Turns out that when an
    // object with an id is re-used via rb_gc_force_recycle, it will "inherit" the ID
    // of the old object but it will NOT have the FL_SEEN_OBJ_ID as per the experiment
    // in https://github.com/DataDog/dd-trace-rb/pull/3360#discussion_r1442823517
    //
    // Thus, if we detect that the ref we just resolved above is missing this flag, we can
    // safely say re-use happened and thus treat it as an implicit free of the object
    // we were tracking (the original one which got recycled).
    if (RB_FL_ABLE(ref) && !RB_FL_TEST(ref, RUBY_FL_SEEN_OBJ_ID)) {

      // NOTE: We don't really need to set this flag for heap recorder to work correctly
      // but doing so partially mitigates a bug in runtimes with working rb_gc_force_recycle
      // which leads to broken invariants and leaking of entries in obj_to_id and id_to_obj
      // tables in objspace. We already do the same thing when we sample a recycled object,
      // here we apply it as well to objects that replace recycled objects that were being
      // tracked. More details in https://github.com/DataDog/dd-trace-rb/pull/3366
      RB_FL_SET(ref, RUBY_FL_SEEN_OBJ_ID);

      on_committed_object_record_cleanup(recorder, record);
      recorder->stats_last_update.objects_dead++;
      return ST_DELETE;
    }

  #endif

  if (recorder->size_enabled && !record->object_data.is_frozen) {
    // if we were asked to update sizes and this object was not already seen as being frozen,
    // update size again.
    record->object_data.size = ruby_obj_memsize_of(ref);
    // Check if it's now frozen so we skip a size update next time
    record->object_data.is_frozen = RB_OBJ_FROZEN(ref);
  }

  recorder->stats_last_update.objects_alive++;
  if (record->object_data.is_frozen) {
    recorder->stats_last_update.objects_frozen++;
  }

  return ST_CONTINUE;
}

// WARN: This can get called outside the GVL. NO HEAP ALLOCATIONS OR EXCEPTIONS ARE ALLOWED.
static int st_object_records_iterate(DDTRACE_UNUSED st_data_t key, st_data_t value, st_data_t extra) {
  object_record *record = (object_record*) value;
  const heap_stack *stack = record->heap_record->stack;
  iteration_context *context = (iteration_context*) extra;

  const heap_recorder *recorder = context->heap_recorder;

  if (should_exclude_from_iteration(record)) {
    // Skip objects that should not be included in iteration
    // NOTE: This matches the short-circuiting condition in st_object_record_update
    //       and prevents iteration over stale objects.
    return ST_CONTINUE;
  }

  ddog_prof_Location *locations = recorder->reusable_locations;
  for (uint16_t i = 0; i < stack->frames_len; i++) {
    const heap_frame *frame = &stack->frames[i];
    locations[i] = (ddog_prof_Location) {
      .mapping = {.filename = DDOG_CHARSLICE_C(""), .build_id = DDOG_CHARSLICE_C("")},
      .function = {
        .name = DDOG_CHARSLICE_C(""),
        .name_id = frame->name,
        .filename = DDOG_CHARSLICE_C(""),
        .filename_id = frame->filename,
      },
      .line = frame->line,
    };
  }

  heap_recorder_iteration_data iteration_data;
  iteration_data.object_data = record->object_data;
  iteration_data.locations = (ddog_prof_Slice_Location) {.ptr = locations, .len = stack->frames_len};

  if (!context->for_each_callback(iteration_data, context->for_each_callback_extra_arg)) {
    return ST_STOP;
  }

  return ST_CONTINUE;
}

static int st_object_records_debug(DDTRACE_UNUSED st_data_t key, st_data_t value, st_data_t extra) {
  debug_context *context = (debug_context*) extra;
  VALUE debug_str = context->debug_str;

  object_record *record = (object_record*) value;

  rb_str_catf(debug_str, "%"PRIsVALUE"\n", object_record_inspect(context->recorder, record));

  return ST_CONTINUE;
}

// Struct holding data required for an update operation on heap_records
typedef struct {
  // [in] The recording containing the new object record we want to add.
  // NOTE: Transfer of ownership of the contained object record is assumed, do not re-use it after call to ::update_object_record_entry
  recording recording;

  // [in] The heap recorder where the update is happening.
  heap_recorder *heap_recorder;
} object_record_update_data;

static int update_object_record_entry(DDTRACE_UNUSED st_data_t *key, st_data_t *value, st_data_t data, int existing) {
  object_record_update_data *update_data = (object_record_update_data*) data;
  recording recording = update_data->recording;
  object_record *new_object_record = recording.object_record;
  if (existing) {
    object_record *existing_record = (object_record*) (*value);
    if (recording.did_recycle_workaround) {
      // In this case, it's possible for an object id to be re-used and we were lucky enough to have
      // sampled both the original object and the replacement so cleanup the old one and replace it with
      // the new object_record (i.e. treat this as a combined free+allocation).
      on_committed_object_record_cleanup(update_data->heap_recorder, existing_record);
    } else {
      // This is not supposed to happen, raising...
      VALUE existing_inspect = object_record_inspect(update_data->heap_recorder, existing_record);
      VALUE new_inspect = object_record_inspect(update_data->heap_recorder, new_object_record);
      rb_raise(rb_eRuntimeError, "Object ids are supposed to be unique. We got 2 allocation recordings with "
        "the same id. previous=%"PRIsVALUE" new=%"PRIsVALUE, existing_inspect, new_inspect);
    }
  }
  // Always carry on with the update, we want the new record to be there at the end
  (*value) = (st_data_t) new_object_record;
  return ST_CONTINUE;
}

static void commit_recording(heap_recorder *heap_recorder, heap_record *heap_record, recording recording) {
  // Link the object record with the corresponding heap record. This was the last remaining thing we
  // needed to fully build the object_record.
  recording.object_record->heap_record = heap_record;
  if (heap_record->num_tracked_objects == UINT32_MAX) {
    rb_raise(rb_eRuntimeError, "Reached maximum number of tracked objects for heap record");
  }
  heap_record->num_tracked_objects++;

  // Update object_records with the data for this new recording
  object_record_update_data update_data = (object_record_update_data) {
    .heap_recorder = heap_recorder,
    .recording = recording,
  };
  st_update(heap_recorder->object_records, recording.object_record->obj_id, update_object_record_entry, (st_data_t) &update_data);
}

// Struct holding data required for an update operation on heap_records
typedef struct {
  // [in] The locations we did this update with
  heap_recorder *recorder;
  ddog_prof_Slice_Location locations;
  // [out] Pointer that will be updated to the updated heap record to prevent having to do
  // another lookup to access the updated heap record.
  heap_record **record;
} heap_record_update_data;

// This function assumes ownership of stack_data is passed on to it so it'll either transfer ownership or clean-up.
static int update_heap_record_entry_with_new_allocation(st_data_t *key, st_data_t *value, st_data_t data, int existing) {
  heap_record_update_data *update_data = (heap_record_update_data*) data;

  if (!existing) {
    // there was no matching heap record so lets create a new one...
    heap_stack *stack = (heap_stack*) *key;
    (*value) = (st_data_t) heap_record_new(stack);
  }

  heap_record *record = (heap_record*) (*value);
  (*update_data->record) = record;

  return ST_CONTINUE;
}

static heap_record* get_or_create_heap_record(heap_recorder *heap_recorder, ddog_prof_Slice_Location locations) {

  heap_stack *stack = heap_stack_new(heap_recorder, locations);

  heap_record *heap_record = NULL;
  heap_record_update_data update_data = (heap_record_update_data) {
    .recorder = heap_recorder,
    .record = &heap_record,
  };
  bool existing = st_update(heap_recorder->heap_records, (st_data_t) stack, update_heap_record_entry_with_new_allocation, (st_data_t) &update_data);
  if (existing) {
    heap_stack_free(heap_recorder, stack);
  }

  return heap_record;
}

static void cleanup_heap_record_if_unused(heap_recorder *heap_recorder, heap_record *heap_record) {
  if (heap_record->num_tracked_objects > 0) {
    // still being used! do nothing...
    return;
  }

  heap_stack *key = heap_record->stack;
  if (!st_delete(heap_recorder->heap_records, (st_data_t*) &key, NULL)) {
    rb_raise(rb_eRuntimeError, "Attempted to cleanup an untracked heap_record");
  };
  heap_record_free(heap_recorder, heap_record);
}

static void on_committed_object_record_cleanup(heap_recorder *heap_recorder, object_record *record) {
  // Starting with the associated heap record. There will now be one less tracked object pointing to it
  heap_record *heap_record = record->heap_record;
  heap_record->num_tracked_objects--;

  // One less object using this heap record, it may have become unused...
  cleanup_heap_record_if_unused(heap_recorder, heap_record);

  object_record_free(heap_recorder, record);
}

// ===============
// Heap Record API
// ===============
heap_record* heap_record_new(heap_stack *stack) {
  heap_record *record = ruby_xcalloc(1, sizeof(heap_record));
  record->num_tracked_objects = 0;
  record->stack = stack;
  return record;
}

void heap_record_free(heap_recorder *recorder, heap_record *record) {
  heap_stack_free(recorder, record->stack);
  ruby_xfree(record);
}


// =================
// Object Record API
// =================
object_record* object_record_new(long obj_id, heap_record *heap_record, live_object_data object_data) {
  object_record *record = ruby_xcalloc(1, sizeof(object_record));
  record->obj_id = obj_id;
  record->heap_record = heap_record;
  record->object_data = object_data;
  return record;
}

void object_record_free(heap_recorder *recorder, object_record *record) {
  unintern_or_raise(recorder, record->object_data.class);
  ruby_xfree(record);
}

VALUE object_record_inspect(heap_recorder *recorder, object_record *record) {
  heap_frame top_frame = record->heap_record->stack->frames[0];
  VALUE filename = get_ruby_string_or_raise(recorder, top_frame.filename);
  live_object_data object_data = record->object_data;

  VALUE inspect = rb_sprintf("obj_id=%ld weight=%d size=%zu location=%"PRIsVALUE":%d alloc_gen=%zu gen_age=%zu frozen=%d ",
      record->obj_id, object_data.weight, object_data.size, filename,
      (int) top_frame.line, object_data.alloc_gen, object_data.gen_age, object_data.is_frozen);

  if (record->object_data.class > 0) {
    VALUE class = get_ruby_string_or_raise(recorder, record->object_data.class);

    rb_str_catf(inspect, "class=%"PRIsVALUE" ", class);
  }
  VALUE ref;

  if (!ruby_ref_from_id(LONG2NUM(record->obj_id), &ref)) {
    rb_str_catf(inspect, "object=<invalid>");
  } else {
    rb_str_catf(inspect, "value=%p ", (void *) ref);
    VALUE ruby_inspect = ruby_safe_inspect(ref);
    if (ruby_inspect != Qnil) {
      rb_str_catf(inspect, "object=%"PRIsVALUE, ruby_inspect);
    } else {
      rb_str_catf(inspect, "object=%s", ruby_value_type_to_string(rb_type(ref)));
    }
  }

  return inspect;
}

// ==============
// Heap Frame API
// ==============
int heap_frame_cmp(heap_frame *f1, heap_frame *f2) {
  int line_diff = (int) (f1->line - f2->line);
  if (line_diff != 0) {
    return line_diff;
  }
  int name_diff = (int) (f1->name - f2->name);
  if (name_diff != 0) {
    return name_diff;
  }
  return (int) (f1->filename - f2->filename);
}

st_index_t heap_frame_hash(heap_frame *frame, st_index_t seed) {
  st_index_t hash = st_hash(&frame->name, sizeof(frame->name), seed);
  hash = st_hash(&frame->filename, sizeof(frame->filename), hash);
  hash = st_hash(&frame->line, sizeof(frame->line), hash);
  return hash;
}

// ==============
// Heap Stack API
// ==============
heap_stack* heap_stack_new(heap_recorder *recorder, ddog_prof_Slice_Location locations) {
  uint16_t frames_len = locations.len;
  if (frames_len > MAX_FRAMES_LIMIT) {
    // This should not be happening anyway since MAX_FRAMES_LIMIT should be shared with
    // the stacktrace construction mechanism. If it happens, lets just raise. This should
    // be safe since only allocate with the GVL anyway.
    rb_raise(rb_eRuntimeError, "Found stack with more than %d frames (%d)", MAX_FRAMES_LIMIT, frames_len);
  }
  heap_stack *stack = ruby_xcalloc(1, sizeof(heap_stack) + frames_len * sizeof(heap_frame));
  stack->frames_len = frames_len;
  for (uint16_t i = 0; i < stack->frames_len; i++) {
    const ddog_prof_Location *location = &locations.ptr[i];
    stack->frames[i] = (heap_frame) {
      .name = intern_or_raise(recorder, &location->function.name),
      .filename = intern_or_raise(recorder, &location->function.filename),
      // ddog_prof_Location is a int64_t. We don't expect to have to profile files with more than
      // 2M lines so this cast should be fairly safe?
      .line = (int32_t) location->line,
    };
  }
  return stack;
}

void heap_stack_free(heap_recorder *recorder, heap_stack *stack) {
  for (u_int16_t i = 0; i < stack->frames_len; i++) {
    unintern_or_raise(recorder, stack->frames[i].filename);
    unintern_or_raise(recorder, stack->frames[i].name);
  }

  ruby_xfree(stack);
}

st_index_t heap_stack_hash(heap_stack *stack, st_index_t seed) {
  st_index_t hash = seed;
  for (uint64_t i = 0; i < stack->frames_len; i++) {
    hash = heap_frame_hash(&stack->frames[i], hash);
  }
  return hash;
}

int heap_stack_cmp_st(st_data_t key1, st_data_t key2) {
  heap_stack *stack1 = (heap_stack*) key1;
  heap_stack *stack2 = (heap_stack*) key2;

  // Fast path, check if lengths differ
  if (stack1->frames_len != stack2->frames_len) {
    return ((int) stack1->frames_len) - ((int) stack2->frames_len);
  }

  // If we got this far, we have same lengths so need to check item-by-item
  for (size_t i = 0; i < stack1->frames_len; i++) {
    heap_frame* frame1 = &stack1->frames[i];
    heap_frame* frame2 = &stack2->frames[i];

    if (frame1->name != frame2->name) {
      return ((int) frame1->name) - ((int) frame2->name);
    }

    if (frame1->filename != frame2->filename) {
      return ((int) frame1->filename) - ((int) frame2->filename);
    }

    if (frame1->line != frame2->line) {
      return ((int) frame1->line) - ((int)frame2->line);
    }
  }

  // If we survived the above for, then everything matched
  return 0;
}

// Initial seed for hash functions
#define FNV1_32A_INIT 0x811c9dc5

st_index_t heap_stack_hash_st(st_data_t key) {
  heap_stack *stack = (heap_stack*) key;
  return heap_stack_hash(stack, FNV1_32A_INIT);
}

static u_int32_t intern_or_raise(heap_recorder *recorder, const ddog_CharSlice *char_slice) {
  if (char_slice == NULL) {
    return 0;
  }
  ddog_prof_ManagedStringStorageInternResult intern_result = ddog_prof_ManagedStringStorage_intern(*recorder->string_storage, char_slice);
  if (intern_result.tag == DDOG_PROF_MANAGED_STRING_STORAGE_INTERN_RESULT_ERR) {
    rb_raise(rb_eRuntimeError, "Failed to intern char slice: %"PRIsVALUE, get_error_details_and_drop(&intern_result.err));
  }
  return intern_result.ok;
}

static void unintern_or_raise(heap_recorder *recorder, u_int32_t id) {
  ddog_prof_ManagedStringStorageResult intern_result = ddog_prof_ManagedStringStorage_unintern(*recorder->string_storage, id);
  if (intern_result.tag == DDOG_PROF_MANAGED_STRING_STORAGE_INTERN_RESULT_ERR) {
    rb_raise(rb_eRuntimeError, "Failed to unintern id: %"PRIsVALUE, get_error_details_and_drop(&intern_result.err));
  }
}

static VALUE get_ruby_string_or_raise(heap_recorder *recorder, u_int32_t id) {
  ddog_prof_StringWrapperResult get_string_result = ddog_prof_ManagedStringStorage_get_string(*recorder->string_storage, id);
  if (get_string_result.tag == DDOG_PROF_STRING_WRAPPER_RESULT_ERR) {
    rb_raise(rb_eRuntimeError, "Failed to get string: %"PRIsVALUE, get_error_details_and_drop(&get_string_result.err));
  }
  VALUE ruby_string = ruby_string_from_vec_u8(get_string_result.ok.message);
  ddog_StringWrapper_drop((struct ddog_StringWrapper*)&get_string_result.ok);

  return ruby_string;
}

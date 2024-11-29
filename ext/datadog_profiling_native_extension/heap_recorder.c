#include "heap_recorder.h"
#include "ruby/st.h"
#include "ruby_helpers.h"
#include "collectors_stack.h"
#include "libdatadog_helpers.h"
#include "time_helpers.h"

// Minimum age (in GC generations) of heap objects we want to include in heap
// recorder iterations. Object with age 0 represent objects that have yet to undergo
// a GC and, thus, may just be noise/trash at instant of iteration and are usually not
// relevant for heap profiles as the great majority should be trivially reclaimed
// during the next GC.
#define ITERATION_MIN_AGE 1
// Copied from https://github.com/ruby/ruby/blob/15135030e5808d527325feaaaf04caeb1b44f8b5/gc/default.c#L725C1-L725C27
// to align with Ruby's GC definition of what constitutes an old object which are only
// supposed to be reclaimed in major GCs.
#define OLD_AGE 3
// Wait at least 2 seconds before asking heap recorder to explicitly update itself. Heap recorder
// data will only materialize at profile serialization time but updating often helps keep our
// heap tracking data small since every GC should get rid of a bunch of temporary objects. The
// more we clean up before profile flush, the less work we'll have to do all-at-once when preparing
// to flush heap data and holding the GVL which should hopefully help with reducing latency impact.
#define MIN_TIME_BETWEEN_HEAP_RECORDER_UPDATES_NS SECONDS_AS_NS(2)

// A compact representation of a stacktrace frame for a heap allocation.
typedef struct {
  ddog_prof_ManagedStringId name;
  ddog_prof_ManagedStringId filename;
  int32_t line;
} heap_frame;

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
  //
  // TODO: @ivoanjo We've evolved to actually never need to look up on object_records (we only insert and iterate),
  // so right now this seems to be just a really really fancy self-resizing list/set.
  st_table *object_records;

  // Map[obj_id: long, record: object_record*]
  // NOTE: This is a snapshot of object_records built ahead of a iteration. Outside of an
  // iteration context, this table will be NULL. During an iteration, there will be no
  // mutation of the data so iteration can occur without acquiring a lock.
  // NOTE: Contrary to object_records, this table has no ownership of its data.
  st_table *object_records_snapshot;
  // Are we currently updating or not?
  bool updating;
  // The GC gen/epoch/count in which we are updating (or last updated if not currently updating).
  //
  // This enables us to calculate the age of objects considered in the update by comparing it
  // against an object's alloc_gen.
  size_t update_gen;
  // Whether the current update (or last update if not currently updating) is including old
  // objects or not.
  bool update_include_old;
  // When did we do the last update of heap recorder?
  long last_update_ns;

  // Data for a heap recording that was started but not yet ended
  object_record *active_recording;

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

  struct stats_lifetime {
    unsigned long updates_successful;
    unsigned long updates_skipped_concurrent;
    unsigned long updates_skipped_gcgen;
    unsigned long updates_skipped_time;

    double ewma_young_objects_alive;
    double ewma_young_objects_dead;
    double ewma_young_objects_skipped; // Note: Here "young" refers to the young update; objects skipped includes non-young objects

    double ewma_objects_alive;
    double ewma_objects_dead;
    double ewma_objects_skipped;
  } stats_lifetime;

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
static void commit_recording(heap_recorder *, heap_record *, object_record *active_recording);
static VALUE end_heap_allocation_recording(VALUE end_heap_allocation_args);
static void heap_recorder_update(heap_recorder *heap_recorder, bool full_update);
static inline double ewma_stat(double previous, double current);
static ddog_prof_ManagedStringId intern_or_raise(heap_recorder*, const ddog_CharSlice*);
static void unintern_or_raise(heap_recorder *, ddog_prof_ManagedStringId);
static VALUE get_ruby_string_or_raise(heap_recorder*, ddog_prof_ManagedStringId);

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
  recorder->active_recording = NULL;
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

  if (heap_recorder->active_recording != NULL && heap_recorder->active_recording != &SKIPPED_RECORD) {
    // If there's a partial object record, clean it up as well
    object_record_free(heap_recorder, heap_recorder->active_recording);
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
  // outside of the GVL, any state specific to that interaction may be inconsistent after fork
  // (e.g. an acquired lock for thread safety). Iteration operates on object_records_snapshot
  // though and that one will be updated on next heap_recorder_prepare_iteration so we really
  // only need to finish any iteration that might have been left unfinished.
  if (heap_recorder->object_records_snapshot != NULL) {
    heap_recorder_finish_iteration(heap_recorder);
  }

  // Clear lifetime stats since this is essentially a new heap recorder
  heap_recorder->stats_lifetime = (struct stats_lifetime) {0};
}

void start_heap_allocation_recording(heap_recorder *heap_recorder, VALUE new_obj, unsigned int weight, ddog_CharSlice alloc_class) {
  if (heap_recorder == NULL) {
    return;
  }

  if (heap_recorder->active_recording != NULL) {
    rb_raise(rb_eRuntimeError, "Detected consecutive heap allocation recording starts without end.");
  }

  if (++heap_recorder->num_recordings_skipped < heap_recorder->sample_rate) {
    heap_recorder->active_recording = &SKIPPED_RECORD;
    return;
  }

  heap_recorder->num_recordings_skipped = 0;

  VALUE ruby_obj_id = rb_obj_id(new_obj);
  if (!FIXNUM_P(ruby_obj_id)) {
    rb_raise(rb_eRuntimeError, "Detected a bignum object id. These are not supported by heap profiling.");
  }

  ddog_prof_ManagedStringId alloc_class_id = intern_or_raise(heap_recorder, &alloc_class);

  heap_recorder->active_recording = object_record_new(
    FIX2LONG(ruby_obj_id),
    NULL,
    (live_object_data) {
      .weight = weight * heap_recorder->sample_rate,
      .class = alloc_class_id,
      .alloc_gen = rb_gc_count(),
    }
  );
}

// end_heap_allocation_recording_with_rb_protect gets called while the stack_recorder is holding one of the profile
// locks. To enable us to correctly unlock the profile on exception, we wrap the call to end_heap_allocation_recording
// with an rb_protect.
__attribute__((warn_unused_result))
int end_heap_allocation_recording_with_rb_protect(struct heap_recorder *heap_recorder, ddog_prof_Slice_Location locations) {
  if (heap_recorder == NULL) {
    return 0;
  }

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

  object_record *active_recording = heap_recorder->active_recording;

  if (active_recording == NULL) {
    // Recording ended without having been started?
    rb_raise(rb_eRuntimeError, "Ended a heap recording that was not started");
  }
  // From now on, mark the global active recording as invalid so we can short-circuit at any point
  // and not end up with a still active recording. the local active_recording still holds the
  // data required for committing though.
  heap_recorder->active_recording = NULL;

  if (active_recording == &SKIPPED_RECORD) { // special marker when we decided to skip due to sampling
    return Qnil;
  }

  heap_record *heap_record = get_or_create_heap_record(heap_recorder, locations);

  // And then commit the new allocation.
  commit_recording(heap_recorder, heap_record, active_recording);

  return Qnil;
}

void heap_recorder_update_young_objects(heap_recorder *heap_recorder) {
  if (heap_recorder == NULL) {
    return;
  }

  heap_recorder_update(heap_recorder, /* full_update: */ false);
}

static void heap_recorder_update(heap_recorder *heap_recorder, bool full_update) {
  if (heap_recorder->updating) {
    if (full_update) rb_raise(rb_eRuntimeError, "BUG: full_update should not be triggered during another update");

    // If we try to update while another update is still running, short-circuit.
    // NOTE: This runs while holding the GVL. But since updates may be triggered from GC activity, there's still
    //       a chance for updates to be attempted concurrently if scheduling gods so determine.
    heap_recorder->stats_lifetime.updates_skipped_concurrent++;
    return;
  }

  if (heap_recorder->object_records_snapshot != NULL) {
    // While serialization is happening, it runs without the GVL and uses the object_records_snapshot.
    // Although we iterate on a snapshot of object_records, these records point to other data that has not been
    // snapshotted for efficiency reasons (e.g. heap_records). Since updating may invalidate
    // some of that non-snapshotted data, let's refrain from doing updates during iteration. This also enforces the
    // semantic that iteration will operate as a point-in-time snapshot.
    return;
  }

  size_t current_gc_gen = rb_gc_count();
  long now_ns = monotonic_wall_time_now_ns(DO_NOT_RAISE_ON_FAILURE);

  if (!full_update) {
    if (current_gc_gen == heap_recorder->update_gen) {
      // Are we still in the same GC gen as last update? If so, skip updating since things should not have
      // changed significantly since last time.
      // NOTE: This is mostly a performance decision. I suppose some objects may be cleaned up in intermediate
      // GC steps and sizes may change. But because we have to iterate through all our tracked
      // object records to do an update, let's wait until all steps for a particular GC generation
      // have finished to do so. We may revisit this once we have a better liveness checking mechanism.
      heap_recorder->stats_lifetime.updates_skipped_gcgen++;
      return;
    }

    if (now_ns > 0 && (now_ns - heap_recorder->last_update_ns) < MIN_TIME_BETWEEN_HEAP_RECORDER_UPDATES_NS) {
      // We did an update not too long ago. Let's skip this one to avoid over-taxing the system.
      heap_recorder->stats_lifetime.updates_skipped_time++;
      return;
    }
  }

  heap_recorder->updating = true;
  // Reset last update stats, we'll be building them from scratch during the st_foreach call below
  heap_recorder->stats_last_update = (struct stats_last_update) {0};

  heap_recorder->update_gen = current_gc_gen;
  heap_recorder->update_include_old = full_update;

  st_foreach(heap_recorder->object_records, st_object_record_update, (st_data_t) heap_recorder);

  heap_recorder->last_update_ns = now_ns;
  heap_recorder->stats_lifetime.updates_successful++;

  // Lifetime stats updating
  if (!full_update) {
    heap_recorder->stats_lifetime.ewma_young_objects_alive = ewma_stat(heap_recorder->stats_lifetime.ewma_young_objects_alive, heap_recorder->stats_last_update.objects_alive);
    heap_recorder->stats_lifetime.ewma_young_objects_dead = ewma_stat(heap_recorder->stats_lifetime.ewma_young_objects_dead, heap_recorder->stats_last_update.objects_dead);
    heap_recorder->stats_lifetime.ewma_young_objects_skipped = ewma_stat(heap_recorder->stats_lifetime.ewma_young_objects_skipped, heap_recorder->stats_last_update.objects_skipped);
  } else {
    heap_recorder->stats_lifetime.ewma_objects_alive = ewma_stat(heap_recorder->stats_lifetime.ewma_objects_alive, heap_recorder->stats_last_update.objects_alive);
    heap_recorder->stats_lifetime.ewma_objects_dead = ewma_stat(heap_recorder->stats_lifetime.ewma_objects_dead, heap_recorder->stats_last_update.objects_dead);
    heap_recorder->stats_lifetime.ewma_objects_skipped = ewma_stat(heap_recorder->stats_lifetime.ewma_objects_skipped, heap_recorder->stats_last_update.objects_skipped);
  }

  heap_recorder->updating = false;
}

void heap_recorder_prepare_iteration(heap_recorder *heap_recorder) {
  if (heap_recorder == NULL) {
    return;
  }

  if (heap_recorder->object_records_snapshot != NULL) {
    // we could trivially handle this but we raise to highlight and catch unexpected usages.
    rb_raise(rb_eRuntimeError, "New heap recorder iteration prepared without the previous one having been finished.");
  }

  heap_recorder_update(heap_recorder, /* full_update: */ true);

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

    // Lifetime stats
    ID2SYM(rb_intern("lifetime_updates_successful")), /* => */ LONG2NUM(heap_recorder->stats_lifetime.updates_successful),
    ID2SYM(rb_intern("lifetime_updates_skipped_concurrent")), /* => */ LONG2NUM(heap_recorder->stats_lifetime.updates_skipped_concurrent),
    ID2SYM(rb_intern("lifetime_updates_skipped_gcgen")), /* => */ LONG2NUM(heap_recorder->stats_lifetime.updates_skipped_gcgen),
    ID2SYM(rb_intern("lifetime_updates_skipped_time")), /* => */ LONG2NUM(heap_recorder->stats_lifetime.updates_skipped_time),
    ID2SYM(rb_intern("lifetime_ewma_young_objects_alive")), /* => */ DBL2NUM(heap_recorder->stats_lifetime.ewma_young_objects_alive),
    ID2SYM(rb_intern("lifetime_ewma_young_objects_dead")), /* => */ DBL2NUM(heap_recorder->stats_lifetime.ewma_young_objects_dead),
      // Note: Here "young" refers to the young update; objects skipped includes non-young objects
    ID2SYM(rb_intern("lifetime_ewma_young_objects_skipped")), /* => */ DBL2NUM(heap_recorder->stats_lifetime.ewma_young_objects_skipped),
    ID2SYM(rb_intern("lifetime_ewma_objects_alive")), /* => */ DBL2NUM(heap_recorder->stats_lifetime.ewma_objects_alive),
    ID2SYM(rb_intern("lifetime_ewma_objects_dead")), /* => */ DBL2NUM(heap_recorder->stats_lifetime.ewma_objects_dead),
    ID2SYM(rb_intern("lifetime_ewma_objects_skipped")), /* => */ DBL2NUM(heap_recorder->stats_lifetime.ewma_objects_skipped),
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
    rb_raise(rb_eArgError, "heap_recorder is NULL");
  }

  VALUE debug_str = rb_str_new2("object records:\n");
  debug_context context = (debug_context) {.recorder = heap_recorder, .debug_str = debug_str};
  st_foreach(heap_recorder->object_records, st_object_records_debug, (st_data_t) &context);

  rb_str_catf(debug_str, "state snapshot: %"PRIsVALUE"\n------\n", heap_recorder_state_snapshot(heap_recorder));

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

static int st_object_record_update(st_data_t key, st_data_t value, st_data_t extra_arg) {
  long obj_id = (long) key;
  object_record *record = (object_record*) value;
  heap_recorder *recorder = (heap_recorder*) extra_arg;

  VALUE ref;

  size_t update_gen = recorder->update_gen;
  size_t alloc_gen = record->object_data.alloc_gen;
  // Guard against potential overflows given unsigned types here.
  record->object_data.gen_age = alloc_gen < update_gen ? update_gen - alloc_gen : 0;

  if (record->object_data.gen_age == 0) {
    // Objects that belong to the current GC gen have not had a chance to be cleaned up yet
    // and won't show up in the iteration anyway so no point in checking their liveness/sizes.
    recorder->stats_last_update.objects_skipped++;
    return ST_CONTINUE;
  }

  if (!recorder->update_include_old && record->object_data.gen_age >= OLD_AGE) {
    // The current update is not including old objects but this record is for an old object, skip its update.
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

  if (
    recorder->size_enabled &&
    recorder->update_include_old && // We only update sizes when doing a full update
    !record->object_data.is_frozen
  ) {
    // if we were asked to update sizes and this object was not already seen as being frozen,
    // update size again.
    record->object_data.size = ruby_obj_memsize_of(ref);
    // Check if it's now frozen so we skip a size update next time
    record->object_data.is_frozen = RB_OBJ_FROZEN(ref);
  }

  // Ensure that ref is kept on the stack so the Ruby garbage collector does not try to clean up the object before this
  // point.
  RB_GC_GUARD(ref);

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

  if (record->object_data.gen_age < ITERATION_MIN_AGE) {
    // Skip objects that should not be included in iteration
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

  // This is expected to be StackRecorder's add_heap_sample_to_active_profile_without_gvl
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

static int update_object_record_entry(DDTRACE_UNUSED st_data_t *key, st_data_t *value, st_data_t new_object_record, int existing) {
  if (!existing) {
    (*value) = (st_data_t) new_object_record; // Expected to be a `object_record *`
  } else {
    // If key already existed, we don't touch the existing value, so it can be used for diagnostics
  }
  return ST_CONTINUE;
}

static void commit_recording(heap_recorder *heap_recorder, heap_record *heap_record, object_record *active_recording) {
  // Link the object record with the corresponding heap record. This was the last remaining thing we
  // needed to fully build the object_record.
  active_recording->heap_record = heap_record;
  if (heap_record->num_tracked_objects == UINT32_MAX) {
    rb_raise(rb_eRuntimeError, "Reached maximum number of tracked objects for heap record");
  }
  heap_record->num_tracked_objects++;

  int existing_error = st_update(heap_recorder->object_records, active_recording->obj_id, update_object_record_entry, (st_data_t) active_recording);
  if (existing_error) {
    object_record *existing_record = NULL;
    st_lookup(heap_recorder->object_records, active_recording->obj_id, (st_data_t *) &existing_record);
    if (existing_record == NULL) rb_raise(rb_eRuntimeError, "Unexpected NULL when reading existing record");

    VALUE existing_inspect = object_record_inspect(update_data->heap_recorder, existing_record);
    VALUE new_inspect = object_record_inspect(update_data->heap_recorder, active_recording);
    rb_raise(rb_eRuntimeError, "Object ids are supposed to be unique. We got 2 allocation recordings with "
      "the same id. previous={%"PRIsVALUE"} new={%"PRIsVALUE"}", existing_inspect, new_inspect);
  }
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
  // @ivoanjo: We've seen a segfault crash in the field in this function (October 2024) which we're still trying to investigate.
  // (See PROF-10656 Datadog-internal for details). Just in case, I've sprinkled a bunch of NULL tests in this function for now.
  // Once we figure out the issue we can get rid of them again.

  if (heap_recorder == NULL) rb_raise(rb_eRuntimeError, "heap_recorder was NULL in on_committed_object_record_cleanup");
  if (heap_recorder->heap_records == NULL) rb_raise(rb_eRuntimeError, "heap_recorder->heap_records was NULL in on_committed_object_record_cleanup");
  if (record == NULL) rb_raise(rb_eRuntimeError, "record was NULL in on_committed_object_record_cleanup");

  // Starting with the associated heap record. There will now be one less tracked object pointing to it
  heap_record *heap_record = record->heap_record;

  if (heap_record == NULL) rb_raise(rb_eRuntimeError, "heap_record was NULL in on_committed_object_record_cleanup");
  if (heap_record->stack == NULL) rb_raise(rb_eRuntimeError, "heap_record->stack was NULL in on_committed_object_record_cleanup");

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

  if (record->object_data.class.value > 0) {
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
    // This is not expected as MAX_FRAMES_LIMIT is shared with the stacktrace construction mechanism
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

    if (frame1->name.value != frame2->name.value) {
      return ((int) frame1->name.value) - ((int) frame2->name.value);
    }

    if (frame1->filename.value != frame2->filename.value) {
      return ((int) frame1->filename.value) - ((int) frame2->filename.value);
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

static ddog_prof_ManagedStringId intern_or_raise(heap_recorder *recorder, const ddog_CharSlice *char_slice) {
  if (char_slice == NULL) {
    return (ddog_prof_ManagedStringId) { 0 };
  }
  ddog_prof_ManagedStringStorageInternResult intern_result = ddog_prof_ManagedStringStorage_intern(*recorder->string_storage, *char_slice);
  if (intern_result.tag == DDOG_PROF_MANAGED_STRING_STORAGE_INTERN_RESULT_ERR) {
    rb_raise(rb_eRuntimeError, "Failed to intern char slice: %"PRIsVALUE, get_error_details_and_drop(&intern_result.err));
  }
  return intern_result.ok;
}

static void unintern_or_raise(heap_recorder *recorder, ddog_prof_ManagedStringId id) {
  ddog_prof_MaybeError result = ddog_prof_ManagedStringStorage_unintern(*recorder->string_storage, id);
  if (result.tag == DDOG_PROF_OPTION_ERROR_SOME_ERROR) {
    rb_raise(rb_eRuntimeError, "Failed to unintern id: %"PRIsVALUE, get_error_details_and_drop(&result.some));
  }
}

static VALUE get_ruby_string_or_raise(heap_recorder *recorder, ddog_prof_ManagedStringId id) {
  ddog_prof_StringWrapperResult get_string_result = ddog_prof_ManagedStringStorage_get_string(*recorder->string_storage, id);
  if (get_string_result.tag == DDOG_PROF_STRING_WRAPPER_RESULT_ERR) {
    rb_raise(rb_eRuntimeError, "Failed to get string: %"PRIsVALUE, get_error_details_and_drop(&get_string_result.err));
  }
  VALUE ruby_string = ruby_string_from_vec_u8(get_string_result.ok.message);
  ddog_StringWrapper_drop((struct ddog_StringWrapper*)&get_string_result.ok);

  return ruby_string;
}

static inline double ewma_stat(double previous, double current) {
  double alpha = 0.3;
  return (1 - alpha) * previous + alpha * current;
}

VALUE heap_recorder_testonly_is_object_recorded(heap_recorder *heap_recorder, VALUE obj_id) {
  if (heap_recorder == NULL) {
    rb_raise(rb_eArgError, "heap_recorder is NULL");
  }

  // Check if object records contains an object with this object_id
  return st_is_member(heap_recorder->object_records, FIX2LONG(obj_id)) ? Qtrue : Qfalse;
}

void heap_recorder_testonly_reset_last_update(heap_recorder *heap_recorder) {
  if (heap_recorder == NULL) {
    rb_raise(rb_eArgError, "heap_recorder is NULL");
  }

  heap_recorder->last_update_ns = 0;
}

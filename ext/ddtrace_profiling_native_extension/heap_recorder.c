#include "heap_recorder.h"
#include <pthread.h>
#include "ruby/st.h"
#include "ruby_helpers.h"
#include <errno.h>
#include "collectors_stack.h"

// A compact representation of a stacktrace frame for a heap allocation.
typedef struct {
  char *name;
  char *filename;
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
static heap_stack* heap_stack_new(ddog_prof_Slice_Location);
static void heap_stack_free(heap_stack*);
static st_index_t heap_stack_hash(heap_stack*, st_index_t);

#if MAX_FRAMES_LIMIT > UINT16_MAX
  #error Frames len type not compatible with MAX_FRAMES_LIMIT
#endif

enum heap_record_key_type {
  HEAP_STACK,
  LOCATION_SLICE
};
// This struct allows us to use two different types of stacks when
// interacting with a heap_record hash.
//
// The idea is that we'll always want to use heap_stack-keys when
// adding new entries to the hash since that's the compact stack
// representation we rely on internally.
//
// However, when querying for an existing heap record, we'd save a
// lot of allocations if we could query with the
// ddog_prof_Slice_Location we receive in our external API.
//
// To allow this interchange, we need a union and need to ensure
// that whatever shape of the union, the heap_record_key_cmp_st
// and heap_record_hash_st functions return the same results for
// equivalent stacktraces.
typedef struct {
  enum heap_record_key_type type;
  union {
    // key never owns this if set
    heap_stack *heap_stack;
    // key never owns this if set
    ddog_prof_Slice_Location *location_slice;
  };
} heap_record_key;
static heap_record_key* heap_record_key_new(heap_stack*);
static void heap_record_key_free(heap_record_key*);
static int heap_record_key_cmp_st(st_data_t, st_data_t);
static st_index_t heap_record_key_hash_st(st_data_t);
static const struct st_hash_type st_hash_type_heap_record_key = {
    heap_record_key_cmp_st,
    heap_record_key_hash_st,
};

// Need to implement these functions to support the location-slice based keys
static st_index_t ddog_location_hash(ddog_prof_Location, st_index_t seed);
static st_index_t ddog_location_slice_hash(ddog_prof_Slice_Location, st_index_t seed);

// A heap record is used for deduping heap allocation stacktraces across multiple
// objects sharing the same allocation location.
typedef struct {
  // How many objects are currently tracked by the heap recorder for this heap record.
  uint32_t num_tracked_objects;
  // stack is owned by the associated record and gets cleaned up alongside it
  heap_stack *stack;
} heap_record;
static heap_record* heap_record_new(heap_stack*);
static void heap_record_free(heap_record*);

// An object record is used for storing data about currently tracked live objects
typedef struct {
  long obj_id;
  heap_record *heap_record;
  live_object_data object_data;
} object_record;
static object_record* object_record_new(long, heap_record*, live_object_data);
static void object_record_free(object_record*);

// Allows storing data passed to ::start_heap_allocation_recording to make it accessible to
// ::end_heap_allocation_recording.
//
// obj_id != 0 flags this struct as holding a valid partial heap recording.
typedef struct {
  long obj_id;
  live_object_data object_data;
} partial_heap_recording;

struct heap_recorder {
  // Map[key: heap_record_key*, record: heap_record*]
  // NOTE: We always use heap_record_key.type == HEAP_STACK for storage but support lookups
  // via heap_record_key.type == LOCATION_SLICE to allow for allocation-free fast-paths.
  // NOTE: This table is currently only protected by the GVL since we never iterate on it
  // outside the GVL.
  st_table *heap_records;

  // Map[obj_id: long, record: object_record*]
  st_table *object_records;

  // Lock protecting writes to object_records.
  // NOTE: heap_records is currently not protected by this one since we do not iterate on
  // heap records outside the GVL.
  pthread_mutex_t records_mutex;

  // Data for a heap recording that was started but not yet ended
  partial_heap_recording active_recording;

  // Reusable location array, implementing a flyweight pattern for things like iteration.
  ddog_prof_Location *reusable_locations;
};
static heap_record* get_or_create_heap_record(heap_recorder*, ddog_prof_Slice_Location);
static void cleanup_heap_record_if_unused(heap_recorder*, heap_record*);
static int st_heap_record_entry_free(st_data_t, st_data_t, st_data_t);
static int st_object_record_entry_free(st_data_t, st_data_t, st_data_t);
static int st_object_record_entry_free_if_invalid(st_data_t, st_data_t, st_data_t);
static int st_object_records_iterate(st_data_t, st_data_t, st_data_t);
static int update_object_record_entry(st_data_t*, st_data_t*, st_data_t, int);
static void commit_allocation(heap_recorder*, heap_record*, long, live_object_data);

// ==========================
// Heap Recorder External API
//
// WARN: All these APIs should support receiving a NULL heap_recorder, resulting in a noop.
//
// WARN: Except for ::heap_recorder_for_each_live_object, we always assume interaction with these APIs
// happens under the GVL.
//
// ==========================
heap_recorder* heap_recorder_new(void) {
  heap_recorder *recorder = ruby_xcalloc(1, sizeof(heap_recorder));

  recorder->records_mutex = (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;
  recorder->heap_records = st_init_table(&st_hash_type_heap_record_key);
  recorder->object_records = st_init_numtable();
  recorder->reusable_locations = ruby_xcalloc(MAX_FRAMES_LIMIT, sizeof(ddog_prof_Location));
  recorder->active_recording = (partial_heap_recording) {
    .obj_id = 0, // 0 is actually the obj_id of false, but we'll never track that one in heap so we use
                 // it as invalid/unset value.
    .object_data = {0},
  };

  return recorder;
}

void heap_recorder_free(heap_recorder *heap_recorder) {
  if (heap_recorder == NULL) {
    return;
  }

  st_foreach(heap_recorder->object_records, st_object_record_entry_free, 0);
  st_free_table(heap_recorder->object_records);

  st_foreach(heap_recorder->heap_records, st_heap_record_entry_free, 0);
  st_free_table(heap_recorder->heap_records);

  pthread_mutex_destroy(&heap_recorder->records_mutex);

  ruby_xfree(heap_recorder->reusable_locations);

  ruby_xfree(heap_recorder);
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
  // simply be noticed on next heap_recorder_flush.
  //
  // There is one small caveat though: fork only preserves one thread and in a Ruby app, that
  // will be the thread holding on to the GVL. Since we support iteration on the heap recorder
  // outside of the GVL (which implies acquiring the records_mutex lock), this means the child
  // process may be in this weird state of having a records_mutex lock stuck in a locked
  // state and that state having been caused by a thread that no longer exists.
  //
  // We can't blindly unlock records_mutex from the thread calling heap_recorder_after_fork
  // as unlocking mutexes a thread doesn't own is undefined behaviour. What we can do is
  // create a new lock and start using it from now on-forward. This is fine because at this
  // point in the fork-handling logic, all tracepoints are disabled and no-one should be
  // iterating on the recorder state so there are no writers/readers that may race with
  // this reinitialization.
  heap_recorder->records_mutex = (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;
}

void start_heap_allocation_recording(heap_recorder *heap_recorder, VALUE new_obj, unsigned int weight) {
  if (heap_recorder == NULL) {
    return;
  }

  VALUE ruby_obj_id = rb_obj_id(new_obj);
  if (!FIXNUM_P(ruby_obj_id)) {
    rb_raise(rb_eRuntimeError, "Detected a bignum object id. These are not supported by heap profiling.");
  }

  heap_recorder->active_recording = (partial_heap_recording) {
    .obj_id = FIX2LONG(ruby_obj_id),
    .object_data = (live_object_data) {
      .weight = weight,
    },
  };
}

void end_heap_allocation_recording(struct heap_recorder *heap_recorder, ddog_prof_Slice_Location locations) {
  if (heap_recorder == NULL) {
    return;
  }

  partial_heap_recording *active_recording = &heap_recorder->active_recording;

  long obj_id = active_recording->obj_id;
  if (obj_id == 0) {
    // Recording ended without having been started?
    rb_raise(rb_eRuntimeError, "Ended a heap recording that was not started");
  }

  // From now on, mark active recording as invalid so we can short-circuit at any point and
  // not end up with a still active recording. new_obj still holds the object for this recording
  active_recording->obj_id = 0;

  // NOTE: This is the only path where we lookup/mutate the heap_records hash. Since this
  //       runs under the GVL, we can afford to interact with heap_records without getting
  //       the lock below.
  heap_record *heap_record = get_or_create_heap_record(heap_recorder, locations);

  int error = pthread_mutex_trylock(&heap_recorder->records_mutex);
  if (error == EBUSY) {
    // We weren't able to get a lock
    // TODO: Add some queuing system so we can do something other than drop this data.
    cleanup_heap_record_if_unused(heap_recorder, heap_record);
    return;
  }
  if (error) ENFORCE_SUCCESS_GVL(error);

  // And then commit the new allocation.
  commit_allocation(heap_recorder, heap_record, obj_id, active_recording->object_data);

  ENFORCE_SUCCESS_GVL(pthread_mutex_unlock(&heap_recorder->records_mutex));
}

void heap_recorder_flush(heap_recorder *heap_recorder) {
  if (heap_recorder == NULL) {
    return;
  }

  st_foreach(heap_recorder->object_records, st_object_record_entry_free_if_invalid, (st_data_t) heap_recorder);
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

// WARN: If with_gvl = False, NO HEAP ALLOCATIONS, EXCEPTIONS or RUBY CALLS ARE ALLOWED.
void heap_recorder_for_each_live_object(
    heap_recorder *heap_recorder,
    bool (*for_each_callback)(heap_recorder_iteration_data stack_data, void *extra_arg),
    void *for_each_callback_extra_arg,
    bool with_gvl) {
  if (heap_recorder == NULL) {
    return;
  }

  ENFORCE_SUCCESS_HELPER(pthread_mutex_lock(&heap_recorder->records_mutex), with_gvl);
  iteration_context context;
  context.for_each_callback = for_each_callback;
  context.for_each_callback_extra_arg = for_each_callback_extra_arg;
  context.heap_recorder = heap_recorder;
  st_foreach(heap_recorder->object_records, st_object_records_iterate, (st_data_t) &context);
  ENFORCE_SUCCESS_HELPER(pthread_mutex_unlock(&heap_recorder->records_mutex), with_gvl);
}

void heap_recorder_testonly_assert_hash_matches(ddog_prof_Slice_Location locations) {
  heap_stack *stack = heap_stack_new(locations);
  heap_record_key stack_based_key = (heap_record_key) {
    .type = HEAP_STACK,
    .heap_stack = stack,
  };
  heap_record_key location_based_key = (heap_record_key) {
    .type = LOCATION_SLICE,
    .location_slice = &locations,
  };

  st_index_t stack_hash = heap_record_key_hash_st((st_data_t) &stack_based_key);
  st_index_t location_hash = heap_record_key_hash_st((st_data_t) &location_based_key);

  heap_stack_free(stack);

  if (stack_hash != location_hash) {
    rb_raise(rb_eRuntimeError, "Heap record key hashes built from the same locations differ. stack_based_hash=%"PRI_VALUE_PREFIX"u location_based_hash=%"PRI_VALUE_PREFIX"u", stack_hash, location_hash);
  }
}

// ==========================
// Heap Recorder Internal API
// ==========================
static int st_heap_record_entry_free(st_data_t key, st_data_t value, DDTRACE_UNUSED st_data_t extra_arg) {
  heap_record_key *record_key = (heap_record_key*) key;
  heap_record_key_free(record_key);
  heap_record_free((heap_record *) value);
  return ST_DELETE;
}

static int st_object_record_entry_free(DDTRACE_UNUSED st_data_t key, st_data_t value, DDTRACE_UNUSED st_data_t extra_arg) {
  object_record_free((object_record *) value);
  return ST_DELETE;
}

static int st_object_record_entry_free_if_invalid(st_data_t key, st_data_t value, st_data_t extra_arg) {
  long obj_id = (long) key;
  object_record *record = (object_record*) value;
  heap_recorder *recorder = (heap_recorder*) extra_arg;

  if (!ruby_ref_from_id(LONG2NUM(obj_id), NULL)) {
    // Id no longer associated with a valid ref. Need to clean things up!

    // Starting with the associated heap record. There will now be one less tracked object pointing to it
    heap_record *heap_record = record->heap_record;
    heap_record->num_tracked_objects--;

    // One less object using this heap record, it may have become unused...
    cleanup_heap_record_if_unused(recorder, heap_record);

    object_record_free(record);
    return ST_DELETE;
  }

  return ST_CONTINUE;
}

// WARN: This can get called outside the GVL. NO HEAP ALLOCATIONS OR EXCEPTIONS ARE ALLOWED.
static int st_object_records_iterate(DDTRACE_UNUSED st_data_t key, st_data_t value, st_data_t extra) {
  object_record *record = (object_record*) value;
  const heap_stack *stack = record->heap_record->stack;
  iteration_context *context = (iteration_context*) extra;

  ddog_prof_Location *locations = context->heap_recorder->reusable_locations;

  for (uint16_t i = 0; i < stack->frames_len; i++) {
    const heap_frame *frame = &stack->frames[i];
    ddog_prof_Location *location = &locations[i];
    location->function.name.ptr = frame->name;
    location->function.name.len = strlen(frame->name);
    location->function.filename.ptr = frame->filename;
    location->function.filename.len = strlen(frame->filename);
    location->line = frame->line;
  }

  heap_recorder_iteration_data iteration_data;
  iteration_data.object_data = record->object_data;
  iteration_data.locations = (ddog_prof_Slice_Location) {.ptr = locations, .len = stack->frames_len};

  if (!context->for_each_callback(iteration_data, context->for_each_callback_extra_arg)) {
    return ST_STOP;
  }

  return ST_CONTINUE;
}

// Struct holding data required for an update operation on heap_records
typedef struct {
  // [in] The new object record we want to add.
  // NOTE: Transfer of ownership is assumed, do not re-use it after call to ::update_object_record_entry
  object_record *new_object_record;

  // [in] The heap recorder where the update is happening.
  heap_recorder *heap_recorder;
} object_record_update_data;

static int update_object_record_entry(DDTRACE_UNUSED st_data_t *key, st_data_t *value, st_data_t data, int existing) {
  object_record_update_data *update_data = (object_record_update_data*) data;
  if (existing) {
    rb_raise(rb_eRuntimeError, "Object ids are supposed to be unique. We got 2 allocation recordings with the same id");
  }
  // Always carry on with the update, we want the new record to be there at the end
  (*value) = (st_data_t) update_data->new_object_record;
  return ST_CONTINUE;
}

// WARN: Expects records_mutex to be held
static void commit_allocation(heap_recorder *heap_recorder, heap_record *heap_record, long obj_id, live_object_data object_data) {
  // Update object_records
  object_record_update_data update_data = (object_record_update_data) {
    .heap_recorder = heap_recorder,
    .new_object_record = object_record_new(obj_id, heap_record, object_data),
  };
  if (!st_update(heap_recorder->object_records, obj_id, update_object_record_entry, (st_data_t) &update_data)) {
    // We are sure there was no previous record for this id so let the heap record know there now is one
    // extra record associated with this stack.
    if (heap_record->num_tracked_objects == UINT32_MAX) {
      rb_raise(rb_eRuntimeError, "Reached maximum number of tracked objects for heap record");
    }
    heap_record->num_tracked_objects++;
  };
}

// Struct holding data required for an update operation on heap_records
typedef struct {
  // [in] The locations we did this update with
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
    // we need to initialize a heap_record_key with a new stack and use that for the key storage. We can't use the
    // locations-based key we used for the update call because we don't own its lifecycle. So we create a new
    // heap stack and will pass ownership of it to the heap_record.
    heap_stack *stack = heap_stack_new(update_data->locations);
    (*key) = (st_data_t) heap_record_key_new(stack);
    (*value) = (st_data_t) heap_record_new(stack);
  }

  heap_record *record = (heap_record*) (*value);
  (*update_data->record) = record;

  return ST_CONTINUE;
}

static heap_record* get_or_create_heap_record(heap_recorder *heap_recorder, ddog_prof_Slice_Location locations) {
  // For performance reasons we use a stack-allocated location-slice based key. This allows us
  // to do allocation-free lookups and reuse of a matching existing heap record.
  // NOTE: If we end up creating a new record, we'll create a heap-allocated key we own and use that for storage
  //       instead of this one.
  heap_record_key lookup_key = (heap_record_key) {
    .type = LOCATION_SLICE,
    .location_slice = &locations,
  };

  heap_record *heap_record = NULL;
  heap_record_update_data update_data = (heap_record_update_data) {
    .locations = locations,
    .record = &heap_record,
  };
  st_update(heap_recorder->heap_records, (st_data_t) &lookup_key, update_heap_record_entry_with_new_allocation, (st_data_t) &update_data);

  return heap_record;
}

static void cleanup_heap_record_if_unused(heap_recorder *heap_recorder, heap_record *heap_record) {
  if (heap_record->num_tracked_objects > 0) {
    // still being used! do nothing...
    return;
  }

  heap_record_key heap_key = (heap_record_key) {
    .type = HEAP_STACK,
    .heap_stack = heap_record->stack,
  };
  // We need to access the deleted key to free it since we gave ownership of the keys to the hash.
  // st_delete will change this pointer to point to the removed key if one is found.
  heap_record_key *deleted_key = &heap_key;
  if (!st_delete(heap_recorder->heap_records, (st_data_t*) &deleted_key, NULL)) {
    rb_raise(rb_eRuntimeError, "Attempted to cleanup an untracked heap_record");
  };
  heap_record_key_free(deleted_key);
  heap_record_free(heap_record);
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

void heap_record_free(heap_record *record) {
  heap_stack_free(record->stack);
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

void object_record_free(object_record *record) {
  ruby_xfree(record);
}

// ==============
// Heap Frame API
// ==============
int heap_frame_cmp(heap_frame *f1, heap_frame *f2) {
  int line_diff = (int) (f1->line - f2->line);
  if (line_diff != 0) {
    return line_diff;
  }
  int cmp = strcmp(f1->name, f2->name);
  if (cmp != 0) {
    return cmp;
  }
  return strcmp(f1->filename, f2->filename);
}

// TODO: Research potential performance improvements around hashing stuff here
//       once we have a benchmarking suite.
//       Example: Each call to st_hash is calling murmur_finish and we may want
//                to only finish once per structure, not per field?
//       Example: There may be a more efficient hashing for line that is not the
//                generic st_hash algorithm?

// WARN: Must be kept in-sync with ::char_slice_hash
st_index_t string_hash(char *str, st_index_t seed) {
  return st_hash(str, strlen(str), seed);
}

// WARN: Must be kept in-sync with ::string_hash
st_index_t char_slice_hash(ddog_CharSlice char_slice, st_index_t seed) {
  return st_hash(char_slice.ptr, char_slice.len, seed);
}

// WARN: Must be kept in-sync with ::ddog_location_hash
st_index_t heap_frame_hash(heap_frame *frame, st_index_t seed) {
  st_index_t hash = string_hash(frame->name, seed);
  hash = string_hash(frame->filename, hash);
  hash = st_hash(&frame->line, sizeof(frame->line), hash);
  return hash;
}

// WARN: Must be kept in-sync with ::heap_frame_hash
st_index_t ddog_location_hash(ddog_prof_Location location, st_index_t seed) {
  st_index_t hash = char_slice_hash(location.function.name, seed);
  hash = char_slice_hash(location.function.filename, hash);
  // Convert ddog_prof line type to the same type we use for our heap_frames to
  // ensure we have compatible hashes
  int32_t line_as_int32 = (int32_t) location.line;
  hash = st_hash(&line_as_int32, sizeof(line_as_int32), hash);
  return hash;
}

// ==============
// Heap Stack API
// ==============
heap_stack* heap_stack_new(ddog_prof_Slice_Location locations) {
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
      .name = ruby_strndup(location->function.name.ptr, location->function.name.len),
      .filename = ruby_strndup(location->function.filename.ptr, location->function.filename.len),
      // ddog_prof_Location is a int64_t. We don't expect to have to profile files with more than
      // 2M lines so this cast should be fairly safe?
      .line = (int32_t) location->line,
    };
  }
  return stack;
}

void heap_stack_free(heap_stack *stack) {
  for (uint64_t i = 0; i < stack->frames_len; i++) {
    heap_frame *frame = &stack->frames[i];
    ruby_xfree(frame->name);
    ruby_xfree(frame->filename);
  }
  ruby_xfree(stack);
}

// WARN: Must be kept in-sync with ::ddog_location_slice_hash
st_index_t heap_stack_hash(heap_stack *stack, st_index_t seed) {
  st_index_t hash = seed;
  for (uint64_t i = 0; i < stack->frames_len; i++) {
    hash = heap_frame_hash(&stack->frames[i], hash);
  }
  return hash;
}

// WARN: Must be kept in-sync with ::heap_stack_hash
st_index_t ddog_location_slice_hash(ddog_prof_Slice_Location locations, st_index_t seed) {
  st_index_t hash = seed;
  for (uint64_t i = 0; i < locations.len; i++) {
    hash = ddog_location_hash(locations.ptr[i], hash);
  }
  return hash;
}

// ===================
// Heap Record Key API
// ===================
heap_record_key* heap_record_key_new(heap_stack *stack) {
  heap_record_key *key = ruby_xmalloc(sizeof(heap_record_key));
  key->type = HEAP_STACK;
  key->heap_stack = stack;
  return key;
}

void heap_record_key_free(heap_record_key *key) {
  ruby_xfree(key);
}

static inline size_t heap_record_key_len(heap_record_key *key) {
  if (key->type == HEAP_STACK) {
    return key->heap_stack->frames_len;
  } else {
    return key->location_slice->len;
  }
}

static inline int64_t heap_record_key_entry_line(heap_record_key *key, size_t entry_i) {
  if (key->type == HEAP_STACK) {
    return key->heap_stack->frames[entry_i].line;
  } else {
    return key->location_slice->ptr[entry_i].line;
  }
}

static inline size_t heap_record_key_entry_name(heap_record_key *key, size_t entry_i, const char **name_ptr) {
  if (key->type == HEAP_STACK) {
    char *name = key->heap_stack->frames[entry_i].name;
    (*name_ptr) = name;
    return strlen(name);
  } else {
    ddog_CharSlice name = key->location_slice->ptr[entry_i].function.name;
    (*name_ptr) = name.ptr;
    return name.len;
  }
}

static inline size_t heap_record_key_entry_filename(heap_record_key *key, size_t entry_i, const char **filename_ptr) {
  if (key->type == HEAP_STACK) {
    char *filename = key->heap_stack->frames[entry_i].filename;
    (*filename_ptr) = filename;
    return strlen(filename);
  } else {
    ddog_CharSlice filename = key->location_slice->ptr[entry_i].function.filename;
    (*filename_ptr) = filename.ptr;
    return filename.len;
  }
}

int heap_record_key_cmp_st(st_data_t key1, st_data_t key2) {
  heap_record_key *key_record1 = (heap_record_key*) key1;
  heap_record_key *key_record2 = (heap_record_key*) key2;

  // Fast path, check if lengths differ
  size_t key_record1_len = heap_record_key_len(key_record1);
  size_t key_record2_len = heap_record_key_len(key_record2);

  if (key_record1_len != key_record2_len) {
    return ((int) key_record1_len) - ((int) key_record2_len);
  }

  // If we got this far, we have same lengths so need to check item-by-item
  for (size_t i = 0; i < key_record1_len; i++) {
    // Lines are faster to compare, lets do that first
    size_t line1 = heap_record_key_entry_line(key_record1, i);
    size_t line2 = heap_record_key_entry_line(key_record2, i);
    if (line1 != line2) {
      return ((int) line1) - ((int)line2);
    }

    // Then come names, they are usually smaller than filenames
    const char *name1, *name2;
    size_t name1_len = heap_record_key_entry_name(key_record1, i, &name1);
    size_t name2_len = heap_record_key_entry_name(key_record2, i, &name2);
    if (name1_len != name2_len) {
      return ((int) name1_len) - ((int) name2_len);
    }
    int name_cmp_result = strncmp(name1, name2, name1_len);
    if (name_cmp_result != 0) {
      return name_cmp_result;
    }

    // Then come filenames
    const char *filename1, *filename2;
    int64_t filename1_len = heap_record_key_entry_filename(key_record1, i, &filename1);
    int64_t filename2_len = heap_record_key_entry_filename(key_record2, i, &filename2);
    if (filename1_len != filename2_len) {
      return ((int) filename1_len) - ((int) filename2_len);
    }
    int filename_cmp_result = strncmp(filename1, filename2, filename1_len);
    if (filename_cmp_result != 0) {
      return filename_cmp_result;
    }
  }

  // If we survived the above for, then everything matched
  return 0;
}

// Initial seed for hash functions
#define FNV1_32A_INIT 0x811c9dc5

st_index_t heap_record_key_hash_st(st_data_t key) {
  heap_record_key *record_key = (heap_record_key*) key;
  if (record_key->type == HEAP_STACK) {
    return heap_stack_hash(record_key->heap_stack, FNV1_32A_INIT);
  } else {
    return ddog_location_slice_hash(*record_key->location_slice, FNV1_32A_INIT);
  }
}

#include "heap_recorder.h"
#include <pthread.h>
#include "ruby/st.h"
#include "ruby/util.h"
#include "ruby_helpers.h"
#include <errno.h>

#define MAX_FRAMES_LIMIT 10000
#define MAX_QUEUE_LIMIT 10000

// A compact representation of a stacktrace frame for a heap allocation.
typedef struct {
  char *name;
  char *filename;
  int64_t line;
} heap_frame;
static st_index_t heap_frame_hash(heap_frame*, st_index_t seed);

// A compact representation of a stacktrace for a heap allocation.
//
// We could use a ddog_prof_Slice_Location instead but it has a lot of
// unused fields. Because we have to keep these stacks around for at
// least the lifetime of the objects allocated therein, we would be
// incurring a non-negligible memory overhead for little purpose.
typedef struct {
  heap_frame *frames;
  uint64_t frames_len;
} heap_stack;
static heap_stack* heap_stack_new(ddog_prof_Slice_Location);
static void heap_stack_free(heap_stack*);
static st_index_t heap_stack_hash(heap_stack*, st_index_t);

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
  uint64_t num_tracked_objects;
  // stack is owned by the associated record and gets cleaned up alongside it
  heap_stack *stack;
} heap_record;
static heap_record* heap_record_new(heap_stack*);
static void heap_record_free(heap_record*);

// An object record is used for storing data about currently tracked live objects
typedef struct {
  VALUE obj;
  heap_record *heap_record;
  live_object_data object_data;
} object_record;
static object_record* object_record_new(VALUE, heap_record*, live_object_data);
static void object_record_free(object_record*);

// Allows storing data passed to ::start_heap_allocation_recording to make it accessible to
// ::end_heap_allocation_recording.
//
// obj != Qnil flags this struct as holding a valid partial heap recording.
typedef struct {
  VALUE obj;
  live_object_data object_data;
} partial_heap_recording;

typedef struct {
  // Has ownership of this, needs to clean-it-up if not transferred.
  heap_stack *stack;
  VALUE obj;
  live_object_data object_data;
  bool free;
  bool skip;
} uncommitted_sample;

struct heap_recorder {
  // Map[key: heap_record_key*, record: heap_record*]
  // NOTE: We always use heap_record_key.type == HEAP_STACK for storage but support lookups
  // via heap_record_key.type == LOCATION_SLICE to allow for allocation-free fast-paths.
  st_table *heap_records;

  // Map[obj: VALUE, record: object_record*]
  st_table *object_records;

  // Lock protecting writes to above record tables
  pthread_mutex_t records_mutex;

  // Data for a heap recording that was started but not yet ended
  partial_heap_recording active_recording;

  // Storage for queued samples built while samples are being taken but records_mutex is locked.
  // These will be flushed back to record tables on the next sample execution that can take
  // a write lock on heap_records (or explicitly via ::heap_recorder_flush)
  uncommitted_sample *queued_samples;
  size_t queued_samples_len;

  // Reusable location array, implementing a flyweight pattern for things like iteration.
  ddog_prof_Location *reusable_locations;
};
static int st_heap_record_entry_free(st_data_t, st_data_t, st_data_t);
static int st_object_record_entry_free(st_data_t, st_data_t, st_data_t);
static int st_object_records_iterate(st_data_t, st_data_t, st_data_t);
static int update_object_record_entry(st_data_t*, st_data_t*, st_data_t, int);
static void commit_allocation_with_heap_stack(heap_recorder*, heap_stack*, VALUE, live_object_data);
static void commit_allocation_with_heap_record(heap_recorder*, heap_record*, VALUE, live_object_data);
static void commit_free(heap_recorder*, VALUE, object_record*);
static void flush_queue(heap_recorder*);
static void enqueue_sample(heap_recorder*, uncommitted_sample);
static void enqueue_allocation(heap_recorder*, heap_stack*, VALUE, live_object_data);
static void enqueue_free(heap_recorder*, VALUE);

// ==========================
// Heap Recorder External API
//
// WARN: Except for ::heap_recorder_for_each_live_object, we always assume interaction with these APIs
// happens under the GVL.
//
// ==========================
heap_recorder* heap_recorder_new(void) {
  heap_recorder* recorder = ruby_xmalloc(sizeof(heap_recorder));

  recorder->records_mutex = (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;
  recorder->heap_records = st_init_table(&st_hash_type_heap_record_key);
  recorder->object_records = st_init_numtable();
  recorder->reusable_locations = ruby_xcalloc(MAX_FRAMES_LIMIT, sizeof(ddog_prof_Location));
  recorder->active_recording = (partial_heap_recording) {
    .obj = Qnil,
    .object_data = {0},
  };
  recorder->queued_samples = ruby_xcalloc(MAX_QUEUE_LIMIT, sizeof(uncommitted_sample));
  recorder->queued_samples_len = 0;

  return recorder;
}

void heap_recorder_free(struct heap_recorder* recorder) {
  st_foreach(recorder->object_records, st_object_record_entry_free, 0);
  st_free_table(recorder->object_records);

  st_foreach(recorder->heap_records, st_heap_record_entry_free, 0);
  st_free_table(recorder->heap_records);

  pthread_mutex_destroy(&recorder->records_mutex);

  ruby_xfree(recorder->reusable_locations);
  ruby_xfree(recorder->queued_samples);

  ruby_xfree(recorder);
}

typedef struct {
  void (*for_each_callback)(heap_recorder_iteration_data stack_data, void *extra_arg);
  void *for_each_callback_extra_arg;
  heap_recorder *heap_recorder;
} iteration_context;

void start_heap_allocation_recording(heap_recorder* heap_recorder, VALUE new_obj, unsigned int weight) {
  heap_recorder->active_recording = (partial_heap_recording) {
    .obj = new_obj,
    .object_data = (live_object_data) {
      .weight = weight,
    },
  };
}

void end_heap_allocation_recording(struct heap_recorder *heap_recorder, ddog_prof_Slice_Location locations) {
  partial_heap_recording *active_recording = &heap_recorder->active_recording;

  VALUE new_obj = active_recording->obj;
  if (new_obj == Qnil) {
    // Recording ended without having been started?
    rb_raise(rb_eRuntimeError, "Ended a heap recording that was not started");
  }

  // From now on, mark active recording as invalid so we can short-circuit at any point and
  // not end up with a still active recording. new_obj still holds the object for this recording
  active_recording->obj = Qnil;

  // For performance reasons we use a stack-allocated location-slice based key. This allows us
  // to do allocation-free lookups and reuse of a matching existing heap record.
  heap_record_key locations_record_key = (heap_record_key) {
    .type = LOCATION_SLICE,
    .location_slice = &locations,
  };

  heap_record *heap_record = NULL;
  // WARN: We assume we are under the GVL and that all mutations of object_records happen
  // while holding the GVL so we can afford to do a lock-free lookup.
  st_lookup(heap_recorder->heap_records, (st_data_t) &locations_record_key, (st_data_t*) heap_record);

  int error = pthread_mutex_trylock(&heap_recorder->records_mutex);
  if (error) {
    // unhappy and hopefully rare path
    if (error == EBUSY) {
      // We weren't able to get a lock, enqueue it for later processing
      // When enqueueing, always use a new stack, we can't guarantee a reference to a shared one
      // won't be cleared in-between due to processing of a free.
      // We could potentially improve this but this is not supposed to be the critical path anyway.
      heap_stack *stack = heap_stack_new(locations);
      enqueue_allocation(heap_recorder, stack, new_obj, active_recording->object_data);
    } else {
      // Something unexpected happened, lets error out
      ENFORCE_SUCCESS_GVL(error)
    }
    return;
  }

  // We were able to get a lock to heap_records so lets flush any pending samples
  // that might have been queued previously before adding this new one.
  flush_queue(heap_recorder);

  // And then commit the new allocation.
  if (heap_record == NULL) {
    // If we didn't find a matching heap record we'll need to create a new one so go with
    // new heap stack path.
    heap_stack *stack = heap_stack_new(locations);
    commit_allocation_with_heap_stack(heap_recorder, stack, new_obj, active_recording->object_data);
  } else {
    // If we found an existing heap record, we can re-use it so go with existing heap record
    // path.
    commit_allocation_with_heap_record(heap_recorder, heap_record, new_obj, active_recording->object_data);
  }

  ENFORCE_SUCCESS_GVL(pthread_mutex_unlock(&heap_recorder->records_mutex));
}

// WARN: This can get called during Ruby GC. NO HEAP ALLOCATIONS OR EXCEPTIONS ARE ALLOWED.
void record_heap_free(heap_recorder *heap_recorder, VALUE obj) {
  object_record *object_record = NULL;

  // lookups require hashing and traversal over hash buckets but should not require doing any allocations
  // and should thus be safe to run in GC.
  // WARN: We assume we are under the GVL and that all mutations of object_records happen
  // while holding the GVL so we can afford to do a lock-free lookup.
  st_lookup(heap_recorder->object_records, (st_data_t) obj, (st_data_t*) &object_record);

  if (object_record == NULL) {
    // we don't seem to be tracking this object on the table atm
    // check if the allocation sample is in the queue
    for (size_t i = 0; i < heap_recorder->queued_samples_len; i++) {
      uncommitted_sample *queued_sample = &heap_recorder->queued_samples[i];
      if (queued_sample->obj == obj && !queued_sample->skip) {
        queued_sample->skip = true;
        break;
      }
    }

    // free of an untracked object, return early
    return;
  }

  // If we got this far, we freed a tracked object so we need to update and remove records!
  // However, there's a caveat: we're under tight constraints and may be running during a GC where we are forbidden
  // to do any more allocations. In certain situations, even calling ruby_xfree on an object_record may trigger
  // such allocations (https://github.com/ruby/ruby/blob/ffb1eb37e74334ae85d6bfee07d784a145e23dd8/gc.c#L12599).
  // We also do not want to risk triggering reentrant free sampling. Therefore, we take the extremely cautious
  // approach of enqueuing this free to be applied at next allocation recording or flush with no explicit heap
  // allocations or frees, direct or otherwise, happening during the execution of this method.
  enqueue_free(heap_recorder, obj);
}

void heap_recorder_flush(heap_recorder *heap_recorder) {
  ENFORCE_SUCCESS_GVL(pthread_mutex_lock(&heap_recorder->records_mutex));
  flush_queue(heap_recorder);
  ENFORCE_SUCCESS_GVL(pthread_mutex_unlock(&heap_recorder->records_mutex));
}

void heap_recorder_for_each_live_object(
    heap_recorder *heap_recorder,
    void (*for_each_callback)(heap_recorder_iteration_data stack_data, void *extra_arg),
    void *for_each_callback_extra_arg,
    bool with_gvl) {
  ENFORCE_SUCCESS_HELPER(pthread_mutex_lock(&heap_recorder->records_mutex), with_gvl);
  iteration_context context;
  context.for_each_callback = for_each_callback;
  context.for_each_callback_extra_arg = for_each_callback_extra_arg;
  context.heap_recorder = heap_recorder;
  st_foreach(heap_recorder->object_records, st_object_records_iterate, (st_data_t) &context);
  ENFORCE_SUCCESS_HELPER(pthread_mutex_unlock(&heap_recorder->records_mutex), with_gvl);
}

// ==========================
// Heap Recorder Internal API
// ==========================
static int st_heap_record_entry_free(st_data_t key, st_data_t value, st_data_t extra_arg) {
  heap_record_key *record_key = (heap_record_key*) key;
  heap_record_key_free(record_key);
  heap_record_free((heap_record *) value);
  return ST_DELETE;
}

static int st_object_record_entry_free(st_data_t key, st_data_t value, st_data_t extra_arg) {
  object_record_free((object_record *) value);
  return ST_DELETE;
}

// WARN: This can get called outside the GVL. NO HEAP ALLOCATIONS OR EXCEPTIONS ARE ALLOWED.
static int st_object_records_iterate(st_data_t key, st_data_t value, st_data_t extra) {
  object_record *record = (object_record*) value;
  const heap_stack *stack = record->heap_record->stack;
  iteration_context *context = (iteration_context*) extra;

  ddog_prof_Location *locations = context->heap_recorder->reusable_locations;

  for (uint64_t i = 0; i < stack->frames_len; i++) {
    heap_frame *frame = &stack->frames[i];
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

  context->for_each_callback(iteration_data, context->for_each_callback_extra_arg);

  return ST_CONTINUE;
}

// Struct holding data required for an update operation on heap_records
typedef struct {
  // [in] The stack this heap_record update operation is associated with
  // NOTE: Transfer of ownership is assumed, do not re-use it after call to ::update_object_record_entry
  object_record *new_object_record;

  // [in] The heap recorder where the update is happening
  heap_recorder *heap_recorder;
} object_record_update_data;

static int update_object_record_entry(st_data_t *key, st_data_t *value, st_data_t data, int existing) {
  object_record_update_data *update_data = (object_record_update_data*) data;
  if (existing) {
    // Object was already tracked. One of 3 things could have happened:
    //
    // 1. Ruby did some smart memory re-use.
    //    TODO: Research this case and document it.
    //
    // 2. We missed a free.
    //    TODO: Research this case and document it.
    //
    // 3. An unknown thing happened.
    //
    // Except for #3 where we're kinda screwed anyway, dropping the existing object record is
    // acceptable behaviour and is equivalent to treating this allocation as a combined
    // free+allocation.
    VALUE obj = (VALUE) (*key);
    object_record *existing_record = (object_record*) (*value);
    commit_free(update_data->heap_recorder, obj, existing_record);
  }
  // Always carry on with the update, we want the new record to be there at the end
  (*value) = (st_data_t) update_data->new_object_record;
  return ST_CONTINUE;
}

// WARN: Expects records_mutex to be held
static void commit_allocation_with_heap_record(heap_recorder *heap_recorder, heap_record *heap_record, VALUE obj, live_object_data object_data) {
  // Mark the heap record as having an extra tracked object linked to it
  // NOTE: Do this before the call to ::update_object_record_entry because that call could
  // be a bundled free+allocation and could thus lead to cleanup of this heap_record if
  // num_tracked_objects reached 0
  heap_record->num_tracked_objects++;
  // Then update object_records
  object_record_update_data update_data = (object_record_update_data) {
    .heap_recorder = heap_recorder,
    .new_object_record = object_record_new(obj, heap_record, object_data),
  };
  st_update(heap_recorder->object_records, obj, update_object_record_entry, (st_data_t) &update_data);
}

// Struct holding data required for an update operation on heap_records
typedef struct {
  // [in] The stack this heap_record update operation is associated with
  // NOTE: Transfer of ownership is assumed, do not re-use it after call to ::update_heap_record_entry_with_new_allocation
  heap_stack *stack;
  // [out] Pointer that will be updated to the updated heap record to prevent having to do
  // another lookup to access the updated heap record.
  heap_record **record;
} heap_record_update_data;

// This function assumes ownership of stack_data is passed on to it so it'll either transfer ownership or clean-up.
static int update_heap_record_entry_with_new_allocation(st_data_t *key, st_data_t *value, st_data_t data, int existing) {
  heap_record_update_data *update_data = (heap_record_update_data*) data;

  if (existing) {
    // there's already a heap_record matching the stack, lets just re-use it which means
    // we should free the stack
    heap_stack_free(update_data->stack);
  } else {
    // no matching heap record, lets allocate new heap_record_key and heap_record based on the stack
    // and transfer ownership to the hash
    (*key) = (st_data_t) heap_record_key_new(update_data->stack);
    (*value) = (st_data_t) heap_record_new(update_data->stack);
  }

  heap_record *record = (heap_record*) (*value);
  (*update_data->record) = record;

  return ST_CONTINUE;
}

// This version assumes that a new stack got created and there's an expectation of transfer of ownership of
// it to this function. For stack re-use you should be using ::commit_allocation_with_heap_record.
// WARN: Expects records_mutex to be held
static void commit_allocation_with_heap_stack(heap_recorder *heap_recorder, heap_stack *heap_stack, VALUE obj, live_object_data object_data) {
  // First lets update the heap_records with this stack info
  // NOTE: Using a stack-allocated key here for easy cleanup logic. The update function will create a heap-allocated key
  // if no matching heap_record exists.
  heap_record_key lookup_key = (heap_record_key) {
    .type = HEAP_STACK,
    .heap_stack = heap_stack,
  };
  heap_record *heap_record = NULL;
  heap_record_update_data update_data = (heap_record_update_data) {
    .stack = heap_stack,
    .record = &heap_record,
  };
  st_update(heap_recorder->heap_records, (st_data_t) &lookup_key, update_heap_record_entry_with_new_allocation, (st_data_t) &update_data);

  commit_allocation_with_heap_record(heap_recorder, heap_record, obj, object_data);
}

// Commits a free to our internal tracking structures.
//
// @param object_record
//   Pointer to a object_record that is in the process of being updated. If NULL, assume no
//   object_record is currently being updated so do it here. If not NULL, assume ownership
//   is passed to this function (where we'll free it).
//
// WARN: Expects records_mutex to be held
static void commit_free(heap_recorder *heap_recorder, VALUE obj, object_record *object_record) {
  if (object_record == NULL) {
    if (!st_delete(heap_recorder->object_records, (st_data_t*) &obj, (st_data_t*) &object_record)) {
      // This should not be possible since we're already checking for tracked objects during the free
      // tracepoint but just in case something bugs out, lets error out
      rb_raise(rb_eRuntimeError, "Committing free of untracked object");
    }
  }

  heap_record *heap_record = object_record->heap_record;
  heap_record->num_tracked_objects--;

  if (heap_record->num_tracked_objects == 0) {
    heap_record_key heap_key = (heap_record_key) {
      .type = HEAP_STACK,
      .heap_stack = heap_record->stack,
    };
    // We need to access the deleted key to free it since we gave ownership of the keys to the hash.
    // st_delete will change this pointer to point to the removed key if one is found.
    // NOTE: We don't do this above with the object_records delete because the VALUE keys are not
    // owned by us.
    heap_record_key *deleted_key = &heap_key;
    if (!st_delete(heap_recorder->heap_records, (st_data_t*) &deleted_key, NULL)) {
      rb_raise(rb_eRuntimeError, "Found an object record associated with an untracked heap_record");
    };
    heap_record_key_free(deleted_key);
    heap_record_free(heap_record);
  }

  object_record_free(object_record);
}

// WARN: Expects records_mutex to be held
static void flush_queue(heap_recorder *heap_recorder) {
  for (size_t i = 0; i < heap_recorder->queued_samples_len; i++) {
    uncommitted_sample *queued_sample = &heap_recorder->queued_samples[i];
    if (!queued_sample->skip) {
      if (queued_sample->free) {
        commit_free(heap_recorder, queued_sample->obj, NULL);
      } else {
        commit_allocation_with_heap_stack(heap_recorder, queued_sample->stack, queued_sample->obj, queued_sample->object_data);
      }
    }

    *queued_sample = (uncommitted_sample) {0};
  }
  heap_recorder->queued_samples_len = 0;
}

// WARN: This can get called during Ruby GC. NO HEAP ALLOCATIONS OR EXCEPTIONS ARE ALLOWED.
static void enqueue_sample(heap_recorder *heap_recorder, uncommitted_sample new_sample) {
  if (heap_recorder->queued_samples_len >= MAX_QUEUE_LIMIT) {
    // FIXME: If we're droppping a free sample here, the accuracy of our heap profiles will be affected.
    // Should we completely give up and stop sending heap profiles or should we trigger a flag that we
    // can then use to add a warning in the UI? At the very least we'd want telemetry here.
    return;
  }

  heap_recorder->queued_samples[heap_recorder->queued_samples_len] = new_sample;
  heap_recorder->queued_samples_len++;
}

static void enqueue_allocation(heap_recorder *heap_recorder, heap_stack *heap_stack, VALUE obj, live_object_data object_data) {
  enqueue_sample(heap_recorder, (uncommitted_sample) {
      .stack = heap_stack,
      .obj = obj,
      .object_data = object_data,
      .free = false,
      .skip = false,
  });
}

// WARN: This can get called during Ruby GC. NO HEAP ALLOCATIONS OR EXCEPTIONS ARE ALLOWED.
static void enqueue_free(heap_recorder *heap_recorder, VALUE obj) {
  enqueue_sample(heap_recorder, (uncommitted_sample) {
      .stack = NULL,
      .obj = obj,
      .object_data = {0},
      .free = true,
      .skip = false,
  });
}

// ===============
// Heap Record API
// ===============
heap_record* heap_record_new(heap_stack *stack) {
  heap_record* record = ruby_xcalloc(1, sizeof(heap_record));
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
object_record* object_record_new(VALUE new_obj, heap_record *heap_record, live_object_data object_data) {
  object_record* record = ruby_xcalloc(1, sizeof(object_record));
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

// WARN: Must be kept in-sync with ::char_slice_hash
st_index_t string_hash(char *str, st_index_t seed) {
  return st_hash(str, strlen(str), seed);
}

// WARN: Must be kept in-sync with ::ddog_location_hash
st_index_t heap_frame_hash(heap_frame *frame, st_index_t seed) {
  st_index_t hash = string_hash(frame->name, seed);
  hash = string_hash(frame->filename, hash);
  hash = st_hash(&frame->line, sizeof(frame->line), hash);
  return hash;
}

// WARN: Must be kept in-sync with ::string_hash
st_index_t char_slice_hash(ddog_CharSlice char_slice, st_index_t seed) {
  return st_hash(char_slice.ptr, char_slice.len, seed);
}

// WARN: Must be kept in-sync with ::heap_frame_hash
st_index_t ddog_location_hash(ddog_prof_Location location, st_index_t seed) {
  st_index_t hash = char_slice_hash(location.function.name, seed);
  hash = char_slice_hash(location.function.filename, hash);
  hash = st_hash(&location.line, sizeof(location.line), hash);
  return hash;
}


// ==============
// Heap Stack API
// ==============
heap_stack* heap_stack_new(ddog_prof_Slice_Location locations) {
  heap_stack *stack = ruby_xcalloc(1, sizeof(heap_stack));
  *stack = (heap_stack) {
    .frames = ruby_xcalloc(locations.len, sizeof(heap_frame)),
    .frames_len = locations.len,
  };
  for (uint64_t i = 0; i < locations.len; i++) {
    const ddog_prof_Location *location = &locations.ptr[i];
    stack->frames[i] = (heap_frame) {
      .name = ruby_strndup(location->function.name.ptr, location->function.name.len),
      .filename = ruby_strndup(location->function.filename.ptr, location->function.name.len),
      .line = location->line,
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
  ruby_xfree(stack->frames);
  ruby_xfree(stack);
}

int heap_stack_cmp(heap_stack *st1, heap_stack *st2) {
  if (st1->frames_len != st2->frames_len) {
    return (int) (st1->frames_len - st2->frames_len);
  }
  for (uint64_t i = 0; i < st1->frames_len; i++) {
    int cmp = heap_frame_cmp(&st1->frames[i], &st2->frames[i]);
    if (cmp != 0) {
      return cmp;
    }
  }
  return 0;
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

#include "heap_recorder.h"
#include <pthread.h>
#include "ruby/st.h"
#include "ruby/util.h"
#include "ruby_helpers.h"
#include <errno.h>

#define MAX_FRAMES_LIMIT 10000
#define MAX_QUEUE_LIMIT 10000

// Initial seed for hash functions
#define FNV1_32A_INIT 0x811c9dc5

typedef struct {
  char *name;
  char *filename;
  int64_t line;
} heap_frame;
static int heap_frame_cmp(heap_frame*, heap_frame*);
static st_index_t heap_frame_hash(heap_frame*, st_index_t seed);

typedef struct {
  heap_frame *frames;
  uint64_t frames_len;
  st_index_t hash;
  st_index_t hash_seed;
  bool hash_calculated;
} heap_stack;
static heap_stack* heap_stack_init(ddog_prof_Slice_Location);
static void heap_stack_free(heap_stack*);
void heap_stack_debug(const heap_stack*);
static int heap_stack_cmp(heap_stack*, heap_stack*);
static st_index_t heap_stack_hash(heap_stack*, st_index_t);
static int heap_stack_cmp_st(st_data_t, st_data_t);
static st_index_t heap_stack_hash_st(st_data_t);
static const struct st_hash_type st_hash_type_heap_stack = {
    heap_stack_cmp_st,
    heap_stack_hash_st,
};

typedef struct {
  // How many objects are currently tracked by the heap recorder for this heap record.
  uint64_t num_tracked_objects;
  // Estimate for how many objects are currently in use for this heap record.
  // (this is basically a sum of the weights of the num_tracked_objects)
  uint64_t inuse_objects;
  const heap_stack *stack;
} heap_record;
static heap_record* heap_record_init(const heap_stack*);
static void heap_record_free(heap_record*);

typedef struct {
  VALUE obj;
  unsigned int weight;
  heap_record *heap_record;
} object_record;
static object_record* object_record_init(VALUE, unsigned int, heap_record*);
static void object_record_free(object_record*);

typedef struct {
  VALUE obj;
  unsigned int weight;
} partial_heap_recording;

typedef struct sample {
  heap_stack *stack;
  VALUE obj;
  unsigned int weight;
  bool free;
  bool skip;
} sample;
const sample EmptySample = {0};

struct heap_recorder {
  // Map[heap_stack, heap_record]
  st_table *heap_records;

  // Map[obj, object_record]
  st_table *object_records;

  // Lock protecting writes to above record tables
  pthread_mutex_t records_mutex;

  // Data for a heap recording that was started but not yet ended
  partial_heap_recording active_recording;

  // Storage for queued samples built while samples are being taken but records_mutex is locked.
  // These will be flushed back to record tables on the next sample execution that can take
  // a write lock on heap_records
  sample *queued_samples;
  size_t queued_samples_len;

  // Reusable location array, implementing a flyweight pattern for things like iteration.
  ddog_prof_Location *reusable_locations;
};

// =================
// Heap Recorder API
// =================
heap_recorder* heap_recorder_init(void) {
  heap_recorder* recorder = ruby_xcalloc(1, sizeof(heap_recorder));

  recorder->records_mutex = (pthread_mutex_t) PTHREAD_MUTEX_INITIALIZER;
  recorder->heap_records = st_init_table(&st_hash_type_heap_stack);
  recorder->object_records = st_init_numtable();
  recorder->reusable_locations = ruby_xcalloc(MAX_FRAMES_LIMIT, sizeof(ddog_prof_Location));
  recorder->queued_samples = ruby_xcalloc(MAX_QUEUE_LIMIT, sizeof(sample));
  recorder->queued_samples_len = 0;

  return recorder;
}

int st_record_table_entry_free(st_data_t key, st_data_t value, st_data_t extra_arg) {
  heap_stack_free((heap_stack *) key);
  heap_record_free((heap_record *) value);
  return ST_DELETE;
}

int st_object_table_entry_free(st_data_t key, st_data_t value, st_data_t extra_arg) {
  object_record_free((object_record *) value);
  return ST_DELETE;
}

void heap_recorder_free(struct heap_recorder* recorder) {
  st_foreach(recorder->object_records, st_object_table_entry_free, 0);
  st_free_table(recorder->object_records);

  st_foreach(recorder->heap_records, st_record_table_entry_free, 0);
  st_free_table(recorder->heap_records);

  pthread_mutex_destroy(&recorder->records_mutex);

  ruby_xfree(recorder->reusable_locations);
  ruby_xfree(recorder->queued_samples);

  ruby_xfree(recorder);
}

typedef struct {
  void (*for_each_callback)(stack_iteration_data stack_data, void *extra_arg);
  void *for_each_callback_extra_arg;
  heap_recorder *heap_recorder;
} internal_iteration_data;

static int st_heap_records_iterate(st_data_t key, st_data_t value, st_data_t extra) {
  heap_stack *stack = (heap_stack*) key;
  heap_record *record = (heap_record*) value;
  internal_iteration_data *iteration_data = (internal_iteration_data*) extra;

  ddog_prof_Location *locations = iteration_data->heap_recorder->reusable_locations;

  for (uint64_t i = 0; i < stack->frames_len; i++) {
    heap_frame *frame = &stack->frames[i];
    ddog_prof_Location *location = &locations[i];
    location->function.name.ptr = frame->name;
    location->function.name.len = strlen(frame->name);
    location->function.filename.ptr = frame->filename;
    location->function.filename.len = strlen(frame->filename);
    location->line = frame->line;
  }

  stack_iteration_data stack_data;
  stack_data.inuse_objects = record->inuse_objects;
  stack_data.locations = (ddog_prof_Slice_Location) {.ptr = locations, .len = stack->frames_len};

  iteration_data->for_each_callback(stack_data, iteration_data->for_each_callback_extra_arg);

  return ST_CONTINUE;
}

void heap_recorder_iterate_stacks_without_gvl(heap_recorder *heap_recorder, void (*for_each_callback)(stack_iteration_data stack_data, void *extra_arg), void *for_each_callback_extra_arg) {
  ENFORCE_SUCCESS_NO_GVL(pthread_mutex_lock(&heap_recorder->records_mutex));
  internal_iteration_data internal_iteration_data;
  internal_iteration_data.for_each_callback = for_each_callback;
  internal_iteration_data.for_each_callback_extra_arg = for_each_callback_extra_arg;
  internal_iteration_data.heap_recorder = heap_recorder;
  st_foreach(heap_recorder->heap_records, st_heap_records_iterate, (st_data_t) &internal_iteration_data);
  ENFORCE_SUCCESS_NO_GVL(pthread_mutex_unlock(&heap_recorder->records_mutex));
}

void commit_allocation(heap_recorder *heap_recorder, heap_stack *heap_stack, VALUE obj, unsigned int weight) {
  heap_record *heap_record = NULL;
  if (!st_lookup(heap_recorder->heap_records, (st_data_t) heap_stack, (st_data_t*) &heap_record)) {
    heap_record = heap_record_init(heap_stack);
    if (st_insert(heap_recorder->heap_records, (st_data_t) heap_stack, (st_data_t) heap_record)) {
      // This should not be possible but just in case something bugs out, lets error out
      rb_raise(rb_eRuntimeError, "Duplicate heap stack tracking: %p", heap_stack);
    };
  } else {
    // FIXME: Figure out a way to not have to instantiate a new stack only to free it if it's
    // already sampled. Something like supporting indexing the heap_records table with
    // ddog_prof_Slice_Location objects directly for instance.
    heap_stack_free(heap_stack);
  }

  object_record *object_record = object_record_init(obj, weight, heap_record);
  if (st_insert(heap_recorder->object_records, (st_data_t) obj, (st_data_t) object_record) != 0) {
    // Object already tracked?
    // FIXME: This seems to happen in practice. Research how/why and handle differently.
    object_record_free(object_record);
    rb_raise(rb_eRuntimeError, "Duplicate heap object tracking: %lu", obj);
  }

  fprintf(stderr, "Committed allocation of %lu (heap_record=%p, object_record=%p)\n", obj, heap_record, object_record);

  heap_record->num_tracked_objects++;
  heap_record->inuse_objects += weight;
}

void commit_free(heap_recorder *heap_recorder, VALUE obj) {
  st_data_t key = (st_data_t) obj;
  object_record *object_record = NULL;
  if (!st_delete(heap_recorder->object_records, (st_data_t*) &key, (st_data_t*) &object_record)) {
    // This should not be possible since we're already checking for tracked objects during the free
    // tracepoint but just in case something bugs out, lets error out
    rb_raise(rb_eRuntimeError, "Committing free of untracked object");
  }

  heap_record *heap_record = object_record->heap_record;
  heap_record->num_tracked_objects--;
  heap_record->inuse_objects -= object_record->weight;

  fprintf(stderr, "Committed free of %lu (heap_record=%p, object_record=%p)\n", obj, heap_record, object_record);

  object_record_free(object_record);
}

// NOTE: Must be holding the records_mutex lock
static void flush_queue(heap_recorder *heap_recorder) {
  for (size_t i = 0; i < heap_recorder->queued_samples_len; i++) {
    sample *queued_sample = &heap_recorder->queued_samples[i];
    if (!queued_sample->skip) {
      fprintf(stderr, "Flushing sample %p\n", queued_sample);

      if (queued_sample->free) {
        commit_free(heap_recorder, queued_sample->obj);
      } else {
        commit_allocation(heap_recorder, queued_sample->stack, queued_sample->obj, queued_sample->weight);
      }
    }

    *queued_sample = EmptySample;
  }
  heap_recorder->queued_samples_len = 0;
}

void heap_recorder_flush(heap_recorder *heap_recorder) {
  int error = pthread_mutex_lock(&heap_recorder->records_mutex);
  if (!error) {
    // We were able to get a lock to heap_records so lets flush any pending samples
    // that might have been queued previously before adding this new one.
    flush_queue(heap_recorder);
  } else {
    ENFORCE_SUCCESS_GVL(error)
    return;
  }

  pthread_mutex_unlock(&heap_recorder->records_mutex);
}

// Safety: This function may get called while Ruby is doing garbage collection. While Ruby is doing garbage collection,
// *NO ALLOCATION* is allowed. This function, and any it calls must never trigger memory or object allocation.
// This includes exceptions and use of ruby_xcalloc (because xcalloc can trigger GC)!
static void enqueue_sample(heap_recorder *heap_recorder, sample new_sample) {
  fprintf(stderr, "Enqueuing sample for %lu (weight=%u free=%i)\n", new_sample.obj, new_sample.weight, new_sample.free);
  if (heap_recorder->queued_samples_len >= MAX_QUEUE_LIMIT) {
    // FIXME: If we're droppping a free sample here, the accuracy of our heap profiles will be affected.
    // Should we completely give up or should we trigger a flag that we can then use to add a warning in the UI?
    fprintf(stderr, "Dropping sample on the floor.\n");
    return;
  }

  heap_recorder->queued_samples[heap_recorder->queued_samples_len] = new_sample;
  heap_recorder->queued_samples_len++;
}

static void enqueue_allocation(heap_recorder *heap_recorder, heap_stack *heap_stack, VALUE obj, unsigned int weight) {
  enqueue_sample(heap_recorder, (sample) {
      .stack = heap_stack,
      .obj = obj,
      .weight = weight,
      .free = false,
      .skip = false,
  });
}

// Safety: This function may get called while Ruby is doing garbage collection. While Ruby is doing garbage collection,
// *NO ALLOCATION* is allowed. This function, and any it calls must never trigger memory or object allocation.
// This includes exceptions and use of ruby_xcalloc (because xcalloc can trigger GC)!
static void enqueue_free(heap_recorder *heap_recorder, VALUE obj) {
  enqueue_sample(heap_recorder, (sample) {
      .stack = NULL,
      .obj = obj,
      .weight = 0,
      .free = true,
      .skip = false,
  });
}

void start_heap_allocation_recording(heap_recorder* heap_recorder, VALUE new_obj, unsigned int weight) {
  fprintf(stderr, "Started recording allocation of %lu with weight %u\n", new_obj, weight);
  heap_recorder->active_recording = (partial_heap_recording) {
    .obj = new_obj,
    .weight = weight,
  };
}

void end_heap_allocation_recording(struct heap_recorder *heap_recorder, ddog_prof_Slice_Location locations) {
  partial_heap_recording *active_recording = &heap_recorder->active_recording;

  VALUE new_obj = active_recording->obj;
  if (!new_obj) {
    // Recording ended without having been started?
    rb_raise(rb_eRuntimeError, "Ended a heap recording that was not started");
  }

  int weight = active_recording->weight;

  // From now on, mark active recording as invalid so we can short-circuit at any point and
  // not end up with a still active recording. new_obj still holds the object for this recording
  active_recording->obj = Qnil;

  heap_stack *heap_stack = heap_stack_init(locations);
  int error = pthread_mutex_trylock(&heap_recorder->records_mutex);
  if (error) {
    // We weren't able to get a lock, so enqueue this sample for later processing
    // and end early
    if (error == EBUSY) {
      enqueue_allocation(heap_recorder, heap_stack, new_obj, weight);
    } else {
      ENFORCE_SUCCESS_GVL(error)
    }
    return;
  }

  // We were able to get a lock to heap_records so lets flush any pending samples
  // that might have been queued previously before adding this new one.
  flush_queue(heap_recorder);

  // And then add the new allocation
  commit_allocation(heap_recorder, heap_stack, new_obj, weight);

  ENFORCE_SUCCESS_GVL(pthread_mutex_unlock(&heap_recorder->records_mutex));
}

// Safety: This function can get called while Ruby is doing garbage collection. While Ruby is doing garbage collection,
// *NO ALLOCATION* is allowed. This function, and any it calls must never trigger memory or object allocation.
// This includes exceptions and use of ruby_xcalloc (because xcalloc can trigger GC)!
void record_heap_free(heap_recorder *heap_recorder, VALUE obj) {
  object_record *object_record = NULL;
  // lookups require hashing and traversal over hash buckets but should not require doing any allocations
  // and should thus be safe to run in GC.
  st_lookup(heap_recorder->object_records, (st_data_t) obj, (st_data_t*) &object_record);

  if (object_record == NULL) {
    // we don't seem to be tracking this object on the table atm
    // check if the allocation sample is in the queue
    for (size_t i = 0; i < heap_recorder->queued_samples_len; i++) {
      sample *queued_sample = &heap_recorder->queued_samples[i];
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

// ===============
// Heap Record API
// ===============
heap_record* heap_record_init(const heap_stack *stack) {
  heap_record* record = ruby_xcalloc(1, sizeof(heap_record));
  record->num_tracked_objects = 0;
  record->inuse_objects = 0;
  record->stack = stack;
  return record;
}

void heap_record_free(heap_record *record) {
  ruby_xfree(record);
}


// =================
// Object Record API
// =================
object_record* object_record_init(VALUE new_obj, unsigned int weight, heap_record *heap_record) {
  object_record* record = ruby_xcalloc(1, sizeof(object_record));
  record->weight = weight;
  record->heap_record = heap_record;
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

st_index_t string_hash(char *str, st_index_t seed) {
  return st_hash(str, strlen(str), seed);
}

st_index_t heap_frame_hash(heap_frame *frame, st_index_t seed) {
  st_index_t hash = string_hash(frame->name, seed);
  hash = string_hash(frame->filename, hash);
  hash = st_hash(&frame->line, sizeof(frame->line), hash);
  return hash;
}

// Important: This should match string_hash behaviour
st_index_t char_slice_hash(ddog_CharSlice char_slice, st_index_t seed) {
  return st_hash(char_slice.ptr, char_slice.len, seed);
}

// ==============
// Heap Stack API
// ==============
heap_stack* heap_stack_init(ddog_prof_Slice_Location locations) {
  heap_stack *stack = ruby_xcalloc(1, sizeof(heap_stack));
  *stack = (heap_stack) {
    .frames = ruby_xcalloc(locations.len, sizeof(heap_frame)),
    .frames_len = locations.len,
    .hash = 0,
    .hash_seed = 0,
    .hash_calculated = false
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

void heap_stack_debug(const heap_stack *stack) {
  fprintf(stderr, "stack {\n");
  for (uint64_t i = 0; i < stack->frames_len; i++) {
    heap_frame *frame = &stack->frames[i];
    fprintf(stderr, "  frame {\n");
    fprintf(stderr, "    name: '%s'\n", frame->name);
    fprintf(stderr, "    filename: '%s'\n", frame->filename);
    fprintf(stderr, "    line: %lli\n", frame->line);
    fprintf(stderr, "  }\n");
  }
  fprintf(stderr, "}\n");
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

int heap_stack_cmp_st(st_data_t key1, st_data_t key2) {
  return heap_stack_cmp((heap_stack *) key1, (heap_stack *) key2);
}

st_index_t heap_stack_hash(heap_stack *stack, st_index_t seed) {
  if (stack->hash_calculated && stack->hash_seed == seed) {
    // fast path, hash is already known
    return stack->hash;
  }

  st_index_t hash = seed;
  for (uint64_t i = 0; i < stack->frames_len; i++) {
    hash = heap_frame_hash(&stack->frames[i], hash);
  }
  return hash;
}

st_index_t heap_stack_hash_st(st_data_t key) {
  return heap_stack_hash((heap_stack *) key, FNV1_32A_INIT);
}

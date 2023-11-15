#include "heap_recorder.h"
#include <pthread.h>
#include "ruby/st.h"
#include "ruby/util.h"
#include "ruby_helpers.h"
#include <errno.h>

// This is not part of public headers but is in a RUBY_SYMBOL_EXPORT block
size_t rb_obj_memsize_of(VALUE obj);

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
  ddog_CharSlice *class_name;
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
  // Config
  bool enable_heap_size_profiling;

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
heap_recorder* heap_recorder_init(bool enable_heap_size_profiling) {
  heap_recorder* recorder = ruby_xcalloc(1, sizeof(heap_recorder));

  recorder->enable_heap_size_profiling = enable_heap_size_profiling;
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

static ddog_prof_Slice_Location reusableLocationsFromStack(heap_recorder *heap_recorder, const heap_stack *stack) {
  ddog_prof_Location *locations = heap_recorder->reusable_locations;

  for (uint64_t i = 0; i < stack->frames_len; i++) {
    heap_frame *frame = &stack->frames[i];
    ddog_prof_Location *location = &locations[i];
    location->function.name.ptr = frame->name;
    location->function.name.len = strlen(frame->name);
    location->function.filename.ptr = frame->filename;
    location->function.filename.len = strlen(frame->filename);
    location->line = frame->line;
  }

  return (ddog_prof_Slice_Location) {.ptr = locations, .len = stack->frames_len};
}

static int st_heap_records_iterate(st_data_t key, st_data_t value, st_data_t extra) {
  heap_stack *stack = (heap_stack*) key;
  heap_record *record = (heap_record*) value;
  internal_iteration_data *iteration_data = (internal_iteration_data*) extra;

  stack_iteration_data stack_data = {
    .inuse_objects = record->inuse_objects,
    .inuse_size = 0,
    .locations = reusableLocationsFromStack(iteration_data->heap_recorder, stack),
  };

  iteration_data->for_each_callback(stack_data, iteration_data->for_each_callback_extra_arg);

  return ST_CONTINUE;
}

static int st_object_records_iterate(st_data_t key, st_data_t value, st_data_t extra) {
  VALUE obj = (VALUE) key;
  object_record *record = (object_record*) value;
  internal_iteration_data *iteration_data = (internal_iteration_data*) extra;

  stack_iteration_data stack_data = {
    .inuse_objects = record->weight,
    .inuse_size = rb_obj_memsize_of(obj),
    .locations = reusableLocationsFromStack(iteration_data->heap_recorder, record->heap_record->stack),
  };

  iteration_data->for_each_callback(stack_data, iteration_data->for_each_callback_extra_arg);

  return ST_CONTINUE;
}

void heap_recorder_iterate_stacks(heap_recorder *heap_recorder, void (*for_each_callback)(stack_iteration_data stack_data, void *extra_arg), void *for_each_callback_extra_arg) {
  pthread_mutex_lock(&heap_recorder->records_mutex);
  internal_iteration_data internal_iteration_data;
  internal_iteration_data.for_each_callback = for_each_callback;
  internal_iteration_data.for_each_callback_extra_arg = for_each_callback_extra_arg;
  internal_iteration_data.heap_recorder = heap_recorder;
  if (heap_recorder->enable_heap_size_profiling) {
    // To get an accurate object size, we need to query our tracked live objects so lets iterate over the object_records
    st_foreach(heap_recorder->object_records, st_object_records_iterate, (st_data_t) &internal_iteration_data);
  } else {
    // If we're just reporting heap counts/samples, it's faster to iterate on the heap records
    st_foreach(heap_recorder->heap_records, st_heap_records_iterate, (st_data_t) &internal_iteration_data);
  }
  pthread_mutex_unlock(&heap_recorder->records_mutex);
}

void commit_allocation(heap_recorder *heap_recorder, heap_stack *heap_stack, VALUE obj, unsigned int weight) {
  heap_record *heap_record = NULL;
  if (!st_lookup(heap_recorder->heap_records, (st_data_t) heap_stack, (st_data_t*) &heap_record)) {
    heap_record = heap_record_init(heap_stack);
    if (st_insert(heap_recorder->heap_records, (st_data_t) heap_stack, (st_data_t) heap_record)) {
      rb_raise(rb_eRuntimeError, "Duplicate heap stack tracking: %p", heap_stack);
      return;
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
    object_record_free(object_record);
    rb_raise(rb_eRuntimeError, "Duplicate heap object tracking: %lu", obj);
    return;
  }

  fprintf(stderr, "Committed allocation of %lu (heap_record=%p, object_record=%p)\n", obj, heap_record, object_record);

  heap_record->num_tracked_objects++;
  heap_record->inuse_objects += weight;
}

void commit_free(heap_recorder *heap_recorder, VALUE obj) {
  st_data_t key = (st_data_t) obj;
  object_record *object_record = NULL;
  if (!st_delete(heap_recorder->object_records, (st_data_t*) &key, (st_data_t*) &object_record)) {
    // Object not tracked?
    rb_raise(rb_eRuntimeError, "Committing free of untracked object");
    return;
  }

  heap_record *heap_record = object_record->heap_record;
  heap_record->num_tracked_objects--;
  heap_record->inuse_objects -= object_record->weight;

  fprintf(stderr, "Committed free of %lu (heap_record=%p, object_record=%p)\n", obj, heap_record, object_record);

  object_record_free(object_record);
}

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

static void enqueue_sample(heap_recorder *heap_recorder, sample new_sample) {
  fprintf(stderr, "Enqueuing sample for %lu (weight=%u free=%i)\n", new_sample.obj, new_sample.weight, new_sample.free);
  if (heap_recorder->queued_samples_len >= MAX_QUEUE_LIMIT) {
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

static void enqueue_free(heap_recorder *heap_recorder, VALUE obj) {
  enqueue_sample(heap_recorder, (sample) {
      .stack = NULL,
      .obj = obj,
      .weight = 0,
      .free = true,
      .skip = false,
  });
}

void start_heap_allocation_recording(heap_recorder* heap_recorder, VALUE new_obj, unsigned int weight, ddog_CharSlice *class_name) {
  fprintf(stderr, "Started recording allocation of %lu with weight %u\n", new_obj, weight);
  partial_heap_recording *active_recording = &heap_recorder->active_recording;
  active_recording->obj = new_obj;
  active_recording->weight = weight;
  active_recording->class_name = class_name;
}

void end_heap_allocation_recording(struct heap_recorder *heap_recorder, ddog_prof_Slice_Location locations) {
  // TODO: Make use of active_recording->class_name
  partial_heap_recording *active_recording = &heap_recorder->active_recording;

  VALUE new_obj = active_recording->obj;
  if (!new_obj) {
    // Recording ended without having been started?
    rb_raise(rb_eRuntimeError, "Ended a heap recording that was not started");
    return;
  }

  int weight = active_recording->weight;

  // From now on, mark active recording as invalid so we can short-circuit at any point and
  // not end up with a still active recording. new_obj still holds the object for this recording
  active_recording->obj = 0;

  heap_stack *heap_stack = heap_stack_init(locations);
  int error = pthread_mutex_trylock(&heap_recorder->records_mutex);
  if (!error) {
    // We were able to get a lock to heap_records so lets flush any pending samples
    // that might have been queued previously before adding this new one.
    flush_queue(heap_recorder);
  } else {
    // We weren't able to get a lock, so enqueue this sample for later processing
    // and end early
    if (error == EBUSY) {
      enqueue_allocation(heap_recorder, heap_stack, new_obj, weight);
    } else {
      ENFORCE_SUCCESS_GVL(error)
    }
    return;
  }

  // If we got this far, we got a write lock so we can commit the record
  commit_allocation(heap_recorder, heap_stack, new_obj, weight);

  pthread_mutex_unlock(&heap_recorder->records_mutex);
}

void record_heap_free(heap_recorder *heap_recorder, VALUE obj) {
  object_record *object_record = NULL;
  st_lookup(heap_recorder->object_records, (st_data_t) obj, (st_data_t*) &object_record);

  if (object_record == NULL) {
    // we don't seem to be tracking this object on the table atm
    // check if the allocation sample is in the queue
    for (size_t i = 0; i < heap_recorder->queued_samples_len; i++) {
      sample *queued_sample = &heap_recorder->queued_samples[i];
      if (queued_sample->obj == obj) {
        queued_sample->skip = true;
        break;
      }
    }

    // free of an untracked object, return early
    return;
  }

  // if we got this far, we freed a tracked object so need to update records!
  int error = pthread_mutex_trylock(&heap_recorder->records_mutex);
  if (error) {
    // We weren't able to get a lock, so enqueue this sample for later processing
    // and exit early
    if (error == EBUSY) {
      enqueue_free(heap_recorder, obj);
    } else {
      ENFORCE_SUCCESS_GVL(error)
    }
    return;
  }

  // If we got this far, we got a write lock so we can commit the record
  commit_free(heap_recorder, obj);

  pthread_mutex_unlock(&heap_recorder->records_mutex);
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
  int cmp = strcmp(f1->name, f2->name);
  if (cmp != 0) {
    return cmp;
  }
  cmp = strcmp(f1->filename, f2->filename);
  if (cmp != 0) {
    return cmp;
  }
  return (int) (f1->line - f2->line);
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
  stack->frames = ruby_xcalloc(locations.len, sizeof(heap_frame));
  stack->frames_len = locations.len;
  for (uint64_t i = 0; i < locations.len; i++) {
    const ddog_prof_Location *location = &locations.ptr[i];
    heap_frame *frame = &stack->frames[i];
    frame->name = ruby_strdup(location->function.name.ptr);
    frame->filename = ruby_strdup(location->function.filename.ptr);
    frame->line = location->line;
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
  st_index_t hash = seed;
  for (uint64_t i = 0; i < stack->frames_len; i++) {
    hash = heap_frame_hash(&stack->frames[i], hash);
  }
  return hash;
}

st_index_t heap_stack_hash_st(st_data_t key) {
  return heap_stack_hash((heap_stack *) key, FNV1_32A_INIT);
}

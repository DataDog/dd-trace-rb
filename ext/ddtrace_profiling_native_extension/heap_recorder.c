#include "heap_recorder.h"
#include <pthread.h>
#include "ruby/st.h"
#include "ruby/util.h"
#include "ruby_helpers.h"
#include <errno.h>

// Allows storing data passed to ::start_heap_allocation_recording to make it accessible to
// ::end_heap_allocation_recording.
//
// obj != Qnil flags this struct as holding a valid partial heap recording.
typedef struct {
  VALUE obj;
  live_object_data object_data;
} partial_heap_recording;

struct heap_recorder {
  // Data for a heap recording that was started but not yet ended
  partial_heap_recording active_recording;
};

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
  heap_recorder* recorder = ruby_xmalloc(sizeof(heap_recorder));

  recorder->active_recording = (partial_heap_recording) {
    .obj = Qnil,
    .object_data = {0},
  };

  return recorder;
}

void heap_recorder_free(struct heap_recorder* recorder) {
  if (recorder == NULL) {
    return;
  }

  ruby_xfree(recorder);
}

// TODO: Remove when things get implemented
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wunused-parameter"

void heap_recorder_after_fork(heap_recorder *heap_recorder) {
  if (heap_recorder == NULL) {
    return;
  }

  // TODO: Implement
}

void start_heap_allocation_recording(heap_recorder *heap_recorder, VALUE new_obj, unsigned int weight) {
  if (heap_recorder == NULL) {
    return;
  }

  heap_recorder->active_recording = (partial_heap_recording) {
    .obj = new_obj,
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

  VALUE new_obj = active_recording->obj;
  if (new_obj == Qnil) {
    // Recording ended without having been started?
    rb_raise(rb_eRuntimeError, "Ended a heap recording that was not started");
  }

  // From now on, mark active recording as invalid so we can short-circuit at any point and
  // not end up with a still active recording. new_obj still holds the object for this recording
  active_recording->obj = Qnil;

  // TODO: Implement
}

void heap_recorder_flush(heap_recorder *heap_recorder) {
  if (heap_recorder == NULL) {
    return;
  }

  // TODO: Implement
}

// WARN: If with_gvl = False, NO HEAP ALLOCATIONS, EXCEPTIONS or RUBY CALLS ARE ALLOWED.
void heap_recorder_for_each_live_object(
    heap_recorder *heap_recorder,
    bool (*for_each_callback)(heap_recorder_iteration_data stack_data, void *extra_arg),
    void *for_each_callback_extra_arg,
    bool with_gvl) {
  if (heap_recorder == NULL) {
    return;
  }

  // TODO: Implement
}

// TODO: Remove when things get implemented
#pragma GCC diagnostic pop

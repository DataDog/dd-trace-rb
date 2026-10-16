#include <ruby.h>

#include "buffer_marking.h"
#include "../private_vm_api_access.h"
#include "../setup_signal_handler.h"

_Static_assert(
  offsetof(miteruby_event_stack_sample_t, thread.value) + sizeof(VALUE) ==
    offsetof(miteruby_event_stack_sample_t, refs),
  "Bulk marking requires frame references immediately after thread.value"
);
_Static_assert(
  offsetof(miteruby_event_frame_refs_t, cme) == 0 &&
    offsetof(miteruby_event_frame_refs_t, iseq) == sizeof(VALUE) &&
    sizeof(miteruby_event_frame_refs_t) == 2 * sizeof(VALUE),
  "Bulk marking requires contiguous VALUE-sized frame references without padding"
);

static size_t miteruby_buffer_size(const void *buffer) {
  (void)buffer;
  return sizeof(miteruby_buffer_t);
}

static void miteruby_buffer_mark_event(const uint64_t *data) {
  const miteruby_event_stack_sample_t *event = (const miteruby_event_stack_sample_t *)data;
  if (event->header.type != MITERUBY_EVENT_STACK_SAMPLE) return;

  // Assumes thread.value and all frame references form contiguous VALUE-sized slots without padding.
  // The static assertions above make incompatible layout changes fail compilation.
  rb_gc_mark_locations(&event->thread.value, (const VALUE *)&event->refs[event->header.frame_count]);
}

static void miteruby_buffer_mark(void *buffer) {
  // NOTE: ObjectSpace can also invoke dmark outside GC, where the signal handler would otherwise try to take our lock.
  //       Hence we mask out the signal as well during marking, even though the signal handler shouldn't try to push
  //       on the buffer in the middle of GC.
  miteruby_buffer_visit(buffer, miteruby_buffer_mark_event, &sigprof_signal_mask);
}

static const rb_data_type_t miteruby_buffer_typed_data = {
  .wrap_struct_name = "Datadog::Profiling::Miteruby::Buffer",
  .function = {
    .dmark = miteruby_buffer_mark,
    .dfree = NULL, // The buffer has static storage owned by cpu_and_wall_time_worker.
    .dsize = miteruby_buffer_size,
  },
};

void miteruby_buffer_marking_init(miteruby_buffer_t *buffer) {
  VALUE wrapper = TypedData_Wrap_Struct(rb_cObject, &miteruby_buffer_typed_data, buffer);
  // TODO: Make buffer be collectable when profiling disabled
  rb_gc_register_mark_object(wrapper);
}

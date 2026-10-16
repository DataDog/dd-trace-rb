#include <ruby.h>

#include "buffer_marking.h"

static const rb_data_type_t miteruby_buffer_typed_data = {
  .wrap_struct_name = "Datadog::Profiling::Miteruby::Buffer",
  .function = {
    .dmark = NULL,
    .dfree = NULL, // The buffer has static storage owned by cpu_and_wall_time_worker.
    .dsize = NULL,
  },
};

void miteruby_buffer_marking_init(miteruby_buffer_t *buffer) {
  VALUE wrapper = TypedData_Wrap_Struct(rb_cObject, &miteruby_buffer_typed_data, buffer);
  // TODO: Make buffer be collectable when profiling disabled
  rb_gc_register_mark_object(wrapper);
}

#include <ruby.h>

static VALUE _native_start(VALUE self);
static VALUE _native_stop(VALUE self);

static FILE* output_file = NULL;

void gvl_tracing_init(VALUE profiling_module) {
  VALUE gvl_tracing_class = rb_define_class_under(profiling_module, "GvlTracing", rb_cObject);

  rb_define_singleton_method(gvl_tracing_class, "_native_start", _native_start, 0);
  rb_define_singleton_method(gvl_tracing_class, "_native_stop", _native_stop, 0);
}

static VALUE _native_start(VALUE self) {
  if (output_file != NULL) {
    rb_raise(rb_eRuntimeError, "Already started");
  }

  output_file = fopen("gvl_tracing_out.json", "w");
  if (output_file == NULL) {
    rb_raise(rb_eRuntimeError, "Failed to open file");
  }

  fprintf(output_file, "[\n");

  return Qtrue;
}

static VALUE _native_stop(VALUE self) {
  if (output_file == NULL) {
    rb_raise(rb_eRuntimeError, "Not started");
  }

  fprintf(output_file, "  []\n]\n");
  fclose(output_file);

  return Qtrue;
}

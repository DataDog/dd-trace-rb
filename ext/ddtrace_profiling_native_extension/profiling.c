#include <ruby.h>
#include <ruby/debug.h>

#define MAX_STACK_DEPTH 400 // FIXME: Need to handle when this is not enough

static VALUE native_working_p(VALUE self);
static VALUE sample_threads(VALUE self);
static VALUE sample_thread(VALUE thread);
static VALUE to_sample(int frames_count, VALUE* frames, int* lines);

int borrowed_from_ruby_sources_rb_profile_frames(VALUE thread, int start, int limit, VALUE *buff, int *lines);
VALUE thread_id_for(VALUE thread);

void Init_ddtrace_profiling_native_extension(void) {
  VALUE datadog_module = rb_define_module("Datadog");
  VALUE profiling_module = rb_define_module_under(datadog_module, "Profiling");
  VALUE native_extension_module = rb_define_module_under(profiling_module, "NativeExtension");

  rb_define_singleton_method(native_extension_module, "native_working?", native_working_p, 0);
  rb_funcall(native_extension_module, rb_intern("private_class_method"), 1, ID2SYM(rb_intern("native_working?")));

  rb_define_singleton_method(native_extension_module, "sample_threads", sample_threads, 0);
}

static VALUE native_working_p(VALUE self) {
  return Qtrue;
}

static VALUE sample_threads(VALUE self) {
  if (!ruby_thread_has_gvl_p()) {
    rb_fatal("Expected to have GVL");
  }

  VALUE threads = rb_funcall(rb_cThread, rb_intern("list"), 0);
  VALUE samples = rb_ary_new();

  for (int i = 0; i < RARRAY_LEN(threads); i++) {
    VALUE thread = RARRAY_AREF(threads, i);
    VALUE result = sample_thread(thread);

    rb_ary_push(samples, result);
  }

  return samples;
}

static VALUE sample_thread(VALUE thread) {
  VALUE frames[MAX_STACK_DEPTH];
  int lines[MAX_STACK_DEPTH];

  int stack_depth = borrowed_from_ruby_sources_rb_profile_frames(thread, 0, MAX_STACK_DEPTH, frames, lines);
  VALUE stack = to_sample(stack_depth, frames, lines);
  VALUE thread_id = thread_id_for(thread);

  return rb_ary_new_from_args(4, thread, INT2FIX(stack_depth), stack, thread_id);
}


static VALUE to_sample(int frames_count, VALUE* frames, int* lines) {
  VALUE result = rb_ary_new();

  for (int i = 0; i < frames_count; i++) {
    rb_ary_push(result,
      rb_ary_new_from_args(3, rb_profile_frame_path(frames[i]), rb_profile_frame_full_label(frames[i]), INT2FIX(lines[i]))
    );
  }

  return result;
}

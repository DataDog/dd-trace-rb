#include <ruby.h>
#include <ddprof/ffi.h>

// TODO BETTER DESCRIPTION
// This file implements the native bits of the Datadog::Profiling::Collectors::Stack class

static VALUE ok_symbol = Qnil; // :ok in Ruby
static VALUE error_symbol = Qnil; // :error in Ruby

#define slice_char_from_literal(string) ((ddprof_ffi_Slice_c_char) {.ptr = "" string, .len = sizeof("" string) - 1})

#define CPU_TIME_VALUE {.type_ = slice_char_from_literal("cpu-time"), .unit = slice_char_from_literal("nanoseconds")}
#define CPU_SAMPLES_VALUE {.type_ = slice_char_from_literal("cpu-samples"), .unit = slice_char_from_literal("count")}
#define WALL_TIME_VALUE {.type_ = slice_char_from_literal("wall-time"), .unit = slice_char_from_literal("nanoseconds")}
#define ALLOC_SAMPLES_VALUE {.type_ = slice_char_from_literal("alloc-samples"), .unit = slice_char_from_literal("count")}
#define ALLOC_SPACE_VALUE {.type_ = slice_char_from_literal("alloc-space"), .unit = slice_char_from_literal("bytes")}
#define HEAP_SPACE_VALUE {.type_ = slice_char_from_literal("heap-space"), .unit = slice_char_from_literal("bytes")}

const static ddprof_ffi_ValueType enabled_value_types[] = {ALLOC_SAMPLES_VALUE, ALLOC_SPACE_VALUE, HEAP_SPACE_VALUE};

static VALUE collectors_stack_class = Qnil;

static VALUE _native_new(VALUE klass);
static void collectors_stack_ddprof_ffi_Profile_free(void *data);
static VALUE _native_serialize(VALUE self, VALUE stack_instance);

void collectors_stack_init(VALUE profiling_module) {
  VALUE collectors_module = rb_define_module_under(profiling_module, "Collectors");
  collectors_stack_class = rb_define_class_under(collectors_module, "Stack", rb_cObject);

  rb_define_singleton_method(collectors_stack_class, "_native_serialize", _native_serialize, 1);

  // Instances of this class MUST be created via native code because this the Collectors::Stack class is used as a
  // "TypedData" object. A "TypedData" object in Ruby is a special object that contains inside itself a pointer to
  // native resources. Obviously, this cannot be done from Ruby code, so we replace Ruby's default allocation method.
  rb_define_alloc_func(collectors_stack_class, _native_new);

  ok_symbol = ID2SYM(rb_intern_const("ok"));
  error_symbol = ID2SYM(rb_intern_const("error"));
}

// This structure is used to define a Ruby object that stores a pointer to a ddprof_ffi_Profile instance
// See also https://github.com/ruby/ruby/blob/master/doc/extension.rdoc for how this works
static const rb_data_type_t collectors_stack_ddprof_ffi_Profile = {
  .wrap_struct_name = "Datadog::Profiling::Collectors::Stack",
  .function = {
    .dfree = collectors_stack_ddprof_ffi_Profile_free,
    .dsize = NULL, // We don't track profile memory usage (although it'd be cool if we did!)
    // No need to provide dmark nor dcompact because we don't directly reference Ruby VALUEs from inside this object
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE _native_new(VALUE klass) {
  ddprof_ffi_Slice_value_type sample_types = {
    .ptr = enabled_value_types,
    .len = (sizeof(enabled_value_types) / sizeof(ddprof_ffi_ValueType))
  };

  ddprof_ffi_Profile *profile = ddprof_ffi_Profile_new(sample_types, NULL /* Period is optional */);

  return TypedData_Wrap_Struct(collectors_stack_class, &collectors_stack_ddprof_ffi_Profile, profile);
}

static void collectors_stack_ddprof_ffi_Profile_free(void *data) {
  ddprof_ffi_Profile_free((ddprof_ffi_Profile *) data);
}

static VALUE _native_serialize(VALUE self, VALUE stack_instance) {
  Check_TypedStruct(stack_instance, &collectors_stack_ddprof_ffi_Profile);

  ddprof_ffi_Profile *profile;
  TypedData_Get_Struct(stack_instance, ddprof_ffi_Profile, &collectors_stack_ddprof_ffi_Profile, profile);

  ddprof_ffi_EncodedProfile *serialized_profile = ddprof_ffi_Profile_serialize(profile);
  if (serialized_profile == NULL) return rb_ary_new_from_args(2, error_symbol, rb_str_new_cstr("Failed to serialize profile"));

  VALUE encoded_pprof = rb_str_new((char *) serialized_profile->buffer.ptr, serialized_profile->buffer.len);
  VALUE start = rb_time_nano_new(serialized_profile->start.seconds, serialized_profile->start.nanoseconds);
  VALUE finish = rb_time_nano_new(serialized_profile->end.seconds, serialized_profile->end.nanoseconds);

  ddprof_ffi_EncodedProfile_delete(serialized_profile);

  if (!ddprof_ffi_Profile_reset(profile)) return rb_ary_new_from_args(2, error_symbol, rb_str_new_cstr("Failed to reset profile"));/** FIXME: Why/when would this ever fail? sus API... **/

  return rb_ary_new_from_args(2, ok_symbol, rb_ary_new_from_args(3, start, finish, encoded_pprof));
}

VALUE create_stack_collector() {
  return _native_new(collectors_stack_class);
}

void collector_add(VALUE collector, ddprof_ffi_Sample sample) {
  Check_TypedStruct(collector, &collectors_stack_ddprof_ffi_Profile);

  ddprof_ffi_Profile *profile;
  TypedData_Get_Struct(collector, ddprof_ffi_Profile, &collectors_stack_ddprof_ffi_Profile, profile);

  printf("Added sample to profile!\n");

  ddprof_ffi_Profile_add(profile, sample);
}

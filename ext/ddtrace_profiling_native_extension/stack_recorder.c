#include <ruby.h>
#include <ruby/debug.h>
#include <ddprof/ffi.h>
#include "stack_recorder.h"

// Used to wrap a ddprof_ffi_Profile in a Ruby object and expose Ruby-level serialization APIs
// This file implements the native bits of the Datadog::Profiling::StackRecorder class

static VALUE ok_symbol = Qnil; // :ok in Ruby
static VALUE error_symbol = Qnil; // :error in Ruby

static VALUE stack_recorder_class = Qnil;

#define      CPU_TIME_VALUE {.type_ = DDPROF_FFI_CHARSLICE_C("cpu-time"),      .unit = DDPROF_FFI_CHARSLICE_C("nanoseconds")}
#define   CPU_SAMPLES_VALUE {.type_ = DDPROF_FFI_CHARSLICE_C("cpu-samples"),   .unit = DDPROF_FFI_CHARSLICE_C("count")}
#define     WALL_TIME_VALUE {.type_ = DDPROF_FFI_CHARSLICE_C("wall-time"),     .unit = DDPROF_FFI_CHARSLICE_C("nanoseconds")}
#define ALLOC_SAMPLES_VALUE {.type_ = DDPROF_FFI_CHARSLICE_C("alloc-samples"), .unit = DDPROF_FFI_CHARSLICE_C("count")}
#define   ALLOC_SPACE_VALUE {.type_ = DDPROF_FFI_CHARSLICE_C("alloc-space"),   .unit = DDPROF_FFI_CHARSLICE_C("bytes")}
#define    HEAP_SPACE_VALUE {.type_ = DDPROF_FFI_CHARSLICE_C("heap-space"),    .unit = DDPROF_FFI_CHARSLICE_C("bytes")}

const static ddprof_ffi_ValueType enabled_value_types[] = {CPU_TIME_VALUE, CPU_SAMPLES_VALUE, WALL_TIME_VALUE};
#define ENABLED_VALUE_TYPES_COUNT (sizeof(enabled_value_types) / sizeof(ddprof_ffi_ValueType))

static VALUE _native_new(VALUE klass);
static void stack_recorder_typed_data_free(void *data);
static VALUE _native_serialize(VALUE self, VALUE recorder_instance);
static VALUE ruby_time_from(ddprof_ffi_Timespec ddprof_time);

void stack_recorder_init(VALUE profiling_module) {
  stack_recorder_class = rb_define_class_under(profiling_module, "StackRecorder", rb_cObject);

  // Instances of the StackRecorder class are going to be "TypedData" objects.
  // "TypedData" objects are special objects in the Ruby VM that can wrap C structs.
  // In our case, we're going to keep a libddprof profile reference inside our object.
  //
  // Because Ruby doesn't know how to initialize libddprof profiles, we MUST override the allocation function for objects
  // of this class so that we can manage this part. Not overriding or disabling the allocation function is a common
  // gotcha for "TypedData" objects that can very easily lead to VM crashes, see for instance
  // https://bugs.ruby-lang.org/issues/18007 for a discussion around this.
  rb_define_alloc_func(stack_recorder_class, _native_new);

  rb_define_singleton_method(stack_recorder_class, "_native_serialize",  _native_serialize, 1);

  ok_symbol = ID2SYM(rb_intern_const("ok"));
  error_symbol = ID2SYM(rb_intern_const("error"));

}

// This structure is used to define a Ruby object that stores a pointer to a ddprof_ffi_Profile instance
// See also https://github.com/ruby/ruby/blob/master/doc/extension.rdoc for how this works
static const rb_data_type_t stack_recorder_typed_data = {
  .wrap_struct_name = "Datadog::Profiling::StackRecorder",
  .function = {
    .dfree = stack_recorder_typed_data_free,
    .dsize = NULL, // We don't track profile memory usage (although it'd be cool if we did!)
    // No need to provide dmark nor dcompact because we don't directly reference Ruby VALUEs from inside this object
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE _native_new(VALUE klass) {
  ddprof_ffi_Slice_value_type sample_types = {.ptr = enabled_value_types, .len = ENABLED_VALUE_TYPES_COUNT};

  ddprof_ffi_Profile *profile = ddprof_ffi_Profile_new(sample_types, NULL /* Period is optional */);

  return TypedData_Wrap_Struct(stack_recorder_class, &stack_recorder_typed_data, profile);
}

static void stack_recorder_typed_data_free(void *data) {
  ddprof_ffi_Profile_free((ddprof_ffi_Profile *) data);
}

static VALUE _native_serialize(VALUE self, VALUE recorder_instance) {
  Check_TypedStruct(recorder_instance, &stack_recorder_typed_data);

  ddprof_ffi_Profile *profile;
  TypedData_Get_Struct(recorder_instance, ddprof_ffi_Profile, &stack_recorder_typed_data, profile);

  // TODO: Update this after https://github.com/DataDog/libddprof/pull/42 gets merged
  ddprof_ffi_EncodedProfile *serialized_profile = ddprof_ffi_Profile_serialize(profile);
  if (serialized_profile == NULL) return rb_ary_new_from_args(2, error_symbol, rb_str_new_cstr("Failed to serialize profile"));

  VALUE encoded_pprof = rb_str_new((char *) serialized_profile->buffer.ptr, serialized_profile->buffer.len);
  VALUE start = ruby_time_from(serialized_profile->start);
  VALUE finish = ruby_time_from(serialized_profile->end);

  ddprof_ffi_EncodedProfile_delete(serialized_profile);
  if (!ddprof_ffi_Profile_reset(profile)) return rb_ary_new_from_args(2, error_symbol, rb_str_new_cstr("Failed to reset profile"));

  return rb_ary_new_from_args(2, ok_symbol, rb_ary_new_from_args(3, start, finish, encoded_pprof));
}

static VALUE ruby_time_from(ddprof_ffi_Timespec ddprof_time) {
  const int utc = INT_MAX - 1; // From Ruby sources
  struct timespec time = {.tv_sec = ddprof_time.seconds, .tv_nsec = ddprof_time.nanoseconds};
  return rb_time_timespec_new(&time, utc);
}

void record_sample(VALUE recorder_instance, ddprof_ffi_Sample sample) {
  Check_TypedStruct(recorder_instance, &stack_recorder_typed_data);
  ddprof_ffi_Profile *profile;
  TypedData_Get_Struct(recorder_instance, ddprof_ffi_Profile, &stack_recorder_typed_data, profile);
  ddprof_ffi_Profile_add(profile, sample);
}

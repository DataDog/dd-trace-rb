#include <ruby.h>
#include <ruby/thread.h>
#include "stack_recorder.h"
#include "libddprof_helpers.h"

// Used to wrap a ddprof_ffi_Profile in a Ruby object and expose Ruby-level serialization APIs
// This file implements the native bits of the Datadog::Profiling::StackRecorder class

static VALUE ok_symbol = Qnil; // :ok in Ruby
static VALUE error_symbol = Qnil; // :error in Ruby

static ID ruby_time_from_id; // id of :ruby_time_from in Ruby

static VALUE stack_recorder_class = Qnil;

struct call_serialize_without_gvl_arguments {
  ddprof_ffi_Profile *profile;
  ddprof_ffi_SerializeResult result;
  bool serialize_ran;
};

static VALUE _native_new(VALUE klass);
static void stack_recorder_typed_data_free(void *data);
static VALUE _native_serialize(VALUE self, VALUE recorder_instance);
static VALUE ruby_time_from(ddprof_ffi_Timespec ddprof_time);
static void *call_serialize_without_gvl(void *call_args);

void stack_recorder_init(VALUE profiling_module) {
  stack_recorder_class = rb_define_class_under(profiling_module, "StackRecorder", rb_cObject);

  // Instances of the StackRecorder class are "TypedData" objects.
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
  ruby_time_from_id = rb_intern_const("ruby_time_from");
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

  return TypedData_Wrap_Struct(klass, &stack_recorder_typed_data, profile);
}

static void stack_recorder_typed_data_free(void *data) {
  ddprof_ffi_Profile_free((ddprof_ffi_Profile *) data);
}

static VALUE _native_serialize(VALUE self, VALUE recorder_instance) {
  ddprof_ffi_Profile *profile;
  TypedData_Get_Struct(recorder_instance, ddprof_ffi_Profile, &stack_recorder_typed_data, profile);

  // We'll release the Global VM Lock while we're calling serialize, so that the Ruby VM can continue to work while this
  // is pending
  struct call_serialize_without_gvl_arguments args = {.profile = profile, .serialize_ran = false};

  // We use rb_thread_call_without_gvl2 for similar reasons as in http_transport.c: we don't want pending interrupts
  // that cause exceptions to be raised to be processed as otherwise we can leak the serialized profile.
  rb_thread_call_without_gvl2(call_serialize_without_gvl, &args, /* No interruption supported */ NULL, NULL);

  // This weird corner case can happen if rb_thread_call_without_gvl2 returns immediately due to an interrupt
  // without ever calling call_serialize_without_gvl. In this situation, we don't have anything to clean up, we can
  // just return.
  if (!args.serialize_ran) {
    return rb_ary_new_from_args(2, error_symbol, rb_str_new_cstr("Interrupted before call_serialize_without_gvl ran"));
  }

  ddprof_ffi_SerializeResult serialized_profile = args.result;

  if (serialized_profile.tag == DDPROF_FFI_SERIALIZE_RESULT_ERR) {
    VALUE err_details = ruby_string_from_vec_u8(serialized_profile.err);
    ddprof_ffi_SerializeResult_drop(serialized_profile);
    return rb_ary_new_from_args(2, error_symbol, err_details);
  }

  VALUE encoded_pprof = ruby_string_from_vec_u8(serialized_profile.ok.buffer);

  ddprof_ffi_Timespec ddprof_start = serialized_profile.ok.start;
  ddprof_ffi_Timespec ddprof_finish = serialized_profile.ok.end;

  // Clean up libddprof object to avoid leaking in case ruby_time_from raises an exception
  ddprof_ffi_SerializeResult_drop(serialized_profile);

  VALUE start = ruby_time_from(ddprof_start);
  VALUE finish = ruby_time_from(ddprof_finish);

  if (!ddprof_ffi_Profile_reset(profile)) return rb_ary_new_from_args(2, error_symbol, rb_str_new_cstr("Failed to reset profile"));

  return rb_ary_new_from_args(2, ok_symbol, rb_ary_new_from_args(3, start, finish, encoded_pprof));
}

static VALUE ruby_time_from(ddprof_ffi_Timespec ddprof_time) {
  #ifndef NO_RB_TIME_TIMESPEC_NEW // Modern Rubies
    const int utc = INT_MAX - 1; // From Ruby sources
    struct timespec time = {.tv_sec = ddprof_time.seconds, .tv_nsec = ddprof_time.nanoseconds};
    return rb_time_timespec_new(&time, utc);
  #else // Ruby < 2.3
    return rb_funcall(stack_recorder_class, ruby_time_from_id, 2, LONG2NUM(ddprof_time.seconds), UINT2NUM(ddprof_time.nanoseconds));
  #endif
}

void record_sample(VALUE recorder_instance, ddprof_ffi_Sample sample) {
  ddprof_ffi_Profile *profile;
  TypedData_Get_Struct(recorder_instance, ddprof_ffi_Profile, &stack_recorder_typed_data, profile);

  ddprof_ffi_Profile_add(profile, sample);
}

static void *call_serialize_without_gvl(void *call_args) {
  struct call_serialize_without_gvl_arguments *args = (struct call_serialize_without_gvl_arguments *) call_args;

  args->result = ddprof_ffi_Profile_serialize(args->profile);
  args->serialize_ran = true;

  return NULL; // Unused
}

void enforce_recorder_instance(VALUE object) {
  Check_TypedStruct(object, &stack_recorder_typed_data);
}

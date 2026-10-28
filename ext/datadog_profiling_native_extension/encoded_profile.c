#include "encoded_profile.h"
#include "datadog_ruby_common.h"
#include "libdatadog_helpers.h"
#include "ruby_helpers.h"
#include <stdlib.h>
#include <string.h>

// This class exists to wrap a ddog_prof_EncodedProfile into a Ruby object
// This file implements the native bits of the Datadog::Profiling::EncodedProfile class

static void encoded_profile_typed_data_free(void *state_ptr);
static VALUE _native_bytes(VALUE self);
static VALUE from_custom(VALUE self, VALUE start, VALUE end, VALUE bytes_string);

static VALUE encoded_profile_class = Qnil;

void encoded_profile_init(VALUE profiling_module) {
  encoded_profile_class = rb_define_class_under(profiling_module, "EncodedProfile", rb_cObject);

  rb_undef_alloc_func(encoded_profile_class); // Class cannot be created from Ruby code
  rb_global_variable(&encoded_profile_class);

  rb_define_method(encoded_profile_class, "_native_bytes", _native_bytes, 0);
  rb_define_singleton_method(encoded_profile_class, "from_custom", from_custom, 3);
}

// This structure is used to define a Ruby object that stores a `ddog_prof_EncodedProfile`
// See also https://github.com/ruby/ruby/blob/master/doc/extension.rdoc for how this works
static const rb_data_type_t encoded_profile_typed_data = {
  .wrap_struct_name = "Datadog::Profiling::EncodedProfile",
  .function = {
    .dmark = NULL, // We don't store references to Ruby objects so we don't need to mark any of them
    .dfree = encoded_profile_typed_data_free,
    .dsize = NULL, // We don't track memory usage (although it'd be cool if we did!)
    //.dcompact = NULL, // Not needed -- we don't store references to Ruby objects
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

VALUE from_ddog_prof_EncodedProfile(ddog_prof_EncodedProfile profile) {
  ddog_prof_EncodedProfile *state = ruby_xcalloc(1, sizeof(ddog_prof_EncodedProfile));
  *state = profile;
  return TypedData_Wrap_Struct(encoded_profile_class, &encoded_profile_typed_data, state);
}

static ddog_ByteSlice get_bytes(ddog_prof_EncodedProfile *state) {
  ddog_prof_Result_ByteSlice raw_bytes = ddog_prof_EncodedProfile_bytes(state);
  if (raw_bytes.tag == DDOG_PROF_RESULT_BYTE_SLICE_ERR_BYTE_SLICE) {
    raise_error(rb_eRuntimeError, "Failed to get bytes from profile: %"PRIsVALUE, get_error_details_and_drop(&raw_bytes.err));
  }
  return raw_bytes.ok;
}

static ddog_prof_EncodedProfile *internal_to_ddog_prof_EncodedProfile(VALUE object) {
  ddog_prof_EncodedProfile *state;
  TypedData_Get_Struct(object, ddog_prof_EncodedProfile, &encoded_profile_typed_data, state);
  return state;
}

ddog_prof_EncodedProfile *to_ddog_prof_EncodedProfile(VALUE object) {
  ddog_prof_EncodedProfile *state = internal_to_ddog_prof_EncodedProfile(object);
  get_bytes(state); // Validate profile is still usable -- if it's not, this will raise an exception
  return state;
}

static void encoded_profile_typed_data_free(void *state_ptr) {
  ddog_prof_EncodedProfile *state = (ddog_prof_EncodedProfile *) state_ptr;

  // This drops the profile itself
  ddog_prof_EncodedProfile_drop(state);

  // This drops the tiny bit of memory we allocated to contain the ` ddog_prof_EncodedProfile` struct
  ruby_xfree(state);
}

static VALUE _native_bytes(VALUE self) {
  ddog_ByteSlice bytes = get_bytes(internal_to_ddog_prof_EncodedProfile(self));
  return rb_str_new((const char *) bytes.ptr, bytes.len);
}

VALUE enforce_encoded_profile_instance(VALUE object) {
  ENFORCE_TYPED_DATA(object, &encoded_profile_typed_data);
  return object;
}

// Test-only workaround for libdatadog's lack of a constructor accepting arbitrary encoded bytes.
// Serialize an empty profile so libdatadog initializes timestamps and endpoint statistics, then
// replace its buffer while preserving normal export/drop ownership. This assumes Rust's private
// Vec layout at the start of the object, checked against libdatadog's bytes API before mutation.
static VALUE from_custom(DDTRACE_UNUSED VALUE self, VALUE start, VALUE end, VALUE bytes_string) {
  if (!rb_obj_is_kind_of(start, rb_cTime) || !rb_obj_is_kind_of(end, rb_cTime)) {
    raise_error(rb_eTypeError, "start and end must be Time objects");
  }
  ENFORCE_TYPE(bytes_string, T_STRING);

  struct timespec start_time = rb_time_timespec(start);
  struct timespec end_time = rb_time_timespec(end);
  ddog_Timespec profile_start = {.seconds = start_time.tv_sec, .nanoseconds = start_time.tv_nsec};
  ddog_Timespec profile_end = {.seconds = end_time.tv_sec, .nanoseconds = end_time.tv_nsec};

  // Allocate the Ruby owner first so exceptions cannot leak the native profile.
  ddog_prof_EncodedProfile *state;
  VALUE result = TypedData_Make_Struct(encoded_profile_class, ddog_prof_EncodedProfile, &encoded_profile_typed_data, state);
  ddog_prof_SampleType sample_type = DDOG_PROF_SAMPLE_TYPE_WALL_TIME;
  ddog_prof_Profile_NewResult profile = ddog_prof_Profile_new(
    (ddog_prof_Slice_SampleType) {.ptr = &sample_type, .len = 1}, NULL
  );
  if (profile.tag == DDOG_PROF_PROFILE_NEW_RESULT_ERR) {
    raise_error(rb_eRuntimeError, "Failed to create profile: %"PRIsVALUE, get_error_details_and_drop(&profile.err));
  }

  ddog_prof_Profile_SerializeResult encoded = ddog_prof_Profile_serialize(&profile.ok, &profile_start, &profile_end);
  ddog_prof_Profile_drop(&profile.ok);
  if (encoded.tag == DDOG_PROF_PROFILE_SERIALIZE_RESULT_ERR) {
    raise_error(rb_eRuntimeError, "Failed to serialize profile: %"PRIsVALUE, get_error_details_and_drop(&encoded.err));
  }
  *state = encoded.ok;

  struct {
    size_t capacity;
    uint8_t *pointer;
    size_t length;
  } buffer;
  ddog_ByteSlice bytes = get_bytes(state);
  memcpy(&buffer, state->inner, sizeof(buffer));
  if (buffer.pointer != bytes.ptr || buffer.length != bytes.len || buffer.capacity < buffer.length || buffer.length == 0) {
    raise_error(rb_eRuntimeError, "EncodedProfile.from_custom: incompatible libdatadog buffer layout");
  }

  size_t length = RSTRING_LEN(bytes_string);
  size_t capacity = length > 0 ? length : 1;
  // libdatadog uses the system allocator, so this must not use Ruby's allocators.
  uint8_t *pointer = realloc(buffer.pointer, capacity);
  if (pointer == NULL) rb_memerror();
  if (length > 0) memcpy(pointer, RSTRING_PTR(bytes_string), length);
  buffer.capacity = capacity;
  buffer.pointer = pointer;
  buffer.length = length;
  memcpy(state->inner, &buffer, sizeof(buffer));
  RB_GC_GUARD(bytes_string);
  return result;
}

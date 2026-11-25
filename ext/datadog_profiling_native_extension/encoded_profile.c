#include "encoded_profile.h"
#include "datadog_ruby_common.h"
#include "libdatadog_helpers.h"
#include "ruby_helpers.h"

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

static VALUE allocate_encoded_profile(VALUE state_out_ptr) {
  ddog_prof_EncodedProfile **state_out = (ddog_prof_EncodedProfile **) state_out_ptr;
  return TypedData_Make_Struct(encoded_profile_class, ddog_prof_EncodedProfile, &encoded_profile_typed_data, *state_out);
}

VALUE from_ddog_prof_EncodedProfile(ddog_prof_EncodedProfile profile) {
  ddog_prof_EncodedProfile *state;
  int error;
  VALUE result = rb_protect(allocate_encoded_profile, (VALUE) &state, &error);
  if (error != 0) {
    ddog_prof_EncodedProfile_drop(&profile);
    rb_jump_tag(error);
  }
  *state = profile;
  return result;
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

static VALUE from_custom(DDTRACE_UNUSED VALUE self, VALUE start, VALUE end, VALUE bytes_string) {
  if (!rb_obj_is_kind_of(start, rb_cTime) || !rb_obj_is_kind_of(end, rb_cTime)) {
    raise_error(rb_eTypeError, "start and end must be Time objects");
  }
  ENFORCE_TYPE(bytes_string, T_STRING);

  struct timespec start_time = rb_time_timespec(start);
  struct timespec end_time = rb_time_timespec(end);
  ddog_Timespec profile_start = {.seconds = start_time.tv_sec, .nanoseconds = start_time.tv_nsec};
  ddog_Timespec profile_end = {.seconds = end_time.tv_sec, .nanoseconds = end_time.tv_nsec};

  ddog_prof_EncodedProfile_Result encoded = ddog_prof_EncodedProfile_from_bytes(
    (ddog_ByteSlice) {.ptr = (const uint8_t *) RSTRING_PTR(bytes_string), .len = RSTRING_LEN(bytes_string)},
    profile_start,
    profile_end
  );
  RB_GC_GUARD(bytes_string);
  if (encoded.tag == DDOG_PROF_ENCODED_PROFILE_RESULT_ERR_HANDLE_ENCODED_PROFILE) {
    raise_error(rb_eRuntimeError, "Failed to create encoded profile: %"PRIsVALUE, get_error_details_and_drop(&encoded.err));
  }
  return from_ddog_prof_EncodedProfile(encoded.ok);
}

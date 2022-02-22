#include <ruby.h>
#include <ddprof/ffi.h>

// Used to report profiling data to Datadog.
// This file implements the native bits of the Datadog::Profiling::HttpTransport class

// Datadog::Profiling::HttpTransport::Exporter
// This is used to wrap a native-level pointer to a libddprof exporter;
// see exporter_as_ruby_object below for more details
static VALUE exporter_class = Qnil;

inline static ddprof_ffi_ByteSlice byte_slice_from_chars(const char *string);
inline static ddprof_ffi_ByteSlice byte_slice_from_ruby_string(VALUE string);
static VALUE _native_create_agentless_exporter(VALUE self, VALUE site, VALUE api_key, VALUE tags_as_array);
static VALUE _native_create_agent_exporter(VALUE self, VALUE base_url, VALUE tags_as_array);
static VALUE create_exporter(struct ddprof_ffi_EndpointV3 endpoint, VALUE tags_as_array);
static void convert_tags(ddprof_ffi_Tag *converted_tags, long tags_count, VALUE tags_as_array);
static void exporter_as_ruby_object_free(void *data);
static VALUE exporter_to_ruby_object(ddprof_ffi_ProfileExporterV3* exporter);
static VALUE _native_do_export(
  VALUE self,
  VALUE libddprof_exporter,
  VALUE upload_timeout_milliseconds,
  VALUE start_timespec_seconds,
  VALUE start_timespec_nanoseconds,
  VALUE finish_timespec_seconds,
  VALUE finish_timespec_nanoseconds,
  VALUE pprof_file_name,
  VALUE pprof_data,
  VALUE code_provenance_file_name,
  VALUE code_provenance_data
);

void http_transport_init(VALUE profiling_module) {
  VALUE http_transport_class = rb_define_class_under(profiling_module, "HttpTransport", rb_cObject);

  rb_define_singleton_method(
    http_transport_class, "_native_create_agentless_exporter",  _native_create_agentless_exporter, 3
  );
  rb_define_singleton_method(
    http_transport_class, "_native_create_agent_exporter",  _native_create_agent_exporter, 2
  );
  rb_define_singleton_method(
    http_transport_class, "_native_do_export",  _native_do_export, 10
  );

  exporter_class = rb_define_class_under(http_transport_class, "Exporter", rb_cObject);
  // This prevents creation of the exporter class outside of our extension, see https://bugs.ruby-lang.org/issues/18007
  rb_undef_alloc_func(exporter_class);
}

// TODO: Extract these out
// FIXME I THINK THIS IS COMPLETELY BROKEN !
inline static ddprof_ffi_ByteSlice byte_slice_from_chars(const char *string) {
  ddprof_ffi_ByteSlice byte_slice = {.ptr = (uint8_t *) string, .len = sizeof(string) - 1};
  return byte_slice;
}

inline static ddprof_ffi_ByteSlice byte_slice_from_ruby_string(VALUE string) {
  Check_Type(string, T_STRING);
  ddprof_ffi_ByteSlice byte_slice = {.ptr = (uint8_t *) StringValuePtr(string), .len = RSTRING_LEN(string)};
  return byte_slice;
}

static VALUE _native_create_agentless_exporter(VALUE self, VALUE site, VALUE api_key, VALUE tags_as_array) {
  Check_Type(site, T_STRING);
  Check_Type(api_key, T_STRING);
  Check_Type(tags_as_array, T_ARRAY);

  return create_exporter(
    ddprof_ffi_EndpointV3_agentless(
      byte_slice_from_ruby_string(site),
      byte_slice_from_ruby_string(api_key)
    ),
    tags_as_array
  );
}

static VALUE _native_create_agent_exporter(VALUE self, VALUE base_url, VALUE tags_as_array) {
  Check_Type(base_url, T_STRING);
  Check_Type(tags_as_array, T_ARRAY);

  return create_exporter(
    ddprof_ffi_EndpointV3_agent(byte_slice_from_ruby_string(base_url)),
    tags_as_array
  );
}

static VALUE create_exporter(struct ddprof_ffi_EndpointV3 endpoint, VALUE tags_as_array) {

  long tags_count = rb_array_len(tags_as_array);
  ddprof_ffi_Tag converted_tags[tags_count];

  convert_tags(converted_tags, tags_count, tags_as_array);

  struct ddprof_ffi_NewProfileExporterV3Result exporter_result =
    ddprof_ffi_ProfileExporterV3_new(
      byte_slice_from_chars("ruby"),
      (ddprof_ffi_Slice_tag) {.ptr = converted_tags, .len = tags_count},
      endpoint
    );

  if (exporter_result.tag != DDPROF_FFI_NEW_PROFILE_EXPORTER_V3_RESULT_OK) {
    VALUE failure_details = rb_str_new((char *) exporter_result.err.ptr, exporter_result.err.len);
    ddprof_ffi_NewProfileExporterV3Result_dtor(exporter_result); // Clean up result
    rb_raise(rb_eRuntimeError, "Failed to initialize libddprof: %+"PRIsVALUE, failure_details);
  }

  VALUE exporter = exporter_to_ruby_object(exporter_result.ok);
  // No need to call the result dtor, since the only heap-allocated part is the exporter and we like that part

  return exporter;
}

static void convert_tags(ddprof_ffi_Tag *converted_tags, long tags_count, VALUE tags_as_array) {
  Check_Type(tags_as_array, T_ARRAY);

  for (long i = 0; i < tags_count; i++) {
    VALUE name_value_pair = rb_ary_entry(tags_as_array, i);
    Check_Type(name_value_pair, T_ARRAY);

    // Note: We can index the array without checking its size first because rb_ary_entry returns Qnil if out of bounds
    VALUE tag_name = rb_ary_entry(name_value_pair, 0);
    VALUE tag_value = rb_ary_entry(name_value_pair, 1);
    Check_Type(tag_name, T_STRING);
    Check_Type(tag_value, T_STRING);

    converted_tags[i] = (ddprof_ffi_Tag) {
      .name = byte_slice_from_ruby_string(tag_name),
      .value = byte_slice_from_ruby_string(tag_value)
    };
  }
}

// This structure is used to define a Ruby object that stores a pointer to a ddprof_ffi_ProfileExporterV3 instance
// See also https://github.com/ruby/ruby/blob/master/doc/extension.rdoc for how this works
static const rb_data_type_t exporter_as_ruby_object = {
  .wrap_struct_name = "Datadog::Profiling::HttpTransport::Exporter",
  .function = {
    .dfree = exporter_as_ruby_object_free,
    .dsize = NULL, // We don't track exporter memory usage
    // No need to provide dmark nor dcompact because we don't reference Ruby VALUEs from inside this object
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static void exporter_as_ruby_object_free(void *data) {
  ddprof_ffi_ProfileExporterV3_delete((ddprof_ffi_ProfileExporterV3 *) data);
}

static VALUE exporter_to_ruby_object(ddprof_ffi_ProfileExporterV3* exporter) {
  return TypedData_Wrap_Struct(exporter_class, &exporter_as_ruby_object, exporter);
}

static VALUE _native_do_export(
  VALUE self,
  VALUE libddprof_exporter,
  VALUE upload_timeout_milliseconds,
  VALUE start_timespec_seconds,
  VALUE start_timespec_nanoseconds,
  VALUE finish_timespec_seconds,
  VALUE finish_timespec_nanoseconds,
  VALUE pprof_file_name,
  VALUE pprof_data,
  VALUE code_provenance_file_name,
  VALUE code_provenance_data
) {
  Check_TypedStruct(libddprof_exporter, &exporter_as_ruby_object);
  Check_Type(upload_timeout_milliseconds, T_FIXNUM);
  Check_Type(start_timespec_seconds, T_FIXNUM);
  Check_Type(start_timespec_nanoseconds, T_FIXNUM);
  Check_Type(finish_timespec_seconds, T_FIXNUM);
  Check_Type(finish_timespec_nanoseconds, T_FIXNUM);
  Check_Type(pprof_file_name, T_STRING);
  Check_Type(pprof_data, T_STRING);
  Check_Type(code_provenance_file_name, T_STRING);
  Check_Type(code_provenance_data, T_STRING);

  ddprof_ffi_ProfileExporterV3 *exporter;
  TypedData_Get_Struct(libddprof_exporter, ddprof_ffi_ProfileExporterV3, &exporter_as_ruby_object, exporter);

  uint64_t timeout_milliseconds = NUM2ULONG(upload_timeout_milliseconds);

  ddprof_ffi_Timespec start =
    {.seconds = NUM2LONG(start_timespec_seconds), .nanoseconds = NUM2UINT(start_timespec_nanoseconds)};
  ddprof_ffi_Timespec finish =
    {.seconds = NUM2LONG(finish_timespec_seconds), .nanoseconds = NUM2UINT(finish_timespec_nanoseconds)};

  ddprof_ffi_Buffer pprof_buffer =
    {.ptr = (uint8_t *) StringValuePtr(pprof_data), .len = RSTRING_LEN(pprof_data), .capacity = 0}; // FIXME Should I be using this?
  ddprof_ffi_Buffer code_provenance_buffer =
    {.ptr = (uint8_t *) StringValuePtr(code_provenance_data), .len = RSTRING_LEN(code_provenance_data), .capacity = 0}; // FIXME Should I be using this?

  const ddprof_ffi_File files[] = {
    {.name = byte_slice_from_ruby_string(pprof_file_name), .file = &pprof_buffer},
    {.name = byte_slice_from_ruby_string(code_provenance_file_name), .file = &code_provenance_buffer}
  };
  ddprof_ffi_Slice_file slice_files = {.ptr = files, .len = (sizeof(files) / sizeof(ddprof_ffi_File))};

  ddprof_ffi_Request *request =
    ddprof_ffi_ProfileExporterV3_build(exporter, start, finish, slice_files, timeout_milliseconds);

  ddprof_ffi_SendResult result = ddprof_ffi_ProfileExporterV3_send(exporter, request);
  request = NULL; // send consumes and takes care of cleaning up request

  if (result.tag == DDPROF_FFI_SEND_RESULT_HTTP_RESPONSE) {
    VALUE failure_details = rb_str_new((char *) result.failure.ptr, result.failure.len);
    // TODO: Missing clean up of error string?
    rb_raise(rb_eRuntimeError, "Failed to report profile: %+"PRIsVALUE, failure_details);
  }

  // TODO: Release gil (how to interrupt libddprof send?)
  return UINT2NUM(result.http_response.code);
}

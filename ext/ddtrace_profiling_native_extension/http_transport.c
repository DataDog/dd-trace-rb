#include <ruby.h>
#include <ddprof/ffi.h>

inline static ddprof_ffi_ByteSlice byte_slice_from_chars(const char *string);
inline static ddprof_ffi_ByteSlice byte_slice_from_ruby_string(VALUE string);
static VALUE _native_create_agentless_exporter(VALUE self, VALUE site, VALUE api_key, VALUE tags_as_array);
static VALUE _native_create_agent_exporter(VALUE self, VALUE base_url, VALUE tags_as_array);
static void create_exporter(struct ddprof_ffi_EndpointV3 endpoint, VALUE tags_as_array);
static void convert_tags(ddprof_ffi_Tag *converted_tags, long tags_count, VALUE tags_as_array);
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

void HttpTransport_init(VALUE profiling_module) {
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
}

// TODO: Extract these out
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

  create_exporter(
    ddprof_ffi_EndpointV3_agentless(
      byte_slice_from_ruby_string(site),
      byte_slice_from_ruby_string(api_key)
    ),
    tags_as_array
  );

  return Qnil;
}

static VALUE _native_create_agent_exporter(VALUE self, VALUE base_url, VALUE tags_as_array) {
  Check_Type(base_url, T_STRING);
  Check_Type(tags_as_array, T_ARRAY);

  create_exporter(
    ddprof_ffi_EndpointV3_agent(byte_slice_from_ruby_string(base_url)),
    tags_as_array
  );

  return Qnil;
}

static void create_exporter(struct ddprof_ffi_EndpointV3 endpoint, VALUE tags_as_array) {

  long tags_count = rb_array_len(tags_as_array);
  ddprof_ffi_Tag converted_tags[tags_count];

  convert_tags(converted_tags, tags_count, tags_as_array);

  struct ddprof_ffi_NewProfileExporterV3Result profile_exporter_result =
    ddprof_ffi_ProfileExporterV3_new(
      byte_slice_from_chars("ruby"),
      (ddprof_ffi_Slice_tag) {.ptr = converted_tags, .len = tags_count},
      endpoint
    );
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
  // Check_Type(libddprof_exporter, ???); FIXME
  Check_Type(upload_timeout_milliseconds, T_FIXNUM);
  Check_Type(start_timespec_seconds, T_FIXNUM);
  Check_Type(start_timespec_nanoseconds, T_FIXNUM);
  Check_Type(finish_timespec_seconds, T_FIXNUM);
  Check_Type(finish_timespec_nanoseconds, T_FIXNUM);
  Check_Type(pprof_file_name, T_STRING);
  Check_Type(pprof_data, T_STRING);
  Check_Type(code_provenance_file_name, T_STRING);
  Check_Type(code_provenance_data, T_STRING);

  // TODO: libpprof magic

  return Qnil;
}

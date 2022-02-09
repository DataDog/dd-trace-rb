#include <ruby.h>
#include <ddprof/ffi.h>

inline static ddprof_ffi_ByteSlice byte_slice_from_chars(const unsigned char *string);
inline static ddprof_ffi_ByteSlice byte_slice_from_ruby_string(VALUE string);
static VALUE _native_create_agentless_exporter(VALUE self, VALUE site, VALUE api_key, VALUE tags);
static VALUE _native_create_agent_exporter(VALUE self, VALUE base_url, VALUE tags);
static void create_exporter(struct ddprof_ffi_EndpointV3 endpoint, VALUE tags);
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

inline static ddprof_ffi_ByteSlice byte_slice_from_chars(const unsigned char *string) {
  ddprof_ffi_ByteSlice byte_slice = {.ptr = string, .len = sizeof(string) - 1};
  return byte_slice;
}

inline static ddprof_ffi_ByteSlice byte_slice_from_ruby_string(VALUE string) {
  Check_Type(string, T_STRING);
  ddprof_ffi_ByteSlice byte_slice = {.ptr = (uint8_t *) StringValuePtr(string), .len = RSTRING_LEN(string)};
  return byte_slice;
}

static VALUE _native_create_agentless_exporter(VALUE self, VALUE site, VALUE api_key, VALUE tags) {
  Check_Type(site, T_STRING);
  Check_Type(api_key, T_STRING);
  Check_Type(tags, RUBY_T_HASH);

  create_exporter(
    ddprof_ffi_EndpointV3_agentless(
      byte_slice_from_ruby_string(site),
      byte_slice_from_ruby_string(api_key)
    ),
    tags
  );

  return Qnil;
}

static VALUE _native_create_agent_exporter(VALUE self, VALUE base_url, VALUE tags) {
  Check_Type(base_url, T_STRING);
  Check_Type(tags, T_HASH);

  create_exporter(
    ddprof_ffi_EndpointV3_agent(byte_slice_from_ruby_string(base_url)),
    tags
  );

  return Qnil;
}

static void create_exporter(struct ddprof_ffi_EndpointV3 endpoint, VALUE tags) {
  Check_Type(tags, T_HASH);

  // struct ddprof_ffi_NewProfileExporterV3Result profile_exporter_result =
  //   ddprof_ffi_ProfileExporterV3_new(
  //     LIBDDPROF_STRING("ruby"),
  //     /* FIXME TAGS */,
  //     /* FIXME ENDPOINT */
  //   );

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

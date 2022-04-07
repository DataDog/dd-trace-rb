#include <ruby.h>
#include <ruby/thread.h>
#include <ddprof/ffi.h>

// Used to report profiling data to Datadog.
// This file implements the native bits of the Datadog::Profiling::HttpTransport class

static VALUE ok_symbol = Qnil; // :ok in Ruby
static VALUE error_symbol = Qnil; // :error in Ruby

static ID agentless_id; // id of :agentless in Ruby
static ID agent_id; // id of :agent in Ruby

#define byte_slice_from_literal(string) ((ddprof_ffi_ByteSlice) {.ptr = (uint8_t *) "" string, .len = sizeof("" string) - 1})

struct call_exporter_without_gvl_arguments {
  ddprof_ffi_ProfileExporterV3 *exporter;
  ddprof_ffi_Request *request;
  ddprof_ffi_SendResult result;
};

inline static ddprof_ffi_ByteSlice byte_slice_from_ruby_string(VALUE string);
static VALUE _native_validate_exporter(VALUE self, VALUE exporter_configuration);
static ddprof_ffi_NewProfileExporterV3Result create_exporter(VALUE exporter_configuration, VALUE tags_as_array);
static VALUE handle_exporter_failure(ddprof_ffi_NewProfileExporterV3Result exporter_result);
static ddprof_ffi_EndpointV3 endpoint_from(VALUE exporter_configuration);
static void convert_tags(ddprof_ffi_Tag *converted_tags, long tags_count, VALUE tags_as_array);
static VALUE _native_do_export(
  VALUE self,
  VALUE exporter_configuration,
  VALUE upload_timeout_milliseconds,
  VALUE start_timespec_seconds,
  VALUE start_timespec_nanoseconds,
  VALUE finish_timespec_seconds,
  VALUE finish_timespec_nanoseconds,
  VALUE pprof_file_name,
  VALUE pprof_data,
  VALUE code_provenance_file_name,
  VALUE code_provenance_data,
  VALUE tags_as_array
);
static ddprof_ffi_Request *build_request(
  ddprof_ffi_ProfileExporterV3 *exporter,
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
static void *call_exporter_without_gvl(void *exporter_and_request);

void http_transport_init(VALUE profiling_module) {
  VALUE http_transport_class = rb_define_class_under(profiling_module, "HttpTransport", rb_cObject);

  rb_define_singleton_method(http_transport_class, "_native_validate_exporter",  _native_validate_exporter, 1);
  rb_define_singleton_method(http_transport_class, "_native_do_export",  _native_do_export, 11);

  ok_symbol = ID2SYM(rb_intern_const("ok"));
  error_symbol = ID2SYM(rb_intern_const("error"));
  agentless_id = rb_intern_const("agentless");
  agent_id = rb_intern_const("agent");
}

inline static ddprof_ffi_ByteSlice byte_slice_from_ruby_string(VALUE string) {
  Check_Type(string, T_STRING);
  ddprof_ffi_ByteSlice byte_slice = {.ptr = (uint8_t *) StringValuePtr(string), .len = RSTRING_LEN(string)};
  return byte_slice;
}

static VALUE _native_validate_exporter(VALUE self, VALUE exporter_configuration) {
  Check_Type(exporter_configuration, T_ARRAY);
  ddprof_ffi_NewProfileExporterV3Result exporter_result = create_exporter(exporter_configuration, rb_ary_new());

  VALUE failure_tuple = handle_exporter_failure(exporter_result);
  if (!NIL_P(failure_tuple)) return failure_tuple;

  // We don't actually need the exporter for now -- we just wanted to validate that we could create it with the
  // settings we were given
  ddprof_ffi_NewProfileExporterV3Result_dtor(exporter_result);

  return rb_ary_new_from_args(2, ok_symbol, Qnil);
}

static ddprof_ffi_NewProfileExporterV3Result create_exporter(VALUE exporter_configuration, VALUE tags_as_array) {
  Check_Type(exporter_configuration, T_ARRAY);
  Check_Type(tags_as_array, T_ARRAY);

  long tags_count = RARRAY_LEN(tags_as_array);
  ddprof_ffi_Tag* converted_tags = xcalloc(tags_count, sizeof(ddprof_ffi_Tag));
  if (converted_tags == NULL) rb_raise(rb_eNoMemError, "Failed to allocate memory for storing tags");
  convert_tags(converted_tags, tags_count, tags_as_array);

  ddprof_ffi_NewProfileExporterV3Result exporter_result = ddprof_ffi_ProfileExporterV3_new(
    byte_slice_from_literal("ruby"),
    (ddprof_ffi_Slice_tag) {.ptr = converted_tags, .len = tags_count},
    endpoint_from(exporter_configuration)
  );

  xfree(converted_tags);

  return exporter_result;
}

static VALUE handle_exporter_failure(ddprof_ffi_NewProfileExporterV3Result exporter_result) {
  if (exporter_result.tag == DDPROF_FFI_NEW_PROFILE_EXPORTER_V3_RESULT_OK) return Qnil;

  VALUE failure_details = rb_str_new((char *) exporter_result.err.ptr, exporter_result.err.len);

  ddprof_ffi_NewProfileExporterV3Result_dtor(exporter_result);

  return rb_ary_new_from_args(2, error_symbol, failure_details);
}

static ddprof_ffi_EndpointV3 endpoint_from(VALUE exporter_configuration) {
  Check_Type(exporter_configuration, T_ARRAY);

  ID working_mode = SYM2ID(rb_ary_entry(exporter_configuration, 0)); // SYMID verifies its input so we can do this safely

  if (working_mode != agentless_id && working_mode != agent_id) {
    rb_raise(rb_eArgError, "Failed to initialize transport: Unexpected working mode, expected :agentless or :agent");
  }

  if (working_mode == agentless_id) {
    VALUE site = rb_ary_entry(exporter_configuration, 1);
    VALUE api_key = rb_ary_entry(exporter_configuration, 2);
    Check_Type(site, T_STRING);
    Check_Type(api_key, T_STRING);

    return ddprof_ffi_EndpointV3_agentless(byte_slice_from_ruby_string(site), byte_slice_from_ruby_string(api_key));
  } else { // agent_id
    VALUE base_url = rb_ary_entry(exporter_configuration, 1);
    Check_Type(base_url, T_STRING);

    return ddprof_ffi_EndpointV3_agent(byte_slice_from_ruby_string(base_url));
  }
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
  VALUE exporter_configuration,
  VALUE upload_timeout_milliseconds,
  VALUE start_timespec_seconds,
  VALUE start_timespec_nanoseconds,
  VALUE finish_timespec_seconds,
  VALUE finish_timespec_nanoseconds,
  VALUE pprof_file_name,
  VALUE pprof_data,
  VALUE code_provenance_file_name,
  VALUE code_provenance_data,
  VALUE tags_as_array
) {
  ddprof_ffi_NewProfileExporterV3Result exporter_result = create_exporter(exporter_configuration, tags_as_array);

  VALUE failure_tuple = handle_exporter_failure(exporter_result);
  if (!NIL_P(failure_tuple)) return failure_tuple;

  ddprof_ffi_ProfileExporterV3 *exporter = exporter_result.ok;

  ddprof_ffi_Request *request =
    build_request(
      exporter,
      upload_timeout_milliseconds,
      start_timespec_seconds,
      start_timespec_nanoseconds,
      finish_timespec_seconds,
      finish_timespec_nanoseconds,
      pprof_file_name,
      pprof_data,
      code_provenance_file_name,
      code_provenance_data
    );

  // We'll release the Global VM Lock while we're calling send, so that the Ruby VM can continue to work while this
  // is pending
  struct call_exporter_without_gvl_arguments args = {.exporter = exporter, .request = request};
  // TODO: We don't provide a function to interrupt reporting, which means this thread will be blocked until
  // call_exporter_without_gvl returns.
  rb_thread_call_without_gvl(call_exporter_without_gvl, &args, NULL, NULL);
  ddprof_ffi_SendResult result = args.result;

  // Dispose of the exporter
  ddprof_ffi_NewProfileExporterV3Result_dtor(exporter_result);

  // The request itself does not need to be freed as libddprof takes care of it.

  if (result.tag != DDPROF_FFI_SEND_RESULT_HTTP_RESPONSE) {
    VALUE failure_details = rb_str_new((char *) result.failure.ptr, result.failure.len);
    // TODO: This is needed until a proper dtor gets added in libddprof for SendResult; note that the Buffer
    // itself is stack-allocated (so there's nothing to free/clean up there), so we only need to make sure its contents
    // aren't leaked
    ddprof_ffi_Buffer_reset(&result.failure); // Clean up result
    return rb_ary_new_from_args(2, error_symbol, failure_details);
  }

  return rb_ary_new_from_args(2, ok_symbol, UINT2NUM(result.http_response.code));
}

static ddprof_ffi_Request *build_request(
  ddprof_ffi_ProfileExporterV3 *exporter,
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
  Check_Type(upload_timeout_milliseconds, T_FIXNUM);
  Check_Type(start_timespec_seconds, T_FIXNUM);
  Check_Type(start_timespec_nanoseconds, T_FIXNUM);
  Check_Type(finish_timespec_seconds, T_FIXNUM);
  Check_Type(finish_timespec_nanoseconds, T_FIXNUM);
  Check_Type(pprof_file_name, T_STRING);
  Check_Type(pprof_data, T_STRING);
  Check_Type(code_provenance_file_name, T_STRING);

  // Code provenance can be disabled and in that case will be set to nil
  bool have_code_provenance = !NIL_P(code_provenance_data);
  if (have_code_provenance) Check_Type(code_provenance_data, T_STRING);

  uint64_t timeout_milliseconds = NUM2ULONG(upload_timeout_milliseconds);

  ddprof_ffi_Timespec start =
    {.seconds = NUM2LONG(start_timespec_seconds), .nanoseconds = NUM2UINT(start_timespec_nanoseconds)};
  ddprof_ffi_Timespec finish =
    {.seconds = NUM2LONG(finish_timespec_seconds), .nanoseconds = NUM2UINT(finish_timespec_nanoseconds)};

  int files_to_report = 1 + (have_code_provenance ? 1 : 0);
  ddprof_ffi_File files[files_to_report];
  ddprof_ffi_Slice_file slice_files = {.ptr = files, .len = files_to_report};

  files[0] = (ddprof_ffi_File) {
    .name = byte_slice_from_ruby_string(pprof_file_name),
    .file = byte_slice_from_ruby_string(pprof_data)
  };
  if (have_code_provenance) {
    files[1] = (ddprof_ffi_File) {
      .name = byte_slice_from_ruby_string(code_provenance_file_name),
      .file = byte_slice_from_ruby_string(code_provenance_data)
    };
  }

  ddprof_ffi_Request *request =
    ddprof_ffi_ProfileExporterV3_build(exporter, start, finish, slice_files, timeout_milliseconds);

  return request;
}

static void *call_exporter_without_gvl(void *exporter_and_request) {
  struct call_exporter_without_gvl_arguments *args = (struct call_exporter_without_gvl_arguments*) exporter_and_request;

  args->result = ddprof_ffi_ProfileExporterV3_send(args->exporter, args->request);

  return NULL; // Unused
}

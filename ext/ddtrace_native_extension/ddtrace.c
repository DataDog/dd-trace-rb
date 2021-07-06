#include <stdio.h>

#include "ruby.h"

#include <ddprof/exporter.h>

static VALUE native_send(VALUE self, VALUE url, VALUE headers, VALUE body, VALUE timeout_ms);

void Init_ddtrace_native_extension(void) {
  VALUE LibddprofAdapter = rb_const_get(rb_cObject, rb_intern("LibddprofAdapter"));
  rb_define_method(LibddprofAdapter, "native_send", native_send, 4);
}

static VALUE native_send(VALUE _self, VALUE url, VALUE headers, VALUE body, VALUE timeout_ms) {
  const char *c_url = StringValueCStr(url);
  ddprof_exporter_ByteSlice c_body = {.buffer = (uint8_t*) StringValuePtr(body), .len = RSTRING_LEN(body)};
  long c_timeout_ms = FIX2LONG(timeout_ms);

  // Header conversion
  long header_count = rb_array_len(headers);
  ddprof_exporter_Field fields[header_count];

  for (long i = 0; i < header_count; i++) {
    VALUE header_pair = rb_ary_entry(headers, i);
    VALUE name_string = rb_ary_entry(header_pair, 0);
    VALUE value_string = rb_ary_entry(header_pair, 1);
    Check_Type(name_string, T_STRING);
    Check_Type(value_string, T_STRING);

    fields[i] = (ddprof_exporter_Field) {
      .name = StringValueCStr(name_string),
      .value = {
        .buffer = (uint8_t*) StringValuePtr(value_string),
        .len = RSTRING_LEN(value_string)
      },
    };
  }

  ddprof_exporter_Fields c_headers = {
    .len = header_count,
    .data = fields
  };
  // Header conversion end

  enum ddprof_exporter_Status status =
    ddprof_exporter_send("POST", c_url, c_headers, c_body, c_timeout_ms);

  return status == DDPROF_EXPORTER_STATUS_SUCCESS ? Qtrue : Qfalse;
}

#include <ruby.h>

#include "datadog_ruby_common.h"
#include "otel_thread_ctx.h"

// This binding is Linux-only: the underlying libdatadog crate is gated on
// `target_os = "linux"` (it relies on the TLSDESC TLS dialect so an
// out-of-process eBPF profiler can read the record), so the header/symbols
// are absent on other platforms. `HAVE_DATADOG_OTEL_THREAD_CTX_H` is set by
// `have_header` in extconf.rb.
#ifdef HAVE_DATADOG_OTEL_THREAD_CTX_H
#include <datadog/otel-thread-ctx.h>
#endif

static VALUE native_attach_new(VALUE _self);
static VALUE native_detach_and_free(VALUE _self);
static VALUE native_supported_p(VALUE _self);
static VALUE native_debug_peek(VALUE _self);

void otel_thread_ctx_init(VALUE core_module) {
  VALUE otel_thread_ctx_module = rb_define_module_under(core_module, "OTelThreadContext");

  rb_define_singleton_method(otel_thread_ctx_module, "_native_attach_new", native_attach_new, 0);
  rb_define_singleton_method(otel_thread_ctx_module, "_native_detach_and_free", native_detach_and_free, 0);
  rb_define_singleton_method(otel_thread_ctx_module, "_native_supported?", native_supported_p, 0);
  rb_define_singleton_method(otel_thread_ctx_module, "_native_debug_peek", native_debug_peek, 0);
}

#ifdef HAVE_DATADOG_OTEL_THREAD_CTX_H

// Allocates a new thread context record (all-zero trace/span ids, meaning
// "no trace attached yet") and attaches it to the calling (current)
// thread's TLS slot. If a context was already attached (should not
// normally happen), it is freed.
static VALUE native_attach_new(VALUE _self) {
  static const uint8_t zero_trace_id[16] = {0};
  static const uint8_t zero_span_id[8] = {0};

  struct ddog_ThreadContextHandle *ctx = ddog_otel_thread_ctx_new(&zero_trace_id, &zero_span_id, &zero_span_id);
  struct ddog_ThreadContextHandle *previous = ddog_otel_thread_ctx_attach(ctx);

  if (previous) ddog_otel_thread_ctx_free(previous);

  return Qtrue;
}

// Detaches the thread context record currently attached to the calling
// thread (if any) and frees it.
static VALUE native_detach_and_free(VALUE _self) {
  struct ddog_ThreadContextHandle *ctx = ddog_otel_thread_ctx_detach();

  if (ctx) ddog_otel_thread_ctx_free(ctx);

  return Qtrue;
}

static VALUE native_supported_p(VALUE _self) {
  return Qtrue;
}

// Debug-only helper: reads back the record currently attached to the calling
// thread, without disturbing it (detach, read, re-attach). Returns nil if no
// context is attached.
//
// There is no libdatadog API to read a record's fields -- the whole point of
// this feature is that an out-of-process reader (the eBPF profiler) parses the
// raw bytes directly. We do the same here, using the documented, stable wire
// layout (see the `ThreadContextRecord` doc comment in
// `libdd-otel-thread-ctx/src/lib.rs`): trace_id at offset 0 (16 bytes), span_id
// at offset 16 (8 bytes), valid at offset 24 (1 byte), attrs_data_size at
// offset 26 (2 bytes, little-endian), attrs_data at offset 28.
static VALUE native_debug_peek(VALUE _self) {
  struct ddog_ThreadContextHandle *ctx = ddog_otel_thread_ctx_detach();

  if (!ctx) return Qnil;

  const uint8_t *raw = (const uint8_t *) ctx;

  VALUE trace_id = rb_str_new((const char *) raw, 16);
  VALUE span_id = rb_str_new((const char *) (raw + 16), 8);
  VALUE valid = raw[24] ? Qtrue : Qfalse;
  uint16_t attrs_data_size = (uint16_t) raw[26] | ((uint16_t) raw[27] << 8);
  VALUE attrs_data = rb_str_new((const char *) (raw + 28), attrs_data_size);

  // Must return NULL: we just detached the only attached context, and nothing else touches
  // this thread's slot in between.
  struct ddog_ThreadContextHandle *previous = ddog_otel_thread_ctx_attach(ctx);
  if (previous) raise_error(rb_eRuntimeError, "Internal: unexpected context already attached during debug_peek");

  VALUE result = rb_hash_new();
  rb_hash_aset(result, ID2SYM(rb_intern("trace_id")), trace_id);
  rb_hash_aset(result, ID2SYM(rb_intern("span_id")), span_id);
  rb_hash_aset(result, ID2SYM(rb_intern("valid")), valid);
  rb_hash_aset(result, ID2SYM(rb_intern("attrs_data")), attrs_data);

  return result;
}

#else

static VALUE native_attach_new(VALUE _self) {
  return Qfalse;
}

static VALUE native_detach_and_free(VALUE _self) {
  return Qfalse;
}

static VALUE native_supported_p(VALUE _self) {
  return Qfalse;
}

static VALUE native_debug_peek(VALUE _self) {
  return Qnil;
}

#endif

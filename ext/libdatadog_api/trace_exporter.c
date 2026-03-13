#include <ruby.h>
#include <datadog/data-pipeline.h>

#include "datadog_ruby_common.h"
#include "helpers.h"
#include "trace_exporter.h"

/* ========================================================================
 * Forward declarations
 * ======================================================================== */

/* Internal: convert a Ruby Span to a Rust ddog_TracerSpan* (caller owns) */
static ddog_TracerSpan *convert_ruby_span_to_rust(VALUE span);

/* TracerSpan methods */
static VALUE _native_from_span(VALUE klass, VALUE span);
static VALUE tracer_span_name(VALUE self);
static VALUE tracer_span_service(VALUE self);
static VALUE tracer_span_resource(VALUE self);
static VALUE tracer_span_type(VALUE self);
static VALUE tracer_span_span_id(VALUE self);
static VALUE tracer_span_parent_id(VALUE self);
static VALUE tracer_span_trace_id(VALUE self);
static VALUE tracer_span_start(VALUE self);
static VALUE tracer_span_duration(VALUE self);
static VALUE tracer_span_error(VALUE self);
static VALUE tracer_span_get_meta(VALUE self, VALUE key);
static VALUE tracer_span_get_metric(VALUE self, VALUE key);

/* TraceExporter methods */
static VALUE _native_exporter_new(VALUE klass, VALUE rb_url,
  VALUE rb_tracer_version, VALUE rb_language, VALUE rb_language_version,
  VALUE rb_language_interpreter, VALUE rb_hostname, VALUE rb_env,
  VALUE rb_service, VALUE rb_version);
static VALUE _native_send_traces(VALUE self, VALUE traces);

/* Response methods */
static VALUE response_ok_p(VALUE self);
static VALUE response_internal_error_p(VALUE self);
static VALUE response_server_error_p(VALUE self);
static VALUE response_trace_count_m(VALUE self);
static VALUE response_false(DDTRACE_UNUSED VALUE self);
static VALUE response_nil(DDTRACE_UNUSED VALUE self);

/* GC / TypedData */
static void tracer_span_dfree(void *ptr);
static void trace_exporter_dfree(void *ptr);

/* ========================================================================
 * Cached Ruby intern IDs
 * ======================================================================== */

/* Instance variable IDs on Datadog::Tracing::Span */
static ID at_name_id;
static ID at_service_id;
static ID at_resource_id;
static ID at_type_id;
static ID at_id_id;
static ID at_parent_id_id;
static ID at_trace_id_id;
static ID at_start_time_id;
static ID at_duration_id;
static ID at_status_id;
static ID at_meta_id;
static ID at_metrics_id;

/* Method IDs for time / integer operations */
static ID id_to_i;
static ID id_nsec;
static ID id_duration_method;
static ID id_bitand;
static ID id_rshift;
static ID id_bitor;
static ID id_lshift;

/* Response ivar IDs */
static ID at_ok_id;
static ID at_int_error_id;
static ID at_srv_error_id;
static ID at_trace_count_id;

/* ========================================================================
 * Ruby class references (marked as GC roots)
 * ======================================================================== */

static VALUE tracer_span_class    = Qnil;
static VALUE trace_exporter_class = Qnil;
static VALUE response_class       = Qnil;

/* ========================================================================
 * TypedData definitions
 * ======================================================================== */

static const rb_data_type_t tracer_span_typed_data = {
  .wrap_struct_name = "Datadog::Tracing::Transport::LibdatadogNative::TracerSpan",
  .function = {
    .dmark = NULL,
    .dfree = tracer_span_dfree,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static void tracer_span_dfree(void *ptr) {
  if (ptr != NULL) {
    ddog_tracer_span_free((ddog_TracerSpan *)ptr);
  }
}

static const rb_data_type_t trace_exporter_typed_data = {
  .wrap_struct_name = "Datadog::Tracing::Transport::LibdatadogNative::TraceExporter",
  .function = {
    .dmark = NULL,
    .dfree = trace_exporter_dfree,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static void trace_exporter_dfree(void *ptr) {
  if (ptr != NULL) {
    ddog_trace_exporter_free((ddog_TraceExporter *)ptr);
  }
}

/* ========================================================================
 * Error handling
 * ======================================================================== */

/*
 * If +err+ is non-NULL, copies the message, frees the error struct, and
 * raises a Ruby RuntimeError.  Does not return on error.
 */
static inline void check_exporter_error(const char *context,
                                        ddog_TraceExporterError *err) {
  if (err == NULL) return;

  char buf[MAX_RAISE_MESSAGE_SIZE];
  if (err->msg != NULL) {
    snprintf(buf, sizeof(buf), "%s: %s", context, err->msg);
  } else {
    snprintf(buf, sizeof(buf), "%s: (unknown error)", context);
  }
  ddog_trace_exporter_error_free(err);
  raise_error(rb_eRuntimeError, "%s", buf);
}

/* ========================================================================
 * Conversion helpers (Ruby → C, require the GVL)
 * ======================================================================== */

/* Nullable Ruby String → ddog_CharSlice (nil ⟶ empty slice) */
static inline ddog_CharSlice nullable_char_slice(VALUE str) {
  if (str == Qnil) {
    return (ddog_CharSlice){.ptr = "", .len = 0};
  }
  ENFORCE_TYPE(str, T_STRING);
  return (ddog_CharSlice){.ptr = RSTRING_PTR(str), .len = RSTRING_LEN(str)};
}

/* Ruby Time → int64_t nanoseconds since Unix epoch */
static inline int64_t time_to_nanos(VALUE time) {
  VALUE secs = rb_funcall(time, id_to_i, 0);
  VALUE nsec = rb_funcall(time, id_nsec, 0);
  return (int64_t)NUM2LL(secs) * 1000000000LL + (int64_t)NUM2LL(nsec);
}

/* Ruby 128-bit Integer → (low, high) 64-bit halves */
static inline void split_trace_id(VALUE trace_id,
                                   uint64_t *low, uint64_t *high) {
  VALUE mask = ULL2NUM(0xFFFFFFFFFFFFFFFF);
  *low  = NUM2ULL(rb_funcall(trace_id, id_bitand, 1, mask));
  *high = NUM2ULL(rb_funcall(trace_id, id_rshift, 1, INT2FIX(64)));
}

/* (low, high) 64-bit halves → Ruby Integer */
static inline VALUE combine_trace_id(uint64_t low, uint64_t high) {
  if (high == 0) return ULL2NUM(low);
  VALUE hi_val = ULL2NUM(high);
  VALUE shifted = rb_funcall(hi_val, id_lshift, 1, INT2FIX(64));
  return rb_funcall(shifted, id_bitor, 1, ULL2NUM(low));
}

/* CharSlice → Ruby String */
static inline VALUE ruby_string_from_charslice(ddog_CharSlice slice) {
  return rb_str_new((const char *)slice.ptr, (long)slice.len);
}

/* ========================================================================
 * Hash iteration callbacks for meta / metrics
 * ======================================================================== */

static int meta_iter_cb(VALUE key, VALUE value, VALUE arg) {
  ddog_TracerSpan *span = (ddog_TracerSpan *)arg;

  if (!RB_TYPE_P(key, T_STRING) || !RB_TYPE_P(value, T_STRING))
    return ST_CONTINUE;

  ddog_CharSlice ks = {.ptr = RSTRING_PTR(key),   .len = RSTRING_LEN(key)};
  ddog_CharSlice vs = {.ptr = RSTRING_PTR(value), .len = RSTRING_LEN(value)};

  ddog_TraceExporterError *err = ddog_tracer_span_set_meta(span, ks, vs);
  if (err != NULL) ddog_trace_exporter_error_free(err);

  return ST_CONTINUE;
}

static int metrics_iter_cb(VALUE key, VALUE value, VALUE arg) {
  ddog_TracerSpan *span = (ddog_TracerSpan *)arg;

  if (!RB_TYPE_P(key, T_STRING)) return ST_CONTINUE;
  if (!RB_TYPE_P(value, T_FLOAT) && !RB_TYPE_P(value, T_FIXNUM) &&
      !RB_TYPE_P(value, T_BIGNUM))
    return ST_CONTINUE;

  ddog_CharSlice ks = {.ptr = RSTRING_PTR(key), .len = RSTRING_LEN(key)};

  ddog_TraceExporterError *err =
      ddog_tracer_span_set_metric(span, ks, NUM2DBL(value));
  if (err != NULL) ddog_trace_exporter_error_free(err);

  return ST_CONTINUE;
}

/* ========================================================================
 * Internal: convert a Ruby Span → ddog_TracerSpan*
 *
 * The returned pointer is Rust-heap-allocated.  Ownership is transferred
 * to the caller (either wrap it in TypedData or push it into trace chunks).
 * ======================================================================== */

static ddog_TracerSpan *convert_ruby_span_to_rust(VALUE span) {
  /* 1. Read Ruby ivars */
  VALUE rb_name      = rb_ivar_get(span, at_name_id);
  VALUE rb_service   = rb_ivar_get(span, at_service_id);
  VALUE rb_resource  = rb_ivar_get(span, at_resource_id);
  VALUE rb_type      = rb_ivar_get(span, at_type_id);
  VALUE rb_span_id   = rb_ivar_get(span, at_id_id);
  VALUE rb_parent_id = rb_ivar_get(span, at_parent_id_id);
  VALUE rb_trace_id  = rb_ivar_get(span, at_trace_id_id);
  VALUE rb_status    = rb_ivar_get(span, at_status_id);

  /* 2. Convert scalars */
  ddog_CharSlice name_s     = char_slice_from_ruby_string(rb_name);
  ddog_CharSlice service_s  = nullable_char_slice(rb_service);
  ddog_CharSlice resource_s = char_slice_from_ruby_string(rb_resource);
  ddog_CharSlice type_s     = nullable_char_slice(rb_type);

  uint64_t span_id   = NUM2ULL(rb_span_id);
  uint64_t parent_id = NUM2ULL(rb_parent_id);
  int32_t  error_val = NUM2INT(rb_status);

  uint64_t trace_id_low, trace_id_high;
  split_trace_id(rb_trace_id, &trace_id_low, &trace_id_high);

  /* start (ns) */
  int64_t start_ns = 0;
  VALUE rb_start_time = rb_ivar_get(span, at_start_time_id);
  if (rb_start_time != Qnil) {
    start_ns = time_to_nanos(rb_start_time);
  }

  /* duration (ns) */
  int64_t duration_ns = 0;
  VALUE rb_duration_ivar = rb_ivar_get(span, at_duration_id);
  if (rb_duration_ivar != Qnil) {
    duration_ns = (int64_t)(NUM2DBL(rb_duration_ivar) * 1e9);
  } else {
    VALUE dur = rb_funcall(span, id_duration_method, 0);
    if (dur != Qnil) duration_ns = (int64_t)(NUM2DBL(dur) * 1e9);
  }

  /* 3. Create Rust span */
  ddog_TracerSpan *rust_span = NULL;

  ddog_TraceExporterError *err = ddog_tracer_span_new(
      &rust_span,
      service_s, name_s, resource_s, type_s,
      trace_id_low, trace_id_high,
      span_id, parent_id,
      start_ns, duration_ns,
      error_val);
  check_exporter_error("Failed to create TracerSpan", err);

  /* 4. Populate meta and metrics */
  VALUE rb_meta = rb_ivar_get(span, at_meta_id);
  if (RB_TYPE_P(rb_meta, T_HASH) && RHASH_SIZE(rb_meta) > 0) {
    rb_hash_foreach(rb_meta, meta_iter_cb, (VALUE)rust_span);
  }

  VALUE rb_metrics = rb_ivar_get(span, at_metrics_id);
  if (RB_TYPE_P(rb_metrics, T_HASH) && RHASH_SIZE(rb_metrics) > 0) {
    rb_hash_foreach(rb_metrics, metrics_iter_cb, (VALUE)rust_span);
  }

  return rust_span;
}

/* ========================================================================
 * TracerSpan._native_from_span — wraps conversion result as Ruby TypedData
 * ======================================================================== */

static VALUE _native_from_span(DDTRACE_UNUSED VALUE klass, VALUE span) {
  ddog_TracerSpan *rust_span = convert_ruby_span_to_rust(span);
  return TypedData_Wrap_Struct(tracer_span_class, &tracer_span_typed_data,
                               rust_span);
}

/* ========================================================================
 * TracerSpan reader methods
 * ======================================================================== */

#define GET_SPAN(self, var)                                                \
  ddog_TracerSpan *var;                                                    \
  TypedData_Get_Struct(self, ddog_TracerSpan, &tracer_span_typed_data, var)

static VALUE tracer_span_name(VALUE self) {
  GET_SPAN(self, span);
  return ruby_string_from_charslice(ddog_tracer_span_get_name(span));
}

static VALUE tracer_span_service(VALUE self) {
  GET_SPAN(self, span);
  return ruby_string_from_charslice(ddog_tracer_span_get_service(span));
}

static VALUE tracer_span_resource(VALUE self) {
  GET_SPAN(self, span);
  return ruby_string_from_charslice(ddog_tracer_span_get_resource(span));
}

static VALUE tracer_span_type(VALUE self) {
  GET_SPAN(self, span);
  return ruby_string_from_charslice(ddog_tracer_span_get_type(span));
}

static VALUE tracer_span_span_id(VALUE self) {
  GET_SPAN(self, span);
  return ULL2NUM(ddog_tracer_span_get_span_id(span));
}

static VALUE tracer_span_parent_id(VALUE self) {
  GET_SPAN(self, span);
  return ULL2NUM(ddog_tracer_span_get_parent_id(span));
}

static VALUE tracer_span_trace_id(VALUE self) {
  GET_SPAN(self, span);
  uint64_t low, high;
  ddog_tracer_span_get_trace_id(span, &low, &high);
  return combine_trace_id(low, high);
}

static VALUE tracer_span_start(VALUE self) {
  GET_SPAN(self, span);
  return LL2NUM(ddog_tracer_span_get_start(span));
}

static VALUE tracer_span_duration(VALUE self) {
  GET_SPAN(self, span);
  return LL2NUM(ddog_tracer_span_get_duration(span));
}

static VALUE tracer_span_error(VALUE self) {
  GET_SPAN(self, span);
  return INT2NUM(ddog_tracer_span_get_error(span));
}

static VALUE tracer_span_get_meta(VALUE self, VALUE key) {
  GET_SPAN(self, span);
  ENFORCE_TYPE(key, T_STRING);

  ddog_CharSlice key_s = char_slice_from_ruby_string(key);
  const uint8_t *out_ptr = NULL;
  size_t out_len = 0;

  if (ddog_tracer_span_get_meta(span, key_s, &out_ptr, &out_len)) {
    return rb_str_new((const char *)out_ptr, (long)out_len);
  }
  return Qnil;
}

static VALUE tracer_span_get_metric(VALUE self, VALUE key) {
  GET_SPAN(self, span);
  ENFORCE_TYPE(key, T_STRING);

  ddog_CharSlice key_s = char_slice_from_ruby_string(key);
  double out_val = 0.0;

  if (ddog_tracer_span_get_metric(span, key_s, &out_val)) {
    return DBL2NUM(out_val);
  }
  return Qnil;
}

#undef GET_SPAN

/* ========================================================================
 * Response class helpers
 * ======================================================================== */

static VALUE create_response(bool ok, bool internal_error,
                              bool server_error, long trace_count) {
  VALUE resp = rb_obj_alloc(response_class);
  rb_ivar_set(resp, at_ok_id,         ok ? Qtrue : Qfalse);
  rb_ivar_set(resp, at_int_error_id,  internal_error ? Qtrue : Qfalse);
  rb_ivar_set(resp, at_srv_error_id,  server_error ? Qtrue : Qfalse);
  rb_ivar_set(resp, at_trace_count_id, LONG2NUM(trace_count));
  return resp;
}

static VALUE response_ok_p(VALUE self) {
  return rb_ivar_get(self, at_ok_id);
}

static VALUE response_internal_error_p(VALUE self) {
  return rb_ivar_get(self, at_int_error_id);
}

static VALUE response_server_error_p(VALUE self) {
  return rb_ivar_get(self, at_srv_error_id);
}

static VALUE response_trace_count_m(VALUE self) {
  return rb_ivar_get(self, at_trace_count_id);
}

static VALUE response_false(DDTRACE_UNUSED VALUE self) { return Qfalse; }
static VALUE response_nil(DDTRACE_UNUSED VALUE self)   { return Qnil; }

/* ========================================================================
 * TraceExporter._native_new
 *
 * Creates a Rust TraceExporter with the given configuration.
 *
 * Ruby signature:
 *   TraceExporter._native_new(url, tracer_version, language,
 *     language_version, language_interpreter, hostname, env,
 *     service, version) → TraceExporter
 *
 * +url+ is required (String).  All other arguments may be nil.
 * ======================================================================== */

static VALUE _native_exporter_new(
    DDTRACE_UNUSED VALUE klass,
    VALUE rb_url,
    VALUE rb_tracer_version,
    VALUE rb_language,
    VALUE rb_language_version,
    VALUE rb_language_interpreter,
    VALUE rb_hostname,
    VALUE rb_env,
    VALUE rb_service,
    VALUE rb_version
) {
  /* Phase 1: validate types (may raise, no Rust resources yet) */
  ENFORCE_TYPE(rb_url, T_STRING);
  if (rb_tracer_version    != Qnil) ENFORCE_TYPE(rb_tracer_version,    T_STRING);
  if (rb_language           != Qnil) ENFORCE_TYPE(rb_language,           T_STRING);
  if (rb_language_version   != Qnil) ENFORCE_TYPE(rb_language_version,   T_STRING);
  if (rb_language_interpreter != Qnil) ENFORCE_TYPE(rb_language_interpreter, T_STRING);
  if (rb_hostname           != Qnil) ENFORCE_TYPE(rb_hostname,           T_STRING);
  if (rb_env                != Qnil) ENFORCE_TYPE(rb_env,                T_STRING);
  if (rb_service            != Qnil) ENFORCE_TYPE(rb_service,            T_STRING);
  if (rb_version            != Qnil) ENFORCE_TYPE(rb_version,            T_STRING);

  /* Phase 2: create config (cleanup on error) */
  ddog_TraceExporterConfig *config = NULL;
  ddog_trace_exporter_config_new(&config);
  if (config == NULL) {
    raise_error(rb_eRuntimeError, "Failed to allocate TraceExporter config");
  }

  ddog_TraceExporterError *err;

#define SET_CONFIG(setter, rb_val, label)                                    \
  do {                                                                       \
    if (rb_val != Qnil) {                                                    \
      err = setter(config, char_slice_from_ruby_string(rb_val));             \
      if (err) {                                                             \
        ddog_trace_exporter_config_free(config);                             \
        check_exporter_error("TraceExporter config: failed to set " label,  \
                             err);                                           \
      }                                                                      \
    }                                                                        \
  } while (0)

  SET_CONFIG(ddog_trace_exporter_config_set_url,              rb_url,                  "url");
  SET_CONFIG(ddog_trace_exporter_config_set_tracer_version,   rb_tracer_version,       "tracer_version");
  SET_CONFIG(ddog_trace_exporter_config_set_language,          rb_language,              "language");
  SET_CONFIG(ddog_trace_exporter_config_set_lang_version,     rb_language_version,     "language_version");
  SET_CONFIG(ddog_trace_exporter_config_set_lang_interpreter, rb_language_interpreter, "language_interpreter");
  SET_CONFIG(ddog_trace_exporter_config_set_hostname,          rb_hostname,              "hostname");
  SET_CONFIG(ddog_trace_exporter_config_set_env,               rb_env,                   "env");
  SET_CONFIG(ddog_trace_exporter_config_set_service,           rb_service,               "service");
  SET_CONFIG(ddog_trace_exporter_config_set_version,           rb_version,               "version");

#undef SET_CONFIG

  /* Phase 3: build the exporter from the config */
  ddog_TraceExporter *exporter = NULL;
  err = ddog_trace_exporter_new(&exporter, config);
  ddog_trace_exporter_config_free(config);
  config = NULL;

  if (err) {
    check_exporter_error("Failed to create TraceExporter", err);
  }

  return TypedData_Wrap_Struct(trace_exporter_class, &trace_exporter_typed_data,
                               exporter);
}

/* ========================================================================
 * TraceExporter#_native_send_traces
 *
 * Ruby signature:
 *   exporter._native_send_traces(traces) → Array[Response]
 *
 * +traces+ is an Array of Arrays of Spans:
 *   [[span, span, ...], [span, ...], ...]
 *
 * Each inner array maps to one trace chunk (Vec<Span> in Rust).
 *
 * On success returns [Response(ok: true, trace_count: N)].
 * On error returns [Response(ok: false, ...)].
 * ======================================================================== */

static VALUE _native_send_traces(VALUE self, VALUE traces) {
  ENFORCE_TYPE(traces, T_ARRAY);

  ddog_TraceExporter *exporter;
  TypedData_Get_Struct(self, ddog_TraceExporter, &trace_exporter_typed_data,
                       exporter);
  if (exporter == NULL) {
    raise_error(rb_eRuntimeError,
                "TraceExporter has not been initialized or was already freed");
  }

  long trace_count = RARRAY_LEN(traces);

  /* Empty batch → empty response (matches existing transport behaviour) */
  if (trace_count == 0) {
    return rb_ary_new();
  }

  /* Build trace chunks */
  ddog_TracerTraceChunks *chunks = NULL;
  ddog_tracer_trace_chunks_new(&chunks);
  if (chunks == NULL) {
    raise_error(rb_eRuntimeError, "Failed to allocate trace chunks");
  }

  for (long i = 0; i < trace_count; i++) {
    VALUE chunk_spans = rb_ary_entry(traces, i);
    ENFORCE_TYPE(chunk_spans, T_ARRAY);

    ddog_tracer_trace_chunks_begin_chunk(chunks);

    long span_count = RARRAY_LEN(chunk_spans);
    for (long j = 0; j < span_count; j++) {
      VALUE rb_span = rb_ary_entry(chunk_spans, j);

      /*
       * convert_ruby_span_to_rust may raise (type errors, etc.).
       * If it does, we need to free chunks.  We use rb_protect so we
       * can clean up before re-raising.
       */
      ddog_TracerSpan *rust_span = convert_ruby_span_to_rust(rb_span);

      /*
       * push_span consumes rust_span (ownership transferred to chunks).
       * On error the span is still consumed.
       */
      ddog_TraceExporterError *push_err =
          ddog_tracer_trace_chunks_push_span(chunks, rust_span);
      if (push_err != NULL) {
        ddog_trace_exporter_error_free(push_err);
        /* span already consumed; continue with next */
      }
    }
  }

  /* Send — consumes chunks regardless of outcome */
  ddog_TraceExporterResponse *response = NULL;
  ddog_TraceExporterError *send_err =
      ddog_trace_exporter_send_trace_chunks(exporter, chunks, &response);
  /* chunks is now consumed; do NOT free it */

  if (response != NULL) {
    ddog_trace_exporter_response_free(response);
    response = NULL;
  }

  if (send_err != NULL) {
    bool is_server_err =
        (send_err->code == DDOG_TRACE_EXPORTER_ERROR_CODE_HTTP_SERVER);
    ddog_trace_exporter_error_free(send_err);

    VALUE err_resp = create_response(false, !is_server_err, is_server_err,
                                      trace_count);
    return rb_ary_new_from_args(1, err_resp);
  }

  VALUE ok_resp = create_response(true, false, false, trace_count);
  return rb_ary_new_from_args(1, ok_resp);
}

/* ========================================================================
 * Initialization — called from init.c
 * ======================================================================== */

void trace_exporter_init(VALUE tracing_module) {
  /* -- Module hierarchy -- */
  VALUE transport_module = rb_define_module_under(tracing_module, "Transport");
  VALUE native_module =
      rb_define_module_under(transport_module, "LibdatadogNative");

  /* ----------------------------------------------------------------
   * TracerSpan class
   * ---------------------------------------------------------------- */
  tracer_span_class =
      rb_define_class_under(native_module, "TracerSpan", rb_cObject);
  rb_global_variable(&tracer_span_class);
  rb_undef_alloc_func(tracer_span_class);

  /* Factory */
  rb_define_singleton_method(tracer_span_class, "_native_from_span",
                             _native_from_span, 1);

  /* Readers */
  rb_define_method(tracer_span_class, "name",      tracer_span_name,      0);
  rb_define_method(tracer_span_class, "service",   tracer_span_service,   0);
  rb_define_method(tracer_span_class, "resource",  tracer_span_resource,  0);
  rb_define_method(tracer_span_class, "type",      tracer_span_type,      0);
  rb_define_method(tracer_span_class, "span_id",   tracer_span_span_id,   0);
  rb_define_method(tracer_span_class, "parent_id", tracer_span_parent_id, 0);
  rb_define_method(tracer_span_class, "trace_id",  tracer_span_trace_id,  0);
  rb_define_method(tracer_span_class, "start",     tracer_span_start,     0);
  rb_define_method(tracer_span_class, "duration",  tracer_span_duration,  0);
  rb_define_method(tracer_span_class, "error",     tracer_span_error,     0);
  rb_define_method(tracer_span_class, "get_meta",  tracer_span_get_meta,  1);
  rb_define_method(tracer_span_class, "get_metric", tracer_span_get_metric, 1);

  /* ----------------------------------------------------------------
   * TraceExporter class
   * ---------------------------------------------------------------- */
  trace_exporter_class =
      rb_define_class_under(native_module, "TraceExporter", rb_cObject);
  rb_global_variable(&trace_exporter_class);
  rb_undef_alloc_func(trace_exporter_class);

  /* Factory: _native_new(url, tracer_version, language, language_version,
   *                       language_interpreter, hostname, env, service,
   *                       version) */
  rb_define_singleton_method(trace_exporter_class, "_native_new",
                             _native_exporter_new, 9);

  /* Instance: _native_send_traces(traces) → Array[Response] */
  rb_define_method(trace_exporter_class, "_native_send_traces",
                   _native_send_traces, 1);

  /* ----------------------------------------------------------------
   * Response class — lightweight response compatible with Writer
   * ---------------------------------------------------------------- */
  response_class =
      rb_define_class_under(native_module, "Response", rb_cObject);
  rb_global_variable(&response_class);

  rb_define_method(response_class, "ok?",             response_ok_p,              0);
  rb_define_method(response_class, "internal_error?",  response_internal_error_p,  0);
  rb_define_method(response_class, "server_error?",    response_server_error_p,    0);
  rb_define_method(response_class, "trace_count",      response_trace_count_m,     0);
  /* Stubs expected by Transport::Response */
  rb_define_method(response_class, "unsupported?",     response_false,             0);
  rb_define_method(response_class, "not_found?",       response_false,             0);
  rb_define_method(response_class, "client_error?",    response_false,             0);
  rb_define_method(response_class, "payload",          response_nil,               0);

  /* ----------------------------------------------------------------
   * Cache Ruby intern IDs
   * ---------------------------------------------------------------- */

  /* Span ivars */
  at_name_id       = rb_intern("@name");
  at_service_id    = rb_intern("@service");
  at_resource_id   = rb_intern("@resource");
  at_type_id       = rb_intern("@type");
  at_id_id         = rb_intern("@id");
  at_parent_id_id  = rb_intern("@parent_id");
  at_trace_id_id   = rb_intern("@trace_id");
  at_start_time_id = rb_intern("@start_time");
  at_duration_id   = rb_intern("@duration");
  at_status_id     = rb_intern("@status");
  at_meta_id       = rb_intern("@meta");
  at_metrics_id    = rb_intern("@metrics");

  /* Methods */
  id_to_i            = rb_intern("to_i");
  id_nsec            = rb_intern("nsec");
  id_duration_method = rb_intern("duration");
  id_bitand          = rb_intern("&");
  id_rshift          = rb_intern(">>");
  id_bitor           = rb_intern("|");
  id_lshift          = rb_intern("<<");

  /* Response ivars */
  at_ok_id          = rb_intern("@ok");
  at_int_error_id   = rb_intern("@internal_error");
  at_srv_error_id   = rb_intern("@server_error");
  at_trace_count_id = rb_intern("@trace_count");
}
#include <ruby.h>
#include <ruby/thread.h>
#include <stdbool.h>
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

/* TraceExporter methods */
static VALUE _native_exporter_new(VALUE klass, VALUE rb_url,
  VALUE rb_tracer_version, VALUE rb_language, VALUE rb_language_version,
  VALUE rb_language_interpreter, VALUE rb_hostname, VALUE rb_env,
  VALUE rb_service, VALUE rb_version);
static VALUE _native_send_traces(VALUE self, VALUE traces);

/* Response helpers */
static VALUE create_ok_response(long trace_count, VALUE payload);
static VALUE create_error_response(ddog_TraceExporterErrorCode code,
                                    long trace_count);
static VALUE response_ok_p(VALUE self);
static VALUE response_internal_error_p(VALUE self);
static VALUE response_server_error_p(VALUE self);
static VALUE response_client_error_p(VALUE self);
static VALUE response_not_found_p(VALUE self);
static VALUE response_unsupported_p(VALUE self);
static VALUE response_trace_count_m(VALUE self);
static VALUE response_payload(VALUE self);

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

/* Response ivar IDs */
static ID at_ok_id;
static ID at_int_error_id;
static ID at_srv_error_id;
static ID at_cli_error_id;
static ID at_not_found_id;
static ID at_unsupported_id;
static ID at_trace_count_id;
static ID at_payload_id;

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
  .wrap_struct_name = "Datadog::Tracing::Transport::Native::TracerSpan",
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
  .wrap_struct_name = "Datadog::Tracing::Transport::Native::TraceExporter",
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
 * Config helpers
 * ======================================================================== */

typedef ddog_TraceExporterError *(*config_setter_fn)(
    ddog_TraceExporterConfig *, ddog_CharSlice);

static inline void set_config_field(
    ddog_TraceExporterConfig *config,
    config_setter_fn setter,
    VALUE rb_val,
    const char *label) {
  if (rb_val == Qnil) return;

  ddog_TraceExporterError *err =
      setter(config, char_slice_from_ruby_string(rb_val));
  if (err) {
    ddog_trace_exporter_config_free(config);
    check_exporter_error(label, err);
  }
}

/* ========================================================================
 * Conversion helpers (Ruby -> C, require the GVL)
 * ======================================================================== */

/* Nullable Ruby String -> ddog_CharSlice (nil -> empty slice) */
static inline ddog_CharSlice nullable_char_slice(VALUE str) {
  if (str == Qnil) {
    return (ddog_CharSlice){.ptr = "", .len = 0};
  }
  return char_slice_from_ruby_string(str);
}

/* Ruby Time -> int64_t nanoseconds since Unix epoch */
static inline int64_t time_to_nanos(VALUE time) {
  VALUE secs = rb_funcall(time, id_to_i, 0);
  VALUE nsec = rb_funcall(time, id_nsec, 0);
  return (int64_t)NUM2LL(secs) * 1000000000LL + (int64_t)NUM2LL(nsec);
}

/* 128-bit trace ID split into two 64-bit halves */
typedef struct {
  uint64_t low;
  uint64_t high;
} trace_id_t;

/* Ruby 128-bit Integer -> trace_id_t */
static inline trace_id_t split_trace_id(VALUE trace_id) {
  VALUE mask = ULL2NUM(0xFFFFFFFFFFFFFFFF);
  return (trace_id_t){
    .low  = NUM2ULL(rb_funcall(trace_id, id_bitand, 1, mask)),
    .high = NUM2ULL(rb_funcall(trace_id, id_rshift, 1, INT2FIX(64))),
  };
}

/* ========================================================================
 * Hash iteration callbacks for meta / metrics
 *
 * We cannot raise Ruby exceptions from inside rb_hash_foreach callbacks
 * (longjmp would corrupt the hash iteration state).  Instead, the first
 * error is stashed in a context struct and iteration is stopped with
 * ST_STOP.  The caller checks for the error after rb_hash_foreach
 * returns.
 * ======================================================================== */

typedef struct {
  ddog_TracerSpan        *span;
  ddog_TraceExporterError *error;  /* first error, if any */
} hash_iter_ctx;

static int meta_iter_cb(VALUE key, VALUE value, VALUE arg) {
  hash_iter_ctx *ctx = (hash_iter_ctx *)arg;

  /*
   * We intentionally use direct struct initialization instead of
   * char_slice_from_ruby_string() here: that helper contains
   * ENFORCE_TYPE which can raise, and raising inside an
   * rb_hash_foreach callback would longjmp out of the hash
   * iteration and corrupt internal VM state.
   */
  if (!RB_TYPE_P(key, T_STRING) || !RB_TYPE_P(value, T_STRING))
    return ST_CONTINUE;

  ddog_CharSlice ks = {.ptr = RSTRING_PTR(key),   .len = RSTRING_LEN(key)};
  ddog_CharSlice vs = {.ptr = RSTRING_PTR(value), .len = RSTRING_LEN(value)};

  ddog_TraceExporterError *err = ddog_tracer_span_set_meta(ctx->span, ks, vs);
  if (err != NULL) {
    ctx->error = err;
    return ST_STOP;
  }

  return ST_CONTINUE;
}

static int metrics_iter_cb(VALUE key, VALUE value, VALUE arg) {
  hash_iter_ctx *ctx = (hash_iter_ctx *)arg;

  if (!RB_TYPE_P(key, T_STRING)) return ST_CONTINUE;
  if (!RB_TYPE_P(value, T_FLOAT) && !RB_TYPE_P(value, T_FIXNUM) &&
      !RB_TYPE_P(value, T_BIGNUM))
    return ST_CONTINUE;

  /* See meta_iter_cb for why we avoid char_slice_from_ruby_string() here. */
  ddog_CharSlice ks = {.ptr = RSTRING_PTR(key), .len = RSTRING_LEN(key)};

  ddog_TraceExporterError *err =
      ddog_tracer_span_set_metric(ctx->span, ks, NUM2DBL(value));
  if (err != NULL) {
    ctx->error = err;
    return ST_STOP;
  }

  return ST_CONTINUE;
}

/* ========================================================================
 * Internal: convert a Ruby Span -> ddog_TracerSpan*
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

  trace_id_t trace_id = split_trace_id(rb_trace_id);

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
      trace_id.low, trace_id.high,
      span_id, parent_id,
      start_ns, duration_ns,
      error_val);
  check_exporter_error("Failed to create TracerSpan", err);

  /* 4. Populate meta and metrics */
  hash_iter_ctx ctx = {.span = rust_span, .error = NULL};

  VALUE rb_meta = rb_ivar_get(span, at_meta_id);
  if (RB_TYPE_P(rb_meta, T_HASH) && RHASH_SIZE(rb_meta) > 0) {
    rb_hash_foreach(rb_meta, meta_iter_cb, (VALUE)&ctx);
    if (ctx.error != NULL) {
      ddog_tracer_span_free(rust_span);
      check_exporter_error("Failed to set span meta", ctx.error);
    }
  }

  VALUE rb_metrics = rb_ivar_get(span, at_metrics_id);
  if (RB_TYPE_P(rb_metrics, T_HASH) && RHASH_SIZE(rb_metrics) > 0) {
    rb_hash_foreach(rb_metrics, metrics_iter_cb, (VALUE)&ctx);
    if (ctx.error != NULL) {
      ddog_tracer_span_free(rust_span);
      check_exporter_error("Failed to set span metric", ctx.error);
    }
  }

  return rust_span;
}

/* ========================================================================
 * TracerSpan._native_from_span
 * ======================================================================== */

static VALUE _native_from_span(DDTRACE_UNUSED VALUE klass, VALUE span) {
  ddog_TracerSpan *rust_span = convert_ruby_span_to_rust(span);
  return TypedData_Wrap_Struct(tracer_span_class, &tracer_span_typed_data,
                               rust_span);
}

/* ========================================================================
 * Response class helpers
 * ======================================================================== */

/*
 * Build an error response, classifying the error code into the
 * Transport::Response categories:
 *
 *   HTTP_CLIENT  -> client_error? (4xx family)
 *   HTTP_SERVER  -> server_error? (5xx family)
 *   everything else -> internal_error?
 */
static VALUE create_error_response(ddog_TraceExporterErrorCode code,
                                    long trace_count) {
  bool client_err = (code == DDOG_TRACE_EXPORTER_ERROR_CODE_HTTP_CLIENT);
  bool server_err = (code == DDOG_TRACE_EXPORTER_ERROR_CODE_HTTP_SERVER);
  bool internal   = !client_err && !server_err;

  VALUE resp = rb_obj_alloc(response_class);
  rb_ivar_set(resp, at_ok_id,           Qfalse);
  rb_ivar_set(resp, at_int_error_id,    internal   ? Qtrue : Qfalse);
  rb_ivar_set(resp, at_srv_error_id,    server_err ? Qtrue : Qfalse);
  rb_ivar_set(resp, at_cli_error_id,    client_err ? Qtrue : Qfalse);
  rb_ivar_set(resp, at_not_found_id,    Qfalse);
  rb_ivar_set(resp, at_unsupported_id,  Qfalse);
  rb_ivar_set(resp, at_trace_count_id,  LONG2NUM(trace_count));
  rb_ivar_set(resp, at_payload_id,      Qnil);
  return resp;
}

/*
 * Build a success response, optionally carrying the agent's response body
 * as +payload+.
 *
 * +payload+ is the raw HTTP response body returned by the Datadog Agent
 * (typically JSON containing +rate_by_service+).  It is surfaced here so
 * that callers matching the +Datadog::Core::Transport::Response+ interface
 * can parse service sampling rates, just as the Net::HTTP transport does.
 */
static VALUE create_ok_response(long trace_count, VALUE payload) {
  VALUE resp = rb_obj_alloc(response_class);
  rb_ivar_set(resp, at_ok_id,           Qtrue);
  rb_ivar_set(resp, at_int_error_id,    Qfalse);
  rb_ivar_set(resp, at_srv_error_id,    Qfalse);
  rb_ivar_set(resp, at_cli_error_id,    Qfalse);
  rb_ivar_set(resp, at_not_found_id,    Qfalse);
  rb_ivar_set(resp, at_unsupported_id,  Qfalse);
  rb_ivar_set(resp, at_trace_count_id,  LONG2NUM(trace_count));
  rb_ivar_set(resp, at_payload_id,      payload);
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

static VALUE response_client_error_p(VALUE self) {
  return rb_ivar_get(self, at_cli_error_id);
}

static VALUE response_not_found_p(VALUE self) {
  return rb_ivar_get(self, at_not_found_id);
}

static VALUE response_unsupported_p(VALUE self) {
  return rb_ivar_get(self, at_unsupported_id);
}

static VALUE response_trace_count_m(VALUE self) {
  return rb_ivar_get(self, at_trace_count_id);
}

/*
 * The raw HTTP response body from the Datadog Agent (typically JSON).
 *
 * The HTTP-based trace transport uses this to parse the
 * +rate_by_service+ map that the agent returns after accepting
 * traces, which feeds back into client-side sampling rate
 * decisions.  For the native transport this body is extracted
 * from +ddog_trace_exporter_response_get_body+ on success, and is
 * +nil+ on error or when the agent returned an empty body.
 */
static VALUE response_payload(VALUE self) {
  return rb_ivar_get(self, at_payload_id);
}

/* ========================================================================
 * TraceExporter._native_new
 *
 * Creates a Rust TraceExporter with the given configuration.
 *
 * Ruby signature:
 *   TraceExporter._native_new(url, tracer_version, language,
 *     language_version, language_interpreter, hostname, env,
 *     service, version) -> TraceExporter
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
  if (rb_tracer_version       != Qnil) ENFORCE_TYPE(rb_tracer_version,       T_STRING);
  if (rb_language             != Qnil) ENFORCE_TYPE(rb_language,             T_STRING);
  if (rb_language_version     != Qnil) ENFORCE_TYPE(rb_language_version,     T_STRING);
  if (rb_language_interpreter != Qnil) ENFORCE_TYPE(rb_language_interpreter, T_STRING);
  if (rb_hostname             != Qnil) ENFORCE_TYPE(rb_hostname,             T_STRING);
  if (rb_env                  != Qnil) ENFORCE_TYPE(rb_env,                  T_STRING);
  if (rb_service              != Qnil) ENFORCE_TYPE(rb_service,              T_STRING);
  if (rb_version              != Qnil) ENFORCE_TYPE(rb_version,              T_STRING);

  /* Phase 2: create config (cleanup on error) */
  ddog_TraceExporterConfig *config = NULL;
  ddog_trace_exporter_config_new(&config);

  set_config_field(config, ddog_trace_exporter_config_set_url,               rb_url,                   "url");
  set_config_field(config, ddog_trace_exporter_config_set_tracer_version,    rb_tracer_version,        "tracer_version");
  set_config_field(config, ddog_trace_exporter_config_set_language,          rb_language,              "language");
  set_config_field(config, ddog_trace_exporter_config_set_lang_version,      rb_language_version,      "language_version");
  set_config_field(config, ddog_trace_exporter_config_set_lang_interpreter,  rb_language_interpreter,  "language_interpreter");
  set_config_field(config, ddog_trace_exporter_config_set_hostname,          rb_hostname,              "hostname");
  set_config_field(config, ddog_trace_exporter_config_set_env,               rb_env,                   "env");
  set_config_field(config, ddog_trace_exporter_config_set_service,           rb_service,               "service");
  set_config_field(config, ddog_trace_exporter_config_set_version,           rb_version,               "version");

  /* Phase 3: build the exporter from the config */
  ddog_TraceExporter *exporter = NULL;
  ddog_TraceExporterError *err = ddog_trace_exporter_new(&exporter, config);
  ddog_trace_exporter_config_free(config);
  config = NULL;

  if (err) {
    check_exporter_error("Failed to create TraceExporter", err);
  }

  return TypedData_Wrap_Struct(trace_exporter_class, &trace_exporter_typed_data,
                               exporter);
}

/* ========================================================================
 * GVL-release helper for ddog_trace_exporter_send_trace_chunks
 *
 * The send call performs blocking network I/O.  Releasing the GVL lets
 * other Ruby threads (application code, test mock servers, etc.) run
 * while we wait for the agent's response.
 * ======================================================================== */

typedef struct {
  const ddog_TraceExporter       *exporter;
  ddog_TracerTraceChunks         *chunks;
  ddog_TraceExporterResponse     *response;
  ddog_TraceExporterErrorCode     error_code;
  bool                            failed;
  bool                            send_ran;
} send_chunks_args_t;

static void *send_chunks_without_gvl(void *data) {
  send_chunks_args_t *args = (send_chunks_args_t *)data;
  ddog_TraceExporterError *err = ddog_trace_exporter_send_trace_chunks(
      args->exporter, args->chunks, &args->response);
  if (err != NULL) {
    args->error_code = err->code;
    args->failed = true;
    ddog_trace_exporter_error_free(err);
  }
  args->send_ran = true;
  return NULL;
}

/*
 * Check for a pending Ruby exception without raising it.
 * Mirrors the profiling extension's check_if_pending_exception().
 */
static VALUE process_pending_interruptions(DDTRACE_UNUSED VALUE _) {
  rb_thread_check_ints();
  return Qnil;
}

__attribute__((warn_unused_result))
static int check_if_pending_exception(void) {
  int pending_exception;
  rb_protect(process_pending_interruptions, Qnil, &pending_exception);
  return pending_exception;
}

/* ========================================================================
 * TraceExporter#_native_send_traces
 *
 * Ruby signature:
 *   exporter._native_send_traces(traces) -> Array[Response]
 *
 * +traces+ is an Array of Arrays of Spans:
 *   [[span, span, ...], [span, ...], ...]
 *
 * Each inner array maps to one trace chunk (Vec<Span> in Rust).
 *
 * On success returns [Response(ok: true, trace_count: N)].
 * On error returns [Response(ok: false, ...)].
 *
 * The chunk-building loop calls into Ruby (ENFORCE_TYPE,
 * convert_ruby_span_to_rust) which may raise.  We use rb_ensure so
 * that the Rust-allocated chunks are freed if an exception fires
 * before the send consumes them.
 * ======================================================================== */

/* Context shared between the body and ensure callbacks. */
typedef struct {
  const ddog_TraceExporter *exporter;
  VALUE                     traces;
  long                      trace_count;
  ddog_TracerTraceChunks   *chunks;  /* NULL after send consumes it */
} send_traces_ctx;

/*
 * Body: build trace chunks from Ruby spans, then send them.
 * Passed to rb_ensure as the "try" block.
 */
static VALUE build_and_send_traces(VALUE arg) {
  send_traces_ctx *ctx = (send_traces_ctx *)arg;

  for (long i = 0; i < ctx->trace_count; i++) {
    VALUE chunk_spans = rb_ary_entry(ctx->traces, i);
    ENFORCE_TYPE(chunk_spans, T_ARRAY);

    ddog_tracer_trace_chunks_begin_chunk(ctx->chunks);

    long span_count = RARRAY_LEN(chunk_spans);
    for (long j = 0; j < span_count; j++) {
      VALUE rb_span = rb_ary_entry(chunk_spans, j);

      /* convert_ruby_span_to_rust may raise (type errors, etc.).
       * rb_ensure guarantees chunks is freed in that case. */
      ddog_TracerSpan *rust_span = convert_ruby_span_to_rust(rb_span);

      /* push_span consumes rust_span (ownership transferred to chunks).
       * The error path is unreachable in practice: push only fails if no
       * chunk was started (we always call begin_chunk above) or if the
       * handle is NULL.  Free defensively just in case. */
      ddog_TraceExporterError *push_err =
          ddog_tracer_trace_chunks_push_span(ctx->chunks, rust_span);
      if (push_err != NULL) {
        ddog_trace_exporter_error_free(push_err);
      }
    }
  }

  /*
   * Send -- consumes chunks regardless of outcome.
   *
   * Release the GVL so other Ruby threads can run during network I/O.
   *
   * We use rb_thread_call_without_gvl2 (not the plain variant) because
   * the "2" variant does NOT automatically raise pending interrupts
   * after the call returns.  This matters because chunks has already
   * been consumed by the Rust side, and we must inspect send_err /
   * response before any Ruby exception propagates -- otherwise we
   * would leak those Rust-allocated objects.
   *
   * An interrupt (e.g. Thread#kill) may cause gvl2 to return before
   * our function runs, so we loop until it does.
   */
  send_chunks_args_t args = {
    .exporter     = ctx->exporter,
    .chunks       = ctx->chunks,
    .response     = NULL,
    .failed       = false,
    .send_ran     = false,
  };

  int pending_exception = 0;
  while (!args.send_ran && !pending_exception) {
    rb_thread_call_without_gvl2(
        send_chunks_without_gvl, &args,
        RUBY_UBF_IO, NULL);

    if (!args.send_ran) {
      pending_exception = check_if_pending_exception();
    }
  }
  /* Only null chunks when the send actually ran and consumed them.
   * If an interrupt fired before the send executed, chunks are still
   * live and the ensure handler must free them. */
  if (args.send_ran) {
    ctx->chunks = NULL;
  }

  /* Extract the response body as a Ruby string before freeing. */
  VALUE payload = Qnil;
  if (args.response != NULL) {
    uintptr_t body_len = 0;
    const uint8_t *body_ptr =
        ddog_trace_exporter_response_get_body(args.response, &body_len);
    if (body_ptr != NULL && body_len > 0) {
      payload = rb_str_new((const char *)body_ptr, (long)body_len);
    }
    ddog_trace_exporter_response_free(args.response);
    args.response = NULL;
  }

  if (pending_exception) {
    rb_jump_tag(pending_exception);
  }

  if (args.failed) {
    VALUE err_resp = create_error_response(args.error_code, ctx->trace_count);
    return rb_ary_new_from_args(1, err_resp);
  }

  VALUE ok_resp = create_ok_response(ctx->trace_count, payload);
  return rb_ary_new_from_args(1, ok_resp);
}

/*
 * Ensure: free chunks if they haven't been consumed by the send yet.
 * This runs whether build_and_send_traces returned normally or raised.
 */
static VALUE free_chunks_if_needed(VALUE arg) {
  send_traces_ctx *ctx = (send_traces_ctx *)arg;
  if (ctx->chunks != NULL) {
    ddog_tracer_trace_chunks_free(ctx->chunks);
    ctx->chunks = NULL;
  }
  return Qnil;
}

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

  /* Empty batch -> empty response (matches existing transport behaviour) */
  if (trace_count == 0) {
    return rb_ary_new();
  }

  /* Allocate trace chunks */
  ddog_TracerTraceChunks *chunks = NULL;
  ddog_TraceExporterError *chunks_err =
      ddog_tracer_trace_chunks_new((size_t)trace_count, &chunks);
  if (chunks_err != NULL) {
    ddog_trace_exporter_error_free(chunks_err);
    raise_error(rb_eRuntimeError, "Failed to allocate trace chunks");
  }

  send_traces_ctx ctx = {
    .exporter    = exporter,
    .traces      = traces,
    .trace_count = trace_count,
    .chunks      = chunks,
  };

  return rb_ensure(
      build_and_send_traces, (VALUE)&ctx,
      free_chunks_if_needed, (VALUE)&ctx);
}

/* ========================================================================
 * Initialization
 * ======================================================================== */

void trace_exporter_init(VALUE tracing_module) {
  /* -- Module hierarchy -- */
  VALUE transport_module = rb_define_module_under(tracing_module, "Transport");
  VALUE native_module =
      rb_define_module_under(transport_module, "Native");

  /* ----------------------------------------------------------------
   * TracerSpan class
   * ---------------------------------------------------------------- */
  tracer_span_class =
      rb_define_class_under(native_module, "TracerSpan", rb_cObject);
  rb_undef_alloc_func(tracer_span_class);

  /* Factory */
  rb_define_singleton_method(tracer_span_class, "_native_from_span",
                             _native_from_span, 1);

  /* ----------------------------------------------------------------
   * TraceExporter class
   * ---------------------------------------------------------------- */
  trace_exporter_class =
      rb_define_class_under(native_module, "TraceExporter", rb_cObject);
  rb_undef_alloc_func(trace_exporter_class);

  /* Factory: _native_new(url, tracer_version, language, language_version,
   *                       language_interpreter, hostname, env, service,
   *                       version) */
  rb_define_singleton_method(trace_exporter_class, "_native_new",
                             _native_exporter_new, 9);

  /* Instance: _native_send_traces(traces) -> Array[Response] */
  rb_define_method(trace_exporter_class, "_native_send_traces",
                   _native_send_traces, 1);

  /* ----------------------------------------------------------------
   * Response class
   * ---------------------------------------------------------------- */
  response_class =
      rb_define_class_under(native_module, "Response", rb_cObject);

  rb_define_method(response_class, "ok?",              response_ok_p,              0);
  rb_define_method(response_class, "internal_error?",  response_internal_error_p,  0);
  rb_define_method(response_class, "server_error?",    response_server_error_p,    0);
  rb_define_method(response_class, "client_error?",    response_client_error_p,    0);
  rb_define_method(response_class, "not_found?",       response_not_found_p,       0);
  rb_define_method(response_class, "unsupported?",     response_unsupported_p,     0);
  rb_define_method(response_class, "trace_count",      response_trace_count_m,     0);
  rb_define_method(response_class, "payload",          response_payload,           0);

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

  /* Response ivars */
  at_ok_id          = rb_intern("@ok");
  at_int_error_id   = rb_intern("@internal_error");
  at_srv_error_id   = rb_intern("@server_error");
  at_cli_error_id   = rb_intern("@client_error");
  at_not_found_id   = rb_intern("@not_found");
  at_unsupported_id = rb_intern("@unsupported");
  at_trace_count_id = rb_intern("@trace_count");
  at_payload_id     = rb_intern("@payload");
}

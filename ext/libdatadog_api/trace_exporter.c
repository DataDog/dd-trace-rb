#include <ruby.h>
#include <ruby/encoding.h>
#include <ruby/thread.h>
#include <limits.h>
#include <stdbool.h>
#include <string.h>
#include <datadog/data-pipeline.h>
#include <datadog/shared-runtime.h>

#include "datadog_ruby_common.h"
#include "helpers.h"
#include "trace_exporter.h"

/* ========================================================================
 * Forward declarations
 * ======================================================================== */

typedef struct {
  ddog_TracerSpan *span;
} raw_span_owner;

/* Internal: convert a Ruby Span into the supplied raw Rust span owner */
static void convert_ruby_span_to_rust(VALUE span, raw_span_owner *owner);

/* TracerSpan methods */
static VALUE _native_from_span(VALUE klass, VALUE span);

/* TraceExporter methods */
static VALUE _native_exporter_new(int argc, VALUE *argv, VALUE klass);
static VALUE _native_send_traces(VALUE self, VALUE traces);
static VALUE _native_before_fork(VALUE self);
static VALUE _native_after_fork_in_parent(VALUE self);
static VALUE _native_after_fork_in_child(VALUE self);

/* Response helpers */
static VALUE create_ok_response(long trace_count, VALUE payload);
static VALUE create_error_response(ddog_TraceExporterErrorCode code,
                                    long trace_count);

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
static ID at_metastruct_id;

/* Method IDs for time / integer operations */
static ID id_duration_method;
static ID id_to_h;
static ID id_negative_p;

/* Resolved lazily because AppSec may load after this extension. */
static VALUE serializable_backtrace_class = Qnil;

/* Response class (loaded from Ruby) */
static VALUE response_class       = Qnil;
static ID id_new;

/* Response keyword-argument IDs, cached to avoid re-interning per send */
static ID kw_ok;
static ID kw_internal_error;
static ID kw_server_error;
static ID kw_client_error;
static ID kw_trace_count;
static ID kw_payload;

/* ========================================================================
 * Ruby class references (marked as GC roots)
 * ======================================================================== */

static VALUE tracer_span_class    = Qnil;
static VALUE trace_exporter_class = Qnil;

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

/*
 * The TraceExporter wrapper owns both the Rust exporter and the SharedRuntime
 * that drives its background workers.  Fork-safety hooks operate on the
 * runtime, while send/receive operate on the exporter.
 */
typedef struct {
  ddog_TraceExporter       *exporter;
  const ddog_ForkSafeRuntime *runtime;
} trace_exporter_t;

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
    trace_exporter_t *wrapper = (trace_exporter_t *)ptr;
    if (wrapper->exporter != NULL) {
      ddog_trace_exporter_free(wrapper->exporter);
    }
    if (wrapper->runtime != NULL) {
      ddog_shared_runtime_free(wrapper->runtime);
    }
    ruby_xfree(wrapper);
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

/*
 * If +err+ is non-NULL, copies the message, frees the error struct, and
 * raises a Ruby RuntimeError.  Does not return on error.
 */
static inline void check_shared_runtime_error(const char *context,
                                              ddog_SharedRuntimeFFIError *err) {
  if (err == NULL) return;

  char buf[MAX_RAISE_MESSAGE_SIZE];
  if (err->msg != NULL) {
    snprintf(buf, sizeof(buf), "%s: %s", context, err->msg);
  } else {
    snprintf(buf, sizeof(buf), "%s: (unknown error)", context);
  }
  ddog_shared_runtime_error_free(err);
  raise_error(rb_eRuntimeError, "%s", buf);
}

/* ========================================================================
 * Config helpers
 * ======================================================================== */

typedef ddog_TraceExporterError *(*config_setter_fn)(
    ddog_TraceExporterConfig *, ddog_CharSlice);

/*
 * Set a single string-valued config field. `rb_val` MUST be a Ruby String
 * (or nil, which is skipped): it is passed to char_slice_from_ruby_string,
 * which enforces the String type. This helper does not handle numeric or
 * other non-string config settings.
 */
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
  struct timespec ts = rb_time_timespec(time);
  return (int64_t)ts.tv_sec * 1000000000LL + (int64_t)ts.tv_nsec;
}

/* 128-bit trace ID split into two 64-bit halves */
typedef struct {
  uint64_t low;
  uint64_t high;
} trace_id_t;

/* Ruby 128-bit Integer -> trace_id_t */
static inline trace_id_t split_trace_id(VALUE trace_id) {
  /* Fast path: Fixnum fits in 63 bits, no high half */
  if (FIXNUM_P(trace_id)) {
    return (trace_id_t){
      .low  = (uint64_t)FIX2LONG(trace_id),
      .high = 0,
    };
  }

  /* Bignum path: extract raw bytes into two 64-bit words */
  unsigned long words[2] = {0, 0};
  rb_big_pack(trace_id, words, 2);
  return (trace_id_t){
    .low  = (uint64_t)words[0],
    .high = (uint64_t)words[1],
  };
}

/* ========================================================================
 * Hash iteration callbacks for meta / metrics
 *
 * The libdatadog setters return owned errors rather than raising. Stash the
 * first error in a context struct and stop iteration with ST_STOP so the
 * caller can free the still-unowned Rust span before turning the error into
 * a Ruby exception. (This is about span ownership, not hash iteration: MRI
 * restores rb_hash_foreach's iteration state via rb_ensure if a callback
 * exits non-locally.)
 * ======================================================================== */

typedef struct {
  ddog_TracerSpan        *span;
  ddog_TraceExporterError *error;  /* first error, if any */
  long                    skipped; /* entries skipped due to wrong type */
} hash_iter_ctx;

static int meta_iter_cb(VALUE key, VALUE value, VALUE arg) {
  hash_iter_ctx *ctx = (hash_iter_ctx *)arg;

  /*
   * The types are checked below, so build the ddog_CharSlice directly instead
   * of repeating char_slice_from_ruby_string()'s ENFORCE_TYPE check.
   * libdatadog copies both slices before the FFI call returns and retains no
   * pointer into the Ruby-owned string storage.
   */
  if (!RB_TYPE_P(key, T_STRING) || !RB_TYPE_P(value, T_STRING)) {
    ctx->skipped++;
    return ST_CONTINUE;
  }

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

  if (!RB_TYPE_P(key, T_STRING) ||
      (!RB_TYPE_P(value, T_FLOAT) && !RB_TYPE_P(value, T_FIXNUM) &&
       !RB_TYPE_P(value, T_BIGNUM))) {
    ctx->skipped++;
    return ST_CONTINUE;
  }

  /* See meta_iter_cb: the key type is checked above, so build the slice
   * directly. */
  ddog_CharSlice ks = {.ptr = RSTRING_PTR(key), .len = RSTRING_LEN(key)};

  ddog_TraceExporterError *err =
      ddog_tracer_span_set_metric(ctx->span, ks, NUM2DBL(value));
  if (err != NULL) {
    ctx->error = err;
    return ST_STOP;
  }

  return ST_CONTINUE;
}

typedef struct {
  ddog_TracerValueToken *tokens;
  size_t len;
  size_t capacity;
  st_table *active;
  uint8_t **scratch;
  size_t scratch_len;
  size_t scratch_capacity;
} structured_value_ctx;

static ddog_TracerValueToken *append_structured_value_token(
    structured_value_ctx *ctx, uint8_t kind) {
  if (ctx->len == ctx->capacity) {
    size_t capacity = ctx->capacity == 0 ? 16 : ctx->capacity * 2;
    if (capacity < ctx->capacity || capacity > SIZE_MAX / sizeof(*ctx->tokens)) {
      rb_raise(rb_eNoMemError, "meta_struct token buffer is too large");
    }
    REALLOC_N(ctx->tokens, ddog_TracerValueToken, capacity);
    ctx->capacity = capacity;
  }

  ddog_TracerValueToken *token = &ctx->tokens[ctx->len++];
  *token = (ddog_TracerValueToken){0};
  token->kind = kind;
  return token;
}

static const uint8_t *copy_structured_value_bytes(
    structured_value_ctx *ctx, VALUE string, size_t len) {
  if (len == 0) return (const uint8_t *)"";

  if (ctx->scratch_len == ctx->scratch_capacity) {
    size_t capacity = ctx->scratch_capacity == 0 ? 8 : ctx->scratch_capacity * 2;
    if (capacity < ctx->scratch_capacity || capacity > SIZE_MAX / sizeof(*ctx->scratch)) {
      rb_raise(rb_eNoMemError, "meta_struct scratch buffer is too large");
    }
    REALLOC_N(ctx->scratch, uint8_t *, capacity);
    ctx->scratch_capacity = capacity;
  }

  uint8_t *copy = ruby_xmalloc(len);
  ctx->scratch[ctx->scratch_len++] = copy;
  /* ruby_xmalloc may trigger GC, so retrieve the Ruby buffer only after it
   * returns and do not call Ruby again before the copy completes. */
  memcpy(copy, RSTRING_PTR(string), len);
  return copy;
}

static void free_structured_value_ctx(structured_value_ctx *ctx) {
  if (ctx->active != NULL) st_free_table(ctx->active);
  for (size_t i = 0; i < ctx->scratch_len; i++) {
    ruby_xfree(ctx->scratch[i]);
  }
  ruby_xfree(ctx->scratch);
  ruby_xfree(ctx->tokens);
}

static VALUE resolve_serializable_backtrace_class(void) {
  if (serializable_backtrace_class != Qnil) return serializable_backtrace_class;

  ID datadog_id = rb_intern("Datadog");
  ID appsec_id = rb_intern("AppSec");
  ID actions_handler_id = rb_intern("ActionsHandler");
  ID backtrace_id = rb_intern("SerializableBacktrace");
  if (!rb_const_defined(rb_cObject, datadog_id)) return Qnil;
  VALUE datadog = rb_const_get(rb_cObject, datadog_id);
  if (!rb_const_defined(datadog, appsec_id)) return Qnil;
  VALUE appsec = rb_const_get(datadog, appsec_id);
  if (!rb_const_defined(appsec, actions_handler_id)) return Qnil;
  VALUE actions_handler = rb_const_get(appsec, actions_handler_id);
  if (!rb_const_defined(actions_handler, backtrace_id)) return Qnil;

  serializable_backtrace_class = rb_const_get(actions_handler, backtrace_id);
  rb_global_variable(&serializable_backtrace_class);
  return serializable_backtrace_class;
}

static void append_structured_value(VALUE value, unsigned int depth,
                                    structured_value_ctx *ctx);

typedef struct {
  structured_value_ctx *ctx;
  unsigned int depth;
} structured_hash_ctx;

static int append_structured_hash_entry(VALUE key, VALUE value, VALUE arg) {
  structured_hash_ctx *hash_ctx = (structured_hash_ctx *)arg;
  append_structured_value(key, hash_ctx->depth, hash_ctx->ctx);
  append_structured_value(value, hash_ctx->depth, hash_ctx->ctx);
  return ST_CONTINUE;
}

static VALUE utf8_string(VALUE value) {
  VALUE string = RB_TYPE_P(value, T_SYMBOL) ? rb_sym2str(value) : value;
  string = rb_str_export_to_enc(string, rb_utf8_encoding());
  if (rb_enc_str_coderange(string) == ENC_CODERANGE_BROKEN) {
    rb_raise(rb_eEncodingError, "meta_struct string is not valid UTF-8");
  }
  return string;
}

static void append_structured_value(VALUE value, unsigned int depth,
                                    structured_value_ctx *ctx) {
  if (value == Qnil) {
    append_structured_value_token(ctx, DDOG_TRACER_VALUE_NIL);
    return;
  }
  if (value == Qtrue || value == Qfalse) {
    ddog_TracerValueToken *token =
        append_structured_value_token(ctx, DDOG_TRACER_VALUE_BOOL);
    token->bool_value = value == Qtrue ? 1 : 0;
    return;
  }
  if (RB_TYPE_P(value, T_FIXNUM) || RB_TYPE_P(value, T_BIGNUM)) {
    if (RTEST(rb_funcall(value, id_negative_p, 0))) {
      ddog_TracerValueToken *token =
          append_structured_value_token(ctx, DDOG_TRACER_VALUE_I64);
      token->i64_value = NUM2LL(value);
    } else {
      ddog_TracerValueToken *token =
          append_structured_value_token(ctx, DDOG_TRACER_VALUE_U64);
      token->u64_value = NUM2ULL(value);
    }
    return;
  }
  if (RB_TYPE_P(value, T_FLOAT)) {
    ddog_TracerValueToken *token =
        append_structured_value_token(ctx, DDOG_TRACER_VALUE_F64);
    token->f64_value = RFLOAT_VALUE(value);
    return;
  }
  if (RB_TYPE_P(value, T_STRING) || RB_TYPE_P(value, T_SYMBOL)) {
    bool binary = RB_TYPE_P(value, T_STRING) &&
        rb_enc_get_index(value) == rb_ascii8bit_encindex();
    VALUE string = binary ? value : utf8_string(value);
    size_t len = (size_t)RSTRING_LEN(string);
    ddog_TracerValueToken *token = append_structured_value_token(
        ctx, binary ? DDOG_TRACER_VALUE_BINARY : DDOG_TRACER_VALUE_STRING);
    token->bytes = (ddog_ByteSlice){
      .ptr = copy_structured_value_bytes(ctx, string, len),
      .len = len,
    };
    return;
  }

  VALUE backtrace_class = resolve_serializable_backtrace_class();
  if (backtrace_class != Qnil && rb_obj_is_kind_of(value, backtrace_class)) {
    append_structured_value(rb_funcall(value, id_to_h, 0), depth, ctx);
    return;
  }

  if (!RB_TYPE_P(value, T_ARRAY) && !RB_TYPE_P(value, T_HASH)) {
    rb_raise(rb_eTypeError, "unsupported meta_struct value type: %s",
             rb_obj_classname(value));
  }
  if (depth >= 64) {
    rb_raise(rb_eArgError, "meta_struct value exceeds maximum depth of 64");
  }
  if (st_lookup(ctx->active, (st_data_t)value, NULL)) {
    rb_raise(rb_eArgError, "meta_struct value contains a cycle");
  }
  st_insert(ctx->active, (st_data_t)value, 1);

  long length = RB_TYPE_P(value, T_ARRAY) ? RARRAY_LEN(value) : RHASH_SIZE(value);
  if ((unsigned long)length > UINT32_MAX) {
    rb_raise(rb_eArgError, "meta_struct container exceeds u32::MAX entries");
  }
  ddog_TracerValueToken *token = append_structured_value_token(
      ctx, RB_TYPE_P(value, T_ARRAY) ? DDOG_TRACER_VALUE_ARRAY : DDOG_TRACER_VALUE_MAP);
  token->child_count = (uint32_t)length;

  if (RB_TYPE_P(value, T_ARRAY)) {
    for (long i = 0; i < length; i++) {
      append_structured_value(rb_ary_entry(value, i), depth + 1, ctx);
    }
  } else {
    structured_hash_ctx hash_ctx = {.ctx = ctx, .depth = depth + 1};
    rb_hash_foreach(value, append_structured_hash_entry, (VALUE)&hash_ctx);
  }
  st_delete(ctx->active, (st_data_t *)&value, NULL);
}

typedef struct {
  const uint8_t *key;
  size_t key_len;
  structured_value_ctx value;
} prepared_metastruct_entry;

typedef struct {
  prepared_metastruct_entry *entries;
  size_t len;
  size_t capacity;
} prepared_metastruct;

static void free_prepared_metastruct(prepared_metastruct *prepared) {
  for (size_t i = 0; i < prepared->len; i++) {
    free_structured_value_ctx(&prepared->entries[i].value);
  }
  ruby_xfree(prepared->entries);
  *prepared = (prepared_metastruct){0};
}

static prepared_metastruct_entry *append_prepared_metastruct_entry(
    prepared_metastruct *prepared) {
  if (prepared->len == prepared->capacity) {
    size_t capacity = prepared->capacity == 0 ? 4 : prepared->capacity * 2;
    if (capacity < prepared->capacity || capacity > SIZE_MAX / sizeof(*prepared->entries)) {
      rb_raise(rb_eNoMemError, "meta_struct entry buffer is too large");
    }
    REALLOC_N(prepared->entries, prepared_metastruct_entry, capacity);
    prepared->capacity = capacity;
  }

  prepared_metastruct_entry *entry = &prepared->entries[prepared->len++];
  *entry = (prepared_metastruct_entry){0};
  entry->value.active = st_init_numtable();
  return entry;
}

typedef struct {
  prepared_metastruct *prepared;
  long skipped;
} metastruct_prepare_ctx;

static int prepare_metastruct_iter_cb(VALUE key, VALUE value, VALUE arg) {
  metastruct_prepare_ctx *ctx = (metastruct_prepare_ctx *)arg;

  /* The agent meta_struct contract requires string keys. Accept symbols as a
   * Ruby convenience, but do not encode other key types differently from the
   * native tracer implementations. */
  if (RB_TYPE_P(key, T_SYMBOL)) {
    key = rb_sym2str(key);
  } else if (!RB_TYPE_P(key, T_STRING)) {
    ctx->skipped++;
    return ST_CONTINUE;
  }

  key = utf8_string(key);
  prepared_metastruct_entry *entry =
      append_prepared_metastruct_entry(ctx->prepared);
  entry->key_len = (size_t)RSTRING_LEN(key);
  entry->key = copy_structured_value_bytes(
      &entry->value, key, entry->key_len);
  append_structured_value(value, 0, &entry->value);

  return ST_CONTINUE;
}

typedef struct {
  VALUE span;
  prepared_metastruct *prepared;
} prepare_metastruct_call;

static VALUE prepare_metastruct_body(VALUE arg) {
  prepare_metastruct_call *call = (prepare_metastruct_call *)arg;
  VALUE metastruct = rb_ivar_get(call->span, at_metastruct_id);
  if (metastruct == Qnil) return Qnil;

  VALUE values = rb_funcall(metastruct, id_to_h, 0);
  Check_Type(values, T_HASH);
  if (RHASH_SIZE(values) == 0) return Qnil;

  metastruct_prepare_ctx ctx = {.prepared = call->prepared, .skipped = 0};
  rb_hash_foreach(values, prepare_metastruct_iter_cb, (VALUE)&ctx);
  if (ctx.skipped > 0) {
    log_warning(rb_sprintf(
        "Native trace exporter: skipped %ld meta_struct entries with non-string keys",
        ctx.skipped));
  }
  return Qnil;
}

/* Prepare stable token storage before allocating the Rust span. Any Ruby
 * callback or non-local exit is contained here, where deterministic cleanup
 * does not need to account for Rust span ownership. */
static void prepare_metastruct(VALUE span, prepared_metastruct *prepared) {
  prepare_metastruct_call call = {.span = span, .prepared = prepared};
  int state = 0;
  rb_protect(prepare_metastruct_body, (VALUE)&call, &state);
  if (state) {
    free_prepared_metastruct(prepared);
    rb_jump_tag(state);
  }
}

static void set_prepared_metastruct(
    ddog_TracerSpan *span, prepared_metastruct *prepared) {
  for (size_t i = 0; i < prepared->len; i++) {
    prepared_metastruct_entry *entry = &prepared->entries[i];
    ddog_Slice_TracerValueToken tokens = {
      .ptr = entry->value.tokens,
      .len = entry->value.len,
    };
    ddog_CharSlice key = {
      .ptr = (const char *)entry->key,
      .len = entry->key_len,
    };
    ddog_TraceExporterError *err =
        ddog_tracer_span_set_meta_struct(span, key, tokens);
    if (err != NULL) {
      free_prepared_metastruct(prepared);
      check_exporter_error("Failed to set span meta_struct", err);
    }
  }
  free_prepared_metastruct(prepared);
}
/* ========================================================================
 * Internal: convert a Ruby Span into a raw_span_owner
 *
 * The caller keeps its ensure handler active until the span is either wrapped
 * in TypedData or consumed by a trace chunk.
 * ======================================================================== */

static void convert_ruby_span_to_rust(VALUE span, raw_span_owner *owner) {
  /* 1. Read Ruby ivars */
  VALUE rb_name      = rb_ivar_get(span, at_name_id);
  VALUE rb_service   = rb_ivar_get(span, at_service_id);
  VALUE rb_resource  = rb_ivar_get(span, at_resource_id);
  VALUE rb_type      = rb_ivar_get(span, at_type_id);
  VALUE rb_span_id   = rb_ivar_get(span, at_id_id);
  VALUE rb_parent_id = rb_ivar_get(span, at_parent_id_id);
  VALUE rb_trace_id  = rb_ivar_get(span, at_trace_id_id);
  VALUE rb_status    = rb_ivar_get(span, at_status_id);

  ENFORCE_TYPE(rb_name, T_STRING);
  if (rb_service != Qnil) ENFORCE_TYPE(rb_service, T_STRING);
  if (rb_resource != Qnil) ENFORCE_TYPE(rb_resource, T_STRING);
  if (rb_type != Qnil) ENFORCE_TYPE(rb_type, T_STRING);

  /* 2. Convert scalars that may call Ruby. */
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

  /* Structured-value normalisation can call Ruby code. Snapshot it before
   * borrowing scalar string pointers or allocating the Rust span. */
  prepared_metastruct metastruct = {0};
  prepare_metastruct(span, &metastruct);

  /* No Ruby calls may occur between borrowing these pointers and span_new. */
  ddog_CharSlice name_s     = char_slice_from_ruby_string(rb_name);
  ddog_CharSlice service_s  = nullable_char_slice(rb_service);
  ddog_CharSlice resource_s = nullable_char_slice(rb_resource);
  ddog_CharSlice type_s     = nullable_char_slice(rb_type);

  /* 3. Create Rust span and immediately consume the stable prepared values. */
  ddog_TracerSpanFields fields = {
    .service        = service_s,
    .name           = name_s,
    .resource       = resource_s,
    .span_type      = type_s,
    .trace_id_low   = trace_id.low,
    .trace_id_high  = trace_id.high,
    .span_id        = span_id,
    .parent_id      = parent_id,
    .start          = start_ns,
    .duration       = duration_ns,
    .error          = error_val,
  };

  ddog_TraceExporterError *err = ddog_tracer_span_new(&owner->span, &fields);
  if (err != NULL) free_prepared_metastruct(&metastruct);
  check_exporter_error("Failed to create TracerSpan", err);
  set_prepared_metastruct(owner->span, &metastruct);

  /* 4. Populate meta and metrics */
  hash_iter_ctx ctx = {.span = owner->span, .error = NULL, .skipped = 0};

  VALUE rb_meta = rb_ivar_get(span, at_meta_id);
  if (RB_TYPE_P(rb_meta, T_HASH) && RHASH_SIZE(rb_meta) > 0) {
    rb_hash_foreach(rb_meta, meta_iter_cb, (VALUE)&ctx);
    check_exporter_error("Failed to set span meta", ctx.error);
    if (ctx.skipped > 0) {
      log_warning(rb_sprintf(
          "Native trace exporter: skipped %ld non-string meta entries",
          ctx.skipped));
      ctx.skipped = 0;
    }
  }

  VALUE rb_metrics = rb_ivar_get(span, at_metrics_id);
  if (RB_TYPE_P(rb_metrics, T_HASH) && RHASH_SIZE(rb_metrics) > 0) {
    rb_hash_foreach(rb_metrics, metrics_iter_cb, (VALUE)&ctx);
    check_exporter_error("Failed to set span metric", ctx.error);
    if (ctx.skipped > 0) {
      log_warning(rb_sprintf(
          "Native trace exporter: skipped %ld non-numeric metrics entries",
          ctx.skipped));
    }
  }

}

static VALUE free_raw_span(VALUE arg) {
  raw_span_owner *owner = (raw_span_owner *)arg;
  if (owner->span != NULL) {
    ddog_tracer_span_free(owner->span);
    owner->span = NULL;
  }
  return Qnil;
}

/* ========================================================================
 * TracerSpan._native_from_span
 * ======================================================================== */

typedef struct {
  VALUE span;
  raw_span_owner owner;
} wrap_span_ctx;

static VALUE convert_and_wrap_span(VALUE arg) {
  wrap_span_ctx *ctx = (wrap_span_ctx *)arg;
  convert_ruby_span_to_rust(ctx->span, &ctx->owner);

  VALUE wrapped = TypedData_Wrap_Struct(
      tracer_span_class, &tracer_span_typed_data, ctx->owner.span);
  ctx->owner.span = NULL;
  return wrapped;
}

static VALUE _native_from_span(DDTRACE_UNUSED VALUE klass, VALUE span) {
  wrap_span_ctx ctx = {.span = span, .owner = {.span = NULL}};
  return rb_ensure(
      convert_and_wrap_span, (VALUE)&ctx,
      free_raw_span, (VALUE)&ctx.owner);
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
  VALUE kwargs = rb_hash_new();
  rb_hash_aset(kwargs, ID2SYM(kw_ok),             Qfalse);
  rb_hash_aset(kwargs, ID2SYM(kw_internal_error), (code != DDOG_TRACE_EXPORTER_ERROR_CODE_HTTP_CLIENT &&
                                                   code != DDOG_TRACE_EXPORTER_ERROR_CODE_HTTP_SERVER) ? Qtrue : Qfalse);
  rb_hash_aset(kwargs, ID2SYM(kw_server_error),   code == DDOG_TRACE_EXPORTER_ERROR_CODE_HTTP_SERVER ? Qtrue : Qfalse);
  rb_hash_aset(kwargs, ID2SYM(kw_client_error),   code == DDOG_TRACE_EXPORTER_ERROR_CODE_HTTP_CLIENT ? Qtrue : Qfalse);
  rb_hash_aset(kwargs, ID2SYM(kw_trace_count),    LONG2NUM(trace_count));
  return rb_funcallv_kw(response_class, id_new, 1, &kwargs, RB_PASS_KEYWORDS);
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
  VALUE kwargs = rb_hash_new();
  rb_hash_aset(kwargs, ID2SYM(kw_ok),          Qtrue);
  rb_hash_aset(kwargs, ID2SYM(kw_trace_count), LONG2NUM(trace_count));
  rb_hash_aset(kwargs, ID2SYM(kw_payload),     payload);
  return rb_funcallv_kw(response_class, id_new, 1, &kwargs, RB_PASS_KEYWORDS);
}

/* ========================================================================
 * TraceExporter._native_new
 *
 * Creates a Rust TraceExporter with the given configuration.
 *
 * Ruby signature:
 *   TraceExporter._native_new(
 *     url:, tracer_version: nil, language: nil, language_version: nil,
 *     language_interpreter: nil, hostname: nil, env: nil,
 *     service: nil, version: nil) -> TraceExporter
 *
 * +url+ is required (String).  All other arguments may be nil.
 * ======================================================================== */

static VALUE _native_exporter_new(
    int argc, VALUE *argv, DDTRACE_UNUSED VALUE klass
) {
  VALUE options;
  rb_scan_args(argc, argv, "0:", &options);
  if (options == Qnil) options = rb_hash_new();

  VALUE rb_url                  = rb_hash_fetch(options, ID2SYM(rb_intern("url")));
  VALUE rb_tracer_version       = rb_hash_fetch(options, ID2SYM(rb_intern("tracer_version")));
  VALUE rb_language             = rb_hash_fetch(options, ID2SYM(rb_intern("language")));
  VALUE rb_language_version     = rb_hash_fetch(options, ID2SYM(rb_intern("language_version")));
  VALUE rb_language_interpreter = rb_hash_fetch(options, ID2SYM(rb_intern("language_interpreter")));
  VALUE rb_hostname             = rb_hash_fetch(options, ID2SYM(rb_intern("hostname")));
  VALUE rb_env                  = rb_hash_fetch(options, ID2SYM(rb_intern("env")));
  VALUE rb_service              = rb_hash_fetch(options, ID2SYM(rb_intern("service")));
  VALUE rb_version              = rb_hash_fetch(options, ID2SYM(rb_intern("version")));

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

  /* Phase 2: configure before creating the separately-owned runtime. */
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

  /*
   * Create a SharedRuntime and attach it to the config before building the
   * exporter.  The exporter holds a clone of the runtime's Arc; we keep our
   * own handle in the wrapper to drive fork-safety hooks and to free it when
   * the exporter is collected.
   */
  const ddog_ForkSafeRuntime *runtime = NULL;
  ddog_SharedRuntimeFFIError *rt_err = ddog_shared_runtime_new(&runtime);
  if (rt_err != NULL) {
    ddog_trace_exporter_config_free(config);
    check_shared_runtime_error("Failed to create SharedRuntime", rt_err);
  }

  /*
   * Const asymmetry: ddog_shared_runtime_new yields a `const ddog_ForkSafeRuntime *`
   * but the setter takes a non-const pointer.  The setter only clones the Arc,
   * so casting away const here is safe.
   */
  {
    ddog_TraceExporterError *attach_err = ddog_trace_exporter_config_set_shared_runtime(
        config, (ddog_ForkSafeRuntime *)runtime);
    if (attach_err != NULL) {
      ddog_trace_exporter_config_free(config);
      ddog_shared_runtime_free(runtime);
      check_exporter_error("Failed to attach SharedRuntime to config", attach_err);
    }
  }

  /* Phase 3: build the exporter from the config */
  ddog_TraceExporter *exporter = NULL;
  ddog_TraceExporterError *err = ddog_trace_exporter_new(&exporter, config);
  ddog_trace_exporter_config_free(config);
  config = NULL;

  if (err) {
    ddog_shared_runtime_free(runtime);
    check_exporter_error("Failed to create TraceExporter", err);
  }

  trace_exporter_t *wrapper = ruby_xmalloc(sizeof(trace_exporter_t));
  wrapper->exporter = exporter;
  wrapper->runtime  = runtime;

  return TypedData_Wrap_Struct(trace_exporter_class, &trace_exporter_typed_data,
                               wrapper);
}

/* ========================================================================
 * Fork safety hooks
 *
 * These coordinate the tokio runtime lifecycle around process forks
 * (Puma, Unicorn, Passenger).
 * ======================================================================== */

static VALUE _native_before_fork(VALUE self) {
  trace_exporter_t *wrapper;
  TypedData_Get_Struct(self, trace_exporter_t, &trace_exporter_typed_data, wrapper);
  if (wrapper == NULL || wrapper->runtime == NULL) {
    raise_error(rb_eRuntimeError, "TraceExporter has not been initialized or was already freed");
  }
  ddog_SharedRuntimeFFIError *err = ddog_shared_runtime_before_fork(wrapper->runtime);
  check_shared_runtime_error("Failed to prepare for fork", err);
  return Qnil;
}

static VALUE _native_after_fork_in_parent(VALUE self) {
  trace_exporter_t *wrapper;
  TypedData_Get_Struct(self, trace_exporter_t, &trace_exporter_typed_data, wrapper);
  if (wrapper == NULL || wrapper->runtime == NULL) {
    raise_error(rb_eRuntimeError, "TraceExporter has not been initialized or was already freed");
  }
  ddog_SharedRuntimeFFIError *err = ddog_shared_runtime_after_fork_parent(wrapper->runtime);
  check_shared_runtime_error("Failed to restore after fork in parent", err);
  return Qnil;
}

static VALUE _native_after_fork_in_child(VALUE self) {
  trace_exporter_t *wrapper;
  TypedData_Get_Struct(self, trace_exporter_t, &trace_exporter_typed_data, wrapper);
  if (wrapper == NULL || wrapper->runtime == NULL) {
    raise_error(rb_eRuntimeError, "TraceExporter has not been initialized or was already freed");
  }
  ddog_SharedRuntimeFFIError *err = ddog_shared_runtime_after_fork_child(wrapper->runtime);
  check_shared_runtime_error("Failed to restore after fork in child", err);
  return Qnil;
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
  ddog_TraceExporterCancelToken  *cancel_token;  /* borrowed, not owned */
  ddog_TraceExporterErrorCode     error_code;
  bool                            failed;
  bool                            send_ran;
} send_chunks_args_t;

static void *send_chunks_without_gvl(void *data) {
  send_chunks_args_t *args = (send_chunks_args_t *)data;
  ddog_TraceExporterError *err = ddog_trace_exporter_send_trace_chunks(
      args->exporter, args->chunks, &args->response, args->cancel_token);
  if (err != NULL) {
    args->error_code = err->code;
    args->failed = true;
    ddog_trace_exporter_error_free(err);
  }
  args->send_ran = true;
  return NULL;
}

/*
 * Unblock function: cooperatively cancel an in-flight send.
 *
 * Called by Ruby when an interrupt (Thread#kill, shutdown) fires while
 * the thread is inside rb_thread_call_without_gvl2.  Cancelling the
 * token causes the Rust HTTP pipeline to abort the in-flight request
 * and return promptly, which is not possible with RUBY_UBF_IO's
 * signal-based approach.
 */
static void interrupt_exporter_call(void *cancel_token) {
  ddog_trace_exporter_cancel_token_cancel(
      (const ddog_TraceExporterCancelToken *)cancel_token);
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
  raw_span_owner            span_owner;
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

    long span_count = RARRAY_LEN(chunk_spans);
    /* Propagate a begin_chunk failure instead of swallowing it: continuing
     * would build an incomplete payload and still report success. rb_ensure
     * frees chunks on the raise. Today this only fails for an absurd
     * span_count, but a future libdatadog change (e.g. a fallible allocator)
     * could make it reachable. */
    ddog_TraceExporterError *begin_err =
        ddog_tracer_trace_chunks_begin_chunk(ctx->chunks, (size_t)span_count);
    check_exporter_error("Failed to begin trace chunk", begin_err);
    for (long j = 0; j < span_count; j++) {
      convert_ruby_span_to_rust(
          rb_ary_entry(chunk_spans, j), &ctx->span_owner);

      ddog_TraceExporterError *push_err =
          ddog_tracer_trace_chunks_push_span(ctx->chunks, ctx->span_owner.span);
      /* push_span consumes the span on every path. */
      ctx->span_owner.span = NULL;
      check_exporter_error("Failed to push span into trace chunk", push_err);
    }
  }

  /*
   * Send with the GVL released so other Ruby threads run during I/O.
   *
   * Custom behaviour of this call site:
   *  - We use the gvl2 variant precisely because it does NOT auto-raise a
   *    pending interrupt on return: the send consumes chunks and allocates
   *    a Rust response, so we must inspect/free those before letting any
   *    exception propagate (otherwise they leak).
   *  - The unblock function cancels a per-send cancellation token, which
   *    cooperatively aborts the in-flight Rust HTTP request (RUBY_UBF_IO
   *    could not cancel the Rust pipeline).
   *  - An interrupt can make gvl2 return before send_chunks_without_gvl
   *    runs, so we loop until the send actually executes or an exception
   *    is pending.
   */
  ddog_TraceExporterCancelToken *cancel_token =
      ddog_trace_exporter_cancel_token_new();

  send_chunks_args_t args = {
    .exporter     = ctx->exporter,
    .chunks       = ctx->chunks,
    .response     = NULL,
    .cancel_token = cancel_token,
    .failed       = false,
    .send_ran     = false,
  };

  int pending_exception = 0;
  while (!args.send_ran && !pending_exception) {
    rb_thread_call_without_gvl2(
        send_chunks_without_gvl, &args,
        interrupt_exporter_call, cancel_token);

    if (!args.send_ran) {
      pending_exception = check_if_pending_exception();
    }
  }

  ddog_trace_exporter_cancel_token_drop(cancel_token);
  /* Only null chunks when the send actually ran and consumed them.
   * If an interrupt fired before the send executed, chunks are still
   * live and the ensure handler must free them. */
  if (args.send_ran) {
    ctx->chunks = NULL;
  }

  /* Extract the response body as a Ruby string before freeing. */
  VALUE payload = Qnil;
  if (args.response != NULL) {
    ddog_ByteSlice body =
        ddog_trace_exporter_response_get_body(args.response);
    if (body.len > 0) {
      payload = rb_str_new((const char *)body.ptr, (long)body.len);
    }
    ddog_trace_exporter_response_free(args.response);
    args.response = NULL;
  }

  /*
   * Re-check for a pending interrupt unconditionally before deciding the
   * outcome.  In a race, the unblock function (interrupt_exporter_call) can
   * fire -- cancelling the token -- while the send still completes, so
   * rb_thread_call_without_gvl2 returns with args.send_ran == true.  In that
   * case the loop above exits without ever calling check_if_pending_exception(),
   * leaving the interrupt pending.  If we did not check here, the cancelled
   * send would fall through and be reported as an ordinary transport error
   * response, swallowing the interrupt (e.g. Thread#kill / shutdown).
   *
   * This runs after the response has already been extracted and freed and
   * after chunks have been handed off to the ensure handler, so re-raising
   * here leaks nothing.
   */
  if (!pending_exception) {
    pending_exception = check_if_pending_exception();
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
 * Ensure: free the current raw span and any chunks not consumed by the send.
 * This runs whether build_and_send_traces returned normally or raised.
 */
static VALUE free_send_resources(VALUE arg) {
  send_traces_ctx *ctx = (send_traces_ctx *)arg;
  free_raw_span((VALUE)&ctx->span_owner);
  if (ctx->chunks != NULL) {
    ddog_tracer_trace_chunks_free(ctx->chunks);
    ctx->chunks = NULL;
  }
  return Qnil;
}

static VALUE _native_send_traces(VALUE self, VALUE traces) {
  ENFORCE_TYPE(traces, T_ARRAY);

  trace_exporter_t *wrapper;
  TypedData_Get_Struct(self, trace_exporter_t, &trace_exporter_typed_data,
                       wrapper);
  if (wrapper == NULL || wrapper->exporter == NULL) {
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
    .exporter    = wrapper->exporter,
    .traces      = traces,
    .trace_count = trace_count,
    .span_owner  = {.span = NULL},
    .chunks      = chunks,
  };

  return rb_ensure(
      build_and_send_traces, (VALUE)&ctx,
      free_send_resources, (VALUE)&ctx);
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

  /* Factory: _native_new(url:, tracer_version:, ...) */
  rb_define_singleton_method(trace_exporter_class, "_native_new",
                             _native_exporter_new, -1);

  /* Instance: _native_send_traces(traces) -> Array[Response] */
  rb_define_method(trace_exporter_class, "_native_send_traces",
                   _native_send_traces, 1);

  /* Instance: fork safety hooks */
  rb_define_method(trace_exporter_class, "_native_before_fork",
                   _native_before_fork, 0);
  rb_define_method(trace_exporter_class, "_native_after_fork_in_parent",
                   _native_after_fork_in_parent, 0);
  rb_define_method(trace_exporter_class, "_native_after_fork_in_child",
                   _native_after_fork_in_child, 0);

  /* ----------------------------------------------------------------
   * Response class (defined in Ruby, loaded lazily)
   *
   * We resolve it here so create_ok_response / create_error_response
   * can call Response.new without repeated const lookups.
   * ---------------------------------------------------------------- */
  rb_require("datadog/tracing/transport/native/response");
  response_class =
      rb_const_get(native_module, rb_intern("Response"));
  rb_global_variable(&response_class);

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
  at_metastruct_id = rb_intern("@metastruct");

  /* Methods */
  id_duration_method = rb_intern("duration");
  id_to_h            = rb_intern("to_h");
  id_negative_p      = rb_intern("negative?");

  /* Response.new */
  id_new = rb_intern("new");

  /* Response keyword-argument IDs */
  kw_ok             = rb_intern("ok");
  kw_internal_error = rb_intern("internal_error");
  kw_server_error   = rb_intern("server_error");
  kw_client_error   = rb_intern("client_error");
  kw_trace_count    = rb_intern("trace_count");
  kw_payload        = rb_intern("payload");
}

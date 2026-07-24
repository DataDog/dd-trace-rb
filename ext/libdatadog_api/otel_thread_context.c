#include <ruby.h>
#include <ruby/thread.h>

#include "datadog_ruby_common.h"
#include "otel_thread_context.h"

#ifdef HAVE_DATADOG_OTEL_THREAD_CTX_H
#include <datadog/otel-thread-ctx.h>

extern __thread void *otel_thread_ctx_v1;

typedef struct {
  uint8_t trace_id[16];
  uint8_t span_id[8];
  uint8_t local_root_span_id[8];
} otel_fiber_context;

static const rb_data_type_t otel_fiber_context_type = {
  .wrap_struct_name = "Datadog::Core::OTelThreadContext fiber-local context",
  .function = {.dfree = RUBY_TYPED_DEFAULT_FREE},
  .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static ID fiber_context_slot;

static VALUE native_set(VALUE _self, VALUE trace_id, VALUE  span_id, VALUE local_root_span_id);
static VALUE native_supported_p(VALUE _self);
static VALUE native_enable(VALUE _self);
static VALUE native_read(VALUE _self);

void otel_thread_context_init(VALUE core_module) {
  fiber_context_slot = rb_intern("__dd_otel_fiber_context");

  VALUE otel_thread_context_module = rb_define_module_under(core_module, "OTelThreadContext");

#ifdef HAVE_RB_EXT_RACTOR_SAFE
  rb_ext_ractor_safe(true);
#endif

  rb_define_singleton_method(otel_thread_context_module, "_native_set", native_set, 3);
  rb_define_singleton_method(otel_thread_context_module, "_native_supported?", native_supported_p, 0);
  rb_define_singleton_method(otel_thread_context_module, "_native_enable", native_enable, 0);
  rb_define_singleton_method(otel_thread_context_module, "_native_read", native_read, 0);

#ifdef HAVE_RB_EXT_RACTOR_SAFE
  rb_ext_ractor_safe(false);
#endif
}

static otel_fiber_context *get_fiber_context_for(VALUE thread) {
  VALUE existing_ctx = rb_thread_local_aref(thread, fiber_context_slot);
  if (NIL_P(existing_ctx)) return NULL;

  otel_fiber_context *ctx;
  TypedData_Get_Struct(existing_ctx, otel_fiber_context, &otel_fiber_context_type, ctx);
  return ctx;
}

static otel_fiber_context *get_or_create_current_fiber_context(void) {
  otel_fiber_context *ctx = get_fiber_context_for(rb_thread_current());
  if (ctx) return ctx;

  VALUE obj = TypedData_Make_Struct(rb_cObject, otel_fiber_context, &otel_fiber_context_type, ctx);
  rb_thread_local_aset(rb_thread_current(), fiber_context_slot, obj);
  return ctx;
}

static void pack_id_big_endian(VALUE id, uint8_t *buffer, size_t size) {
  rb_integer_pack(id, buffer, size, 1, 0, INTEGER_PACK_MSWORD_FIRST | INTEGER_PACK_BIG_ENDIAN);
}

static void publish_context(const otel_fiber_context *ctx) {
  if (ctx) {
    ddog_otel_thread_ctx_update(&ctx->trace_id, &ctx->span_id, &ctx->local_root_span_id);
  } else {
    static const uint8_t zero_trace_id[16] = {0};
    static const uint8_t zero_span_id[8] = {0};

    ddog_otel_thread_ctx_update(&zero_trace_id, &zero_span_id, &zero_span_id);
  }
}

static void on_fiber_switch(
  DDTRACE_UNUSED rb_event_flag_t evflag,
  DDTRACE_UNUSED VALUE data,
  DDTRACE_UNUSED VALUE self,
  DDTRACE_UNUSED ID mid,
  DDTRACE_UNUSED VALUE klass
) {
  publish_context(get_or_create_current_fiber_context());
}

#ifdef RUBY_INTERNAL_THREAD_EVENT_EXITED
static void on_thread_exited(
  DDTRACE_UNUSED rb_event_flag_t event,
  DDTRACE_UNUSED const rb_internal_thread_event_data_t *event_data,
  DDTRACE_UNUSED void *user_data
) {
  struct ddog_ThreadContextHandle *ctx = ddog_otel_thread_ctx_detach();
  if (ctx) ddog_otel_thread_ctx_free(ctx);
}
#else
static void on_thread_end(
  DDTRACE_UNUSED rb_event_flag_t evflag,
  DDTRACE_UNUSED VALUE data,
  DDTRACE_UNUSED VALUE self,
  DDTRACE_UNUSED ID mid,
  DDTRACE_UNUSED VALUE klass
) {
  struct ddog_ThreadContextHandle *ctx = ddog_otel_thread_ctx_detach();
  if (ctx) ddog_otel_thread_ctx_free(ctx);
}
#endif

#ifdef HAVE_RB_INTERNAL_THREAD_EVENT_DATA_T_THREAD
  static void on_thread_resumed(
    DDTRACE_UNUSED rb_event_flag_t event,
    const rb_internal_thread_event_data_t *event_data,
    DDTRACE_UNUSED void *user_data
  ) {
    publish_context(get_fiber_context_for(event_data->thread));
  }
#endif

static VALUE native_set(DDTRACE_UNUSED VALUE _self, VALUE trace_id, VALUE span_id, VALUE local_root_span_id) {
  otel_fiber_context *ctx = get_or_create_current_fiber_context();

  pack_id_big_endian(trace_id, ctx->trace_id, sizeof(ctx->trace_id));
  pack_id_big_endian(span_id, ctx->span_id, sizeof(ctx->span_id));
  pack_id_big_endian(local_root_span_id, ctx->local_root_span_id, sizeof(ctx->local_root_span_id));

  publish_context(ctx);

  return Qtrue;
}

static VALUE native_supported_p(VALUE _self) {
  return Qtrue;
}

static VALUE native_enable(DDTRACE_UNUSED VALUE _self) {
  static bool enabled = false;
  if (enabled) return Qfalse;

  rb_add_event_hook(on_fiber_switch, RUBY_EVENT_FIBER_SWITCH, Qnil);

  // Starting with Ruby 3.2 we use internal thread EXITED hook and not
  // RUBY_EVENT_THREAD_END VM trace event, since trace events are scoped to main Ractor only
  #ifdef RUBY_INTERNAL_THREAD_EVENT_EXITED
    rb_internal_thread_add_event_hook(on_thread_exited, RUBY_INTERNAL_THREAD_EVENT_EXITED, NULL);
  #else
    rb_add_event_hook(on_thread_end, RUBY_EVENT_THREAD_END, Qnil);
  #endif

  #ifdef HAVE_RB_INTERNAL_THREAD_EVENT_DATA_T_THREAD
    rb_internal_thread_add_event_hook(on_thread_resumed, RUBY_INTERNAL_THREAD_EVENT_RESUMED, NULL);
  #endif

  enabled = true;
  return Qtrue;
}

static VALUE native_read(VALUE _self) {
  if (!otel_thread_ctx_v1) return Qnil;

  const uint8_t *raw = (const uint8_t *) otel_thread_ctx_v1;

  const uint16_t attrs_data_size = (uint16_t) raw[26] | ((uint16_t) raw[27] << 8);

  VALUE result = rb_hash_new();
  rb_hash_aset(result, ID2SYM(rb_intern("trace_id")), rb_str_new((const char *) raw, 16));
  rb_hash_aset(result, ID2SYM(rb_intern("span_id")), rb_str_new((const char *) (raw + 16), 8));
  rb_hash_aset(result, ID2SYM(rb_intern("valid")), rb_str_new((const char *) (raw + 24), 1));
  rb_hash_aset(result, ID2SYM(rb_intern("attrs")), rb_str_new((const char *) (raw + 28), attrs_data_size));

  return result;
}
#else
static VALUE native_set(DDTRACE_UNUSED VALUE _self, DDTRACE_UNUSED VALUE trace_id, DDTRACE_UNUSED VALUE span_id, DDTRACE_UNUSED VALUE local_root_span_id) {
  return Qfalse;
}

static VALUE native_supported_p(VALUE _self) {
  return Qfalse;
}

static VALUE native_enable(DDTRACE_UNUSED VALUE _self) {
  return Qfalse;
}

static VALUE native_read(VALUE _self) {
  return Qnil;
}
#endif

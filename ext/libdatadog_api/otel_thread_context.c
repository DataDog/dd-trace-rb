#include <ruby.h>
#include <ruby/thread.h>

#include "datadog_ruby_common.h"
#include "otel_thread_context.h"

#ifdef HAVE_DATADOG_OTEL_THREAD_CTX_H
#include <datadog/otel-thread-ctx.h>
#endif

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
static VALUE native_debug_read(VALUE _self);

void otel_thread_context_init(VALUE core_module) {
  fiber_context_slot = rb_intern("__dd_otel_fiber_context");

  VALUE otel_thread_context_module = rb_define_module_under(core_module, "OTelThreadContext");

  rb_define_singleton_method(otel_thread_context_module, "_native_set", native_set, 3);
  rb_define_singleton_method(otel_thread_context_module, "_native_supported?", native_supported_p, 0);
  rb_define_singleton_method(otel_thread_context_module, "_native_enable", native_enable, 0);
  rb_define_singleton_method(otel_thread_context_module, "_native_debug_read", native_debug_read, 0);
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

  enabled = true;
  return Qtrue;
}

static VALUE native_debug_read(VALUE _self) {
  struct ddog_ThreadContextHandle *ctx = ddog_otel_thread_ctx_detach();

  if (!ctx) return Qnil;

  const uint8_t *raw = (const uint8_t *) ctx;

  VALUE trace_id = rb_integer_unpack(raw, 16, 1, 0, INTEGER_PACK_MSWORD_FIRST | INTEGER_PACK_MSBYTE_FIRST);
  VALUE span_id = rb_integer_unpack(raw + 16, 8, 1, 0, INTEGER_PACK_MSWORD_FIRST | INTEGER_PACK_MSBYTE_FIRST);
  VALUE valid = raw[24] ? Qtrue : Qfalse;

  VALUE attrs = rb_hash_new();

  const uint8_t *attrs_data = raw + 28;
  const uint16_t attrs_data_size = (uint16_t) raw[26] | ((uint16_t) raw[27] << 8);
  uint16_t offset = 0;
  while (offset + 2 <= attrs_data_size) {
    uint8_t key_index = attrs_data[offset];
    uint8_t value_len = attrs_data[offset + 1];

    if (offset + 2 + value_len > attrs_data_size) break;

    VALUE value = rb_str_new((const char *) (attrs_data + offset + 2), value_len);

    rb_hash_aset(attrs, INT2FIX(key_index), value);
    offset += 2 + value_len;
  }

  struct ddog_ThreadContextHandle *previous = ddog_otel_thread_ctx_attach(ctx);
  if (previous) raise_error(rb_eRuntimeError, "Internal: unexpected context already attached during debug read");

  VALUE result = rb_hash_new();
  rb_hash_aset(result, ID2SYM(rb_intern("trace_id")), trace_id);
  rb_hash_aset(result, ID2SYM(rb_intern("span_id")), span_id);
  rb_hash_aset(result, ID2SYM(rb_intern("valid")), valid);
  rb_hash_aset(result, ID2SYM(rb_intern("attrs")), attrs);

  return result;
}

#include <ruby.h>
#include <ruby/thread.h>

#include "datadog_ruby_common.h"
#include "otel_thread_context.h"

#ifdef __linux__
  #include <datadog/otel-thread-ctx.h>
  extern __thread const uint8_t *otel_thread_ctx_v1;

  static void otel_ctx_handle_free(void *handle) {
    ddog_otel_thread_ctx_free((struct ddog_ThreadContextHandle *) handle);
  }

  static const rb_data_type_t otel_ctx_handle_t = {
    .wrap_struct_name = "Datadog::Core::OTelThreadContext handle",
    .function = {.dfree = otel_ctx_handle_free},
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
  };
#endif

#ifdef HAVE_RUBY_THREAD_STORAGE_API
  static rb_internal_thread_specific_key_t otel_ctx_key;
#endif

static ID fiber_context_slot;
static const int BIG_ENDIAN_PACK_FLAGS = INTEGER_PACK_MSWORD_FIRST | INTEGER_PACK_BIG_ENDIAN;

static bool otel_context_enabled = false;

static VALUE native_set(VALUE _self, VALUE trace_id, VALUE span_id, VALUE local_root_span_id);
static VALUE native_supported_p(VALUE _self);
static VALUE native_enable(VALUE _self);
static VALUE native_read(VALUE _self);

void otel_thread_context_init(VALUE core_module) {
  fiber_context_slot = rb_intern("__dd_otel_fiber_context");

  #ifdef HAVE_RUBY_THREAD_STORAGE_API
    otel_ctx_key = rb_internal_thread_specific_key_create();
  #endif

  VALUE otel_thread_context_module = rb_define_module_under(core_module, "OTelThreadContext");

  rb_define_singleton_method(otel_thread_context_module, "_native_enable", native_enable, 0);
  rb_define_singleton_method(otel_thread_context_module, "_native_set", native_set, 3);
  rb_define_singleton_method(otel_thread_context_module, "_native_supported?", native_supported_p, 0);

  VALUE testing_module = rb_define_module_under(otel_thread_context_module, "Testing");
  rb_define_singleton_method(testing_module, "_native_read", native_read, 0);
}

#ifdef __linux__
  static struct ddog_ThreadContextHandle *get_current_fiber_handle(void) {
    VALUE obj = rb_thread_local_aref(rb_thread_current(), fiber_context_slot);
    if (NIL_P(obj)) return NULL;

    struct ddog_ThreadContextHandle *handle;
    TypedData_Get_Struct(obj, struct ddog_ThreadContextHandle, &otel_ctx_handle_t, handle);
    return handle;
  }

  static void store_current_fiber_handle(struct ddog_ThreadContextHandle *handle) {
    VALUE obj = TypedData_Wrap_Struct(rb_cObject, &otel_ctx_handle_t, handle);
    rb_thread_local_aset(rb_thread_current(), fiber_context_slot, obj);
  }

  #ifdef RUBY_INTERNAL_THREAD_EVENT_EXITED
    static void on_thread_exited(
      DDTRACE_UNUSED rb_event_flag_t event,
      DDTRACE_UNUSED const rb_internal_thread_event_data_t *event_data,
      DDTRACE_UNUSED void *user_data
    ) {
      ddog_otel_thread_ctx_detach();
    }
  #else
    static void on_thread_end(
      DDTRACE_UNUSED rb_event_flag_t evflag,
      DDTRACE_UNUSED VALUE data,
      DDTRACE_UNUSED VALUE self,
      DDTRACE_UNUSED ID mid,
      DDTRACE_UNUSED VALUE klass
    ) {
      ddog_otel_thread_ctx_detach();
    }
  #endif

  #ifdef HAVE_RUBY_THREAD_STORAGE_API
    // SUSPENDED fires on every GVL release, so if thread that calls set and then enters a C extension
    // that releases the GVL and does something, the slot becomes empty for the whole duration.
    static void on_thread_suspended(
      DDTRACE_UNUSED rb_event_flag_t event,
      const rb_internal_thread_event_data_t *event_data,
      DDTRACE_UNUSED void *user_data
    ) {
      struct ddog_ThreadContextHandle *handle = ddog_otel_thread_ctx_detach();
      rb_internal_thread_specific_set(event_data->thread, otel_ctx_key, handle);
    }

    static void on_thread_resumed(
      DDTRACE_UNUSED rb_event_flag_t event,
      const rb_internal_thread_event_data_t *event_data,
      DDTRACE_UNUSED void *user_data
    ) {
      struct ddog_ThreadContextHandle *handle = rb_internal_thread_specific_get(event_data->thread, otel_ctx_key);

      if (handle != NULL) ddog_otel_thread_ctx_attach(handle);
    }
  #endif

  static void on_fiber_switch(
    DDTRACE_UNUSED rb_event_flag_t evflag,
    DDTRACE_UNUSED VALUE data,
    DDTRACE_UNUSED VALUE self,
    DDTRACE_UNUSED ID mid,
    DDTRACE_UNUSED VALUE klass
  ) {
    struct ddog_ThreadContextHandle *handle = get_current_fiber_handle();

    if (handle != NULL) {
      ddog_otel_thread_ctx_attach(handle);
    } else {
      ddog_otel_thread_ctx_detach();
    }
  }
#endif

static VALUE native_enable(DDTRACE_UNUSED VALUE _self) {
  #ifdef __linux__
    if (otel_context_enabled) return Qtrue;
    otel_context_enabled = true;

    #ifdef RUBY_INTERNAL_THREAD_EVENT_EXITED
      rb_internal_thread_add_event_hook(on_thread_exited, RUBY_INTERNAL_THREAD_EVENT_EXITED, NULL);
    #else
      rb_add_event_hook(on_thread_end, RUBY_EVENT_THREAD_END, Qnil);
    #endif

    // Under M:N, a Ruby thread migrates between OS threads.
    // We use thread storage to store a pointer to the OTel thread context record.
    #ifdef HAVE_RUBY_THREAD_STORAGE_API
      rb_internal_thread_add_event_hook(on_thread_suspended, RUBY_INTERNAL_THREAD_EVENT_SUSPENDED, NULL);
      rb_internal_thread_add_event_hook(on_thread_resumed, RUBY_INTERNAL_THREAD_EVENT_RESUMED, NULL);
    #endif

    rb_add_event_hook(on_fiber_switch, RUBY_EVENT_FIBER_SWITCH, Qnil);

    return Qtrue;
  #else
    return Qfalse;
  #endif
}

static VALUE native_supported_p(DDTRACE_UNUSED VALUE _self) {
  #ifdef __linux__
    return Qtrue;
  #else
    return Qfalse;
  #endif
}

static VALUE native_set(
    DDTRACE_UNUSED VALUE _self,
    DDTRACE_UNUSED VALUE trace_id,
    DDTRACE_UNUSED VALUE span_id,
    DDTRACE_UNUSED VALUE local_root_span_id
  ) {
  #ifdef __linux__
    if (!otel_context_enabled) return Qfalse;

    uint8_t trace_id_bytes[16];
    uint8_t span_id_bytes[8];
    uint8_t local_root_span_id_bytes[8];

    rb_integer_pack(trace_id, trace_id_bytes, sizeof(trace_id_bytes), 1, 0, BIG_ENDIAN_PACK_FLAGS);
    rb_integer_pack(span_id, span_id_bytes, sizeof(span_id_bytes), 1, 0, BIG_ENDIAN_PACK_FLAGS);
    rb_integer_pack(local_root_span_id, local_root_span_id_bytes, sizeof(local_root_span_id_bytes), 1, 0, BIG_ENDIAN_PACK_FLAGS);

    struct ddog_ThreadContextHandle *handle = get_current_fiber_handle();

    if (handle == NULL) {
      handle = ddog_otel_thread_ctx_new(&trace_id_bytes, &span_id_bytes, 0, &local_root_span_id_bytes);
      store_current_fiber_handle(handle);
      ddog_otel_thread_ctx_attach(handle);
    } else {
      ddog_otel_thread_ctx_attach(handle);
      ddog_otel_thread_ctx_update(&trace_id_bytes, &span_id_bytes, 0, &local_root_span_id_bytes);
    }

    return Qtrue;
  #else
    return Qfalse;
  #endif
}

static VALUE native_read(DDTRACE_UNUSED VALUE _self) {
  #ifdef __linux__
    const uint8_t *raw = otel_thread_ctx_v1;
    if (!raw) return Qnil;

    uint16_t attrs_data_size = (uint16_t) raw[26] | ((uint16_t) raw[27] << 8);

    if (attrs_data_size > ddog_MAX_ATTRS_DATA_SIZE) {
      raise_error(
        rb_eRuntimeError,
        "Invalid OTel thread context record: attrs_data_size (%d) exceeds maximum (%d)",
        attrs_data_size, ddog_MAX_ATTRS_DATA_SIZE
      );
    }

    VALUE result = rb_hash_new();
    rb_hash_aset(result, ID2SYM(rb_intern("trace_id")), rb_str_new((const char *) raw, 16));
    rb_hash_aset(result, ID2SYM(rb_intern("span_id")), rb_str_new((const char *) (raw + 16), 8));
    rb_hash_aset(result, ID2SYM(rb_intern("valid")), rb_str_new((const char *) (raw + 24), 1));
    rb_hash_aset(result, ID2SYM(rb_intern("attrs")), rb_str_new((const char *) (raw + 28), attrs_data_size));

    return result;
  #else
    return Qnil;
  #endif
}

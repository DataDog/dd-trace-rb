#include <ruby.h>
#include <ruby/thread.h>

#include "datadog_ruby_common.h"
#include "otel_thread_context.h"

#ifdef __linux__
  #include <datadog/otel-thread-ctx.h>
  extern __thread const uint8_t *otel_thread_ctx_v1;

  static void otel_ctx_handle_free(void *handle) {
    ddog_otel_thread_ctx_free((ddog_ThreadContextHandle *) handle);
  }

  static const rb_data_type_t otel_ctx_handle_t = {
    .wrap_struct_name = "Datadog::Tracing::OTelThreadContext handle",
    .function = {.dfree = otel_ctx_handle_free},
    .flags = RUBY_TYPED_FREE_IMMEDIATELY,
  };
#endif

static ID fiber_context_slot;

DDTRACE_UNUSED static bool otel_context_enabled = false;

static VALUE native_set(VALUE _self, VALUE trace_id, VALUE span_id, VALUE local_root_span_id);
static VALUE native_supported_p(VALUE _self);
static VALUE native_enable(VALUE _self);
static VALUE native_read(VALUE _self);

void otel_thread_context_init(VALUE tracing_module) {
  fiber_context_slot = rb_intern("__dd_otel_fiber_context");

  VALUE otel_thread_context_module = rb_define_module_under(tracing_module, "OTelThreadContext");

  rb_define_singleton_method(otel_thread_context_module, "_native_enable", native_enable, 0);
  rb_define_singleton_method(otel_thread_context_module, "_native_set", native_set, 3);
  rb_define_singleton_method(otel_thread_context_module, "_native_supported?", native_supported_p, 0);

  VALUE testing_module = rb_define_module_under(otel_thread_context_module, "Testing");
  rb_define_singleton_method(testing_module, "_native_read", native_read, 0);
}

#ifdef __linux__
  static ddog_ThreadContextHandle *get_fiber_handle_for(VALUE thread) {
    VALUE obj = rb_thread_local_aref(thread, fiber_context_slot);

    if (!rb_typeddata_is_kind_of(obj, &otel_ctx_handle_t)) return NULL;

    return RTYPEDDATA_DATA(obj);
  }

  static ddog_ThreadContextHandle *get_current_fiber_handle(void) {
    return get_fiber_handle_for(rb_thread_current());
  }

  static void store_current_fiber_handle(ddog_ThreadContextHandle *handle) {
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
    // This function is declared in internal/thread.h.
    // It returns 0 when the current thread sits in a blocking region.
    int ruby_thread_has_gvl_p(void);

    static bool in_blocking_region(void) {
      #ifdef HAVE_RUBY_THREAD_HAS_GVL_P
        return ruby_thread_has_gvl_p() == 0;
      #else
        return false;
      #endif
    }

    // Under M:N a Ruby thread can migrate between native threads,
    // so we need to detach the context when the Ruby thread gets suspended.
    static void on_thread_suspended(
      DDTRACE_UNUSED rb_event_flag_t event,
      DDTRACE_UNUSED const rb_internal_thread_event_data_t *event_data,
      DDTRACE_UNUSED void *user_data
    ) {
      // Ruby pins threads that release GVL to call into a native extension,
      // so we know the thread will not migrate.
      if (in_blocking_region()) return;

      ddog_otel_thread_ctx_detach();
    }

    static void on_thread_resumed(
      DDTRACE_UNUSED rb_event_flag_t event,
      const rb_internal_thread_event_data_t *event_data,
      DDTRACE_UNUSED void *user_data
    ) {
      ddog_ThreadContextHandle *handle = get_fiber_handle_for(event_data->thread);

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
    ddog_ThreadContextHandle *handle = get_current_fiber_handle();

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

    // These hooks only matter under the M:N thread scheduler (Ruby 3.3+),
    // where a Ruby thread can migrate between native threads.
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

    const int BIG_ENDIAN_PACK_FLAGS = INTEGER_PACK_MSWORD_FIRST | INTEGER_PACK_BIG_ENDIAN;
    rb_integer_pack(trace_id, trace_id_bytes, sizeof(trace_id_bytes), 1, 0, BIG_ENDIAN_PACK_FLAGS);
    rb_integer_pack(span_id, span_id_bytes, sizeof(span_id_bytes), 1, 0, BIG_ENDIAN_PACK_FLAGS);
    rb_integer_pack(local_root_span_id, local_root_span_id_bytes, sizeof(local_root_span_id_bytes), 1, 0, BIG_ENDIAN_PACK_FLAGS);

    ddog_ThreadContextHandle *handle = get_current_fiber_handle();

    if (handle == NULL) {
      handle = ddog_otel_thread_ctx_new(&trace_id_bytes, &span_id_bytes, 0, &local_root_span_id_bytes);
      store_current_fiber_handle(handle);
      ddog_otel_thread_ctx_attach(handle);
    } else {
      // FIXME: add a method to libdatadog to update the context record before attaching it
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

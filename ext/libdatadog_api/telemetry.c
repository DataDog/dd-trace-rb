#include <ruby.h>
#include <datadog/telemetry.h>

#include "datadog_ruby_common.h"
#include "telemetry.h"

// Raises a Ruby RuntimeError if the `ddog_MaybeError` carries an error.
// The error message is appended to the provided `message`.
#define CHECK_TELEMETRY_ERROR(message, result)                                         \
  do {                                                                                 \
    if ((result).tag == DDOG_OPTION_ERROR_SOME_ERROR) {                                \
      char error_msg[MAX_RAISE_MESSAGE_SIZE];                                          \
      read_ddogerr_string_and_drop(&(result).some, error_msg, MAX_RAISE_MESSAGE_SIZE);  \
      raise_error(rb_eRuntimeError, "%s: %s", message, error_msg);                          \
    }                                                                                  \
  } while (0)

typedef struct {
  ddog_TelemetryWorkerHandle *handle;
} telemetry_worker_t;

typedef struct {
  ddog_ContextKey key;
} telemetry_metric_context_t;

static void telemetry_worker_dfree(void *ptr);
static void telemetry_metric_context_dfree(void *ptr);

static const rb_data_type_t telemetry_worker_typed_data = {
  .wrap_struct_name = "Datadog::Core::Telemetry::Native::Worker",
  .function = {
    .dmark = NULL,
    .dfree = telemetry_worker_dfree,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static const rb_data_type_t telemetry_metric_context_typed_data = {
  .wrap_struct_name = "Datadog::Core::Telemetry::Native::MetricContext",
  .function = {
    .dmark = NULL,
    .dfree = telemetry_metric_context_dfree,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE telemetry_worker_class = Qnil;
static VALUE telemetry_metric_context_class = Qnil;

static VALUE _native_worker_new(int argc, VALUE *argv, DDTRACE_UNUSED VALUE klass);
static VALUE _native_worker_start(VALUE self);
static VALUE _native_worker_stop(VALUE self);
static VALUE _native_worker_shutdown(VALUE self, VALUE timeout_milliseconds);
static VALUE _native_worker_register_metric_context(
    VALUE self, VALUE name, VALUE metric_type, VALUE common, VALUE namespace);
static VALUE _native_worker_add_point(VALUE self, VALUE context, VALUE value, VALUE tags_as_array);
static VALUE _native_worker_add_log(
    VALUE self, VALUE identifier, VALUE message, VALUE level, VALUE stack_trace);

static bool metric_type_symbol_to_enum(VALUE symbol, ddog_MetricType *out_type);
static bool namespace_symbol_to_enum(VALUE symbol, ddog_MetricNamespace *out_namespace);

void telemetry_init(VALUE core_module) {
  VALUE telemetry_module = rb_define_module_under(core_module, "Telemetry");
  VALUE native_module = rb_define_module_under(telemetry_module, "Native");

  telemetry_worker_class = rb_define_class_under(native_module, "Worker", rb_cObject);
  rb_define_singleton_method(telemetry_worker_class, "_native_new", _native_worker_new, -1);
  rb_define_method(telemetry_worker_class, "_start", _native_worker_start, 0);
  rb_define_method(telemetry_worker_class, "_stop", _native_worker_stop, 0);
  rb_define_method(telemetry_worker_class, "_shutdown", _native_worker_shutdown, 1);
  rb_define_method(telemetry_worker_class, "_register_metric_context", _native_worker_register_metric_context, 4);
  rb_define_method(telemetry_worker_class, "_add_point", _native_worker_add_point, 3);
  rb_define_method(telemetry_worker_class, "_add_log", _native_worker_add_log, 4);

  rb_undef_alloc_func(telemetry_worker_class);

  telemetry_metric_context_class = rb_define_class_under(native_module, "MetricContext", rb_cObject);
  rb_undef_alloc_func(telemetry_metric_context_class);
}

static void telemetry_worker_dfree(void *ptr) {
  if (ptr != NULL) {
    telemetry_worker_t *worker = (telemetry_worker_t *)ptr;
    // The handle is NULL after _shutdown, which passes ownership to libdatadog.
    if (worker->handle != NULL) {
      ddog_telemetry_handle_drop(worker->handle);
    }
    ruby_xfree(worker);
  }
}

static void telemetry_metric_context_dfree(void *ptr) {
  // ddog_ContextKey is a plain value struct with nothing to drop.
  ruby_xfree(ptr);
}

static ddog_TelemetryWorkerHandle *get_worker_handle(VALUE self) {
  telemetry_worker_t *worker;
  TypedData_Get_Struct(self, telemetry_worker_t, &telemetry_worker_typed_data, worker);
  if (worker->handle == NULL) {
    raise_error(rb_eRuntimeError, "Telemetry native worker has already been shut down");
  }
  return worker->handle;
}

static ddog_ContextKey get_metric_context(VALUE context) {
  telemetry_metric_context_t *metric_context;
  TypedData_Get_Struct(
      context, telemetry_metric_context_t, &telemetry_metric_context_typed_data, metric_context);
  return metric_context->key;
}

typedef ddog_MaybeError (*telemetry_str_setter_fn)(ddog_TelemetryWorkerBuilder *, ddog_CharSlice);

static void set_builder_str_field(
    ddog_TelemetryWorkerBuilder *builder,
    telemetry_str_setter_fn setter,
    VALUE rb_val,
    const char *label) {
  if (rb_val == Qnil) return;
  ENFORCE_TYPE(rb_val, T_STRING);

  ddog_MaybeError err = setter(builder, char_slice_from_ruby_string(rb_val));
  // On error the builder leaks: libdatadog exposes no builder_free and only the
  // run functions consume it. These setters only fail on allocation.
  CHECK_TELEMETRY_ERROR(label, err);
}

static VALUE _native_worker_new(int argc, VALUE *argv, DDTRACE_UNUSED VALUE klass) {
  VALUE options;
  rb_scan_args(argc, argv, "0:", &options);
  if (options == Qnil) options = rb_hash_new();

  VALUE rb_url = rb_hash_fetch(options, ID2SYM(rb_intern("url")));
  VALUE rb_timeout_ms = rb_hash_fetch(options, ID2SYM(rb_intern("timeout_milliseconds")));
  VALUE rb_service_name = rb_hash_fetch(options, ID2SYM(rb_intern("service_name")));
  VALUE rb_language_name = rb_hash_fetch(options, ID2SYM(rb_intern("language_name")));
  VALUE rb_language_version = rb_hash_fetch(options, ID2SYM(rb_intern("language_version")));
  VALUE rb_tracer_version = rb_hash_fetch(options, ID2SYM(rb_intern("tracer_version")));

  VALUE rb_hostname = rb_hash_lookup(options, ID2SYM(rb_intern("hostname")));
  VALUE rb_env = rb_hash_lookup(options, ID2SYM(rb_intern("env")));
  VALUE rb_service_version = rb_hash_lookup(options, ID2SYM(rb_intern("service_version")));
  VALUE rb_runtime_name = rb_hash_lookup(options, ID2SYM(rb_intern("runtime_name")));
  VALUE rb_runtime_version = rb_hash_lookup(options, ID2SYM(rb_intern("runtime_version")));
  VALUE rb_runtime_id = rb_hash_lookup(options, ID2SYM(rb_intern("runtime_id")));
  VALUE rb_kernel_name = rb_hash_lookup(options, ID2SYM(rb_intern("kernel_name")));
  VALUE rb_kernel_release = rb_hash_lookup(options, ID2SYM(rb_intern("kernel_release")));
  VALUE rb_kernel_version = rb_hash_lookup(options, ID2SYM(rb_intern("kernel_version")));

  ENFORCE_TYPE(rb_url, T_STRING);
  ENFORCE_TYPE(rb_timeout_ms, T_FIXNUM);
  ENFORCE_TYPE(rb_service_name, T_STRING);
  ENFORCE_TYPE(rb_language_name, T_STRING);
  ENFORCE_TYPE(rb_language_version, T_STRING);
  ENFORCE_TYPE(rb_tracer_version, T_STRING);
  if (rb_hostname != Qnil) ENFORCE_TYPE(rb_hostname, T_STRING);
  if (rb_env != Qnil) ENFORCE_TYPE(rb_env, T_STRING);
  if (rb_service_version != Qnil) ENFORCE_TYPE(rb_service_version, T_STRING);
  if (rb_runtime_name != Qnil) ENFORCE_TYPE(rb_runtime_name, T_STRING);
  if (rb_runtime_version != Qnil) ENFORCE_TYPE(rb_runtime_version, T_STRING);
  if (rb_runtime_id != Qnil) ENFORCE_TYPE(rb_runtime_id, T_STRING);
  if (rb_kernel_name != Qnil) ENFORCE_TYPE(rb_kernel_name, T_STRING);
  if (rb_kernel_release != Qnil) ENFORCE_TYPE(rb_kernel_release, T_STRING);
  if (rb_kernel_version != Qnil) ENFORCE_TYPE(rb_kernel_version, T_STRING);

  ddog_TelemetryWorkerBuilder *builder = NULL;
  ddog_MaybeError err;
  if (rb_hostname == Qnil) {
    err = ddog_telemetry_builder_instantiate(
        &builder,
        char_slice_from_ruby_string(rb_service_name),
        char_slice_from_ruby_string(rb_language_name),
        char_slice_from_ruby_string(rb_language_version),
        char_slice_from_ruby_string(rb_tracer_version));
  } else {
    err = ddog_telemetry_builder_instantiate_with_hostname(
        &builder,
        char_slice_from_ruby_string(rb_hostname),
        char_slice_from_ruby_string(rb_service_name),
        char_slice_from_ruby_string(rb_language_name),
        char_slice_from_ruby_string(rb_language_version),
        char_slice_from_ruby_string(rb_tracer_version));
  }
  CHECK_TELEMETRY_ERROR("Failed to instantiate telemetry worker builder", err);

  set_builder_str_field(builder, ddog_telemetry_builder_with_str_application_env, rb_env,
                        "Failed to set telemetry env");
  set_builder_str_field(builder, ddog_telemetry_builder_with_str_application_service_version, rb_service_version,
                        "Failed to set telemetry service version");
  set_builder_str_field(builder, ddog_telemetry_builder_with_str_application_runtime_name, rb_runtime_name,
                        "Failed to set telemetry runtime name");
  set_builder_str_field(builder, ddog_telemetry_builder_with_str_application_runtime_version, rb_runtime_version,
                        "Failed to set telemetry runtime version");
  set_builder_str_field(builder, ddog_telemetry_builder_with_str_runtime_id, rb_runtime_id,
                        "Failed to set telemetry runtime id");
  set_builder_str_field(builder, ddog_telemetry_builder_with_str_host_kernel_name, rb_kernel_name,
                        "Failed to set telemetry kernel name");
  set_builder_str_field(builder, ddog_telemetry_builder_with_str_host_kernel_release, rb_kernel_release,
                        "Failed to set telemetry kernel release");
  set_builder_str_field(builder, ddog_telemetry_builder_with_str_host_kernel_version, rb_kernel_version,
                        "Failed to set telemetry kernel version");

  // Empty api_key and test_token select agent-based submission. Passing false
  // for use_system_resolver keeps libdatadog's fork-safe in-process resolver.
  err = ddog_telemetry_builder_with_endpoint_config_endpoint(
      builder,
      char_slice_from_ruby_string(rb_url),
      (ddog_CharSlice){.ptr = "", .len = 0},
      NUM2UINT(rb_timeout_ms),
      (ddog_CharSlice){.ptr = "", .len = 0},
      false);
  CHECK_TELEMETRY_ERROR("Failed to set telemetry endpoint", err);

  // The metric_logs flavor only processes metrics and logs. Lifecycle events
  // stay on the Ruby event layer until the lifecycle migration step.
  ddog_TelemetryWorkerHandle *handle = NULL;
  err = ddog_telemetry_builder_run_metric_logs(builder, &handle);
  CHECK_TELEMETRY_ERROR("Failed to run telemetry worker", err);

  telemetry_worker_t *worker = ruby_xmalloc(sizeof(telemetry_worker_t));
  worker->handle = handle;
  return TypedData_Wrap_Struct(telemetry_worker_class, &telemetry_worker_typed_data, worker);
}

static VALUE _native_worker_start(VALUE self) {
  ddog_MaybeError err = ddog_telemetry_handle_start(get_worker_handle(self));
  CHECK_TELEMETRY_ERROR("Failed to start telemetry worker", err);
  return Qtrue;
}

static VALUE _native_worker_stop(VALUE self) {
  ddog_MaybeError err = ddog_telemetry_handle_stop(get_worker_handle(self));
  CHECK_TELEMETRY_ERROR("Failed to stop telemetry worker", err);
  return Qtrue;
}

static VALUE _native_worker_shutdown(VALUE self, VALUE timeout_milliseconds) {
  ENFORCE_TYPE(timeout_milliseconds, T_FIXNUM);

  telemetry_worker_t *worker;
  TypedData_Get_Struct(self, telemetry_worker_t, &telemetry_worker_typed_data, worker);
  if (worker->handle == NULL) return Qtrue;

  _native_worker_stop(self);

  // wait_for_shutdown_ms takes ownership of the handle.
  ddog_TelemetryWorkerHandle *handle = worker->handle;
  worker->handle = NULL;
  ddog_telemetry_handle_wait_for_shutdown_ms(handle, NUM2ULL(timeout_milliseconds));
  return Qtrue;
}

static bool metric_type_symbol_to_enum(VALUE symbol, ddog_MetricType *out_type) {
  ID id = SYM2ID(symbol);
#define CHECK_METRIC_TYPE(name, value) \
  if (id == rb_intern(name)) { *out_type = (value); return true; }
  CHECK_METRIC_TYPE("gauge", DDOG_METRIC_TYPE_GAUGE)
  CHECK_METRIC_TYPE("count", DDOG_METRIC_TYPE_COUNT)
  CHECK_METRIC_TYPE("distribution", DDOG_METRIC_TYPE_DISTRIBUTION)
  CHECK_METRIC_TYPE("rate", DDOG_METRIC_TYPE_RATE)
#undef CHECK_METRIC_TYPE
  return false;
}

static bool namespace_symbol_to_enum(VALUE symbol, ddog_MetricNamespace *out_namespace) {
  ID id = SYM2ID(symbol);
#define CHECK_NAMESPACE(name, value) \
  if (id == rb_intern(name)) { *out_namespace = (value); return true; }
  CHECK_NAMESPACE("tracers", DDOG_METRIC_NAMESPACE_TRACERS)
  CHECK_NAMESPACE("profilers", DDOG_METRIC_NAMESPACE_PROFILERS)
  CHECK_NAMESPACE("rum", DDOG_METRIC_NAMESPACE_RUM)
  CHECK_NAMESPACE("appsec", DDOG_METRIC_NAMESPACE_APPSEC)
  CHECK_NAMESPACE("ide_plugins", DDOG_METRIC_NAMESPACE_IDE_PLUGINS)
  CHECK_NAMESPACE("live_debugger", DDOG_METRIC_NAMESPACE_LIVE_DEBUGGER)
  CHECK_NAMESPACE("iast", DDOG_METRIC_NAMESPACE_IAST)
  CHECK_NAMESPACE("general", DDOG_METRIC_NAMESPACE_GENERAL)
  CHECK_NAMESPACE("telemetry", DDOG_METRIC_NAMESPACE_TELEMETRY)
  CHECK_NAMESPACE("apm", DDOG_METRIC_NAMESPACE_APM)
  CHECK_NAMESPACE("sidecar", DDOG_METRIC_NAMESPACE_SIDECAR)
  CHECK_NAMESPACE("civisibility", DDOG_METRIC_NAMESPACE_CIVISIBILITY)
  CHECK_NAMESPACE("mlobs", DDOG_METRIC_NAMESPACE_MLOBS)
  CHECK_NAMESPACE("ddtraceapi", DDOG_METRIC_NAMESPACE_DDTRACEAPI)
  CHECK_NAMESPACE("ai_guard", DDOG_METRIC_NAMESPACE_AI_GUARD)
  CHECK_NAMESPACE("debugger", DDOG_METRIC_NAMESPACE_DEBUGGER)
#undef CHECK_NAMESPACE
  return false;
}

static VALUE _native_worker_register_metric_context(
    VALUE self, VALUE name, VALUE metric_type, VALUE common, VALUE namespace) {
  ENFORCE_TYPE(name, T_STRING);
  ENFORCE_TYPE(metric_type, T_SYMBOL);
  ENFORCE_BOOLEAN(common);
  ENFORCE_TYPE(namespace, T_SYMBOL);

  ddog_MetricType type;
  if (!metric_type_symbol_to_enum(metric_type, &type)) {
    raise_error(rb_eArgError, "Unexpected metric type: %+"PRIsVALUE, metric_type);
  }
  ddog_MetricNamespace namespace_enum;
  if (!namespace_symbol_to_enum(namespace, &namespace_enum)) {
    raise_error(rb_eArgError, "Unexpected metric namespace: %+"PRIsVALUE, namespace);
  }

  // Tags are passed per point instead: callers use varying tag sets under the
  // same metric name, so the context carries none of its own.
  // The empty Vec_Tag moves by value: libdatadog takes ownership of it.
  ddog_Vec_Tag empty_tags = ddog_Vec_Tag_new();
  ddog_ContextKey key = ddog_telemetry_handle_register_metric_context(
      get_worker_handle(self),
      char_slice_from_ruby_string(name),
      type,
      empty_tags,
      common == Qtrue,
      namespace_enum);

  telemetry_metric_context_t *metric_context = ruby_xmalloc(sizeof(telemetry_metric_context_t));
  metric_context->key = key;
  return TypedData_Wrap_Struct(telemetry_metric_context_class, &telemetry_metric_context_typed_data, metric_context);
}

static VALUE _native_worker_add_point(VALUE self, VALUE context, VALUE value, VALUE tags_as_array) {
  ENFORCE_TYPE(context, T_DATA);
  ENFORCE_TYPE(tags_as_array, T_ARRAY);
  double point_value = NUM2DBL(value);

  ddog_ContextKey key = get_metric_context(context);

  // Tags are heap-allocated, so after this point the code must not raise
  // exceptions, or the memory will leak.
  // The Vec_Tag moves by value: libdatadog takes ownership of it, so the
  // code must not drop it here, not even on the error path below.
  ddog_Vec_Tag tags = convert_tags(tags_as_array);

  ddog_MaybeError err = ddog_telemetry_handle_add_point_with_tags(
      get_worker_handle(self), &key, point_value, tags);

  CHECK_TELEMETRY_ERROR("Failed to add telemetry metric point", err);
  return Qtrue;
}

static VALUE _native_worker_add_log(
    VALUE self, VALUE identifier, VALUE message, VALUE level, VALUE stack_trace) {
  ENFORCE_TYPE(identifier, T_STRING);
  ENFORCE_TYPE(message, T_STRING);
  ENFORCE_TYPE(level, T_SYMBOL);
  if (stack_trace != Qnil) ENFORCE_TYPE(stack_trace, T_STRING);

  ddog_LogLevel level_enum;
  ID id = SYM2ID(level);
  if (id == rb_intern("error")) {
    level_enum = DDOG_LOG_LEVEL_ERROR;
  } else if (id == rb_intern("warn")) {
    level_enum = DDOG_LOG_LEVEL_WARN;
  } else {
    raise_error(rb_eArgError, "Unexpected log level: %+"PRIsVALUE, level);
  }

  ddog_CharSlice stack_trace_slice;
  if (stack_trace == Qnil) {
    stack_trace_slice = (ddog_CharSlice){.ptr = "", .len = 0};
  } else {
    stack_trace_slice = char_slice_from_ruby_string(stack_trace);
  }

  ddog_MaybeError err = ddog_telemetry_handle_add_log(
      get_worker_handle(self),
      char_slice_from_ruby_string(identifier),
      char_slice_from_ruby_string(message),
      level_enum,
      stack_trace_slice);
  CHECK_TELEMETRY_ERROR("Failed to add telemetry log", err);
  return Qtrue;
}

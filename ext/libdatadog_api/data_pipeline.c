#include <ruby.h>
#include <datadog/crashtracker.h>
#include <datadog/data-pipeline.h>
#include <stdint.h>

#include "datadog_ruby_common.h"
#include "ruby/internal/arithmetic/double.h"
#include "ruby/internal/arithmetic/int.h"
#include "ruby/internal/special_consts.h"

static VALUE trace_exporter_class;
static VALUE trace_exporter_config_class;
static VALUE rb_eTraceExporterError;

static VALUE _native_trace_exporter_initialize(VALUE self,  VALUE config);
static VALUE _native_trace_exporter_send(VALUE self, VALUE payload, VALUE trace_count);

static VALUE _native_trace_exporter_config_initialize(VALUE self);
static VALUE _native_trace_exporter_config_set_url(VALUE self, VALUE url);
static VALUE _native_trace_exporter_config_set_tracer_version(VALUE self, VALUE tracer_version);
static VALUE _native_trace_exporter_config_set_env(VALUE self, VALUE env);
static VALUE _native_trace_exporter_config_set_service(VALUE self, VALUE service);

static VALUE trace_exporter_alloc(VALUE klass);
static VALUE trace_exporter_config_alloc(VALUE klass);
static void free_trace_exporter(void *ptr);
static void free_trace_exporter_config(void *ptr);

[[noreturn]] static void closed_exporter(void)
{
    rb_raise(rb_eTraceExporterError, "invalid exporter");
}

[[noreturn]] static void closed_exporter_config(void)
{
    rb_raise(rb_eTraceExporterError, "invalid exporter config");
}

#define GetTraceExporter(obj, exporter) do {\
    TypedData_Get_Struct((obj), struct trace_exporter_object, &trace_exporter_type, (exporter));\
    if ((exporter) == 0 || (exporter)->inner == 0) closed_exporter() ;\
} while (0)

#define GetTraceExporterConfig(obj, config) do {\
    TypedData_Get_Struct((obj), struct trace_exporter_config_object, &trace_exporter_config_type, (config));\
    if ((config) == 0 || (config)->inner == 0) closed_exporter_config();\
} while (0)

void trace_exporter_init() {
  VALUE datadog_module = rb_define_module("Datadog");
  VALUE tracing_module = rb_define_module_under(datadog_module, "Tracing");
  VALUE transport_module = rb_define_module_under(tracing_module, "Transport");
  VALUE trace_exporter_module = rb_define_module_under(transport_module, "TraceExporter");
  trace_exporter_class = rb_define_class_under(trace_exporter_module, "Component", rb_cObject);
  trace_exporter_config_class = rb_define_class_under(trace_exporter_module, "TraceExporterConfig", rb_cObject);
  rb_eTraceExporterError = rb_define_class("TraceExporterError", rb_eStandardError);
  rb_define_alloc_func(trace_exporter_class, trace_exporter_alloc);
  rb_define_alloc_func(trace_exporter_config_class, trace_exporter_config_alloc);
  rb_define_method(trace_exporter_class, "initialize", _native_trace_exporter_initialize, 1);
  rb_define_method(trace_exporter_class, "send", _native_trace_exporter_send, 2);
  rb_define_method(trace_exporter_config_class, "initialize", _native_trace_exporter_config_initialize, 0);
  rb_define_method(trace_exporter_config_class, "set_url", _native_trace_exporter_config_set_url, 1);
  rb_define_method(trace_exporter_config_class, "set_tracer_version", _native_trace_exporter_config_set_tracer_version, 1);
  rb_define_method(trace_exporter_config_class, "set_env", _native_trace_exporter_config_set_env, 1);
  rb_define_method(trace_exporter_config_class, "set_service", _native_trace_exporter_config_set_service, 1);
}

struct trace_exporter_object {
  ddog_TraceExporter* inner;
};

struct trace_exporter_config_object {
  ddog_TraceExporterConfig* inner;
};

typedef struct trace_exporter_object trace_exporter_object;
typedef struct trace_exporter_config_object trace_exporter_config_object;

static const rb_data_type_t trace_exporter_type = {
  "trace_exporter",
  {0,free_trace_exporter,0,0,{0}},
  0,0,0
};

static const rb_data_type_t trace_exporter_config_type = {
  "trace_exporter_config",
  {0,free_trace_exporter_config,0,0,{0}},
  0,0,0
};

static VALUE trace_exporter_alloc(VALUE klass){
  trace_exporter_object* exporter;
  return TypedData_Make_Struct(klass, trace_exporter_object, &trace_exporter_type, exporter);
}
static VALUE trace_exporter_config_alloc(VALUE klass){
  trace_exporter_config_object* config;
  return TypedData_Make_Struct(klass, trace_exporter_config_object, &trace_exporter_config_type, config);
}

static VALUE _native_trace_exporter_config_initialize(VALUE self) {
  trace_exporter_config_object *config_object;
  TypedData_Get_Struct(self, trace_exporter_config_object, &trace_exporter_config_type, config_object);
  ddog_trace_exporter_config_new(&config_object->inner);
  ddog_trace_exporter_config_set_language(config_object->inner, DDOG_CHARSLICE_C("ruby"));
  return Qnil;
}

static VALUE _native_trace_exporter_config_set_url(VALUE self, VALUE url) {
  trace_exporter_config_object *config_object;
  GetTraceExporterConfig(self, config_object);
  ddog_trace_exporter_config_set_url(config_object->inner, char_slice_from_ruby_string(url));
  return self;
}

static VALUE _native_trace_exporter_config_set_tracer_version(VALUE self, VALUE tracer_version) {
  trace_exporter_config_object *config_object;
  GetTraceExporterConfig(self, config_object);
  ddog_trace_exporter_config_set_tracer_version(config_object->inner, char_slice_from_ruby_string(tracer_version));
  return self;
}

static VALUE _native_trace_exporter_config_set_env(VALUE self, VALUE env) {
  trace_exporter_config_object *config_object;
  GetTraceExporterConfig(self, config_object);
  ddog_trace_exporter_config_set_env(config_object->inner, char_slice_from_ruby_string(env));
  return self;
}

static VALUE _native_trace_exporter_config_set_service(VALUE self, VALUE service) {
  trace_exporter_config_object *config_object;
  GetTraceExporterConfig(self, config_object);
  ddog_trace_exporter_config_set_service(config_object->inner, char_slice_from_ruby_string(service));
  return self;
}

static VALUE _native_trace_exporter_initialize(DDTRACE_UNUSED VALUE self, VALUE config_instance) {
  trace_exporter_config_object *config_object;
  trace_exporter_object *exporter_object;
  GetTraceExporterConfig(config_instance, config_object);
  TypedData_Get_Struct(self, struct trace_exporter_object, &trace_exporter_type, exporter_object);
  ddog_TraceExporterError* err = ddog_trace_exporter_new(&exporter_object->inner, config_object->inner);
  if (err!=NULL) {
    rb_raise(rb_eArgError,"TraceExporter error : %+"PRIsVALUE, INT2NUM(err->code));
  }
  return Qnil;
}

static VALUE _native_trace_exporter_send(VALUE self, VALUE payload, VALUE trace_count) {
  trace_exporter_object *exporter_object;
  GetTraceExporter(self, exporter_object);
  char_slice_from_ruby_string(payload);
  ddog_AgentResponse response;
  ddog_trace_exporter_send(exporter_object->inner, byte_slice_from_ruby_string(payload), NUM2INT(trace_count), &response);
  return rb_float_new(response.rate);
}

static void free_trace_exporter(void *ptr){
  trace_exporter_object *exporter = ptr;
  if (exporter->inner != 0) {
    ddog_trace_exporter_free(exporter->inner);
  }
  ruby_xfree(ptr);
}
static void free_trace_exporter_config(void *ptr){
  trace_exporter_config_object *config = ptr;
  if (config->inner != 0) {
  ddog_trace_exporter_config_free(config->inner);
  }
  ruby_xfree(ptr);
}


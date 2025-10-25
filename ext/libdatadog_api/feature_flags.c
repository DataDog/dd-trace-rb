#include <ruby.h>
#include <datadog/datadog_ffe.h>

#include "datadog_ruby_common.h"

// Forward declarations
static VALUE configuration_alloc(VALUE klass);
static void configuration_free(void *ptr);
static VALUE configuration_initialize(VALUE self, VALUE json_str);

static VALUE evaluation_context_alloc(VALUE klass);
static void evaluation_context_free(void *ptr);
static VALUE evaluation_context_initialize(VALUE self, VALUE targeting_key);
static VALUE evaluation_context_initialize_with_attribute(VALUE self, VALUE targeting_key, VALUE attr_name, VALUE attr_value);

static VALUE assignment_alloc(VALUE klass);
static void assignment_free(void *ptr);

static VALUE native_get_assignment(VALUE self, VALUE config, VALUE flag_key, VALUE context);

NORETURN(static void raise_ffe_error(const char *message, ddog_VoidResult result));

void feature_flags_init(VALUE core_module) {
  VALUE feature_flags_module = rb_define_module_under(core_module, "FeatureFlags");

  // Configuration class
  VALUE configuration_class = rb_define_class_under(feature_flags_module, "Configuration", rb_cObject);
  rb_define_alloc_func(configuration_class, configuration_alloc);
  rb_define_method(configuration_class, "_native_initialize", configuration_initialize, 1);

  // EvaluationContext class  
  VALUE evaluation_context_class = rb_define_class_under(feature_flags_module, "EvaluationContext", rb_cObject);
  rb_define_alloc_func(evaluation_context_class, evaluation_context_alloc);
  rb_define_method(evaluation_context_class, "_native_initialize", evaluation_context_initialize, 1);
  rb_define_method(evaluation_context_class, "_native_initialize_with_attribute", evaluation_context_initialize_with_attribute, 3);

  // Assignment class
  VALUE assignment_class = rb_define_class_under(feature_flags_module, "Assignment", rb_cObject);
  rb_define_alloc_func(assignment_class, assignment_alloc);

  // Module-level method
  rb_define_module_function(feature_flags_module, "_native_get_assignment", native_get_assignment, 3);
}

// Configuration TypedData definition
static const rb_data_type_t configuration_typed_data = {
  .wrap_struct_name = "Datadog::Core::FeatureFlags::Configuration",
  .function = {
    .dmark = NULL,
    .dfree = configuration_free,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE configuration_alloc(VALUE klass) {
  ddog_ffe_Handle_Configuration *config = ruby_xcalloc(1, sizeof(ddog_ffe_Handle_Configuration));
  return TypedData_Wrap_Struct(klass, &configuration_typed_data, config);
}

static void configuration_free(void *ptr) {
  ddog_ffe_Handle_Configuration *config = (ddog_ffe_Handle_Configuration *) ptr;
  ddog_ffe_configuration_drop(config);
  ruby_xfree(ptr);
}

static VALUE configuration_initialize(VALUE self, VALUE json_str) {
  Check_Type(json_str, T_STRING);

  ddog_ffe_Handle_Configuration *config;
  TypedData_Get_Struct(self, ddog_ffe_Handle_Configuration, &configuration_typed_data, config);

  *config = ddog_ffe_configuration_new(RSTRING_PTR(json_str));

  return self;
}

// EvaluationContext TypedData definition
static const rb_data_type_t evaluation_context_typed_data = {
  .wrap_struct_name = "Datadog::Core::FeatureFlags::EvaluationContext",
  .function = {
    .dmark = NULL,
    .dfree = evaluation_context_free,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE evaluation_context_alloc(VALUE klass) {
  ddog_ffe_Handle_EvaluationContext *context = ruby_xcalloc(1, sizeof(ddog_ffe_Handle_EvaluationContext));
  return TypedData_Wrap_Struct(klass, &evaluation_context_typed_data, context);
}

static void evaluation_context_free(void *ptr) {
  ddog_ffe_Handle_EvaluationContext *context = (ddog_ffe_Handle_EvaluationContext *) ptr;
  ddog_ffe_evaluation_context_drop(context);
  ruby_xfree(ptr);
}

static VALUE evaluation_context_initialize(VALUE self, VALUE targeting_key) {
  Check_Type(targeting_key, T_STRING);

  ddog_ffe_Handle_EvaluationContext *context;
  TypedData_Get_Struct(self, ddog_ffe_Handle_EvaluationContext, &evaluation_context_typed_data, context);

  *context = ddog_ffe_evaluation_context_new(RSTRING_PTR(targeting_key));

  return self;
}

static VALUE evaluation_context_initialize_with_attribute(VALUE self, VALUE targeting_key, VALUE attr_name, VALUE attr_value) {
  Check_Type(targeting_key, T_STRING);
  Check_Type(attr_name, T_STRING);
  Check_Type(attr_value, T_STRING);

  ddog_ffe_Handle_EvaluationContext *context;
  TypedData_Get_Struct(self, ddog_ffe_Handle_EvaluationContext, &evaluation_context_typed_data, context);

  *context = ddog_ffe_evaluation_context_new_with_attribute(
    RSTRING_PTR(targeting_key),
    RSTRING_PTR(attr_name), 
    RSTRING_PTR(attr_value)
  );

  return self;
}

// Assignment TypedData definition
static const rb_data_type_t assignment_typed_data = {
  .wrap_struct_name = "Datadog::Core::FeatureFlags::Assignment",
  .function = {
    .dmark = NULL,
    .dfree = assignment_free,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE assignment_alloc(VALUE klass) {
  ddog_ffe_Handle_Assignment *assignment = ruby_xcalloc(1, sizeof(ddog_ffe_Handle_Assignment));
  return TypedData_Wrap_Struct(klass, &assignment_typed_data, assignment);
}

static void assignment_free(void *ptr) {
  ddog_ffe_Handle_Assignment *assignment = (ddog_ffe_Handle_Assignment *) ptr;
  ddog_ffe_assignment_drop(assignment);
  ruby_xfree(ptr);
}

static void raise_ffe_error(const char *message, ddog_VoidResult result) {
  rb_raise(rb_eRuntimeError, "%s: %"PRIsVALUE, message, get_error_details_and_drop(&result.err));
}

static VALUE native_get_assignment(VALUE self, VALUE config_obj, VALUE flag_key, VALUE context_obj) {
  Check_Type(flag_key, T_STRING);

  ddog_ffe_Handle_Configuration *config;
  TypedData_Get_Struct(config_obj, ddog_ffe_Handle_Configuration, &configuration_typed_data, config);

  ddog_ffe_Handle_EvaluationContext *context;
  TypedData_Get_Struct(context_obj, ddog_ffe_Handle_EvaluationContext, &evaluation_context_typed_data, context);

  ddog_ffe_Handle_Assignment assignment_out;
  ddog_VoidResult result = ddog_ffe_get_assignment(config, RSTRING_PTR(flag_key), context, &assignment_out);

  if (result.tag == DDOG_VOID_RESULT_ERR) {
    raise_ffe_error("Feature flag evaluation failed", result);
  }

  // Check if assignment is empty (no assignment returned)
  if (assignment_out.inner == NULL) {
    return Qnil;
  }

  // Create a new Assignment Ruby object and wrap the result
  VALUE assignment_class = rb_const_get_at(rb_const_get_at(rb_const_get(rb_cObject, rb_intern("Datadog")), rb_intern("Core")), rb_intern("FeatureFlags"));
  assignment_class = rb_const_get(assignment_class, rb_intern("Assignment"));
  
  VALUE assignment_obj = assignment_alloc(assignment_class);
  
  ddog_ffe_Handle_Assignment *assignment_ptr;
  TypedData_Get_Struct(assignment_obj, ddog_ffe_Handle_Assignment, &assignment_typed_data, assignment_ptr);
  
  *assignment_ptr = assignment_out;

  return assignment_obj;
}

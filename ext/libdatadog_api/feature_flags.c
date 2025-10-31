#include <ruby.h>
#include <datadog/datadog_ffe.h>

#include "datadog_ruby_common.h"

// Forward declarations
static VALUE configuration_alloc(VALUE klass);
static void configuration_free(void *ptr);
static VALUE configuration_initialize(VALUE self, VALUE json_str);

static VALUE evaluation_context_alloc(VALUE klass);
static void evaluation_context_free(void *ptr);
static VALUE evaluation_context_initialize_with_attributes(VALUE self, VALUE targeting_key, VALUE attributes_hash);

static VALUE assignment_alloc(VALUE klass);
static void assignment_free(void *ptr);

static VALUE native_get_assignment(VALUE self, VALUE config, VALUE flag_key, VALUE context);


void feature_flags_init(VALUE open_feature_module) {
  VALUE binding_module = rb_define_module_under(open_feature_module, "Binding");

  // Configuration class
  VALUE configuration_class = rb_define_class_under(binding_module, "Configuration", rb_cObject);
  rb_define_alloc_func(configuration_class, configuration_alloc);
  rb_define_method(configuration_class, "_native_initialize", configuration_initialize, 1);

  // EvaluationContext class  
  VALUE evaluation_context_class = rb_define_class_under(binding_module, "EvaluationContext", rb_cObject);
  rb_define_alloc_func(evaluation_context_class, evaluation_context_alloc);
  rb_define_method(evaluation_context_class, "_native_initialize_with_attributes", evaluation_context_initialize_with_attributes, 2);

  // Assignment class
  VALUE assignment_class = rb_define_class_under(binding_module, "Assignment", rb_cObject);
  rb_define_alloc_func(assignment_class, assignment_alloc);

  // Module-level method
  rb_define_module_function(binding_module, "_native_get_assignment", native_get_assignment, 3);
}

// Configuration TypedData definition
static const rb_data_type_t configuration_typed_data = {
  .wrap_struct_name = "Datadog::OpenFeature::Binding::Configuration",
  .function = {
    .dmark = NULL,
    .dfree = configuration_free,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE configuration_alloc(VALUE klass) {
  ddog_ffe_Handle_Configuration *config = ruby_xcalloc(1, sizeof(ddog_ffe_Handle_Configuration));
  config->inner = NULL; // Explicitly initialize to NULL
  return TypedData_Wrap_Struct(klass, &configuration_typed_data, config);
}

static void configuration_free(void *ptr) {
  ddog_ffe_Handle_Configuration *config = (ddog_ffe_Handle_Configuration *) ptr;
  if (config) {
    ddog_ffe_configuration_drop(config);
  }
  ruby_xfree(ptr);
}

static VALUE configuration_initialize(VALUE self, VALUE json_str) {
  Check_Type(json_str, T_STRING);

  ddog_ffe_Handle_Configuration *config;
  TypedData_Get_Struct(self, ddog_ffe_Handle_Configuration, &configuration_typed_data, config);

  struct ddog_ffe_Result_HandleConfiguration result = ddog_ffe_configuration_new(RSTRING_PTR(json_str));
  if (result.tag == DDOG_FFE_RESULT_HANDLE_CONFIGURATION_ERR_HANDLE_CONFIGURATION) {
    rb_raise(rb_eRuntimeError, "Failed to create configuration: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }
  
  *config = result.ok;

  return self;
}

// EvaluationContext TypedData definition
static const rb_data_type_t evaluation_context_typed_data = {
  .wrap_struct_name = "Datadog::OpenFeature::Binding::EvaluationContext",
  .function = {
    .dmark = NULL,
    .dfree = evaluation_context_free,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE evaluation_context_alloc(VALUE klass) {
  ddog_ffe_Handle_EvaluationContext *context = ruby_xcalloc(1, sizeof(ddog_ffe_Handle_EvaluationContext));
  context->inner = NULL; // Explicitly initialize to NULL
  return TypedData_Wrap_Struct(klass, &evaluation_context_typed_data, context);
}

static void evaluation_context_free(void *ptr) {
  ddog_ffe_Handle_EvaluationContext *context = (ddog_ffe_Handle_EvaluationContext *) ptr;
  if (context) {
    ddog_ffe_evaluation_context_drop(context);
  }
  ruby_xfree(ptr);
}



static VALUE evaluation_context_initialize_with_attributes(VALUE self, VALUE targeting_key, VALUE attributes_hash) {
  Check_Type(targeting_key, T_STRING);
  Check_Type(attributes_hash, T_HASH);

  ddog_ffe_Handle_EvaluationContext *context;
  TypedData_Get_Struct(self, ddog_ffe_Handle_EvaluationContext, &evaluation_context_typed_data, context);

  // Get the number of attributes
  long attr_count = RHASH_SIZE(attributes_hash);
  
  if (attr_count == 0) {
    // If no attributes, pass NULL and 0
    *context = ddog_ffe_evaluation_context_new(RSTRING_PTR(targeting_key), NULL, 0);
    return self;
  }

  // Allocate array for attributes
  struct ddog_ffe_AttributePair *attrs = ruby_xcalloc(attr_count, sizeof(struct ddog_ffe_AttributePair));
  
  // Convert hash to attribute pairs
  VALUE keys = rb_funcall(attributes_hash, rb_intern("keys"), 0);
  for (long i = 0; i < attr_count; i++) {
    VALUE key = rb_ary_entry(keys, i);
    VALUE value = rb_hash_aref(attributes_hash, key);
    
    Check_Type(key, T_STRING);
    Check_Type(value, T_STRING);
    
    attrs[i].name = RSTRING_PTR(key);
    attrs[i].value = RSTRING_PTR(value);
  }
  
  *context = ddog_ffe_evaluation_context_new(
    RSTRING_PTR(targeting_key),
    attrs,
    attr_count
  );
  
  ruby_xfree(attrs);
  return self;
}

// Assignment TypedData definition
static const rb_data_type_t assignment_typed_data = {
  .wrap_struct_name = "Datadog::OpenFeature::Binding::Assignment",
  .function = {
    .dmark = NULL,
    .dfree = assignment_free,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE assignment_alloc(VALUE klass) {
  ddog_ffe_Handle_Assignment *assignment = ruby_xcalloc(1, sizeof(ddog_ffe_Handle_Assignment));
  assignment->inner = NULL; // Explicitly initialize to NULL
  return TypedData_Wrap_Struct(klass, &assignment_typed_data, assignment);
}

static void assignment_free(void *ptr) {
  ddog_ffe_Handle_Assignment *assignment = (ddog_ffe_Handle_Assignment *) ptr;
  if (assignment) {
    ddog_ffe_assignment_drop(assignment);
  }
  ruby_xfree(ptr);
}


static VALUE native_get_assignment(VALUE self, VALUE config_obj, VALUE flag_key, VALUE context_obj) {
  Check_Type(flag_key, T_STRING);

  ddog_ffe_Handle_Configuration *config;
  TypedData_Get_Struct(config_obj, ddog_ffe_Handle_Configuration, &configuration_typed_data, config);

  ddog_ffe_Handle_EvaluationContext *context;
  TypedData_Get_Struct(context_obj, ddog_ffe_Handle_EvaluationContext, &evaluation_context_typed_data, context);

  struct ddog_ffe_Result_HandleAssignment result = ddog_ffe_get_assignment(config, RSTRING_PTR(flag_key), context);

  if (result.tag == DDOG_FFE_RESULT_HANDLE_ASSIGNMENT_ERR_HANDLE_ASSIGNMENT) {
    rb_raise(rb_eRuntimeError, "Feature flag evaluation failed: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }

  ddog_ffe_Handle_Assignment assignment_out = result.ok;

  // Check if assignment is empty (no assignment returned)
  if (assignment_out.inner == NULL) {
    return Qnil;
  }

  // Create a new Assignment Ruby object and wrap the result
  VALUE assignment_class = rb_const_get_at(rb_const_get_at(rb_const_get(rb_cObject, rb_intern("Datadog")), rb_intern("OpenFeature")), rb_intern("Binding"));
  assignment_class = rb_const_get(assignment_class, rb_intern("Assignment"));
  
  VALUE assignment_obj = assignment_alloc(assignment_class);
  
  ddog_ffe_Handle_Assignment *assignment_ptr;
  TypedData_Get_Struct(assignment_obj, ddog_ffe_Handle_Assignment, &assignment_typed_data, assignment_ptr);
  
  *assignment_ptr = assignment_out;

  return assignment_obj;
}

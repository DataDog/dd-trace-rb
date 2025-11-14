#include <ruby.h>
#include <datadog/datadog_ffe.h>
#include <string.h>
#include <stdlib.h>

#include "datadog_ruby_common.h"

// Forward declarations
static VALUE configuration_alloc(VALUE klass);
static void configuration_free(void *ptr);
static VALUE configuration_initialize(VALUE self, VALUE json_str);

static VALUE evaluation_context_alloc(VALUE klass);
static void evaluation_context_free(void *ptr);
static VALUE evaluation_context_initialize_with_attributes(VALUE self, VALUE targeting_key, VALUE attributes_hash);

static VALUE resolution_details_alloc(VALUE klass);
static void resolution_details_free(void *ptr);

// Resolution details accessor methods
static VALUE resolution_details_get_value(VALUE self);
static VALUE resolution_details_get_reason(VALUE self);
static VALUE resolution_details_get_error_code(VALUE self);
static VALUE resolution_details_get_error_message(VALUE self);
static VALUE resolution_details_get_variant(VALUE self);
static VALUE resolution_details_get_allocation_key(VALUE self);
static VALUE resolution_details_get_do_log(VALUE self);
static VALUE resolution_details_get_flag_metadata(VALUE self);

static VALUE native_get_assignment(VALUE self, VALUE config, VALUE flag_key, VALUE context);


void feature_flags_init(VALUE open_feature_module) {
  // Always define the Binding module - it will reuse existing if it exists
  VALUE binding_module = rb_define_module_under(open_feature_module, "Binding");

  // Configuration class
  VALUE configuration_class = rb_define_class_under(binding_module, "Configuration", rb_cObject);
  rb_define_alloc_func(configuration_class, configuration_alloc);
  rb_define_method(configuration_class, "_native_initialize", configuration_initialize, 1);

  // EvaluationContext class
  VALUE evaluation_context_class = rb_define_class_under(binding_module, "EvaluationContext", rb_cObject);
  rb_define_alloc_func(evaluation_context_class, evaluation_context_alloc);
  rb_define_method(evaluation_context_class, "_native_initialize_with_attributes", evaluation_context_initialize_with_attributes, 2);

  // ResolutionDetails class
  VALUE resolution_details_class = rb_define_class_under(binding_module, "ResolutionDetails", rb_cObject);
  rb_define_alloc_func(resolution_details_class, resolution_details_alloc);

  rb_define_method(resolution_details_class, "value", resolution_details_get_value, 0);
  rb_define_method(resolution_details_class, "reason", resolution_details_get_reason, 0);
  rb_define_method(resolution_details_class, "error_code", resolution_details_get_error_code, 0);
  rb_define_method(resolution_details_class, "error_message", resolution_details_get_error_message, 0);
  rb_define_method(resolution_details_class, "variant", resolution_details_get_variant, 0);
  rb_define_method(resolution_details_class, "allocation_key", resolution_details_get_allocation_key, 0);
  rb_define_method(resolution_details_class, "do_log", resolution_details_get_do_log, 0);

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
  *config = NULL; // Initialize the handle to NULL
  return TypedData_Wrap_Struct(klass, &configuration_typed_data, config);
}

static void configuration_free(void *ptr) {
  ddog_ffe_Handle_Configuration *config = (ddog_ffe_Handle_Configuration *) ptr;
  if (config && *config) {
    ddog_ffe_configuration_drop(config);
  }
  ruby_xfree(ptr);
}

static VALUE configuration_initialize(VALUE self, VALUE json_str) {
  Check_Type(json_str, T_STRING);

  ddog_ffe_Handle_Configuration *config;
  TypedData_Get_Struct(self, ddog_ffe_Handle_Configuration, &configuration_typed_data, config);

  // Create BorrowedStr for the JSON input
  struct ddog_ffe_BorrowedStr json_borrowed = {
    .ptr = (const uint8_t*)RSTRING_PTR(json_str),
    .len = RSTRING_LEN(json_str)
  };

  struct ddog_ffe_Result_HandleConfiguration result = ddog_ffe_configuration_new(json_borrowed);
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
  *context = NULL; // Initialize the handle to NULL
  return TypedData_Wrap_Struct(klass, &evaluation_context_typed_data, context);
}

static void evaluation_context_free(void *ptr) {
  ddog_ffe_Handle_EvaluationContext *context = (ddog_ffe_Handle_EvaluationContext *) ptr;
  if (context && *context) {
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

    attrs[i].name = RSTRING_PTR(key);

    // Set the value based on its Ruby type
    switch (TYPE(value)) {
      case T_STRING:
        attrs[i].value.tag = DDOG_FFE_ATTRIBUTE_VALUE_STRING;
        attrs[i].value.string = RSTRING_PTR(value);
        break;
      case T_FIXNUM:
      case T_FLOAT:
        attrs[i].value.tag = DDOG_FFE_ATTRIBUTE_VALUE_NUMBER;
        attrs[i].value.number = NUM2DBL(value);
        break;
      case T_TRUE:
        attrs[i].value.tag = DDOG_FFE_ATTRIBUTE_VALUE_BOOLEAN;
        attrs[i].value.boolean = true;
        break;
      case T_FALSE:
        attrs[i].value.tag = DDOG_FFE_ATTRIBUTE_VALUE_BOOLEAN;
        attrs[i].value.boolean = false;
        break;
      default:
        // Default to string representation
        value = rb_funcall(value, rb_intern("to_s"), 0);
        attrs[i].value.tag = DDOG_FFE_ATTRIBUTE_VALUE_STRING;
        attrs[i].value.string = RSTRING_PTR(value);
        break;
    }
  }

  *context = ddog_ffe_evaluation_context_new(
    RSTRING_PTR(targeting_key),
    attrs,
    attr_count
  );

  ruby_xfree(attrs);
  return self;
}

// ResolutionDetails TypedData definition
static const rb_data_type_t resolution_details_typed_data = {
  .wrap_struct_name = "Datadog::OpenFeature::Binding::ResolutionDetails",
  .function = {
    .dmark = NULL,
    .dfree = resolution_details_free,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE resolution_details_alloc(VALUE klass) {
  ddog_ffe_Handle_ResolutionDetails *resolution_details = ruby_xcalloc(1, sizeof(ddog_ffe_Handle_ResolutionDetails));
  *resolution_details = NULL; // Initialize the handle to NULL
  return TypedData_Wrap_Struct(klass, &resolution_details_typed_data, resolution_details);
}

static void resolution_details_free(void *ptr) {
  ddog_ffe_Handle_ResolutionDetails *resolution_details = (ddog_ffe_Handle_ResolutionDetails *) ptr;
  if (resolution_details && *resolution_details) {
    // Use the new FFI drop function
    ddog_ffe_assignment_drop(resolution_details);
  }
  ruby_xfree(ptr);
}


static VALUE native_get_assignment(VALUE self, VALUE config_obj, VALUE flag_key, VALUE context_obj) {
  Check_Type(flag_key, T_STRING);

  ddog_ffe_Handle_Configuration *config;
  TypedData_Get_Struct(config_obj, ddog_ffe_Handle_Configuration, &configuration_typed_data, config);

  ddog_ffe_Handle_EvaluationContext *context;
  TypedData_Get_Struct(context_obj, ddog_ffe_Handle_EvaluationContext, &evaluation_context_typed_data, context);

  // Validate handles before use
  if (!config || !*config) {
    rb_raise(rb_eRuntimeError, "Configuration handle is NULL");
  }
  if (!context || !*context) {
    rb_raise(rb_eRuntimeError, "Context handle is NULL");
  }

  // Use the new FFI function directly - no Result wrapper
  // For now, use a generic flag type - this could be parameterized later
  ddog_ffe_Handle_ResolutionDetails resolution_details_out = ddog_ffe_get_assignment(
    *config,
    RSTRING_PTR(flag_key),
    DDOG_FFE_EXPECTED_FLAG_TYPE_STRING,  // Default to string type
    *context
  );

  // Check if resolution_details is NULL (no assignment returned)
  if (resolution_details_out == NULL) {
    return Qnil;
  }

  // Create a new ResolutionDetails Ruby object and wrap the result
  VALUE resolution_details_class = rb_const_get_at(rb_const_get_at(rb_const_get(rb_cObject, rb_intern("Datadog")), rb_intern("OpenFeature")), rb_intern("Binding"));
  resolution_details_class = rb_const_get(resolution_details_class, rb_intern("ResolutionDetails"));

  VALUE resolution_details_obj = resolution_details_alloc(resolution_details_class);

  ddog_ffe_Handle_ResolutionDetails *resolution_details_ptr;
  TypedData_Get_Struct(resolution_details_obj, ddog_ffe_Handle_ResolutionDetails, &resolution_details_typed_data, resolution_details_ptr);

  *resolution_details_ptr = resolution_details_out;

  return resolution_details_obj;
}

// Accessor methods for ResolutionDetails
static VALUE resolution_details_get_value(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails *resolution_details;
  TypedData_Get_Struct(self, ddog_ffe_Handle_ResolutionDetails, &resolution_details_typed_data, resolution_details);

  if (!resolution_details) {
    return Qnil;
  }

  // Use the new FFI function to get the value
  struct ddog_ffe_VariantValue value = ddog_ffe_assignment_get_value(*resolution_details);

  switch (value.tag) {
    case DDOG_FFE_VARIANT_VALUE_NONE:
      return Qnil;
    case DDOG_FFE_VARIANT_VALUE_STRING:
      return rb_str_new((const char*)value.string.ptr, value.string.len);
    case DDOG_FFE_VARIANT_VALUE_INTEGER:
      return LONG2NUM(value.integer);
    case DDOG_FFE_VARIANT_VALUE_FLOAT:
      return rb_float_new(value.float_);
    case DDOG_FFE_VARIANT_VALUE_BOOLEAN:
      return value.boolean ? Qtrue : Qfalse;
    case DDOG_FFE_VARIANT_VALUE_OBJECT:
      return rb_str_new((const char*)value.object.ptr, value.object.len);
    default:
      return Qnil;
  }
}

static VALUE resolution_details_get_reason(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails *resolution_details;
  TypedData_Get_Struct(self, ddog_ffe_Handle_ResolutionDetails, &resolution_details_typed_data, resolution_details);

  if (!resolution_details) {
    return Qnil;
  }

  // Use the new FFI function to get the reason
  enum ddog_ffe_Reason reason = ddog_ffe_assignment_get_reason(*resolution_details);

  switch (reason) {
    case DDOG_FFE_REASON_STATIC:
      return ID2SYM(rb_intern("static"));
    case DDOG_FFE_REASON_DEFAULT:
      return ID2SYM(rb_intern("default"));
    case DDOG_FFE_REASON_TARGETING_MATCH:
      return ID2SYM(rb_intern("targeting_match"));
    case DDOG_FFE_REASON_SPLIT:
      return ID2SYM(rb_intern("split"));
    case DDOG_FFE_REASON_DISABLED:
      return ID2SYM(rb_intern("disabled"));
    case DDOG_FFE_REASON_ERROR:
      return ID2SYM(rb_intern("error"));
    default:
      return Qnil;
  }
}

static VALUE resolution_details_get_error_code(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails *resolution_details;
  TypedData_Get_Struct(self, ddog_ffe_Handle_ResolutionDetails, &resolution_details_typed_data, resolution_details);

  if (!resolution_details) {
    return Qnil;
  }

  // Use the new FFI function to get the error code
  enum ddog_ffe_ErrorCode error_code = ddog_ffe_assignment_get_error_code(*resolution_details);

  switch (error_code) {
    case DDOG_FFE_ERROR_CODE_TYPE_MISMATCH:
      return ID2SYM(rb_intern("type_mismatch"));
    case DDOG_FFE_ERROR_CODE_PARSE_ERROR:
      return ID2SYM(rb_intern("parse_error"));
    case DDOG_FFE_ERROR_CODE_FLAG_NOT_FOUND:
      return ID2SYM(rb_intern("flag_not_found"));
    case DDOG_FFE_ERROR_CODE_TARGETING_KEY_MISSING:
      return ID2SYM(rb_intern("targeting_key_missing"));
    case DDOG_FFE_ERROR_CODE_INVALID_CONTEXT:
      return ID2SYM(rb_intern("invalid_context"));
    case DDOG_FFE_ERROR_CODE_PROVIDER_NOT_READY:
      return ID2SYM(rb_intern("provider_not_ready"));
    case DDOG_FFE_ERROR_CODE_GENERAL:
      return ID2SYM(rb_intern("general"));
    default:
      return Qnil;
  }
}

static VALUE resolution_details_get_error_message(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails *resolution_details;
  TypedData_Get_Struct(self, ddog_ffe_Handle_ResolutionDetails, &resolution_details_typed_data, resolution_details);

  if (!resolution_details) {
    return Qnil;
  }

  // Use the new FFI function to get the error message
  struct ddog_ffe_BorrowedStr error_message = ddog_ffe_assignment_get_error_message(*resolution_details);

  if (error_message.ptr == NULL || error_message.len == 0) {
    return Qnil;
  }

  return rb_str_new((const char*)error_message.ptr, error_message.len);
}

static VALUE resolution_details_get_variant(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails *resolution_details;
  TypedData_Get_Struct(self, ddog_ffe_Handle_ResolutionDetails, &resolution_details_typed_data, resolution_details);

  if (!resolution_details) {
    return Qnil;
  }

  // Use the new FFI function to get the variant
  struct ddog_ffe_BorrowedStr variant = ddog_ffe_assignment_get_variant(*resolution_details);

  if (variant.ptr == NULL || variant.len == 0) {
    return Qnil;
  }

  return rb_str_new((const char*)variant.ptr, variant.len);
}

static VALUE resolution_details_get_allocation_key(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails *resolution_details;
  TypedData_Get_Struct(self, ddog_ffe_Handle_ResolutionDetails, &resolution_details_typed_data, resolution_details);

  if (!resolution_details) {
    return Qnil;
  }

  // Use the new FFI function to get the allocation key
  struct ddog_ffe_BorrowedStr allocation_key = ddog_ffe_assignment_get_allocation_key(*resolution_details);

  if (allocation_key.ptr == NULL || allocation_key.len == 0) {
    return Qnil;
  }

  return rb_str_new((const char*)allocation_key.ptr, allocation_key.len);
}

static VALUE resolution_details_get_do_log(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails *resolution_details;
  TypedData_Get_Struct(self, ddog_ffe_Handle_ResolutionDetails, &resolution_details_typed_data, resolution_details);

  if (!resolution_details) {
    return Qfalse;
  }

  // Use the new FFI function to get the do_log flag
  return ddog_ffe_assignment_get_do_log(*resolution_details) ? Qtrue : Qfalse;
}

static VALUE resolution_details_get_flag_metadata(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails resolution_details =
    (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);
  (void)resolution_details;

  VALUE hash = rb_hash_new();

  // TODO: datadog-ffe-ffi-1.0.1 has a memory corruption bug when
  // returning flag metadata. Therefore, this section is currently
  // commented out.
  //
  // struct ddog_ffe_ArrayMap_BorrowedStr metadata =
  //   ddog_ffe_assignnment_get_flag_metadata(resolution_details);
  //
  // for (size_t i = 0; i < metadata.count; i++) {
  //   ddog_ffe_KeyValue_BorrowedStr kv = metadata.elements[i];
  //   VALUE key = str_from_borrow(kv.key);
  //   VALUE value = str_from_borrow(kv.value);
  //   rb_hash_aset(hash, key, value);
  // }

  return hash;
}

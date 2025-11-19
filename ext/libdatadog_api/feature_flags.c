#include "feature_flags.h"

#include <datadog/ffe.h>
#include <datadog/common.h>

#include "datadog_ruby_common.h"
#include "ruby/internal/intern/string.h"
#include "ruby/internal/value_type.h"

#include <stdint.h>
#include <string.h>
#include <stdlib.h>

/**
 * Borrow a string from Ruby VALUE.
 */
static inline ddog_ffe_BorrowedStr borrow_str(VALUE str) {
  ENFORCE_TYPE(str, T_STRING);
  return (ddog_ffe_BorrowedStr){
    .ptr = (const uint8_t*)RSTRING_PTR(str),
    .len = RSTRING_LEN(str)
  };
}

/**
 * Create a new Ruby string from borrowed string.
 */
static inline VALUE str_from_borrow(ddog_ffe_BorrowedStr str) {
  return rb_str_new((const char *)str.ptr, str.len);
}

static VALUE configuration_new(VALUE klass, VALUE json_str);
static VALUE configuration_get_assignment(VALUE self, VALUE flag_key, VALUE context);
static void configuration_free(void *ptr);

static VALUE resolution_details_get_value(VALUE self);
static VALUE resolution_details_get_reason(VALUE self);
static VALUE resolution_details_get_error_code(VALUE self);
static VALUE resolution_details_get_error_message(VALUE self);
static VALUE resolution_details_is_error(VALUE self);
static VALUE resolution_details_get_variant(VALUE self);
static VALUE resolution_details_get_allocation_key(VALUE self);
static VALUE resolution_details_get_do_log(VALUE self);
static void resolution_details_free(void *ptr);

void feature_flags_init(VALUE core_module) {
  // Always define the Binding module - it will reuse existing if it exists
  VALUE binding_module = rb_define_module_under(core_module, "FeatureFlags");

  VALUE Configuration = rb_define_class_under(binding_module, "Configuration", rb_cObject);
  rb_undef_alloc_func(Configuration);
  rb_define_singleton_method(Configuration, "new", configuration_new, 1);
  rb_define_method(Configuration, "get_assignment", configuration_get_assignment, 2);

  VALUE ResolutionDetails = rb_define_class_under(binding_module, "ResolutionDetails", rb_cObject);
  rb_undef_alloc_func(ResolutionDetails);
  rb_define_method(ResolutionDetails, "value", resolution_details_get_value, 0);
  rb_define_method(ResolutionDetails, "reason", resolution_details_get_reason, 0);
  rb_define_method(ResolutionDetails, "error_code", resolution_details_get_error_code, 0);
  rb_define_method(ResolutionDetails, "error_message", resolution_details_get_error_message, 0);
  rb_define_method(ResolutionDetails, "error?", resolution_details_is_error, 0);
  rb_define_method(ResolutionDetails, "variant", resolution_details_get_variant, 0);
  rb_define_method(ResolutionDetails, "allocation_key", resolution_details_get_allocation_key, 0);
  rb_define_method(ResolutionDetails, "log?", resolution_details_get_do_log, 0);
}

// Configuration TypedData definition
static const rb_data_type_t configuration_data_type = {
  .wrap_struct_name = "Datadog::Core::FeatureFlags::Configuration",
  .function = {
    .dmark = NULL,
    .dfree = configuration_free,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE configuration_new(VALUE klass, VALUE json_str) {
  struct ddog_ffe_Result_HandleConfiguration result = ddog_ffe_configuration_new(borrow_str(json_str));
  if (result.tag == DDOG_FFE_RESULT_HANDLE_CONFIGURATION_ERR_HANDLE_CONFIGURATION) {
    rb_raise(rb_eRuntimeError, "Failed to create configuration: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }

  return TypedData_Wrap_Struct(klass, &configuration_data_type, result.ok);
}

static void configuration_free(void *ptr) {
  ddog_ffe_Handle_Configuration config = (ddog_ffe_Handle_Configuration) ptr;
  ddog_ffe_configuration_drop(&config);
}

/**
 * Context builder structure for hash iteration callback
 */
struct hash_iteration_context {
  ddog_ffe_AttributePair *attrs;
  VALUE *key_refs;
  VALUE *string_value_refs;
  long attr_count;
  long max_attr_count;
  const char *targeting_key;
  VALUE targeting_key_value;
};

/**
 * Hash iteration callback for building attribute pairs
 */
static int build_attributes_callback(VALUE key, VALUE value, VALUE context_ptr) {
  struct hash_iteration_context *ctx = (struct hash_iteration_context *)context_ptr;

  Check_Type(key, T_STRING);

  const char *name = RSTRING_PTR(key);
  if (strcmp(name, "targeting_key") == 0 && TYPE(value) == T_STRING) {
    ctx->targeting_key_value = value; // Keep reference for GC safety
    ctx->targeting_key = RSTRING_PTR(ctx->targeting_key_value);
    return ST_CONTINUE;
  }

  // Prevent buffer overflow
  if (ctx->attr_count >= ctx->max_attr_count) {
    return ST_CONTINUE;
  }

  // Store key reference for GC safety
  ctx->key_refs[ctx->attr_count] = key;
  ctx->attrs[ctx->attr_count].name = RSTRING_PTR(key);

  // Set the value based on its Ruby type
  switch (TYPE(value)) {
    case T_STRING:
      ctx->string_value_refs[ctx->attr_count] = value; // Keep reference for GC safety
      ctx->attrs[ctx->attr_count].value.tag = DDOG_FFE_ATTRIBUTE_VALUE_STRING;
      ctx->attrs[ctx->attr_count].value.string = RSTRING_PTR(value);
      break;
    case T_FIXNUM:
    case T_FLOAT:
      ctx->attrs[ctx->attr_count].value.tag = DDOG_FFE_ATTRIBUTE_VALUE_NUMBER;
      ctx->attrs[ctx->attr_count].value.number = NUM2DBL(value);
      break;
    case T_TRUE:
      ctx->attrs[ctx->attr_count].value.tag = DDOG_FFE_ATTRIBUTE_VALUE_BOOLEAN;
      ctx->attrs[ctx->attr_count].value.boolean = true;
      break;
    case T_FALSE:
      ctx->attrs[ctx->attr_count].value.tag = DDOG_FFE_ATTRIBUTE_VALUE_BOOLEAN;
      ctx->attrs[ctx->attr_count].value.boolean = false;
      break;
    default:
      // Default to string representation
      ctx->string_value_refs[ctx->attr_count] = rb_funcall(value, rb_intern("to_s"), 0);
      ctx->attrs[ctx->attr_count].value.tag = DDOG_FFE_ATTRIBUTE_VALUE_STRING;
      ctx->attrs[ctx->attr_count].value.string = RSTRING_PTR(ctx->string_value_refs[ctx->attr_count]);
      break;
  }

  ctx->attr_count++;
  return ST_CONTINUE;
}

/**
 * Allocates new context from Ruby Hash.
 *
 * # Ownership
 *
 * The returned handle must be dropped with `ddog_ffe_evaluation_context_drop()`.
 */
static ddog_ffe_Handle_EvaluationContext evaluation_context_new(VALUE hash) {
  ENFORCE_TYPE(hash, T_HASH);

  const long max_attr_count = RHASH_SIZE(hash);
  ddog_ffe_AttributePair *const attrs =
      ruby_xcalloc(max_attr_count, sizeof(struct ddog_ffe_AttributePair));

  // Arrays to hold VALUE references for GC safety
  VALUE *key_refs = ruby_xcalloc(max_attr_count, sizeof(VALUE));
  VALUE *string_value_refs = ruby_xcalloc(max_attr_count, sizeof(VALUE));

  // Initialize context for hash iteration
  struct hash_iteration_context ctx = {
    .attrs = attrs,
    .key_refs = key_refs,
    .string_value_refs = string_value_refs,
    .attr_count = 0,
    .max_attr_count = max_attr_count,
    .targeting_key = NULL,
    .targeting_key_value = Qnil
  };

  // Iterate through hash using efficient rb_hash_foreach
  rb_hash_foreach(hash, build_attributes_callback, (VALUE)&ctx);

  const ddog_ffe_Handle_EvaluationContext context = ddog_ffe_evaluation_context_new(
    ctx.targeting_key,
    attrs,
    ctx.attr_count
  );

  // Clean up temporary arrays (strings are safe to release now that context is created)
  ruby_xfree(attrs);
  ruby_xfree(key_refs);
  ruby_xfree(string_value_refs);

  // Ensure GC safety for all referenced strings during the FFI call
  RB_GC_GUARD(hash);
  RB_GC_GUARD(ctx.targeting_key_value);

  return context;
}

// ResolutionDetails TypedData definition
static const rb_data_type_t resolution_details_typed_data = {
  .wrap_struct_name = "Datadog::Core::FeatureFlags::ResolutionDetails",
  .function = {
    .dmark = NULL,
    .dfree = resolution_details_free,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static void resolution_details_free(void *ptr) {
  ddog_ffe_Handle_ResolutionDetails resolution_details = (ddog_ffe_Handle_ResolutionDetails)ptr;
  if (resolution_details) {
    ddog_ffe_assignment_drop(&resolution_details);
  }
}


static VALUE configuration_get_assignment(VALUE self, VALUE flag_key, VALUE context_hash) {
  ENFORCE_TYPED_DATA(self, &configuration_data_type);
  ENFORCE_TYPE(flag_key, T_STRING);
  ENFORCE_TYPE(context_hash, T_HASH);

  const ddog_ffe_Handle_Configuration config =
      (ddog_ffe_Handle_Configuration)rb_check_typeddata(
          self, &configuration_data_type);

  const ddog_ffe_Handle_EvaluationContext context = evaluation_context_new(context_hash);

  ddog_ffe_Handle_ResolutionDetails resolution_details = ddog_ffe_get_assignment(
    config,
    RSTRING_PTR(flag_key),
    DDOG_FFE_EXPECTED_FLAG_TYPE_STRING,  // Default to string type
    context
  );

  // Create a new ResolutionDetails Ruby object and wrap the result
  VALUE Datadog = rb_const_get(rb_cObject, rb_intern("Datadog"));
  VALUE Core = rb_const_get(Datadog, rb_intern("Core"));
  VALUE FeatureFlags = rb_const_get(Core, rb_intern("FeatureFlags"));
  VALUE ResolutionDetails = rb_const_get(FeatureFlags, rb_intern("ResolutionDetails"));

  return TypedData_Wrap_Struct(ResolutionDetails, &resolution_details_typed_data, resolution_details);
}

// Accessor methods for ResolutionDetails
static VALUE resolution_details_get_value(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails resolution_details = (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);

  if (!resolution_details) {
    return Qnil;
  }

  struct ddog_ffe_VariantValue value = ddog_ffe_assignment_get_value(resolution_details);

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
  ddog_ffe_Handle_ResolutionDetails resolution_details = (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);

  if (!resolution_details) {
    return Qnil;
  }

  // Use the new FFI function to get the reason
  enum ddog_ffe_Reason reason = ddog_ffe_assignment_get_reason(resolution_details);

  switch (reason) {
    case DDOG_FFE_REASON_STATIC:
      return rb_str_new_cstr("STATIC");
    case DDOG_FFE_REASON_DEFAULT:
      return rb_str_new_cstr("DEFAULT");
    case DDOG_FFE_REASON_TARGETING_MATCH:
      return rb_str_new_cstr("TARGETING_MATCH");
    case DDOG_FFE_REASON_SPLIT:
      return rb_str_new_cstr("SPLIT");
    case DDOG_FFE_REASON_DISABLED:
      return rb_str_new_cstr("DISABLED");
    case DDOG_FFE_REASON_ERROR:
      return rb_str_new_cstr("ERROR");
    default:
      return Qnil;
  }
}

static VALUE resolution_details_get_error_code(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails resolution_details = (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);

  if (!resolution_details) {
    return Qnil;
  }

  // Use the new FFI function to get the error code
  enum ddog_ffe_ErrorCode error_code = ddog_ffe_assignment_get_error_code(resolution_details);

  switch (error_code) {
    case DDOG_FFE_ERROR_CODE_OK:
      return Qnil;
    case DDOG_FFE_ERROR_CODE_TYPE_MISMATCH:
      return rb_str_new_cstr("TYPE_MISMATCH");
    case DDOG_FFE_ERROR_CODE_PARSE_ERROR:
      return rb_str_new_cstr("PARSE_ERROR");
    case DDOG_FFE_ERROR_CODE_FLAG_NOT_FOUND:
      return rb_str_new_cstr("FLAG_NOT_FOUND");
    case DDOG_FFE_ERROR_CODE_TARGETING_KEY_MISSING:
      return rb_str_new_cstr("TARGETING_KEY_MISSING");
    case DDOG_FFE_ERROR_CODE_INVALID_CONTEXT:
      return rb_str_new_cstr("INVALID_CONTEXT");
    case DDOG_FFE_ERROR_CODE_PROVIDER_NOT_READY:
      return rb_str_new_cstr("PROVIDER_NOT_READY");
    case DDOG_FFE_ERROR_CODE_GENERAL:
    default:
      return rb_str_new_cstr("GENERAL");
  }
}

static VALUE resolution_details_get_error_message(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails resolution_details = (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);

  if (!resolution_details) {
    return Qnil;
  }

  // Use the new FFI function to get the error message
  struct ddog_ffe_BorrowedStr error_message = ddog_ffe_assignment_get_error_message(resolution_details);

  if (error_message.ptr == NULL || error_message.len == 0) {
    return Qnil;
  }

  return rb_str_new((const char*)error_message.ptr, error_message.len);
}

static VALUE resolution_details_is_error(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails resolution_details = (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);

  if (!resolution_details) {
    return Qfalse;
  }

  // Use the existing FFI function to get the error code
  enum ddog_ffe_ErrorCode error_code = ddog_ffe_assignment_get_error_code(resolution_details);

  // Return true if there's an error (any error code other than OK)
  return (error_code != DDOG_FFE_ERROR_CODE_OK) ? Qtrue : Qfalse;
}

static VALUE resolution_details_get_variant(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails resolution_details = (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);

  if (!resolution_details) {
    return Qnil;
  }

  // Use the new FFI function to get the variant
  struct ddog_ffe_BorrowedStr variant = ddog_ffe_assignment_get_variant(resolution_details);

  if (variant.ptr == NULL || variant.len == 0) {
    return Qnil;
  }

  return rb_str_new((const char*)variant.ptr, variant.len);
}

static VALUE resolution_details_get_allocation_key(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails resolution_details = (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);

  if (!resolution_details) {
    return Qnil;
  }

  // Use the new FFI function to get the allocation key
  struct ddog_ffe_BorrowedStr allocation_key = ddog_ffe_assignment_get_allocation_key(resolution_details);

  if (allocation_key.ptr == NULL || allocation_key.len == 0) {
    return Qnil;
  }

  return rb_str_new((const char*)allocation_key.ptr, allocation_key.len);
}

static VALUE resolution_details_get_do_log(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails resolution_details = (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);

  if (!resolution_details) {
    return Qfalse;
  }

  // Use the new FFI function to get the do_log flag
  return ddog_ffe_assignment_get_do_log(resolution_details) ? Qtrue : Qfalse;
}

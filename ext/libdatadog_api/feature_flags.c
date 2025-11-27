#include "feature_flags.h"

#include <stdio.h>
#include <datadog/ffe.h>
#include <datadog/common.h>

#include "datadog_ruby_common.h"

#include <stdint.h>
#include <string.h>
#include <stdlib.h>

// Forward declarations
static VALUE configuration_new(VALUE klass, VALUE json_str);
static void configuration_free(void *ptr);
static VALUE configuration_get_assignment(
  VALUE self, VALUE flag_key, VALUE expected_type, VALUE context);

static void resolution_details_free(void *ptr);
static VALUE resolution_details_get_raw_value(VALUE self);
static VALUE resolution_details_get_flag_type(VALUE self);
static VALUE resolution_details_get_variant(VALUE self);
static VALUE resolution_details_get_allocation_key(VALUE self);
static VALUE resolution_details_get_reason(VALUE self);
static VALUE resolution_details_get_error_code(VALUE self);
static VALUE resolution_details_get_error_message(VALUE self);
static VALUE resolution_details_get_do_log(VALUE self);
static VALUE resolution_details_get_flag_metadata(VALUE self);

static const rb_data_type_t configuration_data_type = {
  .wrap_struct_name = "Datadog::Core::FeatureFlags::Configuration",
  .function = {
    .dmark = NULL,
    .dfree = configuration_free,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static const rb_data_type_t resolution_details_typed_data = {
  .wrap_struct_name = "Datadog::Core::FeatureFlags::ResolutionDetails",
  .function = {
    .dmark = NULL,
    .dfree = resolution_details_free,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

// Cached values to use in function later in the code.
static VALUE feature_flags_error_class = Qnil;
static VALUE resolution_details_class = Qnil;
static ID id_boolean;
static ID id_string;
static ID id_number;
static ID id_object;
static ID id_any;
static ID id_integer;
static ID id_float;

// SAFETY: The returned borrowed string points directly to Ruby's
// internal string buffer.
//
// This is safe as long as the GVL is held preventing garbage
// collection. It is held automatically when C extension is called.
// Note that calling into any Ruby code (rb_funcall, or even
// rb_hash_lookup) may release GVL or run GC, so are unsafe.
static inline ddog_ffe_BorrowedStr borrow_str(VALUE str) {
  ENFORCE_TYPE(str, T_STRING);
  return (ddog_ffe_BorrowedStr){
    .ptr = (const uint8_t*)RSTRING_PTR(str),
    .len = RSTRING_LEN(str)
  };
}

// Create a new Ruby string from borrowed string. Returns nil if the
// borrowed string pointer is NULL.
static inline VALUE str_from_borrow(ddog_ffe_BorrowedStr str) {
  if (str.ptr == NULL) {
    return Qnil;
  }

  return rb_str_new((const char *)str.ptr, str.len);
}

void feature_flags_init(VALUE core_module) {
  VALUE feature_flags_module = rb_define_module_under(core_module, "FeatureFlags");

  rb_gc_register_address(&feature_flags_error_class);
  feature_flags_error_class = rb_define_class_under(feature_flags_module, "Error", rb_eStandardError);

  VALUE configuration_class = rb_define_class_under(feature_flags_module, "Configuration", rb_cObject);
  rb_undef_alloc_func(configuration_class);
  rb_define_singleton_method(configuration_class, "new", configuration_new, 1);
  rb_define_method(configuration_class, "get_assignment", configuration_get_assignment, 3);

  rb_gc_register_address(&resolution_details_class);
  resolution_details_class = rb_define_class_under(feature_flags_module, "ResolutionDetails", rb_cObject);
  rb_undef_alloc_func(resolution_details_class);
  rb_define_method(resolution_details_class, "raw_value", resolution_details_get_raw_value, 0);
  rb_define_method(resolution_details_class, "flag_type", resolution_details_get_flag_type, 0);
  rb_define_method(resolution_details_class, "variant", resolution_details_get_variant, 0);
  rb_define_method(resolution_details_class, "allocation_key", resolution_details_get_allocation_key, 0);
  rb_define_method(resolution_details_class, "reason", resolution_details_get_reason, 0);
  rb_define_method(resolution_details_class, "error_code", resolution_details_get_error_code, 0);
  rb_define_method(resolution_details_class, "error_message", resolution_details_get_error_message, 0);
  rb_define_method(resolution_details_class, "log?", resolution_details_get_do_log, 0);
  rb_define_method(resolution_details_class, "flag_metadata", resolution_details_get_flag_metadata, 0);

  // Cache symbol IDs for expected types
  id_boolean = rb_intern_const("boolean");
  id_string = rb_intern_const("string");
  id_number = rb_intern_const("number");
  id_object = rb_intern_const("object");
  id_any = rb_intern_const("any");
  id_integer = rb_intern_const("integer");
  id_float = rb_intern_const("float");
}

/*
 * call-seq:
 *   Configuration.new(json_str) -> Configuration
 *
 * Creates a new Configuration from a JSON string.
 *
 * @param json_str [String] The JSON configuration string
 * @return [Configuration] The configuration instance
 * @raise [Datadog::Core::FeatureFlags::Error] If the JSON is invalid
 */
static VALUE configuration_new(VALUE klass, VALUE json_str) {
  struct ddog_ffe_Result_HandleConfiguration result = ddog_ffe_configuration_new(borrow_str(json_str));
  if (result.tag == DDOG_FFE_RESULT_HANDLE_CONFIGURATION_ERR_HANDLE_CONFIGURATION) {
    rb_raise(feature_flags_error_class, "Failed to create configuration from JSON: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }
  return TypedData_Wrap_Struct(klass, &configuration_data_type, result.ok);
}

static void configuration_free(void *ptr) {
  ddog_ffe_Handle_Configuration config = (ddog_ffe_Handle_Configuration)ptr;
  ddog_ffe_configuration_drop(&config);
}

static ddog_ffe_ExpectedFlagType expected_type_from_value(VALUE expected_type) {
  ENFORCE_TYPE(expected_type, T_SYMBOL);

  const ID id = rb_sym2id(expected_type);
  if (id == id_boolean) {
    return DDOG_FFE_EXPECTED_FLAG_TYPE_BOOLEAN;
  } else if (id == id_string) {
    return DDOG_FFE_EXPECTED_FLAG_TYPE_STRING;
  } else if (id == id_number) {
    return DDOG_FFE_EXPECTED_FLAG_TYPE_NUMBER;
  } else if (id == id_object) {
    return DDOG_FFE_EXPECTED_FLAG_TYPE_OBJECT;
  } else if (id == id_any) {
    return DDOG_FFE_EXPECTED_FLAG_TYPE_ANY;
  } else if (id == id_integer) {
    return DDOG_FFE_EXPECTED_FLAG_TYPE_INTEGER;
  } else if (id == id_float) {
    return DDOG_FFE_EXPECTED_FLAG_TYPE_FLOAT;
  } else {
    rb_raise(feature_flags_error_class, "Internal: Unexpected flag type: %"PRIsVALUE, expected_type);
  }
}

// Structure to hold state during hash iteration for building evaluation context
struct evaluation_context_builder {
  VALUE hash;
  const char *targeting_key;
  ddog_ffe_AttributePair *attrs;
  long attr_count;
  long attr_capacity;
};

// Callback function for rb_hash_foreach to process each key-value pair
static int evaluation_context_foreach_callback(VALUE key, VALUE value, VALUE arg) {
  struct evaluation_context_builder *builder = (struct evaluation_context_builder *)arg;

  ENFORCE_TYPE(key, T_STRING);
  const char *name = RSTRING_PTR(key);

  // Extract targeting_key separately if present.
  //
  // If targeting_key has wrong type, we will skip it and attempt
  // evaluation without it. If targeting_key turns out to be required,
  // the error will be reported by
  // ddog_ffe_configuration_get_assignment function.
  if (strcmp(name, "targeting_key") == 0 && TYPE(value) == T_STRING) {
    builder->targeting_key = RSTRING_PTR(value);
    return ST_CONTINUE;
  }

  // Skip nil values
  if (value == Qnil) {
    return ST_CONTINUE;
  }

  // Ensure we don't exceed capacity.
  if (builder->attr_count >= builder->attr_capacity) {
    // This should never happen because evaluation_context_from_hash()
    // pre-allocates attr_capacity equal to iterated Hash size.
    rb_raise(feature_flags_error_class, "Internal: Attribute count exceeded capacity");
  }

  ddog_ffe_AttributePair *attr = &builder->attrs[builder->attr_count];

  switch (TYPE(value)) {
    case T_STRING:
      attr->name = name;
      attr->value.tag = DDOG_FFE_ATTRIBUTE_VALUE_STRING;
      attr->value.string = RSTRING_PTR(value);
      break;
    case T_FIXNUM:
    case T_FLOAT:
      attr->name = name;
      attr->value.tag = DDOG_FFE_ATTRIBUTE_VALUE_NUMBER;
      attr->value.number = NUM2DBL(value);
      break;
    case T_TRUE:
      attr->name = name;
      attr->value.tag = DDOG_FFE_ATTRIBUTE_VALUE_BOOLEAN;
      attr->value.boolean = true;
      break;
    case T_FALSE:
      attr->name = name;
      attr->value.tag = DDOG_FFE_ATTRIBUTE_VALUE_BOOLEAN;
      attr->value.boolean = false;
      break;
    default:
      // Skip unsupported attribute types.
      return ST_CONTINUE;
  }

  builder->attr_count += 1;
  return ST_CONTINUE;
}


static VALUE protected_context_build(VALUE p) {
  struct evaluation_context_builder *builder = (struct evaluation_context_builder *)p;

  rb_hash_foreach(builder->hash, evaluation_context_foreach_callback, p);

  return Qnil;
}

// The hash should contain attributes for feature flag evaluation. The
// special key "targeting_key" (if present) is extracted separately as
// it has special meaning in the libdatadog API. All other key-value
// pairs become attributes.
//
// Note: all strings are copied into the new EvaluationContext, so
// there are no safety concerns regarding string lifetimes. However,
// the caller is responsible for the returned EvaluationContext and
// must free it when no longer in use.
static ddog_ffe_Handle_EvaluationContext evaluation_context_from_hash(VALUE hash) {
  ENFORCE_TYPE(hash, T_HASH);

  // Initialize builder with pre-allocated attribute array
  struct evaluation_context_builder builder = {
    .hash = hash,
    .targeting_key = NULL,
    .attrs = ruby_xcalloc(RHASH_SIZE(hash), sizeof(ddog_ffe_AttributePair)),
    .attr_count = 0,
    .attr_capacity = RHASH_SIZE(hash)
  };

  int state = 0;
  rb_protect(protected_context_build, (VALUE)&builder, &state);

  // If an exception occurred, clean up and re-raise
  if (state != 0) {
    ruby_xfree(builder.attrs);
    rb_jump_tag(state);
  }

  ddog_ffe_Handle_EvaluationContext context = ddog_ffe_evaluation_context_new(
    builder.targeting_key,
    builder.attrs,
    builder.attr_count
  );

  ruby_xfree(builder.attrs);

  return context;
}

/*
 * call-seq:
 *   configuration.get_assignment(flag_key, expected_type, context) -> ResolutionDetails
 *
 * Get assignment for a feature flag.
 *
 * @param flag_key [String] The key of the feature flag
 * @param expected_type [Symbol] Expected type (:boolean, :string, :number, :object, :any, :integer, :float)
 * @param context [Hash] Evaluation context with targeting_key and other attributes
 * @return [ResolutionDetails] The resolution details
 */
static VALUE configuration_get_assignment(VALUE self, VALUE flag_key, VALUE expected_type, VALUE context_hash) {
  ENFORCE_TYPED_DATA(self, &configuration_data_type);
  ENFORCE_TYPE(flag_key, T_STRING);
  ENFORCE_TYPE(expected_type, T_SYMBOL);
  ENFORCE_TYPE(context_hash, T_HASH);

  const ddog_ffe_Handle_Configuration config =
    (ddog_ffe_Handle_Configuration)rb_check_typeddata(self, &configuration_data_type);
  const ddog_ffe_ExpectedFlagType expected_ty = expected_type_from_value(expected_type);
  ddog_ffe_Handle_EvaluationContext context = evaluation_context_from_hash(context_hash);

  ddog_ffe_Handle_ResolutionDetails resolution_details = ddog_ffe_get_assignment(
    config,
    RSTRING_PTR(flag_key),
    expected_ty,
    context
  );

  ddog_ffe_evaluation_context_drop(&context);

  return TypedData_Wrap_Struct(resolution_details_class, &resolution_details_typed_data, resolution_details);
}

static void resolution_details_free(void *ptr) {
  ddog_ffe_Handle_ResolutionDetails resolution_details = (ddog_ffe_Handle_ResolutionDetails)ptr;
  ddog_ffe_assignment_drop(&resolution_details);
}

/*
 * call-seq:
 *   resolution_details.raw_value() -> Object
 *
 * Get the raw resolved value from libdatadog.
 *
 * The value can be any type depending on the feature flag (String, Integer, Float, Boolean, or nil).
 * For object types, returns the raw JSON string without parsing.
 */
static VALUE resolution_details_get_raw_value(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails resolution_details =
    (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);

  struct ddog_ffe_VariantValue value = ddog_ffe_assignment_get_value(resolution_details);

  switch (value.tag) {
    case DDOG_FFE_VARIANT_VALUE_STRING:
      return str_from_borrow(value.string);
    case DDOG_FFE_VARIANT_VALUE_INTEGER:
      return LONG2NUM(value.integer);
    case DDOG_FFE_VARIANT_VALUE_FLOAT:
      return rb_float_new(value.float_);
    case DDOG_FFE_VARIANT_VALUE_BOOLEAN:
      return value.boolean ? Qtrue : Qfalse;
    case DDOG_FFE_VARIANT_VALUE_OBJECT:
      return str_from_borrow(value.string);
    case DDOG_FFE_VARIANT_VALUE_NONE:
      return Qnil;
    default:
      // This should never happen as we checked for all possible tag values.
      rb_raise(feature_flags_error_class, "Internal: Unexpected ResolutionDetails value tag");
  }
}

/*
 * call-seq:
 *   resolution_details.flag_type() -> Symbol or nil
 *
 * Get the type of the flag value.
 *
 * @return [Symbol, nil] One of: :string, :integer, :float, :boolean, :object, nil
 */
static VALUE resolution_details_get_flag_type(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails resolution_details =
    (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);

  struct ddog_ffe_VariantValue value = ddog_ffe_assignment_get_value(resolution_details);

  switch (value.tag) {
    case DDOG_FFE_VARIANT_VALUE_STRING:
      return ID2SYM(id_string);
    case DDOG_FFE_VARIANT_VALUE_INTEGER:
      return ID2SYM(id_integer);
    case DDOG_FFE_VARIANT_VALUE_FLOAT:
      return ID2SYM(id_float);
    case DDOG_FFE_VARIANT_VALUE_BOOLEAN:
      return ID2SYM(id_boolean);
    case DDOG_FFE_VARIANT_VALUE_OBJECT:
      return ID2SYM(id_object);
    case DDOG_FFE_VARIANT_VALUE_NONE:
      return Qnil;
    default:
      // This should never happen as we checked for all possible tag values.
      rb_raise(feature_flags_error_class, "Internal: Unexpected ResolutionDetails value tag");
  }
}

/*
 * call-seq:
 *   resolution_details.variant() -> String or nil
 *
 * Get the variant identifier.
 *
 * @return [String, nil] The variant identifier or nil
 */
static VALUE resolution_details_get_variant(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails resolution_details =
    (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);
  struct ddog_ffe_BorrowedStr variant = ddog_ffe_assignment_get_variant(resolution_details);
  return str_from_borrow(variant);
}

/*
 * call-seq:
 *   resolution_details.allocation_key() -> String or nil
 *
 * Get the allocation key.
 *
 * @return [String, nil] The allocation key or nil
 */
static VALUE resolution_details_get_allocation_key(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails resolution_details =
    (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);
  struct ddog_ffe_BorrowedStr allocation_key = ddog_ffe_assignment_get_allocation_key(resolution_details);
  return str_from_borrow(allocation_key);
}

/*
 * call-seq:
 *   resolution_details.reason() -> String
 *
 * Get the reason for the resolution.
 *
 * @return [String] One of: "STATIC", "DEFAULT", "TARGETING_MATCH", "SPLIT", "DISABLED", "ERROR", "UNKNOWN"
 */
static VALUE resolution_details_get_reason(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails resolution_details =
    (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);

  enum ddog_ffe_Reason reason = ddog_ffe_assignment_get_reason(resolution_details);

  switch (reason) {
    case DDOG_FFE_REASON_STATIC:
      return rb_str_new_lit("STATIC");
    case DDOG_FFE_REASON_DEFAULT:
      return rb_str_new_lit("DEFAULT");
    case DDOG_FFE_REASON_TARGETING_MATCH:
      return rb_str_new_lit("TARGETING_MATCH");
    case DDOG_FFE_REASON_SPLIT:
      return rb_str_new_lit("SPLIT");
    case DDOG_FFE_REASON_DISABLED:
      return rb_str_new_lit("DISABLED");
    case DDOG_FFE_REASON_ERROR:
      return rb_str_new_lit("ERROR");
    default:
      return rb_str_new_lit("UNKNOWN");
  }
}

/*
 * call-seq:
 *   resolution_details.error_code() -> String or nil
 *
 * Get the error code if there was an error.
 *
 * @return [String, nil] Error code or nil if no error
 */
static VALUE resolution_details_get_error_code(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails resolution_details =
    (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);

  enum ddog_ffe_ErrorCode error_code = ddog_ffe_assignment_get_error_code(resolution_details);

  switch (error_code) {
    case DDOG_FFE_ERROR_CODE_OK:
      return Qnil;
    case DDOG_FFE_ERROR_CODE_TYPE_MISMATCH:
      return rb_str_new_lit("TYPE_MISMATCH");
    case DDOG_FFE_ERROR_CODE_PARSE_ERROR:
      return rb_str_new_lit("PARSE_ERROR");
    case DDOG_FFE_ERROR_CODE_FLAG_NOT_FOUND:
      return rb_str_new_lit("FLAG_NOT_FOUND");
    case DDOG_FFE_ERROR_CODE_TARGETING_KEY_MISSING:
      return rb_str_new_lit("TARGETING_KEY_MISSING");
    case DDOG_FFE_ERROR_CODE_INVALID_CONTEXT:
      return rb_str_new_lit("INVALID_CONTEXT");
    case DDOG_FFE_ERROR_CODE_PROVIDER_NOT_READY:
      return rb_str_new_lit("PROVIDER_NOT_READY");
    case DDOG_FFE_ERROR_CODE_GENERAL:
    default:
      return rb_str_new_lit("GENERAL");
  }
}

/*
 * call-seq:
 *   resolution_details.error_message() -> String or nil
 *
 * Get the error message if there was an error.
 *
 * @return [String, nil] Error message or nil
 */
static VALUE resolution_details_get_error_message(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails resolution_details =
    (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);
  struct ddog_ffe_BorrowedStr error_message = ddog_ffe_assignment_get_error_message(resolution_details);
  return str_from_borrow(error_message);
}

/*
 * call-seq:
 *   resolution_details.log?() -> Boolean
 *
 * Check if this resolution should be logged.
 *
 * @return [Boolean] True if should be logged
 */
static VALUE resolution_details_get_do_log(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails resolution_details =
    (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);
  return ddog_ffe_assignment_get_do_log(resolution_details) ? Qtrue : Qfalse;
}

/*
 * call-seq:
 *   resolution_details.flag_metadata() -> Hash
 *
 * Get the flag metadata.
 *
 * @return [Hash{String => String}] The flag metadata as a hash
 */
static VALUE resolution_details_get_flag_metadata(VALUE self) {
  ddog_ffe_Handle_ResolutionDetails resolution_details =
    (ddog_ffe_Handle_ResolutionDetails)rb_check_typeddata(self, &resolution_details_typed_data);
  (void)resolution_details;

  VALUE hash = rb_hash_new();

  // TODO(FFL-1450): datadog-ffe-ffi-1.0.1 has a memory corruption bug
  // when returning flag metadata. Therefore, this section is
  // currently commented out. We'll uncommented it when the bug is
  // fixed in libdatadog.
  //
  // This is not a blocker as flag_metadata should be empty for now
  // until we decide to add more fields to it.
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

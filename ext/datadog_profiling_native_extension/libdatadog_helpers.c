#include "libdatadog_helpers.h"

#include <ruby.h>

static VALUE log_failure_to_process_tag(VALUE err_details);

const char *ruby_value_type_to_string(enum ruby_value_type type) {
  return ruby_value_type_to_char_slice(type).ptr;
}

ddog_CharSlice ruby_value_type_to_char_slice(enum ruby_value_type type) {
  switch (type) {
    case(RUBY_T_NONE    ): return DDOG_CHARSLICE_C("T_NONE");
    case(RUBY_T_OBJECT  ): return DDOG_CHARSLICE_C("T_OBJECT");
    case(RUBY_T_CLASS   ): return DDOG_CHARSLICE_C("T_CLASS");
    case(RUBY_T_MODULE  ): return DDOG_CHARSLICE_C("T_MODULE");
    case(RUBY_T_FLOAT   ): return DDOG_CHARSLICE_C("T_FLOAT");
    case(RUBY_T_STRING  ): return DDOG_CHARSLICE_C("T_STRING");
    case(RUBY_T_REGEXP  ): return DDOG_CHARSLICE_C("T_REGEXP");
    case(RUBY_T_ARRAY   ): return DDOG_CHARSLICE_C("T_ARRAY");
    case(RUBY_T_HASH    ): return DDOG_CHARSLICE_C("T_HASH");
    case(RUBY_T_STRUCT  ): return DDOG_CHARSLICE_C("T_STRUCT");
    case(RUBY_T_BIGNUM  ): return DDOG_CHARSLICE_C("T_BIGNUM");
    case(RUBY_T_FILE    ): return DDOG_CHARSLICE_C("T_FILE");
    case(RUBY_T_DATA    ): return DDOG_CHARSLICE_C("T_DATA");
    case(RUBY_T_MATCH   ): return DDOG_CHARSLICE_C("T_MATCH");
    case(RUBY_T_COMPLEX ): return DDOG_CHARSLICE_C("T_COMPLEX");
    case(RUBY_T_RATIONAL): return DDOG_CHARSLICE_C("T_RATIONAL");
    case(RUBY_T_NIL     ): return DDOG_CHARSLICE_C("T_NIL");
    case(RUBY_T_TRUE    ): return DDOG_CHARSLICE_C("T_TRUE");
    case(RUBY_T_FALSE   ): return DDOG_CHARSLICE_C("T_FALSE");
    case(RUBY_T_SYMBOL  ): return DDOG_CHARSLICE_C("T_SYMBOL");
    case(RUBY_T_FIXNUM  ): return DDOG_CHARSLICE_C("T_FIXNUM");
    case(RUBY_T_UNDEF   ): return DDOG_CHARSLICE_C("T_UNDEF");
    case(RUBY_T_IMEMO   ): return DDOG_CHARSLICE_C("T_IMEMO");
    case(RUBY_T_NODE    ): return DDOG_CHARSLICE_C("T_NODE");
    case(RUBY_T_ICLASS  ): return DDOG_CHARSLICE_C("T_ICLASS");
    case(RUBY_T_ZOMBIE  ): return DDOG_CHARSLICE_C("T_ZOMBIE");
    #ifndef NO_T_MOVED
    case(RUBY_T_MOVED   ): return DDOG_CHARSLICE_C("T_MOVED");
    #endif
                  default: return DDOG_CHARSLICE_C("BUG: Unknown value for ruby_value_type");
  }
}

size_t read_ddogerr_string_and_drop(ddog_Error *error, char *string, size_t capacity) {
  if (capacity == 0 || string == NULL) {
    // short-circuit, we can't write anything
    ddog_Error_drop(error);
    return 0;
  }

  ddog_CharSlice error_msg_slice = ddog_Error_message(error);
  size_t error_msg_size = error_msg_slice.len;
  // Account for extra null char for proper cstring
  if (error_msg_size >= capacity) {
    // Error message too big, lets truncate it to capacity - 1 to allow for extra null at end
    error_msg_size = capacity - 1;
  }
  strncpy(string, error_msg_slice.ptr, error_msg_size);
  string[error_msg_size] = '\0';
  ddog_Error_drop(error);
  return error_msg_size;
}

__attribute__((warn_unused_result))
ddog_prof_Endpoint endpoint_from(VALUE exporter_configuration) {
  ENFORCE_TYPE(exporter_configuration, T_ARRAY);

  VALUE exporter_working_mode = rb_ary_entry(exporter_configuration, 0);
  ENFORCE_TYPE(exporter_working_mode, T_SYMBOL);
  ID working_mode = SYM2ID(exporter_working_mode);

  ID agentless_id = rb_intern("agentless");
  ID agent_id = rb_intern("agent");

  if (working_mode != agentless_id && working_mode != agent_id) {
    rb_raise(rb_eArgError, "Failed to initialize transport: Unexpected working mode, expected :agentless or :agent");
  }

  if (working_mode == agentless_id) {
    VALUE site = rb_ary_entry(exporter_configuration, 1);
    VALUE api_key = rb_ary_entry(exporter_configuration, 2);
    ENFORCE_TYPE(site, T_STRING);
    ENFORCE_TYPE(api_key, T_STRING);

    return ddog_prof_Endpoint_agentless(char_slice_from_ruby_string(site), char_slice_from_ruby_string(api_key));
  } else { // agent_id
    VALUE base_url = rb_ary_entry(exporter_configuration, 1);
    ENFORCE_TYPE(base_url, T_STRING);

    return ddog_prof_Endpoint_agent(char_slice_from_ruby_string(base_url));
  }
}

__attribute__((warn_unused_result))
ddog_Vec_Tag convert_tags(VALUE tags_as_array) {
  ENFORCE_TYPE(tags_as_array, T_ARRAY);

  long tags_count = RARRAY_LEN(tags_as_array);
  ddog_Vec_Tag tags = ddog_Vec_Tag_new();

  for (long i = 0; i < tags_count; i++) {
    VALUE name_value_pair = rb_ary_entry(tags_as_array, i);

    if (!RB_TYPE_P(name_value_pair, T_ARRAY)) {
      ddog_Vec_Tag_drop(tags);
      ENFORCE_TYPE(name_value_pair, T_ARRAY);
    }

    // Note: We can index the array without checking its size first because rb_ary_entry returns Qnil if out of bounds
    VALUE tag_name = rb_ary_entry(name_value_pair, 0);
    VALUE tag_value = rb_ary_entry(name_value_pair, 1);

    if (!(RB_TYPE_P(tag_name, T_STRING) && RB_TYPE_P(tag_value, T_STRING))) {
      ddog_Vec_Tag_drop(tags);
      ENFORCE_TYPE(tag_name, T_STRING);
      ENFORCE_TYPE(tag_value, T_STRING);
    }

    ddog_Vec_Tag_PushResult push_result =
      ddog_Vec_Tag_push(&tags, char_slice_from_ruby_string(tag_name), char_slice_from_ruby_string(tag_value));

    if (push_result.tag == DDOG_VEC_TAG_PUSH_RESULT_ERR) {
      // libdatadog validates tags and may catch invalid tags that ddtrace didn't actually catch.
      // We warn users about such tags, and then just ignore them.

      int exception_state;
      rb_protect(log_failure_to_process_tag, get_error_details_and_drop(&push_result.err), &exception_state);

      // Since we are calling into Ruby code, it may raise an exception. Ensure that dynamically-allocated tags
      // get cleaned before propagating the exception.
      if (exception_state) {
        ddog_Vec_Tag_drop(tags);
        rb_jump_tag(exception_state);  // "Re-raise" exception
      }
    }
  }

  return tags;
}

static VALUE log_failure_to_process_tag(VALUE err_details) {
  VALUE datadog_module = rb_const_get(rb_cObject, rb_intern("Datadog"));
  VALUE logger = rb_funcall(datadog_module, rb_intern("logger"), 0);

  return rb_funcall(logger, rb_intern("warn"), 1, rb_sprintf("Failed to add tag to profiling request: %"PRIsVALUE, err_details));
}

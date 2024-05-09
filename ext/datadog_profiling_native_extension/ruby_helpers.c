#include <ruby.h>
#include <ruby/thread.h>

#include "ruby_helpers.h"
#include "private_vm_api_access.h"

// The following global variables are initialized at startup to save expensive lookups later.
// They are not expected to be mutated outside of init.
static VALUE module_object_space = Qnil;
static ID _id2ref_id = Qnil;
static ID inspect_id = Qnil;
static ID to_s_id = Qnil;

void ruby_helpers_init(void) {
  rb_global_variable(&module_object_space);

  module_object_space = rb_const_get(rb_cObject, rb_intern("ObjectSpace"));
  _id2ref_id = rb_intern("_id2ref");
  inspect_id = rb_intern("inspect");
  to_s_id = rb_intern("to_s");
}

void raise_unexpected_type(
  VALUE value,
  const char *value_name,
  const char *type_name,
  const char *file,
  int line,
  const char* function_name
) {
  rb_exc_raise(
    rb_exc_new_str(
      rb_eTypeError,
      rb_sprintf("wrong argument %"PRIsVALUE" for '%s' (expected a %s) at %s:%d:in `%s'",
        rb_inspect(value),
        value_name,
        type_name,
        file,
        line,
        function_name
      )
    )
  );
}

#define MAX_RAISE_MESSAGE_SIZE 256

struct raise_arguments {
  VALUE exception_class;
  char exception_message[MAX_RAISE_MESSAGE_SIZE];
};

static void *trigger_raise(void *raise_arguments) {
  struct raise_arguments *args = (struct raise_arguments *) raise_arguments;
  rb_raise(args->exception_class, "%s", args->exception_message);
}

void grab_gvl_and_raise(VALUE exception_class, const char *format_string, ...) {
  struct raise_arguments args;

  args.exception_class = exception_class;

  va_list format_string_arguments;
  va_start(format_string_arguments, format_string);
  vsnprintf(args.exception_message, MAX_RAISE_MESSAGE_SIZE, format_string, format_string_arguments);

  if (is_current_thread_holding_the_gvl()) {
    rb_raise(
      rb_eRuntimeError,
      "grab_gvl_and_raise called by thread holding the global VM lock. exception_message: '%s'",
      args.exception_message
    );
  }

  rb_thread_call_with_gvl(trigger_raise, &args);

  rb_bug("[ddtrace] Unexpected: Reached the end of grab_gvl_and_raise while raising '%s'\n", args.exception_message);
}

struct syserr_raise_arguments {
  int syserr_errno;
  char exception_message[MAX_RAISE_MESSAGE_SIZE];
};

static void *trigger_syserr_raise(void *syserr_raise_arguments) {
  struct syserr_raise_arguments *args = (struct syserr_raise_arguments *) syserr_raise_arguments;
  rb_syserr_fail(args->syserr_errno, args->exception_message);
}

void grab_gvl_and_raise_syserr(int syserr_errno, const char *format_string, ...) {
  struct syserr_raise_arguments args;

  args.syserr_errno = syserr_errno;

  va_list format_string_arguments;
  va_start(format_string_arguments, format_string);
  vsnprintf(args.exception_message, MAX_RAISE_MESSAGE_SIZE, format_string, format_string_arguments);

  if (is_current_thread_holding_the_gvl()) {
    rb_raise(
      rb_eRuntimeError,
      "grab_gvl_and_raise_syserr called by thread holding the global VM lock. syserr_errno: %d, exception_message: '%s'",
      syserr_errno,
      args.exception_message
    );
  }

  rb_thread_call_with_gvl(trigger_syserr_raise, &args);

  rb_bug("[ddtrace] Unexpected: Reached the end of grab_gvl_and_raise_syserr while raising '%s'\n", args.exception_message);
}

void raise_syserr(
  int syserr_errno,
  bool have_gvl,
  const char *expression,
  const char *file,
  int line,
  const char *function_name
) {
  if (have_gvl) {
    rb_exc_raise(rb_syserr_new_str(syserr_errno, rb_sprintf("Failure returned by '%s' at %s:%d:in `%s'", expression, file, line, function_name)));
  } else {
    grab_gvl_and_raise_syserr(syserr_errno, "Failure returned by '%s' at %s:%d:in `%s'", expression, file, line, function_name);
  }
}

char* ruby_strndup(const char *str, size_t size) {
  char *dup;

  dup = xmalloc(size + 1);
  memcpy(dup, str, size);
  dup[size] = '\0';

  return dup;
}

static VALUE _id2ref(VALUE obj_id) {
  // Call ::ObjectSpace._id2ref natively. It will raise if the id is no longer valid
  return rb_funcall(module_object_space, _id2ref_id, 1, obj_id);
}

static VALUE _id2ref_failure(DDTRACE_UNUSED VALUE _unused1, DDTRACE_UNUSED VALUE _unused2) {
  return Qfalse;
}

// Native wrapper to get an object ref from an id. Returns true on success and
// writes the ref to the value pointer parameter if !NULL. False if id doesn't
// reference a valid object (in which case value is not changed).
bool ruby_ref_from_id(VALUE obj_id, VALUE *value) {
  // Call ::ObjectSpace._id2ref natively. It will raise if the id is no longer valid
  // so we need to call it via rb_rescue2
  // TODO: Benchmark rb_rescue2 vs rb_protect here
  VALUE result = rb_rescue2(
    _id2ref,
    obj_id,
    _id2ref_failure,
    Qnil,
    rb_eRangeError, // rb_eRangeError is the error used to flag invalid ids
    0 // Required by API to be the last argument
  );

  if (result == Qfalse) {
    return false;
  }

  if (value != NULL) {
    (*value) = result;
  }

  return true;
}

// Not part of public headers but is externed from Ruby
size_t rb_obj_memsize_of(VALUE obj);

// Wrapper around rb_obj_memsize_of to avoid hitting crashing paths.
//
// The crashing paths are due to calls to rb_bug so should hopefully
// be situations that can't happen. But given that rb_obj_memsize_of
// isn't fully public (it's externed but not part of public headers)
// there is a possibility that it is just assumed that whoever calls
// it, will do proper checking for those cases. We want to be cautious
// so we'll assume that's the case and will skip over known crashing
// paths in this wrapper.
size_t ruby_obj_memsize_of(VALUE obj) {
  switch (rb_type(obj)) {
    case T_OBJECT:
    case T_MODULE:
    case T_CLASS:
    case T_ICLASS:
    case T_STRING:
    case T_ARRAY:
    case T_HASH:
    case T_REGEXP:
    case T_DATA:
    case T_MATCH:
    case T_FILE:
    case T_RATIONAL:
    case T_COMPLEX:
    case T_IMEMO:
    case T_FLOAT:
    case T_SYMBOL:
    case T_BIGNUM:
    // case T_NODE: -> Crashes the vm in rb_obj_memsize_of
    case T_STRUCT:
    case T_ZOMBIE:
    #ifndef NO_T_MOVED
    case T_MOVED:
    #endif
      return rb_obj_memsize_of(obj);
    default:
      // Unsupported, return 0 instead of erroring like rb_obj_memsize_of likes doing
      return 0;
  }
}

// Inspired by rb_class_of but without actually returning classes or potentially doing assertions
static bool ruby_is_obj_with_class(VALUE obj) {
  if (!RB_SPECIAL_CONST_P(obj)) {
    return true;
  }
  if (obj == RUBY_Qfalse) {
    return true;
  }
  else if (obj == RUBY_Qnil) {
    return true;
  }
  else if (obj == RUBY_Qtrue) {
    return true;
  }
  else if (RB_FIXNUM_P(obj)) {
    return true;
  }
  else if (RB_STATIC_SYM_P(obj)) {
    return true;
  }
  else if (RB_FLONUM_P(obj)) {
    return true;
  }

  return false;
}

VALUE ruby_safe_inspect(VALUE obj) {
  if (!ruby_is_obj_with_class(obj)) {
    return rb_str_new_cstr("(Not an object)");
  }

  if (rb_respond_to(obj, inspect_id)) {
    return rb_sprintf("%+"PRIsVALUE, obj);
  } else if (rb_respond_to(obj, to_s_id)) {
    return rb_sprintf("%"PRIsVALUE, obj);
  } else {
    return rb_str_new_cstr("(Not inspectable)");
  }
}

VALUE ddtrace_version(void) {
  VALUE ddtrace_module = rb_const_get(rb_cObject, rb_intern("Datadog"));
  ENFORCE_TYPE(ddtrace_module, T_MODULE);
  VALUE version_module = rb_const_get(ddtrace_module, rb_intern("VERSION"));
  ENFORCE_TYPE(version_module, T_MODULE);
  VALUE version_string = rb_const_get(version_module, rb_intern("STRING"));
  ENFORCE_TYPE(version_string, T_STRING);
  return version_string;
}

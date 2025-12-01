#include <ruby.h>
#include <ruby/thread.h>

#include "ruby_helpers.h"
#include "private_vm_api_access.h"
#include "extconf.h"

// The following global variables are initialized at startup to save expensive lookups later.
// They are not expected to be mutated outside of init.
static VALUE module_object_space = Qnil;
static ID _id2ref_id = Qnil;
static ID inspect_id = Qnil;
static ID to_s_id = Qnil;

static ID telemetry_message_id = Qnil;

void ruby_helpers_init(void) {
  VALUE datadog_module = rb_const_get(rb_cObject, rb_intern("Datadog"));
  datadog_ruby_common_init(datadog_module);

  rb_global_variable(&module_object_space);

  module_object_space = rb_const_get(rb_cObject, rb_intern("ObjectSpace"));
  _id2ref_id = rb_intern("_id2ref");
  inspect_id = rb_intern("inspect");
  to_s_id = rb_intern("to_s");

  telemetry_message_id = rb_intern("@telemetry_message");
}

#define MAX_RAISE_MESSAGE_SIZE 256

#define FORMAT_VA_ERROR_MESSAGE(buf, fmt) \
  char buf[MAX_RAISE_MESSAGE_SIZE]; \
  va_list buf##_args; \
  va_start(buf##_args, fmt); \
  vsnprintf(buf, MAX_RAISE_MESSAGE_SIZE, fmt, buf##_args); \
  va_end(buf##_args);

// Raises a NativeError exception with seperate telemetry-safe and detailed messages.
// Make sure to *not* invoke Ruby code as this function can run in unsafe contexts.
// @see debug_enter_unsafe_context
void private_raise_native_error(VALUE native_exception_class, const char *detailed_message, const char *static_message) {
  if (native_exception_class != eNativeRuntimeError &&
      native_exception_class != eNativeArgumentError &&
      native_exception_class != eNativeTypeError) {

      const char* fmt = "private_raise_native_error called with an exception that might not support two error messages. " \
        "Expected eNativeRuntimeError, eNativeArgumentError, or eNativeTypeError, was: %s";
      VALUE exception = rb_exc_new_str(
        eNativeArgumentError,
        rb_sprintf(fmt, rb_class2name(native_exception_class) ?: "(Unknown)")
      );
      rb_ivar_set(exception, telemetry_message_id, rb_str_new_cstr(fmt));
      rb_exc_raise(exception);
  }

  VALUE exception = rb_exc_new_cstr(native_exception_class, detailed_message);
  rb_ivar_set(exception, telemetry_message_id, rb_str_new_cstr(static_message));
  rb_exc_raise(exception);
}

// Use `raise_error` the macro instead, as it provides additional argument checks.
void private_raise_error(VALUE native_exception_class, const char *fmt, ...) {
  FORMAT_VA_ERROR_MESSAGE(formatted_msg, fmt);
  private_raise_native_error(native_exception_class, formatted_msg, fmt);
}

// Raises a SysErr exception with seperate telemetry-safe and detailed messages.
// The telemetry-safe message is set in the instance variable `@telemetry_message`.
//
// Make sure to *not* invoke Ruby code as this function can run in unsafe contexts.
// @see debug_enter_unsafe_context
NORETURN(void private_raise_syserr(int syserr_errno, const char *detailed_message, const char *static_message));
void private_raise_syserr(int syserr_errno, const char *detailed_message, const char *static_message) {
  VALUE error = rb_syserr_new(syserr_errno, detailed_message);

  // Because there are 150+ Errno error classes,
  // we set the telemetry-safe message to an instance variable, instead
  // of creating/modifying a large amount of exception classes.
  rb_ivar_set(error, telemetry_message_id, rb_str_new_cstr(static_message));

  rb_exc_raise(error);
}

typedef struct {
  VALUE exception_class;
  int syserr_errno;
  char exception_message[MAX_RAISE_MESSAGE_SIZE];
  char telemetry_message[MAX_RAISE_MESSAGE_SIZE];
} raise_args;

static void *trigger_raise(void *raise_arguments) {
  raise_args *args = (raise_args *) raise_arguments;

  if (args->syserr_errno) {
    private_raise_syserr(
      args->syserr_errno,
      args->exception_message,
      args->telemetry_message
    );
  } else {
    private_raise_native_error(
      args->exception_class,
      args->exception_message,
      args->telemetry_message
    );
  }

  return NULL;
}

// The message must be statically bound and checked.
void raise_telemetry_safe_error(VALUE native_exception_class, const char *telemetry_safe_format, ...) {
  FORMAT_VA_ERROR_MESSAGE(telemetry_safe_message, telemetry_safe_format);
  private_raise_native_error(native_exception_class, telemetry_safe_message, telemetry_safe_message);
}

// The message must be statically bound and checked.
void raise_telemetry_safe_syserr(int syserr_errno, const char *telemetry_safe_format, ...) {
  FORMAT_VA_ERROR_MESSAGE(telemetry_safe_message, telemetry_safe_format);

  private_raise_syserr(syserr_errno, telemetry_safe_message, telemetry_safe_message);
}

void private_grab_gvl_and_raise(VALUE native_exception_class, int syserr_errno, const char *format_string, ...) {
  raise_args args;
  char short_error_type[MAX_RAISE_MESSAGE_SIZE];

  if (syserr_errno != 0) {
    args.exception_class = Qnil;
    args.syserr_errno = syserr_errno;

    snprintf(short_error_type, MAX_RAISE_MESSAGE_SIZE, "Errno %d", syserr_errno);
  } else {
    args.exception_class = native_exception_class;
    args.syserr_errno = 0;

    snprintf(short_error_type, MAX_RAISE_MESSAGE_SIZE, "%s", rb_class2name(native_exception_class) ?: "(Unknown)");
  }

  FORMAT_VA_ERROR_MESSAGE(formatted_exception_message, format_string);
  snprintf(args.exception_message, MAX_RAISE_MESSAGE_SIZE, "%s", formatted_exception_message);
  snprintf(args.telemetry_message, MAX_RAISE_MESSAGE_SIZE, "%s", format_string);

  if (is_current_thread_holding_the_gvl()) {
    // Render telemetry message without formatted arguments, only the exception class.
    char telemetry_message[MAX_RAISE_MESSAGE_SIZE];
    snprintf(
      telemetry_message,
      MAX_RAISE_MESSAGE_SIZE,
      "grab_gvl_and_raise called by thread holding the global VM lock: %s (%s)",
      format_string,
      short_error_type
    );
    // Render the full exception message.
    char exception_message[MAX_RAISE_MESSAGE_SIZE];
    snprintf(
      exception_message,
      MAX_RAISE_MESSAGE_SIZE,
      "grab_gvl_and_raise called by thread holding the global VM lock: %s (%s)",
      args.exception_message,
      short_error_type
    );
    private_raise_native_error(eNativeRuntimeError, exception_message, telemetry_message);
  }

  rb_thread_call_with_gvl(trigger_raise, &args);

  rb_bug("[ddtrace] Unexpected: Reached the end of grab_gvl_and_raise while raising '%s'\n", args.exception_message);
}

typedef struct {
  int syserr_errno;
  char exception_message[MAX_RAISE_MESSAGE_SIZE];
  char telemetry_message[MAX_RAISE_MESSAGE_SIZE];
} syserr_raise_args;

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
    private_grab_gvl_and_raise(Qnil, syserr_errno, "Failure returned by '%s' at %s:%d:in `%s'", expression, file, line, function_name);
  }
}

static VALUE _id2ref(VALUE obj_id) {
  // Call ::ObjectSpace._id2ref natively. It will raise if the id is no longer valid
  return rb_funcall(module_object_space, _id2ref_id, 1, obj_id);
}

static VALUE _id2ref_failure(DDTRACE_UNUSED VALUE _unused1, DDTRACE_UNUSED VALUE _unused2) {
  return Qfalse;
}

// See notes on header for important details
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

// This function is not present in the VM headers, but is a public symbol that can be invoked.
int rb_objspace_internal_object_p(VALUE obj);

#ifdef NO_RB_OBJ_INFO
  const char* safe_object_info(DDTRACE_UNUSED VALUE obj) { return "(No rb_obj_info for current Ruby)"; }
#else
  // This function is a public symbol, but not on all Rubies; `safe_object_info` below abstracts this, and
  // should be used instead.
  const char *rb_obj_info(VALUE obj);

  const char* safe_object_info(VALUE obj) { return rb_obj_info(obj); }
#endif

VALUE ruby_safe_inspect(VALUE obj) {
  if (!ruby_is_obj_with_class(obj))       return rb_str_new_cstr("(Not an object)");
  if (rb_objspace_internal_object_p(obj)) return rb_sprintf("(VM Internal, %s)", safe_object_info(obj));
  // @ivoanjo: I saw crashes on Ruby 3.1.4 when trying to #inspect matchdata objects. I'm not entirely sure why this
  // is needed, but since we only use this method for debug purposes I put in this alternative and decided not to
  // dig deeper.
  if (rb_type(obj) == RUBY_T_MATCH)   return rb_sprintf("(MatchData, %s)", safe_object_info(obj));
  if (rb_respond_to(obj, inspect_id)) return rb_sprintf("%+"PRIsVALUE, obj);
  if (rb_respond_to(obj, to_s_id))    return rb_sprintf("%"PRIsVALUE, obj);

  return rb_str_new_cstr("(Not inspectable)");
}

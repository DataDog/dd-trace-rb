#include <ruby.h>
#include <ruby/thread.h>

#include "ruby_helpers.h"
#include "private_vm_api_access.h"
#include "extconf.h"

// The following global variables are initialized at startup to save expensive lookups later.
// They are not expected to be mutated outside of init.
static VALUE class_weak_map = Qnil;
static ID aref_id = Qnil;
static ID aset_id = Qnil;
static ID inspect_id = Qnil;
static ID to_s_id = Qnil;

void ruby_helpers_init(void) {
  rb_global_variable(&class_weak_map);

  VALUE module_object_space = rb_const_get(rb_cObject, rb_intern("ObjectSpace"));
  class_weak_map = rb_const_get(module_object_space, rb_intern("WeakMap"));
  aref_id = rb_intern("[]");
  aset_id = rb_intern("[]=");
  inspect_id = rb_intern("inspect");
  to_s_id = rb_intern("to_s");
}

// Use `raise_syserr` the macro instead, as it provides additional argument checks.
void private_raise_syserr(int syserr_errno, const char *fmt, ...) {
  va_list args;
  va_start(args, fmt);
  VALUE detailed_message = rb_vsprintf(fmt, args);
  va_end(args);

  VALUE exception = rb_syserr_new_str(syserr_errno, detailed_message);
  private_raise_exception(exception, fmt);
}

typedef struct {
  VALUE exception_class;
  int syserr_errno;
  const char *format_string;
  va_list va_args;
} raise_args;

// Called via rb_thread_call_with_gvl from private_grab_gvl_and_raise.
// Formats the message with rb_vsprintf (which requires the GVL) and raises.
static void *trigger_raise(void *raise_arguments) {
  raise_args *args = (raise_args *) raise_arguments;

  VALUE detailed_message = rb_vsprintf(args->format_string, args->va_args);

  VALUE exception;
  if (args->syserr_errno) {
    exception = rb_syserr_new_str(args->syserr_errno, detailed_message);
  } else {
    exception = rb_exc_new_str(args->exception_class, detailed_message);
  }

  private_raise_exception(exception, args->format_string);

  return NULL;
}

void private_grab_gvl_and_raise(VALUE exception_class, int syserr_errno, const char *format_string, ...) {
  raise_args args;

  if (syserr_errno != 0) {
    args.exception_class = Qnil;
    args.syserr_errno = syserr_errno;
  } else {
    args.exception_class = exception_class;
    args.syserr_errno = 0;
  }

  args.format_string = format_string;
  va_start(args.va_args, format_string);

  if (is_current_thread_holding_the_gvl()) {
    VALUE detailed_message = rb_vsprintf(format_string, args.va_args);
    va_end(args.va_args);

    VALUE wrapped_message = rb_sprintf(
      "grab_gvl_and_raise called by thread holding the global VM lock: %"PRIsVALUE,
      detailed_message
    );
    char telemetry_message[MAX_RAISE_MESSAGE_SIZE];
    snprintf(
      telemetry_message,
      MAX_RAISE_MESSAGE_SIZE,
      "grab_gvl_and_raise called by thread holding the global VM lock: %s",
      format_string
    );
    VALUE exception = rb_exc_new_str(rb_eRuntimeError, wrapped_message);
    private_raise_exception(exception, telemetry_message);
  }

  rb_thread_call_with_gvl(trigger_raise, &args);

  va_end(args.va_args);
  rb_bug("[ddtrace] Unexpected: Reached the end of grab_gvl_and_raise while raising '%s'\n", format_string);
}

void private_raise_enforce_syserr(
  int syserr_errno,
  bool have_gvl,
  const char *expression,
  const char *file,
  int line,
  const char *function_name
) {
  const char *format = "Failure returned by '%s' at %s:%d:in `%s'";
  if (have_gvl) {
    private_raise_exception(rb_syserr_new_str(syserr_errno, rb_sprintf(format, expression, file, line, function_name)), format);
  } else {
    private_grab_gvl_and_raise(Qnil, syserr_errno, format, expression, file, line, function_name);
  }
}

// See notes on header for important details
VALUE ruby_weak_map_new(void) {
  return rb_class_new_instance(0, NULL, class_weak_map);
}

// See notes on header for important details
void ruby_weak_map_set(VALUE weak_map, VALUE key, VALUE value) {
  if (value == Qnil) {
    raise_error(rb_eRuntimeError, "Can't use nil as the value in the WeakMap, otherwise #[] can't differentiate alive vs nil value");
  }
  rb_funcall(weak_map, aset_id, 2, key, value);
}

// See notes on header for important details
VALUE ruby_weak_map_get(VALUE weak_map, VALUE key) {
  return rb_funcall(weak_map, aref_id, 1, key);
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
    // On Ruby 4.0, computing the size of a class/module/iclass seems to not be safe: `rb_obj_memsize_of` walks the
    // per-namespace class extensions (`rb_class_classext_foreach` -> `classext_memsize` -> `rb_id_table_memsize`)
    // and can crash the VM when called on objects tracked by heap profiling.
    // See https://github.com/DataDog/dd-trace-rb/issues/5936. Class objects contribute negligibly to heap size,
    // so we skip them (fall through to the `default` branch, returning 0) rather than risk a SIGSEGV.
    #ifndef NO_SAFE_CLASS_MEMSIZE
    case T_MODULE:
    case T_CLASS:
    case T_ICLASS:
    #endif
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

#ifdef NO_RB_OBJ_INFO
  const char* safe_object_info(DDTRACE_UNUSED VALUE obj) { return "(No rb_obj_info for current Ruby)"; }
#else
  // This function is a public symbol, but not on all Rubies; `safe_object_info` below abstracts this, and
  // should be used instead.
  const char *rb_obj_info(VALUE obj);

  const char* safe_object_info(VALUE obj) { return rb_obj_info(obj); }
#endif

VALUE ruby_safe_inspect(VALUE obj) {
  if (ddtrace_is_internal_object_p(obj))  return rb_sprintf("(VM Internal, %s)", safe_object_info(obj));
  // @ivoanjo: I saw crashes on Ruby 3.1.4 when trying to #inspect matchdata objects. I'm not entirely sure why this
  // is needed, but since we only use this method for debug purposes I put in this alternative and decided not to
  // dig deeper.
  if (rb_type(obj) == RUBY_T_MATCH)   return rb_sprintf("(MatchData, %s)", safe_object_info(obj));
  if (rb_respond_to(obj, inspect_id)) return rb_sprintf("%+"PRIsVALUE, obj);
  if (rb_respond_to(obj, to_s_id))    return rb_sprintf("%"PRIsVALUE, obj);

  return rb_str_new_cstr("(Not inspectable)");
}

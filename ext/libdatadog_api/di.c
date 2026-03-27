#include <stdbool.h>

#include "datadog_ruby_common.h"

// Prototypes for Ruby functions declared in internal Ruby headers.
VALUE rb_iseqw_new(const void *iseq);
int rb_objspace_internal_object_p(VALUE obj);
void rb_objspace_each_objects(
    int (*callback)(void *start, void *end, size_t stride, void *data),
    void *data);

#ifdef HAVE_RB_BACKTRACE_P
// Backtrace conversion functions from vm_backtrace.c.
// Only available on Ruby builds that export these symbols (detected
// by have_func in extconf.rb).
int rb_backtrace_p(VALUE obj);
VALUE rb_backtrace_to_str_ary(VALUE self);
#endif

#define IMEMO_TYPE_ISEQ 7

// The ID value of the string "mesg" which is used in Ruby source as
// id_mesg or idMesg, and is used to set and retrieve the exception message
// from standard library exception classes like NameError.
static ID id_mesg;

// The ID value of the string "bt" which is used in Ruby source as
// id_bt or idBt, and is used to set and retrieve the exception backtrace.
static ID id_bt;

#ifndef HAVE_RB_BACKTRACE_P
// Fallback: cached UnboundMethod for Exception#backtrace, used when
// rb_backtrace_p/rb_backtrace_to_str_ary are not exported by Ruby.
// Calls the original C implementation without dispatching through the
// method table (which would invoke customer overrides).
static VALUE exception_backtrace_unbound_method;
#endif

// Returns whether the argument is an IMEMO of type ISEQ.
static bool ddtrace_imemo_iseq_p(VALUE v) {
  return rb_objspace_internal_object_p(v) && RB_TYPE_P(v, T_IMEMO) && ddtrace_imemo_type(v) == IMEMO_TYPE_ISEQ;
}

static int ddtrace_di_os_obj_of_i(void *vstart, void *vend, size_t stride, void *data)
{
  VALUE *array = (VALUE *)data;

  VALUE v = (VALUE)vstart;
  for (; v != (VALUE)vend; v += stride) {
    if (ddtrace_imemo_iseq_p(v)) {
      VALUE iseq = rb_iseqw_new((void *) v);
      rb_ary_push(*array, iseq);
    }
  }

  return 0;
}

/*
Returns all RubyVM::InstructionSequence objects existing in the current process.

This uses the same approach as ruby/debug's iseq_collector.c:
https://github.com/ruby/debug/blob/master/ext/debug/iseq_collector.c
*/
static VALUE all_iseqs(DDTRACE_UNUSED VALUE _self) {
  VALUE array = rb_ary_new();
  rb_objspace_each_objects(ddtrace_di_os_obj_of_i, &array);
  return array;
}

/*
 * call-seq:
 *   DI.exception_message(exception) -> String | Object
 *
 * Returns the exception message associated with the exception via the
 * exception's constructor.
 *
 * This method does not invoke Ruby code and as such will not call
 * the +message+ method, if one is defined on the exception object.
 *
 * Normally, the exception message is a string, however there is no
 * type enforcement done by Ruby for the messages and objects of arbitrary
 * classes can be passed to exception constructors and will, subsequently,
 * be returned by this method.
 *
 * @param exception [Exception] The exception object
 * @return [String | Object] The exception message
 */
static VALUE exception_message(DDTRACE_UNUSED VALUE _self, VALUE exception) {
  return rb_ivar_get(exception, id_mesg);
}

/*
 * call-seq:
 *   DI.exception_backtrace(exception) -> Array | nil
 *
 * Returns the backtrace of the exception as an Array of Strings, without
 * dispatching through the exception's method table.
 *
 * This is important for DI instrumentation where we must not invoke
 * customer code. If a customer subclass overrides +Exception#backtrace+,
 * calling +exception.backtrace+ would dispatch to the override.
 *
 * Two strategies, selected at compile time by have_func:
 *
 * 1. If rb_backtrace_p is exported: read the +bt+ ivar directly and
 *    convert via rb_backtrace_to_str_ary. No Ruby method dispatch at all.
 *
 * 2. Fallback: call Exception#backtrace via an UnboundMethod captured
 *    from Exception at init time. This invokes the original C
 *    implementation (exc_backtrace in error.c) regardless of subclass
 *    overrides. Uses bind+call (not bind_call) for Ruby 2.6 compat.
 *
 * In both cases, only Ruby stdlib C code executes — never customer code.
 *
 * The +bt+ ivar after +raise+ contains a Thread::Backtrace object.
 * Ruby's exc_backtrace (error.c) converts it to Array<String> via
 * rb_backtrace_to_str_ary (vm_backtrace.c). If set via
 * +Exception#set_backtrace+, +bt+ already holds an Array<String>.
 *
 * @param exception [Exception] The exception object
 * @return [Array<String>, nil] The backtrace as an array of strings,
 *   or nil if no backtrace is set
 */
static VALUE exception_backtrace(DDTRACE_UNUSED VALUE _self, VALUE exception) {
#ifdef HAVE_RB_BACKTRACE_P
  VALUE bt = rb_ivar_get(exception, id_bt);

  // Array: set via Exception#set_backtrace, or already materialized
  // by a prior call to Exception#backtrace.
  if (RB_TYPE_P(bt, T_ARRAY)) return bt;

  // Thread::Backtrace: raw backtrace object stored by raise.
  // Convert to Array<String> via rb_backtrace_to_str_ary.
  if (rb_backtrace_p(bt)) {
    return rb_backtrace_to_str_ary(bt);
  }

  // nil: no backtrace set (Exception.new without raise).
  return Qnil;
#else
  // Fallback: call the original Exception#backtrace via UnboundMethod.
  VALUE bound = rb_funcall(exception_backtrace_unbound_method,
    rb_intern("bind"), 1, exception);
  return rb_funcall(bound, rb_intern("call"), 0);
#endif
}

void di_init(VALUE datadog_module) {
  id_mesg = rb_intern("mesg");
  id_bt = rb_intern("bt");

#ifndef HAVE_RB_BACKTRACE_P
  // Capture Exception.instance_method(:backtrace) once at init time.
  // This UnboundMethod points to the original C implementation in error.c
  // and will not be affected by subclass overrides.
  exception_backtrace_unbound_method = rb_funcall(
    rb_eException, rb_intern("instance_method"), 1,
    ID2SYM(rb_intern("backtrace")));
  rb_gc_register_mark_object(exception_backtrace_unbound_method);
#endif

  VALUE di_module = rb_define_module_under(datadog_module, "DI");
  rb_define_singleton_method(di_module, "all_iseqs", all_iseqs, 0);
  rb_define_singleton_method(di_module, "exception_message", exception_message, 1);
  rb_define_singleton_method(di_module, "exception_backtrace", exception_backtrace, 1);
}

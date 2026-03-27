#include <stdbool.h>

#include "datadog_ruby_common.h"

// Prototypes for Ruby functions declared in internal Ruby headers.
VALUE rb_iseqw_new(const void *iseq);
int rb_objspace_internal_object_p(VALUE obj);
void rb_objspace_each_objects(
    int (*callback)(void *start, void *end, size_t stride, void *data),
    void *data);

#define IMEMO_TYPE_ISEQ 7

// The ID value of the string "mesg" which is used in Ruby source as
// id_mesg or idMesg, and is used to set and retrieve the exception message
// from standard library exception classes like NameError.
static ID id_mesg;

// Cached UnboundMethod for Exception#backtrace, used to call the original
// C implementation without dispatching through the method table (which
// would invoke customer overrides). Initialized once in di_init.
static VALUE exception_backtrace_unbound_method;

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
 * invoking any Ruby-level method on the exception object itself.
 *
 * This is important for DI instrumentation where we must not invoke
 * customer code. If a customer subclass overrides +Exception#backtrace+,
 * calling +exception.backtrace+ would dispatch to the override. This
 * method bypasses that by calling the original +Exception#backtrace+
 * implementation directly via an UnboundMethod captured at init time.
 *
 * Implementation: at init time, we capture
 * +Exception.instance_method(:backtrace)+ as an UnboundMethod. At call
 * time, we bind it to the exception and call it. This invokes the
 * original C implementation of +Exception#backtrace+ (defined in
 * Ruby's error.c), which handles all Ruby version differences in
 * internal backtrace storage:
 *
 * - Ruby 2.6–3.1: +bt+ ivar holds a Thread::Backtrace object after
 *   +raise+. +Exception#backtrace+ converts it to Array<String>.
 *
 * - Ruby 3.2+: +bt+ is nil after +raise+; actual backtrace is in
 *   +bt_locations+. +Exception#backtrace+ reads and converts it.
 *
 * - All versions: +Exception#set_backtrace+ stores Array<String>
 *   directly in +bt+.
 *
 * Using bind+call on the UnboundMethod is safe: it only invokes Ruby
 * stdlib code (the original Exception#backtrace C function), not
 * customer code. The UnboundMethod is captured once from Exception
 * itself, so even if a subclass overrides backtrace, bind_call still
 * dispatches to the original.
 *
 * @param exception [Exception] The exception object
 * @return [Array<String>, nil] The backtrace as an array of strings,
 *   or nil if no backtrace is set
 */
static VALUE exception_backtrace(DDTRACE_UNUSED VALUE _self, VALUE exception) {
  // Use bind + call (not bind_call) for Ruby 2.6 compatibility.
  // bind_call was added in Ruby 2.7.
  VALUE bound = rb_funcall(exception_backtrace_unbound_method,
    rb_intern("bind"), 1, exception);
  return rb_funcall(bound, rb_intern("call"), 0);
}

void di_init(VALUE datadog_module) {
  id_mesg = rb_intern("mesg");

  // Capture Exception.instance_method(:backtrace) once at init time.
  // This UnboundMethod points to the original C implementation in error.c
  // and will not be affected by subclass overrides.
  exception_backtrace_unbound_method = rb_funcall(
    rb_eException, rb_intern("instance_method"), 1,
    ID2SYM(rb_intern("backtrace")));
  // Prevent GC from collecting the cached UnboundMethod.
  rb_gc_register_mark_object(exception_backtrace_unbound_method);

  VALUE di_module = rb_define_module_under(datadog_module, "DI");
  rb_define_singleton_method(di_module, "all_iseqs", all_iseqs, 0);
  rb_define_singleton_method(di_module, "exception_message", exception_message, 1);
  rb_define_singleton_method(di_module, "exception_backtrace", exception_backtrace, 1);
}

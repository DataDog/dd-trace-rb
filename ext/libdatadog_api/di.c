#include <stdbool.h>

#include "datadog_ruby_common.h"

// Prototypes for Ruby functions declared in internal Ruby headers.
VALUE rb_iseqw_new(const void *iseq);
int rb_objspace_internal_object_p(VALUE obj);
void rb_objspace_each_objects(
    int (*callback)(void *start, void *end, size_t stride, void *data),
    void *data);

// Backtrace conversion functions from vm_backtrace.c.
// rb_backtrace_p returns true if the value is a Thread::Backtrace object.
// rb_backtrace_to_str_ary converts a Thread::Backtrace to Array<String>.
int rb_backtrace_p(VALUE obj);
VALUE rb_backtrace_to_str_ary(VALUE self);

#define IMEMO_TYPE_ISEQ 7

// The ID value of the string "mesg" which is used in Ruby source as
// id_mesg or idMesg, and is used to set and retrieve the exception message
// from standard library exception classes like NameError.
static ID id_mesg;

// The ID value of the string "bt" which is used in Ruby source as
// id_bt or idBt, and is used to set and retrieve the exception backtrace.
static ID id_bt;

// The ID value of the string "bt_locations" which is used in Ruby source
// to store the Thread::Backtrace object for lazy backtrace evaluation.
// On newer Ruby versions, bt may be nil with the actual backtrace stored
// in bt_locations instead.
static ID id_bt_locations;

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
 * Returns the backtrace stored on the exception object as an Array of
 * Strings, without invoking any Ruby-level method on the exception.
 *
 * This reads the internal +bt+ and +bt_locations+ instance variables
 * directly, bypassing any override of +Exception#backtrace+. This is
 * important for DI instrumentation where we must not invoke customer code.
 *
 * Ruby stores the backtrace internally as a Thread::Backtrace object,
 * not as an Array of Strings. The public Exception#backtrace method
 * converts it lazily. This function performs the same conversion using
 * rb_backtrace_to_str_ary (a Ruby internal C function, not customer code).
 *
 * Ruby version differences in internal backtrace storage:
 *
 * - Ruby 2.6: When +raise+ is called, Ruby sets +bt+ to a
 *   Thread::Backtrace object. +Exception#backtrace+ converts it to
 *   Array<String> on first access and caches the result back in +bt+.
 *
 * - Ruby 3.2+: When +raise+ is called, Ruby sets +bt+ to +nil+ and
 *   stores the Thread::Backtrace in +bt_locations+ instead (lazy
 *   evaluation). +Exception#backtrace+ reads +bt_locations+, converts
 *   to Array<String>, and caches in +bt+.
 *
 * - All versions: +Exception#set_backtrace+ stores an Array<String>
 *   directly in +bt+ (no Thread::Backtrace involved).
 *
 * @param exception [Exception] The exception object
 * @return [Array<String>, nil] The backtrace as an array of strings,
 *   or nil if no backtrace is set
 */
static VALUE exception_backtrace(DDTRACE_UNUSED VALUE _self, VALUE exception) {
  VALUE bt = rb_ivar_get(exception, id_bt);

  // Array: backtrace was set via Exception#set_backtrace, or was already
  // materialized by a prior call to Exception#backtrace. All Ruby versions.
  if (RB_TYPE_P(bt, T_ARRAY)) return bt;

  // Thread::Backtrace: Ruby 2.6–3.1 store the raw backtrace object in bt
  // when raise is called, before Exception#backtrace materializes it.
  if (rb_backtrace_p(bt)) {
    return rb_backtrace_to_str_ary(bt);
  }

  // nil: On Ruby 3.2+, bt starts as nil after raise. The actual backtrace
  // is stored in bt_locations as a Thread::Backtrace (lazy evaluation).
  // Also nil when no backtrace has been set (e.g. Exception.new without raise).
  if (NIL_P(bt)) {
    VALUE bt_locations = rb_ivar_get(exception, id_bt_locations);
    if (!NIL_P(bt_locations) && rb_backtrace_p(bt_locations)) {
      return rb_backtrace_to_str_ary(bt_locations);
    }
  }

  // No backtrace set (exception created without raise and without set_backtrace).
  return Qnil;
}

void di_init(VALUE datadog_module) {
  id_mesg = rb_intern("mesg");
  id_bt = rb_intern("bt");
  id_bt_locations = rb_intern("bt_locations");

  VALUE di_module = rb_define_module_under(datadog_module, "DI");
  rb_define_singleton_method(di_module, "all_iseqs", all_iseqs, 0);
  rb_define_singleton_method(di_module, "exception_message", exception_message, 1);
  rb_define_singleton_method(di_module, "exception_backtrace", exception_backtrace, 1);
}

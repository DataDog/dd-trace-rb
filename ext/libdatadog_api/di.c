#include <stdbool.h>

#include "datadog_ruby_common.h"

// Prototypes for Ruby functions declared in internal Ruby headers.
VALUE rb_iseqw_new(const void *iseq);
const void *rb_iseqw_to_iseq(VALUE iseqw);
VALUE rb_iseq_type(const void *iseq);
int rb_objspace_internal_object_p(VALUE obj);
void rb_objspace_each_objects(
    int (*callback)(void *start, void *end, size_t stride, void *data),
    void *data);

#define IMEMO_TYPE_ISEQ 7

// The ID value of the string "mesg" which is used in Ruby source as
// id_mesg or idMesg, and is used to set and retrieve the exception message
// from standard library exception classes like NameError.
static ID id_mesg;

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
 *   DI.iseq_type(iseq) -> Symbol
 *
 * Returns the type of an InstructionSequence as a symbol.
 *
 * Possible return values: :top, :method, :block, :class, :rescue,
 * :ensure, :eval, :main, :plain.
 *
 * :top and :main represent whole-file iseqs (from require/load and the
 * entry point script respectively). Other types represent sub-file
 * constructs (method definitions, class bodies, blocks, etc.).
 *
 * @param iseq [RubyVM::InstructionSequence] The instruction sequence
 * @return [Symbol] The iseq type
 */
static VALUE iseq_type(DDTRACE_UNUSED VALUE _self, VALUE iseq_val) {
  const void *iseq = rb_iseqw_to_iseq(iseq_val);
  if (!iseq) return Qnil;
  return rb_iseq_type(iseq);
}

void di_init(VALUE datadog_module) {
  id_mesg = rb_intern("mesg");

  VALUE di_module = rb_define_module_under(datadog_module, "DI");
  rb_define_singleton_method(di_module, "all_iseqs", all_iseqs, 0);
  rb_define_singleton_method(di_module, "exception_message", exception_message, 1);
  rb_define_singleton_method(di_module, "iseq_type", iseq_type, 1);
}

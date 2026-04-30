#include <stdbool.h>

#include "datadog_ruby_common.h"

// Prototypes for Ruby functions declared in internal Ruby headers.
// rb_iseqw_new wraps an internal iseq pointer into a Ruby-visible
// RubyVM::InstructionSequence object.
VALUE rb_iseqw_new(const void *iseq);
// rb_iseqw_to_iseq unwraps a RubyVM::InstructionSequence object back
// to its internal iseq pointer.
const void *rb_iseqw_to_iseq(VALUE iseqw);
int rb_objspace_internal_object_p(VALUE obj);
void rb_objspace_each_objects(
    int (*callback)(void *start, void *end, size_t stride, void *data),
    void *data);

#define IMEMO_TYPE_ISEQ 7

// The ID value of the string "mesg" which is used in Ruby source as
// id_mesg or idMesg, and is used to set and retrieve the exception message
// from standard library exception classes like NameError.
static ID id_mesg;

// ID for the fiber-local key that backs the method-probe re-entrancy guard.
// Storage is the same hashtable that backs Thread#[] / Thread#[]=, but accessed
// directly via rb_thread_local_aref / rb_thread_local_aset so that user-installed
// method probes on Thread#[] / Thread#[]= cannot intercept guard reads/writes.
static ID id_datadog_di_in_probe;

// rb_thread_local_aref and rb_thread_local_aset are public Ruby C API functions
// that read/write the current fiber's local storage hashtable directly. They do
// NOT dispatch through Thread#[] / Thread#[]=, so a user probe on those Thread
// methods does not cause re-entrancy when these are called.
VALUE rb_thread_local_aref(VALUE thread, ID id);
VALUE rb_thread_local_aset(VALUE thread, ID id, VALUE val);

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
 *   DI.in_probe? -> true | false
 *
 * Returns whether the current fiber is currently inside DI probe processing.
 * Reads the same fiber-local storage as Thread.current[:datadog_di_in_probe]
 * but bypasses Thread#[] method dispatch — a user method probe on Thread#[]
 * cannot observe or intercept this call.
 */
static VALUE in_probe_p(DDTRACE_UNUSED VALUE _self) {
  VALUE v = rb_thread_local_aref(rb_thread_current(), id_datadog_di_in_probe);
  return RTEST(v) ? Qtrue : Qfalse;
}

/*
 * call-seq:
 *   DI.enter_probe -> nil
 *
 * Marks the current fiber as inside DI probe processing. Writes to the same
 * fiber-local storage as Thread.current[:datadog_di_in_probe] = true, but
 * bypasses Thread#[]= method dispatch — a user method probe on Thread#[]=
 * cannot observe or intercept this call.
 */
static VALUE enter_probe(DDTRACE_UNUSED VALUE _self) {
  rb_thread_local_aset(rb_thread_current(), id_datadog_di_in_probe, Qtrue);
  return Qnil;
}

/*
 * call-seq:
 *   DI.leave_probe -> nil
 *
 * Marks the current fiber as no longer inside DI probe processing. Writes to
 * the same fiber-local storage as Thread.current[:datadog_di_in_probe] = nil,
 * but bypasses Thread#[]= method dispatch — a user method probe on Thread#[]=
 * cannot observe or intercept this call.
 */
static VALUE leave_probe(DDTRACE_UNUSED VALUE _self) {
  rb_thread_local_aset(rb_thread_current(), id_datadog_di_in_probe, Qnil);
  return Qnil;
}

/*
 * call-seq:
 *   DI.array_empty?(arr) -> true | false
 *
 * Returns whether the given Array is empty by direct length access via
 * RARRAY_LEN, bypassing Array#empty? method dispatch. Used in the method
 * probe wrapper to test args/kwargs shape without giving user-installed
 * method probes on Array#empty? a chance to recurse.
 *
 * @api private
 */
static VALUE array_empty_p(DDTRACE_UNUSED VALUE _self, VALUE obj) {
  return RARRAY_LEN(obj) == 0 ? Qtrue : Qfalse;
}

/*
 * call-seq:
 *   DI.hash_empty?(h) -> true | false
 *
 * Returns whether the given Hash is empty by direct size access via
 * RHASH_SIZE, bypassing Hash#empty? method dispatch. Used in the method
 * probe wrapper to test args/kwargs shape without giving user-installed
 * method probes on Hash#empty? a chance to recurse.
 *
 * @api private
 */
static VALUE hash_empty_p(DDTRACE_UNUSED VALUE _self, VALUE obj) {
  return RHASH_SIZE(obj) == 0 ? Qtrue : Qfalse;
}

// rb_iseq_type was added in Ruby 3.1 (commit 89a02d89 by Koichi Sasada,
// 2021-12-19). It returns the iseq type as a Symbol. On Ruby < 3.1 this
// function does not exist, so have_func('rb_iseq_type') in extconf.rb
// gates compilation. When unavailable, backfill_registry falls back to
// the first_lineno == 0 heuristic.
#ifdef HAVE_RB_ISEQ_TYPE
VALUE rb_iseq_type(const void *iseq);

/*
 * call-seq:
 *   DI.iseq_type(iseq) -> Symbol
 *
 * Returns the type of an InstructionSequence as a symbol by calling
 * the internal rb_iseq_type() function (available since Ruby 3.1).
 *
 * This method is only defined when rb_iseq_type is detected at compile
 * time via have_func in extconf.rb. On Ruby < 3.1 it is not available
 * and callers must use an alternative (e.g. first_lineno heuristic).
 *
 * Possible return values: :top, :method, :block, :class, :rescue,
 * :ensure, :eval, :main, :plain.
 *
 * :top and :main represent whole-file iseqs (from require/load and the
 * entry point script respectively). Other types represent sub-file
 * constructs (method definitions, class bodies, blocks, etc.).
 *
 * Used by CodeTracker#backfill_registry to distinguish whole-file iseqs
 * from per-method/block/class iseqs when populating the registry from
 * the object space.
 *
 * @param iseq [RubyVM::InstructionSequence] The instruction sequence
 * @return [Symbol] The iseq type
 */
static VALUE iseq_type(DDTRACE_UNUSED VALUE _self, VALUE iseq_val) {
  const void *iseq = rb_iseqw_to_iseq(iseq_val);
  if (!iseq) return Qnil;
  return rb_iseq_type(iseq);
}
#endif

void di_init(VALUE datadog_module) {
  id_mesg = rb_intern("mesg");
  id_datadog_di_in_probe = rb_intern("datadog_di_in_probe");

  VALUE di_module = rb_define_module_under(datadog_module, "DI");
  rb_define_singleton_method(di_module, "all_iseqs", all_iseqs, 0);
  rb_define_singleton_method(di_module, "exception_message", exception_message, 1);
  rb_define_singleton_method(di_module, "in_probe?", in_probe_p, 0);
  rb_define_singleton_method(di_module, "enter_probe", enter_probe, 0);
  rb_define_singleton_method(di_module, "leave_probe", leave_probe, 0);
  rb_define_singleton_method(di_module, "array_empty?", array_empty_p, 1);
  rb_define_singleton_method(di_module, "hash_empty?", hash_empty_p, 1);
#ifdef HAVE_RB_ISEQ_TYPE
  rb_define_singleton_method(di_module, "iseq_type", iseq_type, 1);
#endif
}

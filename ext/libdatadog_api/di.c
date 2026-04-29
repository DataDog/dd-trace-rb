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

// rb_iseq_alloc_with_dummy_path was added in Ruby 3.2.9 (backport of #11036)
// to create profiler-safe placeholder frames during require/load. These dummy
// iseqs have iseq_size == 0 (no bytecode). Used by the test helper below.
#ifdef HAVE_RB_ISEQ_ALLOC_WITH_DUMMY_PATH
void *rb_iseq_alloc_with_dummy_path(VALUE fname);

/*
 * call-seq:
 *   DI.create_dummy_iseq(path) -> RubyVM::InstructionSequence
 *
 * Creates a dummy profiler iseq (iseq_size == 0) with the given path,
 * identical to what Ruby 3.2.9+ creates during require/load via
 * rb_iseq_alloc_with_dummy_path. The iseq is a real IMEMO object in
 * the Ruby heap — all_iseqs will find it during object space walks.
 *
 * Test-only helper for verifying that backfill_registry filters out
 * dummy iseqs. Not defined on Ruby versions without the underlying
 * function.
 *
 * @param path [String] the absolute path to assign to the dummy iseq
 * @return [RubyVM::InstructionSequence] the dummy iseq wrapper
 */
static VALUE create_dummy_iseq(DDTRACE_UNUSED VALUE _self, VALUE path) {
  void *iseq = rb_iseq_alloc_with_dummy_path(path);
  return rb_iseqw_new(iseq);
}
#endif

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

  VALUE di_module = rb_define_module_under(datadog_module, "DI");
  rb_define_singleton_method(di_module, "all_iseqs", all_iseqs, 0);
  rb_define_singleton_method(di_module, "exception_message", exception_message, 1);
#ifdef HAVE_RB_ISEQ_ALLOC_WITH_DUMMY_PATH
  rb_define_singleton_method(di_module, "create_dummy_iseq", create_dummy_iseq, 1);
#endif
#ifdef HAVE_RB_ISEQ_TYPE
  rb_define_singleton_method(di_module, "iseq_type", iseq_type, 1);
#endif
}

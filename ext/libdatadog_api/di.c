#include <ruby.h>
#include <stdbool.h>
#include "ruby_internal.h"
#include "ruby_helpers.h"

#ifndef DDTRACE_UNUSED
#define DDTRACE_UNUSED  __attribute__((unused))
#endif

struct ddtrace_di_os_each_struct {
    VALUE array;
};

static int ddtrace_di_os_obj_of_i(void *vstart, void *vend, size_t stride, void *data)
{
    struct ddtrace_di_os_each_struct *oes = (struct ddtrace_di_os_each_struct *)data;
    VALUE array = oes->array;

    VALUE v = (VALUE)vstart;
    for (; v != (VALUE)vend; v += stride) {
        if (ddtrace_imemo_iseq_p(v)) {
            VALUE iseq = rb_iseqw_new((void *) v);
            rb_ary_push(array, iseq);
        }
    }

    return 0;
}

/* 
Returns RubyVM::InstructionSequence ("iseq") objects existing in the
current process.

There are several types of iseqs:

- The ones from eval'd code. These have a nil +absolute_path+.
- The ones for a whole loaded file. These have +absolute_path+ set
and have a +first_lineno+ of 0.
- The ones for a particular method defined in a file. These have
+absolute_path+ set and +first_lineno+ of greater than 0.

The first type, eval'd iseqs, are not currently of interest to DI
because the UI only supports line probes defined on a line of 
source file and we interpret the lines as the "base layer" of source.

The second type, iseqs for a whole file, are only available for a
relatively small subset of loaded files. My theory is that after a
file is fully loaded, its complete iseq is no longer needed for
anything and is subject to garbage collection.

The full-file iseqs are easiest to deal with from the DI perspective
as we just need to match the file path to the probe specification and
we can use the full-file iseq to target any line in the file.

The third type, iseqs for a method, is the only iseqs we have available
for much of third-party code. They require DI to identify the correct
iseq object in a particular file that contains the line that the probe
is trying to instrument.

iseqs contain the first line of the code they correspond to, but no
last line or number of lines. The actual instructions are labeled
per line, therefore it is possible to figure out the range of each
iseq from the instructions. However I think this is unnecessary -
all that should be required is picking the iseq with first_lineno
smaller than, and closest to, the desired line number.
*/
static VALUE all_iseqs(DDTRACE_UNUSED VALUE _self) {
    struct ddtrace_di_os_each_struct oes;

    oes.array = rb_ary_new();
    rb_objspace_each_objects(ddtrace_di_os_obj_of_i, &oes);
    RB_GC_GUARD(oes.array);
    return oes.array;
}

void di_init(VALUE datadog_module) {
  VALUE di_module = rb_define_module_under(datadog_module, "DI");
  rb_define_singleton_method(di_module, "all_iseqs", all_iseqs, 0);
}

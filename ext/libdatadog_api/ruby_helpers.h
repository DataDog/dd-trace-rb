#include <ruby.h>

#define IMEMO_TYPE_ISEQ 7

#define IMEMO_MASK   0x0f

int ddtrace_imemo_type(VALUE imemo);

// Returns whether the argument is an IMEMO of type ISEQ.
bool ddtrace_imemo_iseq_p(VALUE v);

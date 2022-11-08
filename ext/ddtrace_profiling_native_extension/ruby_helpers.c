#include "ruby_helpers.h"

void raise_unexpected_type(
  VALUE value,
  const char *value_name,
  const char *type_name,
  const char *file,
  int line,
  const char* function_name
) {
  rb_exc_raise(
    rb_exc_new_str(
      rb_eTypeError,
      rb_sprintf("wrong argument %"PRIsVALUE" for '%s' (expected a %s) at %s:%d:in `%s'",
        rb_inspect(value),
        value_name,
        type_name,
        file,
        line,
        function_name
      )
    )
  );
}

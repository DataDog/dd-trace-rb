// Prototypes for Ruby functions that are declared in internal Ruby headers.

#include <ruby.h>

VALUE rb_iseqw_new(const void *iseq);

int rb_objspace_internal_object_p(VALUE obj);

void rb_objspace_each_objects(
    int (*callback)(void *start, void *end, size_t stride, void *data),
    void *data);

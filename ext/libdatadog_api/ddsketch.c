#include <ruby.h>
#include <datadog/ddsketch.h>

#include "datadog_ruby_common.h"
#include "helpers.h"

static VALUE _native_new(VALUE klass);
static void ddsketch_free(void *ptr);
static VALUE native_add(VALUE self, VALUE point);
static VALUE native_add_with_count(VALUE self, VALUE point, VALUE count);
static VALUE native_count(VALUE self);
static VALUE native_encode(VALUE self);

void ddsketch_init(VALUE core_module) {
  VALUE ddsketch_class = rb_define_class_under(core_module, "DDSketch", rb_cObject);

  rb_define_alloc_func(ddsketch_class, _native_new);
  rb_define_method(ddsketch_class, "add", native_add, 1);
  rb_define_method(ddsketch_class, "add_with_count", native_add_with_count, 2);
  rb_define_method(ddsketch_class, "count", native_count, 0);
  rb_define_method(ddsketch_class, "encode", native_encode, 0);
}

// This structure is used to define a Ruby object that stores a pointer to a ddsketch_Handle_DDSketch
// See also https://github.com/ruby/ruby/blob/master/doc/extension.rdoc for how this works
static const rb_data_type_t ddsketch_typed_data = {
  .wrap_struct_name = "Datadog::DDSketch",
  .function = {
    .dmark = NULL, // We don't store references to Ruby objects so we don't need to mark any of them
    .dfree = ddsketch_free,
    .dsize = NULL, // We don't track memory usage (although it'd be cool if we did!)
    //.dcompact = NULL, // Not needed -- we don't store references to Ruby objects
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE _native_new(VALUE klass) {
  ddsketch_Handle_DDSketch *state = ruby_xcalloc(1, sizeof(ddsketch_Handle_DDSketch));

  *state = ddog_ddsketch_new();

  return TypedData_Wrap_Struct(klass, &ddsketch_typed_data, state);
}

static void ddsketch_free(void *ptr) {
  ddsketch_Handle_DDSketch *state = (ddsketch_Handle_DDSketch *) ptr;
  ddog_ddsketch_drop(state);
  ruby_xfree(ptr);
}

static VALUE native_add(VALUE self, VALUE point) {
  ddsketch_Handle_DDSketch *state;
  TypedData_Get_Struct(self, ddsketch_Handle_DDSketch, &ddsketch_typed_data, state);

  ddog_VoidResult result = ddog_ddsketch_add(state, NUM2DBL(point));

  CHECK_VOID_RESULT("DDSketch add failed", result);

  return self;
}

static VALUE native_add_with_count(VALUE self, VALUE point, VALUE count) {
  ddsketch_Handle_DDSketch *state;
  TypedData_Get_Struct(self, ddsketch_Handle_DDSketch, &ddsketch_typed_data, state);

  ddog_VoidResult result = ddog_ddsketch_add_with_count(state, NUM2DBL(point), NUM2DBL(count));

  CHECK_VOID_RESULT("DDSketch add_with_count failed", result);

  return self;
}

static VALUE native_count(VALUE self) {
  ddsketch_Handle_DDSketch *state;
  TypedData_Get_Struct(self, ddsketch_Handle_DDSketch, &ddsketch_typed_data, state);

  double count_out;
  ddog_VoidResult result = ddog_ddsketch_count(state, &count_out);

  CHECK_VOID_RESULT("DDSketch count failed", result);

  return DBL2NUM(count_out);
}

static VALUE native_encode(VALUE self) {
  ddsketch_Handle_DDSketch *state;
  TypedData_Get_Struct(self, ddsketch_Handle_DDSketch, &ddsketch_typed_data, state);

  ddog_Vec_U8 encoded = ddog_ddsketch_encode(state);

  // Copy into a Ruby string
  VALUE bytes = rb_str_new((const char *) encoded.ptr, encoded.len);

  ddog_Vec_U8_drop(encoded);

  // The sketch is consumed by encode; to make this a bit more user-friendly for
  // a Ruby API (since we can't "kill" the Ruby object), let's re-initialize it so
  // it can be used again.
  *state = ddog_ddsketch_new();

  return bytes;
}

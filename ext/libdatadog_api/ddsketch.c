#include "datadog_ruby_common.h"
#include <ruby.h>
#include <datadog/ddsketch.h>

static VALUE _native_new(VALUE klass);
static void ddsketch_free(void *ptr);
static VALUE native_add(VALUE self, VALUE point);
static VALUE native_add_with_count(VALUE self, VALUE point, VALUE count);
static VALUE native_count(VALUE self);

void ddsketch_init(VALUE datadog_module) {
  VALUE ddsketch_class = rb_define_class_under(datadog_module, "DDSketch", rb_cObject);

  rb_define_alloc_func(ddsketch_class, _native_new);
  rb_define_method(ddsketch_class, "add", native_add, 1);
  rb_define_method(ddsketch_class, "add_with_count", native_add_with_count, 2);
  rb_define_method(ddsketch_class, "count", native_count, 0);
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

  ddsketch_VoidResult result = ddog_ddsketch_add(state, NUM2DBL(point));

  if (result.tag == DDSKETCH_VOID_RESULT_ERR) {
    rb_raise(rb_eRuntimeError, "DDSketch add failed");
    // TODO: These types need fixing on the libdatadog side
    // rb_raise(rb_eRuntimeError, "DDSketch add failed: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }

  return Qtrue;
}

static VALUE native_add_with_count(VALUE self, VALUE point, VALUE count) {
  ddsketch_Handle_DDSketch *state;
  TypedData_Get_Struct(self, ddsketch_Handle_DDSketch, &ddsketch_typed_data, state);

  ddsketch_VoidResult result = ddog_ddsketch_add_with_count(state, NUM2DBL(point), NUM2DBL(count));

  if (result.tag == DDSKETCH_VOID_RESULT_ERR) {
    rb_raise(rb_eRuntimeError, "DDSketch add_with_count failed");
    // TODO: These types need fixing on the libdatadog side
    // rb_raise(rb_eRuntimeError, "DDSketch add_with_count failed: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }

  return Qtrue;
}

static VALUE native_count(VALUE self) {
  ddsketch_Handle_DDSketch *state;
  TypedData_Get_Struct(self, ddsketch_Handle_DDSketch, &ddsketch_typed_data, state);

  double count_out;
  ddsketch_VoidResult result = ddog_ddsketch_count(state, &count_out);

  if (result.tag == DDSKETCH_VOID_RESULT_ERR) {
    rb_raise(rb_eRuntimeError, "DDSketch count failed");
    // TODO: These types need fixing on the libdatadog side
    // rb_raise(rb_eRuntimeError, "DDSketch count failed: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }

  return DBL2NUM(count_out);
}

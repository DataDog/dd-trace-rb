#include <ruby.h>
#include <datadog/ddsketch.h>

static VALUE _native_new(VALUE klass);
static void ddsketch_free(void *ptr);

void ddsketch_init(VALUE datadog_module) {
  VALUE ddsketch_class = rb_define_class_under(datadog_module, "DDSketch", rb_cObject);

  rb_define_alloc_func(ddsketch_class, _native_new);
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

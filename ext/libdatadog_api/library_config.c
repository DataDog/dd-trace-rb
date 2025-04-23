#include <ruby.h>
#include <datadog/library-config.h>

#include "datadog_ruby_common.h"

static void configurator_free(void *ptr);
static VALUE _native_configurator_new(VALUE klass);
static VALUE _native_configurator_initialize(VALUE self);
static VALUE _native_configurator_get(VALUE self);

static const rb_data_type_t configurator_typed_data = {
  .wrap_struct_name = "Datadog::Core::LibraryConfig::Configurator",
  .function = {
    .dfree = configurator_free,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static void configurator_free(void *ptr) {
  ddog_Configurator *configurator = (ddog_Configurator *)ptr;
  ddog_library_configurator_drop(configurator);
}

void library_config_init(VALUE core_module) {
  VALUE library_config_class = rb_define_class_under(core_module, "LibraryConfig", rb_cObject);
  VALUE configurator_class = rb_define_class_under(library_config_class, "Configurator", rb_cObject);

  rb_define_alloc_func(configurator_class, _native_configurator_new);
  rb_define_method(configurator_class, "initialize", _native_configurator_initialize, 0);
  rb_define_method(configurator_class, "get", _native_configurator_get, 0);
}

static VALUE _native_configurator_new(VALUE klass) {
  ddog_Configurator *configurator = ddog_library_configurator_new(false, DDOG_CHARSLICE_C("ruby"));

  return TypedData_Wrap_Struct(klass, &configurator_typed_data, configurator);
}

static VALUE _native_configurator_initialize(VALUE self) {
  ddog_Configurator *configurator;
  TypedData_Get_Struct(self, ddog_Configurator, &configurator_typed_data, configurator);

  ddog_library_configurator_with_detect_process_info(configurator);

  return self;
}

static VALUE _native_configurator_get(VALUE self) {
  ddog_Configurator *configurator;
  TypedData_Get_Struct(self, ddog_Configurator, &configurator_typed_data, configurator);

  VALUE config_array = rb_ary_new();

  ddog_Result_VecLibraryConfig configurator_result = ddog_library_configurator_get(configurator);
  if (configurator_result.tag == DDOG_RESULT_VEC_LIBRARY_CONFIG_ERR_VEC_LIBRARY_CONFIG) {
    ddog_Error err = configurator_result.err;
    VALUE message = get_error_details_and_drop(&err);
    log_warning(message);
    return Qnil;
  }

  ddog_Vec_LibraryConfig config_vec = configurator_result.ok;
  for (uintptr_t i = 0; i < config_vec.len; i++) {
    ddog_LibraryConfig config = config_vec.ptr[i];
    VALUE config_hash = rb_hash_new();

    ddog_CStr name = ddog_library_config_name_to_env(config.name);
    rb_hash_aset(config_hash, ID2SYM(rb_intern("name")), rb_str_new(name.ptr, name.length));

    // config.value is already a CStr
    rb_hash_aset(config_hash, ID2SYM(rb_intern("value")), rb_str_new(config.value.ptr, config.value.length));

    ddog_CStr source = ddog_library_config_source_to_string(config.source);
    rb_hash_aset(config_hash, ID2SYM(rb_intern("source")), rb_to_symbol(rb_str_new(source.ptr, source.length)));

    rb_ary_push(config_array, config_hash);
  }
  ddog_library_config_drop(config_vec);

  return config_array;
}

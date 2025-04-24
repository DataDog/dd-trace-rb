#include <ruby.h>
#include <datadog/library-config.h>

#include "datadog_ruby_common.h"

static VALUE _native_configurator_new(VALUE klass);
static VALUE _native_configurator_get(VALUE self);

static VALUE config_vec_class = Qnil;

// ddog_Configurator memory management
static void configurator_free(void *configurator_ptr) {
  ddog_Configurator *configurator = (ddog_Configurator *)configurator_ptr;

  ddog_library_configurator_drop(configurator);
}

static const rb_data_type_t configurator_typed_data = {
  .wrap_struct_name = "Datadog::Core::StableConfig::Configurator",
  .function = {
    .dfree = configurator_free,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

// ddog_Vec_LibraryConfig memory management
static void config_vec_free(void *config_vec_ptr) {
  ddog_Vec_LibraryConfig *config_vec = (ddog_Vec_LibraryConfig *)config_vec_ptr;

  ddog_library_config_drop(*config_vec);
  ruby_xfree(config_vec_ptr);
}

static const rb_data_type_t config_vec_typed_data = {
  .wrap_struct_name = "Datadog::Core::StableConfig::Configurator::ConfigVec",
  .function = {
    .dfree = config_vec_free,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

void library_config_init(VALUE core_module) {
  VALUE stable_config_module = rb_define_module_under(core_module, "StableConfig");
  VALUE configurator_class = rb_define_class_under(stable_config_module, "Configurator", rb_cObject);
  config_vec_class = rb_define_class_under(configurator_class, "ConfigVec", rb_cObject);

  rb_define_alloc_func(configurator_class, _native_configurator_new);
  rb_define_method(configurator_class, "get", _native_configurator_get, 0);

  rb_undef_alloc_func(config_vec_class); // It cannot be created form Ruby code and only serves as an intermediate object for the Ruby GC
}

static VALUE _native_configurator_new(VALUE klass) {
  ddog_Configurator *configurator = ddog_library_configurator_new(false, DDOG_CHARSLICE_C("ruby"));

  ddog_library_configurator_with_detect_process_info(configurator);

  return TypedData_Wrap_Struct(klass, &configurator_typed_data, configurator);
}

static VALUE _native_configurator_get(VALUE self) {
  ddog_Configurator *configurator;
  TypedData_Get_Struct(self, ddog_Configurator, &configurator_typed_data, configurator);

  ddog_Result_VecLibraryConfig configurator_result = ddog_library_configurator_get(configurator);

  if (configurator_result.tag == DDOG_RESULT_VEC_LIBRARY_CONFIG_ERR_VEC_LIBRARY_CONFIG) {
    ddog_Error err = configurator_result.err;
    VALUE message = get_error_details_and_drop(&err);
    log_warning(message);
    return Qnil;
  }

  // Wrapping config_vec into a Ruby object enables the Ruby GC to manage its memory
  // We need to allocate memory for config_vec because once it is out of scope, it will be freed (at the end of this function)
  // So we cannot reference it with &config_vec
  ddog_Vec_LibraryConfig *config_vec = ruby_xmalloc(sizeof(ddog_Vec_LibraryConfig));
  *config_vec = configurator_result.ok;
  TypedData_Wrap_Struct(config_vec_class, &config_vec_typed_data, config_vec);

  VALUE config_array = rb_ary_new();
  for (uintptr_t i = 0; i < config_vec->len; i++) {
    ddog_LibraryConfig config = config_vec->ptr[i];
    VALUE config_hash = rb_hash_new();

    ddog_CStr name = ddog_library_config_name_to_env(config.name);
    rb_hash_aset(config_hash, ID2SYM(rb_intern("name")), rb_str_new(name.ptr, name.length));

    // config.value is already a CStr
    rb_hash_aset(config_hash, ID2SYM(rb_intern("value")), rb_str_new(config.value.ptr, config.value.length));

    ddog_CStr source = ddog_library_config_source_to_string(config.source);
    rb_hash_aset(config_hash, ID2SYM(rb_intern("source")), rb_to_symbol(rb_str_new(source.ptr, source.length)));

    rb_ary_push(config_array, config_hash);
  }
  return config_array;
}

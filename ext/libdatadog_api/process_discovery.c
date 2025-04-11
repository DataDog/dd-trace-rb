#include <errno.h>
#include <stdlib.h>
#include <ruby.h>
#include <datadog/common.h>

#include "datadog_ruby_common.h"

static VALUE _native_store_tracer_metadata(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self);
static VALUE _native_close_tracer_memfd(DDTRACE_UNUSED VALUE _self, VALUE fd);

static const rb_data_type_t tracer_memfd_type = {
  .wrap_struct_name = "Datadog::Core::ProcessDiscovery::TracerMemfd",
  .function = {
    .dfree = RUBY_DEFAULT_FREE,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

void process_discovery_init(VALUE core_module) {
  VALUE process_discovery_class = rb_define_class_under(core_module, "ProcessDiscovery", rb_cObject);
  rb_define_class_under(process_discovery_class, "TracerMemfd", rb_cObject);

  rb_define_singleton_method(process_discovery_class, "_native_store_tracer_metadata", _native_store_tracer_metadata, -1);
  rb_define_singleton_method(process_discovery_class, "_native_close_tracer_memfd", _native_close_tracer_memfd, 1);
}

static VALUE _native_store_tracer_metadata(int argc, VALUE *argv, VALUE self) {
  VALUE options;
  rb_scan_args(argc, argv, "0:", &options);
  if (options == Qnil) options = rb_hash_new();

  VALUE schema_version = rb_hash_fetch(options, ID2SYM(rb_intern("schema_version")));
  VALUE runtime_id = rb_hash_fetch(options, ID2SYM(rb_intern("runtime_id")));
  VALUE tracer_language = rb_hash_fetch(options, ID2SYM(rb_intern("tracer_language")));
  VALUE tracer_version = rb_hash_fetch(options, ID2SYM(rb_intern("tracer_version")));
  VALUE hostname = rb_hash_fetch(options, ID2SYM(rb_intern("hostname")));
  VALUE service_name = rb_hash_fetch(options, ID2SYM(rb_intern("service_name")));
  VALUE service_env = rb_hash_fetch(options, ID2SYM(rb_intern("service_env")));
  VALUE service_version = rb_hash_fetch(options, ID2SYM(rb_intern("service_version")));

  ENFORCE_TYPE(schema_version, T_FIXNUM);
  ENFORCE_TYPE(runtime_id, T_STRING);
  ENFORCE_TYPE(tracer_language, T_STRING);
  ENFORCE_TYPE(tracer_version, T_STRING);
  ENFORCE_TYPE(hostname, T_STRING);
  ENFORCE_TYPE(service_name, T_STRING);
  ENFORCE_TYPE(service_env, T_STRING);
  ENFORCE_TYPE(service_version, T_STRING);

  ddog_Result_TracerMemfdHandle result = ddog_store_tracer_metadata(
    (uint8_t) NUM2UINT(schema_version),
    char_slice_from_ruby_string(runtime_id),
    char_slice_from_ruby_string(tracer_language),
    char_slice_from_ruby_string(tracer_version),
    char_slice_from_ruby_string(hostname),
    char_slice_from_ruby_string(service_name),
    char_slice_from_ruby_string(service_env),
    char_slice_from_ruby_string(service_version)
  );

  if (result.tag == DDOG_RESULT_TRACER_MEMFD_HANDLE_ERR_TRACER_MEMFD_HANDLE) {
    rb_raise(rb_eRuntimeError, "Failed to store the tracer configuration in a memory file descriptor: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }

  // &result.ok is a ddog_TracerMemfdHandle, which is a struct only containing int fd, which is a file descriptor
  // We should just return the fd
  int *fd = malloc(sizeof(int));
  if (!fd) {
    rb_raise(rb_eRuntimeError, "Failed to allocate memory for file descriptor");
  }

  *fd = result.ok.fd;
  VALUE tracer_memfd_class = rb_const_get(self, rb_intern("TracerMemfd"));
  VALUE tracer_memfd = TypedData_Wrap_Struct(tracer_memfd_class, &tracer_memfd_type, fd);
  return tracer_memfd;
}

static VALUE _native_close_tracer_memfd(DDTRACE_UNUSED VALUE _self, VALUE tracer_memfd) {
  int *fd;
  TypedData_Get_Struct(tracer_memfd, int, &tracer_memfd_type, fd);
  if (fd == NULL) {
    rb_raise(rb_eRuntimeError, "Failed to get the tracer configuration memory file descriptor: %s", strerror(errno));
  }

  int close_result = close(*fd);
  free(fd);

  if (close_result == -1) {
    rb_raise(rb_eRuntimeError, "Failed to close the tracer configuration memory file descriptor: %s", strerror(errno));
  }

  return Qnil;
}

#include "linux_tid_override.h"
#include "linux_tid_from_pthread.h"
#include "private_vm_api_access.h"
#include "helpers.h"

// Used to access the linux_tid_from_thread functionality.
//
// This file implements the native bits of the Datadog::Profling::LinuxTidOverride class

// Contains state for a single LinuxTidOverride instance
struct linux_tid_override_state {
  short offset;
};

static VALUE _native_new(VALUE klass);
static VALUE _native_working(DDTRACE_UNUSED VALUE self, VALUE self_instance);
static VALUE _native_linux_tid_override_for(DDTRACE_UNUSED VALUE self, VALUE self_instance, VALUE thread);
static VALUE _native_gettid(DDTRACE_UNUSED VALUE self);
static VALUE _native_can_use_process_vm_readv(DDTRACE_UNUSED VALUE self);

void linux_tid_override_init(VALUE profiling_module) {
  VALUE linux_tid_override_class = rb_define_class_under(profiling_module, "LinuxTidOverride", rb_cObject);
  // Hosts methods used for testing the native code using RSpec
  VALUE testing_module = rb_define_module_under(linux_tid_override_class, "Testing");

  // Instances of the LinuxTidOverride class are "TypedData" objects.
  // "TypedData" objects are special objects in the Ruby VM that can wrap C structs.
  // In this case, it wraps the linux_tid_override_state.
  //
  // Because Ruby doesn't know how to initialize native-level structs, we MUST override the allocation function for objects
  // of this class so that we can manage this part. Not overriding or disabling the allocation function is a common
  // gotcha for "TypedData" objects that can very easily lead to VM crashes, see for instance
  // https://bugs.ruby-lang.org/issues/18007 for a discussion around this.
  rb_define_alloc_func(linux_tid_override_class, _native_new);

  rb_define_singleton_method(linux_tid_override_class, "_native_working?", _native_working, 1);
  rb_define_singleton_method(testing_module, "_native_linux_tid_override_for", _native_linux_tid_override_for, 2);
  rb_define_singleton_method(testing_module, "_native_gettid", _native_gettid, 0);
  rb_define_singleton_method(testing_module, "_native_can_use_process_vm_readv?", _native_can_use_process_vm_readv, 0);
}

// This structure is used to define a Ruby object that stores a pointer to a struct linux_tid_override_state
// See also https://github.com/ruby/ruby/blob/master/doc/extension.rdoc for how this works
static const rb_data_type_t linux_tid_override_typed_data = {
  .wrap_struct_name = "Datadog::Profiling::LinuxTidOverride",
  .function = {
    .dmark = NULL, // We don't store references to Ruby objects so we don't need to mark any of them
    .dfree = RUBY_DEFAULT_FREE, // We don't store references to malloc'd memory so we don't need a custom free
    .dsize = NULL, // We don't track memory usage (although it'd be cool if we did!)
    //.dcompact = NULL, // Not needed -- we don't store references to Ruby objects
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE _native_new(VALUE klass) {
  struct linux_tid_override_state *state = ruby_xcalloc(1, sizeof(struct linux_tid_override_state));

  state->offset = setup_linux_tid_from_pthread_offset();

  return TypedData_Wrap_Struct(klass, &linux_tid_override_typed_data, state);
}

pid_t linux_tid_override_for(VALUE linux_tid_override, pthread_t thread) {
  struct linux_tid_override_state *state;
  TypedData_Get_Struct(linux_tid_override, struct linux_tid_override_state, &linux_tid_override_typed_data, state);

  if (state->offset < 0) return -1;

  return linux_tid_from(thread, state->offset);
}

static VALUE _native_working(DDTRACE_UNUSED VALUE self, VALUE self_instance) {
  return linux_tid_override_for(self_instance, pthread_self()) == ddtrace_gettid() ? Qtrue : Qfalse;
}

// This method exists only to enable testing Datadog::Profiling::LinuxTidOverride behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_linux_tid_override_for(DDTRACE_UNUSED VALUE self, VALUE self_instance, VALUE thread) {
  return LONG2NUM(linux_tid_override_for(self_instance, pthread_id_for(thread)));
}

// This method exists only to enable testing Datadog::Profiling::LinuxTidOverride behavior using RSpec.
// It SHOULD NOT be used for other purposes.
static VALUE _native_gettid(DDTRACE_UNUSED VALUE self) {
  return LONG2NUM(ddtrace_gettid());
}

static VALUE _native_can_use_process_vm_readv(DDTRACE_UNUSED VALUE self) {
  return can_use_process_vm_readv() ? Qtrue : Qfalse;
}

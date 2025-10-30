#include "extconf.h"

#ifdef RUBY_MJIT_HEADER
  // Pick up internal structures from the private Ruby MJIT header file
  #include RUBY_MJIT_HEADER
#else
  // The MJIT header was introduced on 2.6 and removed on 3.3; for other Rubies we rely on
  // the datadog-ruby_core_source gem to get access to private VM headers.

  // We can't do anything about warnings in VM headers, so we just use this technique to suppress them.
  // See https://nelkinda.com/blog/suppress-warnings-in-gcc-and-clang/#d11e364 for details.
  #pragma GCC diagnostic push
  #pragma GCC diagnostic ignored "-Wunused-parameter"
  #pragma GCC diagnostic ignored "-Wattributes"
  #pragma GCC diagnostic ignored "-Wpragmas"
  #pragma GCC diagnostic ignored "-Wexpansion-to-defined"
    #include <vm_core.h>
  #pragma GCC diagnostic pop

  #pragma GCC diagnostic push
  #pragma GCC diagnostic ignored "-Wunused-parameter"
    #include <iseq.h>
  #pragma GCC diagnostic pop

  #include <ruby.h>

  #ifndef NO_RACTOR_HEADER_INCLUDE
    #pragma GCC diagnostic push
    #pragma GCC diagnostic ignored "-Wunused-parameter"
      #include <ractor_core.h>
    #pragma GCC diagnostic pop
  #endif
#endif

#include <datadog/crashtracker.h>
#include "datadog_ruby_common.h"
#include <sys/mman.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

// This was renamed in Ruby 3.2
#if !defined(ccan_list_for_each) && defined(list_for_each)
  #define ccan_list_for_each list_for_each
#endif

static VALUE _native_start_or_update_on_fork(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self);
static VALUE _native_stop(DDTRACE_UNUSED VALUE _self);
static VALUE _native_register_runtime_stack_callback(VALUE _self, VALUE callback_type);
static VALUE _native_is_runtime_callback_registered(DDTRACE_UNUSED VALUE _self);

static void ruby_runtime_stack_callback(
  void (*emit_frame)(const ddog_crasht_RuntimeStackFrame*)
);

static bool first_init = true;

static bool is_pointer_readable(const void *ptr, size_t size) {
  if (!ptr) return false;

  // This is signal-safe and doesn't allocate memory
  size_t page_size = getpagesize();
  void *aligned_ptr = (void*)((uintptr_t)ptr & ~(page_size - 1));
  size_t pages = ((char*)ptr + size - (char*)aligned_ptr + page_size - 1) / page_size;

  // Stack-allocate a small buffer for mincore results.. should be safe?
  unsigned char vec[16];
  if (pages > 16) return false; // Too big to check safely

  return mincore(aligned_ptr, pages * page_size, vec) == 0;
}

static bool is_safe_string_encoding(const char *ptr, long len) {
  if (!ptr || len <= 0) return false;

  // Should we scan it all?
  for (long i = 0; i < len && i < 128; i++) {
    unsigned char c = (unsigned char)ptr[i];

    if (c == 0 && i < len - 1) return false;

    // Control characters (except tab, newline, return) is sus
    if (c < 0x20 && c != 0x09 && c != 0x0A && c != 0x0D) return false;

    // High bytes
    if (c >= 0xF8) return false;
  }

  return true;
}

static bool is_reasonable_string_size(VALUE str) {
  if (str == Qnil) return false;
  if (!RB_TYPE_P(str, T_STRING)) return false;

  if (!is_pointer_readable(&str, sizeof(VALUE))) return false;

  long len = RSTRING_LEN(str);

  if (len < 0) return false;  // Negative length, probably corrupted
  if (len > 2048) return false;  // > 2KB path/function name, sus

  if (len > 0) {
    if (!is_pointer_readable(RSTRING(str), sizeof(struct RString))) return false;
  }

  return true;
}

static const char* safe_string_ptr(VALUE str) {
  if (str == Qnil) return "<nil>";
  if (!RB_TYPE_P(str, T_STRING)) return "<not_string>";

  long len = RSTRING_LEN(str);
  if (!is_reasonable_string_size(str)) return "<corrupted>";

  // Use Ruby's standard string pointer access (handles different representations internally)
  const char *ptr = RSTRING_PTR(str);

  if (!ptr) return "<null>";

  if (!is_pointer_readable(ptr, len > 0 ? len : 1)) return "<unreadable>";
  if (!is_safe_string_encoding(ptr, len)) return "<unsafe_encoding>";

  return ptr;
}

static bool is_valid_control_frame(const rb_control_frame_t *cfp,
                                   const rb_execution_context_t *ec) {
  if (!cfp) return false;

  void *stack_start = ec->vm_stack;
  void *stack_end = (char*)stack_start + ec->vm_stack_size * sizeof(VALUE);
  if ((void*)cfp < stack_start || (void*)cfp >= stack_end) {
    return false;
  }

  if (!is_pointer_readable(cfp, sizeof(rb_control_frame_t))) {
    return false;
  }

  return true;
}

static bool is_valid_iseq(const rb_iseq_t *iseq) {
  if (!iseq) return false;
  if (!is_pointer_readable(iseq, sizeof(rb_iseq_t))) return false;

  // Check iseq body
  if (!iseq->body) return false;
  if (!is_pointer_readable(iseq->body, sizeof(*iseq->body))) return false;

  // Validate iseq size
  if (iseq->body->iseq_size > 100000) return false; // > 100K instructions, suspicious

  return true;
}

// Used to report Ruby VM crashes.
// Once initialized, segfaults will be reported automatically using libdatadog.

void crashtracker_init(VALUE core_module) {
  VALUE crashtracking_module = rb_define_module_under(core_module, "Crashtracking");
  VALUE crashtracker_class = rb_define_class_under(crashtracking_module, "Component", rb_cObject);

  rb_define_singleton_method(crashtracker_class, "_native_start_or_update_on_fork", _native_start_or_update_on_fork, -1);
  rb_define_singleton_method(crashtracker_class, "_native_stop", _native_stop, 0);
  rb_define_singleton_method(crashtracker_class, "_native_register_runtime_stack_callback", _native_register_runtime_stack_callback, 1);
  rb_define_singleton_method(crashtracker_class, "_native_is_runtime_callback_registered", _native_is_runtime_callback_registered, 0);
}

static VALUE _native_start_or_update_on_fork(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self) {
  VALUE options;
  rb_scan_args(argc, argv, "0:", &options);
  if (options == Qnil) options = rb_hash_new();

  VALUE agent_base_url = rb_hash_fetch(options, ID2SYM(rb_intern("agent_base_url")));
  VALUE path_to_crashtracking_receiver_binary = rb_hash_fetch(options, ID2SYM(rb_intern("path_to_crashtracking_receiver_binary")));
  VALUE ld_library_path = rb_hash_fetch(options, ID2SYM(rb_intern("ld_library_path")));
  VALUE tags_as_array = rb_hash_fetch(options, ID2SYM(rb_intern("tags_as_array")));
  VALUE action = rb_hash_fetch(options, ID2SYM(rb_intern("action")));
  VALUE upload_timeout_seconds = rb_hash_fetch(options, ID2SYM(rb_intern("upload_timeout_seconds")));

  VALUE start_action = ID2SYM(rb_intern("start"));
  VALUE update_on_fork_action = ID2SYM(rb_intern("update_on_fork"));

  ENFORCE_TYPE(agent_base_url, T_STRING);
  ENFORCE_TYPE(tags_as_array, T_ARRAY);
  ENFORCE_TYPE(path_to_crashtracking_receiver_binary, T_STRING);
  ENFORCE_TYPE(ld_library_path, T_STRING);
  ENFORCE_TYPE(action, T_SYMBOL);
  ENFORCE_TYPE(upload_timeout_seconds, T_FIXNUM);

  if (action != start_action && action != update_on_fork_action) rb_raise(rb_eArgError, "Unexpected action: %+"PRIsVALUE, action);

  VALUE version = datadog_gem_version();

  // Tags and endpoint are heap-allocated, so after here we can't raise exceptions otherwise we'll leak this memory
  // Start of exception-free zone to prevent leaks {{
  ddog_Endpoint *endpoint = ddog_endpoint_from_url(char_slice_from_ruby_string(agent_base_url));
  if (endpoint == NULL) {
    rb_raise(rb_eRuntimeError, "Failed to create endpoint from agent_base_url: %"PRIsVALUE, agent_base_url);
  }
  ddog_Vec_Tag tags = convert_tags(tags_as_array);

  ddog_crasht_Config config = {
    .additional_files = {},
    // @ivoanjo: The Ruby VM already uses an alt stack to detect stack overflows.
    //
    // In libdatadog < 14 with `create_alt_stack = true` I saw a segfault, such as Ruby 2.6's bug with
    // "Process.detach(fork { exit! }).instance_variable_get(:@foo)" being turned into a
    // "-e:1:in `instance_variable_get': stack level too deep (SystemStackError)" by Ruby.
    // The Ruby crash handler also seems to get confused when this option is enabled and
    // "Process.kill('SEGV', Process.pid)" gets run.
    //
    // This actually changed in libdatadog 14, so I could see no issues with `create_alt_stack = true`, but not
    // overriding what Ruby set up seems a saner default to keep anyway.
    .create_alt_stack = false,
    .use_alt_stack = true,
    .endpoint = endpoint,
    .resolve_frames = DDOG_CRASHT_STACKTRACE_COLLECTION_ENABLED_WITH_SYMBOLS_IN_RECEIVER,
    .timeout_ms = FIX2INT(upload_timeout_seconds) * 1000,
  };

  ddog_crasht_Metadata metadata = {
    .library_name = DDOG_CHARSLICE_C("dd-trace-rb"),
    .library_version = char_slice_from_ruby_string(version),
    .family = DDOG_CHARSLICE_C("ruby"),
    .tags = &tags,
  };

  ddog_crasht_EnvVar ld_library_path_env = {
    .key = DDOG_CHARSLICE_C("LD_LIBRARY_PATH"),
    .val = char_slice_from_ruby_string(ld_library_path),
  };

  ddog_crasht_ReceiverConfig receiver_config = {
    .args = {},
    .env = {.ptr = &ld_library_path_env, .len = 1},
    .path_to_receiver_binary = char_slice_from_ruby_string(path_to_crashtracking_receiver_binary),
    .optional_stderr_filename = {},
    .optional_stdout_filename = {},
  };

  ddog_VoidResult result =
    action == start_action ?
      (first_init ?
        ddog_crasht_init(config, receiver_config, metadata) :
        ddog_crasht_reconfigure(config, receiver_config, metadata)
      ) :
      ddog_crasht_update_on_fork(config, receiver_config, metadata);

  first_init = false;

  // Clean up before potentially raising any exceptions
  ddog_Vec_Tag_drop(tags);
  ddog_endpoint_drop(endpoint);
  // }} End of exception-free zone to prevent leaks

  if (result.tag == DDOG_VOID_RESULT_ERR) {
    rb_raise(rb_eRuntimeError, "Failed to start/update the crash tracker: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }

  return Qtrue;
}

static VALUE _native_stop(DDTRACE_UNUSED VALUE _self) {
  ddog_VoidResult result = ddog_crasht_disable();

  if (result.tag == DDOG_VOID_RESULT_ERR) {
    rb_raise(rb_eRuntimeError, "Failed to stop the crash tracker: %"PRIsVALUE, get_error_details_and_drop(&result.err));
  }

  return Qtrue;
}

static void ruby_runtime_stack_callback(
  void (*emit_frame)(const ddog_crasht_RuntimeStackFrame*)
) {

  VALUE current_thread = rb_thread_current();
  if (current_thread == Qnil) return;

  // Get thread struct carefully
  static const rb_data_type_t *thread_data_type = NULL;
  if (thread_data_type == NULL) {
    thread_data_type = RTYPEDDATA_TYPE(current_thread);
    if (!thread_data_type) return;
  }

  rb_thread_t *th = (rb_thread_t *) rb_check_typeddata(current_thread, thread_data_type);
  if (!th) return;

  const rb_execution_context_t *ec = th->ec;
  if (!ec) return;

  if (th->status == THREAD_KILLED) return;
  if (!ec->vm_stack || ec->vm_stack_size == 0) return;

  const rb_control_frame_t *cfp = ec->cfp;
  const rb_control_frame_t *end_cfp = RUBY_VM_END_CONTROL_FRAME(ec);

  if (!cfp || !end_cfp) return;

  // Skip dummy frame, `thread_profile_frames` does this too
  end_cfp = RUBY_VM_NEXT_CONTROL_FRAME(end_cfp);
  if (end_cfp <= cfp) return;

  end_cfp = RUBY_VM_NEXT_CONTROL_FRAME(end_cfp);

  int frame_count = 0;
  const int MAX_FRAMES = 400;

  // Traverse from current frame backwards to older frames, so that we get the crash point at the top
  for (; frame_count < MAX_FRAMES && cfp != end_cfp; cfp = RUBY_VM_PREVIOUS_CONTROL_FRAME(cfp)) {
    if (!is_valid_control_frame(cfp, ec)) {
      continue;
    }

    if (cfp->iseq && !cfp->pc) {
      continue;
    }

    if (VM_FRAME_RUBYFRAME_P(cfp) && cfp->iseq) {
      // Handle Ruby frames
      const rb_iseq_t *iseq = cfp->iseq;

      if (!is_valid_iseq(iseq)) {
        continue;
      }

      VALUE name = rb_iseq_base_label(iseq);
      const char *function_name = "<unknown>";
      if (name != Qnil) {
        function_name = safe_string_ptr(name);
      }

      VALUE filename = rb_iseq_path(iseq);
      const char *file_name = "<unknown>";
      if (filename != Qnil) {
        file_name = safe_string_ptr(filename);
      }

      int line_no = 0;
      if (iseq && iseq->body) {
        if (!cfp->pc) {
          // Handle case where PC is NULL - use first line number like private_vm_api_access.c
          if (iseq->body->type == ISEQ_TYPE_TOP) {
            // For TOP type iseqs, line number should be 0
            line_no = 0;
          } else {
            // Use first line number for other types
            # ifndef NO_INT_FIRST_LINENO // Ruby 3.2+
              line_no = iseq->body->location.first_lineno;
            # else
              line_no = FIX2INT(iseq->body->location.first_lineno);
            #endif
          }
        } else {
          // Handle case where PC is available - mirror calc_pos logic
          if (is_pointer_readable(iseq->body->iseq_encoded, iseq->body->iseq_size * sizeof(*iseq->body->iseq_encoded)) &&
              iseq->body->iseq_size > 0) {
            ptrdiff_t pc_offset = cfp->pc - iseq->body->iseq_encoded;

            // bounds checking like private_vm_api_access.c PROF-11475 fix
            if (pc_offset >= 0 && pc_offset <= iseq->body->iseq_size) {
              size_t pos = (size_t)pc_offset;
              if (pos > 0) {
                // Use pos-1 because PC points to next instruction
                pos--;
              }
              line_no = rb_iseq_line_no(iseq, pos);
            }
          }
        }
      }

      ddog_crasht_RuntimeStackFrame frame = {
        .type_name = char_slice_from_cstr(NULL),
        .function = char_slice_from_cstr(function_name),
        .file = char_slice_from_cstr(file_name),
        .line = line_no,
        .column = 0
      };

      emit_frame(&frame);
      frame_count++;
    } else if (VM_FRAME_CFRAME_P(cfp)) {
      const char *function_name = "<C method>";
      const char *file_name = "<C extension>";

      // Try to get method entry information
      const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);
      if (me && is_pointer_readable(me, sizeof(rb_callable_method_entry_t))) {
        if (me->def && is_pointer_readable(me->def, sizeof(*me->def))) {
          if (me->def->original_id) {
            const char *method_name = rb_id2name(me->def->original_id);
            if (method_name && is_pointer_readable(method_name, strlen(method_name))) {
              // Sanity check for method name length
              size_t method_name_len = strlen(method_name);
              if (method_name_len > 0 && method_name_len < 256) {
                function_name = method_name;
              }
            }
          }

          if (me->def->type == VM_METHOD_TYPE_CFUNC && me->owner) {
            // Try to get the full class/module path
            VALUE owner_name = Qnil;
            VALUE actual_owner = me->owner;

            // If this is a singleton class (like Fiddle's singleton class for module methods),
            // try to get the attached object which should be the actual module or else we will
            // just get `Module` which is not that useful lol
            if (RB_TYPE_P(me->owner, T_CLASS) && FL_TEST(me->owner, FL_SINGLETON)) {
              VALUE attached = rb_ivar_get(me->owner, rb_intern("__attached__"));
              if (attached != Qnil) {
                actual_owner = attached;
              }
            }

            // Get the class/module path
            if (RB_TYPE_P(actual_owner, T_CLASS) || RB_TYPE_P(actual_owner, T_MODULE)) {
              owner_name = rb_class_path(actual_owner);
            }

            // Fallback to rb_class_name if rb_class_path fails
            if (owner_name == Qnil) {
              owner_name = rb_class_name(actual_owner);
            }

            if (owner_name != Qnil) {
              const char *owner_str = safe_string_ptr(owner_name);
              static char file_buffer[256];
              snprintf(file_buffer, sizeof(file_buffer), "<%s (C extension)>", owner_str);
              file_name = file_buffer;
            }
          }
        }
      }

      ddog_crasht_RuntimeStackFrame frame = {
        .type_name = char_slice_from_cstr(NULL),
        .function = char_slice_from_cstr(function_name),
        .file = char_slice_from_cstr(file_name),
        .line = 0,
        .column = 0
      };

      emit_frame(&frame);
      frame_count++;
    }
  }
}

static VALUE _native_register_runtime_stack_callback(DDTRACE_UNUSED VALUE _self, VALUE callback_type) {
  ENFORCE_TYPE(callback_type, T_SYMBOL);

  VALUE frame_symbol = ID2SYM(rb_intern("frame"));
  if (callback_type != frame_symbol) {
    rb_raise(rb_eArgError, "Invalid callback_type. Only :frame is supported");
  }

  enum ddog_crasht_CallbackResult result = ddog_crasht_register_runtime_frame_callback(
    ruby_runtime_stack_callback
  );

  switch (result) {
    case DDOG_CRASHT_CALLBACK_RESULT_OK:
      return Qtrue;
    default:
      return Qfalse;
  }

  return Qfalse;
}

static VALUE _native_is_runtime_callback_registered(DDTRACE_UNUSED VALUE _self) {
  return ddog_crasht_is_runtime_callback_registered() ? Qtrue : Qfalse;
}

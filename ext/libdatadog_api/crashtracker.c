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

// Include profiling stack walking functionality
// Note: rb_iseq_path and rb_iseq_base_label are already declared in MJIT header

// This was renamed in Ruby 3.2
#if !defined(ccan_list_for_each) && defined(list_for_each)
  #define ccan_list_for_each list_for_each
#endif

static VALUE _native_start_or_update_on_fork(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self);
static VALUE _native_stop(DDTRACE_UNUSED VALUE _self);
static VALUE _native_register_runtime_stack_callback(VALUE _self, VALUE callback_type);
static VALUE _native_is_runtime_callback_registered(DDTRACE_UNUSED VALUE _self);

static void ruby_runtime_stack_callback(
  void (*emit_frame)(const ddog_crasht_RuntimeStackFrame*),
  void (*emit_stacktrace_string)(const char*)
);

static bool first_init = true;

// Safety checks for signal-safe stack walking
static bool is_pointer_readable(const void *ptr, size_t size) {
  if (!ptr) return false;

  // This is signal-safe and doesn't allocate memory
  size_t page_size = getpagesize();
  void *aligned_ptr = (void*)((uintptr_t)ptr & ~(page_size - 1));
  size_t pages = ((char*)ptr + size - (char*)aligned_ptr + page_size - 1) / page_size;

  // Stack-allocate a small buffer for mincore results.. should be safe?
  char vec[16]; // Support up to 16 pages (64KB on 4K page systems)
  if (pages > 16) return false; // Too big to check safely

  return mincore(aligned_ptr, pages * page_size, vec) == 0;
}

static bool is_reasonable_string_size(VALUE str) {
  if (str == Qnil) return false;

  long len = RSTRING_LEN(str);

  // Sanity checks for corrupted string lengths
  if (len < 0) return false;  // Negative length, probably corrupted
  if (len > 1024) return false;  // > 1KB path/function name, suspicious for crash context

  return true;
}

static const char* safe_string_ptr(VALUE str) {
  if (str == Qnil) return "<nil>";

  long len = RSTRING_LEN(str);
  if (len < 0 || len > 2048) return "<corrupted>";

  const char *ptr = RSTRING_PTR(str);
  if (!ptr) return "<null>";

  if (!is_pointer_readable(ptr, len)) return "<unreadable>";

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
  void (*emit_frame)(const ddog_crasht_RuntimeStackFrame*),
  void (*emit_stacktrace_string)(const char*)
) {
  (void)emit_stacktrace_string;

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

  end_cfp = RUBY_VM_NEXT_CONTROL_FRAME(end_cfp);
  if (end_cfp <= cfp) return;

  const rb_control_frame_t *top_sentinel = RUBY_VM_NEXT_CONTROL_FRAME(cfp);

  cfp = RUBY_VM_NEXT_CONTROL_FRAME(end_cfp);

  int frame_count = 0;
  const int MAX_FRAMES = 20;

  for (; cfp != top_sentinel && frame_count < MAX_FRAMES; cfp = RUBY_VM_NEXT_CONTROL_FRAME(cfp)) {
    if (!is_valid_control_frame(cfp, ec)) {
      continue; // Skip invalid frames
    }

    if (cfp->iseq && !cfp->pc) {
      continue;
    }

    if (VM_FRAME_RUBYFRAME_P(cfp) && cfp->iseq) {
      const rb_iseq_t *iseq = cfp->iseq;

      if (!iseq || !iseq->body) {
        continue;
      }

      VALUE name = rb_iseq_base_label(iseq);
      const char *function_name = (name != Qnil) ? safe_string_ptr(name) : "<unknown>";

      VALUE filename = rb_iseq_path(iseq);
      const char *file_name = (filename != Qnil) ? safe_string_ptr(filename) : "<unknown>";

      int line_no = 0;
      if (iseq && cfp->pc) {
        if (iseq->body && iseq->body->iseq_encoded && iseq->body->iseq_size > 0) {
          ptrdiff_t pc_offset = cfp->pc - iseq->body->iseq_encoded;
          if (pc_offset >= 0 && pc_offset < iseq->body->iseq_size) {
            // Use the Ruby VM line calculation like ddtrace_rb_profile_frames
            size_t pos = pc_offset;
            if (pos > 0) {
              pos--; // Use pos-1 because PC points next instruction
            }
            line_no = rb_iseq_line_no(iseq, pos);
          }
        }
      }

      ddog_crasht_RuntimeStackFrame frame = {
        .function_name = function_name,
        .file_name = file_name,
        .line_number = line_no,
        .column_number = 0
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

  enum ddog_crasht_CallbackResult result = ddog_crasht_register_runtime_stack_callback(
    ruby_runtime_stack_callback,
    DDOG_CRASHT_CALLBACK_TYPE_FRAME
  );

  switch (result) {
    case DDOG_CRASHT_CALLBACK_RESULT_OK:
      return Qtrue;
    case DDOG_CRASHT_CALLBACK_RESULT_NULL_CALLBACK:
      rb_raise(rb_eRuntimeError, "Failed to register runtime callback: null callback provided");
      break;
    case DDOG_CRASHT_CALLBACK_RESULT_UNKNOWN_ERROR:
      rb_raise(rb_eRuntimeError, "Failed to register runtime callback: unknown error");
      break;
  }

  return Qfalse;
}

static VALUE _native_is_runtime_callback_registered(DDTRACE_UNUSED VALUE _self) {
  return ddog_crasht_is_runtime_callback_registered() ? Qtrue : Qfalse;
}

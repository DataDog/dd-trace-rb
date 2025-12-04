// NOTE: This file is a part of the profiling native extension even though the
// runtime stacks feature is consumed by the crashtracker. The profiling
// extension already carries all the Ruby VM private header access and build
// plumbing required to safely poke at internal structures. Sharing that setup
// avoids duplicating another native extension with the same (fragile) access
// patterns, and keeps the overall install/build surface area smaller.
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

#include "crashtracking_runtime_stacks.h"
#include <datadog/crashtracker.h>
#include "datadog_ruby_common.h"
#include "private_vm_api_access.h"
#include <sys/mman.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

static VALUE _native_register_runtime_stack_callback(VALUE _self);
static VALUE _native_is_runtime_callback_registered(DDTRACE_UNUSED VALUE _self);
static const rb_data_type_t *crashtracker_thread_data_type = NULL;

static void ruby_runtime_stack_callback(
  void (*emit_frame)(const ddog_crasht_RuntimeStackFrame*)
);

#if defined(__x86_64__)
#  define SYS_MINCORE 0x1B
#elif defined(__aarch64__)
#  define SYS_MINCORE 0xE8
#endif

long syscall(long number, ...);

// align down to power of two
static inline uintptr_t align_down(uintptr_t x, uintptr_t align) {
  return x & ~(align - 1u);
}

static inline bool is_pointer_readable(const void *ptr, size_t size) {
  if (!ptr || size == 0) return false;

  uintptr_t page_size = (uintptr_t)sysconf(_SC_PAGESIZE);
  // fallback for weird value; 0 or not a power of two
  if (page_size == 0 || (page_size & (page_size - 1u))) {
      page_size = 4096;
  }

  const uintptr_t start = align_down((uintptr_t)ptr, page_size);
  const uintptr_t end   = ((uintptr_t)ptr + size - 1u);
  const uintptr_t last  = align_down(end, page_size);

  // Number of pages spanned
  size_t pages = 1u + (last != start);
  if (pages > 2u) pages = 2u;

  unsigned char vec[2];

  int retries = 5;
  for (;;) {
      size_t len = pages * (size_t)page_size;
      long rc = syscall(SYS_MINCORE, (void*)start, len, vec);

      if (rc == 0) {
          return true;
      }

      int e = errno;
      if (e == ENOMEM || e == EFAULT) {
          return false;
      }

      if (e == EAGAIN && retries-- > 0) {
          continue;
      }

      // Unknown errno, we assume mapped to avoid cascading faults in crash path
      return true;
  }
}

static bool is_reasonable_string_size(VALUE str) {
  if (str == Qnil) return false;
  if (!RB_TYPE_P(str, T_STRING)) return false;

  // Check if the heap object pointed to by str is readable
  if (!is_pointer_readable((const void *)str, sizeof(struct RBasic))) return false;

  // For strings, we need to check the full RString structure
  if (!is_pointer_readable(RSTRING(str), sizeof(struct RString))) return false;

  long len = RSTRING_LEN(str);

  if (len < 0) return false;  // Negative length, probably corrupted
  if (len > 1024) return false;  // > 1KB path/function name, sus

  return true;
}

static const char* safe_string_ptr(VALUE str) {
  if (str == Qnil) return "<nil>";
  if (!RB_TYPE_P(str, T_STRING)) return "<not_string>";

  // Validate the VALUE first before touching any of its internals
  if (!is_reasonable_string_size(str)) return "<corrupted>";

  long len = RSTRING_LEN(str);
  const char *ptr = RSTRING_PTR(str);

  if (!ptr) return "<null>";

  if (!is_pointer_readable(ptr, len > 0 ? len : 1)) return "<unreadable>";

  return ptr;
}

static bool is_valid_control_frame(const rb_control_frame_t *cfp,
                                   const rb_execution_context_t *ec) {
  if (!cfp) return false;
  if (!ec) return false;

  if (!is_pointer_readable(ec, sizeof(*ec))) {
    return false;
  }

  VALUE *stack_ptr = ec->vm_stack;
  size_t stack_slots = ec->vm_stack_size;
  if (!stack_ptr || stack_slots == 0) {
    return false;
  }

  size_t stack_bytes = stack_slots * sizeof(VALUE);
  if (stack_bytes / sizeof(VALUE) != stack_slots) {
    return false;  // overflow
  }

  const char *stack_start = (const char *)stack_ptr;
  if (!is_pointer_readable(stack_start, sizeof(VALUE))) {
    return false;
  }

  const char *stack_end = stack_start + stack_bytes;
  if (!is_pointer_readable(stack_end - sizeof(VALUE), sizeof(VALUE))) {
    return false;
  }
  const char *cfp_ptr = (const char *)cfp;
  if (cfp_ptr < stack_start || cfp_ptr >= stack_end) {
    return false;
  }

  if (!is_pointer_readable(cfp, sizeof(rb_control_frame_t))) {
    return false;
  }

  return true;
}

static bool fetch_iseq_body(const rb_iseq_t *iseq, const struct rb_iseq_constant_body **body_out) {
  if (!iseq) return false;
  if (!is_pointer_readable(iseq, sizeof(rb_iseq_t))) return false;

  const struct rb_iseq_constant_body *body = iseq->body;
  if (!body) return false;

  if (!is_pointer_readable(body, sizeof(*body))) return false;
  if (!is_pointer_readable(&body->type, sizeof(body->type))) return false;
  if (!is_pointer_readable(&body->location, sizeof(body->location))) return false;
  if (!is_pointer_readable(&body->iseq_size, sizeof(body->iseq_size))) return false;
  if (!is_pointer_readable(&body->iseq_encoded, sizeof(body->iseq_encoded))) return false;

  if (body_out) {
    *body_out = body;
  }

  return true;
}

static bool is_valid_iseq(const rb_iseq_t *iseq, const struct rb_iseq_constant_body **body_out) {
  const struct rb_iseq_constant_body *body = NULL;
  if (!fetch_iseq_body(iseq, &body)) {
    return false;
  }

  // Validate iseq size
  if (body->iseq_size > 100000) return false; // > 100K instructions, suspicious

  if (body_out) {
    *body_out = body;
  }

  return true;
}

static void ruby_runtime_stack_callback(
  void (*emit_frame)(const ddog_crasht_RuntimeStackFrame*)
) {

  VALUE current_thread = rb_thread_current();
  if (current_thread == Qnil) return;

  if (crashtracker_thread_data_type == NULL) return;

  rb_thread_t *th = (rb_thread_t *) rb_check_typeddata(current_thread, crashtracker_thread_data_type);
  if (!th || !is_pointer_readable(th, sizeof(*th))) return;

  const rb_execution_context_t *ec = th->ec;
  if (!ec || !is_pointer_readable(ec, sizeof(*ec))) return;

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


    if (VM_FRAME_RUBYFRAME_P(cfp) && cfp->iseq) {
      // Handle Ruby frames
      const rb_iseq_t *iseq = cfp->iseq;
      const struct rb_iseq_constant_body *body = NULL;

      if (!is_valid_iseq(iseq, &body)) {
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
      if (body) {
        if (!cfp->pc) {
          // Handle case where PC is NULL; using first line number like private_vm_api_access.c
          if (body->type == ISEQ_TYPE_TOP) {
            // For TOP type iseqs, line number should be 0
            line_no = 0;
          } else {
            // Use first line number for other types
            # ifndef NO_INT_FIRST_LINENO // Ruby 3.2+
              line_no = body->location.first_lineno;
            # else
              line_no = FIX2INT(body->location.first_lineno);
            #endif
          }
        } else {
          // Handle case where PC is available - mirror calc_pos logic
          if (body->iseq_size > 0 &&
              is_pointer_readable(body->iseq_encoded, body->iseq_size * sizeof(*body->iseq_encoded))) {
            ptrdiff_t pc_offset = cfp->pc - body->iseq_encoded;

            // bounds checking like private_vm_api_access.c PROF-11475 fix
            // to prevent crashes when calling rb_iseq_line_no
            if (pc_offset >= 0 && pc_offset <= (ptrdiff_t)body->iseq_size) {
              size_t pos = (size_t)pc_offset;
              if (pos > 0) {
                // Use pos-1 because PC points to next instruction
                pos--;
              }

              // Additional safety check before calling rb_iseq_line_no (PROF-11475 fix)
              if (pos < body->iseq_size) {
                line_no = rb_iseq_line_no(iseq, pos);
              }
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

      // Resolve Ruby C frames via rb_vm_frame_method_entry (Ruby or our fallback depending on version)
      const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);
      if (is_pointer_readable(me, sizeof(rb_callable_method_entry_t))) {
        const rb_method_definition_t *method_def = me->def;
        if (is_pointer_readable(method_def, sizeof(*method_def))) {
          if (method_def->original_id) {
            const char *method_name = rb_id2name(method_def->original_id);
            if (is_pointer_readable(method_name, 256)) {
              size_t method_name_len = strnlen(method_name, 256);
              if (method_name_len > 0 && method_name_len < 256) {
                function_name = method_name;
              }
            }
          }

          if (method_def->type == VM_METHOD_TYPE_CFUNC && me->owner) {
            // Try to get the full class/module path
            VALUE owner_name = Qnil;
            VALUE actual_owner = me->owner;

            // If this is a singleton class (like Fiddle's singleton class for module methods),
            // try to get the attached object which should be the actual module
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

static VALUE _native_register_runtime_stack_callback(DDTRACE_UNUSED VALUE _self) {
  if (crashtracker_thread_data_type == NULL) {
    VALUE current_thread = rb_thread_current();
    if (current_thread == Qnil) return Qfalse;

    const rb_data_type_t *thread_data_type = RTYPEDDATA_TYPE(current_thread);
    if (!thread_data_type) return Qfalse;

    crashtracker_thread_data_type = thread_data_type;
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

void crashtracking_runtime_stacks_init(VALUE datadog_module) {
  VALUE core_module = rb_define_module_under(datadog_module, "Core");
  VALUE crashtracking_module = rb_define_module_under(core_module, "Crashtracking");
  VALUE runtime_stacks_class = rb_define_class_under(crashtracking_module, "RuntimeStacks", rb_cObject);

  rb_define_singleton_method(
    runtime_stacks_class,
    "_native_register_runtime_stack_callback",
    _native_register_runtime_stack_callback,
    0
  );
  rb_define_singleton_method(
    runtime_stacks_class,
    "_native_is_runtime_callback_registered",
    _native_is_runtime_callback_registered,
    0
  );
}


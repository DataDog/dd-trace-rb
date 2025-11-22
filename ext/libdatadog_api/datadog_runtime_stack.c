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
#include "datadog_runtime_stack.h"
#include "datadog_ruby_common.h"
#include <sys/mman.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

// This was renamed in Ruby 3.2
#if !defined(ccan_list_for_each) && defined(list_for_each)
  #define ccan_list_for_each list_for_each
#endif

static VALUE _native_register_runtime_stack_callback(VALUE _self);
static VALUE _native_is_runtime_callback_registered(DDTRACE_UNUSED VALUE _self);

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

static bool is_safe_string_encoding(const char *ptr, long len) {
  if (!ptr || len <= 0) return false;

  // Sanity check to scan the first 128 bytes to check
  // for control characters and high bytes
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

static void ruby_runtime_stack_callback(
  void (*emit_frame)(const ddog_crasht_RuntimeStackFrame*)
) {

  VALUE current_thread = rb_thread_current();
  if (current_thread == Qnil) return;

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
          // Handle case where PC is NULL; using first line number like private_vm_api_access.c
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
            // to prevent crashes when calling rb_iseq_line_no
            if (pc_offset >= 0 && pc_offset <= iseq->body->iseq_size) {
              size_t pos = (size_t)pc_offset;
              if (pos > 0) {
                // Use pos-1 because PC points to next instruction
                pos--;
              }

              // Additional safety check before calling rb_iseq_line_no (PROF-11475 fix)
              if (pos < iseq->body->iseq_size) {
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

#ifdef RUBY_MJIT_HEADER
      // Only attempt method entry resolution on Ruby versions with MJIT header
      // where rb_vm_frame_method_entry is guaranteed to be available
      const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);
      if (me && is_pointer_readable(me, sizeof(rb_callable_method_entry_t))) {
        if (me->def && is_pointer_readable(me->def, sizeof(*me->def))) {
          if (me->def->original_id) {
            const char *method_name = rb_id2name(me->def->original_id);
            if (method_name && is_pointer_readable(method_name, strlen(method_name))) {
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
            // just get `Module` which is not that useful to us
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
#else
      // For Ruby versions without MJIT header, use our own rb_vm_frame_method_entry implementation
      const rb_callable_method_entry_t *me = rb_vm_frame_method_entry(cfp);
      if (me && is_pointer_readable(me, sizeof(rb_callable_method_entry_t))) {
        if (me->def && is_pointer_readable(me->def, sizeof(*me->def))) {
          if (me->def->original_id) {
            const char *method_name = rb_id2name(me->def->original_id);
            if (method_name && is_pointer_readable(method_name, strlen(method_name))) {
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
#endif

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

// Support code for Ruby versions without MJIT header (copied from private_vm_api_access.c)
#ifndef RUBY_MJIT_HEADER

#define MJIT_STATIC // No-op on older Rubies

#ifndef FALSE
# define FALSE false
#elif FALSE
# error FALSE must be false
#endif

#ifndef TRUE
# define TRUE true
#elif ! TRUE
# error TRUE must be true
#endif

static rb_callable_method_entry_t *
check_method_entry(VALUE obj, int can_be_svar)
{
    if (obj == Qfalse) return NULL;

    switch (imemo_type(obj)) {
      case imemo_ment:
        return (rb_callable_method_entry_t *)obj;
      case imemo_cref:
        return NULL;
      case imemo_svar:
        if (can_be_svar) {
            return check_method_entry(((struct vm_svar *)obj)->cref_or_me, FALSE);
        }
        // fallthrough
      default:
        return NULL;
    }
}

MJIT_STATIC const rb_callable_method_entry_t *
rb_vm_frame_method_entry(const rb_control_frame_t *cfp)
{
    const VALUE *ep = cfp->ep;
    rb_callable_method_entry_t *me;

    while (!VM_ENV_LOCAL_P(ep)) {
        if ((me = check_method_entry(ep[VM_ENV_DATA_INDEX_ME_CREF], FALSE)) != NULL) return me;
        ep = VM_ENV_PREV_EP(ep);
    }

    return check_method_entry(ep[VM_ENV_DATA_INDEX_ME_CREF], TRUE);
}
#endif // RUBY_MJIT_HEADER

static VALUE _native_register_runtime_stack_callback(DDTRACE_UNUSED VALUE _self) {
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

void datadog_runtime_stack_init(VALUE crashtracker_class) {
  rb_define_singleton_method(crashtracker_class, "_native_register_runtime_stack_callback", _native_register_runtime_stack_callback, 0);
  rb_define_singleton_method(crashtracker_class, "_native_is_runtime_callback_registered", _native_is_runtime_callback_registered, 0);
}

VALUE datadog_runtime_stack_register_callback(void) {
  return _native_register_runtime_stack_callback(Qnil);
}

VALUE datadog_runtime_stack_is_callback_registered(void) {
  return _native_is_runtime_callback_registered(Qnil);
}

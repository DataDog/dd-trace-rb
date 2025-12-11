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

#include <datadog/crashtracker.h>
#include "datadog_ruby_common.h"
#include "private_vm_api_access.h"
#include <sys/mman.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

static const rb_data_type_t *crashtracker_thread_data_type = NULL;

static void ruby_runtime_stack_callback(
  void (*emit_frame)(const ddog_crasht_RuntimeStackFrame*)
);

// Use a fixed, preallocated buffer for crash-time runtime stacks to avoid
// heap allocation in the signal/crash path.
static const int RUNTIME_STACK_MAX_FRAMES = 512;
static frame_info runtime_stack_buffer[512];

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

// This function is not necessarily Ruby specific. This will be moved to
// `libdatadog` in the future as a shared utility function.
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

static inline ddog_CharSlice char_slice_from_cstr(const char *cstr) {
  if (cstr == NULL) {
    return (ddog_CharSlice){.ptr = NULL, .len = 0};
  }
  return (ddog_CharSlice){.ptr = cstr, .len = strlen(cstr)};
}

// Heuristically validate a Ruby string VALUE before dereferencing it from crash context:
// 1) ensure it is actually a String heap object (no immediates/symbols)
// 2) confirm both the common header (RBasic) and the string payload (RString) live in
//    readable pages to avoid faulting while inspecting potentially corrupted memory
// 3) enforce upper bound for lengths we expect to emit (file names, function names)
static bool is_reasonable_string_size(VALUE str) {
  if (str == Qnil) return false;

  // After RB_TYPE_P confirms this VALUE is a heap string, the tagged VALUE is
  // guaranteed to be an aligned pointer, so casting to void* is equivalent to
  // RBASIC(str); we verify the object header is readable before touching it.
  if (!is_pointer_readable((const void *)str, sizeof(struct RBasic))) return false;

  // For strings, we need to check the full RString structure
  if (!is_pointer_readable((const void *)str, sizeof(struct RString))) return false;

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

// Collect the crashing thread's frames via ddtrace_rb_profile_frames into a static buffer, then emit
// them newest-first. If corruption is detected, emit placeholder frames so the crash report still
// completes. We lean on the Ruby VM helpers we already use for profiling and rely on crashtracker's
// safety nets so a failure here should not impact customers.
static void ruby_runtime_stack_callback(
  void (*emit_frame)(const ddog_crasht_RuntimeStackFrame*)
) {
  // Grab the Ruby thread we crashed on; crashtracker only runs once.
  VALUE current_thread = rb_thread_current();
  if (current_thread == Qnil) return;

  if (crashtracker_thread_data_type == NULL) return;

  rb_thread_t *th = (rb_thread_t *) rb_check_typeddata(current_thread, crashtracker_thread_data_type);
  if (!th || !is_pointer_readable(th, sizeof(*th))) return;

  // Use the profiling helper to gather frames into our static buffer.
  int frame_count = ddtrace_rb_profile_frames(
    current_thread,
    0,
    RUNTIME_STACK_MAX_FRAMES,
    runtime_stack_buffer
  );

  if (frame_count <= 0) return;

  for (int i = frame_count - 1; i >= 0; i--) {
    frame_info *info = &runtime_stack_buffer[i];

    if (info->is_ruby_frame) {
      const rb_iseq_t *iseq = (const rb_iseq_t *)info->as.ruby_frame.iseq;
      const char *function_name = "<unknown>";
      const char *file_name = "<unknown>";

      if (iseq && is_pointer_readable(iseq, sizeof(rb_iseq_t))) {
        VALUE name = rb_iseq_base_label(iseq);
        if (name != Qnil) {
          function_name = safe_string_ptr(name);
        }

        VALUE filename = rb_iseq_path(iseq);
        if (filename != Qnil) {
          file_name = safe_string_ptr(filename);
        }
      }

      ddog_crasht_RuntimeStackFrame frame = {
        .type_name = char_slice_from_cstr(NULL),
        .function = char_slice_from_cstr(function_name),
        .file = char_slice_from_cstr(file_name),
        .line = info->as.ruby_frame.line,
        .column = 0
      };

      emit_frame(&frame);
    } else {
      const char *function_name = "<C method>";
      const char *file_name = "<C extension>";

      if (info->as.native_frame.method_id) {
        const char *method_name = rb_id2name(info->as.native_frame.method_id);
        if (is_pointer_readable(method_name, 256)) {
          size_t method_name_len = strnlen(method_name, 256);
          if (method_name_len > 0 && method_name_len < 256) {
            function_name = method_name;
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
    }
  }
}

void crashtracking_runtime_stacks_init(void) {
  if (crashtracker_thread_data_type == NULL) {
    VALUE current_thread = rb_thread_current();
    if (current_thread == Qnil) return;

    const rb_data_type_t *thread_data_type = RTYPEDDATA_TYPE(current_thread);
    if (!thread_data_type) return;

    crashtracker_thread_data_type = thread_data_type;
  }

  // Register immediately so Ruby doesn't need to manage this explicitly.
  ddog_crasht_register_runtime_frame_callback(ruby_runtime_stack_callback);
}


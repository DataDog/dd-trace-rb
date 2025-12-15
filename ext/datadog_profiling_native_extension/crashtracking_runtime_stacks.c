// NOTE: This file is a part of the profiling native extension even though the
// runtime stacks feature is consumed by the crashtracker. The profiling
// extension already carries all the Ruby VM private header access and build
// plumbing required to safely poke at internal structures. Sharing that setup
// avoids duplicating another native extension with the same (fragile) access
// patterns, and keeps the overall install/build surface area smaller.
#include "extconf.h"

#if defined(__linux__)

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
#define RUNTIME_STACK_MAX_FRAMES 512
static frame_info runtime_stack_buffer[RUNTIME_STACK_MAX_FRAMES];

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

static uintptr_t cached_page_size = 0;

// TODO: This function is not necessarily Ruby specific. This will be moved to
// `libdatadog` in the future as a shared utility function.
static inline bool is_pointer_readable(const void *ptr, size_t size) {
  if (!ptr || size == 0) return false;

  uintptr_t page_size = cached_page_size;

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

static ddog_CharSlice safe_string_value(VALUE str) {
  if (str == Qnil) return DDOG_CHARSLICE_C("<nil>");

  // Validate object and payload readability in one check
  if (!is_pointer_readable((const void *)str, sizeof(struct RString))) return DDOG_CHARSLICE_C("<corrupted>");
  if (!RB_TYPE_P(str, T_STRING)) return DDOG_CHARSLICE_C("<not_string>");

  long len = RSTRING_LEN(str);
  if (len < 0 || len > 1024) return DDOG_CHARSLICE_C("<length_over_limit>");

  const char *ptr = RSTRING_PTR(str);
  if (!ptr) return DDOG_CHARSLICE_C("<null>");

  if (!is_pointer_readable(ptr, len > 0 ? len : 1)) return DDOG_CHARSLICE_C("<unreadable>");

  return (ddog_CharSlice){.ptr = ptr, .len = (size_t)len};
}

static void emit_placeholder_frame(
  void (*emit_frame)(const ddog_crasht_RuntimeStackFrame*),
  const char *label
) {
  ddog_crasht_RuntimeStackFrame frame = {
    .type_name = DDOG_CHARSLICE_C(""),
    .function = char_slice_from_cstr(label),
    .file = DDOG_CHARSLICE_C("<unknown>"),
    .line = 0,
    .column = 0
  };
  emit_frame(&frame);
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

  if (!rb_typeddata_is_kind_of(current_thread, crashtracker_thread_data_type)) {
    emit_placeholder_frame(emit_frame, "<runtime stack not found>");
    return;
  }

  // Use the profiling helper to gather frames into our static buffer.
  int frame_count = ddtrace_rb_profile_frames(
    current_thread,
    0,
    RUNTIME_STACK_MAX_FRAMES,
    runtime_stack_buffer
  );

  if (frame_count <= 0) {
    emit_placeholder_frame(emit_frame, "<runtime stack not found>");
    return;
  }

  bool truncated = frame_count >= RUNTIME_STACK_MAX_FRAMES;

  for (int i = frame_count - 1; i >= 0; i--) {
    if (truncated && i == 0) {
      emit_placeholder_frame(emit_frame, "<truncated frames>");
      return;
    }

    frame_info *info = &runtime_stack_buffer[i];

    if (info->is_ruby_frame) {
      const void *iseq = (const void *)info->as.ruby_frame.iseq;
      ddog_CharSlice function_slice = DDOG_CHARSLICE_C("<unknown>");
      ddog_CharSlice file_slice = DDOG_CHARSLICE_C("<unknown>");

      if (iseq && is_pointer_readable(iseq, sizeof_rb_iseq_t())) {
        function_slice = safe_string_value(ddtrace_iseq_base_label(iseq));
        file_slice = safe_string_value(ddtrace_iseq_path(iseq));
      }

      ddog_crasht_RuntimeStackFrame frame = {
        .type_name = DDOG_CHARSLICE_C(""),
        .function = function_slice,
        .file = file_slice,
        .line = info->as.ruby_frame.line,
        .column = 0
      };

      emit_frame(&frame);
    } else {
      ddog_CharSlice function_slice = DDOG_CHARSLICE_C("<C method>");
      ddog_CharSlice file_slice = DDOG_CHARSLICE_C("<C extension>");

      if (info->as.native_frame.method_id) {
        const char *method_name = rb_id2name(info->as.native_frame.method_id);
        if (is_pointer_readable(method_name, 256)) {
          size_t method_name_len = strnlen(method_name, 256);
          if (method_name_len > 0 && method_name_len < 256) {
            function_slice = char_slice_from_cstr(method_name);
          }
        }
      }

      ddog_crasht_RuntimeStackFrame frame = {
        .type_name = DDOG_CHARSLICE_C(""),
        .function = function_slice,
        .file = file_slice,
        .line = 0,
        .column = 0
      };

      emit_frame(&frame);
    }
  }
}

void crashtracking_runtime_stacks_init(void) {
  cached_page_size = (uintptr_t)sysconf(_SC_PAGESIZE);
  if (cached_page_size == 0 || (cached_page_size & (cached_page_size - 1u))) {
    cached_page_size = 4096;
  }

  if (crashtracker_thread_data_type == NULL) {
    VALUE current_thread = rb_thread_current();
    if (current_thread == Qnil) {
      rb_raise(rb_eRuntimeError, "crashtracking_runtime_stacks_init: rb_thread_current returned Qnil");
    }

    const rb_data_type_t *thread_data_type = RTYPEDDATA_TYPE(current_thread);
    if (!thread_data_type) {
      rb_raise(rb_eRuntimeError, "crashtracking_runtime_stacks_init: RTYPEDDATA_TYPE returned NULL");
    }

    crashtracker_thread_data_type = thread_data_type;
  }

  // Register immediately so Ruby doesn't need to manage this explicitly.
  ddog_crasht_register_runtime_frame_callback(ruby_runtime_stack_callback);
}

#else
// Keep init symbol to satisfy linkage on non linux platforms, but do nothing
void crashtracking_runtime_stacks_init(void) {}
#endif


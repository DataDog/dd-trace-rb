// Implements a way of mapping a `pthread_t` in Linux to that thread's id -- tid, what you'd get from calling `gettid()`.
//
// This is not needed when a thread can get its own tid (by calling `gettid()`) -- our setup is only useful
// when a different thread B wants to know thread A's tid and only has the `pthread_t` for A, as happens for our profiler.
// (In Ruby 3.1 and above, Ruby calls `gettid()` when it a thread starts and records it, so this is not needed.)
//
// The libc implementations for Linux don't expose any way to get the tid for another thread.
// The intuition for our implementation is that both glibc and musl (the two more common libc implementations) actually
// do record this information for their own internal bookkeeping.
//
// Thus, the objective of this file is to peek inside the internal libc bookkeeping and return the information we need,
// as well as gracefully fail (AND NEVER CRASH) if the libc doesn't have this information, or we're not on Linux.

// ### Implementation
//
// So where is the tid stored on glibc and musl? For both of them, the `pthread_t` is typedef'd as an opaque integer,
// but for both of them, internally, the `pthread_t` is actually a `struct pthread *` that got cast into `pthread_t`.
// And somewhere inside that `struct pthread`, for both of them, is a field containing the `tid`.
// The layout of `struct pthread` is internal to the libc and not available in any header, so we need to figure it out
// in another way.
//
// Thus, this file provides two APIs:
// * `setup_linux_tid_from_pthread_offset` tries to discover the offset inside the `struct pthread` where the tid lives
//   (or -1 if not found/available)
// * `linux_tid_from`, given a `pthread_t` and a valid offset, returns the libc-internal `tid` information
//   (or -1 if not found/available)
//
// The intuition for figuring out the offset inside in `setup_linux_tid_from_pthread_offset` is that:
//
// 1. We can take a thread for which we DO know the tid, like the caller thread. Let's call it a reference thread.
// 2. We cast the reference thread's `pthread_t` to a pointer.
// 3. We follow that pointer and all goes well, we expect that at some offset from the memory `pthread_t` was pointing
//    at, we'll find the reference thread's tid.
// 4. Since the offset for every thread is the same (the layout of `struct pthread` doesn't change), we can now use this
//    offset to get the tid any other thread we want, given its `pthread_t`.
//
// And after step 4, if we were successful, we can call `linux_tid_from` with the offset to get the tid for any thread.
//
// #### How to make this safe
//
// You may be asking yourself, isn't what is described above incredibly unsafe and crashy in C? The answer is yes, if
// not done carefully. Specifically, it's crashy if we just cast `pthread_t` to a `void *`, dereference it, and hope for
// the best. But that's not what we're doing.
//
// What we do instead is use the very powerful `process_vm_readv` Linux system API that allows you to read memory
// from a process in a safe manner -- e.g., it either succeeds or it returns a failure status code, rather than
// triggering a segfault. (This API is actually able to read memory from any process, and is usually used to read memory
// from other processes, but can actually be used to read memory from the current process in this safe way).
//
// Thus, we can safely read the opaque block of memory that we suspect exists at that memory location, and search it for
// the info we want.
//
// Note: As documented in the man page, `process_vm_readv` needs special permissions and may not work on every Linux
// setup. This is handled below as any other error, and just makes this approach not usable in those machines.
//
// #### How to make this accurate
//
// After reading memory safely, you may wonder -- what if the tid is really low, like 1 or 2 (e.g. in a docker container)
// and there's other things inside `struct pthread` that may be set to 1 or 2? Won't that cause us to find the wrong
// offset?
//
// To solve this issue, inside `setup_linux_tid_from_pthread_offset` we actually don't use only the current thread as
// a reference thread -- we actually use REFERENCE_THREADS_COUNT (3, as of this writing) threads as a reference.
//
// The thinking is -- the odds are really low that multiple different threads have, at the same offset, a value that is
// exactly same as their tid, but not their tid.
//
// That's why we document in the `linux_tid_from_pthread.h` that it's rare-but-not-theoretically-impossible that the
// result we get is wrong.
//
// ---

#ifdef __linux__

  #define _GNU_SOURCE
  #include <pthread.h>
  #include <stdbool.h>
  #include <stdio.h>
  #include <sys/syscall.h>
  #include <sys/uio.h>
  #include <unistd.h>
  #include "linux_tid_from_pthread.h"

  // This value seems enough for both glibc and musl (and it's safe to read with `process_vm_readv`)
  // Must be a multiple of sizeof(pid_t)
  #define STRUCT_PTHREAD_READ_SIZE 2048

  #define REFERENCE_THREADS_COUNT 3

  struct tid_probe_info {
    pid_t tid;
    char buffer[STRUCT_PTHREAD_READ_SIZE];
    bool buffer_read_success;
  };

  static void *collect_tid_probe_info(void *tid_probe_info);
  static short find_tid_offset_in_buffer(struct tid_probe_info *tid_probe_info, short start_position);
  static bool read_struct_pthread(pthread_t thread, void *struct_pthread_buffer);
  static pid_t get_tid_from_buffer(void *struct_pthread_buffer, short offset);

  short setup_linux_tid_from_pthread_offset(void) {
    int error;
    struct tid_probe_info reference_threads_probe_info[REFERENCE_THREADS_COUNT];

    // We use the current thread as the first reference thread
    collect_tid_probe_info(&reference_threads_probe_info[0]);
    if (!reference_threads_probe_info[0].buffer_read_success) return -1;

    // ...and then we create a few more to act as extra references
    for (int i = 1; i < REFERENCE_THREADS_COUNT; i++) {
      pthread_t reference_thread;
      error = pthread_create(&reference_thread, NULL, collect_tid_probe_info, &reference_threads_probe_info[i]);
      if (error) return -1;
      error = pthread_join(reference_thread, NULL);
      if (error || !reference_threads_probe_info[i].buffer_read_success) return -1;
    }

    short candidate_tid_offset = 0;

    // We try to find an offset that contains the expected tid for all reference threads. If we get to the end of the
    // buffer before finding such an offset, the `thread_offset` will be -1 and we'll report back an error.
    while (candidate_tid_offset >= 0) {
      bool all_offsets_match = true;

      for (int i = 0; i < REFERENCE_THREADS_COUNT; i++) {
        short thread_offset = find_tid_offset_in_buffer(&reference_threads_probe_info[i], candidate_tid_offset);

        if (thread_offset != candidate_tid_offset) {
          all_offsets_match = false;
          candidate_tid_offset = thread_offset;
        }
      }

      if (all_offsets_match) break;
    }

    return candidate_tid_offset;
  }

  pid_t linux_tid_from(pthread_t thread, short offset) {
    char buffer[STRUCT_PTHREAD_READ_SIZE];
    read_struct_pthread(thread, buffer);
    return get_tid_from_buffer(buffer, offset);
  }

  static void *collect_tid_probe_info(void *tid_probe_info) {
    struct tid_probe_info *result = (struct tid_probe_info *) tid_probe_info;

    result->tid = ddtrace_gettid();
    result->buffer_read_success = read_struct_pthread(pthread_self(), result->buffer);

    return NULL;
  }

  bool read_safely(void *read_from_ptr, void *read_into_buffer, short buffer_size) {
    struct iovec read_into = {.iov_base = read_into_buffer, .iov_len = buffer_size};
    struct iovec read_from = {.iov_base = read_from_ptr, .iov_len = buffer_size};

    int unused_flags = 0;
    int number_of_iovecs = 1;

    short num_read = process_vm_readv(ddtrace_gettid(), &read_into, number_of_iovecs, &read_from, number_of_iovecs, unused_flags);

    return num_read == buffer_size;
  }

  static bool read_struct_pthread(pthread_t thread, void *struct_pthread_buffer) {
    return read_safely((void *) thread, struct_pthread_buffer, STRUCT_PTHREAD_READ_SIZE);
  }

  static short find_tid_offset_in_buffer(struct tid_probe_info *tid_probe_info, short start_position) {
    if (!tid_probe_info->buffer_read_success) return -1;

    short buffer_size = STRUCT_PTHREAD_READ_SIZE;
    pid_t *struct_pthread_base = (pid_t *) tid_probe_info->buffer;
    pid_t reference_tid = tid_probe_info->tid;

    for (pid_t *tid_ptr = struct_pthread_base + start_position; tid_ptr < struct_pthread_base + (buffer_size / sizeof(pid_t)); tid_ptr++) {
      if (*tid_ptr == reference_tid) { return tid_ptr - struct_pthread_base; }
    }

    return -1;
  }

  static pid_t get_tid_from_buffer(void *struct_pthread_buffer, short offset) {
    if (offset < 0 || ((size_t) offset) >= STRUCT_PTHREAD_READ_SIZE / sizeof(pid_t)) return -1;

    pid_t result = *((pid_t *) struct_pthread_buffer + offset);

    return result > 0 ? result : -1; // Normalize failures to -1
  }

  pid_t ddtrace_gettid(void) {
    // Note: This is the same as gettid() but older libc versions didn't have the nice helper so we have our own
    // so we can support them.
    return syscall(SYS_gettid);
  }

#else // Fallback for when not on Linux

  #include "linux_tid_from_pthread.h"
  #include "helpers.h"

  short setup_linux_tid_from_pthread_offset(void) { return -1; }
  pid_t linux_tid_from(DDTRACE_UNUSED pthread_t thread, DDTRACE_UNUSED short offset) { return -1; }
  bool read_safely(void *read_from_ptr, void *read_into_buffer, short buffer_size) { return false; }
  pid_t ddtrace_gettid(void) { return -1; }

#endif // __linux__

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <ruby.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>
#include <datadog/library-config.h>

#include "datadog_ruby_common.h"
#include "otel_thread_context.h"

#ifdef __linux__
  #include <sys/prctl.h>

  #ifndef PR_SET_VMA
    #define PR_SET_VMA 0x53564d41
  #endif

  #ifndef PR_SET_VMA_ANON_NAME
    #define PR_SET_VMA_ANON_NAME 0
  #endif
#endif

#define OTEL_CONTEXT_MAX_PAYLOAD_SIZE (1u << 20)

typedef struct {
  char signature[8];
  uint32_t version;
  uint32_t payload_size;
  uint64_t monotonic_published_at_ns;
  uint64_t payload_ptr;
} otel_context_header;

typedef struct {
  uintptr_t mapping_address;
  otel_context_header header;
  uint8_t *payload;
} otel_context_snapshot;

static bool otel_context_header_layout_supported(void) {
  return sizeof(otel_context_header) == 32 &&
    __alignof__(otel_context_header) == 8 &&
    offsetof(otel_context_header, signature) == 0 &&
    offsetof(otel_context_header, version) == 8 &&
    offsetof(otel_context_header, payload_size) == 12 &&
    offsetof(otel_context_header, monotonic_published_at_ns) == 16 &&
    offsetof(otel_context_header, payload_ptr) == 24;
}

static VALUE _native_store_tracer_metadata(int argc, VALUE *argv, DDTRACE_UNUSED VALUE _self);
static VALUE _native_to_rb_int(DDTRACE_UNUSED VALUE _self, VALUE tracer_memfd);
static VALUE _native_close_tracer_memfd(DDTRACE_UNUSED VALUE _self, VALUE tracer_memfd, VALUE logger);

static bool find_otel_context_mapping(uintptr_t *address, size_t *size) {
  *address = 0;
  *size = 0;

  if (!otel_context_header_layout_supported()) return false;

  FILE *maps = fopen("/proc/self/maps", "r");
  if (maps == NULL) return false;

  char *line = NULL;
  size_t capacity = 0;
  uintptr_t candidate_address = 0;
  size_t candidate_size = 0;
  bool found = false;
  bool success = false;

  while (getline(&line, &capacity, maps) != -1) {
    uintptr_t start;
    uintptr_t end;
    char permissions[5];
    int pathname_offset = 0;

    int fields = sscanf(
      line,
      "%" SCNxPTR "-%" SCNxPTR " %4s %*s %*s %*s %n",
      &start,
      &end,
      permissions,
      &pathname_offset
    );

    if (fields != 3 || pathname_offset == 0) goto cleanup;

    char *pathname = line + pathname_offset;
    pathname[strcspn(pathname, "\n")] = '\0';

    const char deleted_suffix[] = " (deleted)";
    size_t suffix_length = sizeof(deleted_suffix) - 1;
    size_t pathname_length = strlen(pathname);

    if (
      pathname_length >= suffix_length &&
      strcmp(pathname + pathname_length - suffix_length, deleted_suffix) == 0
    ) {
      pathname[pathname_length - suffix_length] = '\0';
    }

    bool matches =
      strcmp(pathname, "/memfd:OTEL_CTX") == 0 ||
      strcmp(pathname, "[anon:OTEL_CTX]") == 0 ||
      strcmp(pathname, "[anon_shmem:OTEL_CTX]") == 0;

    if (!matches) continue;
    if (found) goto cleanup;

    if (
      start == 0 ||
      end <= start ||
      start % __alignof__(otel_context_header) != 0 ||
      end - start < sizeof(otel_context_header) ||
      permissions[0] != 'r' ||
      permissions[1] != 'w'
    ) {
      goto cleanup;
    }

    candidate_address = start;
    candidate_size = (size_t)(end - start);
    found = true;
  }

  success = found && feof(maps) && !ferror(maps);

cleanup:
  free(line);
  if (fclose(maps) != 0) success = false;

  if (success) {
    *address = candidate_address;
    *size = candidate_size;
  }

  return success;
}

static bool otel_context_header_valid(const otel_context_header *header) {
  return memcmp(header->signature, "OTEL_CTX", sizeof(header->signature)) == 0 &&
    header->version == 2 &&
    header->monotonic_published_at_ns != 0 &&
    header->payload_size > 0 &&
    header->payload_size <= OTEL_CONTEXT_MAX_PAYLOAD_SIZE &&
    header->payload_ptr != 0 &&
    header->payload_ptr <= UINTPTR_MAX - header->payload_size;
}

static bool read_otel_context_memory(uintptr_t address, void *destination, size_t size) {
  if (
    address == 0 ||
    destination == NULL ||
    size == 0 ||
    size > OTEL_CONTEXT_MAX_PAYLOAD_SIZE ||
    size > (size_t)SSIZE_MAX ||
    address > UINTPTR_MAX - size
  ) {
    return false;
  }

  off_t offset = (off_t)address;
  if (offset < 0 || (uintmax_t)offset != (uintmax_t)address) return false;

  int fd;
  do {
    fd = open("/proc/self/mem", O_RDONLY | O_CLOEXEC);
  } while (fd == -1 && errno == EINTR);
  if (fd == -1) return false;

  ssize_t bytes_read;
  do {
    bytes_read = pread(fd, destination, size, offset);
  } while (bytes_read == -1 && errno == EINTR);

  bool success = bytes_read >= 0 && (size_t)bytes_read == size;
  if (close(fd) != 0) success = false;
  return success;
}

DDTRACE_UNUSED static bool read_otel_context_snapshot(otel_context_snapshot *snapshot) {
  *snapshot = (otel_context_snapshot){0};

  uintptr_t mapping_address;
  size_t mapping_size;
  if (!find_otel_context_mapping(&mapping_address, &mapping_size)) return false;

  uintptr_t timestamp_address = mapping_address + offsetof(otel_context_header, monotonic_published_at_ns);
  uint64_t published_before;
  if (!read_otel_context_memory(timestamp_address, &published_before, sizeof(published_before))) return false;
  if (published_before == 0) return false;

  __atomic_thread_fence(__ATOMIC_SEQ_CST);

  otel_context_header header;
  if (!read_otel_context_memory(mapping_address, &header, sizeof(header))) return false;
  if (!otel_context_header_valid(&header)) return false;
  if (header.monotonic_published_at_ns != published_before) return false;

  uint8_t *payload = malloc(header.payload_size);
  if (payload == NULL) return false;

  if (!read_otel_context_memory((uintptr_t)header.payload_ptr, payload, header.payload_size)) goto cleanup;

  __atomic_thread_fence(__ATOMIC_SEQ_CST);

  uint64_t published_after;
  if (!read_otel_context_memory(timestamp_address, &published_after, sizeof(published_after))) goto cleanup;
  if (published_after != published_before) goto cleanup;

  snapshot->mapping_address = mapping_address;
  snapshot->header = header;
  snapshot->payload = payload;
  return true;

cleanup:
  free(payload);
  return false;
}

// Requires the GVL; libdatadog v44's C metadata API emits no threadlocal attributes.
static void publish_otel_threadlocal_metadata(void) {
  #if defined(__linux__) && defined(CLOCK_BOOTTIME)
    if (!otel_thread_context_was_enabled()) return;

    static const uint8_t attributes[] =
      "\x12\x2e\x0a\x1a" "threadlocal.schema_version"
      "\x12\x10\x0a\x0e" "tlsdesc_v1_dev"
      "\x12\x41\x0a\x1d" "threadlocal.attribute_key_map"
      "\x12\x20\x2a\x1e\x0a\x1c\x0a\x1a" "datadog.local_root_span_id";

    const size_t attributes_size = sizeof(attributes) - 1;

    // Retained for process lifetime: external readers may still hold an older payload pointer.
    static uint8_t *published_payload = NULL;

    otel_context_snapshot snapshot;
    if (!read_otel_context_snapshot(&snapshot)) return;
    if (snapshot.header.payload_ptr == (uint64_t)(uintptr_t)published_payload) goto cleanup;
    if (snapshot.header.payload_size > OTEL_CONTEXT_MAX_PAYLOAD_SIZE - attributes_size) goto cleanup;
    if (snapshot.header.monotonic_published_at_ns == UINT64_MAX) goto cleanup;

    struct timespec now;
    if (clock_gettime(CLOCK_BOOTTIME, &now) != 0) goto cleanup;
    if (now.tv_sec < 0 || now.tv_nsec < 0 || now.tv_nsec >= 1000000000L) goto cleanup;

    uint64_t seconds = (uint64_t)now.tv_sec;
    uint64_t nanoseconds = (uint64_t) now.tv_nsec;
    if (seconds > (UINT64_MAX - nanoseconds) / UINT64_C(1000000000)) goto cleanup;

    uint64_t published_at = seconds * UINT64_C(1000000000) + nanoseconds;
    if (published_at <= snapshot.header.monotonic_published_at_ns) {
      published_at = snapshot.header.monotonic_published_at_ns + 1;
    }

    if (published_payload == NULL) {
      published_payload = malloc(OTEL_CONTEXT_MAX_PAYLOAD_SIZE);
      if (published_payload == NULL) goto cleanup;
    }

    size_t payload_size = snapshot.header.payload_size + attributes_size;
    memcpy(published_payload, snapshot.payload, snapshot.header.payload_size);
    memcpy(published_payload + snapshot.header.payload_size, attributes, attributes_size);

    otel_context_header current;
    if (!read_otel_context_memory(snapshot.mapping_address, &current, sizeof(current))) goto cleanup;
    if (memcmp(&current, &snapshot.header, sizeof(current)) != 0) goto cleanup;

    otel_context_header *header = (otel_context_header *)snapshot.mapping_address;
    uint64_t expected = snapshot.header.monotonic_published_at_ns;
    if (!__atomic_compare_exchange_n(
      &header->monotonic_published_at_ns, &expected, 0, false, __ATOMIC_RELAXED, __ATOMIC_RELAXED
    )) goto cleanup;

    __atomic_thread_fence(__ATOMIC_SEQ_CST);
    __atomic_store_n(&header->payload_ptr, (uint64_t)(uintptr_t)published_payload, __ATOMIC_RELAXED);
    __atomic_store_n(&header->payload_size, (uint32_t)payload_size, __ATOMIC_RELAXED);
    __atomic_thread_fence(__ATOMIC_SEQ_CST);
    __atomic_store_n(&header->monotonic_published_at_ns, published_at, __ATOMIC_RELAXED);

    // The agent observes the naming attempt even when the kernel rejects it.
    (void)prctl(
      PR_SET_VMA, (unsigned long)PR_SET_VMA_ANON_NAME,
      (unsigned long)snapshot.mapping_address, (unsigned long)sizeof(*header), "OTEL_CTX"
    );

  cleanup:
    free(snapshot.payload);
  #endif
}

static void tracer_memfd_free(void *ptr) {
  int *fd = (int *)ptr;
  if (*fd != -1) {
    close(*fd);
  }
  ruby_xfree(ptr);
}

static const rb_data_type_t tracer_memfd_type = {
  .wrap_struct_name = "Datadog::Core::ProcessDiscovery::TracerMemfd",
  .function = {
    .dfree = tracer_memfd_free,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

void process_discovery_init(VALUE core_module) {
  VALUE process_discovery_module = rb_define_module_under(core_module, "ProcessDiscovery");
  VALUE tracer_memfd_class = rb_define_class_under(process_discovery_module, "TracerMemfd", rb_cObject);
  rb_undef_alloc_func(tracer_memfd_class); // Class cannot be instantiated from Ruby

  rb_define_module_function(process_discovery_module, "_native_store_tracer_metadata", _native_store_tracer_metadata, -1);
  rb_define_module_function(process_discovery_module, "_native_to_rb_int", _native_to_rb_int, 1);
  rb_define_module_function(process_discovery_module, "_native_close_tracer_memfd", _native_close_tracer_memfd, 2);
}

static VALUE _native_store_tracer_metadata(int argc, VALUE *argv, VALUE self) {
  VALUE logger;
  VALUE options;
  rb_scan_args(argc, argv, "1:", &logger, &options);
  if (options == Qnil) options = rb_hash_new();

  VALUE runtime_id = rb_hash_fetch(options, ID2SYM(rb_intern("runtime_id")));
  VALUE tracer_language = rb_hash_fetch(options, ID2SYM(rb_intern("tracer_language")));
  VALUE tracer_version = rb_hash_fetch(options, ID2SYM(rb_intern("tracer_version")));
  VALUE hostname = rb_hash_fetch(options, ID2SYM(rb_intern("hostname")));
  VALUE service_name = rb_hash_fetch(options, ID2SYM(rb_intern("service_name")));
  VALUE service_env = rb_hash_fetch(options, ID2SYM(rb_intern("service_env")));
  VALUE service_version = rb_hash_fetch(options, ID2SYM(rb_intern("service_version")));
  VALUE process_tags = rb_hash_fetch(options, ID2SYM(rb_intern("process_tags")));
  VALUE container_id = rb_hash_fetch(options, ID2SYM(rb_intern("container_id")));

  ENFORCE_TYPE(runtime_id, T_STRING);
  ENFORCE_TYPE(tracer_language, T_STRING);
  ENFORCE_TYPE(tracer_version, T_STRING);
  ENFORCE_TYPE(hostname, T_STRING);
  ENFORCE_TYPE(service_name, T_STRING);
  ENFORCE_TYPE(service_env, T_STRING);
  ENFORCE_TYPE(service_version, T_STRING);
  ENFORCE_TYPE(process_tags, T_STRING);
  ENFORCE_TYPE(container_id, T_STRING);

  void* builder = ddog_tracer_metadata_new();

  ddog_tracer_metadata_set(builder, DDOG_METADATA_KIND_RUNTIME_ID, StringValueCStr(runtime_id));
  ddog_tracer_metadata_set(builder, DDOG_METADATA_KIND_TRACER_LANGUAGE, StringValueCStr(tracer_language));
  ddog_tracer_metadata_set(builder, DDOG_METADATA_KIND_TRACER_VERSION, StringValueCStr(tracer_version));
  ddog_tracer_metadata_set(builder, DDOG_METADATA_KIND_HOSTNAME, StringValueCStr(hostname));
  ddog_tracer_metadata_set(builder, DDOG_METADATA_KIND_SERVICE_NAME, StringValueCStr(service_name));
  ddog_tracer_metadata_set(builder, DDOG_METADATA_KIND_SERVICE_ENV, StringValueCStr(service_env));
  ddog_tracer_metadata_set(builder, DDOG_METADATA_KIND_SERVICE_VERSION, StringValueCStr(service_version));
  ddog_tracer_metadata_set(builder, DDOG_METADATA_KIND_PROCESS_TAGS, StringValueCStr(process_tags));
  ddog_tracer_metadata_set(builder, DDOG_METADATA_KIND_CONTAINER_ID, StringValueCStr(container_id));

  ddog_Result_TracerMemfdHandle result = ddog_tracer_metadata_store(builder);
  ddog_tracer_metadata_free(builder);

  publish_otel_threadlocal_metadata();

  if (result.tag == DDOG_RESULT_TRACER_MEMFD_HANDLE_ERR_TRACER_MEMFD_HANDLE) {
    rb_funcall(logger, rb_intern("debug"), 1, rb_sprintf("Failed to store the tracer configuration in a memory file descriptor: %"PRIsVALUE, get_error_details_and_drop(&result.err)));
    return Qnil;
  }

  // &result.ok is a ddog_TracerMemfdHandle, which is a struct only containing int fd, which is a file descriptor
  // We should just return the fd
  int *fd = ruby_xmalloc(sizeof(int));

  *fd = result.ok.fd;
  VALUE tracer_memfd_class = rb_const_get(self, rb_intern("TracerMemfd"));
  VALUE tracer_memfd = TypedData_Wrap_Struct(tracer_memfd_class, &tracer_memfd_type, fd);
  return tracer_memfd;
}

static VALUE _native_to_rb_int(DDTRACE_UNUSED VALUE _self, VALUE tracer_memfd) {
  int *fd;
  TypedData_Get_Struct(tracer_memfd, int, &tracer_memfd_type, fd);
  return INT2NUM(*fd);
}

static VALUE _native_close_tracer_memfd(DDTRACE_UNUSED VALUE _self, VALUE tracer_memfd, VALUE logger) {
  int *fd;
  TypedData_Get_Struct(tracer_memfd, int, &tracer_memfd_type, fd);
  if (*fd == -1) {
    rb_funcall(logger, rb_intern("debug"), 1, rb_sprintf("The tracer configuration memory file descriptor has already been closed"));
    return Qnil;
  }

  int close_result = close(*fd);
  *fd = -1;

  if (close_result == -1) {
    rb_funcall(logger, rb_intern("debug"), 1, rb_sprintf("Failed to close the tracer configuration memory file descriptor: %s", strerror(errno)));
    return Qnil;
  }

  return Qnil;
}

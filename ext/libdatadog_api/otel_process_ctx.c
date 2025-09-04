// Unless explicitly stated otherwise all files in this repository are licensed under the Apache License (Version 2.0).
// This product includes software developed at Datadog (https://www.datadoghq.com/) Copyright 2025 Datadog, Inc.

#include "otel_process_ctx.h"

#ifndef _GNU_SOURCE
  #define _GNU_SOURCE
#endif

#ifdef __cplusplus
  #include <atomic>
  using std::atomic_thread_fence;
  using std::memory_order_seq_cst;
#else
  #include <stdatomic.h>
#endif
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/prctl.h>
#include <unistd.h>

#define ADD_QUOTES_HELPER(x) #x
#define ADD_QUOTES(x) ADD_QUOTES_HELPER(x)

#ifndef PR_SET_VMA
  #define PR_SET_VMA            0x53564d41
  #define PR_SET_VMA_ANON_NAME  0
#endif

static const otel_process_ctx_data empty_data = {
  .deployment_environment_name = NULL,
  .host_name = NULL,
  .service_instance_id = NULL,
  .service_name = NULL,
  .service_version = NULL,
  .telemetry_sdk_language = NULL,
  .telemetry_sdk_version = NULL,
  .telemetry_sdk_name = NULL,
  .resources = NULL
};

#if (defined(OTEL_PROCESS_CTX_NOOP) && OTEL_PROCESS_CTX_NOOP) || !defined(__linux__)
  // NOOP implementations when OTEL_PROCESS_CTX_NOOP is defined or not on Linux

  otel_process_ctx_result otel_process_ctx_publish(const otel_process_ctx_data *data) {
    (void) data; // Suppress unused parameter warning
    return (otel_process_ctx_result) {.success = false, .error_message = "OTEL_PROCESS_CTX_NOOP mode is enabled - no-op implementation (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
  }

  bool otel_process_ctx_drop_current(void) {
    return true; // Nothing to do, this always succeeds
  }

  #ifndef OTEL_PROCESS_CTX_NO_READ
    otel_process_ctx_read_result otel_process_ctx_read(void) {
      return (otel_process_ctx_read_result) {.success = false, .error_message = "OTEL_PROCESS_CTX_NOOP mode is enabled - no-op implementation (" __FILE__ ":" ADD_QUOTES(__LINE__) ")", .data = empty_data};
    }

    bool otel_process_ctx_read_drop(otel_process_ctx_read_result *result) {
      (void) result; // Suppress unused parameter warning
      return false;
    }
  #endif // OTEL_PROCESS_CTX_NO_READ
#else // OTEL_PROCESS_CTX_NOOP

/**
 * The process context data that's written into the published anonymous mapping.
 *
 * An outside-of-process reader will read this struct + otel_process_payload to get the data.
 */
typedef struct __attribute__((packed, aligned(8))) {
  char otel_process_ctx_signature[8]; // Always "OTEL_CTX"
  // TODO: Is version useful? Should we just get rid of it?
  uint32_t otel_process_ctx_version;  // Always > 0, incremented when the data structure changes
  // TODO: Is size useful? Should we just get rid of it?
  uint32_t otel_process_payload_size; // Always > 0, size of storage
  // TODO: Should we just inline the data in the mapping itself?
  char *otel_process_payload;         // Always non-null, points to the storage for the data; expected to be a msgpack map of string key/value pairs, null-terminated
} otel_process_ctx_mapping;

/**
 * The full state of a published process context.
 *
 * This is returned as an opaque type to the caller.
 *
 * It is used to store the all data for the process context and that needs to be kept around while the context is published.
 */
typedef struct {
  // The pid of the process that published the context.
  pid_t publisher_pid;
  // The actual mapping of the process context. Note that because we `madvise(..., MADV_DONTFORK)` this mapping is not
  // propagated to child processes and thus `mapping` is only valid on the process that published the context.
  otel_process_ctx_mapping *mapping;
  // The process context payload.
  char *payload;
} otel_process_ctx_state;

/**
 * Only one context is active, so we keep its state as a global.
 */
static otel_process_ctx_state published_state;

static otel_process_ctx_result otel_process_ctx_encode_payload(char **out, uint32_t *out_size, otel_process_ctx_data data);

// We use a mapping size of 2 pages explicitly as a hint when running on legacy kernels that don't support the
// PR_SET_VMA_ANON_NAME prctl call; see below for more details.
static long size_for_mapping(void) {
  long page_size_bytes = sysconf(_SC_PAGESIZE);
  if (page_size_bytes < 4096) {
    return -1;
  }
  return page_size_bytes * 2;
}

// The process context is designed to be read by an outside-of-process reader. Thus, for concurrency purposes the steps
// on this method are ordered in a way to avoid races, or if not possible to avoid, to allow the reader to detect if there was a race.
otel_process_ctx_result otel_process_ctx_publish(const otel_process_ctx_data *data) {
  // Step: Drop any previous context it if it exists
  // No state should be around anywhere after this step.
  if (!otel_process_ctx_drop_current()) {
    return (otel_process_ctx_result) {.success = false, .error_message = "Failed to drop previous context (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
  }

  // Step: Determine size for mapping
  long mapping_size = size_for_mapping();
  if (mapping_size == -1) {
    return (otel_process_ctx_result) {.success = false, .error_message = "Failed to get page size (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
  }

  // Step: Prepare the payload to be published
  // The payload SHOULD be ready and valid before trying to actually create the mapping.
  if (!data) return (otel_process_ctx_result) {.success = false, .error_message = "otel_process_ctx_data is NULL (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
  uint32_t payload_size = 0;
  otel_process_ctx_result result = otel_process_ctx_encode_payload(&published_state.payload, &payload_size, *data);
  if (!result.success) return result;

  // Step: Create the mapping
  published_state.publisher_pid = getpid(); // This allows us to detect in forks that we shouldn't touch the mapping
  published_state.mapping = (otel_process_ctx_mapping *)
    mmap(NULL, mapping_size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (published_state.mapping == MAP_FAILED) {
    otel_process_ctx_drop_current();
    return (otel_process_ctx_result) {.success = false, .error_message = "Failed to allocate mapping (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
  }

  // Step: Setup MADV_DONTFORK
  // This ensures that the mapping is not propagated to child processes (they should call update/publish again).
  if (madvise(published_state.mapping, mapping_size, MADV_DONTFORK) == -1) {
    if (otel_process_ctx_drop_current()) {
      return (otel_process_ctx_result) {.success = false, .error_message = "Failed to setup MADV_DONTFORK (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
    } else {
      return (otel_process_ctx_result) {.success = false, .error_message = "Failed to drop previous context (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
    }
  }

  // Step: Populate the mapping
  // The payload and any extra fields must come first and not be reordered with the signature by the compiler.
  *published_state.mapping = (otel_process_ctx_mapping) {
    .otel_process_ctx_signature = {0}, // Set in "Step: Populate the signature into the mapping" below
    .otel_process_ctx_version = 1,
    .otel_process_payload_size = payload_size,
    .otel_process_payload = published_state.payload
  };

  // Step: Synchronization - Mapping has been filled and is missing signature
  // Make sure the initialization of the mapping + payload above does not get reordered with setting the signature below. Setting
  // the signature is what tells an outside reader that the context is fully published.
  atomic_thread_fence(memory_order_seq_cst);

  // Step: Populate the signature into the mapping
  // The signature must come last and not be reordered with the fields above by the compiler. After this step, external readers
  // can read the signature and know that the payload is ready to be read.
  memcpy(published_state.mapping->otel_process_ctx_signature, "OTEL_CTX", sizeof(published_state.mapping->otel_process_ctx_signature));

  // Step: Change permissions on the mapping to only read permission
  // We've observed the combination of anonymous mapping + a given number of pages + read-only permission is not very common,
  // so this is left as a hint for when running on older kernels and the naming the mapping feature below isn't available.
  // For modern kernels, doing this is harmless so we do it unconditionally.
  if (mprotect(published_state.mapping, mapping_size, PROT_READ) == -1) {
    if (otel_process_ctx_drop_current()) {
      return (otel_process_ctx_result) {.success = false, .error_message = "Failed to change permissions on mapping (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
    } else {
      return (otel_process_ctx_result) {.success = false, .error_message = "Failed to drop previous context (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
    }
  }

  // Step: Name the mapping so outside readers can:
  // * Find it by name
  // * Hook on prctl to detect when new mappings are published
  if (prctl(PR_SET_VMA, PR_SET_VMA_ANON_NAME, published_state.mapping, mapping_size, "OTEL_CTX") == -1) {
    // Naming an anonymous mapping is a Linux 5.17+ feature. On earlier versions, this method call can fail. Thus it's OK
    // for this to fail because:
    // 1. Things that hook on prctl are still able to see this call, even though it's not supported (TODO: Confirm this is actually the case)
    // 2. As a fallback, on older kernels, it's possible to scan the mappings and look for the "OTEL_CTX" signature in the memory itself,
    //    after observing the mapping has the expected number of pages and permissions.
  }

  // All done!

  return (otel_process_ctx_result) {.success = true, .error_message = NULL};
}

bool otel_process_ctx_drop_current(void) {
  otel_process_ctx_state state = published_state;

  // Zero out the state and make sure no operations below are reordered with zeroing
  published_state = (otel_process_ctx_state) {.publisher_pid = 0, .mapping = NULL, .payload = NULL};
  atomic_thread_fence(memory_order_seq_cst);

  // The mapping only exists if it was created by the current process; if it was inherited by a fork it doesn't exist anymore
  // (due to the MADV_DONTFORK) and we don't need to do anything to it.
  if (state.mapping != NULL && state.mapping != MAP_FAILED && getpid() == state.publisher_pid) {
    long mapping_size = size_for_mapping();
    if (mapping_size == -1 || munmap(state.mapping, mapping_size) == -1) return false;
  }

  // The payload may have been inherited from a parent. This is a regular malloc so we need to free it so we don't leak.
  if (state.payload) free(state.payload);

  return true;
}

static otel_process_ctx_result validate_and_calculate_payload_size(size_t *out_pairs_size, size_t *out_num_pairs, char **pairs) {
  size_t num_entries = 0;
  for (size_t i = 0; pairs[i] != NULL; i++) num_entries++;
  if (num_entries % 2 != 0) {
    return (otel_process_ctx_result) {.success = false, .error_message = "Value in otel_process_ctx_data is NULL (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
  }
  *out_num_pairs = num_entries / 2;

  *out_pairs_size = 0;
  for (size_t i = 0; i < *out_num_pairs; i++) {
    size_t key_len = strlen(pairs[i * 2]);
    if (key_len > INT16_MAX) {
      return (otel_process_ctx_result) {.success = false, .error_message = "Length of key in otel_process_ctx_data exceeds INT16_MAX limit (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
    }
    size_t value_len = strlen(pairs[i * 2 + 1]);
    if (value_len > INT16_MAX) {
      return (otel_process_ctx_result) {.success = false, .error_message = "Length of value in otel_process_ctx_data exceeds INT16_MAX limit (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
    }
    *out_pairs_size += 1 + 2 + key_len;   // str 16 for key
    *out_pairs_size += 1 + 2 + value_len; // str 16 for value
  }

  return (otel_process_ctx_result) {.success = true, .error_message = NULL};
}

static void write_msgpack_string(char **ptr, const char *str) {
  size_t len = strlen(str);
  // Write str 16 header
  *(*ptr)++ = 0xda;
  *(*ptr)++ = (len >> 8) & 0xFF; // high byte of length
  *(*ptr)++ = len & 0xFF;        // low byte of length
  memcpy(*ptr, str, len);
  *ptr += len;
}

// TODO: The serialization format is still under discussion and is not considered stable yet.
// Comments **very** welcome: Should we use JSON instead? Or protobuf?
//
// Encode the payload as a msgpack map of string key/value pairs.
//
// This method implements an extremely compact but limited msgpack encoder. This encoder supports only encoding a single
// flat key-value map where every key and value is a string.
// For extra compact code, it uses only a "map 16" encoding format with only "str 16" strings, rather than attempting to
// use some of the other encoding alternatives.
static otel_process_ctx_result otel_process_ctx_encode_payload(char **out, uint32_t *out_size, otel_process_ctx_data data) {
  const char *pairs[] = {
    "deployment.environment.name", data.deployment_environment_name,
    "host.name", data.host_name,
    "service.instance.id", data.service_instance_id,
    "service.name", data.service_name,
    "service.version", data.service_version,
    "telemetry.sdk.language", data.telemetry_sdk_language,
    "telemetry.sdk.version", data.telemetry_sdk_version,
    "telemetry.sdk.name", data.telemetry_sdk_name,
    NULL
  };

  size_t num_pairs = 0, pairs_size = 0;
  otel_process_ctx_result validation_result = validate_and_calculate_payload_size(&pairs_size, &num_pairs, (char **) pairs);
  if (!validation_result.success) return validation_result;

  size_t resources_pairs_size = 0, resources_num_pairs = 0;
  if (data.resources != NULL) {
    validation_result = validate_and_calculate_payload_size(&resources_pairs_size, &resources_num_pairs, data.resources);
    if (!validation_result.success) return validation_result;
  }

  size_t total_pairs = num_pairs + resources_num_pairs;
  size_t total_size = pairs_size + resources_pairs_size + 1 + 2; // map 16 header (1 byte + 2 bytes for count)

  if (total_pairs > INT16_MAX) {
    return (otel_process_ctx_result) {.success = false, .error_message = "Total number of pairs exceeds INT16_MAX limit (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
  }

  char *encoded = (char *) calloc(total_size, 1);
  if (!encoded) {
    return (otel_process_ctx_result) {.success = false, .error_message = "Failed to allocate memory for payload (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
  }
  char *ptr = encoded;

  // Write map 16 header (0xde) followed by count
  *ptr++ = 0xde;
  *ptr++ = (total_pairs >> 8) & 0xFF; // high byte of count
  *ptr++ = total_pairs & 0xFF;        // low byte of count

  for (size_t i = 0; i < num_pairs; i++) {
    write_msgpack_string(&ptr, pairs[i * 2]);     // Write key
    write_msgpack_string(&ptr, pairs[i * 2 + 1]); // Write value
  }

  if (data.resources != NULL) {
    for (size_t i = 0; i < resources_num_pairs; i++) {
      write_msgpack_string(&ptr, data.resources[i * 2]);     // Write key
      write_msgpack_string(&ptr, data.resources[i * 2 + 1]); // Write value
    }
  }

  *out = encoded;
  *out_size = (uint32_t) total_size;

  return (otel_process_ctx_result) {.success = true, .error_message = NULL};
}

#ifndef OTEL_PROCESS_CTX_NO_READ
  #include <inttypes.h>
  #include <limits.h>
  #include <sys/uio.h>
  #include <sys/utsname.h>

  // Note: The below parsing code is only for otel_process_ctx_read and is only provided for debugging
  // and testing purposes.

  // Named mappings are supported on Linux 5.17+
  static bool named_mapping_supported(void) {
    struct utsname uts;
    int major, minor;
    if (uname(&uts) != 0 || sscanf(uts.release, "%d.%d", &major, &minor) != 2) return false;
    return (major > 5) || (major == 5 && minor >= 17);
  }

  static void *parse_mapping_start(char *line) {
    char *endptr = NULL;
    unsigned long long start = strtoull(line, &endptr, 16);
    if (start == 0 || start == ULLONG_MAX) return NULL;
    return (void *)(uintptr_t) start;
  }

  static bool is_otel_process_ctx_mapping(char *line) {
    size_t name_len = sizeof("[anon:OTEL_CTX]") - 1;
    size_t line_len = strlen(line);
    if (line_len < name_len) return false;
    if (line[line_len-1] == '\n') line[--line_len] = '\0';

    // Validate expected permission
    if (strstr(line, " r--p ") == NULL) return false;

    // Validate expected context size
    int64_t start, end;
    if (sscanf(line, "%" PRIx64 "-%" PRIx64, &start, &end) != 2) return false;
    if (start == 0 || end == 0 || end <= start) return false;
    if ((end - start) != size_for_mapping()) return false;

    if (named_mapping_supported()) {
      // On Linux 5.17+, check if the line ends with [anon:OTEL_CTX]
      return memcmp(line + (line_len - name_len), "[anon:OTEL_CTX]", name_len) == 0;
    } else {
      // On older kernels, parse the address to to find the OTEL_CTX signature
      void *addr = parse_mapping_start(line);
      if (addr == NULL) return false;

      // Read 8 bytes at the address using process_vm_readv (to avoid any issues with concurrency/races)
      char buffer[8];
      struct iovec local[] = {{.iov_base = buffer, .iov_len = sizeof(buffer)}};
      struct iovec remote[] = {{.iov_base = addr, .iov_len = sizeof(buffer)}};

      ssize_t bytes_read = process_vm_readv(getpid(), local, 1, remote, 1, 0);
      if (bytes_read != sizeof(buffer)) return false;

      return memcmp(buffer, "OTEL_CTX", sizeof(buffer)) == 0;
    }
  }

  static otel_process_ctx_mapping *try_finding_mapping(void) {
    char line[8192];
    otel_process_ctx_mapping *result = NULL;

    FILE *fp = fopen("/proc/self/maps", "r");
    if (!fp) return result;

    while (fgets(line, sizeof(line), fp)) {
      if (is_otel_process_ctx_mapping(line)) {
        result = (otel_process_ctx_mapping *)parse_mapping_start(line);
        break;
      }
    }

    fclose(fp);
    return result;
  }

  // Simplified msgpack decoder to match the exact encoder above. If the msgpack string doesn't match the encoder, this will
  // return false.
  static bool otel_process_ctx_decode_payload(char *payload, otel_process_ctx_data *data_out) {
    char *ptr = payload;

    // Check map 16 header (0xde)
    if ((unsigned char)*ptr++ != 0xde) return false;

    // Read count (2 bytes, big endian)
    uint16_t count = ((uint8_t)*ptr << 8) | (uint8_t)*(ptr + 1);
    ptr += 2;

    // We expect at least 8 pairs (the standard fields)
    if (count < 8) return false;

    // Initialize output data
    data_out->deployment_environment_name = NULL;
    data_out->host_name = NULL;
    data_out->service_instance_id = NULL;
    data_out->service_name = NULL;
    data_out->service_version = NULL;
    data_out->telemetry_sdk_language = NULL;
    data_out->telemetry_sdk_version = NULL;
    data_out->telemetry_sdk_name = NULL;
    data_out->resources = NULL;

    // Allocate resources array with space for all pairs as a simplification (2 entries per pair + 1 for NULL terminator)
    data_out->resources = (char **) calloc(count * 2 + 1, sizeof(char *));
    if (!data_out->resources) return false;

    int resources_index = 0;

    // Decode each key-value pair
    for (int i = 0; i < count; i++) {
      // Check str 16 header for key (0xda)
      if ((unsigned char)*ptr++ != 0xda) return false;

      // Read key length (2 bytes, big endian)
      uint16_t key_len = ((uint8_t)*ptr << 8) | (uint8_t)*(ptr + 1);
      ptr += 2;

      // Get pointer to key (not null-terminated)
      char *key_not_terminated = ptr;
      ptr += key_len;

      // Check str 16 header for value (0xda)
      if ((unsigned char)*ptr++ != 0xda) return false;

      // Read value length (2 bytes, big endian)
      uint16_t value_len = ((uint8_t)*ptr << 8) | (uint8_t)*(ptr + 1);
      ptr += 2;

      // Read value
      char *value = (char *) calloc(value_len + 1, 1);
      if (!value) return false;
      memcpy(value, ptr, value_len);
      value[value_len] = '\0';
      ptr += value_len;

      // Assign to appropriate field based on key
      if (key_len == strlen("deployment.environment.name") && memcmp(key_not_terminated, "deployment.environment.name", strlen("deployment.environment.name")) == 0) {
        data_out->deployment_environment_name = value;
      } else if (key_len == strlen("host.name") && memcmp(key_not_terminated, "host.name", strlen("host.name")) == 0) {
        data_out->host_name = value;
      } else if (key_len == strlen("service.instance.id") && memcmp(key_not_terminated, "service.instance.id", strlen("service.instance.id")) == 0) {
        data_out->service_instance_id = value;
      } else if (key_len == strlen("service.name") && memcmp(key_not_terminated, "service.name", strlen("service.name")) == 0) {
        data_out->service_name = value;
      } else if (key_len == strlen("service.version") && memcmp(key_not_terminated, "service.version", strlen("service.version")) == 0) {
        data_out->service_version = value;
      } else if (key_len == strlen("telemetry.sdk.language") && memcmp(key_not_terminated, "telemetry.sdk.language", strlen("telemetry.sdk.language")) == 0) {
        data_out->telemetry_sdk_language = value;
      } else if (key_len == strlen("telemetry.sdk.version") && memcmp(key_not_terminated, "telemetry.sdk.version", strlen("telemetry.sdk.version")) == 0) {
        data_out->telemetry_sdk_version = value;
      } else if (key_len == strlen("telemetry.sdk.name") && memcmp(key_not_terminated, "telemetry.sdk.name", strlen("telemetry.sdk.name")) == 0) {
        data_out->telemetry_sdk_name = value;
      } else {
        // Unknown key, put it into resources
        char *key = (char *) calloc(key_len + 1, 1);
        if (!key) {
          free(value);
          return false;
        }
        memcpy(key, key_not_terminated, key_len);
        key[key_len] = '\0';

        data_out->resources[resources_index++] = key;
        data_out->resources[resources_index++] = value;
      }
    }

    // Verify all required fields were found
    return data_out->deployment_environment_name != NULL &&
           data_out->host_name != NULL &&
           data_out->service_instance_id != NULL &&
           data_out->service_name != NULL &&
           data_out->service_version != NULL &&
           data_out->telemetry_sdk_language != NULL &&
           data_out->telemetry_sdk_version != NULL &&
           data_out->telemetry_sdk_name != NULL;
  }

  void otel_process_ctx_read_data_drop(otel_process_ctx_data data) {
    if (data.deployment_environment_name) free(data.deployment_environment_name);
    if (data.host_name) free(data.host_name);
    if (data.service_instance_id) free(data.service_instance_id);
    if (data.service_name) free(data.service_name);
    if (data.service_version) free(data.service_version);
    if (data.telemetry_sdk_language) free(data.telemetry_sdk_language);
    if (data.telemetry_sdk_version) free(data.telemetry_sdk_version);
    if (data.telemetry_sdk_name) free(data.telemetry_sdk_name);
    if (data.resources) {
      for (int i = 0; data.resources[i] != NULL; i++) free(data.resources[i]);
      free(data.resources);
    }
  }

  otel_process_ctx_read_result otel_process_ctx_read(void) {
    otel_process_ctx_mapping *mapping = try_finding_mapping();
    if (!mapping) {
      return (otel_process_ctx_read_result) {.success = false, .error_message = "No OTEL_CTX mapping found (" __FILE__ ":" ADD_QUOTES(__LINE__) ")", .data = empty_data};
    }

    if (strncmp(mapping->otel_process_ctx_signature, "OTEL_CTX", sizeof(mapping->otel_process_ctx_signature)) != 0 || mapping->otel_process_ctx_version != 1) {
      return (otel_process_ctx_read_result) {.success = false, .error_message = "Invalid OTEL_CTX signature or version (" __FILE__ ":" ADD_QUOTES(__LINE__) ")", .data = empty_data};
    }

    otel_process_ctx_data data = empty_data;

    if (!otel_process_ctx_decode_payload(mapping->otel_process_payload, &data)) {
      otel_process_ctx_read_data_drop(data);
      return (otel_process_ctx_read_result) {.success = false, .error_message = "Failed to decode payload (" __FILE__ ":" ADD_QUOTES(__LINE__) ")", .data = empty_data};
    }

    return (otel_process_ctx_read_result) {.success = true, .error_message = NULL, .data = data};
  }

  bool otel_process_ctx_read_drop(otel_process_ctx_read_result *result) {
    if (!result || !result->success) return false;

    // Free allocated strings in the data
    otel_process_ctx_read_data_drop(result->data);

    // Reset the result to empty state
    *result = (otel_process_ctx_read_result) {.success = false, .error_message = "Data dropped", .data = empty_data};

    return true;
  }
#endif // OTEL_PROCESS_CTX_NO_READ

#endif // OTEL_PROCESS_CTX_NOOP

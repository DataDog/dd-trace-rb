#include "otel_process_ctx.h"

#include <errno.h>
#include <limits.h>
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
struct otel_process_ctx_state {
  // The pid of the process that published the context.
  pid_t publisher_pid;
  // The actual mapping of the process context. Note that because we `madvise(..., MADV_DONTFORK)` this mapping is not
  // propagated to child processes and thus `mapping` is only valid on the process that published the context.
  otel_process_ctx_mapping *mapping;
  // The process context payload.
  char *payload;
};

static otel_process_ctx_result otel_process_ctx_encode_payload(char **out, uint32_t *out_size, otel_process_ctx_data data);

// The `volatile` isn't strictly needed here but saves on a few casts below.
static void otel_process_ctx_state_drop(volatile otel_process_ctx_state *state) {
  free(state->payload);
  free((void *) state);
}

// The process context is designed to be read by an outside-of-process reader. Thus, for concurrency purposes the steps
// on this method are ordered in a way to avoid races, or if not possible to avoid, to allow the reader to detect if there was a race.
otel_process_ctx_result otel_process_ctx_publish(otel_process_ctx_data data) {
  volatile otel_process_ctx_state *state = calloc(1, sizeof(otel_process_ctx_state));
  if (!state) {
    return (otel_process_ctx_result) {.success = false, .error_message = "Failed to allocate state (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
  }

  state->publisher_pid = getpid();

  // Step: Prepare the payload to be published
  // The payload SHOULD be ready and valid before trying to actually create the mapping.
  uint32_t payload_size = 0;
  otel_process_ctx_result result = otel_process_ctx_encode_payload((char **)&state->payload, &payload_size, data);
  if (!result.success) {
    otel_process_ctx_state_drop(state);
    return result;
  }

  // Step: Create the mapping
  otel_process_ctx_mapping *mapping =
    mmap(NULL, sizeof(otel_process_ctx_mapping), PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (mapping == MAP_FAILED) {
    otel_process_ctx_state_drop(state);
    return (otel_process_ctx_result) {.success = false, .error_message = "Failed to allocate mapping (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
  }

  // Step: Setup MADV_DONTFORK
  // This ensures that the mapping is not propagated to child processes (they should call update/publish again).
  if (madvise(mapping, sizeof(otel_process_ctx_mapping), MADV_DONTFORK) == -1) {
    otel_process_ctx_state_drop(state);

    if (munmap(mapping, sizeof(otel_process_ctx_mapping)) == -1) {
      return (otel_process_ctx_result) {.success = false, .error_message = "Failed to unmap mapping (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
    } else {
      return (otel_process_ctx_result) {.success = false, .error_message = "Failed to setup MADV_DONTFORK (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
    }
  }

  // (Store the mapping in the `volatile` state and stop using the local variable to force ordering below)
  state->mapping = mapping;
  mapping = NULL;

  // Step: Populate the mapping
  // The payload and any extra fields must come first and not be reordered with the signature by the compiler.
  // (In this implementation we guarantee this because `state` is declared `volatile`.)
  *state->mapping = (otel_process_ctx_mapping) {
    .otel_process_ctx_version = 1,
    .otel_process_payload_size = payload_size,
    .otel_process_payload = state->payload
  };

  // Step: Populate the signature into the mapping
  // The signature must come last and not be reordered with the fields above by the compiler. After this step, external readers
  // can read the signature and know that the payload is ready to be read.
  memcpy(state->mapping->otel_process_ctx_signature, "OTEL_CTX", sizeof(state->mapping->otel_process_ctx_signature));

  // TODO: Do we like this and want to keep it?
  // Optional step: Change permissions on the mapping to only read permission
  // We've observed the combination of anonymous mapping + single page + read-only permission is not very common,
  // so this is left as a hint for when running on older kernels and the naming the mapping feature below isn't available.
  // For modern kernels, doing this is harmless so we do it unconditionally.
  if (mprotect(state->mapping, sizeof(otel_process_ctx_mapping), PROT_READ) == -1) {
    otel_process_ctx_state_drop(state);

    if (munmap(state->mapping, sizeof(otel_process_ctx_mapping)) == -1) {
      return (otel_process_ctx_result) {.success = false, .error_message = "Failed to unmap mapping (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
    } else {
      return (otel_process_ctx_result) {.success = false, .error_message = "Failed to change permissions on mapping (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
    }
  }

  // Step: Name the mapping so outside readers can:
  // * Find it by name
  // * Hook on prctl to detect when new mappings are published
  if (prctl(PR_SET_VMA, PR_SET_VMA_ANON_NAME, state->mapping, sizeof(otel_process_ctx_mapping), "OTEL_CTX") == -1) {
    // Naming an anonymous mapping is a Linux 5.17+ feature. On earlier versions, this method call can fail. Thus it's OK
    // for this to fail because:
    // 1. Things that hook on prctl are still able to see this call, even though it's not supported (TODO: Confirm this is actually the case)
    // 2. As a fallback, on older kernels, it's possible to scan the mappings and look for the "OTEL_CTX" signature in the memory itself,
    //    after observing the mapping has the expected size and permissions.
  }

  // All done!

  return (otel_process_ctx_result) {.success = true, .published_context = (otel_process_ctx_state *) state};
}

otel_process_ctx_result otel_process_ctx_update(otel_process_ctx_result *previous, otel_process_ctx_data data) {
  if (!otel_process_ctx_drop(previous)) {
    return (otel_process_ctx_result) {.success = false, .error_message = "Failed to drop previous context (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
  }

  return otel_process_ctx_publish(data);
}

bool otel_process_ctx_drop(otel_process_ctx_result *previous) {
  if (!previous || !previous->success || !previous->published_context) {
    return false;
  }

  // The mapping only exists if it was created by the current process; if it was inherited by a fork it doesn't exist anymore
  // (due to the MADV_DONTFORK) and we don't need to do anything to it.
  if (getpid() == previous->published_context->publisher_pid) {
    if (munmap(previous->published_context->mapping, sizeof(otel_process_ctx_mapping)) == -1) {
      return false;
    }
  }

  otel_process_ctx_state_drop(previous->published_context);
  previous->published_context = NULL;

  // Just to be nice to the caller, reset these as well
  previous->success = false;
  previous->error_message = "Context dropped";

  return true;
}

// TODO: The serialization format is still under discussion and is not considered stable yet.
//
// Encode the payload as a msgpack map of string key/value pairs.
//
// This method implements an extremely compact but limited msgpack encoder. This encoder supports only encoding a single
// flat key-value map where every key and value is a string.
// For extra compact code, it uses only a "map 16" encoding format with only "str 16" strings, rather than attempting to
// use some of the other encoding alternatives.
static otel_process_ctx_result otel_process_ctx_encode_payload(char **out, uint32_t *out_size, otel_process_ctx_data data) {
  const char *pairs[][2] = {
    {"service.name", data.service_name},
    {"service.instance.id", data.service_instance_id},
    {"deployment.environment.name", data.deployment_environment_name}
  };

  const size_t num_pairs = sizeof(pairs) / sizeof(pairs[0]);

  // Validate + calculate size of payload
  size_t total_size = 1 + 2; // map 16 header (1 byte + 2 bytes for count)
  for (size_t i = 0; i < num_pairs; i++) {
    size_t key_len = strlen(pairs[i][0]);
    if (pairs[i][1] == NULL) {
      return (otel_process_ctx_result) {.success = false, .error_message = "Value in otel_process_ctx_data is NULL (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
    }
    size_t value_len = strlen(pairs[i][1]);
    if (value_len > INT16_MAX) {
      // Keys are hardcoded above so we know they have a valid length
      return (otel_process_ctx_result) {.success = false, .error_message = "Length of value in otel_process_ctx_data exceeds INT16_MAX limit (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
    }
    total_size += 1 + 2 + key_len;   // str 16 for key
    total_size += 1 + 2 + value_len; // str 16 for value
  }

  char *encoded = calloc(total_size, 1);
  if (!encoded) {
    return (otel_process_ctx_result) {.success = false, .error_message = "Failed to allocate memory for payload (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
  }
  char *ptr = encoded;

  // Write map 16 header (0xde) followed by count
  *ptr++ = 0xde;
  *ptr++ = (num_pairs >> 8) & 0xFF; // high byte of count
  *ptr++ = num_pairs & 0xFF;        // low byte of count

  for (size_t i = 0; i < num_pairs; i++) {
    size_t key_len = strlen(pairs[i][0]);
    size_t value_len = strlen(pairs[i][1]);

    // Write key as str 16
    *ptr++ = 0xda;
    *ptr++ = (key_len >> 8) & 0xFF; // high byte of length
    *ptr++ = key_len & 0xFF;        // low byte of length
    memcpy(ptr, pairs[i][0], key_len);
    ptr += key_len;

    // Write value as str 16
    *ptr++ = 0xda;
    *ptr++ = (value_len >> 8) & 0xFF; // high byte of length
    *ptr++ = value_len & 0xFF;        // low byte of length
    memcpy(ptr, pairs[i][1], value_len);
    ptr += value_len;
  }

  *out = encoded;
  *out_size = (uint32_t) total_size;

  return (otel_process_ctx_result) {.success = true };
}

#ifndef OTEL_PROCESS_CTX_NO_READ
  // Note: The below parsing code is only for otel_process_ctx_read and is only provided for debugging
  // and testing purposes.

  static bool is_otel_process_ctx_mapping(char *line) {
    size_t name_len = sizeof("[anon:OTEL_CTX]") - 1;
    size_t line_len = strlen(line);
    if (line_len < name_len) return false;
    if (line[line_len-1] == '\n') line[--line_len] = '\0';
    return memcmp(line + (line_len - name_len), "[anon:OTEL_CTX]", name_len) == 0;
  }

  static void *parse_mapping_start(char *line) {
    char *endptr = NULL;
    unsigned long long start = strtoull(line, &endptr, 16);
    if (start == 0 || start == ULLONG_MAX) return NULL;
    return (void *)(uintptr_t) start;
  }

  static otel_process_ctx_mapping *try_finding_mapping(void) {
    char line[8192];
    void *result = NULL;

    FILE *fp = fopen("/proc/self/maps", "r");
    if (!fp) return result;

    while (fgets(line, sizeof(line), fp)) {
      if (is_otel_process_ctx_mapping(line)) {
        result = parse_mapping_start(line);
        break;
      }
    }

    fclose(fp);
    return (otel_process_ctx_mapping *) result;
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

    // We expect exactly 3 pairs
    if (count != 3) return false;

    // Initialize output data
    data_out->service_name = NULL;
    data_out->service_instance_id = NULL;
    data_out->deployment_environment_name = NULL;

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
      char *value = malloc(value_len + 1);
      if (!value) return false;
      memcpy(value, ptr, value_len);
      value[value_len] = '\0';
      ptr += value_len;

      // Assign to appropriate field based on key
      if (key_len == strlen("service.name") && memcmp(key_not_terminated, "service.name", strlen("service.name")) == 0) {
        data_out->service_name = value;
      } else if (key_len == strlen("service.instance.id") && memcmp(key_not_terminated, "service.instance.id", strlen("service.instance.id")) == 0) {
        data_out->service_instance_id = value;
      } else if (key_len == strlen("deployment.environment.name") && memcmp(key_not_terminated, "deployment.environment.name", strlen("deployment.environment.name")) == 0) {
        data_out->deployment_environment_name = value;
      } else {
        // Unknown key, clean up and fail
        free(value);
        return false;
      }
    }

    // Verify all required fields were found
    return data_out->service_name != NULL &&
           data_out->service_instance_id != NULL &&
           data_out->deployment_environment_name != NULL;
  }

  otel_process_ctx_read_result otel_process_ctx_read(void) {
    otel_process_ctx_mapping *mapping = try_finding_mapping();
    if (!mapping) {
      return (otel_process_ctx_read_result) {.success = false, .error_message = "No OTEL_CTX mapping found (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
    }

    if (strncmp(mapping->otel_process_ctx_signature, "OTEL_CTX", sizeof(mapping->otel_process_ctx_signature)) != 0 || mapping->otel_process_ctx_version != 1) {
      return (otel_process_ctx_read_result) {.success = false, .error_message = "Invalid OTEL_CTX signature or version (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
    }

    otel_process_ctx_data data = {0};

    if (!otel_process_ctx_decode_payload(mapping->otel_process_payload, &data)) {
      return (otel_process_ctx_read_result) {.success = false, .error_message = "Failed to decode payload (" __FILE__ ":" ADD_QUOTES(__LINE__) ")"};
    }

    return (otel_process_ctx_read_result) {.success = true, .data = data};
  }
#endif // OTEL_PROCESS_CTX_NO_READ

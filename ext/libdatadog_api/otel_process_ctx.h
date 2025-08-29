#pragma once

#define OTEL_PROCESS_CTX_VERSION_MAJOR 0
#define OTEL_PROCESS_CTX_VERSION_MINOR 0
#define OTEL_PROCESS_CTX_VERSION_PATCH 5
#define OTEL_PROCESS_CTX_VERSION_STRING "0.0.5"

#ifdef __cplusplus
extern "C" {
#endif

#include <stdbool.h>

/**
 * # OpenTelemetry Process Context reference implementation
 *
 * `otel_process_ctx.h` and `otel_process_ctx.c` provide a reference implementation for the OpenTelemetry
 * process-level context sharing specification. (TODO Link)
 *
 * This reference implementation is Linux-only, as the specification currently only covers Linux.
 * On non-Linux OS's (or when OTEL_PROCESS_CTX_NOOP is defined) no-op versions of functions are supplied.
 */

/**
 * Data that can be published as a process context.
 *
 * Every string MUST be valid for the duration of the call to `otel_process_ctx_publish`.
 * Strings will be copied into the context.
 *
 * Strings MUST be:
 * * Non-NULL
 * * UTF-8 encoded
 * * Not longer than INT16_MAX bytes
 *
 * Strings MAY be:
 * * Empty
 *
 * The below fields map to usual datadog attributes as follows (TODO: Remove this once we share the header publicly)
 * * deployment_environment_name -> env
 * * host_name -> hostname
 * * service_instance_id -> runtime-id
 * * service_name -> service
 * * service_version -> version
 * * telemetry_sdk_language -> tracer_language
 * * telemetry_sdk_version -> tracer_version
 * * telemetry_sdk_name -> name of library (e.g. dd-trace-java)
 */
typedef struct {
  // https://opentelemetry.io/docs/specs/semconv/registry/attributes/deployment/#deployment-environment-name
  char *deployment_environment_name;
  // https://opentelemetry.io/docs/specs/semconv/registry/attributes/host/#host-name
  char *host_name;
  // https://opentelemetry.io/docs/specs/semconv/registry/attributes/service/#service-instance-id
  char *service_instance_id;
  // https://opentelemetry.io/docs/specs/semconv/registry/attributes/service/#service-name
  char *service_name;
  // https://opentelemetry.io/docs/specs/semconv/registry/attributes/service/#service-version
  char *service_version;
  // https://opentelemetry.io/docs/specs/semconv/registry/attributes/telemetry/#telemetry-sdk-language
  char *telemetry_sdk_language;
  // https://opentelemetry.io/docs/specs/semconv/registry/attributes/telemetry/#telemetry-sdk-version
  char *telemetry_sdk_version;
  // https://opentelemetry.io/docs/specs/semconv/registry/attributes/telemetry/#telemetry-sdk-name
  char *telemetry_sdk_name;
  // Additional key/value pairs as resources https://opentelemetry.io/docs/specs/otel/resource/sdk/
  // Can be NULL if no resources are needed; if non-NULL, this array MUST be terminated with a NULL entry.
  // Every even entry is a key, every odd entry is a value (E.g. "key1", "value1", "key2", "value2", NULL).
  char **resources;
} otel_process_ctx_data;

/** Number of entries in the `otel_process_ctx_data` struct. Can be used to easily detect when the struct is updated. */
#define OTEL_PROCESS_CTX_DATA_ENTRIES sizeof(otel_process_ctx_data) / sizeof(char *)

typedef struct {
  bool success;
  const char *error_message; // Static strings only, non-NULL if success is false
} otel_process_ctx_result;

/**
 * Publishes a OpenTelemetry process context with the given data.
 *
 * The context should remain alive until the application exits (or is just about to exit).
 * This method is NOT thread-safe.
 *
 * Calling `publish` multiple times is supported and will replace a previous context (only one is published at any given
 * time). Calling `publish` multiple times usually happens when:
 * * Some of the `otel_process_ctx_data` changes due to a live system reconfiguration for the same process
 * * The process is forked (to provide a new `service_instance_id`)
 *
 * This API can be called in a fork of the process that published the previous context, even though
 * the context is not carried over into forked processes (although part of its memory allocations are).
 *
 * @param data Pointer to the data to publish. This data is copied into the context and only needs to be valid for the duration of
 *             the call. Must not be `NULL`.
 * @return The result of the operation.
 */
otel_process_ctx_result otel_process_ctx_publish(const otel_process_ctx_data *data);

/**
 * Drops the current OpenTelemetry process context, if any.
 *
 * This method is safe to call even there's no current context.
 * This method is NOT thread-safe.
 *
 * This API can be called in a fork of the process that published the current context to clean memory allocations
 * related to the parent's context (even though the context itself is not carried over into forked processes).
 *
 * @return `true` if the context was successfully dropped or no context existed, `false` otherwise.
 */
bool otel_process_ctx_drop_current(void);

/** This can be disabled if no read support is required. */
#ifndef OTEL_PROCESS_CTX_NO_READ
  typedef struct {
    bool success;
    const char *error_message; // Static strings only, non-NULL if success is false
    otel_process_ctx_data data; // Strings are allocated using `malloc` and the caller is responsible for `free`ing them
  } otel_process_ctx_read_result;

  /**
  * Reads the current OpenTelemetry process context, if any.
  *
  * Useful for debugging and testing purposes. Underlying returned strings in `data` are dynamically allocated using
  * `malloc` and `otel_process_ctx_read_drop` must be called to free them.
  *
  * Thread-safety: This function assumes there is no concurrent mutation of the process context.
  *
  * @return The result of the operation. If successful, `data` contains the retrieved context data.
  */
  otel_process_ctx_read_result otel_process_ctx_read(void);

  /**
   * Drops the data resulting from a previous call to `otel_process_ctx_read`.
   *
   * @param result The result of a previous call to `otel_process_ctx_read`. Must not be `NULL`.
   * @return `true` if the data was successfully dropped, `false` otherwise.
   */
  bool otel_process_ctx_read_drop(otel_process_ctx_read_result *result);
#endif

#ifdef __cplusplus
}
#endif

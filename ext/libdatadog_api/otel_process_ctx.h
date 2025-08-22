#pragma once

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
 */

/**
 * Data that can be published as a process context.
 *
 * Every string MUST be valid for the duration of the call to `otel_process_ctx_publish` or
 * `otel_process_ctx_update`. Strings will be copied into the context.
 *
 * Strings MUST be:
 * * Non-null
 * * UTF-8 encoded
 * * Not longer than INT16_MAX bytes
 *
 * Strings MAY be:
 * * Empty
 */
typedef struct {
  // https://opentelemetry.io/docs/specs/semconv/registry/attributes/service/#service-name
  char *service_name;
  // https://opentelemetry.io/docs/specs/semconv/registry/attributes/service/#service-instance-id
  char *service_instance_id;
  // https://opentelemetry.io/docs/specs/semconv/registry/attributes/deployment/#deployment-environment-name
  char *deployment_environment_name;
} otel_process_ctx_data;

/**
 * Opaque type representing the state of a published process context.
 *
 * Internally useful for dropping the context and any memory allocations related to it.
 */
typedef struct otel_process_ctx_state otel_process_ctx_state;

typedef struct {
  bool success;
  const char *error_message; // Static strings only, non-NULL if success is false
  otel_process_ctx_state *published_context; // Non-NULL if success is true
} otel_process_ctx_result;

/**
 * Publishes a OpenTelemetry process context with the given data.
 *
 * The context should remain alive until the application exits (or is just about to exit).
 *
 * @param data The data to publish. This data is copied into the context and only needs to be valid for the duration of
 *             the call.
 * @return The result of the operation.
 */
otel_process_ctx_result otel_process_ctx_publish(otel_process_ctx_data data);

/**
 * Replaces the previous OpenTelemetry process context with the given data.
 *
 * This API is usually called when:
 * * Some of the `otel_process_ctx_data` changes due to a live system reconfiguration for the same process
 * * The process is forked (to provide a new `service_instance_id`)
 *
 * @param previous The previous context. This context is dropped before the new one is installed.
 *                 This API can be called in a fork of the process that published the previous context, even though
 *                 the context is not carried over into forked processes (although part of its memory allocations are).
 *                 Must not be `NULL`.
 * @param data The data to publish. This data is copied into the context and only needs to be valid for the duration of
 *             the call.
 * @return The result of the operation.
 */
otel_process_ctx_result otel_process_ctx_update(otel_process_ctx_result *previous, otel_process_ctx_data data);

/**
 * Drops the previous OpenTelemetry process context.
 *
 * @param previous The previous context to drop. This API can be called in a fork of the process that published the
 *                 previous context, to clean memory allocations related to the parent's context (even though the
 *                 context is not carried over into forked processes).
 *                 Must not be `NULL`.
 * @return `true` if the context was successfully dropped, `false` otherwise.
 */
bool otel_process_ctx_drop(otel_process_ctx_result *previous);

#ifndef OTEL_PROCESS_CTX_NO_READ
  typedef struct {
    bool success;
    const char *error_message; // Static strings only, non-NULL if success is false
    otel_process_ctx_data data; // Strings are allocated using `malloc` and the caller is responsible for `free`ing them
  } otel_process_ctx_read_result;

  /**
  * Reads the current OpenTelemetry process context, if any.
  *
  * Useful for debugging and testing purposes. Underlying returned strings in `data` are allocated using `malloc` and the
  * caller is responsible for `free`ing them.
  *
  * Thread-safety: This function assumes there is no concurrent mutation of the process context.
  *
  * @return The result of the operation. If successful, `data` contains the retrieved context data.
  */
  otel_process_ctx_read_result otel_process_ctx_read(void);
#endif

#ifdef __cplusplus
}
#endif

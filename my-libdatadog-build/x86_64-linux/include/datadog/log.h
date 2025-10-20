// Copyright 2025-Present Datadog, Inc. https://www.datadoghq.com/
// SPDX-License-Identifier: Apache-2.0


#ifndef DDOG_LOG_H
#define DDOG_LOG_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include "common.h"

/**
 * Configures the logger to write to stdout or stderr with the specified configuration.
 *
 * # Arguments
 * * `config` - Configuration for standard stream logging including target
 *
 * # Errors
 * Returns an error if the logger cannot be configured.
 */
struct ddog_Error *ddog_logger_configure_std(struct ddog_StdConfig config);

/**
 * Disables logging by configuring a no-op logger.
 *
 * # Errors
 * Returns an error if the logger cannot be configured.
 */
struct ddog_Error *ddog_logger_disable_std(void);

/**
 * Configures the logger to write to a file with the specified configuration.
 *
 * # Arguments
 * * `config` - Configuration for file logging including path
 *
 * # Errors
 * Returns an error if the logger cannot be configured.
 */
struct ddog_Error *ddog_logger_configure_file(struct ddog_FileConfig config);

/**
 * Disables file logging by configuring a no-op file writer.
 *
 * # Errors
 * Returns an error if the logger cannot be configured.
 */
struct ddog_Error *ddog_logger_disable_file(void);

/**
 * Sets the global log level.
 *
 * # Arguments
 * * `log_level` - The minimum level for events to be logged
 *
 * # Errors
 * Returns an error if the log level cannot be set.
 */
struct ddog_Error *ddog_logger_set_log_level(enum ddog_LogEventLevel log_level);

#endif  /* DDOG_LOG_H */

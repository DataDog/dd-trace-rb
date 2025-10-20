// Copyright 2025-Present Datadog, Inc. https://www.datadoghq.com/
// SPDX-License-Identifier: Apache-2.0


#ifndef DDOG_DDSKETCH_H
#define DDOG_DDSKETCH_H

#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include "common.h"

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

/**
 * Creates a new DDSketch instance with default configuration.
 */
struct ddsketch_Handle_DDSketch ddog_ddsketch_new(void);

/**
 * Drops a DDSketch instance.
 *
 * # Safety
 *
 * The sketch handle must have been created by this library and not already dropped.
 */
void ddog_ddsketch_drop(struct ddsketch_Handle_DDSketch *sketch);

/**
 * Adds a point to the DDSketch.
 *
 * # Safety
 *
 * The `sketch` parameter must be a valid pointer to a DDSketch handle.
 */
struct ddog_VoidResult ddog_ddsketch_add(struct ddsketch_Handle_DDSketch *sketch, double point);

/**
 * Adds a point with a specific count to the DDSketch.
 *
 * # Safety
 *
 * The `sketch` parameter must be a valid pointer to a DDSketch handle.
 */
struct ddog_VoidResult ddog_ddsketch_add_with_count(struct ddsketch_Handle_DDSketch *sketch,
                                                    double point,
                                                    double count);

/**
 * Returns the count of points in the DDSketch via the output parameter.
 *
 * # Safety
 *
 * The `sketch` parameter must be a valid pointer to a DDSketch handle.
 * The `count_out` parameter must be a valid pointer to uninitialized f64 memory.
 */
struct ddog_VoidResult ddog_ddsketch_count(struct ddsketch_Handle_DDSketch *sketch,
                                           double *count_out);

/**
 * Returns the protobuf-encoded bytes of the DDSketch.
 * The sketch handle is consumed by this operation.
 *
 * # Safety
 *
 * The `sketch` parameter must be a valid pointer to a DDSketch handle.
 * The returned vector must be freed with `ddog_Vec_U8_drop`.
 */
struct ddog_Vec_U8 ddog_ddsketch_encode(struct ddsketch_Handle_DDSketch *sketch);

/**
 * Frees the memory allocated for a Vec<u8> returned by ddsketch functions.
 *
 * # Safety
 *
 * The vec parameter must be a valid Vec<u8> returned by this library.
 * After being called, the vec will not point to valid memory.
 */
void ddog_Vec_U8_drop(struct ddog_Vec_U8 _vec);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* DDOG_DDSKETCH_H */

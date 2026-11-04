#pragma once

// Our bundled zstd.c embeds the upstream header, so its declarations aren't visible to other translation units.
// This hand-maintained subset exposes the APIs miteruby uses; keep it in sync with the bundled zstd version.

#include <stddef.h>

typedef struct ZSTD_CCtx_s ZSTD_CCtx;

size_t ZSTD_estimateCStreamSize(int max_compression_level);
ZSTD_CCtx *ZSTD_initStaticCCtx(void *workspace, size_t workspace_size);
size_t ZSTD_compressBound(size_t src_size);
size_t ZSTD_compressCCtx(ZSTD_CCtx *context, void *dst, size_t capacity, const void *src, size_t size, int level);
unsigned ZSTD_isError(size_t result);
const char *ZSTD_getErrorName(size_t result);

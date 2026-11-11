#pragma once

// Our bundled zstd.c embeds the upstream header, so its declarations aren't visible to other translation units.
// This hand-maintained subset exposes the APIs miteruby uses; keep it in sync with the bundled zstd version.

#include <stddef.h>

typedef struct ZSTD_CCtx_s ZSTD_CCtx;
typedef ZSTD_CCtx ZSTD_CStream;

typedef struct ZSTD_inBuffer_s {
  const void *src;
  size_t size;
  size_t pos;
} ZSTD_inBuffer;

typedef struct ZSTD_outBuffer_s {
  void *dst;
  size_t size;
  size_t pos;
} ZSTD_outBuffer;

typedef enum {
  ZSTD_e_continue = 0,
  ZSTD_e_flush = 1,
  ZSTD_e_end = 2,
} ZSTD_EndDirective;

size_t ZSTD_estimateCStreamSize(int max_compression_level);
ZSTD_CCtx *ZSTD_initStaticCCtx(void *workspace, size_t workspace_size);
size_t ZSTD_initCStream(ZSTD_CStream *context, int level);
size_t ZSTD_compressStream2(ZSTD_CCtx *context, ZSTD_outBuffer *output, ZSTD_inBuffer *input, ZSTD_EndDirective end_op);
unsigned ZSTD_isError(size_t result);
const char *ZSTD_getErrorName(size_t result);

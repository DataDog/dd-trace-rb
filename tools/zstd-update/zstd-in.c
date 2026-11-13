// @ivoanjo: We use zstandard/zstd to compress profiles.
//
// We're currently using the official zstd C implementation in "single file" mode.
//
// In this mode, we take the tools/zstd-update/zstd-in.c file and use the
// tools/zstd-update/zstd-update.sh script to generate a zstd.c file in the profiler
// sources directory.
//
// The single-file generation mechanism is provided upstream; our zstd-in.c
// customizes the configuration, and zstd-update.sh runs the official tooling.
//
// Never edit the generated zstd.c directly: change zstd-in.c and regenerate.
// We disable decompression, dictionary building, and multithreading because
// profiling does not currently need them.

/**
 * \file zstd.c
 * Single-file Zstandard library.
 *
 * Generate using:
 * \code
 *	python combine.py -r ../../lib -x legacy/zstd_legacy.h -o zstd.c zstd-in.c
 * \endcode
 */
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */
// @ivoanjo: The BSD-style license is included alongside zstd.c as zstd.LICENSE.txt.
/*
 * Settings to bake for the single library file.
 *
 * Note: It's important that none of these affects 'zstd.h' (only the
 * implementation files we're amalgamating).
 *
 * Note: MEM_MODULE stops xxhash redefining BYTE, U16, etc., which are also
 * defined in mem.h (breaking C99 compatibility).
 *
 * Note: the undefs for xxHash allow Zstd's implementation to coincide with
 * standalone xxHash usage (with global defines).
 *
 * Note: if you enable ZSTD_LEGACY_SUPPORT the combine.py script will need
 * re-running without the "-x legacy/zstd_legacy.h" option (it excludes the
 * legacy support at the source level).
 */
#define DEBUGLEVEL 0

// @ivoanjo: Avoid zstd's forced inlining to reduce compilation time when installing the gem.
#define ZSTD_NO_INLINE
// @ivoanjo: Keep bundled zstd symbols private.
#define ZSTDLIB_VISIBLE ZSTDLIB_HIDDEN
#define ZSTDERRORLIB_VISIBLE ZSTDERRORLIB_HIDDEN

#define MEM_MODULE
#undef  XXH_NAMESPACE
#define XXH_NAMESPACE ZSTD_
#undef  XXH_PRIVATE_API
#define XXH_PRIVATE_API
#undef  XXH_INLINE_ALL
#define XXH_INLINE_ALL
#define ZSTD_LEGACY_SUPPORT 0

// @ivoanjo: We don't currently want/need multi-threaded compression
// #ifndef __EMSCRIPTEN__
// #define ZSTD_MULTITHREAD
// #endif
#undef ZSTD_MULTITHREAD

#define ZSTD_TRACE 0

// @ivoanjo: We compress profiles at level 1, which only uses ZSTD_fast, so exclude all other strategies to reduce binary size && compression time.
#define ZSTD_EXCLUDE_DFAST_BLOCK_COMPRESSOR
#define ZSTD_EXCLUDE_GREEDY_BLOCK_COMPRESSOR
#define ZSTD_EXCLUDE_LAZY_BLOCK_COMPRESSOR
#define ZSTD_EXCLUDE_LAZY2_BLOCK_COMPRESSOR
#define ZSTD_EXCLUDE_BTLAZY2_BLOCK_COMPRESSOR
#define ZSTD_EXCLUDE_BTOPT_BLOCK_COMPRESSOR
#define ZSTD_EXCLUDE_BTULTRA_BLOCK_COMPRESSOR
/* TODO: Can't amalgamate ASM function */
#define ZSTD_DISABLE_ASM 1

// @ivoanjo: All compression state must live in miteruby-owned workspace supplied to ZSTD_initStaticCCtx().
// Reject dynamic allocations in zstd and its bundled xxHash so new code paths cannot silently use malloc.
#define ZSTD_DEPS_MALLOC
#define ZSTD_malloc(size) ((void)(size), (void *)0)
#define ZSTD_calloc(count, size) ((void)(count), (void)(size), (void *)0)
#define ZSTD_free(pointer) ((void)(pointer))
#define XXH_NO_STDLIB

/* Include zstd_deps.h first with all the options we need enabled. */
#define ZSTD_DEPS_NEED_MALLOC
#define ZSTD_DEPS_NEED_MATH64
#include "common/zstd_deps.h"

#include "common/debug.c"
#include "common/entropy_common.c"
#include "common/error_private.c"
#include "common/fse_decompress.c"
#include "common/threading.c"
#include "common/pool.c"
#include "common/zstd_common.c"

#include "compress/fse_compress.c"
#include "compress/hist.c"
#include "compress/huf_compress.c"
#include "compress/zstd_compress_literals.c"
#include "compress/zstd_compress_sequences.c"
#include "compress/zstd_compress_superblock.c"
#include "compress/zstd_preSplit.c"
#include "compress/zstd_compress.c"
#include "compress/zstd_double_fast.c"
#include "compress/zstd_fast.c"
#include "compress/zstd_lazy.c"
#include "compress/zstd_ldm.c"
#include "compress/zstd_opt.c"
#ifdef ZSTD_MULTITHREAD
#include "compress/zstdmt_compress.c"
#endif

// @ivoanjo: We don't need to decompress in the profiler.
// #include "decompress/huf_decompress.c"
// #include "decompress/zstd_ddict.c"
// #include "decompress/zstd_decompress.c"
// #include "decompress/zstd_decompress_block.c"

// @ivoanjo: We do not need to train dictionaries in the profiler.
// #include "dictBuilder/cover.c"
// #include "dictBuilder/divsufsort.c"
// #include "dictBuilder/fastcover.c"
// #include "dictBuilder/zdict.c"

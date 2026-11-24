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
// @ivoanjo: Skip the tracing header so the generator can exclude it to reduce zstd.c size.
#define ZSTD_NO_TRACE

// @ivoanjo: We compress profiles at level 1, which only uses ZSTD_fast, so exclude all other strategies to reduce binary size && compression time.
#define ZSTD_EXCLUDE_DFAST_BLOCK_COMPRESSOR
#define ZSTD_EXCLUDE_GREEDY_BLOCK_COMPRESSOR
#define ZSTD_EXCLUDE_LAZY_BLOCK_COMPRESSOR
#define ZSTD_EXCLUDE_LAZY2_BLOCK_COMPRESSOR
#define ZSTD_EXCLUDE_BTLAZY2_BLOCK_COMPRESSOR
#define ZSTD_EXCLUDE_BTOPT_BLOCK_COMPRESSOR
#define ZSTD_EXCLUDE_BTULTRA_BLOCK_COMPRESSOR

#define ZSTD_DISABLE_ASM 1

// @ivoanjo: All compression state must live in miteruby-owned workspace supplied to ZSTD_initStaticCCtx().
// Reject dynamic allocations in zstd and its bundled xxHash so new code paths cannot silently use malloc.
#define ZSTD_DEPS_MALLOC
#define ZSTD_malloc(size) ((void)(size), (void *)0)
#define ZSTD_calloc(count, size) ((void)(count), (void)(size), (void *)0)
#define ZSTD_free(pointer) ((void)(pointer))
#define XXH_NO_STDLIB


#define ZSTD_DEPS_NEED_MALLOC
#define ZSTD_DEPS_NEED_MATH64
/**** start inlining common/zstd_deps.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */




#ifndef ZSTD_DEPS_COMMON
#define ZSTD_DEPS_COMMON


#if defined(__linux) || defined(__linux__) || defined(linux) || defined(__gnu_linux__) || \
    defined(__CYGWIN__) || defined(__MSYS__)
#if !defined(_GNU_SOURCE) && !defined(__ANDROID__) /* NDK doesn't ship qsort_r(). */
#define _GNU_SOURCE
#endif
#endif

#include <limits.h>
#include <stddef.h>
#include <string.h>

#if defined(__GNUC__) && __GNUC__ >= 4
# define ZSTD_memcpy(d,s,l) __builtin_memcpy((d),(s),(l))
# define ZSTD_memmove(d,s,l) __builtin_memmove((d),(s),(l))
# define ZSTD_memset(p,v,l) __builtin_memset((p),(v),(l))
#else
# define ZSTD_memcpy(d,s,l) memcpy((d),(s),(l))
# define ZSTD_memmove(d,s,l) memmove((d),(s),(l))
# define ZSTD_memset(p,v,l) memset((p),(v),(l))
#endif

#endif /* ZSTD_DEPS_COMMON */


#ifdef ZSTD_DEPS_NEED_MALLOC
#ifndef ZSTD_DEPS_MALLOC
#define ZSTD_DEPS_MALLOC

#include <stdlib.h>

#define ZSTD_malloc(s) malloc(s)
#define ZSTD_calloc(n,s) calloc((n), (s))
#define ZSTD_free(p) free((p))

#endif /* ZSTD_DEPS_MALLOC */
#endif /* ZSTD_DEPS_NEED_MALLOC */


#ifdef ZSTD_DEPS_NEED_MATH64
#ifndef ZSTD_DEPS_MATH64
#define ZSTD_DEPS_MATH64

#define ZSTD_div64(dividend, divisor) ((dividend) / (divisor))

#endif /* ZSTD_DEPS_MATH64 */
#endif /* ZSTD_DEPS_NEED_MATH64 */


#ifdef ZSTD_DEPS_NEED_ASSERT
#ifndef ZSTD_DEPS_ASSERT
#define ZSTD_DEPS_ASSERT

#include <assert.h>

#endif /* ZSTD_DEPS_ASSERT */
#endif /* ZSTD_DEPS_NEED_ASSERT */


#ifdef ZSTD_DEPS_NEED_IO
#ifndef ZSTD_DEPS_IO
#define ZSTD_DEPS_IO

#include <stdio.h>
#define ZSTD_DEBUG_PRINT(...) fprintf(stderr, __VA_ARGS__)

#endif /* ZSTD_DEPS_IO */
#endif /* ZSTD_DEPS_NEED_IO */


#ifdef ZSTD_DEPS_NEED_STDINT
#ifndef ZSTD_DEPS_STDINT
#define ZSTD_DEPS_STDINT

#include <stdint.h>

#endif /* ZSTD_DEPS_STDINT */
#endif /* ZSTD_DEPS_NEED_STDINT */
/**** ended inlining common/zstd_deps.h ****/

/**** start inlining common/debug.c ****/
/* ******************************************************************
 * debug
 * Part of FSE library
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * You can contact the author at :
 * - Source repository : https://github.com/Cyan4973/FiniteStateEntropy
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
****************************************************************** */




/**** start inlining debug.h ****/
/* ******************************************************************
 * debug
 * Part of FSE library
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * You can contact the author at :
 * - Source repository : https://github.com/Cyan4973/FiniteStateEntropy
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
****************************************************************** */




#ifndef DEBUG_H_12987983217
#define DEBUG_H_12987983217



#define DEBUG_STATIC_ASSERT(c) (void)sizeof(char[(c) ? 1 : -1])



#ifndef DEBUGLEVEL
#  define DEBUGLEVEL 0
#endif




#if (DEBUGLEVEL>=1)
#  define ZSTD_DEPS_NEED_ASSERT
/**** skipping file: zstd_deps.h ****/
#else
#  ifndef assert   /* assert may be already defined, due to prior #include <assert.h> */
#    define assert(condition) ((void)0)   /* disable assert (default) */
#  endif
#endif

#if (DEBUGLEVEL>=2)
#  define ZSTD_DEPS_NEED_IO
/**** skipping file: zstd_deps.h ****/
extern int g_debuglevel; /* the variable is only declared,
                            it actually lives in debug.c,
                            and is shared by the whole process.
                            It's not thread-safe.
                            It's useful when enabling very verbose levels
                            on selective conditions (such as position in src) */

#  define RAWLOG(l, ...)                   \
    do {                                   \
        if (l<=g_debuglevel) {             \
            ZSTD_DEBUG_PRINT(__VA_ARGS__); \
        }                                  \
    } while (0)

#define STRINGIFY(x) #x
#define TOSTRING(x) STRINGIFY(x)
#define LINE_AS_STRING TOSTRING(__LINE__)

#  define DEBUGLOG(l, ...)                               \
    do {                                                 \
        if (l<=g_debuglevel) {                           \
            ZSTD_DEBUG_PRINT(__FILE__ ":" LINE_AS_STRING ": " __VA_ARGS__); \
            ZSTD_DEBUG_PRINT(" \n");                     \
        }                                                \
    } while (0)
#else
#  define RAWLOG(l, ...)   do { } while (0)    /* disabled */
#  define DEBUGLOG(l, ...) do { } while (0)    /* disabled */
#endif

#endif /* DEBUG_H_12987983217 */
/**** ended inlining debug.h ****/

#if !defined(ZSTD_LINUX_KERNEL) || (DEBUGLEVEL>=2)

int g_debuglevel = DEBUGLEVEL;
#endif
/**** ended inlining common/debug.c ****/
/**** start inlining common/entropy_common.c ****/
/* ******************************************************************
 * Common functions of New Generation Entropy library
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 *  You can contact the author at :
 *  - FSE+HUF source repository : https://github.com/Cyan4973/FiniteStateEntropy
 *  - Public forum : https://groups.google.com/forum/#!forum/lz4c
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
****************************************************************** */


/**** start inlining bmi2.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_BMI2_H
#define ZSTD_BMI2_H

/**** start inlining portability_macros.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_PORTABILITY_MACROS_H
#define ZSTD_PORTABILITY_MACROS_H





#ifndef __has_attribute
  #define __has_attribute(x) 0
#endif


#ifndef __has_builtin
#  define __has_builtin(x) 0
#endif


#ifndef __has_feature
#  define __has_feature(x) 0
#endif


#ifndef ZSTD_MEMORY_SANITIZER
#  if __has_feature(memory_sanitizer)
#    define ZSTD_MEMORY_SANITIZER 1
#  else
#    define ZSTD_MEMORY_SANITIZER 0
#  endif
#endif


#ifndef ZSTD_ADDRESS_SANITIZER
#  if __has_feature(address_sanitizer)
#    define ZSTD_ADDRESS_SANITIZER 1
#  elif defined(__SANITIZE_ADDRESS__)
#    define ZSTD_ADDRESS_SANITIZER 1
#  else
#    define ZSTD_ADDRESS_SANITIZER 0
#  endif
#endif


#ifndef ZSTD_DATAFLOW_SANITIZER
# if __has_feature(dataflow_sanitizer)
#  define ZSTD_DATAFLOW_SANITIZER 1
# else
#  define ZSTD_DATAFLOW_SANITIZER 0
# endif
#endif


#ifdef __ELF__
# define ZSTD_HIDE_ASM_FUNCTION(func) .hidden func
#elif defined(__APPLE__)
# define ZSTD_HIDE_ASM_FUNCTION(func) .private_extern func
#else
# define ZSTD_HIDE_ASM_FUNCTION(func)
#endif


#ifndef STATIC_BMI2
#  if defined(__BMI2__)
#    define STATIC_BMI2 1
#  elif defined(_MSC_VER) && defined(__AVX2__)
#    define STATIC_BMI2 1 /* MSVC does not have a BMI2 specific flag, but every CPU that supports AVX2 also supports BMI2 */
#  endif
#endif

#ifndef STATIC_BMI2
#  define STATIC_BMI2 0
#endif


#ifndef DYNAMIC_BMI2
#  if ((defined(__clang__) && __has_attribute(__target__)) \
      || (defined(__GNUC__) \
          && (__GNUC__ >= 5 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 8)))) \
      && (defined(__i386__) || defined(__x86_64__) || defined(_M_IX86) || defined(_M_X64)) \
      && !defined(__BMI2__)
#    define DYNAMIC_BMI2 1
#  else
#    define DYNAMIC_BMI2 0
#  endif
#endif


#if defined(ZSTD_LINUX_KERNEL)
#  if defined(__KERNEL__) && defined(CONFIG_X86) && \
      !defined(__DISABLE_EXPORTS)
#    define ZSTD_USE_KERNEL_CPU_FEATURES
#  endif
#endif


#if defined(__GNUC__)
#  if defined(__linux__) || defined(__linux) || defined(__APPLE__) || defined(_WIN32)
#    if ZSTD_MEMORY_SANITIZER
#      define ZSTD_ASM_SUPPORTED 0
#    elif ZSTD_DATAFLOW_SANITIZER
#      define ZSTD_ASM_SUPPORTED 0
#    else
#      define ZSTD_ASM_SUPPORTED 1
#    endif
#  else
#    define ZSTD_ASM_SUPPORTED 0
#  endif
#else
#  define ZSTD_ASM_SUPPORTED 0
#endif


#if !defined(ZSTD_DISABLE_ASM) &&                                 \
    ZSTD_ASM_SUPPORTED &&                                         \
    defined(__x86_64__) &&                                        \
    (DYNAMIC_BMI2 || defined(__BMI2__))
# define ZSTD_ENABLE_ASM_X86_64_BMI2 1
#else
# define ZSTD_ENABLE_ASM_X86_64_BMI2 0
#endif


#if defined(__ELF__) && (defined(__x86_64__) || defined(__i386__)) \
    && defined(__has_include)
# if __has_include(<cet.h>)
#  include <cet.h>
#  define ZSTD_CET_ENDBRANCH _CET_ENDBR
# endif
#endif

#ifndef ZSTD_CET_ENDBRANCH
# define ZSTD_CET_ENDBRANCH
#endif


#if defined(ZSTD_CLEVEL_DEFAULT) \
    || defined(ZSTD_EXCLUDE_DFAST_BLOCK_COMPRESSOR) \
    || defined(ZSTD_EXCLUDE_GREEDY_BLOCK_COMPRESSOR) \
    || defined(ZSTD_EXCLUDE_LAZY_BLOCK_COMPRESSOR) \
    || defined(ZSTD_EXCLUDE_LAZY2_BLOCK_COMPRESSOR) \
    || defined(ZSTD_EXCLUDE_BTLAZY2_BLOCK_COMPRESSOR) \
    || defined(ZSTD_EXCLUDE_BTOPT_BLOCK_COMPRESSOR) \
    || defined(ZSTD_EXCLUDE_BTULTRA_BLOCK_COMPRESSOR)
# define ZSTD_IS_DETERMINISTIC_BUILD 0
#else
# define ZSTD_IS_DETERMINISTIC_BUILD 1
#endif

#endif /* ZSTD_PORTABILITY_MACROS_H */
/**** ended inlining portability_macros.h ****/

#if defined(ZSTD_USE_KERNEL_CPU_FEATURES)
#  include <asm/cpufeature.h>
#endif


#if !DYNAMIC_BMI2
#  define ZSTD_USE_BMI2(bmi2) 0
#  define ZSTD_SET_BMI2(state, value) do { } while (0)
#elif defined(ZSTD_USE_KERNEL_CPU_FEATURES)
#  define ZSTD_USE_BMI2(bmi2) cpu_feature_enabled(X86_FEATURE_BMI2)
#  define ZSTD_SET_BMI2(state, value) do { (state) = 0; } while (0)
#else
#  define ZSTD_USE_BMI2(bmi2) (bmi2)
#  define ZSTD_SET_BMI2(state, value) do { (state) = (value); } while (0)
#endif

#endif /* ZSTD_BMI2_H */
/**** ended inlining bmi2.h ****/
/**** start inlining mem.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef MEM_H_MODULE
#define MEM_H_MODULE


#include <stddef.h>  /* size_t, ptrdiff_t */
/**** start inlining compiler.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_COMPILER_H
#define ZSTD_COMPILER_H

#include <stddef.h>

/**** skipping file: portability_macros.h ****/




#if !defined(ZSTD_NO_INLINE)
#if (defined(__GNUC__) && !defined(__STRICT_ANSI__)) || defined(__cplusplus) || defined(__STDC_VERSION__) && __STDC_VERSION__ >= 199901L   /* C99 */
#  define INLINE_KEYWORD inline
#else
#  define INLINE_KEYWORD
#endif

#if defined(__GNUC__) || defined(__IAR_SYSTEMS_ICC__)
#  define FORCE_INLINE_ATTR __attribute__((always_inline))
#elif defined(_MSC_VER)
#  define FORCE_INLINE_ATTR __forceinline
#else
#  define FORCE_INLINE_ATTR
#endif

#else

#define INLINE_KEYWORD
#define FORCE_INLINE_ATTR

#endif


#if  defined(_MSC_VER)
#  define WIN_CDECL __cdecl
#else
#  define WIN_CDECL
#endif


#if defined(__GNUC__) || defined(__clang__) || defined(__IAR_SYSTEMS_ICC__)  /* clang-cl defines __clang__ but not __GNUC__ */
#  define UNUSED_ATTR __attribute__((unused))
#else
#  define UNUSED_ATTR
#endif


#define FORCE_INLINE_TEMPLATE static INLINE_KEYWORD FORCE_INLINE_ATTR UNUSED_ATTR

#if !defined(__clang__) && defined(__GNUC__) && __GNUC__ >= 4 && __GNUC_MINOR__ >= 8 && __GNUC__ < 5
#  define HINT_INLINE static INLINE_KEYWORD
#else
#  define HINT_INLINE FORCE_INLINE_TEMPLATE
#endif


#ifndef MEM_STATIC  /* already defined in Linux Kernel mem.h */
#if defined(__GNUC__)
#  define MEM_STATIC static __inline UNUSED_ATTR
#elif defined(__IAR_SYSTEMS_ICC__)
#  define MEM_STATIC static inline UNUSED_ATTR
#elif defined (__cplusplus) || (defined (__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L) /* C99 */)
#  define MEM_STATIC static inline UNUSED_ATTR
#elif defined(_MSC_VER)
#  define MEM_STATIC static __inline UNUSED_ATTR
#else
#  define MEM_STATIC static  /* this version may generate warnings for unused static functions; disable the relevant warning */
#endif
#endif


#ifdef _MSC_VER
#  define FORCE_NOINLINE static __declspec(noinline)
#else
#  if defined(__GNUC__) || defined(__IAR_SYSTEMS_ICC__)
#    define FORCE_NOINLINE static __attribute__((__noinline__))
#  else
#    define FORCE_NOINLINE static
#  endif
#endif



#if defined(__GNUC__) || defined(__IAR_SYSTEMS_ICC__)
#  define TARGET_ATTRIBUTE(target) __attribute__((__target__(target)))
#else
#  define TARGET_ATTRIBUTE(target)
#endif


#define BMI2_TARGET_ATTRIBUTE TARGET_ATTRIBUTE("lzcnt,bmi,bmi2")


#if defined(NO_PREFETCH)
#  define PREFETCH_L1(ptr)  do { (void)(ptr); } while (0)  /* disabled */
#  define PREFETCH_L2(ptr)  do { (void)(ptr); } while (0)  /* disabled */
#else
#  if defined(_MSC_VER) && (defined(_M_X64) || defined(_M_I86)) && !defined(_M_ARM64EC)  /* _mm_prefetch() is not defined outside of x86/x64 */
#    include <mmintrin.h>   /* https://msdn.microsoft.com/fr-fr/library/84szxsww(v=vs.90).aspx */
#    define PREFETCH_L1(ptr)  _mm_prefetch((const char*)(ptr), _MM_HINT_T0)
#    define PREFETCH_L2(ptr)  _mm_prefetch((const char*)(ptr), _MM_HINT_T1)
#  elif defined(__GNUC__) && ( (__GNUC__ >= 4) || ( (__GNUC__ == 3) && (__GNUC_MINOR__ >= 1) ) )
#    define PREFETCH_L1(ptr)  __builtin_prefetch((ptr), 0 /* rw==read */, 3 /* locality */)
#    define PREFETCH_L2(ptr)  __builtin_prefetch((ptr), 0 /* rw==read */, 2 /* locality */)
#  elif defined(__aarch64__)

#    define PREFETCH_L1(ptr)  do { __asm__ __volatile__("prfm pldl1keep, %0" ::"Q"(*(const char*)(ptr))); } while (0)
#    define PREFETCH_L2(ptr)  do { __asm__ __volatile__("prfm pldl2keep, %0" ::"Q"(*(const char*)(ptr))); } while (0)
#  else
#    define PREFETCH_L1(ptr) do { (void)(ptr); } while (0)  /* disabled */
#    define PREFETCH_L2(ptr) do { (void)(ptr); } while (0)  /* disabled */
#  endif
#endif  /* NO_PREFETCH */

#define CACHELINE_SIZE 64

#define PREFETCH_AREA(p, s)                              \
    do {                                                 \
        const char* const _ptr = (const char*)(p);       \
        size_t const _size = (size_t)(s);                \
        size_t _pos;                                     \
        for (_pos=0; _pos<_size; _pos+=CACHELINE_SIZE) { \
            PREFETCH_L2(_ptr + _pos);                    \
        }                                                \
    } while (0)


#if !defined(__INTEL_COMPILER) && !defined(__clang__) && defined(__GNUC__) && !defined(__LCC__)
#  if (__GNUC__ == 4 && __GNUC_MINOR__ > 3) || (__GNUC__ >= 5)
#    define DONT_VECTORIZE __attribute__((optimize("no-tree-vectorize")))
#  else
#    define DONT_VECTORIZE _Pragma("GCC optimize(\"no-tree-vectorize\")")
#  endif
#else
#  define DONT_VECTORIZE
#endif


#if defined(__GNUC__)
#define LIKELY(x) (__builtin_expect((x), 1))
#define UNLIKELY(x) (__builtin_expect((x), 0))
#else
#define LIKELY(x) (x)
#define UNLIKELY(x) (x)
#endif

#if __has_builtin(__builtin_unreachable) || (defined(__GNUC__) && (__GNUC__ > 4 || (__GNUC__ == 4 && __GNUC_MINOR__ >= 5)))
#  define ZSTD_UNREACHABLE do { assert(0), __builtin_unreachable(); } while (0)
#else
#  define ZSTD_UNREACHABLE do { assert(0); } while (0)
#endif


#ifdef _MSC_VER    /* Visual Studio */
#  include <intrin.h>                    /* For Visual 2005 */
#  pragma warning(disable : 4100)        /* disable: C4100: unreferenced formal parameter */
#  pragma warning(disable : 4127)        /* disable: C4127: conditional expression is constant */
#  pragma warning(disable : 4204)        /* disable: C4204: non-constant aggregate initializer */
#  pragma warning(disable : 4214)        /* disable: C4214: non-int bitfields */
#  pragma warning(disable : 4324)        /* disable: C4324: padded structure */
#endif


#if !defined(ZSTD_NO_INTRINSICS)
#  if defined(__AVX2__)
#    define ZSTD_ARCH_X86_AVX2
#  endif
#  if defined(__SSE2__) || defined(_M_X64) || (defined (_M_IX86) && defined(_M_IX86_FP) && (_M_IX86_FP >= 2))
#    define ZSTD_ARCH_X86_SSE2
#  endif
#  if defined(__ARM_NEON) || defined(_M_ARM64)
#    define ZSTD_ARCH_ARM_NEON
#  endif
#  if defined(__ARM_FEATURE_SVE)
#    define ZSTD_ARCH_ARM_SVE
#  endif
#  if defined(__ARM_FEATURE_SVE2)
#    define ZSTD_ARCH_ARM_SVE2
#  endif
#  if defined(__riscv) && defined(__riscv_vector)
#    if ((defined(__GNUC__) && !defined(__clang__) && __GNUC__ >= 14) || \
        (defined(__clang__) && __clang_major__ >= 19))
        #define ZSTD_ARCH_RISCV_RVV
#  endif
#endif
#
#  if defined(ZSTD_ARCH_X86_AVX2)
#    include <immintrin.h>
#  endif
#  if defined(ZSTD_ARCH_X86_SSE2)
#    include <emmintrin.h>
#  elif defined(ZSTD_ARCH_ARM_NEON)
#    include <arm_neon.h>
#  endif
#  if defined(ZSTD_ARCH_ARM_SVE) || defined(ZSTD_ARCH_ARM_SVE2)
#    include <arm_sve.h>
#  endif
#  if defined(ZSTD_ARCH_RISCV_RVV)
#    include <riscv_vector.h>
#  endif
#endif


#if defined(__STDC_VERSION__) && (__STDC_VERSION__ > 201710L) && defined(__has_c_attribute)
# define ZSTD_HAS_C_ATTRIBUTE(x) __has_c_attribute(x)
#else
# define ZSTD_HAS_C_ATTRIBUTE(x) 0
#endif


#if defined(__cplusplus) && defined(__has_cpp_attribute)
# define ZSTD_HAS_CPP_ATTRIBUTE(x) __has_cpp_attribute(x)
#else
# define ZSTD_HAS_CPP_ATTRIBUTE(x) 0
#endif


#ifndef ZSTD_FALLTHROUGH
# if ZSTD_HAS_C_ATTRIBUTE(fallthrough)
#  define ZSTD_FALLTHROUGH [[fallthrough]]
# elif ZSTD_HAS_CPP_ATTRIBUTE(fallthrough)
#  define ZSTD_FALLTHROUGH [[fallthrough]]
# elif __has_attribute(__fallthrough__)

#  define ZSTD_FALLTHROUGH ; __attribute__((__fallthrough__))
# else
#  define ZSTD_FALLTHROUGH
# endif
#endif




MEM_STATIC int ZSTD_isPower2(size_t u) {
    return (u & (u-1)) == 0;
}



#ifndef ZSTD_ALIGNOF
# if defined(__GNUC__) || defined(_MSC_VER)


#  define ZSTD_ALIGNOF(T) __alignof(T)

# elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)

#  include <stdalign.h>
#  define ZSTD_ALIGNOF(T) alignof(T)

# else

#  define ZSTD_ALIGNOF(T) (sizeof(void*) < sizeof(T) ? sizeof(void*) : sizeof(T))

# endif
#endif /* ZSTD_ALIGNOF */

#ifndef ZSTD_ALIGNED

# if defined(__GNUC__) || defined(__clang__)
#  define ZSTD_ALIGNED(a) __attribute__((aligned(a)))
# elif defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L) /* C11 */
#  define ZSTD_ALIGNED(a) _Alignas(a)
#elif defined(_MSC_VER)
#  define ZSTD_ALIGNED(n) __declspec(align(n))
# else

#  define ZSTD_ALIGNED(...)
# endif
#endif /* ZSTD_ALIGNED */





#ifndef ZSTD_ALLOW_POINTER_OVERFLOW_ATTR
#  if __has_attribute(no_sanitize)
#    if !defined(__clang__) && defined(__GNUC__) && __GNUC__ < 8

#      define ZSTD_ALLOW_POINTER_OVERFLOW_ATTR __attribute__((no_sanitize("signed-integer-overflow")))
#    else

#      define ZSTD_ALLOW_POINTER_OVERFLOW_ATTR __attribute__((no_sanitize("pointer-overflow")))
#    endif
#  else
#    define ZSTD_ALLOW_POINTER_OVERFLOW_ATTR
#  endif
#endif


MEM_STATIC
ZSTD_ALLOW_POINTER_OVERFLOW_ATTR
ptrdiff_t ZSTD_wrappedPtrDiff(unsigned char const* lhs, unsigned char const* rhs)
{
    return lhs - rhs;
}


MEM_STATIC
ZSTD_ALLOW_POINTER_OVERFLOW_ATTR
const void* ZSTD_wrappedPtrAdd(const void* ptr, ptrdiff_t add)
{
    return (const char*)ptr + add;
}


MEM_STATIC
ZSTD_ALLOW_POINTER_OVERFLOW_ATTR
const void* ZSTD_wrappedPtrSub(const void* ptr, ptrdiff_t sub)
{
    return (const char*)ptr - sub;
}


MEM_STATIC
void* ZSTD_maybeNullPtrAdd(void* ptr, ptrdiff_t add)
{
    return add > 0 ? (char*)ptr + add : ptr;
}


#ifdef __MINGW32__
#ifndef ZSTD_ASAN_DONT_POISON_WORKSPACE
#define ZSTD_ASAN_DONT_POISON_WORKSPACE 1
#endif
#ifndef ZSTD_MSAN_DONT_POISON_WORKSPACE
#define ZSTD_MSAN_DONT_POISON_WORKSPACE 1
#endif
#endif

#if ZSTD_MEMORY_SANITIZER && !defined(ZSTD_MSAN_DONT_POISON_WORKSPACE)

#include <stddef.h>  /* size_t */
#define ZSTD_DEPS_NEED_STDINT
/**** skipping file: zstd_deps.h ****/


void __msan_unpoison(const volatile void *a, size_t size);


void __msan_poison(const volatile void *a, size_t size);


intptr_t __msan_test_shadow(const volatile void *x, size_t size);


void __msan_print_shadow(const volatile void *x, size_t size);
#endif

#if ZSTD_ADDRESS_SANITIZER && !defined(ZSTD_ASAN_DONT_POISON_WORKSPACE)

#include <stddef.h>  /* size_t */


void __asan_poison_memory_region(void const volatile *addr, size_t size);


void __asan_unpoison_memory_region(void const volatile *addr, size_t size);
#endif

#endif /* ZSTD_COMPILER_H */
/**** ended inlining compiler.h ****/
/**** skipping file: debug.h ****/
/**** skipping file: zstd_deps.h ****/



#if defined(_MSC_VER)   /* Visual Studio */
#   include <stdlib.h>  /* _byteswap_ulong */
#   include <intrin.h>  /* _byteswap_* */
#elif defined(__ICCARM__)
#   include <intrinsics.h>
#endif


#if  !defined (__VMS) && (defined (__cplusplus) || (defined (__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L) /* C99 */) )
#  if defined(_AIX)
#    include <inttypes.h>
#  else
#    include <stdint.h> /* intptr_t */
#  endif
  typedef   uint8_t BYTE;
  typedef   uint8_t U8;
  typedef    int8_t S8;
  typedef  uint16_t U16;
  typedef   int16_t S16;
  typedef  uint32_t U32;
  typedef   int32_t S32;
  typedef  uint64_t U64;
  typedef   int64_t S64;
#else
# include <limits.h>
#if CHAR_BIT != 8
#  error "this implementation requires char to be exactly 8-bit type"
#endif
  typedef unsigned char      BYTE;
  typedef unsigned char      U8;
  typedef   signed char      S8;
#if USHRT_MAX != 65535
#  error "this implementation requires short to be exactly 16-bit type"
#endif
  typedef unsigned short      U16;
  typedef   signed short      S16;
#if UINT_MAX != 4294967295
#  error "this implementation requires int to be exactly 32-bit type"
#endif
  typedef unsigned int        U32;
  typedef   signed int        S32;

  typedef unsigned long long  U64;
  typedef   signed long long  S64;
#endif



MEM_STATIC unsigned MEM_32bits(void);
MEM_STATIC unsigned MEM_64bits(void);
MEM_STATIC unsigned MEM_isLittleEndian(void);


MEM_STATIC U16 MEM_read16(const void* memPtr);
MEM_STATIC U32 MEM_read32(const void* memPtr);
MEM_STATIC U64 MEM_read64(const void* memPtr);
MEM_STATIC size_t MEM_readST(const void* memPtr);

MEM_STATIC void MEM_write16(void* memPtr, U16 value);
MEM_STATIC void MEM_write32(void* memPtr, U32 value);
MEM_STATIC void MEM_write64(void* memPtr, U64 value);


MEM_STATIC U16 MEM_readLE16(const void* memPtr);
MEM_STATIC U32 MEM_readLE24(const void* memPtr);
MEM_STATIC U32 MEM_readLE32(const void* memPtr);
MEM_STATIC U64 MEM_readLE64(const void* memPtr);
MEM_STATIC size_t MEM_readLEST(const void* memPtr);

MEM_STATIC void MEM_writeLE16(void* memPtr, U16 val);
MEM_STATIC void MEM_writeLE24(void* memPtr, U32 val);
MEM_STATIC void MEM_writeLE32(void* memPtr, U32 val32);
MEM_STATIC void MEM_writeLE64(void* memPtr, U64 val64);
MEM_STATIC void MEM_writeLEST(void* memPtr, size_t val);


MEM_STATIC U32 MEM_readBE32(const void* memPtr);
MEM_STATIC U64 MEM_readBE64(const void* memPtr);
MEM_STATIC size_t MEM_readBEST(const void* memPtr);

MEM_STATIC void MEM_writeBE32(void* memPtr, U32 val32);
MEM_STATIC void MEM_writeBE64(void* memPtr, U64 val64);
MEM_STATIC void MEM_writeBEST(void* memPtr, size_t val);


MEM_STATIC U32 MEM_swap32(U32 in);
MEM_STATIC U64 MEM_swap64(U64 in);
MEM_STATIC size_t MEM_swapST(size_t in);




#ifndef MEM_FORCE_MEMORY_ACCESS   /* can be defined externally, on command line for example */
#  ifdef __GNUC__
#    define MEM_FORCE_MEMORY_ACCESS 1
#  endif
#endif

MEM_STATIC unsigned MEM_32bits(void) { return sizeof(size_t)==4; }
MEM_STATIC unsigned MEM_64bits(void) { return sizeof(size_t)==8; }

MEM_STATIC unsigned MEM_isLittleEndian(void)
{
#if defined(__BYTE_ORDER__) && defined(__ORDER_LITTLE_ENDIAN__) && (__BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
    return 1;
#elif defined(__BYTE_ORDER__) && defined(__ORDER_BIG_ENDIAN__) && (__BYTE_ORDER__ == __ORDER_BIG_ENDIAN__)
    return 0;
#elif defined(__clang__) && __LITTLE_ENDIAN__
    return 1;
#elif defined(__clang__) && __BIG_ENDIAN__
    return 0;
#elif defined(_MSC_VER) && (_M_X64 || _M_IX86)
    return 1;
#elif defined(__DMC__) && defined(_M_IX86)
    return 1;
#elif defined(__IAR_SYSTEMS_ICC__) && __LITTLE_ENDIAN__
    return 1;
#else
    const union { U32 u; BYTE c[4]; } one = { 1 };   /* don't use static : performance detrimental  */
    return one.c[0];
#endif
}

#if defined(MEM_FORCE_MEMORY_ACCESS) && (MEM_FORCE_MEMORY_ACCESS==2)


MEM_STATIC U16 MEM_read16(const void* memPtr) { return *(const U16*) memPtr; }
MEM_STATIC U32 MEM_read32(const void* memPtr) { return *(const U32*) memPtr; }
MEM_STATIC U64 MEM_read64(const void* memPtr) { return *(const U64*) memPtr; }
MEM_STATIC size_t MEM_readST(const void* memPtr) { return *(const size_t*) memPtr; }

MEM_STATIC void MEM_write16(void* memPtr, U16 value) { *(U16*)memPtr = value; }
MEM_STATIC void MEM_write32(void* memPtr, U32 value) { *(U32*)memPtr = value; }
MEM_STATIC void MEM_write64(void* memPtr, U64 value) { *(U64*)memPtr = value; }

#elif defined(MEM_FORCE_MEMORY_ACCESS) && (MEM_FORCE_MEMORY_ACCESS==1)

typedef __attribute__((aligned(1))) U16 unalign16;
typedef __attribute__((aligned(1))) U32 unalign32;
typedef __attribute__((aligned(1))) U64 unalign64;
typedef __attribute__((aligned(1))) size_t unalignArch;

MEM_STATIC U16 MEM_read16(const void* ptr) { return *(const unalign16*)ptr; }
MEM_STATIC U32 MEM_read32(const void* ptr) { return *(const unalign32*)ptr; }
MEM_STATIC U64 MEM_read64(const void* ptr) { return *(const unalign64*)ptr; }
MEM_STATIC size_t MEM_readST(const void* ptr) { return *(const unalignArch*)ptr; }

MEM_STATIC void MEM_write16(void* memPtr, U16 value) { *(unalign16*)memPtr = value; }
MEM_STATIC void MEM_write32(void* memPtr, U32 value) { *(unalign32*)memPtr = value; }
MEM_STATIC void MEM_write64(void* memPtr, U64 value) { *(unalign64*)memPtr = value; }

#else



MEM_STATIC U16 MEM_read16(const void* memPtr)
{
    U16 val; ZSTD_memcpy(&val, memPtr, sizeof(val)); return val;
}

MEM_STATIC U32 MEM_read32(const void* memPtr)
{
    U32 val; ZSTD_memcpy(&val, memPtr, sizeof(val)); return val;
}

MEM_STATIC U64 MEM_read64(const void* memPtr)
{
    U64 val; ZSTD_memcpy(&val, memPtr, sizeof(val)); return val;
}

MEM_STATIC size_t MEM_readST(const void* memPtr)
{
    size_t val; ZSTD_memcpy(&val, memPtr, sizeof(val)); return val;
}

MEM_STATIC void MEM_write16(void* memPtr, U16 value)
{
    ZSTD_memcpy(memPtr, &value, sizeof(value));
}

MEM_STATIC void MEM_write32(void* memPtr, U32 value)
{
    ZSTD_memcpy(memPtr, &value, sizeof(value));
}

MEM_STATIC void MEM_write64(void* memPtr, U64 value)
{
    ZSTD_memcpy(memPtr, &value, sizeof(value));
}

#endif /* MEM_FORCE_MEMORY_ACCESS */

MEM_STATIC U32 MEM_swap32_fallback(U32 in)
{
    return  ((in << 24) & 0xff000000 ) |
            ((in <<  8) & 0x00ff0000 ) |
            ((in >>  8) & 0x0000ff00 ) |
            ((in >> 24) & 0x000000ff );
}

MEM_STATIC U32 MEM_swap32(U32 in)
{
#if defined(_MSC_VER)     /* Visual Studio */
    return _byteswap_ulong(in);
#elif (defined (__GNUC__) && (__GNUC__ * 100 + __GNUC_MINOR__ >= 403)) \
  || (defined(__clang__) && __has_builtin(__builtin_bswap32))
    return __builtin_bswap32(in);
#elif defined(__ICCARM__)
    return __REV(in);
#else
    return MEM_swap32_fallback(in);
#endif
}

MEM_STATIC U64 MEM_swap64_fallback(U64 in)
{
     return  ((in << 56) & 0xff00000000000000ULL) |
            ((in << 40) & 0x00ff000000000000ULL) |
            ((in << 24) & 0x0000ff0000000000ULL) |
            ((in << 8)  & 0x000000ff00000000ULL) |
            ((in >> 8)  & 0x00000000ff000000ULL) |
            ((in >> 24) & 0x0000000000ff0000ULL) |
            ((in >> 40) & 0x000000000000ff00ULL) |
            ((in >> 56) & 0x00000000000000ffULL);
}

MEM_STATIC U64 MEM_swap64(U64 in)
{
#if defined(_MSC_VER)     /* Visual Studio */
    return _byteswap_uint64(in);
#elif (defined (__GNUC__) && (__GNUC__ * 100 + __GNUC_MINOR__ >= 403)) \
  || (defined(__clang__) && __has_builtin(__builtin_bswap64))
    return __builtin_bswap64(in);
#else
    return MEM_swap64_fallback(in);
#endif
}

MEM_STATIC size_t MEM_swapST(size_t in)
{
    if (MEM_32bits())
        return (size_t)MEM_swap32((U32)in);
    else
        return (size_t)MEM_swap64((U64)in);
}



MEM_STATIC U16 MEM_readLE16(const void* memPtr)
{
    if (MEM_isLittleEndian())
        return MEM_read16(memPtr);
    else {
        const BYTE* p = (const BYTE*)memPtr;
        return (U16)(p[0] + (p[1]<<8));
    }
}

MEM_STATIC void MEM_writeLE16(void* memPtr, U16 val)
{
    if (MEM_isLittleEndian()) {
        MEM_write16(memPtr, val);
    } else {
        BYTE* p = (BYTE*)memPtr;
        p[0] = (BYTE)val;
        p[1] = (BYTE)(val>>8);
    }
}

MEM_STATIC U32 MEM_readLE24(const void* memPtr)
{
    return (U32)MEM_readLE16(memPtr) + ((U32)(((const BYTE*)memPtr)[2]) << 16);
}

MEM_STATIC void MEM_writeLE24(void* memPtr, U32 val)
{
    MEM_writeLE16(memPtr, (U16)val);
    ((BYTE*)memPtr)[2] = (BYTE)(val>>16);
}

MEM_STATIC U32 MEM_readLE32(const void* memPtr)
{
    if (MEM_isLittleEndian())
        return MEM_read32(memPtr);
    else
        return MEM_swap32(MEM_read32(memPtr));
}

MEM_STATIC void MEM_writeLE32(void* memPtr, U32 val32)
{
    if (MEM_isLittleEndian())
        MEM_write32(memPtr, val32);
    else
        MEM_write32(memPtr, MEM_swap32(val32));
}

MEM_STATIC U64 MEM_readLE64(const void* memPtr)
{
    if (MEM_isLittleEndian())
        return MEM_read64(memPtr);
    else
        return MEM_swap64(MEM_read64(memPtr));
}

MEM_STATIC void MEM_writeLE64(void* memPtr, U64 val64)
{
    if (MEM_isLittleEndian())
        MEM_write64(memPtr, val64);
    else
        MEM_write64(memPtr, MEM_swap64(val64));
}

MEM_STATIC size_t MEM_readLEST(const void* memPtr)
{
    if (MEM_32bits())
        return (size_t)MEM_readLE32(memPtr);
    else
        return (size_t)MEM_readLE64(memPtr);
}

MEM_STATIC void MEM_writeLEST(void* memPtr, size_t val)
{
    if (MEM_32bits())
        MEM_writeLE32(memPtr, (U32)val);
    else
        MEM_writeLE64(memPtr, (U64)val);
}



MEM_STATIC U32 MEM_readBE32(const void* memPtr)
{
    if (MEM_isLittleEndian())
        return MEM_swap32(MEM_read32(memPtr));
    else
        return MEM_read32(memPtr);
}

MEM_STATIC void MEM_writeBE32(void* memPtr, U32 val32)
{
    if (MEM_isLittleEndian())
        MEM_write32(memPtr, MEM_swap32(val32));
    else
        MEM_write32(memPtr, val32);
}

MEM_STATIC U64 MEM_readBE64(const void* memPtr)
{
    if (MEM_isLittleEndian())
        return MEM_swap64(MEM_read64(memPtr));
    else
        return MEM_read64(memPtr);
}

MEM_STATIC void MEM_writeBE64(void* memPtr, U64 val64)
{
    if (MEM_isLittleEndian())
        MEM_write64(memPtr, MEM_swap64(val64));
    else
        MEM_write64(memPtr, val64);
}

MEM_STATIC size_t MEM_readBEST(const void* memPtr)
{
    if (MEM_32bits())
        return (size_t)MEM_readBE32(memPtr);
    else
        return (size_t)MEM_readBE64(memPtr);
}

MEM_STATIC void MEM_writeBEST(void* memPtr, size_t val)
{
    if (MEM_32bits())
        MEM_writeBE32(memPtr, (U32)val);
    else
        MEM_writeBE64(memPtr, (U64)val);
}


MEM_STATIC void MEM_check(void) { DEBUG_STATIC_ASSERT((sizeof(size_t)==4) || (sizeof(size_t)==8)); }

#endif /* MEM_H_MODULE */
/**** ended inlining mem.h ****/
/**** start inlining error_private.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */



#ifndef ERROR_H_MODULE
#define ERROR_H_MODULE


/**** start inlining ../zstd_errors.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_ERRORS_H_398273423
#define ZSTD_ERRORS_H_398273423

#if defined (__cplusplus)
extern "C" {
#endif


#ifndef ZSTDERRORLIB_VISIBLE

#  ifdef ZSTDERRORLIB_VISIBILITY
#    define ZSTDERRORLIB_VISIBLE ZSTDERRORLIB_VISIBILITY
#  elif defined(__GNUC__) && (__GNUC__ >= 4) && !defined(__MINGW32__)
#    define ZSTDERRORLIB_VISIBLE __attribute__ ((visibility ("default")))
#  else
#    define ZSTDERRORLIB_VISIBLE
#  endif
#endif

#ifndef ZSTDERRORLIB_HIDDEN
#  if defined(__GNUC__) && (__GNUC__ >= 4) && !defined(__MINGW32__)
#    define ZSTDERRORLIB_HIDDEN __attribute__ ((visibility ("hidden")))
#  else
#    define ZSTDERRORLIB_HIDDEN
#  endif
#endif

#if defined(ZSTD_DLL_EXPORT) && (ZSTD_DLL_EXPORT==1)
#  define ZSTDERRORLIB_API __declspec(dllexport) ZSTDERRORLIB_VISIBLE
#elif defined(ZSTD_DLL_IMPORT) && (ZSTD_DLL_IMPORT==1)
#  define ZSTDERRORLIB_API __declspec(dllimport) ZSTDERRORLIB_VISIBLE /* It isn't required but allows to generate better code, saving a function pointer load from the IAT and an indirect jump.*/
#else
#  define ZSTDERRORLIB_API ZSTDERRORLIB_VISIBLE
#endif


typedef enum {
  ZSTD_error_no_error = 0,
  ZSTD_error_GENERIC  = 1,
  ZSTD_error_prefix_unknown                = 10,
  ZSTD_error_version_unsupported           = 12,
  ZSTD_error_frameParameter_unsupported    = 14,
  ZSTD_error_frameParameter_windowTooLarge = 16,
  ZSTD_error_corruption_detected = 20,
  ZSTD_error_checksum_wrong      = 22,
  ZSTD_error_literals_headerWrong = 24,
  ZSTD_error_dictionary_corrupted      = 30,
  ZSTD_error_dictionary_wrong          = 32,
  ZSTD_error_dictionaryCreation_failed = 34,
  ZSTD_error_parameter_unsupported   = 40,
  ZSTD_error_parameter_combination_unsupported = 41,
  ZSTD_error_parameter_outOfBound    = 42,
  ZSTD_error_tableLog_tooLarge       = 44,
  ZSTD_error_maxSymbolValue_tooLarge = 46,
  ZSTD_error_maxSymbolValue_tooSmall = 48,
  ZSTD_error_cannotProduce_uncompressedBlock = 49,
  ZSTD_error_stabilityCondition_notRespected = 50,
  ZSTD_error_stage_wrong       = 60,
  ZSTD_error_init_missing      = 62,
  ZSTD_error_memory_allocation = 64,
  ZSTD_error_workSpace_tooSmall= 66,
  ZSTD_error_dstSize_tooSmall = 70,
  ZSTD_error_srcSize_wrong    = 72,
  ZSTD_error_dstBuffer_null   = 74,
  ZSTD_error_noForwardProgress_destFull = 80,
  ZSTD_error_noForwardProgress_inputEmpty = 82,

  ZSTD_error_frameIndex_tooLarge = 100,
  ZSTD_error_seekableIO          = 102,
  ZSTD_error_dstBuffer_wrong     = 104,
  ZSTD_error_srcBuffer_wrong     = 105,
  ZSTD_error_sequenceProducer_failed = 106,
  ZSTD_error_externalSequences_invalid = 107,
  ZSTD_error_maxCode = 120  /* never EVER use this value directly, it can change in future versions! Use ZSTD_isError() instead */
} ZSTD_ErrorCode;

ZSTDERRORLIB_API const char* ZSTD_getErrorString(ZSTD_ErrorCode code);   /**< Same as ZSTD_getErrorName, but using a `ZSTD_ErrorCode` enum argument */


#if defined (__cplusplus)
}
#endif

#endif /* ZSTD_ERRORS_H_398273423 */
/**** ended inlining ../zstd_errors.h ****/
/**** skipping file: compiler.h ****/
/**** skipping file: debug.h ****/
/**** skipping file: zstd_deps.h ****/


#if defined(__GNUC__)
#  define ERR_STATIC static __attribute__((unused))
#elif defined (__cplusplus) || (defined (__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L) /* C99 */)
#  define ERR_STATIC static inline
#elif defined(_MSC_VER)
#  define ERR_STATIC static __inline
#else
#  define ERR_STATIC static  /* this version may generate warnings for unused static functions; disable the relevant warning */
#endif



typedef ZSTD_ErrorCode ERR_enum;
#define PREFIX(name) ZSTD_error_##name



#undef ERROR   /* already defined on Visual Studio */
#define ERROR(name) ZSTD_ERROR(name)
#define ZSTD_ERROR(name) ((size_t)-PREFIX(name))

ERR_STATIC unsigned ERR_isError(size_t code) { return (code > ERROR(maxCode)); }

ERR_STATIC ERR_enum ERR_getErrorCode(size_t code) { if (!ERR_isError(code)) return (ERR_enum)0; return (ERR_enum) (0-code); }


#define CHECK_V_F(e, f)     \
    size_t const e = f;     \
    do {                    \
        if (ERR_isError(e)) \
            return e;       \
    } while (0)
#define CHECK_F(f)   do { CHECK_V_F(_var_err__, f); } while (0)




const char* ERR_getErrorString(ERR_enum code);   /* error_private.c */

ERR_STATIC const char* ERR_getErrorName(size_t code)
{
    return ERR_getErrorString(ERR_getErrorCode(code));
}


static INLINE_KEYWORD UNUSED_ATTR
void _force_has_format_string(const char *format, ...) {
  (void)format;
}


#define _FORCE_HAS_FORMAT_STRING(...)              \
    do {                                           \
        if (0) {                                   \
            _force_has_format_string(__VA_ARGS__); \
        }                                          \
    } while (0)

#define ERR_QUOTE(str) #str


#define RETURN_ERROR_IF(cond, err, ...)                                        \
    do {                                                                       \
        if (cond) {                                                            \
            RAWLOG(3, "%s:%d: ERROR!: check %s failed, returning %s",          \
                  __FILE__, __LINE__, ERR_QUOTE(cond), ERR_QUOTE(ERROR(err))); \
            _FORCE_HAS_FORMAT_STRING(__VA_ARGS__);                             \
            RAWLOG(3, ": " __VA_ARGS__);                                       \
            RAWLOG(3, "\n");                                                   \
            return ERROR(err);                                                 \
        }                                                                      \
    } while (0)


#define RETURN_ERROR(err, ...)                                               \
    do {                                                                     \
        RAWLOG(3, "%s:%d: ERROR!: unconditional check failed, returning %s", \
              __FILE__, __LINE__, ERR_QUOTE(ERROR(err)));                    \
        _FORCE_HAS_FORMAT_STRING(__VA_ARGS__);                               \
        RAWLOG(3, ": " __VA_ARGS__);                                         \
        RAWLOG(3, "\n");                                                     \
        return ERROR(err);                                                   \
    } while(0)


#define FORWARD_IF_ERROR(err, ...)                                                 \
    do {                                                                           \
        size_t const err_code = (err);                                             \
        if (ERR_isError(err_code)) {                                               \
            RAWLOG(3, "%s:%d: ERROR!: forwarding error in %s: %s",                 \
                  __FILE__, __LINE__, ERR_QUOTE(err), ERR_getErrorName(err_code)); \
            _FORCE_HAS_FORMAT_STRING(__VA_ARGS__);                                 \
            RAWLOG(3, ": " __VA_ARGS__);                                           \
            RAWLOG(3, "\n");                                                       \
            return err_code;                                                       \
        }                                                                          \
    } while(0)

#endif /* ERROR_H_MODULE */
/**** ended inlining error_private.h ****/
#define FSE_STATIC_LINKING_ONLY  /* FSE_MIN_TABLELOG */
/**** start inlining fse.h ****/
/* ******************************************************************
 * FSE : Finite State Entropy codec
 * Public Prototypes declaration
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * You can contact the author at :
 * - Source repository : https://github.com/Cyan4973/FiniteStateEntropy
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
****************************************************************** */
#ifndef FSE_H
#define FSE_H



/**** skipping file: zstd_deps.h ****/


#if defined(FSE_DLL_EXPORT) && (FSE_DLL_EXPORT==1) && defined(__GNUC__) && (__GNUC__ >= 4)
#  define FSE_PUBLIC_API __attribute__ ((visibility ("default")))
#elif defined(FSE_DLL_EXPORT) && (FSE_DLL_EXPORT==1)   /* Visual expected */
#  define FSE_PUBLIC_API __declspec(dllexport)
#elif defined(FSE_DLL_IMPORT) && (FSE_DLL_IMPORT==1)
#  define FSE_PUBLIC_API __declspec(dllimport) /* It isn't required but allows to generate better code, saving a function pointer load from the IAT and an indirect jump.*/
#else
#  define FSE_PUBLIC_API
#endif


#define FSE_VERSION_MAJOR    0
#define FSE_VERSION_MINOR    9
#define FSE_VERSION_RELEASE  0

#define FSE_LIB_VERSION FSE_VERSION_MAJOR.FSE_VERSION_MINOR.FSE_VERSION_RELEASE
#define FSE_QUOTE(str) #str
#define FSE_EXPAND_AND_QUOTE(str) FSE_QUOTE(str)
#define FSE_VERSION_STRING FSE_EXPAND_AND_QUOTE(FSE_LIB_VERSION)

#define FSE_VERSION_NUMBER  (FSE_VERSION_MAJOR *100*100 + FSE_VERSION_MINOR *100 + FSE_VERSION_RELEASE)
FSE_PUBLIC_API unsigned FSE_versionNumber(void);   /**< library version number; to be used when checking dll version */



FSE_PUBLIC_API size_t FSE_compressBound(size_t size);       /* maximum compressed size */


FSE_PUBLIC_API unsigned    FSE_isError(size_t code);        /* tells if a return value is an error code */
FSE_PUBLIC_API const char* FSE_getErrorName(size_t code);   /* provides error code string (useful for debugging) */








FSE_PUBLIC_API unsigned FSE_optimalTableLog(unsigned maxTableLog, size_t srcSize, unsigned maxSymbolValue);


FSE_PUBLIC_API size_t FSE_normalizeCount(short* normalizedCounter, unsigned tableLog,
                    const unsigned* count, size_t srcSize, unsigned maxSymbolValue, unsigned useLowProbCount);


FSE_PUBLIC_API size_t FSE_NCountWriteBound(unsigned maxSymbolValue, unsigned tableLog);


FSE_PUBLIC_API size_t FSE_writeNCount (void* buffer, size_t bufferSize,
                                 const short* normalizedCounter,
                                 unsigned maxSymbolValue, unsigned tableLog);


typedef unsigned FSE_CTable;   /* don't allocate that. It's only meant to be more restrictive than void* */


FSE_PUBLIC_API size_t FSE_buildCTable(FSE_CTable* ct, const short* normalizedCounter, unsigned maxSymbolValue, unsigned tableLog);


FSE_PUBLIC_API size_t FSE_compress_usingCTable (void* dst, size_t dstCapacity, const void* src, size_t srcSize, const FSE_CTable* ct);







FSE_PUBLIC_API size_t FSE_readNCount (short* normalizedCounter,
                           unsigned* maxSymbolValuePtr, unsigned* tableLogPtr,
                           const void* rBuffer, size_t rBuffSize);


FSE_PUBLIC_API size_t FSE_readNCount_bmi2(short* normalizedCounter,
                           unsigned* maxSymbolValuePtr, unsigned* tableLogPtr,
                           const void* rBuffer, size_t rBuffSize, int bmi2);

typedef unsigned FSE_DTable;   /* don't allocate that. It's just a way to be more restrictive than void* */



#endif  /* FSE_H */


#if defined(FSE_STATIC_LINKING_ONLY) && !defined(FSE_H_FSE_STATIC_LINKING_ONLY)
#define FSE_H_FSE_STATIC_LINKING_ONLY
/**** start inlining bitstream.h ****/
/* ******************************************************************
 * bitstream
 * Part of FSE library
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * You can contact the author at :
 * - Source repository : https://github.com/Cyan4973/FiniteStateEntropy
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
****************************************************************** */
#ifndef BITSTREAM_H_MODULE
#define BITSTREAM_H_MODULE




/**** skipping file: mem.h ****/
/**** skipping file: compiler.h ****/
/**** skipping file: debug.h ****/
/**** skipping file: error_private.h ****/
/**** start inlining bits.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_BITS_H
#define ZSTD_BITS_H

/**** skipping file: mem.h ****/

MEM_STATIC unsigned ZSTD_countTrailingZeros32_fallback(U32 val)
{
    assert(val != 0);
    {
        static const U32 DeBruijnBytePos[32] = {0, 1, 28, 2, 29, 14, 24, 3,
                                                30, 22, 20, 15, 25, 17, 4, 8,
                                                31, 27, 13, 23, 21, 19, 16, 7,
                                                26, 12, 18, 6, 11, 5, 10, 9};
        return DeBruijnBytePos[((U32) ((val & (0-val)) * 0x077CB531U)) >> 27];
    }
}

MEM_STATIC unsigned ZSTD_countTrailingZeros32(U32 val)
{
    assert(val != 0);
#if defined(_MSC_VER)
#  if STATIC_BMI2
    return (unsigned)_tzcnt_u32(val);
#  else
    if (val != 0) {
        unsigned long r;
        _BitScanForward(&r, val);
        return (unsigned)r;
    } else {
        __assume(0); /* Should not reach this code path */
    }
#  endif
#elif defined(__GNUC__) && (__GNUC__ >= 4)
    return (unsigned)__builtin_ctz(val);
#elif defined(__ICCARM__)
    return (unsigned)__builtin_ctz(val);
#else
    return ZSTD_countTrailingZeros32_fallback(val);
#endif
}

MEM_STATIC unsigned ZSTD_countLeadingZeros32_fallback(U32 val)
{
    assert(val != 0);
    {
        static const U32 DeBruijnClz[32] = {0, 9, 1, 10, 13, 21, 2, 29,
                                            11, 14, 16, 18, 22, 25, 3, 30,
                                            8, 12, 20, 28, 15, 17, 24, 7,
                                            19, 27, 23, 6, 26, 5, 4, 31};
        val |= val >> 1;
        val |= val >> 2;
        val |= val >> 4;
        val |= val >> 8;
        val |= val >> 16;
        return 31 - DeBruijnClz[(val * 0x07C4ACDDU) >> 27];
    }
}

MEM_STATIC unsigned ZSTD_countLeadingZeros32(U32 val)
{
    assert(val != 0);
#if defined(_MSC_VER)
#  if STATIC_BMI2
    return (unsigned)_lzcnt_u32(val);
#  else
    if (val != 0) {
        unsigned long r;
        _BitScanReverse(&r, val);
        return (unsigned)(31 - r);
    } else {
        __assume(0); /* Should not reach this code path */
    }
#  endif
#elif defined(__GNUC__) && (__GNUC__ >= 4)
    return (unsigned)__builtin_clz(val);
#elif defined(__ICCARM__)
    return (unsigned)__builtin_clz(val);
#else
    return ZSTD_countLeadingZeros32_fallback(val);
#endif
}

MEM_STATIC unsigned ZSTD_countTrailingZeros64(U64 val)
{
    assert(val != 0);
#if defined(_MSC_VER) && defined(_WIN64)
#  if STATIC_BMI2
    return (unsigned)_tzcnt_u64(val);
#  else
    if (val != 0) {
        unsigned long r;
        _BitScanForward64(&r, val);
        return (unsigned)r;
    } else {
        __assume(0); /* Should not reach this code path */
    }
#  endif
#elif defined(__GNUC__) && (__GNUC__ >= 4) && defined(__LP64__)
    return (unsigned)__builtin_ctzll(val);
#elif defined(__ICCARM__)
    return (unsigned)__builtin_ctzll(val);
#else
    {
        U32 mostSignificantWord = (U32)(val >> 32);
        U32 leastSignificantWord = (U32)val;
        if (leastSignificantWord == 0) {
            return 32 + ZSTD_countTrailingZeros32(mostSignificantWord);
        } else {
            return ZSTD_countTrailingZeros32(leastSignificantWord);
        }
    }
#endif
}

MEM_STATIC unsigned ZSTD_countLeadingZeros64(U64 val)
{
    assert(val != 0);
#if defined(_MSC_VER) && defined(_WIN64)
#  if STATIC_BMI2
    return (unsigned)_lzcnt_u64(val);
#  else
    if (val != 0) {
        unsigned long r;
        _BitScanReverse64(&r, val);
        return (unsigned)(63 - r);
    } else {
        __assume(0); /* Should not reach this code path */
    }
#  endif
#elif defined(__GNUC__) && (__GNUC__ >= 4)
    return (unsigned)(__builtin_clzll(val));
#elif defined(__ICCARM__)
    return (unsigned)(__builtin_clzll(val));
#else
    {
        U32 mostSignificantWord = (U32)(val >> 32);
        U32 leastSignificantWord = (U32)val;
        if (mostSignificantWord == 0) {
            return 32 + ZSTD_countLeadingZeros32(leastSignificantWord);
        } else {
            return ZSTD_countLeadingZeros32(mostSignificantWord);
        }
    }
#endif
}

MEM_STATIC unsigned ZSTD_NbCommonBytes(size_t val)
{
    if (MEM_isLittleEndian()) {
        if (MEM_64bits()) {
            return ZSTD_countTrailingZeros64((U64)val) >> 3;
        } else {
            return ZSTD_countTrailingZeros32((U32)val) >> 3;
        }
    } else {  /* Big Endian CPU */
        if (MEM_64bits()) {
            return ZSTD_countLeadingZeros64((U64)val) >> 3;
        } else {
            return ZSTD_countLeadingZeros32((U32)val) >> 3;
        }
    }
}

MEM_STATIC unsigned ZSTD_highbit32(U32 val)   /* compress, dictBuilder, decodeCorpus */
{
    assert(val != 0);
    return 31 - ZSTD_countLeadingZeros32(val);
}


MEM_STATIC
U64 ZSTD_rotateRight_U64(U64 const value, U32 count) {
    assert(count < 64);
    count &= 0x3F; /* for fickle pattern recognition */
    return (value >> count) | (U64)(value << ((0U - count) & 0x3F));
}

MEM_STATIC
U32 ZSTD_rotateRight_U32(U32 const value, U32 count) {
    assert(count < 32);
    count &= 0x1F; /* for fickle pattern recognition */
    return (value >> count) | (U32)(value << ((0U - count) & 0x1F));
}

MEM_STATIC
U16 ZSTD_rotateRight_U16(U16 const value, U32 count) {
    assert(count < 16);
    count &= 0x0F; /* for fickle pattern recognition */
    return (value >> count) | (U16)(value << ((0U - count) & 0x0F));
}

#endif /* ZSTD_BITS_H */
/**** ended inlining bits.h ****/


#ifndef ZSTD_NO_INTRINSICS
#  if (defined(__BMI__) || defined(__BMI2__)) && defined(__GNUC__)
#    include <immintrin.h>   /* support for bextr (experimental)/bzhi */
#  elif defined(__ICCARM__)
#    include <intrinsics.h>
#  endif
#endif

#define STREAM_ACCUMULATOR_MIN_32  25
#define STREAM_ACCUMULATOR_MIN_64  57
#define STREAM_ACCUMULATOR_MIN    ((U32)(MEM_32bits() ? STREAM_ACCUMULATOR_MIN_32 : STREAM_ACCUMULATOR_MIN_64))



typedef size_t BitContainerType;

typedef struct {
    BitContainerType bitContainer;
    unsigned bitPos;
    char*  startPtr;
    char*  ptr;
    char*  endPtr;
} BIT_CStream_t;

MEM_STATIC size_t BIT_initCStream(BIT_CStream_t* bitC, void* dstBuffer, size_t dstCapacity);
MEM_STATIC void   BIT_addBits(BIT_CStream_t* bitC, BitContainerType value, unsigned nbBits);
MEM_STATIC void   BIT_flushBits(BIT_CStream_t* bitC);
MEM_STATIC size_t BIT_closeCStream(BIT_CStream_t* bitC);





typedef struct {
    BitContainerType bitContainer;
    unsigned bitsConsumed;
    const char* ptr;
    const char* start;
    const char* limitPtr;
} BIT_DStream_t;

typedef enum { BIT_DStream_unfinished = 0,  /* fully refilled */
               BIT_DStream_endOfBuffer = 1, /* still some bits left in bitstream */
               BIT_DStream_completed = 2,   /* bitstream entirely consumed, bit-exact */
               BIT_DStream_overflow = 3     /* user requested more bits than present in bitstream */
    } BIT_DStream_status;  /* result of BIT_reloadDStream() */

MEM_STATIC size_t   BIT_initDStream(BIT_DStream_t* bitD, const void* srcBuffer, size_t srcSize);
FORCE_INLINE_TEMPLATE BitContainerType BIT_readBits(BIT_DStream_t* bitD, unsigned nbBits);
FORCE_INLINE_TEMPLATE BIT_DStream_status BIT_reloadDStream(BIT_DStream_t* bitD);
MEM_STATIC unsigned BIT_endOfDStream(const BIT_DStream_t* bitD);






MEM_STATIC void BIT_addBitsFast(BIT_CStream_t* bitC, BitContainerType value, unsigned nbBits);


MEM_STATIC void BIT_flushBitsFast(BIT_CStream_t* bitC);


MEM_STATIC size_t BIT_readBitsFast(BIT_DStream_t* bitD, unsigned nbBits);



static const unsigned BIT_mask[] = {
    0,          1,         3,         7,         0xF,       0x1F,
    0x3F,       0x7F,      0xFF,      0x1FF,     0x3FF,     0x7FF,
    0xFFF,      0x1FFF,    0x3FFF,    0x7FFF,    0xFFFF,    0x1FFFF,
    0x3FFFF,    0x7FFFF,   0xFFFFF,   0x1FFFFF,  0x3FFFFF,  0x7FFFFF,
    0xFFFFFF,   0x1FFFFFF, 0x3FFFFFF, 0x7FFFFFF, 0xFFFFFFF, 0x1FFFFFFF,
    0x3FFFFFFF, 0x7FFFFFFF}; /* up to 31 bits */
#define BIT_MASK_SIZE (sizeof(BIT_mask) / sizeof(BIT_mask[0]))



MEM_STATIC size_t BIT_initCStream(BIT_CStream_t* bitC,
                                  void* startPtr, size_t dstCapacity)
{
    bitC->bitContainer = 0;
    bitC->bitPos = 0;
    bitC->startPtr = (char*)startPtr;
    bitC->ptr = bitC->startPtr;
    bitC->endPtr = bitC->startPtr + dstCapacity - sizeof(bitC->bitContainer);
    if (dstCapacity <= sizeof(bitC->bitContainer)) return ERROR(dstSize_tooSmall);
    return 0;
}

FORCE_INLINE_TEMPLATE BitContainerType BIT_getLowerBits(BitContainerType bitContainer, U32 const nbBits)
{
#if STATIC_BMI2 && !defined(ZSTD_NO_INTRINSICS)
#  if (defined(__x86_64__) || defined(_M_X64)) && !defined(__ILP32__)
    return _bzhi_u64(bitContainer, nbBits);
#  else
    DEBUG_STATIC_ASSERT(sizeof(bitContainer) == sizeof(U32));
    return _bzhi_u32(bitContainer, nbBits);
#  endif
#else
    assert(nbBits < BIT_MASK_SIZE);
    return bitContainer & BIT_mask[nbBits];
#endif
}


MEM_STATIC void BIT_addBits(BIT_CStream_t* bitC,
                            BitContainerType value, unsigned nbBits)
{
    DEBUG_STATIC_ASSERT(BIT_MASK_SIZE == 32);
    assert(nbBits < BIT_MASK_SIZE);
    assert(nbBits + bitC->bitPos < sizeof(bitC->bitContainer) * 8);
    bitC->bitContainer |= BIT_getLowerBits(value, nbBits) << bitC->bitPos;
    bitC->bitPos += nbBits;
}


MEM_STATIC void BIT_addBitsFast(BIT_CStream_t* bitC,
                                BitContainerType value, unsigned nbBits)
{
    assert((value>>nbBits) == 0);
    assert(nbBits + bitC->bitPos < sizeof(bitC->bitContainer) * 8);
    bitC->bitContainer |= value << bitC->bitPos;
    bitC->bitPos += nbBits;
}


MEM_STATIC void BIT_flushBitsFast(BIT_CStream_t* bitC)
{
    size_t const nbBytes = bitC->bitPos >> 3;
    assert(bitC->bitPos < sizeof(bitC->bitContainer) * 8);
    assert(bitC->ptr <= bitC->endPtr);
    MEM_writeLEST(bitC->ptr, bitC->bitContainer);
    bitC->ptr += nbBytes;
    bitC->bitPos &= 7;
    bitC->bitContainer >>= nbBytes*8;
}


MEM_STATIC void BIT_flushBits(BIT_CStream_t* bitC)
{
    size_t const nbBytes = bitC->bitPos >> 3;
    assert(bitC->bitPos < sizeof(bitC->bitContainer) * 8);
    assert(bitC->ptr <= bitC->endPtr);
    MEM_writeLEST(bitC->ptr, bitC->bitContainer);
    bitC->ptr += nbBytes;
    if (bitC->ptr > bitC->endPtr) bitC->ptr = bitC->endPtr;
    bitC->bitPos &= 7;
    bitC->bitContainer >>= nbBytes*8;
}


MEM_STATIC size_t BIT_closeCStream(BIT_CStream_t* bitC)
{
    BIT_addBitsFast(bitC, 1, 1);   /* endMark */
    BIT_flushBits(bitC);
    if (bitC->ptr >= bitC->endPtr) return 0; /* overflow detected */
    return (size_t)(bitC->ptr - bitC->startPtr) + (bitC->bitPos > 0);
}




MEM_STATIC size_t BIT_initDStream(BIT_DStream_t* bitD, const void* srcBuffer, size_t srcSize)
{
    if (srcSize < 1) { ZSTD_memset(bitD, 0, sizeof(*bitD)); return ERROR(srcSize_wrong); }

    bitD->start = (const char*)srcBuffer;
    bitD->limitPtr = bitD->start + sizeof(bitD->bitContainer);

    if (srcSize >=  sizeof(bitD->bitContainer)) {  /* normal case */
        bitD->ptr   = (const char*)srcBuffer + srcSize - sizeof(bitD->bitContainer);
        bitD->bitContainer = MEM_readLEST(bitD->ptr);
        { BYTE const lastByte = ((const BYTE*)srcBuffer)[srcSize-1];
          bitD->bitsConsumed = lastByte ? 8 - ZSTD_highbit32(lastByte) : 0;  /* ensures bitsConsumed is always set */
          if (lastByte == 0) return ERROR(GENERIC); /* endMark not present */ }
    } else {
        bitD->ptr   = bitD->start;
        bitD->bitContainer = *(const BYTE*)(bitD->start);
        switch(srcSize)
        {
        case 7: bitD->bitContainer += (BitContainerType)(((const BYTE*)(srcBuffer))[6]) << (sizeof(bitD->bitContainer)*8 - 16);
                ZSTD_FALLTHROUGH;

        case 6: bitD->bitContainer += (BitContainerType)(((const BYTE*)(srcBuffer))[5]) << (sizeof(bitD->bitContainer)*8 - 24);
                ZSTD_FALLTHROUGH;

        case 5: bitD->bitContainer += (BitContainerType)(((const BYTE*)(srcBuffer))[4]) << (sizeof(bitD->bitContainer)*8 - 32);
                ZSTD_FALLTHROUGH;

        case 4: bitD->bitContainer += (BitContainerType)(((const BYTE*)(srcBuffer))[3]) << 24;
                ZSTD_FALLTHROUGH;

        case 3: bitD->bitContainer += (BitContainerType)(((const BYTE*)(srcBuffer))[2]) << 16;
                ZSTD_FALLTHROUGH;

        case 2: bitD->bitContainer += (BitContainerType)(((const BYTE*)(srcBuffer))[1]) <<  8;
                ZSTD_FALLTHROUGH;

        default: break;
        }
        {   BYTE const lastByte = ((const BYTE*)srcBuffer)[srcSize-1];
            bitD->bitsConsumed = lastByte ? 8 - ZSTD_highbit32(lastByte) : 0;
            if (lastByte == 0) return ERROR(corruption_detected);  /* endMark not present */
        }
        bitD->bitsConsumed += (U32)(sizeof(bitD->bitContainer) - srcSize)*8;
    }

    return srcSize;
}

FORCE_INLINE_TEMPLATE BitContainerType BIT_getUpperBits(BitContainerType bitContainer, U32 const start)
{
    return bitContainer >> start;
}

FORCE_INLINE_TEMPLATE BitContainerType BIT_getMiddleBits(BitContainerType bitContainer, U32 const start, U32 const nbBits)
{
    U32 const regMask = sizeof(bitContainer)*8 - 1;

    assert(nbBits < BIT_MASK_SIZE);

#if defined(__x86_64__) || defined(_M_X64)
    return (bitContainer >> (start & regMask)) & ((((U64)1) << nbBits) - 1);
#else
    return (bitContainer >> (start & regMask)) & BIT_mask[nbBits];
#endif
}


FORCE_INLINE_TEMPLATE BitContainerType BIT_lookBits(const BIT_DStream_t*  bitD, U32 nbBits)
{

#if 1

    return BIT_getMiddleBits(bitD->bitContainer, (sizeof(bitD->bitContainer)*8) - bitD->bitsConsumed - nbBits, nbBits);
#else

    U32 const regMask = sizeof(bitD->bitContainer)*8 - 1;
    return ((bitD->bitContainer << (bitD->bitsConsumed & regMask)) >> 1) >> ((regMask-nbBits) & regMask);
#endif
}


MEM_STATIC BitContainerType BIT_lookBitsFast(const BIT_DStream_t* bitD, U32 nbBits)
{
    U32 const regMask = sizeof(bitD->bitContainer)*8 - 1;
    assert(nbBits >= 1);
    return (bitD->bitContainer << (bitD->bitsConsumed & regMask)) >> (((regMask+1)-nbBits) & regMask);
}

FORCE_INLINE_TEMPLATE void BIT_skipBits(BIT_DStream_t* bitD, U32 nbBits)
{
    bitD->bitsConsumed += nbBits;
}


FORCE_INLINE_TEMPLATE BitContainerType BIT_readBits(BIT_DStream_t* bitD, unsigned nbBits)
{
    BitContainerType const value = BIT_lookBits(bitD, nbBits);
    BIT_skipBits(bitD, nbBits);
    return value;
}


MEM_STATIC BitContainerType BIT_readBitsFast(BIT_DStream_t* bitD, unsigned nbBits)
{
    BitContainerType const value = BIT_lookBitsFast(bitD, nbBits);
    assert(nbBits >= 1);
    BIT_skipBits(bitD, nbBits);
    return value;
}


MEM_STATIC BIT_DStream_status BIT_reloadDStream_internal(BIT_DStream_t* bitD)
{
    assert(bitD->bitsConsumed <= sizeof(bitD->bitContainer)*8);
    bitD->ptr -= bitD->bitsConsumed >> 3;
    assert(bitD->ptr >= bitD->start);
    bitD->bitsConsumed &= 7;
    bitD->bitContainer = MEM_readLEST(bitD->ptr);
    return BIT_DStream_unfinished;
}


MEM_STATIC BIT_DStream_status BIT_reloadDStreamFast(BIT_DStream_t* bitD)
{
    if (UNLIKELY(bitD->ptr < bitD->limitPtr))
        return BIT_DStream_overflow;
    return BIT_reloadDStream_internal(bitD);
}


FORCE_INLINE_TEMPLATE BIT_DStream_status BIT_reloadDStream(BIT_DStream_t* bitD)
{

    if (UNLIKELY(bitD->bitsConsumed > (sizeof(bitD->bitContainer)*8))) {
        static const BitContainerType zeroFilled = 0;
        bitD->ptr = (const char*)&zeroFilled; /* aliasing is allowed for char */

        return BIT_DStream_overflow;
    }

    assert(bitD->ptr >= bitD->start);

    if (bitD->ptr >= bitD->limitPtr) {
        return BIT_reloadDStream_internal(bitD);
    }
    if (bitD->ptr == bitD->start) {

        if (bitD->bitsConsumed < sizeof(bitD->bitContainer)*8) return BIT_DStream_endOfBuffer;
        return BIT_DStream_completed;
    }

    {   U32 nbBytes = bitD->bitsConsumed >> 3;
        BIT_DStream_status result = BIT_DStream_unfinished;
        if (nbBytes > (size_t)(bitD->ptr - bitD->start)) {
            nbBytes = (U32)(bitD->ptr - bitD->start);  /* ptr > start */
            result = BIT_DStream_endOfBuffer;
        }
        bitD->ptr -= nbBytes;
        bitD->bitsConsumed -= nbBytes*8;
        bitD->bitContainer = MEM_readLEST(bitD->ptr);   /* reminder : srcSize > sizeof(bitD->bitContainer), otherwise bitD->ptr == bitD->start */
        return result;
    }
}


MEM_STATIC unsigned BIT_endOfDStream(const BIT_DStream_t* DStream)
{
    return ((DStream->ptr == DStream->start) && (DStream->bitsConsumed == sizeof(DStream->bitContainer)*8));
}

#endif /* BITSTREAM_H_MODULE */
/**** ended inlining bitstream.h ****/



#define FSE_NCOUNTBOUND 512
#define FSE_BLOCKBOUND(size) ((size) + ((size)>>7) + 4 /* fse states */ + sizeof(size_t) /* bitContainer */)
#define FSE_COMPRESSBOUND(size) (FSE_NCOUNTBOUND + FSE_BLOCKBOUND(size))   /* Macro version, useful for static allocation */


#define FSE_CTABLE_SIZE_U32(maxTableLog, maxSymbolValue)   (1 + (1<<((maxTableLog)-1)) + (((maxSymbolValue)+1)*2))
#define FSE_DTABLE_SIZE_U32(maxTableLog)                   (1 + (1<<(maxTableLog)))


#define FSE_CTABLE_SIZE(maxTableLog, maxSymbolValue)   (FSE_CTABLE_SIZE_U32(maxTableLog, maxSymbolValue) * sizeof(FSE_CTable))
#define FSE_DTABLE_SIZE(maxTableLog)                   (FSE_DTABLE_SIZE_U32(maxTableLog) * sizeof(FSE_DTable))




unsigned FSE_optimalTableLog_internal(unsigned maxTableLog, size_t srcSize, unsigned maxSymbolValue, unsigned minus);


size_t FSE_buildCTable_rle (FSE_CTable* ct, unsigned char symbolValue);



#define FSE_BUILD_CTABLE_WORKSPACE_SIZE_U32(maxSymbolValue, tableLog) (((maxSymbolValue + 2) + (1ull << (tableLog)))/2 + sizeof(U64)/sizeof(U32) /* additional 8 bytes for potential table overwrite */)
#define FSE_BUILD_CTABLE_WORKSPACE_SIZE(maxSymbolValue, tableLog) (sizeof(unsigned) * FSE_BUILD_CTABLE_WORKSPACE_SIZE_U32(maxSymbolValue, tableLog))
size_t FSE_buildCTable_wksp(FSE_CTable* ct, const short* normalizedCounter, unsigned maxSymbolValue, unsigned tableLog, void* workSpace, size_t wkspSize);

#define FSE_BUILD_DTABLE_WKSP_SIZE(maxTableLog, maxSymbolValue) (sizeof(short) * (maxSymbolValue + 1) + (1ULL << maxTableLog) + 8)
#define FSE_BUILD_DTABLE_WKSP_SIZE_U32(maxTableLog, maxSymbolValue) ((FSE_BUILD_DTABLE_WKSP_SIZE(maxTableLog, maxSymbolValue) + sizeof(unsigned) - 1) / sizeof(unsigned))
FSE_PUBLIC_API size_t FSE_buildDTable_wksp(FSE_DTable* dt, const short* normalizedCounter, unsigned maxSymbolValue, unsigned tableLog, void* workSpace, size_t wkspSize);


#define FSE_DECOMPRESS_WKSP_SIZE_U32(maxTableLog, maxSymbolValue) (FSE_DTABLE_SIZE_U32(maxTableLog) + 1 + FSE_BUILD_DTABLE_WKSP_SIZE_U32(maxTableLog, maxSymbolValue) + (FSE_MAX_SYMBOL_VALUE + 1) / 2 + 1)
#define FSE_DECOMPRESS_WKSP_SIZE(maxTableLog, maxSymbolValue) (FSE_DECOMPRESS_WKSP_SIZE_U32(maxTableLog, maxSymbolValue) * sizeof(unsigned))
size_t FSE_decompress_wksp_bmi2(void* dst, size_t dstCapacity, const void* cSrc, size_t cSrcSize, unsigned maxLog, void* workSpace, size_t wkspSize, int bmi2);


typedef enum {
   FSE_repeat_none,  /**< Cannot use the previous table */
   FSE_repeat_check, /**< Can use the previous table but it must be checked */
   FSE_repeat_valid  /**< Can use the previous table and it is assumed to be valid */
 } FSE_repeat;



typedef struct {
    ptrdiff_t   value;
    const void* stateTable;
    const void* symbolTT;
    unsigned    stateLog;
} FSE_CState_t;

static void FSE_initCState(FSE_CState_t* CStatePtr, const FSE_CTable* ct);

static void FSE_encodeSymbol(BIT_CStream_t* bitC, FSE_CState_t* CStatePtr, unsigned symbol);

static void FSE_flushCState(BIT_CStream_t* bitC, const FSE_CState_t* CStatePtr);





typedef struct {
    size_t      state;
    const void* table;   /* precise table may vary, depending on U16 */
} FSE_DState_t;


static void     FSE_initDState(FSE_DState_t* DStatePtr, BIT_DStream_t* bitD, const FSE_DTable* dt);

static unsigned char FSE_decodeSymbol(FSE_DState_t* DStatePtr, BIT_DStream_t* bitD);

static unsigned FSE_endOfDState(const FSE_DState_t* DStatePtr);





static unsigned char FSE_decodeSymbolFast(FSE_DState_t* DStatePtr, BIT_DStream_t* bitD);




typedef struct {
    int deltaFindState;
    U32 deltaNbBits;
} FSE_symbolCompressionTransform; /* total 8 bytes */

MEM_STATIC void FSE_initCState(FSE_CState_t* statePtr, const FSE_CTable* ct)
{
    const void* ptr = ct;
    const U16* u16ptr = (const U16*) ptr;
    const U32 tableLog = MEM_read16(ptr);
    statePtr->value = (ptrdiff_t)1<<tableLog;
    statePtr->stateTable = u16ptr+2;
    statePtr->symbolTT = ct + 1 + (tableLog ? (1<<(tableLog-1)) : 1);
    statePtr->stateLog = tableLog;
}



MEM_STATIC void FSE_initCState2(FSE_CState_t* statePtr, const FSE_CTable* ct, U32 symbol)
{
    FSE_initCState(statePtr, ct);
    {   const FSE_symbolCompressionTransform symbolTT = ((const FSE_symbolCompressionTransform*)(statePtr->symbolTT))[symbol];
        const U16* stateTable = (const U16*)(statePtr->stateTable);
        U32 nbBitsOut  = (U32)((symbolTT.deltaNbBits + (1<<15)) >> 16);
        statePtr->value = (nbBitsOut << 16) - symbolTT.deltaNbBits;
        statePtr->value = stateTable[(statePtr->value >> nbBitsOut) + symbolTT.deltaFindState];
    }
}

MEM_STATIC void FSE_encodeSymbol(BIT_CStream_t* bitC, FSE_CState_t* statePtr, unsigned symbol)
{
    FSE_symbolCompressionTransform const symbolTT = ((const FSE_symbolCompressionTransform*)(statePtr->symbolTT))[symbol];
    const U16* const stateTable = (const U16*)(statePtr->stateTable);
    U32 const nbBitsOut  = (U32)((statePtr->value + symbolTT.deltaNbBits) >> 16);
    BIT_addBits(bitC, (BitContainerType)statePtr->value, nbBitsOut);
    statePtr->value = stateTable[ (statePtr->value >> nbBitsOut) + symbolTT.deltaFindState];
}

MEM_STATIC void FSE_flushCState(BIT_CStream_t* bitC, const FSE_CState_t* statePtr)
{
    BIT_addBits(bitC, (BitContainerType)statePtr->value, statePtr->stateLog);
    BIT_flushBits(bitC);
}



MEM_STATIC U32 FSE_getMaxNbBits(const void* symbolTTPtr, U32 symbolValue)
{
    const FSE_symbolCompressionTransform* symbolTT = (const FSE_symbolCompressionTransform*) symbolTTPtr;
    return (symbolTT[symbolValue].deltaNbBits + ((1<<16)-1)) >> 16;
}


MEM_STATIC U32 FSE_bitCost(const void* symbolTTPtr, U32 tableLog, U32 symbolValue, U32 accuracyLog)
{
    const FSE_symbolCompressionTransform* symbolTT = (const FSE_symbolCompressionTransform*) symbolTTPtr;
    U32 const minNbBits = symbolTT[symbolValue].deltaNbBits >> 16;
    U32 const threshold = (minNbBits+1) << 16;
    assert(tableLog < 16);
    assert(accuracyLog < 31-tableLog);  /* ensure enough room for renormalization double shift */
    {   U32 const tableSize = 1 << tableLog;
        U32 const deltaFromThreshold = threshold - (symbolTT[symbolValue].deltaNbBits + tableSize);
        U32 const normalizedDeltaFromThreshold = (deltaFromThreshold << accuracyLog) >> tableLog;   /* linear interpolation (very approximate) */
        U32 const bitMultiplier = 1 << accuracyLog;
        assert(symbolTT[symbolValue].deltaNbBits + tableSize <= threshold);
        assert(normalizedDeltaFromThreshold <= bitMultiplier);
        return (minNbBits+1)*bitMultiplier - normalizedDeltaFromThreshold;
    }
}




typedef struct {
    U16 tableLog;
    U16 fastMode;
} FSE_DTableHeader;   /* sizeof U32 */

typedef struct
{
    unsigned short newState;
    unsigned char  symbol;
    unsigned char  nbBits;
} FSE_decode_t;   /* size == U32 */

MEM_STATIC void FSE_initDState(FSE_DState_t* DStatePtr, BIT_DStream_t* bitD, const FSE_DTable* dt)
{
    const void* ptr = dt;
    const FSE_DTableHeader* const DTableH = (const FSE_DTableHeader*)ptr;
    DStatePtr->state = BIT_readBits(bitD, DTableH->tableLog);
    BIT_reloadDStream(bitD);
    DStatePtr->table = dt + 1;
}

MEM_STATIC BYTE FSE_peekSymbol(const FSE_DState_t* DStatePtr)
{
    FSE_decode_t const DInfo = ((const FSE_decode_t*)(DStatePtr->table))[DStatePtr->state];
    return DInfo.symbol;
}

MEM_STATIC void FSE_updateState(FSE_DState_t* DStatePtr, BIT_DStream_t* bitD)
{
    FSE_decode_t const DInfo = ((const FSE_decode_t*)(DStatePtr->table))[DStatePtr->state];
    U32 const nbBits = DInfo.nbBits;
    size_t const lowBits = BIT_readBits(bitD, nbBits);
    DStatePtr->state = DInfo.newState + lowBits;
}

MEM_STATIC BYTE FSE_decodeSymbol(FSE_DState_t* DStatePtr, BIT_DStream_t* bitD)
{
    FSE_decode_t const DInfo = ((const FSE_decode_t*)(DStatePtr->table))[DStatePtr->state];
    U32 const nbBits = DInfo.nbBits;
    BYTE const symbol = DInfo.symbol;
    size_t const lowBits = BIT_readBits(bitD, nbBits);

    DStatePtr->state = DInfo.newState + lowBits;
    return symbol;
}


MEM_STATIC BYTE FSE_decodeSymbolFast(FSE_DState_t* DStatePtr, BIT_DStream_t* bitD)
{
    FSE_decode_t const DInfo = ((const FSE_decode_t*)(DStatePtr->table))[DStatePtr->state];
    U32 const nbBits = DInfo.nbBits;
    BYTE const symbol = DInfo.symbol;
    size_t const lowBits = BIT_readBitsFast(bitD, nbBits);

    DStatePtr->state = DInfo.newState + lowBits;
    return symbol;
}

MEM_STATIC unsigned FSE_endOfDState(const FSE_DState_t* DStatePtr)
{
    return DStatePtr->state == 0;
}



#ifndef FSE_COMMONDEFS_ONLY



#ifndef FSE_MAX_MEMORY_USAGE
#  define FSE_MAX_MEMORY_USAGE 14
#endif
#ifndef FSE_DEFAULT_MEMORY_USAGE
#  define FSE_DEFAULT_MEMORY_USAGE 13
#endif
#if (FSE_DEFAULT_MEMORY_USAGE > FSE_MAX_MEMORY_USAGE)
#  error "FSE_DEFAULT_MEMORY_USAGE must be <= FSE_MAX_MEMORY_USAGE"
#endif


#ifndef FSE_MAX_SYMBOL_VALUE
#  define FSE_MAX_SYMBOL_VALUE 255
#endif


#define FSE_FUNCTION_TYPE BYTE
#define FSE_FUNCTION_EXTENSION
#define FSE_DECODE_TYPE FSE_decode_t


#endif   /* !FSE_COMMONDEFS_ONLY */



#define FSE_MAX_TABLELOG  (FSE_MAX_MEMORY_USAGE-2)
#define FSE_MAX_TABLESIZE (1U<<FSE_MAX_TABLELOG)
#define FSE_MAXTABLESIZE_MASK (FSE_MAX_TABLESIZE-1)
#define FSE_DEFAULT_TABLELOG (FSE_DEFAULT_MEMORY_USAGE-2)
#define FSE_MIN_TABLELOG 5

#define FSE_TABLELOG_ABSOLUTE_MAX 15
#if FSE_MAX_TABLELOG > FSE_TABLELOG_ABSOLUTE_MAX
#  error "FSE_MAX_TABLELOG > FSE_TABLELOG_ABSOLUTE_MAX is not supported"
#endif

#define FSE_TABLESTEP(tableSize) (((tableSize)>>1) + ((tableSize)>>3) + 3)

#endif /* FSE_STATIC_LINKING_ONLY */
/**** ended inlining fse.h ****/
/**** start inlining huf.h ****/
/* ******************************************************************
 * huff0 huffman codec,
 * part of Finite State Entropy library
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * You can contact the author at :
 * - Source repository : https://github.com/Cyan4973/FiniteStateEntropy
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
****************************************************************** */

#ifndef HUF_H_298734234
#define HUF_H_298734234


/**** skipping file: zstd_deps.h ****/
/**** skipping file: mem.h ****/
#define FSE_STATIC_LINKING_ONLY
/**** skipping file: fse.h ****/


#define HUF_BLOCKSIZE_MAX (128 * 1024)   /**< maximum input size for a single block compressed with HUF_compress */
size_t HUF_compressBound(size_t size);   /**< maximum compressed size (worst case) */


unsigned    HUF_isError(size_t code);       /**< tells if a return value is an error code */
const char* HUF_getErrorName(size_t code);  /**< provides error code string (useful for debugging) */


#define HUF_WORKSPACE_SIZE ((8 << 10) + 512 /* sorting scratch space */)
#define HUF_WORKSPACE_SIZE_U64 (HUF_WORKSPACE_SIZE / sizeof(U64))


#define HUF_TABLELOG_MAX      12      /* max runtime value of tableLog (due to static allocation); can be modified up to HUF_TABLELOG_ABSOLUTEMAX */
#define HUF_TABLELOG_DEFAULT  11      /* default tableLog value when none specified */
#define HUF_SYMBOLVALUE_MAX  255

#define HUF_TABLELOG_ABSOLUTEMAX  12  /* absolute limit of HUF_MAX_TABLELOG. Beyond that value, code does not work */
#if (HUF_TABLELOG_MAX > HUF_TABLELOG_ABSOLUTEMAX)
#  error "HUF_TABLELOG_MAX is too large !"
#endif




#define HUF_CTABLEBOUND 129
#define HUF_BLOCKBOUND(size) (size + (size>>8) + 8)   /* only true when incompressible is pre-filtered with fast heuristic */
#define HUF_COMPRESSBOUND(size) (HUF_CTABLEBOUND + HUF_BLOCKBOUND(size))   /* Macro version, useful for static allocation */



typedef size_t HUF_CElt;   /* consider it an incomplete type */
#define HUF_CTABLE_SIZE_ST(maxSymbolValue)   ((maxSymbolValue)+2)   /* Use tables of size_t, for proper alignment */
#define HUF_CTABLE_SIZE(maxSymbolValue)       (HUF_CTABLE_SIZE_ST(maxSymbolValue) * sizeof(size_t))
#define HUF_CREATE_STATIC_CTABLE(name, maxSymbolValue) \
    HUF_CElt name[HUF_CTABLE_SIZE_ST(maxSymbolValue)] /* no final ; */


typedef U32 HUF_DTable;
#define HUF_DTABLE_SIZE(maxTableLog)   (1 + (1<<(maxTableLog)))
#define HUF_CREATE_STATIC_DTABLEX1(DTable, maxTableLog) \
        HUF_DTable DTable[HUF_DTABLE_SIZE((maxTableLog)-1)] = { ((U32)((maxTableLog)-1) * 0x01000001) }
#define HUF_CREATE_STATIC_DTABLEX2(DTable, maxTableLog) \
        HUF_DTable DTable[HUF_DTABLE_SIZE(maxTableLog)] = { ((U32)(maxTableLog) * 0x01000001) }





typedef enum {

    HUF_flags_bmi2 = (1 << 0),

    HUF_flags_optimalDepth = (1 << 1),

    HUF_flags_preferRepeat = (1 << 2),

    HUF_flags_suspectUncompressible = (1 << 3),

    HUF_flags_disableAsm = (1 << 4),

    HUF_flags_disableFast = (1 << 5)
} HUF_flags_e;



#define HUF_OPTIMAL_DEPTH_THRESHOLD ZSTD_btultra


unsigned HUF_minTableLog(unsigned symbolCardinality);
unsigned HUF_cardinality(const unsigned* count, unsigned maxSymbolValue);
unsigned HUF_optimalTableLog(unsigned maxTableLog, size_t srcSize, unsigned maxSymbolValue, void* workSpace,
 size_t wkspSize, HUF_CElt* table, const unsigned* count, int flags); /* table is used as scratch space for building and testing tables, not a return value */
size_t HUF_writeCTable_wksp(void* dst, size_t maxDstSize, const HUF_CElt* CTable, unsigned maxSymbolValue, unsigned huffLog, void* workspace, size_t workspaceSize);
size_t HUF_compress4X_usingCTable(void* dst, size_t dstSize, const void* src, size_t srcSize, const HUF_CElt* CTable, int flags);
size_t HUF_estimateCompressedSize(const HUF_CElt* CTable, const unsigned* count, unsigned maxSymbolValue);
int HUF_validateCTable(const HUF_CElt* CTable, const unsigned* count, unsigned maxSymbolValue);

typedef enum {
   HUF_repeat_none,  /**< Cannot use the previous table */
   HUF_repeat_check, /**< Can use the previous table but it must be checked. Note : The previous table must have been constructed by HUF_compress{1, 4}X_repeat */
   HUF_repeat_valid  /**< Can use the previous table and it is assumed to be valid */
 } HUF_repeat;


size_t HUF_compress4X_repeat(void* dst, size_t dstSize,
                       const void* src, size_t srcSize,
                       unsigned maxSymbolValue, unsigned tableLog,
                       void* workSpace, size_t wkspSize,    /**< `workSpace` must be aligned on 4-bytes boundaries, `wkspSize` must be >= HUF_WORKSPACE_SIZE */
                       HUF_CElt* hufTable, HUF_repeat* repeat, int flags);


#define HUF_CTABLE_WORKSPACE_SIZE_U32 ((4 * (HUF_SYMBOLVALUE_MAX + 1)) + 192)
#define HUF_CTABLE_WORKSPACE_SIZE (HUF_CTABLE_WORKSPACE_SIZE_U32 * sizeof(unsigned))
size_t HUF_buildCTable_wksp (HUF_CElt* tree,
                       const unsigned* count, U32 maxSymbolValue, U32 maxNbBits,
                             void* workSpace, size_t wkspSize);


size_t HUF_readStats(BYTE* huffWeight, size_t hwSize,
                     U32* rankStats, U32* nbSymbolsPtr, U32* tableLogPtr,
                     const void* src, size_t srcSize);


#define HUF_READ_STATS_WORKSPACE_SIZE_U32 FSE_DECOMPRESS_WKSP_SIZE_U32(6, HUF_TABLELOG_MAX-1)
#define HUF_READ_STATS_WORKSPACE_SIZE (HUF_READ_STATS_WORKSPACE_SIZE_U32 * sizeof(unsigned))
size_t HUF_readStats_wksp(BYTE* huffWeight, size_t hwSize,
                          U32* rankStats, U32* nbSymbolsPtr, U32* tableLogPtr,
                          const void* src, size_t srcSize,
                          void* workspace, size_t wkspSize,
                          int flags);


size_t HUF_readCTable (HUF_CElt* CTable, unsigned* maxSymbolValuePtr, const void* src, size_t srcSize, unsigned *hasZeroWeights);


U32 HUF_getNbBitsFromCTable(const HUF_CElt* symbolTable, U32 symbolValue);

typedef struct {
    BYTE tableLog;
    BYTE maxSymbolValue;
    BYTE unused[sizeof(size_t) - 2];
} HUF_CTableHeader;


HUF_CTableHeader HUF_readCTableHeader(HUF_CElt const* ctable);




U32 HUF_selectDecoder (size_t dstSize, size_t cSrcSize);


#define HUF_DECOMPRESS_WORKSPACE_SIZE ((2 << 10) + (1 << 9))
#define HUF_DECOMPRESS_WORKSPACE_SIZE_U32 (HUF_DECOMPRESS_WORKSPACE_SIZE / sizeof(U32))






size_t HUF_compress1X_usingCTable(void* dst, size_t dstSize, const void* src, size_t srcSize, const HUF_CElt* CTable, int flags);

size_t HUF_compress1X_repeat(void* dst, size_t dstSize,
                       const void* src, size_t srcSize,
                       unsigned maxSymbolValue, unsigned tableLog,
                       void* workSpace, size_t wkspSize,   /**< `workSpace` must be aligned on 4-bytes boundaries, `wkspSize` must be >= HUF_WORKSPACE_SIZE */
                       HUF_CElt* hufTable, HUF_repeat* repeat, int flags);

size_t HUF_decompress1X_DCtx_wksp(HUF_DTable* dctx, void* dst, size_t dstSize, const void* cSrc, size_t cSrcSize, void* workSpace, size_t wkspSize, int flags);
#ifndef HUF_FORCE_DECOMPRESS_X1
size_t HUF_decompress1X2_DCtx_wksp(HUF_DTable* dctx, void* dst, size_t dstSize, const void* cSrc, size_t cSrcSize, void* workSpace, size_t wkspSize, int flags);   /**< double-symbols decoder */
#endif


size_t HUF_decompress1X_usingDTable(void* dst, size_t maxDstSize, const void* cSrc, size_t cSrcSize, const HUF_DTable* DTable, int flags);
#ifndef HUF_FORCE_DECOMPRESS_X2
size_t HUF_decompress1X1_DCtx_wksp(HUF_DTable* dctx, void* dst, size_t dstSize, const void* cSrc, size_t cSrcSize, void* workSpace, size_t wkspSize, int flags);
#endif
size_t HUF_decompress4X_usingDTable(void* dst, size_t maxDstSize, const void* cSrc, size_t cSrcSize, const HUF_DTable* DTable, int flags);
size_t HUF_decompress4X_hufOnly_wksp(HUF_DTable* dctx, void* dst, size_t dstSize, const void* cSrc, size_t cSrcSize, void* workSpace, size_t wkspSize, int flags);
#ifndef HUF_FORCE_DECOMPRESS_X2
size_t HUF_readDTableX1_wksp(HUF_DTable* DTable, const void* src, size_t srcSize, void* workSpace, size_t wkspSize, int flags);
#endif
#ifndef HUF_FORCE_DECOMPRESS_X1
size_t HUF_readDTableX2_wksp(HUF_DTable* DTable, const void* src, size_t srcSize, void* workSpace, size_t wkspSize, int flags);
#endif

#endif   /* HUF_H_298734234 */
/**** ended inlining huf.h ****/
/**** skipping file: bits.h ****/



unsigned FSE_versionNumber(void) { return FSE_VERSION_NUMBER; }



unsigned FSE_isError(size_t code) { return ERR_isError(code); }
const char* FSE_getErrorName(size_t code) { return ERR_getErrorName(code); }

unsigned HUF_isError(size_t code) { return ERR_isError(code); }
const char* HUF_getErrorName(size_t code) { return ERR_getErrorName(code); }



FORCE_INLINE_TEMPLATE
size_t FSE_readNCount_body(short* normalizedCounter, unsigned* maxSVPtr, unsigned* tableLogPtr,
                           const void* headerBuffer, size_t hbSize)
{
    const BYTE* const istart = (const BYTE*) headerBuffer;
    const BYTE* const iend = istart + hbSize;
    const BYTE* ip = istart;
    int nbBits;
    int remaining;
    int threshold;
    U32 bitStream;
    int bitCount;
    unsigned charnum = 0;
    unsigned const maxSV1 = *maxSVPtr + 1;
    int previous0 = 0;

    if (hbSize < 8) {

        char buffer[8] = {0};
        ZSTD_memcpy(buffer, headerBuffer, hbSize);
        {   size_t const countSize = FSE_readNCount(normalizedCounter, maxSVPtr, tableLogPtr,
                                                    buffer, sizeof(buffer));
            if (FSE_isError(countSize)) return countSize;
            if (countSize > hbSize) return ERROR(corruption_detected);
            return countSize;
    }   }
    assert(hbSize >= 8);


    ZSTD_memset(normalizedCounter, 0, (*maxSVPtr+1) * sizeof(normalizedCounter[0]));   /* all symbols not present in NCount have a frequency of 0 */
    bitStream = MEM_readLE32(ip);
    nbBits = (bitStream & 0xF) + FSE_MIN_TABLELOG;   /* extract tableLog */
    if (nbBits > FSE_TABLELOG_ABSOLUTE_MAX) return ERROR(tableLog_tooLarge);
    bitStream >>= 4;
    bitCount = 4;
    *tableLogPtr = nbBits;
    remaining = (1<<nbBits)+1;
    threshold = 1<<nbBits;
    nbBits++;

    for (;;) {
        if (previous0) {

            int repeats = ZSTD_countTrailingZeros32(~bitStream | 0x80000000) >> 1;
            while (repeats >= 12) {
                charnum += 3 * 12;
                if (LIKELY(ip <= iend-7)) {
                    ip += 3;
                } else {
                    bitCount -= (int)(8 * (iend - 7 - ip));
                    bitCount &= 31;
                    ip = iend - 4;
                }
                bitStream = MEM_readLE32(ip) >> bitCount;
                repeats = ZSTD_countTrailingZeros32(~bitStream | 0x80000000) >> 1;
            }
            charnum += 3 * repeats;
            bitStream >>= 2 * repeats;
            bitCount += 2 * repeats;


            assert((bitStream & 3) < 3);
            charnum += bitStream & 3;
            bitCount += 2;


            if (charnum >= maxSV1) break;



            if (LIKELY(ip <= iend-7) || (ip + (bitCount>>3) <= iend-4)) {
                assert((bitCount >> 3) <= 3); /* For first condition to work */
                ip += bitCount>>3;
                bitCount &= 7;
            } else {
                bitCount -= (int)(8 * (iend - 4 - ip));
                bitCount &= 31;
                ip = iend - 4;
            }
            bitStream = MEM_readLE32(ip) >> bitCount;
        }
        {
            int const max = (2*threshold-1) - remaining;
            int count;

            if ((bitStream & (threshold-1)) < (U32)max) {
                count = bitStream & (threshold-1);
                bitCount += nbBits-1;
            } else {
                count = bitStream & (2*threshold-1);
                if (count >= threshold) count -= max;
                bitCount += nbBits;
            }

            count--;   /* extra accuracy */

            if (count >= 0) {
                remaining -= count;
            } else {
                assert(count == -1);
                remaining += count;
            }
            normalizedCounter[charnum++] = (short)count;
            previous0 = !count;

            assert(threshold > 1);
            if (remaining < threshold) {

                if (remaining <= 1) break;
                nbBits = ZSTD_highbit32(remaining) + 1;
                threshold = 1 << (nbBits - 1);
            }
            if (charnum >= maxSV1) break;

            if (LIKELY(ip <= iend-7) || (ip + (bitCount>>3) <= iend-4)) {
                ip += bitCount>>3;
                bitCount &= 7;
            } else {
                bitCount -= (int)(8 * (iend - 4 - ip));
                bitCount &= 31;
                ip = iend - 4;
            }
            bitStream = MEM_readLE32(ip) >> bitCount;
    }   }
    if (remaining != 1) return ERROR(corruption_detected);

    if (charnum > maxSV1) return ERROR(maxSymbolValue_tooSmall);
    if (bitCount > 32) return ERROR(corruption_detected);
    *maxSVPtr = charnum-1;

    ip += (bitCount+7)>>3;
    return ip-istart;
}


static size_t FSE_readNCount_body_default(
        short* normalizedCounter, unsigned* maxSVPtr, unsigned* tableLogPtr,
        const void* headerBuffer, size_t hbSize)
{
    return FSE_readNCount_body(normalizedCounter, maxSVPtr, tableLogPtr, headerBuffer, hbSize);
}

#if DYNAMIC_BMI2
BMI2_TARGET_ATTRIBUTE static size_t FSE_readNCount_body_bmi2(
        short* normalizedCounter, unsigned* maxSVPtr, unsigned* tableLogPtr,
        const void* headerBuffer, size_t hbSize)
{
    return FSE_readNCount_body(normalizedCounter, maxSVPtr, tableLogPtr, headerBuffer, hbSize);
}
#else
#define FSE_readNCount_body_bmi2 FSE_readNCount_body_default
#endif

size_t FSE_readNCount_bmi2(
        short* normalizedCounter, unsigned* maxSVPtr, unsigned* tableLogPtr,
        const void* headerBuffer, size_t hbSize, int bmi2)
{
    if (ZSTD_USE_BMI2(bmi2)) {
        return FSE_readNCount_body_bmi2(normalizedCounter, maxSVPtr, tableLogPtr, headerBuffer, hbSize);
    }
    (void)bmi2;
    return FSE_readNCount_body_default(normalizedCounter, maxSVPtr, tableLogPtr, headerBuffer, hbSize);
}

size_t FSE_readNCount(
        short* normalizedCounter, unsigned* maxSVPtr, unsigned* tableLogPtr,
        const void* headerBuffer, size_t hbSize)
{
    return FSE_readNCount_bmi2(normalizedCounter, maxSVPtr, tableLogPtr, headerBuffer, hbSize, /* bmi2 */ 0);
}



size_t HUF_readStats(BYTE* huffWeight, size_t hwSize, U32* rankStats,
                     U32* nbSymbolsPtr, U32* tableLogPtr,
                     const void* src, size_t srcSize)
{
    U32 wksp[HUF_READ_STATS_WORKSPACE_SIZE_U32];
    return HUF_readStats_wksp(huffWeight, hwSize, rankStats, nbSymbolsPtr, tableLogPtr, src, srcSize, wksp, sizeof(wksp), /* flags */ 0);
}

FORCE_INLINE_TEMPLATE size_t
HUF_readStats_body(BYTE* huffWeight, size_t hwSize, U32* rankStats,
                   U32* nbSymbolsPtr, U32* tableLogPtr,
                   const void* src, size_t srcSize,
                   void* workSpace, size_t wkspSize,
                   int bmi2)
{
    U32 weightTotal;
    const BYTE* ip = (const BYTE*) src;
    size_t iSize;
    size_t oSize;

    if (!srcSize) return ERROR(srcSize_wrong);
    iSize = ip[0];
/* is not necessary, even though some analyzer complain ... */

    if (iSize >= 128) {  /* special header */
        oSize = iSize - 127;
        iSize = ((oSize+1)/2);
        if (iSize+1 > srcSize) return ERROR(srcSize_wrong);
        if (oSize >= hwSize) return ERROR(corruption_detected);
        ip += 1;
        {   U32 n;
            for (n=0; n<oSize; n+=2) {
                huffWeight[n]   = ip[n/2] >> 4;
                huffWeight[n+1] = ip[n/2] & 15;
    }   }   }
    else  {   /* header compressed with FSE (normal case) */
        if (iSize+1 > srcSize) return ERROR(srcSize_wrong);

        oSize = FSE_decompress_wksp_bmi2(huffWeight, hwSize-1, ip+1, iSize, 6, workSpace, wkspSize, bmi2);
        if (FSE_isError(oSize)) return oSize;
    }


    ZSTD_memset(rankStats, 0, (HUF_TABLELOG_MAX + 1) * sizeof(U32));
    weightTotal = 0;
    {   U32 n; for (n=0; n<oSize; n++) {
            if (huffWeight[n] > HUF_TABLELOG_MAX) return ERROR(corruption_detected);
            rankStats[huffWeight[n]]++;
            weightTotal += (1 << huffWeight[n]) >> 1;
    }   }
    if (weightTotal == 0) return ERROR(corruption_detected);


    {   U32 const tableLog = ZSTD_highbit32(weightTotal) + 1;
        if (tableLog > HUF_TABLELOG_MAX) return ERROR(corruption_detected);
        *tableLogPtr = tableLog;

        {   U32 const total = 1 << tableLog;
            U32 const rest = total - weightTotal;
            U32 const verif = 1 << ZSTD_highbit32(rest);
            U32 const lastWeight = ZSTD_highbit32(rest) + 1;
            if (verif != rest) return ERROR(corruption_detected);    /* last value must be a clean power of 2 */
            huffWeight[oSize] = (BYTE)lastWeight;
            rankStats[lastWeight]++;
    }   }


    if ((rankStats[1] < 2) || (rankStats[1] & 1)) return ERROR(corruption_detected);   /* by construction : at least 2 elts of rank 1, must be even */


    *nbSymbolsPtr = (U32)(oSize+1);
    return iSize+1;
}


static size_t HUF_readStats_body_default(BYTE* huffWeight, size_t hwSize, U32* rankStats,
                     U32* nbSymbolsPtr, U32* tableLogPtr,
                     const void* src, size_t srcSize,
                     void* workSpace, size_t wkspSize)
{
    return HUF_readStats_body(huffWeight, hwSize, rankStats, nbSymbolsPtr, tableLogPtr, src, srcSize, workSpace, wkspSize, 0);
}

#if DYNAMIC_BMI2
static BMI2_TARGET_ATTRIBUTE size_t HUF_readStats_body_bmi2(BYTE* huffWeight, size_t hwSize, U32* rankStats,
                     U32* nbSymbolsPtr, U32* tableLogPtr,
                     const void* src, size_t srcSize,
                     void* workSpace, size_t wkspSize)
{
    return HUF_readStats_body(huffWeight, hwSize, rankStats, nbSymbolsPtr, tableLogPtr, src, srcSize, workSpace, wkspSize, 1);
}
#else
#define HUF_readStats_body_bmi2 HUF_readStats_body_default
#endif

size_t HUF_readStats_wksp(BYTE* huffWeight, size_t hwSize, U32* rankStats,
                     U32* nbSymbolsPtr, U32* tableLogPtr,
                     const void* src, size_t srcSize,
                     void* workSpace, size_t wkspSize,
                     int flags)
{
    if (ZSTD_USE_BMI2(flags & HUF_flags_bmi2)) {
        return HUF_readStats_body_bmi2(huffWeight, hwSize, rankStats, nbSymbolsPtr, tableLogPtr, src, srcSize, workSpace, wkspSize);
    }
    (void)flags;
    return HUF_readStats_body_default(huffWeight, hwSize, rankStats, nbSymbolsPtr, tableLogPtr, src, srcSize, workSpace, wkspSize);
}
/**** ended inlining common/entropy_common.c ****/
/**** start inlining common/error_private.c ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */



/**** skipping file: error_private.h ****/

const char* ERR_getErrorString(ERR_enum code)
{
#ifdef ZSTD_STRIP_ERROR_STRINGS
    (void)code;
    return "Error strings stripped";
#else
    static const char* const notErrorCode = "Unspecified error code";
    switch( code )
    {
    case PREFIX(no_error): return "No error detected";
    case PREFIX(GENERIC):  return "Error (generic)";
    case PREFIX(prefix_unknown): return "Unknown frame descriptor";
    case PREFIX(version_unsupported): return "Version not supported";
    case PREFIX(frameParameter_unsupported): return "Unsupported frame parameter";
    case PREFIX(frameParameter_windowTooLarge): return "Frame requires too much memory for decoding";
    case PREFIX(corruption_detected): return "Data corruption detected";
    case PREFIX(checksum_wrong): return "Restored data doesn't match checksum";
    case PREFIX(literals_headerWrong): return "Header of Literals' block doesn't respect format specification";
    case PREFIX(parameter_unsupported): return "Unsupported parameter";
    case PREFIX(parameter_combination_unsupported): return "Unsupported combination of parameters";
    case PREFIX(parameter_outOfBound): return "Parameter is out of bound";
    case PREFIX(init_missing): return "Context should be init first";
    case PREFIX(memory_allocation): return "Allocation error : not enough memory";
    case PREFIX(workSpace_tooSmall): return "workSpace buffer is not large enough";
    case PREFIX(stage_wrong): return "Operation not authorized at current processing stage";
    case PREFIX(tableLog_tooLarge): return "tableLog requires too much memory : unsupported";
    case PREFIX(maxSymbolValue_tooLarge): return "Unsupported max Symbol Value : too large";
    case PREFIX(maxSymbolValue_tooSmall): return "Specified maxSymbolValue is too small";
    case PREFIX(cannotProduce_uncompressedBlock): return "This mode cannot generate an uncompressed block";
    case PREFIX(stabilityCondition_notRespected): return "pledged buffer stability condition is not respected";
    case PREFIX(dictionary_corrupted): return "Dictionary is corrupted";
    case PREFIX(dictionary_wrong): return "Dictionary mismatch";
    case PREFIX(dictionaryCreation_failed): return "Cannot create Dictionary from provided samples";
    case PREFIX(dstSize_tooSmall): return "Destination buffer is too small";
    case PREFIX(srcSize_wrong): return "Src size is incorrect";
    case PREFIX(dstBuffer_null): return "Operation on NULL destination buffer";
    case PREFIX(noForwardProgress_destFull): return "Operation made no progress over multiple calls, due to output buffer being full";
    case PREFIX(noForwardProgress_inputEmpty): return "Operation made no progress over multiple calls, due to input being empty";

    case PREFIX(frameIndex_tooLarge): return "Frame index is too large";
    case PREFIX(seekableIO): return "An I/O error occurred when reading/seeking";
    case PREFIX(dstBuffer_wrong): return "Destination buffer is wrong";
    case PREFIX(srcBuffer_wrong): return "Source buffer is wrong";
    case PREFIX(sequenceProducer_failed): return "Block-level external sequence producer returned an error code";
    case PREFIX(externalSequences_invalid): return "External sequences are not valid";
    case PREFIX(maxCode):
    default: return notErrorCode;
    }
#endif
}
/**** ended inlining common/error_private.c ****/
/**** start inlining common/fse_decompress.c ****/
/* ******************************************************************
 * FSE : Finite State Entropy decoder
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 *  You can contact the author at :
 *  - FSE source repository : https://github.com/Cyan4973/FiniteStateEntropy
 *  - Public forum : https://groups.google.com/forum/#!forum/lz4c
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
****************************************************************** */



/**** skipping file: debug.h ****/
/**** skipping file: bitstream.h ****/
/**** skipping file: bmi2.h ****/
/**** skipping file: compiler.h ****/
#define FSE_STATIC_LINKING_ONLY
/**** skipping file: fse.h ****/
/**** skipping file: error_private.h ****/
/**** skipping file: zstd_deps.h ****/
/**** skipping file: bits.h ****/



#define FSE_isError ERR_isError
#define FSE_STATIC_ASSERT(c) DEBUG_STATIC_ASSERT(c)   /* use only *after* variable declarations */






#ifndef FSE_FUNCTION_EXTENSION
#  error "FSE_FUNCTION_EXTENSION must be defined"
#endif
#ifndef FSE_FUNCTION_TYPE
#  error "FSE_FUNCTION_TYPE must be defined"
#endif


#define FSE_CAT(X,Y) X##Y
#define FSE_FUNCTION_NAME(X,Y) FSE_CAT(X,Y)
#define FSE_TYPE_NAME(X,Y) FSE_CAT(X,Y)

static size_t FSE_buildDTable_internal(FSE_DTable* dt, const short* normalizedCounter, unsigned maxSymbolValue, unsigned tableLog, void* workSpace, size_t wkspSize)
{
    void* const tdPtr = dt+1;   /* because *dt is unsigned, 32-bits aligned on 32-bits */
    FSE_DECODE_TYPE* const tableDecode = (FSE_DECODE_TYPE*) (tdPtr);
    U16* symbolNext = (U16*)workSpace;
    BYTE* spread = (BYTE*)(symbolNext + maxSymbolValue + 1);

    U32 const maxSV1 = maxSymbolValue + 1;
    U32 const tableSize = 1 << tableLog;
    U32 highThreshold = tableSize-1;


    if (FSE_BUILD_DTABLE_WKSP_SIZE(tableLog, maxSymbolValue) > wkspSize) return ERROR(maxSymbolValue_tooLarge);
    if (maxSymbolValue > FSE_MAX_SYMBOL_VALUE) return ERROR(maxSymbolValue_tooLarge);
    if (tableLog > FSE_MAX_TABLELOG) return ERROR(tableLog_tooLarge);


    {   FSE_DTableHeader DTableH;
        DTableH.tableLog = (U16)tableLog;
        DTableH.fastMode = 1;
        {   S16 const largeLimit= (S16)(1 << (tableLog-1));
            U32 s;
            for (s=0; s<maxSV1; s++) {
                if (normalizedCounter[s]==-1) {
                    tableDecode[highThreshold--].symbol = (FSE_FUNCTION_TYPE)s;
                    symbolNext[s] = 1;
                } else {
                    if (normalizedCounter[s] >= largeLimit) DTableH.fastMode=0;
                    symbolNext[s] = (U16)normalizedCounter[s];
        }   }   }
        ZSTD_memcpy(dt, &DTableH, sizeof(DTableH));
    }


    if (highThreshold == tableSize - 1) {
        size_t const tableMask = tableSize-1;
        size_t const step = FSE_TABLESTEP(tableSize);

        {   U64 const add = 0x0101010101010101ull;
            size_t pos = 0;
            U64 sv = 0;
            U32 s;
            for (s=0; s<maxSV1; ++s, sv += add) {
                int i;
                int const n = normalizedCounter[s];
                MEM_write64(spread + pos, sv);
                for (i = 8; i < n; i += 8) {
                    MEM_write64(spread + pos + i, sv);
                }
                pos += (size_t)n;
        }   }

        {
            size_t position = 0;
            size_t s;
            size_t const unroll = 2;
            assert(tableSize % unroll == 0); /* FSE_MIN_TABLELOG is 5 */
            for (s = 0; s < (size_t)tableSize; s += unroll) {
                size_t u;
                for (u = 0; u < unroll; ++u) {
                    size_t const uPosition = (position + (u * step)) & tableMask;
                    tableDecode[uPosition].symbol = spread[s + u];
                }
                position = (position + (unroll * step)) & tableMask;
            }
            assert(position == 0);
        }
    } else {
        U32 const tableMask = tableSize-1;
        U32 const step = FSE_TABLESTEP(tableSize);
        U32 s, position = 0;
        for (s=0; s<maxSV1; s++) {
            int i;
            for (i=0; i<normalizedCounter[s]; i++) {
                tableDecode[position].symbol = (FSE_FUNCTION_TYPE)s;
                position = (position + step) & tableMask;
                while (position > highThreshold) position = (position + step) & tableMask;   /* lowprob area */
        }   }
        if (position!=0) return ERROR(GENERIC);   /* position must reach all cells once, otherwise normalizedCounter is incorrect */
    }


    {   U32 u;
        for (u=0; u<tableSize; u++) {
            FSE_FUNCTION_TYPE const symbol = (FSE_FUNCTION_TYPE)(tableDecode[u].symbol);
            U32 const nextState = symbolNext[symbol]++;
            tableDecode[u].nbBits = (BYTE) (tableLog - ZSTD_highbit32(nextState) );
            tableDecode[u].newState = (U16) ( (nextState << tableDecode[u].nbBits) - tableSize);
    }   }

    return 0;
}

size_t FSE_buildDTable_wksp(FSE_DTable* dt, const short* normalizedCounter, unsigned maxSymbolValue, unsigned tableLog, void* workSpace, size_t wkspSize)
{
    return FSE_buildDTable_internal(dt, normalizedCounter, maxSymbolValue, tableLog, workSpace, wkspSize);
}


#ifndef FSE_COMMONDEFS_ONLY



FORCE_INLINE_TEMPLATE size_t FSE_decompress_usingDTable_generic(
          void* dst, size_t maxDstSize,
    const void* cSrc, size_t cSrcSize,
    const FSE_DTable* dt, const unsigned fast)
{
    BYTE* const ostart = (BYTE*) dst;
    BYTE* op = ostart;
    BYTE* const omax = op + maxDstSize;
    BYTE* const olimit = omax-3;

    BIT_DStream_t bitD;
    FSE_DState_t state1;
    FSE_DState_t state2;


    CHECK_F(BIT_initDStream(&bitD, cSrc, cSrcSize));

    FSE_initDState(&state1, &bitD, dt);
    FSE_initDState(&state2, &bitD, dt);

    RETURN_ERROR_IF(BIT_reloadDStream(&bitD)==BIT_DStream_overflow, corruption_detected, "");

#define FSE_GETSYMBOL(statePtr) fast ? FSE_decodeSymbolFast(statePtr, &bitD) : FSE_decodeSymbol(statePtr, &bitD)


    for ( ; (BIT_reloadDStream(&bitD)==BIT_DStream_unfinished) & (op<olimit) ; op+=4) {
        op[0] = FSE_GETSYMBOL(&state1);

        if (FSE_MAX_TABLELOG*2+7 > sizeof(bitD.bitContainer)*8)    /* This test must be static */
            BIT_reloadDStream(&bitD);

        op[1] = FSE_GETSYMBOL(&state2);

        if (FSE_MAX_TABLELOG*4+7 > sizeof(bitD.bitContainer)*8)    /* This test must be static */
            { if (BIT_reloadDStream(&bitD) > BIT_DStream_unfinished) { op+=2; break; } }

        op[2] = FSE_GETSYMBOL(&state1);

        if (FSE_MAX_TABLELOG*2+7 > sizeof(bitD.bitContainer)*8)    /* This test must be static */
            BIT_reloadDStream(&bitD);

        op[3] = FSE_GETSYMBOL(&state2);
    }



    while (1) {
        if (op>(omax-2)) return ERROR(dstSize_tooSmall);
        *op++ = FSE_GETSYMBOL(&state1);
        if (BIT_reloadDStream(&bitD)==BIT_DStream_overflow) {
            *op++ = FSE_GETSYMBOL(&state2);
            break;
        }

        if (op>(omax-2)) return ERROR(dstSize_tooSmall);
        *op++ = FSE_GETSYMBOL(&state2);
        if (BIT_reloadDStream(&bitD)==BIT_DStream_overflow) {
            *op++ = FSE_GETSYMBOL(&state1);
            break;
    }   }

    assert(op >= ostart);
    return (size_t)(op-ostart);
}

typedef struct {
    short ncount[FSE_MAX_SYMBOL_VALUE + 1];
} FSE_DecompressWksp;


FORCE_INLINE_TEMPLATE size_t FSE_decompress_wksp_body(
        void* dst, size_t dstCapacity,
        const void* cSrc, size_t cSrcSize,
        unsigned maxLog, void* workSpace, size_t wkspSize,
        int bmi2)
{
    const BYTE* const istart = (const BYTE*)cSrc;
    const BYTE* ip = istart;
    unsigned tableLog;
    unsigned maxSymbolValue = FSE_MAX_SYMBOL_VALUE;
    FSE_DecompressWksp* const wksp = (FSE_DecompressWksp*)workSpace;
    size_t const dtablePos = sizeof(FSE_DecompressWksp) / sizeof(FSE_DTable);
    FSE_DTable* const dtable = (FSE_DTable*)workSpace + dtablePos;

    FSE_STATIC_ASSERT((FSE_MAX_SYMBOL_VALUE + 1) % 2 == 0);
    if (wkspSize < sizeof(*wksp)) return ERROR(GENERIC);


    FSE_STATIC_ASSERT(sizeof(FSE_DecompressWksp) % sizeof(FSE_DTable) == 0);


    {   size_t const NCountLength =
            FSE_readNCount_bmi2(wksp->ncount, &maxSymbolValue, &tableLog, istart, cSrcSize, bmi2);
        if (FSE_isError(NCountLength)) return NCountLength;
        if (tableLog > maxLog) return ERROR(tableLog_tooLarge);
        assert(NCountLength <= cSrcSize);
        ip += NCountLength;
        cSrcSize -= NCountLength;
    }

    if (FSE_DECOMPRESS_WKSP_SIZE(tableLog, maxSymbolValue) > wkspSize) return ERROR(tableLog_tooLarge);
    assert(sizeof(*wksp) + FSE_DTABLE_SIZE(tableLog) <= wkspSize);
    workSpace = (BYTE*)workSpace + sizeof(*wksp) + FSE_DTABLE_SIZE(tableLog);
    wkspSize -= sizeof(*wksp) + FSE_DTABLE_SIZE(tableLog);

    CHECK_F( FSE_buildDTable_internal(dtable, wksp->ncount, maxSymbolValue, tableLog, workSpace, wkspSize) );

    {
        const void* ptr = dtable;
        const FSE_DTableHeader* DTableH = (const FSE_DTableHeader*)ptr;
        const U32 fastMode = DTableH->fastMode;


        if (fastMode) return FSE_decompress_usingDTable_generic(dst, dstCapacity, ip, cSrcSize, dtable, 1);
        return FSE_decompress_usingDTable_generic(dst, dstCapacity, ip, cSrcSize, dtable, 0);
    }
}


static size_t FSE_decompress_wksp_body_default(void* dst, size_t dstCapacity, const void* cSrc, size_t cSrcSize, unsigned maxLog, void* workSpace, size_t wkspSize)
{
    return FSE_decompress_wksp_body(dst, dstCapacity, cSrc, cSrcSize, maxLog, workSpace, wkspSize, 0);
}

#if DYNAMIC_BMI2
BMI2_TARGET_ATTRIBUTE static size_t FSE_decompress_wksp_body_bmi2(void* dst, size_t dstCapacity, const void* cSrc, size_t cSrcSize, unsigned maxLog, void* workSpace, size_t wkspSize)
{
    return FSE_decompress_wksp_body(dst, dstCapacity, cSrc, cSrcSize, maxLog, workSpace, wkspSize, 1);
}
#else
#define FSE_decompress_wksp_body_bmi2 FSE_decompress_wksp_body_default
#endif

size_t FSE_decompress_wksp_bmi2(void* dst, size_t dstCapacity, const void* cSrc, size_t cSrcSize, unsigned maxLog, void* workSpace, size_t wkspSize, int bmi2)
{
    if (ZSTD_USE_BMI2(bmi2)) {
        return FSE_decompress_wksp_body_bmi2(dst, dstCapacity, cSrc, cSrcSize, maxLog, workSpace, wkspSize);
    }
    (void)bmi2;
    return FSE_decompress_wksp_body_default(dst, dstCapacity, cSrc, cSrcSize, maxLog, workSpace, wkspSize);
}

#endif   /* FSE_COMMONDEFS_ONLY */
/**** ended inlining common/fse_decompress.c ****/
// @ivoanjo: Multithreading is disabled, so omit these unused sources to reduce zstd.c size.
// #include "common/threading.c"
// #include "common/pool.c"
/**** start inlining common/zstd_common.c ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */




#define ZSTD_DEPS_NEED_MALLOC
/**** skipping file: error_private.h ****/
/**** start inlining zstd_internal.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_CCOMMON_H_MODULE
#define ZSTD_CCOMMON_H_MODULE




/**** skipping file: compiler.h ****/
/**** start inlining cpu.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_COMMON_CPU_H
#define ZSTD_COMMON_CPU_H



/**** skipping file: mem.h ****/

#ifdef _MSC_VER
#include <intrin.h>
#endif

typedef struct {
    U32 f1c;
    U32 f1d;
    U32 f7b;
    U32 f7c;
} ZSTD_cpuid_t;

MEM_STATIC ZSTD_cpuid_t ZSTD_cpuid(void) {
    U32 f1c = 0;
    U32 f1d = 0;
    U32 f7b = 0;
    U32 f7c = 0;
#if defined(_MSC_VER) && (defined(_M_X64) || defined(_M_IX86))
#if !defined(_M_X64) || !defined(__clang__) || __clang_major__ >= 16
    int reg[4];
    __cpuid((int*)reg, 0);
    {
        int const n = reg[0];
        if (n >= 1) {
            __cpuid((int*)reg, 1);
            f1c = (U32)reg[2];
            f1d = (U32)reg[3];
        }
        if (n >= 7) {
            __cpuidex((int*)reg, 7, 0);
            f7b = (U32)reg[1];
            f7c = (U32)reg[2];
        }
    }
#else

    U32 n;
    __asm__(
        "pushq %%rbx\n\t"
        "cpuid\n\t"
        "popq %%rbx\n\t"
        : "=a"(n)
        : "a"(0)
        : "rcx", "rdx");
    if (n >= 1) {
      U32 f1a;
      __asm__(
          "pushq %%rbx\n\t"
          "cpuid\n\t"
          "popq %%rbx\n\t"
          : "=a"(f1a), "=c"(f1c), "=d"(f1d)
          : "a"(1)
          :);
    }
    if (n >= 7) {
      __asm__(
          "pushq %%rbx\n\t"
          "cpuid\n\t"
          "movq %%rbx, %%rax\n\t"
          "popq %%rbx"
          : "=a"(f7b), "=c"(f7c)
          : "a"(7), "c"(0)
          : "rdx");
    }
#endif
#elif defined(__i386__) && defined(__PIC__) && !defined(__clang__) && defined(__GNUC__)

    U32 n;
    __asm__(
        "pushl %%ebx\n\t"
        "cpuid\n\t"
        "popl %%ebx\n\t"
        : "=a"(n)
        : "a"(0)
        : "ecx", "edx");
    if (n >= 1) {
      U32 f1a;
      __asm__(
          "pushl %%ebx\n\t"
          "cpuid\n\t"
          "popl %%ebx\n\t"
          : "=a"(f1a), "=c"(f1c), "=d"(f1d)
          : "a"(1));
    }
    if (n >= 7) {
      __asm__(
          "pushl %%ebx\n\t"
          "cpuid\n\t"
          "movl %%ebx, %%eax\n\t"
          "popl %%ebx"
          : "=a"(f7b), "=c"(f7c)
          : "a"(7), "c"(0)
          : "edx");
    }
#elif defined(__x86_64__) || defined(_M_X64) || defined(__i386__)
    U32 n;
    __asm__("cpuid" : "=a"(n) : "a"(0) : "ebx", "ecx", "edx");
    if (n >= 1) {
      U32 f1a;
      __asm__("cpuid" : "=a"(f1a), "=c"(f1c), "=d"(f1d) : "a"(1) : "ebx");
    }
    if (n >= 7) {
      U32 f7a;
      __asm__("cpuid"
              : "=a"(f7a), "=b"(f7b), "=c"(f7c)
              : "a"(7), "c"(0)
              : "edx");
    }
#endif
    {
        ZSTD_cpuid_t cpuid;
        cpuid.f1c = f1c;
        cpuid.f1d = f1d;
        cpuid.f7b = f7b;
        cpuid.f7c = f7c;
        return cpuid;
    }
}

#define X(name, r, bit)                                                        \
  MEM_STATIC int ZSTD_cpuid_##name(ZSTD_cpuid_t const cpuid) {                 \
    return ((cpuid.r) & (1U << bit)) != 0;                                     \
  }


#define C(name, bit) X(name, f1c, bit)
  C(sse3, 0)
  C(pclmuldq, 1)
  C(dtes64, 2)
  C(monitor, 3)
  C(dscpl, 4)
  C(vmx, 5)
  C(smx, 6)
  C(eist, 7)
  C(tm2, 8)
  C(ssse3, 9)
  C(cnxtid, 10)
  C(fma, 12)
  C(cx16, 13)
  C(xtpr, 14)
  C(pdcm, 15)
  C(pcid, 17)
  C(dca, 18)
  C(sse41, 19)
  C(sse42, 20)
  C(x2apic, 21)
  C(movbe, 22)
  C(popcnt, 23)
  C(tscdeadline, 24)
  C(aes, 25)
  C(xsave, 26)
  C(osxsave, 27)
  C(avx, 28)
  C(f16c, 29)
  C(rdrand, 30)
#undef C
#define D(name, bit) X(name, f1d, bit)
  D(fpu, 0)
  D(vme, 1)
  D(de, 2)
  D(pse, 3)
  D(tsc, 4)
  D(msr, 5)
  D(pae, 6)
  D(mce, 7)
  D(cx8, 8)
  D(apic, 9)
  D(sep, 11)
  D(mtrr, 12)
  D(pge, 13)
  D(mca, 14)
  D(cmov, 15)
  D(pat, 16)
  D(pse36, 17)
  D(psn, 18)
  D(clfsh, 19)
  D(ds, 21)
  D(acpi, 22)
  D(mmx, 23)
  D(fxsr, 24)
  D(sse, 25)
  D(sse2, 26)
  D(ss, 27)
  D(htt, 28)
  D(tm, 29)
  D(pbe, 31)
#undef D


#define B(name, bit) X(name, f7b, bit)
  B(bmi1, 3)
  B(hle, 4)
  B(avx2, 5)
  B(smep, 7)
  B(bmi2, 8)
  B(erms, 9)
  B(invpcid, 10)
  B(rtm, 11)
  B(mpx, 14)
  B(avx512f, 16)
  B(avx512dq, 17)
  B(rdseed, 18)
  B(adx, 19)
  B(smap, 20)
  B(avx512ifma, 21)
  B(pcommit, 22)
  B(clflushopt, 23)
  B(clwb, 24)
  B(avx512pf, 26)
  B(avx512er, 27)
  B(avx512cd, 28)
  B(sha, 29)
  B(avx512bw, 30)
  B(avx512vl, 31)
#undef B
#define C(name, bit) X(name, f7c, bit)
  C(prefetchwt1, 0)
  C(avx512vbmi, 1)
#undef C

#undef X

#endif /* ZSTD_COMMON_CPU_H */
/**** ended inlining cpu.h ****/
/**** skipping file: mem.h ****/
/**** skipping file: debug.h ****/
/**** skipping file: error_private.h ****/
#define ZSTD_STATIC_LINKING_ONLY
/**** start inlining ../zstd.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_H_235446
#define ZSTD_H_235446



#include <stddef.h>   /* size_t */

/**** skipping file: zstd_errors.h ****/
#if defined(ZSTD_STATIC_LINKING_ONLY) && !defined(ZSTD_H_ZSTD_STATIC_LINKING_ONLY)
#include <limits.h>   /* INT_MAX */
#endif /* ZSTD_STATIC_LINKING_ONLY */

#if defined (__cplusplus)
extern "C" {
#endif


#ifndef ZSTDLIB_VISIBLE

#  ifdef ZSTDLIB_VISIBILITY
#    define ZSTDLIB_VISIBLE ZSTDLIB_VISIBILITY
#  elif defined(__GNUC__) && (__GNUC__ >= 4) && !defined(__MINGW32__)
#    define ZSTDLIB_VISIBLE __attribute__ ((visibility ("default")))
#  else
#    define ZSTDLIB_VISIBLE
#  endif
#endif

#ifndef ZSTDLIB_HIDDEN
#  if defined(__GNUC__) && (__GNUC__ >= 4) && !defined(__MINGW32__)
#    define ZSTDLIB_HIDDEN __attribute__ ((visibility ("hidden")))
#  else
#    define ZSTDLIB_HIDDEN
#  endif
#endif

#if defined(ZSTD_DLL_EXPORT) && (ZSTD_DLL_EXPORT==1)
#  define ZSTDLIB_API __declspec(dllexport) ZSTDLIB_VISIBLE
#elif defined(ZSTD_DLL_IMPORT) && (ZSTD_DLL_IMPORT==1)
#  define ZSTDLIB_API __declspec(dllimport) ZSTDLIB_VISIBLE /* It isn't required but allows to generate better code, saving a function pointer load from the IAT and an indirect jump.*/
#else
#  define ZSTDLIB_API ZSTDLIB_VISIBLE
#endif


#ifdef ZSTD_DISABLE_DEPRECATE_WARNINGS
#  define ZSTD_DEPRECATED(message) /* disable deprecation warnings */
#else
#  if defined (__cplusplus) && (__cplusplus >= 201402) /* C++14 or greater */
#    define ZSTD_DEPRECATED(message) [[deprecated(message)]]
#  elif (defined(GNUC) && (GNUC > 4 || (GNUC == 4 && GNUC_MINOR >= 5))) || defined(__clang__) || defined(__IAR_SYSTEMS_ICC__)
#    define ZSTD_DEPRECATED(message) __attribute__((deprecated(message)))
#  elif defined(__GNUC__) && (__GNUC__ >= 3)
#    define ZSTD_DEPRECATED(message) __attribute__((deprecated))
#  elif defined(_MSC_VER)
#    define ZSTD_DEPRECATED(message) __declspec(deprecated(message))
#  else
#    pragma message("WARNING: You need to implement ZSTD_DEPRECATED for this compiler")
#    define ZSTD_DEPRECATED(message)
#  endif
#endif /* ZSTD_DISABLE_DEPRECATE_WARNINGS */


/*******************************************************************************
  Introduction

  zstd, short for Zstandard, is a fast lossless compression algorithm, targeting
  real-time compression scenarios at zlib-level and better compression ratios.
  The zstd compression library provides in-memory compression and decompression
  functions.

  The library supports regular compression levels from 1 up to ZSTD_maxCLevel(),
  which is currently 22. Levels >= 20, labeled `--ultra`, should be used with
  caution, as they require more memory. The library also offers negative
  compression levels, which extend the range of speed vs. ratio preferences.
  The lower the level, the faster the speed (at the cost of compression).

  Compression can be done in:
    - a single step (described as Simple API)
    - a single step, reusing a context (described as Explicit context)
    - unbounded multiple steps (described as Streaming compression)

  The compression ratio achievable on small data can be highly improved using
  a dictionary. Dictionary compression can be performed in:
    - a single step (described as Simple dictionary API)
    - a single step, reusing a dictionary (described as Bulk-processing
      dictionary API)

  Advanced experimental functions can be accessed using
  `#define ZSTD_STATIC_LINKING_ONLY` before including zstd.h.

  Advanced experimental APIs should never be used with a dynamically-linked
  library. They are not "stable"; their definitions or signatures may change in
  the future. Only static linking is allowed.
*******************************************************************************/


#define ZSTD_VERSION_MAJOR    1
#define ZSTD_VERSION_MINOR    6
#define ZSTD_VERSION_RELEASE  0
#define ZSTD_VERSION_NUMBER  (ZSTD_VERSION_MAJOR *100*100 + ZSTD_VERSION_MINOR *100 + ZSTD_VERSION_RELEASE)


ZSTDLIB_API unsigned ZSTD_versionNumber(void);

#define ZSTD_LIB_VERSION ZSTD_VERSION_MAJOR.ZSTD_VERSION_MINOR.ZSTD_VERSION_RELEASE
#define ZSTD_QUOTE(str) #str
#define ZSTD_EXPAND_AND_QUOTE(str) ZSTD_QUOTE(str)
#define ZSTD_VERSION_STRING ZSTD_EXPAND_AND_QUOTE(ZSTD_LIB_VERSION)


ZSTDLIB_API const char* ZSTD_versionString(void);


#ifndef ZSTD_CLEVEL_DEFAULT
#  define ZSTD_CLEVEL_DEFAULT 3
#endif




#define ZSTD_MAGICNUMBER            0xFD2FB528    /* valid since v0.8.0 */
#define ZSTD_MAGIC_DICTIONARY       0xEC30A437    /* valid since v0.7.0 */
#define ZSTD_MAGIC_SKIPPABLE_START  0x184D2A50    /* all 16 values, from 0x184D2A50 to 0x184D2A5F, signal the beginning of a skippable frame */
#define ZSTD_MAGIC_SKIPPABLE_MASK   0xFFFFFFF0

#define ZSTD_BLOCKSIZELOG_MAX  17
#define ZSTD_BLOCKSIZE_MAX     (1<<ZSTD_BLOCKSIZELOG_MAX)


/***************************************
*  Simple Core API
***************************************/

ZSTDLIB_API size_t ZSTD_compress( void* dst, size_t dstCapacity,
                            const void* src, size_t srcSize,
                                  int compressionLevel);


ZSTDLIB_API size_t ZSTD_decompress( void* dst, size_t dstCapacity,
                              const void* src, size_t compressedSize);





#define ZSTD_CONTENTSIZE_UNKNOWN (0ULL - 1)
#define ZSTD_CONTENTSIZE_ERROR   (0ULL - 2)
ZSTDLIB_API unsigned long long ZSTD_getFrameContentSize(const void *src, size_t srcSize);


ZSTD_DEPRECATED("Replaced by ZSTD_getFrameContentSize")
ZSTDLIB_API unsigned long long ZSTD_getDecompressedSize(const void* src, size_t srcSize);


ZSTDLIB_API size_t ZSTD_findFrameCompressedSize(const void* src, size_t srcSize);

typedef enum { ZSTD_frame, ZSTD_skippableFrame } ZSTD_FrameType_e;
#define ZSTD_frameType_e ZSTD_FrameType_e /* old name */
typedef struct {
    unsigned long long frameContentSize; /**< if == ZSTD_CONTENTSIZE_UNKNOWN, it means this field is not available. 0 means "empty" */
    unsigned long long windowSize;       /**< can be very large, up to <= frameContentSize */
    unsigned blockSizeMax;
    ZSTD_FrameType_e frameType;          /**< if == ZSTD_skippableFrame, frameContentSize is the size of skippable content */
    unsigned headerSize;
    unsigned dictID;                     /**< for ZSTD_skippableFrame, contains the skippable magic variant [0-15] */
    unsigned checksumFlag;
    unsigned _reserved1;
    unsigned _reserved2;
} ZSTD_FrameHeader;
#define ZSTD_frameHeader ZSTD_FrameHeader /* old name */


ZSTDLIB_API size_t ZSTD_getFrameHeader(ZSTD_FrameHeader* zfhPtr, const void* src, size_t srcSize);





#define ZSTD_MAX_INPUT_SIZE ((sizeof(size_t)==8) ? 0xFF00FF00FF00FF00ULL : 0xFF00FF00U)
#define ZSTD_COMPRESSBOUND(srcSize)   (((size_t)(srcSize) >= ZSTD_MAX_INPUT_SIZE) ? 0 : (srcSize) + ((srcSize)>>8) + (((srcSize) < (128<<10)) ? (((128<<10) - (srcSize)) >> 11) /* margin, from 64 to 0 */ : 0))  /* this formula ensures that bound(A) + bound(B) <= bound(A+B) as long as A and B >= 128 KB */
ZSTDLIB_API size_t ZSTD_compressBound(size_t srcSize); /*!< maximum compressed size in worst case single-pass scenario */




ZSTDLIB_API unsigned     ZSTD_isError(size_t result);      /*!< tells if a `size_t` function result is an error code */
ZSTDLIB_API ZSTD_ErrorCode ZSTD_getErrorCode(size_t functionResult); /* convert a result into an error code, which can be compared to error enum list */
ZSTDLIB_API const char*  ZSTD_getErrorName(size_t result); /*!< provides readable string from a function result */
ZSTDLIB_API int          ZSTD_minCLevel(void);             /*!< minimum negative compression level allowed, requires v1.4.0+ */
ZSTDLIB_API int          ZSTD_maxCLevel(void);             /*!< maximum compression level available */
ZSTDLIB_API int          ZSTD_defaultCLevel(void);         /*!< default compression level, specified by ZSTD_CLEVEL_DEFAULT, requires v1.5.0+ */


/***************************************
*  Explicit context
***************************************/

typedef struct ZSTD_CCtx_s ZSTD_CCtx;
ZSTDLIB_API ZSTD_CCtx* ZSTD_createCCtx(void);
ZSTDLIB_API size_t     ZSTD_freeCCtx(ZSTD_CCtx* cctx);  /* compatible with NULL pointer */


ZSTDLIB_API size_t ZSTD_compressCCtx(ZSTD_CCtx* cctx,
                                     void* dst, size_t dstCapacity,
                               const void* src, size_t srcSize,
                                     int compressionLevel);


typedef struct ZSTD_DCtx_s ZSTD_DCtx;
ZSTDLIB_API ZSTD_DCtx* ZSTD_createDCtx(void);
ZSTDLIB_API size_t     ZSTD_freeDCtx(ZSTD_DCtx* dctx);  /* accept NULL pointer */


ZSTDLIB_API size_t ZSTD_decompressDCtx(ZSTD_DCtx* dctx,
                                       void* dst, size_t dstCapacity,
                                 const void* src, size_t srcSize);


/*********************************************
*  Advanced compression API (Requires v1.4.0+)
**********************************************/





typedef enum { ZSTD_fast=1,
               ZSTD_dfast=2,
               ZSTD_greedy=3,
               ZSTD_lazy=4,
               ZSTD_lazy2=5,
               ZSTD_btlazy2=6,
               ZSTD_btopt=7,
               ZSTD_btultra=8,
               ZSTD_btultra2=9

} ZSTD_strategy;

typedef enum {


    ZSTD_c_compressionLevel=100, /* Set compression parameters according to pre-defined cLevel table.
                              * Note that exact compression parameters are dynamically determined,
                              * depending on both compression level and srcSize (when known).
                              * Default level is ZSTD_CLEVEL_DEFAULT==3.
                              * Special: value 0 means default, which is controlled by ZSTD_CLEVEL_DEFAULT.
                              * Note 1 : it's possible to pass a negative compression level.
                              * Note 2 : setting a level does not automatically set all other compression parameters
                              *   to default. Setting this will however eventually dynamically impact the compression
                              *   parameters which have not been manually set. The manually set
                              *   ones will 'stick'. */

    ZSTD_c_windowLog=101,    /* Maximum allowed back-reference distance, expressed as power of 2.
                              * This will set a memory budget for streaming decompression,
                              * with larger values requiring more memory
                              * and typically compressing more.
                              * Must be clamped between ZSTD_WINDOWLOG_MIN and ZSTD_WINDOWLOG_MAX.
                              * Special: value 0 means "use default windowLog".
                              * Note: Using a windowLog greater than ZSTD_WINDOWLOG_LIMIT_DEFAULT
                              *       requires explicitly allowing such size at streaming decompression stage. */
    ZSTD_c_hashLog=102,      /* Size of the initial probe table, as a power of 2.
                              * Resulting memory usage is (1 << (hashLog+2)).
                              * Must be clamped between ZSTD_HASHLOG_MIN and ZSTD_HASHLOG_MAX.
                              * Larger tables improve compression ratio of strategies <= dFast,
                              * and improve speed of strategies > dFast.
                              * Special: value 0 means "use default hashLog". */
    ZSTD_c_chainLog=103,     /* Size of the multi-probe search table, as a power of 2.
                              * Resulting memory usage is (1 << (chainLog+2)).
                              * Must be clamped between ZSTD_CHAINLOG_MIN and ZSTD_CHAINLOG_MAX.
                              * Larger tables result in better and slower compression.
                              * This parameter is useless for "fast" strategy.
                              * It's still useful when using "dfast" strategy,
                              * in which case it defines a secondary probe table.
                              * Special: value 0 means "use default chainLog". */
    ZSTD_c_searchLog=104,    /* Number of search attempts, as a power of 2.
                              * More attempts result in better and slower compression.
                              * This parameter is useless for "fast" and "dFast" strategies.
                              * Special: value 0 means "use default searchLog". */
    ZSTD_c_minMatch=105,     /* Minimum size of searched matches.
                              * Note that Zstandard can still find matches of smaller size,
                              * it just tweaks its search algorithm to look for this size and larger.
                              * Larger values increase compression and decompression speed, but decrease ratio.
                              * Must be clamped between ZSTD_MINMATCH_MIN and ZSTD_MINMATCH_MAX.
                              * Note that currently, for all strategies < btopt, effective minimum is 4.
                              *                    , for all strategies > fast, effective maximum is 6.
                              * Special: value 0 means "use default minMatchLength". */
    ZSTD_c_targetLength=106, /* Impact of this field depends on strategy.
                              * For strategies btopt, btultra & btultra2:
                              *     Length of Match considered "good enough" to stop search.
                              *     Larger values make compression stronger, and slower.
                              * For strategy fast:
                              *     Distance between match sampling.
                              *     Larger values make compression faster, and weaker.
                              * Special: value 0 means "use default targetLength". */
    ZSTD_c_strategy=107,     /* See ZSTD_strategy enum definition.
                              * The higher the value of selected strategy, the more complex it is,
                              * resulting in stronger and slower compression.
                              * Special: value 0 means "use default strategy". */

    ZSTD_c_targetCBlockSize=130, /* v1.5.6+
                                  * Attempts to fit compressed block size into approximately targetCBlockSize.
                                  * Bound by ZSTD_TARGETCBLOCKSIZE_MIN and ZSTD_TARGETCBLOCKSIZE_MAX.
                                  * Note that it's not a guarantee, just a convergence target (default:0).
                                  * No target when targetCBlockSize == 0.
                                  * This is helpful in low bandwidth streaming environments to improve end-to-end latency,
                                  * when a client can make use of partial documents (a prominent example being Chrome).
                                  * Note: this parameter is stable since v1.5.6.
                                  * It was present as an experimental parameter in earlier versions,
                                  * but it's not recommended using it with earlier library versions
                                  * due to massive performance regressions.
                                  */

    ZSTD_c_enableLongDistanceMatching=160, /* Enable long distance matching.
                                     * This parameter is designed to improve compression ratio
                                     * for large inputs, by finding large matches at long distance.
                                     * It increases memory usage and window size.
                                     * Note: enabling this parameter increases default ZSTD_c_windowLog to 128 MB
                                     * except when expressly set to a different value.
                                     * Note: will be enabled by default if ZSTD_c_windowLog >= 128 MB and
                                     * compression strategy >= ZSTD_btopt (== compression level 16+) */
    ZSTD_c_ldmHashLog=161,   /* Size of the table for long distance matching, as a power of 2.
                              * Larger values increase memory usage and compression ratio,
                              * but decrease compression speed.
                              * Must be clamped between ZSTD_HASHLOG_MIN and ZSTD_HASHLOG_MAX
                              * default: windowlog - 7.
                              * Special: value 0 means "automatically determine hashlog". */
    ZSTD_c_ldmMinMatch=162,  /* Minimum match size for long distance matcher.
                              * Larger/too small values usually decrease compression ratio.
                              * Must be clamped between ZSTD_LDM_MINMATCH_MIN and ZSTD_LDM_MINMATCH_MAX.
                              * Special: value 0 means "use default value" (default: 64). */
    ZSTD_c_ldmBucketSizeLog=163, /* Log size of each bucket in the LDM hash table for collision resolution.
                              * Larger values improve collision resolution but decrease compression speed.
                              * The maximum value is ZSTD_LDM_BUCKETSIZELOG_MAX.
                              * Special: value 0 means "use default value" (default: 3). */
    ZSTD_c_ldmHashRateLog=164, /* Frequency of inserting/looking up entries into the LDM hash table.
                              * Must be clamped between 0 and (ZSTD_WINDOWLOG_MAX - ZSTD_HASHLOG_MIN).
                              * Default is MAX(0, (windowLog - ldmHashLog)), optimizing hash table usage.
                              * Larger values improve compression speed.
                              * Deviating far from default value will likely result in a compression ratio decrease.
                              * Special: value 0 means "automatically determine hashRateLog". */


    ZSTD_c_contentSizeFlag=200, /* Content size will be written into frame header _whenever known_ (default:1)
                              * Content size must be known at the beginning of compression.
                              * This is automatically the case when using ZSTD_compress2(),
                              * For streaming scenarios, content size must be provided with ZSTD_CCtx_setPledgedSrcSize() */
    ZSTD_c_checksumFlag=201, /* A 32-bits checksum of content is written at end of frame (default:0) */
    ZSTD_c_dictIDFlag=202,   /* When applicable, dictionary's ID is written into frame header (default:1) */



    ZSTD_c_nbWorkers=400,    /* Select how many threads will be spawned to compress in parallel.
                              * When nbWorkers >= 1, triggers asynchronous mode when invoking ZSTD_compressStream*() :
                              * ZSTD_compressStream*() consumes input and flush output if possible, but immediately gives back control to caller,
                              * while compression is performed in parallel, within worker thread(s).
                              * (note : a strong exception to this rule is when first invocation of ZSTD_compressStream2() sets ZSTD_e_end :
                              *  in which case, ZSTD_compressStream2() delegates to ZSTD_compress2(), which is always a blocking call).
                              * More workers improve speed, but also increase memory usage.
                              * Default value is `0`, aka "single-threaded mode" : no worker is spawned,
                              * compression is performed inside Caller's thread, and all invocations are blocking */
    ZSTD_c_jobSize=401,      /* Size of a compression job. This value is enforced only when nbWorkers >= 1.
                              * Each compression job is completed in parallel, so this value can indirectly impact the nb of active threads.
                              * 0 means default, which is dynamically determined based on compression parameters.
                              * Job size must be a minimum of overlap size, or ZSTDMT_JOBSIZE_MIN (= 512 KB), whichever is largest.
                              * The minimum size is automatically and transparently enforced. */
    ZSTD_c_overlapLog=402,   /* Control the overlap size, as a fraction of window size.
                              * The overlap size is an amount of data reloaded from previous job at the beginning of a new job.
                              * It helps preserve compression ratio, while each job is compressed in parallel.
                              * This value is enforced only when nbWorkers >= 1.
                              * Larger values increase compression ratio, but decrease speed.
                              * Possible values range from 0 to 9 :
                              * - 0 means "default" : value will be determined by the library, depending on strategy
                              * - 1 means "no overlap"
                              * - 9 means "full overlap", using a full window size.
                              * Each intermediate rank increases/decreases load size by a factor 2 :
                              * 9: full window;  8: w/2;  7: w/4;  6: w/8;  5:w/16;  4: w/32;  3:w/64;  2:w/128;  1:no overlap;  0:default
                              * default value varies between 6 and 9, depending on strategy */


     ZSTD_c_experimentalParam1=500,
     ZSTD_c_experimentalParam2=10,
     ZSTD_c_experimentalParam3=1000,
     ZSTD_c_experimentalParam4=1001,
     ZSTD_c_experimentalParam5=1002,

     ZSTD_c_experimentalParam7=1004,
     ZSTD_c_experimentalParam8=1005,
     ZSTD_c_experimentalParam9=1006,
     ZSTD_c_experimentalParam10=1007,
     ZSTD_c_experimentalParam11=1008,
     ZSTD_c_experimentalParam12=1009,
     ZSTD_c_experimentalParam13=1010,
     ZSTD_c_experimentalParam14=1011,
     ZSTD_c_experimentalParam15=1012,
     ZSTD_c_experimentalParam16=1013,
     ZSTD_c_experimentalParam17=1014,
     ZSTD_c_experimentalParam18=1015,
     ZSTD_c_experimentalParam19=1016,
     ZSTD_c_experimentalParam20=1017
} ZSTD_cParameter;

typedef struct {
    size_t error;
    int lowerBound;
    int upperBound;
} ZSTD_bounds;


ZSTDLIB_API ZSTD_bounds ZSTD_cParam_getBounds(ZSTD_cParameter cParam);


ZSTDLIB_API size_t ZSTD_CCtx_setParameter(ZSTD_CCtx* cctx, ZSTD_cParameter param, int value);


ZSTDLIB_API size_t ZSTD_CCtx_setPledgedSrcSize(ZSTD_CCtx* cctx, unsigned long long pledgedSrcSize);

typedef enum {
    ZSTD_reset_session_only = 1,
    ZSTD_reset_parameters = 2,
    ZSTD_reset_session_and_parameters = 3
} ZSTD_ResetDirective;


ZSTDLIB_API size_t ZSTD_CCtx_reset(ZSTD_CCtx* cctx, ZSTD_ResetDirective reset);


ZSTDLIB_API size_t ZSTD_compress2( ZSTD_CCtx* cctx,
                                   void* dst, size_t dstCapacity,
                             const void* src, size_t srcSize);


/***********************************************
*  Advanced decompression API (Requires v1.4.0+)
************************************************/



typedef enum {

    ZSTD_d_windowLogMax=100, /* Select a size limit (in power of 2) beyond which
                              * the streaming API will refuse to allocate memory buffer
                              * in order to protect the host from unreasonable memory requirements.
                              * This parameter is only useful in streaming mode, since no internal buffer is allocated in single-pass mode.
                              * By default, a decompression context accepts window sizes <= (1 << ZSTD_WINDOWLOG_LIMIT_DEFAULT).
                              * Special: value 0 means "use default maximum windowLog". */


     ZSTD_d_experimentalParam1=1000,
     ZSTD_d_experimentalParam2=1001,
     ZSTD_d_experimentalParam3=1002,
     ZSTD_d_experimentalParam4=1003,
     ZSTD_d_experimentalParam5=1004,
     ZSTD_d_experimentalParam6=1005

} ZSTD_dParameter;


ZSTDLIB_API ZSTD_bounds ZSTD_dParam_getBounds(ZSTD_dParameter dParam);


ZSTDLIB_API size_t ZSTD_DCtx_setParameter(ZSTD_DCtx* dctx, ZSTD_dParameter param, int value);


ZSTDLIB_API size_t ZSTD_DCtx_reset(ZSTD_DCtx* dctx, ZSTD_ResetDirective reset);


/****************************
*  Streaming
****************************/

typedef struct ZSTD_inBuffer_s {
  const void* src;    /**< start of input buffer */
  size_t size;        /**< size of input buffer */
  size_t pos;         /**< position where reading stopped. Will be updated. Necessarily 0 <= pos <= size */
} ZSTD_inBuffer;

typedef struct ZSTD_outBuffer_s {
  void*  dst;         /**< start of output buffer */
  size_t size;        /**< size of output buffer */
  size_t pos;         /**< position where writing stopped. Will be updated. Necessarily 0 <= pos <= size */
} ZSTD_outBuffer;





typedef ZSTD_CCtx ZSTD_CStream;  /**< CCtx and CStream are now effectively same object (>= v1.3.0) */


ZSTDLIB_API ZSTD_CStream* ZSTD_createCStream(void);
ZSTDLIB_API size_t ZSTD_freeCStream(ZSTD_CStream* zcs);  /* accept NULL pointer */


typedef enum {
    ZSTD_e_continue=0, /* collect more data, encoder decides when to output compressed result, for optimal compression ratio */
    ZSTD_e_flush=1,    /* flush any data provided so far,
                        * it creates (at least) one new block, that can be decoded immediately on reception;
                        * frame will continue: any future data can still reference previously compressed data, improving compression.
                        * note : multithreaded compression will block to flush as much output as possible. */
    ZSTD_e_end=2       /* flush any remaining data _and_ close current frame.
                        * note that frame is only closed after compressed data is fully flushed (return value == 0).
                        * After that point, any additional data starts a new frame.
                        * note : each frame is independent (does not reference any content from previous frame).
                        : note : multithreaded compression will block to flush as much output as possible. */
} ZSTD_EndDirective;


ZSTDLIB_API size_t ZSTD_compressStream2( ZSTD_CCtx* cctx,
                                         ZSTD_outBuffer* output,
                                         ZSTD_inBuffer* input,
                                         ZSTD_EndDirective endOp);



ZSTDLIB_API size_t ZSTD_CStreamInSize(void);    /**< recommended size for input buffer */
ZSTDLIB_API size_t ZSTD_CStreamOutSize(void);   /**< recommended size for output buffer. Guarantee to successfully flush at least one complete compressed block. */





ZSTDLIB_API size_t ZSTD_initCStream(ZSTD_CStream* zcs, int compressionLevel);

ZSTDLIB_API size_t ZSTD_compressStream(ZSTD_CStream* zcs, ZSTD_outBuffer* output, ZSTD_inBuffer* input);

ZSTDLIB_API size_t ZSTD_flushStream(ZSTD_CStream* zcs, ZSTD_outBuffer* output);

ZSTDLIB_API size_t ZSTD_endStream(ZSTD_CStream* zcs, ZSTD_outBuffer* output);




typedef ZSTD_DCtx ZSTD_DStream;  /**< DCtx and DStream are now effectively same object (>= v1.3.0) */


ZSTDLIB_API ZSTD_DStream* ZSTD_createDStream(void);
ZSTDLIB_API size_t ZSTD_freeDStream(ZSTD_DStream* zds);  /* accept NULL pointer */




ZSTDLIB_API size_t ZSTD_initDStream(ZSTD_DStream* zds);


ZSTDLIB_API size_t ZSTD_decompressStream(ZSTD_DStream* zds, ZSTD_outBuffer* output, ZSTD_inBuffer* input);

ZSTDLIB_API size_t ZSTD_DStreamInSize(void);    /*!< recommended size for input buffer */
ZSTDLIB_API size_t ZSTD_DStreamOutSize(void);   /*!< recommended size for output buffer. Guarantee to successfully flush at least one complete block in all circumstances. */


/**************************
*  Simple dictionary API
***************************/

ZSTDLIB_API size_t ZSTD_compress_usingDict(ZSTD_CCtx* ctx,
                                           void* dst, size_t dstCapacity,
                                     const void* src, size_t srcSize,
                                     const void* dict,size_t dictSize,
                                           int compressionLevel);


ZSTDLIB_API size_t ZSTD_decompress_usingDict(ZSTD_DCtx* dctx,
                                             void* dst, size_t dstCapacity,
                                       const void* src, size_t srcSize,
                                       const void* dict,size_t dictSize);


/***********************************
 *  Bulk processing dictionary API
 **********************************/
typedef struct ZSTD_CDict_s ZSTD_CDict;


ZSTDLIB_API ZSTD_CDict* ZSTD_createCDict(const void* dictBuffer, size_t dictSize,
                                         int compressionLevel);


ZSTDLIB_API size_t      ZSTD_freeCDict(ZSTD_CDict* CDict);


ZSTDLIB_API size_t ZSTD_compress_usingCDict(ZSTD_CCtx* cctx,
                                            void* dst, size_t dstCapacity,
                                      const void* src, size_t srcSize,
                                      const ZSTD_CDict* cdict);


typedef struct ZSTD_DDict_s ZSTD_DDict;


ZSTDLIB_API ZSTD_DDict* ZSTD_createDDict(const void* dictBuffer, size_t dictSize);


ZSTDLIB_API ZSTD_DDict* ZSTD_createDDict_byReference(const void* dictBuffer, size_t dictSize);


ZSTDLIB_API size_t      ZSTD_freeDDict(ZSTD_DDict* ddict);


ZSTDLIB_API size_t ZSTD_decompress_usingDDict(ZSTD_DCtx* dctx,
                                              void* dst, size_t dstCapacity,
                                        const void* src, size_t srcSize,
                                        const ZSTD_DDict* ddict);


/********************************
 *  Dictionary helper functions
 *******************************/


ZSTDLIB_API unsigned ZSTD_getDictID_fromDict(const void* dict, size_t dictSize);


ZSTDLIB_API unsigned ZSTD_getDictID_fromCDict(const ZSTD_CDict* cdict);


ZSTDLIB_API unsigned ZSTD_getDictID_fromDDict(const ZSTD_DDict* ddict);


ZSTDLIB_API unsigned ZSTD_getDictID_fromFrame(const void* src, size_t srcSize);


/*******************************************************************************
 * Advanced dictionary and prefix API (Requires v1.4.0+)
 *
 * This API allows dictionaries to be used with ZSTD_compress2(),
 * ZSTD_compressStream2(), and ZSTD_decompressDCtx().
 * Dictionaries are sticky, they remain valid when same context is reused,
 * they only reset when the context is reset
 * with ZSTD_reset_parameters or ZSTD_reset_session_and_parameters.
 * In contrast, Prefixes are single-use.
 ******************************************************************************/



ZSTDLIB_API size_t ZSTD_CCtx_loadDictionary(ZSTD_CCtx* cctx, const void* dict, size_t dictSize);

typedef enum {
    ZSTD_dct_auto = 0,       /**< dictionary is "full" when starting with ZSTD_MAGIC_DICTIONARY, otherwise it is "rawContent" */
    ZSTD_dct_rawContent = 1, /**< ensures dictionary is always loaded as rawContent, even if it starts with ZSTD_MAGIC_DICTIONARY */
    ZSTD_dct_fullDict = 2    /**< refuses to load a dictionary if it does not respect Zstandard's specification, starting with ZSTD_MAGIC_DICTIONARY */
} ZSTD_dictContentType_e;

typedef enum {
    ZSTD_dlm_byCopy = 0,  /**< Copy dictionary content internally */
    ZSTD_dlm_byRef = 1    /**< Reference dictionary content -- the dictionary buffer must outlive its users. */
} ZSTD_dictLoadMethod_e;


ZSTDLIB_API size_t ZSTD_CCtx_loadDictionary_advanced(ZSTD_CCtx* cctx, const void* dict, size_t dictSize, ZSTD_dictLoadMethod_e dictLoadMethod, ZSTD_dictContentType_e dictContentType);


ZSTDLIB_API size_t ZSTD_CCtx_refCDict(ZSTD_CCtx* cctx, const ZSTD_CDict* cdict);


ZSTDLIB_API size_t ZSTD_CCtx_refPrefix(ZSTD_CCtx* cctx,
                                 const void* prefix, size_t prefixSize);


ZSTDLIB_API size_t ZSTD_DCtx_loadDictionary(ZSTD_DCtx* dctx, const void* dict, size_t dictSize);


ZSTDLIB_API size_t ZSTD_DCtx_loadDictionary_advanced(ZSTD_DCtx* dctx, const void* dict, size_t dictSize, ZSTD_dictLoadMethod_e dictLoadMethod, ZSTD_dictContentType_e dictContentType);


ZSTDLIB_API size_t ZSTD_DCtx_refDDict(ZSTD_DCtx* dctx, const ZSTD_DDict* ddict);


ZSTDLIB_API size_t ZSTD_DCtx_refPrefix(ZSTD_DCtx* dctx,
                                 const void* prefix, size_t prefixSize);




ZSTDLIB_API size_t ZSTD_sizeof_CCtx(const ZSTD_CCtx* cctx);
ZSTDLIB_API size_t ZSTD_sizeof_DCtx(const ZSTD_DCtx* dctx);
ZSTDLIB_API size_t ZSTD_sizeof_CStream(const ZSTD_CStream* zcs);
ZSTDLIB_API size_t ZSTD_sizeof_DStream(const ZSTD_DStream* zds);
ZSTDLIB_API size_t ZSTD_sizeof_CDict(const ZSTD_CDict* cdict);
ZSTDLIB_API size_t ZSTD_sizeof_DDict(const ZSTD_DDict* ddict);

#if defined (__cplusplus)
}
#endif

#endif  /* ZSTD_H_235446 */




#if defined(ZSTD_STATIC_LINKING_ONLY) && !defined(ZSTD_H_ZSTD_STATIC_LINKING_ONLY)
#define ZSTD_H_ZSTD_STATIC_LINKING_ONLY

#if defined (__cplusplus)
extern "C" {
#endif


#ifndef ZSTDLIB_STATIC_API
#  if defined(ZSTD_DLL_EXPORT) && (ZSTD_DLL_EXPORT==1)
#    define ZSTDLIB_STATIC_API __declspec(dllexport) ZSTDLIB_VISIBLE
#  elif defined(ZSTD_DLL_IMPORT) && (ZSTD_DLL_IMPORT==1)
#    define ZSTDLIB_STATIC_API __declspec(dllimport) ZSTDLIB_VISIBLE
#  else
#    define ZSTDLIB_STATIC_API ZSTDLIB_VISIBLE
#  endif
#endif

/****************************************************************************************
 *   experimental API (static linking only)
 ****************************************************************************************
 * The following symbols and constants
 * are not planned to join "stable API" status in the near future.
 * They can still change in future versions.
 * Some of them are planned to remain in the static_only section indefinitely.
 * Some of them might be removed in the future (especially when redundant with existing stable functions)
 * ***************************************************************************************/

#define ZSTD_FRAMEHEADERSIZE_PREFIX(format) ((format) == ZSTD_f_zstd1 ? 5 : 1)   /* minimum input size required to query frame header size */
#define ZSTD_FRAMEHEADERSIZE_MIN(format)    ((format) == ZSTD_f_zstd1 ? 6 : 2)
#define ZSTD_FRAMEHEADERSIZE_MAX   18   /* can be useful for static allocation */
#define ZSTD_SKIPPABLEHEADERSIZE    8


#define ZSTD_WINDOWLOG_MAX_32    30
#define ZSTD_WINDOWLOG_MAX_64    31
#define ZSTD_WINDOWLOG_MAX     ((int)(sizeof(size_t) == 4 ? ZSTD_WINDOWLOG_MAX_32 : ZSTD_WINDOWLOG_MAX_64))
#define ZSTD_WINDOWLOG_MIN       10
#define ZSTD_HASHLOG_MAX       ((ZSTD_WINDOWLOG_MAX < 30) ? ZSTD_WINDOWLOG_MAX : 30)
#define ZSTD_HASHLOG_MIN          6
#define ZSTD_CHAINLOG_MAX_32     29
#define ZSTD_CHAINLOG_MAX_64     30
#define ZSTD_CHAINLOG_MAX      ((int)(sizeof(size_t) == 4 ? ZSTD_CHAINLOG_MAX_32 : ZSTD_CHAINLOG_MAX_64))
#define ZSTD_CHAINLOG_MIN        ZSTD_HASHLOG_MIN
#define ZSTD_SEARCHLOG_MAX      (ZSTD_WINDOWLOG_MAX-1)
#define ZSTD_SEARCHLOG_MIN        1
#define ZSTD_MINMATCH_MAX         7   /* only for ZSTD_fast, other strategies are limited to 6 */
#define ZSTD_MINMATCH_MIN         3   /* only for ZSTD_btopt+, faster strategies are limited to 4 */
#define ZSTD_TARGETLENGTH_MAX    ZSTD_BLOCKSIZE_MAX
#define ZSTD_TARGETLENGTH_MIN     0   /* note : comparing this constant to an unsigned results in a tautological test */
#define ZSTD_STRATEGY_MIN        ZSTD_fast
#define ZSTD_STRATEGY_MAX        ZSTD_btultra2
#define ZSTD_BLOCKSIZE_MAX_MIN (1 << 10) /* The minimum valid max blocksize. Maximum blocksizes smaller than this make compressBound() inaccurate. */


#define ZSTD_OVERLAPLOG_MIN       0
#define ZSTD_OVERLAPLOG_MAX       9

#define ZSTD_WINDOWLOG_LIMIT_DEFAULT 27   /* by default, the streaming decoder will refuse any frame
                                           * requiring larger than (1<<ZSTD_WINDOWLOG_LIMIT_DEFAULT) window size,
                                           * to preserve host's memory from unreasonable requirements.
                                           * This limit can be overridden using ZSTD_DCtx_setParameter(,ZSTD_d_windowLogMax,).
                                           * The limit does not apply for one-pass decoders (such as ZSTD_decompress()), since no additional memory is allocated */



#define ZSTD_LDM_HASHLOG_MIN      ZSTD_HASHLOG_MIN
#define ZSTD_LDM_HASHLOG_MAX      ZSTD_HASHLOG_MAX
#define ZSTD_LDM_MINMATCH_MIN        4
#define ZSTD_LDM_MINMATCH_MAX     4096
#define ZSTD_LDM_BUCKETSIZELOG_MIN   1
#define ZSTD_LDM_BUCKETSIZELOG_MAX   8
#define ZSTD_LDM_HASHRATELOG_MIN     0
#define ZSTD_LDM_HASHRATELOG_MAX (ZSTD_WINDOWLOG_MAX - ZSTD_HASHLOG_MIN)


#define ZSTD_TARGETCBLOCKSIZE_MIN   1340 /* suitable to fit into an ethernet / wifi / 4G transport frame */
#define ZSTD_TARGETCBLOCKSIZE_MAX   ZSTD_BLOCKSIZE_MAX
#define ZSTD_SRCSIZEHINT_MIN        0
#define ZSTD_SRCSIZEHINT_MAX        INT_MAX




typedef struct ZSTD_CCtx_params_s ZSTD_CCtx_params;

typedef struct {
    unsigned int offset;      /* The offset of the match. (NOT the same as the offset code)
                               * If offset == 0 and matchLength == 0, this sequence represents the last
                               * literals in the block of litLength size.
                               */

    unsigned int litLength;   /* Literal length of the sequence. */
    unsigned int matchLength; /* Match length of the sequence. */



    unsigned int rep;         /* Represents which repeat offset is represented by the field 'offset'.
                               * Ranges from [0, 3].
                               *
                               * Repeat offsets are essentially previous offsets from previous sequences sorted in
                               * recency order. For more detail, see doc/zstd_compression_format.md
                               *
                               * If rep == 0, then 'offset' does not contain a repeat offset.
                               * If rep > 0:
                               *  If litLength != 0:
                               *      rep == 1 --> offset == repeat_offset_1
                               *      rep == 2 --> offset == repeat_offset_2
                               *      rep == 3 --> offset == repeat_offset_3
                               *  If litLength == 0:
                               *      rep == 1 --> offset == repeat_offset_2
                               *      rep == 2 --> offset == repeat_offset_3
                               *      rep == 3 --> offset == repeat_offset_1 - 1
                               *
                               * Note: This field is optional. ZSTD_generateSequences() will calculate the value of
                               * 'rep', but repeat offsets do not necessarily need to be calculated from an external
                               * sequence provider perspective. For example, ZSTD_compressSequences() does not
                               * use this 'rep' field at all (as of now).
                               */
} ZSTD_Sequence;

typedef struct {
    unsigned windowLog;       /**< largest match distance : larger == more compression, more memory needed during decompression */
    unsigned chainLog;        /**< fully searched segment : larger == more compression, slower, more memory (useless for fast) */
    unsigned hashLog;         /**< dispatch table : larger == faster, more memory */
    unsigned searchLog;       /**< nb of searches : larger == more compression, slower */
    unsigned minMatch;        /**< match length searched : larger == faster decompression, sometimes less compression */
    unsigned targetLength;    /**< acceptable match size for optimal parser (only) : larger == more compression, slower */
    ZSTD_strategy strategy;   /**< see ZSTD_strategy definition above */
} ZSTD_compressionParameters;

typedef struct {
    int contentSizeFlag; /**< 1: content size will be in frame header (when known) */
    int checksumFlag;    /**< 1: generate a 32-bits checksum using XXH64 algorithm at end of frame, for error detection */
    int noDictIDFlag;    /**< 1: no dictID will be saved into frame header (dictID is only useful for dictionary compression) */
} ZSTD_frameParameters;

typedef struct {
    ZSTD_compressionParameters cParams;
    ZSTD_frameParameters fParams;
} ZSTD_parameters;

typedef enum {
    ZSTD_f_zstd1 = 0,           /* zstd frame format, specified in zstd_compression_format.md (default) */
    ZSTD_f_zstd1_magicless = 1  /* Variant of zstd frame format, without initial 4-bytes magic number.
                                 * Useful to save 4 bytes per generated frame.
                                 * Decoder cannot recognise automatically this format, requiring this instruction. */
} ZSTD_format_e;

typedef enum {

    ZSTD_d_validateChecksum = 0,
    ZSTD_d_ignoreChecksum = 1
} ZSTD_forceIgnoreChecksum_e;

typedef enum {

    ZSTD_rmd_refSingleDDict = 0,
    ZSTD_rmd_refMultipleDDicts = 1
} ZSTD_refMultipleDDicts_e;

typedef enum {

    ZSTD_dictDefaultAttach = 0, /* Use the default heuristic. */
    ZSTD_dictForceAttach   = 1, /* Never copy the dictionary. */
    ZSTD_dictForceCopy     = 2, /* Always copy the dictionary. */
    ZSTD_dictForceLoad     = 3  /* Always reload the dictionary */
} ZSTD_dictAttachPref_e;

typedef enum {
  ZSTD_lcm_auto = 0,          /**< Automatically determine the compression mode based on the compression level.
                               *   Negative compression levels will be uncompressed, and positive compression
                               *   levels will be compressed. */
  ZSTD_lcm_huffman = 1,       /**< Always attempt Huffman compression. Uncompressed literals will still be
                               *   emitted if Huffman compression is not profitable. */
  ZSTD_lcm_uncompressed = 2   /**< Always emit uncompressed literals. */
} ZSTD_literalCompressionMode_e;

typedef enum {

  ZSTD_ps_auto = 0,         /* Let the library automatically determine whether the feature shall be enabled */
  ZSTD_ps_enable = 1,       /* Force-enable the feature */
  ZSTD_ps_disable = 2       /* Do not use the feature */
} ZSTD_ParamSwitch_e;
#define ZSTD_paramSwitch_e ZSTD_ParamSwitch_e  /* old name */

/***************************************
*  Frame header and size functions
***************************************/


ZSTDLIB_STATIC_API unsigned long long ZSTD_findDecompressedSize(const void* src, size_t srcSize);


ZSTDLIB_STATIC_API unsigned long long ZSTD_decompressBound(const void* src, size_t srcSize);


ZSTDLIB_STATIC_API size_t ZSTD_frameHeaderSize(const void* src, size_t srcSize);


ZSTDLIB_STATIC_API size_t ZSTD_getFrameHeader_advanced(ZSTD_FrameHeader* zfhPtr, const void* src, size_t srcSize, ZSTD_format_e format);


ZSTDLIB_STATIC_API size_t ZSTD_decompressionMargin(const void* src, size_t srcSize);


#define ZSTD_DECOMPRESSION_MARGIN(originalSize, blockSize) ((size_t)(                                              \
        ZSTD_FRAMEHEADERSIZE_MAX                                                              /* Frame header */ + \
        4                                                                                         /* checksum */ + \
        ((originalSize) == 0 ? 0 : 3 * (((originalSize) + (blockSize) - 1) / blockSize)) /* 3 bytes per block */ + \
        (blockSize)                                                                    /* One block of margin */   \
    ))

typedef enum {
  ZSTD_sf_noBlockDelimiters = 0,         /* ZSTD_Sequence[] has no block delimiters, just sequences */
  ZSTD_sf_explicitBlockDelimiters = 1    /* ZSTD_Sequence[] contains explicit block delimiters */
} ZSTD_SequenceFormat_e;
#define ZSTD_sequenceFormat_e ZSTD_SequenceFormat_e /* old name */


ZSTDLIB_STATIC_API size_t ZSTD_sequenceBound(size_t srcSize);


ZSTD_DEPRECATED("For debugging only, will be replaced by ZSTD_extractSequences()")
ZSTDLIB_STATIC_API size_t
ZSTD_generateSequences(ZSTD_CCtx* zc,
                       ZSTD_Sequence* outSeqs, size_t outSeqsCapacity,
                       const void* src, size_t srcSize);


ZSTDLIB_STATIC_API size_t ZSTD_mergeBlockDelimiters(ZSTD_Sequence* sequences, size_t seqsSize);


ZSTDLIB_STATIC_API size_t
ZSTD_compressSequences(ZSTD_CCtx* cctx,
                       void* dst, size_t dstCapacity,
                 const ZSTD_Sequence* inSeqs, size_t inSeqsSize,
                 const void* src, size_t srcSize);



ZSTDLIB_STATIC_API size_t
ZSTD_compressSequencesAndLiterals(ZSTD_CCtx* cctx,
                                  void* dst, size_t dstCapacity,
                            const ZSTD_Sequence* inSeqs, size_t nbSequences,
                            const void* literals, size_t litSize, size_t litBufCapacity,
                            size_t decompressedSize);



ZSTDLIB_STATIC_API size_t ZSTD_writeSkippableFrame(void* dst, size_t dstCapacity,
                                             const void* src, size_t srcSize,
                                                   unsigned magicVariant);


ZSTDLIB_STATIC_API size_t ZSTD_readSkippableFrame(void* dst, size_t dstCapacity,
                                                  unsigned* magicVariant,
                                                  const void* src, size_t srcSize);


ZSTDLIB_STATIC_API unsigned ZSTD_isSkippableFrame(const void* buffer, size_t size);



/***************************************
*  Memory management
***************************************/


ZSTDLIB_STATIC_API size_t ZSTD_estimateCCtxSize(int maxCompressionLevel);
ZSTDLIB_STATIC_API size_t ZSTD_estimateCCtxSize_usingCParams(ZSTD_compressionParameters cParams);
ZSTDLIB_STATIC_API size_t ZSTD_estimateCCtxSize_usingCCtxParams(const ZSTD_CCtx_params* params);
ZSTDLIB_STATIC_API size_t ZSTD_estimateDCtxSize(void);


ZSTDLIB_STATIC_API size_t ZSTD_estimateCStreamSize(int maxCompressionLevel);
ZSTDLIB_STATIC_API size_t ZSTD_estimateCStreamSize_usingCParams(ZSTD_compressionParameters cParams);
ZSTDLIB_STATIC_API size_t ZSTD_estimateCStreamSize_usingCCtxParams(const ZSTD_CCtx_params* params);
ZSTDLIB_STATIC_API size_t ZSTD_estimateDStreamSize(size_t maxWindowSize);
ZSTDLIB_STATIC_API size_t ZSTD_estimateDStreamSize_fromFrame(const void* src, size_t srcSize);


ZSTDLIB_STATIC_API size_t ZSTD_estimateCDictSize(size_t dictSize, int compressionLevel);
ZSTDLIB_STATIC_API size_t ZSTD_estimateCDictSize_advanced(size_t dictSize, ZSTD_compressionParameters cParams, ZSTD_dictLoadMethod_e dictLoadMethod);
ZSTDLIB_STATIC_API size_t ZSTD_estimateDDictSize(size_t dictSize, ZSTD_dictLoadMethod_e dictLoadMethod);


ZSTDLIB_STATIC_API ZSTD_CCtx*    ZSTD_initStaticCCtx(void* workspace, size_t workspaceSize);
ZSTDLIB_STATIC_API ZSTD_CStream* ZSTD_initStaticCStream(void* workspace, size_t workspaceSize);    /**< same as ZSTD_initStaticCCtx() */

ZSTDLIB_STATIC_API ZSTD_DCtx*    ZSTD_initStaticDCtx(void* workspace, size_t workspaceSize);
ZSTDLIB_STATIC_API ZSTD_DStream* ZSTD_initStaticDStream(void* workspace, size_t workspaceSize);    /**< same as ZSTD_initStaticDCtx() */

ZSTDLIB_STATIC_API const ZSTD_CDict* ZSTD_initStaticCDict(
                                        void* workspace, size_t workspaceSize,
                                        const void* dict, size_t dictSize,
                                        ZSTD_dictLoadMethod_e dictLoadMethod,
                                        ZSTD_dictContentType_e dictContentType,
                                        ZSTD_compressionParameters cParams);

ZSTDLIB_STATIC_API const ZSTD_DDict* ZSTD_initStaticDDict(
                                        void* workspace, size_t workspaceSize,
                                        const void* dict, size_t dictSize,
                                        ZSTD_dictLoadMethod_e dictLoadMethod,
                                        ZSTD_dictContentType_e dictContentType);



typedef void* (*ZSTD_allocFunction) (void* opaque, size_t size);
typedef void  (*ZSTD_freeFunction) (void* opaque, void* address);
typedef struct { ZSTD_allocFunction customAlloc; ZSTD_freeFunction customFree; void* opaque; } ZSTD_customMem;
#if defined(__clang__) && __clang_major__ >= 5
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wzero-as-null-pointer-constant"
#endif
static
#ifdef __GNUC__
__attribute__((__unused__))
#endif
ZSTD_customMem const ZSTD_defaultCMem = { NULL, NULL, NULL };  /**< this constant defers to stdlib's functions */
#if defined(__clang__) && __clang_major__ >= 5
#pragma clang diagnostic pop
#endif

ZSTDLIB_STATIC_API ZSTD_CCtx*    ZSTD_createCCtx_advanced(ZSTD_customMem customMem);
ZSTDLIB_STATIC_API ZSTD_CStream* ZSTD_createCStream_advanced(ZSTD_customMem customMem);
ZSTDLIB_STATIC_API ZSTD_DCtx*    ZSTD_createDCtx_advanced(ZSTD_customMem customMem);
ZSTDLIB_STATIC_API ZSTD_DStream* ZSTD_createDStream_advanced(ZSTD_customMem customMem);

ZSTDLIB_STATIC_API ZSTD_CDict* ZSTD_createCDict_advanced(const void* dict, size_t dictSize,
                                                  ZSTD_dictLoadMethod_e dictLoadMethod,
                                                  ZSTD_dictContentType_e dictContentType,
                                                  ZSTD_compressionParameters cParams,
                                                  ZSTD_customMem customMem);


typedef struct POOL_ctx_s ZSTD_threadPool;
ZSTDLIB_STATIC_API ZSTD_threadPool* ZSTD_createThreadPool(size_t numThreads);
ZSTDLIB_STATIC_API void ZSTD_freeThreadPool (ZSTD_threadPool* pool);  /* accept NULL pointer */
ZSTDLIB_STATIC_API size_t ZSTD_CCtx_refThreadPool(ZSTD_CCtx* cctx, ZSTD_threadPool* pool);



ZSTDLIB_STATIC_API ZSTD_CDict* ZSTD_createCDict_advanced2(
    const void* dict, size_t dictSize,
    ZSTD_dictLoadMethod_e dictLoadMethod,
    ZSTD_dictContentType_e dictContentType,
    const ZSTD_CCtx_params* cctxParams,
    ZSTD_customMem customMem);

ZSTDLIB_STATIC_API ZSTD_DDict* ZSTD_createDDict_advanced(
    const void* dict, size_t dictSize,
    ZSTD_dictLoadMethod_e dictLoadMethod,
    ZSTD_dictContentType_e dictContentType,
    ZSTD_customMem customMem);


/***************************************
*  Advanced compression functions
***************************************/


ZSTDLIB_STATIC_API ZSTD_CDict* ZSTD_createCDict_byReference(const void* dictBuffer, size_t dictSize, int compressionLevel);


ZSTDLIB_STATIC_API ZSTD_compressionParameters ZSTD_getCParams(int compressionLevel, unsigned long long estimatedSrcSize, size_t dictSize);


ZSTDLIB_STATIC_API ZSTD_parameters ZSTD_getParams(int compressionLevel, unsigned long long estimatedSrcSize, size_t dictSize);


ZSTDLIB_STATIC_API size_t ZSTD_checkCParams(ZSTD_compressionParameters params);


ZSTDLIB_STATIC_API ZSTD_compressionParameters ZSTD_adjustCParams(ZSTD_compressionParameters cPar, unsigned long long srcSize, size_t dictSize);


ZSTDLIB_STATIC_API size_t ZSTD_CCtx_setCParams(ZSTD_CCtx* cctx, ZSTD_compressionParameters cparams);


ZSTDLIB_STATIC_API size_t ZSTD_CCtx_setFParams(ZSTD_CCtx* cctx, ZSTD_frameParameters fparams);


ZSTDLIB_STATIC_API size_t ZSTD_CCtx_setParams(ZSTD_CCtx* cctx, ZSTD_parameters params);


ZSTD_DEPRECATED("use ZSTD_compress2")
ZSTDLIB_STATIC_API
size_t ZSTD_compress_advanced(ZSTD_CCtx* cctx,
                              void* dst, size_t dstCapacity,
                        const void* src, size_t srcSize,
                        const void* dict,size_t dictSize,
                              ZSTD_parameters params);


ZSTD_DEPRECATED("use ZSTD_compress2 with ZSTD_CCtx_loadDictionary")
ZSTDLIB_STATIC_API
size_t ZSTD_compress_usingCDict_advanced(ZSTD_CCtx* cctx,
                                              void* dst, size_t dstCapacity,
                                        const void* src, size_t srcSize,
                                        const ZSTD_CDict* cdict,
                                              ZSTD_frameParameters fParams);



ZSTDLIB_STATIC_API size_t ZSTD_CCtx_loadDictionary_byReference(ZSTD_CCtx* cctx, const void* dict, size_t dictSize);


ZSTDLIB_STATIC_API size_t ZSTD_CCtx_refPrefix_advanced(ZSTD_CCtx* cctx, const void* prefix, size_t prefixSize, ZSTD_dictContentType_e dictContentType);





 #define ZSTD_c_rsyncable ZSTD_c_experimentalParam1


#define ZSTD_c_format ZSTD_c_experimentalParam2


#define ZSTD_c_forceMaxWindow ZSTD_c_experimentalParam3


#define ZSTD_c_forceAttachDict ZSTD_c_experimentalParam4


#define ZSTD_c_literalCompressionMode ZSTD_c_experimentalParam5


#define ZSTD_c_srcSizeHint ZSTD_c_experimentalParam7


#define ZSTD_c_enableDedicatedDictSearch ZSTD_c_experimentalParam8


#define ZSTD_c_stableInBuffer ZSTD_c_experimentalParam9


#define ZSTD_c_stableOutBuffer ZSTD_c_experimentalParam10


#define ZSTD_c_blockDelimiters ZSTD_c_experimentalParam11


#define ZSTD_c_validateSequences ZSTD_c_experimentalParam12


#define ZSTD_BLOCKSPLITTER_LEVEL_MAX 6
#define ZSTD_c_blockSplitterLevel ZSTD_c_experimentalParam20


#define ZSTD_c_splitAfterSequences ZSTD_c_experimentalParam13


#define ZSTD_c_useRowMatchFinder ZSTD_c_experimentalParam14


#define ZSTD_c_deterministicRefPrefix ZSTD_c_experimentalParam15


#define ZSTD_c_prefetchCDictTables ZSTD_c_experimentalParam16


#define ZSTD_c_enableSeqProducerFallback ZSTD_c_experimentalParam17


#define ZSTD_c_maxBlockSize ZSTD_c_experimentalParam18


#define ZSTD_c_repcodeResolution ZSTD_c_experimentalParam19
#define ZSTD_c_searchForExternalRepcodes ZSTD_c_experimentalParam19 /* older name */



ZSTDLIB_STATIC_API size_t ZSTD_CCtx_getParameter(const ZSTD_CCtx* cctx, ZSTD_cParameter param, int* value);



ZSTDLIB_STATIC_API ZSTD_CCtx_params* ZSTD_createCCtxParams(void);
ZSTDLIB_STATIC_API size_t ZSTD_freeCCtxParams(ZSTD_CCtx_params* params);  /* accept NULL pointer */


ZSTDLIB_STATIC_API size_t ZSTD_CCtxParams_reset(ZSTD_CCtx_params* params);


ZSTDLIB_STATIC_API size_t ZSTD_CCtxParams_init(ZSTD_CCtx_params* cctxParams, int compressionLevel);


ZSTDLIB_STATIC_API size_t ZSTD_CCtxParams_init_advanced(ZSTD_CCtx_params* cctxParams, ZSTD_parameters params);


ZSTDLIB_STATIC_API size_t ZSTD_CCtxParams_setParameter(ZSTD_CCtx_params* params, ZSTD_cParameter param, int value);


ZSTDLIB_STATIC_API size_t ZSTD_CCtxParams_getParameter(const ZSTD_CCtx_params* params, ZSTD_cParameter param, int* value);


ZSTDLIB_STATIC_API size_t ZSTD_CCtx_setParametersUsingCCtxParams(
        ZSTD_CCtx* cctx, const ZSTD_CCtx_params* params);


ZSTDLIB_STATIC_API size_t ZSTD_compressStream2_simpleArgs (
                            ZSTD_CCtx* cctx,
                            void* dst, size_t dstCapacity, size_t* dstPos,
                      const void* src, size_t srcSize, size_t* srcPos,
                            ZSTD_EndDirective endOp);


/***************************************
*  Advanced decompression functions
***************************************/


ZSTDLIB_STATIC_API unsigned ZSTD_isFrame(const void* buffer, size_t size);


ZSTDLIB_STATIC_API size_t ZSTD_DCtx_loadDictionary_byReference(ZSTD_DCtx* dctx, const void* dict, size_t dictSize);


ZSTDLIB_STATIC_API size_t ZSTD_DCtx_refPrefix_advanced(ZSTD_DCtx* dctx, const void* prefix, size_t prefixSize, ZSTD_dictContentType_e dictContentType);


ZSTDLIB_STATIC_API size_t ZSTD_DCtx_setMaxWindowSize(ZSTD_DCtx* dctx, size_t maxWindowSize);


ZSTDLIB_STATIC_API size_t ZSTD_DCtx_getParameter(ZSTD_DCtx* dctx, ZSTD_dParameter param, int* value);


#define ZSTD_d_format ZSTD_d_experimentalParam1

#define ZSTD_d_stableOutBuffer ZSTD_d_experimentalParam2


#define ZSTD_d_forceIgnoreChecksum ZSTD_d_experimentalParam3


#define ZSTD_d_refMultipleDDicts ZSTD_d_experimentalParam4


#define ZSTD_d_disableHuffmanAssembly ZSTD_d_experimentalParam5


#define ZSTD_d_maxBlockSize ZSTD_d_experimentalParam6



ZSTD_DEPRECATED("use ZSTD_DCtx_setParameter() instead")
ZSTDLIB_STATIC_API
size_t ZSTD_DCtx_setFormat(ZSTD_DCtx* dctx, ZSTD_format_e format);


ZSTDLIB_STATIC_API size_t ZSTD_decompressStream_simpleArgs (
                            ZSTD_DCtx* dctx,
                            void* dst, size_t dstCapacity, size_t* dstPos,
                      const void* src, size_t srcSize, size_t* srcPos);


/********************************************************************
*  Advanced streaming functions
*  Warning : most of these functions are now redundant with the Advanced API.
*  Once Advanced API reaches "stable" status,
*  redundant functions will be deprecated, and then at some point removed.
********************************************************************/




ZSTD_DEPRECATED("use ZSTD_CCtx_reset, see zstd.h for detailed instructions")
ZSTDLIB_STATIC_API
size_t ZSTD_initCStream_srcSize(ZSTD_CStream* zcs,
                         int compressionLevel,
                         unsigned long long pledgedSrcSize);


ZSTD_DEPRECATED("use ZSTD_CCtx_reset, see zstd.h for detailed instructions")
ZSTDLIB_STATIC_API
size_t ZSTD_initCStream_usingDict(ZSTD_CStream* zcs,
                     const void* dict, size_t dictSize,
                           int compressionLevel);


ZSTD_DEPRECATED("use ZSTD_CCtx_reset, see zstd.h for detailed instructions")
ZSTDLIB_STATIC_API
size_t ZSTD_initCStream_advanced(ZSTD_CStream* zcs,
                    const void* dict, size_t dictSize,
                          ZSTD_parameters params,
                          unsigned long long pledgedSrcSize);


ZSTD_DEPRECATED("use ZSTD_CCtx_reset and ZSTD_CCtx_refCDict, see zstd.h for detailed instructions")
ZSTDLIB_STATIC_API
size_t ZSTD_initCStream_usingCDict(ZSTD_CStream* zcs, const ZSTD_CDict* cdict);


ZSTD_DEPRECATED("use ZSTD_CCtx_reset and ZSTD_CCtx_refCDict, see zstd.h for detailed instructions")
ZSTDLIB_STATIC_API
size_t ZSTD_initCStream_usingCDict_advanced(ZSTD_CStream* zcs,
                               const ZSTD_CDict* cdict,
                                     ZSTD_frameParameters fParams,
                                     unsigned long long pledgedSrcSize);


ZSTD_DEPRECATED("use ZSTD_CCtx_reset, see zstd.h for detailed instructions")
ZSTDLIB_STATIC_API
size_t ZSTD_resetCStream(ZSTD_CStream* zcs, unsigned long long pledgedSrcSize);


typedef struct {
    unsigned long long ingested;   /* nb input bytes read and buffered */
    unsigned long long consumed;   /* nb input bytes actually compressed */
    unsigned long long produced;   /* nb of compressed bytes generated and buffered */
    unsigned long long flushed;    /* nb of compressed bytes flushed : not provided; can be tracked from caller side */
    unsigned currentJobID;         /* MT only : latest started job nb */
    unsigned nbActiveWorkers;      /* MT only : nb of workers actively compressing at probe time */
} ZSTD_frameProgression;


ZSTDLIB_STATIC_API ZSTD_frameProgression ZSTD_getFrameProgression(const ZSTD_CCtx* cctx);


ZSTDLIB_STATIC_API size_t ZSTD_toFlushNow(ZSTD_CCtx* cctx);





ZSTD_DEPRECATED("use ZSTD_DCtx_reset + ZSTD_DCtx_loadDictionary, see zstd.h for detailed instructions")
ZSTDLIB_STATIC_API size_t ZSTD_initDStream_usingDict(ZSTD_DStream* zds, const void* dict, size_t dictSize);


ZSTD_DEPRECATED("use ZSTD_DCtx_reset + ZSTD_DCtx_refDDict, see zstd.h for detailed instructions")
ZSTDLIB_STATIC_API size_t ZSTD_initDStream_usingDDict(ZSTD_DStream* zds, const ZSTD_DDict* ddict);


ZSTD_DEPRECATED("use ZSTD_DCtx_reset, see zstd.h for detailed instructions")
ZSTDLIB_STATIC_API size_t ZSTD_resetDStream(ZSTD_DStream* zds);




#define ZSTD_SEQUENCE_PRODUCER_ERROR ((size_t)(-1))

typedef size_t (*ZSTD_sequenceProducer_F) (
  void* sequenceProducerState,
  ZSTD_Sequence* outSeqs, size_t outSeqsCapacity,
  const void* src, size_t srcSize,
  const void* dict, size_t dictSize,
  int compressionLevel,
  size_t windowSize
);


ZSTDLIB_STATIC_API void
ZSTD_registerSequenceProducer(
  ZSTD_CCtx* cctx,
  void* sequenceProducerState,
  ZSTD_sequenceProducer_F sequenceProducer
);


ZSTDLIB_STATIC_API void
ZSTD_CCtxParams_registerSequenceProducer(
  ZSTD_CCtx_params* params,
  void* sequenceProducerState,
  ZSTD_sequenceProducer_F sequenceProducer
);


/*********************************************************************
*  Buffer-less and synchronous inner streaming functions (DEPRECATED)
*
*  This API is deprecated, and will be removed in a future version.
*  It allows streaming (de)compression with user allocated buffers.
*  However, it is hard to use, and not as well tested as the rest of
*  our API.
*
*  Please use the normal streaming API instead: ZSTD_compressStream2,
*  and ZSTD_decompressStream.
*  If there is functionality that you need, but it doesn't provide,
*  please open an issue on our GitHub.
********************************************************************* */




ZSTD_DEPRECATED("The buffer-less API is deprecated in favor of the normal streaming API. See docs.")
ZSTDLIB_STATIC_API size_t ZSTD_compressBegin(ZSTD_CCtx* cctx, int compressionLevel);
ZSTD_DEPRECATED("The buffer-less API is deprecated in favor of the normal streaming API. See docs.")
ZSTDLIB_STATIC_API size_t ZSTD_compressBegin_usingDict(ZSTD_CCtx* cctx, const void* dict, size_t dictSize, int compressionLevel);
ZSTD_DEPRECATED("The buffer-less API is deprecated in favor of the normal streaming API. See docs.")
ZSTDLIB_STATIC_API size_t ZSTD_compressBegin_usingCDict(ZSTD_CCtx* cctx, const ZSTD_CDict* cdict); /**< note: fails if cdict==NULL */

ZSTD_DEPRECATED("The buffer-less API is deprecated in favor of the normal streaming API. See docs.")
ZSTDLIB_STATIC_API size_t ZSTD_compressContinue(ZSTD_CCtx* cctx, void* dst, size_t dstCapacity, const void* src, size_t srcSize);
ZSTD_DEPRECATED("The buffer-less API is deprecated in favor of the normal streaming API. See docs.")
ZSTDLIB_STATIC_API size_t ZSTD_compressEnd(ZSTD_CCtx* cctx, void* dst, size_t dstCapacity, const void* src, size_t srcSize);


ZSTD_DEPRECATED("use advanced API to access custom parameters")
ZSTDLIB_STATIC_API
size_t ZSTD_compressBegin_advanced(ZSTD_CCtx* cctx, const void* dict, size_t dictSize, ZSTD_parameters params, unsigned long long pledgedSrcSize); /**< pledgedSrcSize : If srcSize is not known at init time, use ZSTD_CONTENTSIZE_UNKNOWN */
ZSTD_DEPRECATED("use advanced API to access custom parameters")
ZSTDLIB_STATIC_API
size_t ZSTD_compressBegin_usingCDict_advanced(ZSTD_CCtx* const cctx, const ZSTD_CDict* const cdict, ZSTD_frameParameters const fParams, unsigned long long const pledgedSrcSize);   /* compression parameters are already set within cdict. pledgedSrcSize must be correct. If srcSize is not known, use macro ZSTD_CONTENTSIZE_UNKNOWN */




ZSTDLIB_STATIC_API size_t ZSTD_decodingBufferSize_min(unsigned long long windowSize, unsigned long long frameContentSize);  /**< when frame content size is not known, pass in frameContentSize == ZSTD_CONTENTSIZE_UNKNOWN */


ZSTDLIB_STATIC_API size_t ZSTD_decompressBegin(ZSTD_DCtx* dctx);
ZSTDLIB_STATIC_API size_t ZSTD_decompressBegin_usingDict(ZSTD_DCtx* dctx, const void* dict, size_t dictSize);
ZSTDLIB_STATIC_API size_t ZSTD_decompressBegin_usingDDict(ZSTD_DCtx* dctx, const ZSTD_DDict* ddict);

ZSTDLIB_STATIC_API size_t ZSTD_nextSrcSizeToDecompress(ZSTD_DCtx* dctx);


ZSTDLIB_STATIC_API size_t ZSTD_decompressContinue(ZSTD_DCtx* dctx, void* dst, size_t dstCapacity, const void* src, size_t srcSize);


typedef enum { ZSTDnit_frameHeader, ZSTDnit_blockHeader, ZSTDnit_block, ZSTDnit_lastBlock, ZSTDnit_checksum, ZSTDnit_skippableFrame } ZSTD_nextInputType_e;
ZSTDLIB_STATIC_API ZSTD_nextInputType_e ZSTD_nextInputType(ZSTD_DCtx* dctx);




ZSTDLIB_API int ZSTD_isDeterministicBuild(void);









ZSTD_DEPRECATED("The block API is deprecated in favor of the normal compression API. See docs.")
ZSTDLIB_STATIC_API size_t ZSTD_getBlockSize   (const ZSTD_CCtx* cctx);
ZSTD_DEPRECATED("The block API is deprecated in favor of the normal compression API. See docs.")
ZSTDLIB_STATIC_API size_t ZSTD_compressBlock  (ZSTD_CCtx* cctx, void* dst, size_t dstCapacity, const void* src, size_t srcSize);
ZSTD_DEPRECATED("The block API is deprecated in favor of the normal compression API. See docs.")
ZSTDLIB_STATIC_API size_t ZSTD_decompressBlock(ZSTD_DCtx* dctx, void* dst, size_t dstCapacity, const void* src, size_t srcSize);
ZSTD_DEPRECATED("The block API is deprecated in favor of the normal compression API. See docs.")
ZSTDLIB_STATIC_API size_t ZSTD_insertBlock    (ZSTD_DCtx* dctx, const void* blockStart, size_t blockSize);  /**< insert uncompressed block into `dctx` history. Useful for multi-blocks decompression. */

#if defined (__cplusplus)
}
#endif

#endif   /* ZSTD_H_ZSTD_STATIC_LINKING_ONLY */
/**** ended inlining ../zstd.h ****/
#define FSE_STATIC_LINKING_ONLY
/**** skipping file: fse.h ****/
/**** skipping file: huf.h ****/
#ifndef XXH_STATIC_LINKING_ONLY
#  define XXH_STATIC_LINKING_ONLY  /* XXH64_state_t */
#endif
/**** start inlining xxhash.h ****/
/*
 * xxHash - Extremely Fast Hash algorithm
 * Header File
 * Copyright (c) Yann Collet - Meta Platforms, Inc
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */




#ifndef XXH_NAMESPACE
# define XXH_NAMESPACE ZSTD_
#endif





#ifdef XXH_DOXYGEN

#  define XXH_STATIC_LINKING_ONLY



#  define XXH_IMPLEMENTATION



#  define XXH_INLINE_ALL
#  undef XXH_INLINE_ALL

#  define XXH_PRIVATE_API
#  undef XXH_PRIVATE_API

#  define XXH_NAMESPACE /* YOUR NAME HERE */
#  undef XXH_NAMESPACE
#endif

#if (defined(XXH_INLINE_ALL) || defined(XXH_PRIVATE_API)) \
    && !defined(XXH_INLINE_ALL_31684351384)

#  define XXH_INLINE_ALL_31684351384

#  undef XXH_STATIC_LINKING_ONLY   /* avoid macro redef */
#  define XXH_STATIC_LINKING_ONLY

#  undef XXH_PUBLIC_API
#  if defined(__GNUC__)
#    define XXH_PUBLIC_API static __inline __attribute__((unused))
#  elif defined (__cplusplus) || (defined (__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L) /* C99 */)
#    define XXH_PUBLIC_API static inline
#  elif defined(_MSC_VER)
#    define XXH_PUBLIC_API static __inline
#  else

#    define XXH_PUBLIC_API static
#  endif



#  undef XXH_versionNumber

#  undef XXH32
#  undef XXH32_createState
#  undef XXH32_freeState
#  undef XXH32_reset
#  undef XXH32_update
#  undef XXH32_digest
#  undef XXH32_copyState
#  undef XXH32_canonicalFromHash
#  undef XXH32_hashFromCanonical

#  undef XXH64
#  undef XXH64_createState
#  undef XXH64_freeState
#  undef XXH64_reset
#  undef XXH64_update
#  undef XXH64_digest
#  undef XXH64_copyState
#  undef XXH64_canonicalFromHash
#  undef XXH64_hashFromCanonical

#  undef XXH3_64bits
#  undef XXH3_64bits_withSecret
#  undef XXH3_64bits_withSeed
#  undef XXH3_64bits_withSecretandSeed
#  undef XXH3_createState
#  undef XXH3_freeState
#  undef XXH3_copyState
#  undef XXH3_64bits_reset
#  undef XXH3_64bits_reset_withSeed
#  undef XXH3_64bits_reset_withSecret
#  undef XXH3_64bits_update
#  undef XXH3_64bits_digest
#  undef XXH3_generateSecret

#  undef XXH128
#  undef XXH3_128bits
#  undef XXH3_128bits_withSeed
#  undef XXH3_128bits_withSecret
#  undef XXH3_128bits_reset
#  undef XXH3_128bits_reset_withSeed
#  undef XXH3_128bits_reset_withSecret
#  undef XXH3_128bits_reset_withSecretandSeed
#  undef XXH3_128bits_update
#  undef XXH3_128bits_digest
#  undef XXH128_isEqual
#  undef XXH128_cmp
#  undef XXH128_canonicalFromHash
#  undef XXH128_hashFromCanonical

#  undef XXH_NAMESPACE


#  define XXH_NAMESPACE XXH_INLINE_

#  define XXH_IPREF(Id)   XXH_NAMESPACE ## Id
#  define XXH_OK XXH_IPREF(XXH_OK)
#  define XXH_ERROR XXH_IPREF(XXH_ERROR)
#  define XXH_errorcode XXH_IPREF(XXH_errorcode)
#  define XXH32_canonical_t  XXH_IPREF(XXH32_canonical_t)
#  define XXH64_canonical_t  XXH_IPREF(XXH64_canonical_t)
#  define XXH128_canonical_t XXH_IPREF(XXH128_canonical_t)
#  define XXH32_state_s XXH_IPREF(XXH32_state_s)
#  define XXH32_state_t XXH_IPREF(XXH32_state_t)
#  define XXH64_state_s XXH_IPREF(XXH64_state_s)
#  define XXH64_state_t XXH_IPREF(XXH64_state_t)
#  define XXH3_state_s  XXH_IPREF(XXH3_state_s)
#  define XXH3_state_t  XXH_IPREF(XXH3_state_t)
#  define XXH128_hash_t XXH_IPREF(XXH128_hash_t)

#  undef XXHASH_H_5627135585666179
#  undef XXHASH_H_STATIC_13879238742
#endif /* XXH_INLINE_ALL || XXH_PRIVATE_API */


#ifndef XXHASH_H_5627135585666179
#define XXHASH_H_5627135585666179 1


#if !defined(XXH_INLINE_ALL) && !defined(XXH_PRIVATE_API)
#  if defined(WIN32) && defined(_MSC_VER) && (defined(XXH_IMPORT) || defined(XXH_EXPORT))
#    ifdef XXH_EXPORT
#      define XXH_PUBLIC_API __declspec(dllexport)
#    elif XXH_IMPORT
#      define XXH_PUBLIC_API __declspec(dllimport)
#    endif
#  else
#    define XXH_PUBLIC_API   /* do nothing */
#  endif
#endif

#ifdef XXH_NAMESPACE
#  define XXH_CAT(A,B) A##B
#  define XXH_NAME2(A,B) XXH_CAT(A,B)
#  define XXH_versionNumber XXH_NAME2(XXH_NAMESPACE, XXH_versionNumber)

#  define XXH32 XXH_NAME2(XXH_NAMESPACE, XXH32)
#  define XXH32_createState XXH_NAME2(XXH_NAMESPACE, XXH32_createState)
#  define XXH32_freeState XXH_NAME2(XXH_NAMESPACE, XXH32_freeState)
#  define XXH32_reset XXH_NAME2(XXH_NAMESPACE, XXH32_reset)
#  define XXH32_update XXH_NAME2(XXH_NAMESPACE, XXH32_update)
#  define XXH32_digest XXH_NAME2(XXH_NAMESPACE, XXH32_digest)
#  define XXH32_copyState XXH_NAME2(XXH_NAMESPACE, XXH32_copyState)
#  define XXH32_canonicalFromHash XXH_NAME2(XXH_NAMESPACE, XXH32_canonicalFromHash)
#  define XXH32_hashFromCanonical XXH_NAME2(XXH_NAMESPACE, XXH32_hashFromCanonical)

#  define XXH64 XXH_NAME2(XXH_NAMESPACE, XXH64)
#  define XXH64_createState XXH_NAME2(XXH_NAMESPACE, XXH64_createState)
#  define XXH64_freeState XXH_NAME2(XXH_NAMESPACE, XXH64_freeState)
#  define XXH64_reset XXH_NAME2(XXH_NAMESPACE, XXH64_reset)
#  define XXH64_update XXH_NAME2(XXH_NAMESPACE, XXH64_update)
#  define XXH64_digest XXH_NAME2(XXH_NAMESPACE, XXH64_digest)
#  define XXH64_copyState XXH_NAME2(XXH_NAMESPACE, XXH64_copyState)
#  define XXH64_canonicalFromHash XXH_NAME2(XXH_NAMESPACE, XXH64_canonicalFromHash)
#  define XXH64_hashFromCanonical XXH_NAME2(XXH_NAMESPACE, XXH64_hashFromCanonical)

#  define XXH3_64bits XXH_NAME2(XXH_NAMESPACE, XXH3_64bits)
#  define XXH3_64bits_withSecret XXH_NAME2(XXH_NAMESPACE, XXH3_64bits_withSecret)
#  define XXH3_64bits_withSeed XXH_NAME2(XXH_NAMESPACE, XXH3_64bits_withSeed)
#  define XXH3_64bits_withSecretandSeed XXH_NAME2(XXH_NAMESPACE, XXH3_64bits_withSecretandSeed)
#  define XXH3_createState XXH_NAME2(XXH_NAMESPACE, XXH3_createState)
#  define XXH3_freeState XXH_NAME2(XXH_NAMESPACE, XXH3_freeState)
#  define XXH3_copyState XXH_NAME2(XXH_NAMESPACE, XXH3_copyState)
#  define XXH3_64bits_reset XXH_NAME2(XXH_NAMESPACE, XXH3_64bits_reset)
#  define XXH3_64bits_reset_withSeed XXH_NAME2(XXH_NAMESPACE, XXH3_64bits_reset_withSeed)
#  define XXH3_64bits_reset_withSecret XXH_NAME2(XXH_NAMESPACE, XXH3_64bits_reset_withSecret)
#  define XXH3_64bits_reset_withSecretandSeed XXH_NAME2(XXH_NAMESPACE, XXH3_64bits_reset_withSecretandSeed)
#  define XXH3_64bits_update XXH_NAME2(XXH_NAMESPACE, XXH3_64bits_update)
#  define XXH3_64bits_digest XXH_NAME2(XXH_NAMESPACE, XXH3_64bits_digest)
#  define XXH3_generateSecret XXH_NAME2(XXH_NAMESPACE, XXH3_generateSecret)
#  define XXH3_generateSecret_fromSeed XXH_NAME2(XXH_NAMESPACE, XXH3_generateSecret_fromSeed)

#  define XXH128 XXH_NAME2(XXH_NAMESPACE, XXH128)
#  define XXH3_128bits XXH_NAME2(XXH_NAMESPACE, XXH3_128bits)
#  define XXH3_128bits_withSeed XXH_NAME2(XXH_NAMESPACE, XXH3_128bits_withSeed)
#  define XXH3_128bits_withSecret XXH_NAME2(XXH_NAMESPACE, XXH3_128bits_withSecret)
#  define XXH3_128bits_withSecretandSeed XXH_NAME2(XXH_NAMESPACE, XXH3_128bits_withSecretandSeed)
#  define XXH3_128bits_reset XXH_NAME2(XXH_NAMESPACE, XXH3_128bits_reset)
#  define XXH3_128bits_reset_withSeed XXH_NAME2(XXH_NAMESPACE, XXH3_128bits_reset_withSeed)
#  define XXH3_128bits_reset_withSecret XXH_NAME2(XXH_NAMESPACE, XXH3_128bits_reset_withSecret)
#  define XXH3_128bits_reset_withSecretandSeed XXH_NAME2(XXH_NAMESPACE, XXH3_128bits_reset_withSecretandSeed)
#  define XXH3_128bits_update XXH_NAME2(XXH_NAMESPACE, XXH3_128bits_update)
#  define XXH3_128bits_digest XXH_NAME2(XXH_NAMESPACE, XXH3_128bits_digest)
#  define XXH128_isEqual XXH_NAME2(XXH_NAMESPACE, XXH128_isEqual)
#  define XXH128_cmp     XXH_NAME2(XXH_NAMESPACE, XXH128_cmp)
#  define XXH128_canonicalFromHash XXH_NAME2(XXH_NAMESPACE, XXH128_canonicalFromHash)
#  define XXH128_hashFromCanonical XXH_NAME2(XXH_NAMESPACE, XXH128_hashFromCanonical)
#endif





#if !defined(XXH_INLINE_ALL) && !defined(XXH_PRIVATE_API)
#  if defined(WIN32) && defined(_MSC_VER) && (defined(XXH_IMPORT) || defined(XXH_EXPORT))
#    ifdef XXH_EXPORT
#      define XXH_PUBLIC_API __declspec(dllexport)
#    elif XXH_IMPORT
#      define XXH_PUBLIC_API __declspec(dllimport)
#    endif
#  else
#    define XXH_PUBLIC_API   /* do nothing */
#  endif
#endif

#if defined (__GNUC__)
# define XXH_CONSTF  __attribute__((const))
# define XXH_PUREF   __attribute__((pure))
# define XXH_MALLOCF __attribute__((malloc))
#else
# define XXH_CONSTF  /* disable */
# define XXH_PUREF
# define XXH_MALLOCF
#endif


#define XXH_VERSION_MAJOR    0
#define XXH_VERSION_MINOR    8
#define XXH_VERSION_RELEASE  2

#define XXH_VERSION_NUMBER  (XXH_VERSION_MAJOR *100*100 + XXH_VERSION_MINOR *100 + XXH_VERSION_RELEASE)

#if defined (__cplusplus)
extern "C" {
#endif

XXH_PUBLIC_API XXH_CONSTF unsigned XXH_versionNumber (void);

#if defined (__cplusplus)
}
#endif


#include <stddef.h>   /* size_t */

typedef enum {
    XXH_OK = 0, /*!< OK */
    XXH_ERROR   /*!< Error */
} XXH_errorcode;



#if defined(XXH_DOXYGEN) /* Don't show <stdint.h> include */

typedef uint32_t XXH32_hash_t;

#elif !defined (__VMS) \
  && (defined (__cplusplus) \
  || (defined (__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L) /* C99 */) )
#   ifdef _AIX
#     include <inttypes.h>
#   else
#     include <stdint.h>
#   endif
    typedef uint32_t XXH32_hash_t;

#else
#   include <limits.h>
#   if UINT_MAX == 0xFFFFFFFFUL
      typedef unsigned int XXH32_hash_t;
#   elif ULONG_MAX == 0xFFFFFFFFUL
      typedef unsigned long XXH32_hash_t;
#   else
#     error "unsupported platform: need a 32-bit type"
#   endif
#endif

#if defined (__cplusplus)
extern "C" {
#endif




XXH_PUBLIC_API XXH_PUREF XXH32_hash_t XXH32 (const void* input, size_t length, XXH32_hash_t seed);

#ifndef XXH_NO_STREAM

typedef struct XXH32_state_s XXH32_state_t;


XXH_PUBLIC_API XXH_MALLOCF XXH32_state_t* XXH32_createState(void);

XXH_PUBLIC_API XXH_errorcode  XXH32_freeState(XXH32_state_t* statePtr);

XXH_PUBLIC_API void XXH32_copyState(XXH32_state_t* dst_state, const XXH32_state_t* src_state);


XXH_PUBLIC_API XXH_errorcode XXH32_reset  (XXH32_state_t* statePtr, XXH32_hash_t seed);


XXH_PUBLIC_API XXH_errorcode XXH32_update (XXH32_state_t* statePtr, const void* input, size_t length);


XXH_PUBLIC_API XXH_PUREF XXH32_hash_t XXH32_digest (const XXH32_state_t* statePtr);
#endif /* !XXH_NO_STREAM */

/*******   Canonical representation   *******/


typedef struct {
    unsigned char digest[4]; /*!< Hash bytes, big endian */
} XXH32_canonical_t;


XXH_PUBLIC_API void XXH32_canonicalFromHash(XXH32_canonical_t* dst, XXH32_hash_t hash);


XXH_PUBLIC_API XXH_PUREF XXH32_hash_t XXH32_hashFromCanonical(const XXH32_canonical_t* src);



#ifdef __has_attribute
# define XXH_HAS_ATTRIBUTE(x) __has_attribute(x)
#else
# define XXH_HAS_ATTRIBUTE(x) 0
#endif




#define XXH_C23_VN 201711L




#if defined(__STDC_VERSION__) && (__STDC_VERSION__ >= XXH_C23_VN) && defined(__has_c_attribute)
# define XXH_HAS_C_ATTRIBUTE(x) __has_c_attribute(x)
#else
# define XXH_HAS_C_ATTRIBUTE(x) 0
#endif



#if defined(__cplusplus) && defined(__has_cpp_attribute)
# define XXH_HAS_CPP_ATTRIBUTE(x) __has_cpp_attribute(x)
#else
# define XXH_HAS_CPP_ATTRIBUTE(x) 0
#endif




#if XXH_HAS_C_ATTRIBUTE(fallthrough) || XXH_HAS_CPP_ATTRIBUTE(fallthrough)
# define XXH_FALLTHROUGH [[fallthrough]]
#elif XXH_HAS_ATTRIBUTE(__fallthrough__)
# define XXH_FALLTHROUGH __attribute__ ((__fallthrough__))
#else
# define XXH_FALLTHROUGH /* fallthrough */
#endif




#if XXH_HAS_ATTRIBUTE(noescape)
# define XXH_NOESCAPE __attribute__((noescape))
#else
# define XXH_NOESCAPE
#endif


#if defined (__cplusplus)
} /* end of extern "C" */
#endif



#ifndef XXH_NO_LONG_LONG

#if defined(XXH_DOXYGEN) /* don't include <stdint.h> */

typedef uint64_t XXH64_hash_t;
#elif !defined (__VMS) \
  && (defined (__cplusplus) \
  || (defined (__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L) /* C99 */) )
#   ifdef _AIX
#     include <inttypes.h>
#   else
#     include <stdint.h>
#   endif
   typedef uint64_t XXH64_hash_t;
#else
#  include <limits.h>
#  if defined(__LP64__) && ULONG_MAX == 0xFFFFFFFFFFFFFFFFULL

     typedef unsigned long XXH64_hash_t;
#  else

     typedef unsigned long long XXH64_hash_t;
#  endif
#endif

#if defined (__cplusplus)
extern "C" {
#endif



XXH_PUBLIC_API XXH_PUREF XXH64_hash_t XXH64(XXH_NOESCAPE const void* input, size_t length, XXH64_hash_t seed);

/*******   Streaming   *******/
#ifndef XXH_NO_STREAM

typedef struct XXH64_state_s XXH64_state_t;   /* incomplete type */


XXH_PUBLIC_API XXH_MALLOCF XXH64_state_t* XXH64_createState(void);


XXH_PUBLIC_API XXH_errorcode  XXH64_freeState(XXH64_state_t* statePtr);


XXH_PUBLIC_API void XXH64_copyState(XXH_NOESCAPE XXH64_state_t* dst_state, const XXH64_state_t* src_state);


XXH_PUBLIC_API XXH_errorcode XXH64_reset  (XXH_NOESCAPE XXH64_state_t* statePtr, XXH64_hash_t seed);


XXH_PUBLIC_API XXH_errorcode XXH64_update (XXH_NOESCAPE XXH64_state_t* statePtr, XXH_NOESCAPE const void* input, size_t length);


XXH_PUBLIC_API XXH_PUREF XXH64_hash_t XXH64_digest (XXH_NOESCAPE const XXH64_state_t* statePtr);
#endif /* !XXH_NO_STREAM */
/*******   Canonical representation   *******/


typedef struct { unsigned char digest[sizeof(XXH64_hash_t)]; } XXH64_canonical_t;


XXH_PUBLIC_API void XXH64_canonicalFromHash(XXH_NOESCAPE XXH64_canonical_t* dst, XXH64_hash_t hash);


XXH_PUBLIC_API XXH_PUREF XXH64_hash_t XXH64_hashFromCanonical(XXH_NOESCAPE const XXH64_canonical_t* src);


#if defined (__cplusplus)
} /* extern "C" */
#endif

#endif  /* XXH_NO_LONG_LONG */


#endif /* XXHASH_H_5627135585666179 */



#if defined(XXH_STATIC_LINKING_ONLY) && !defined(XXHASH_H_STATIC_13879238742)
#define XXHASH_H_STATIC_13879238742





struct XXH32_state_s {
   XXH32_hash_t total_len_32; /*!< Total length hashed, modulo 2^32 */
   XXH32_hash_t large_len;    /*!< Whether the hash is >= 16 (handles @ref total_len_32 overflow) */
   XXH32_hash_t v[4];         /*!< Accumulator lanes */
   XXH32_hash_t mem32[4];     /*!< Internal buffer for partial reads. Treated as unsigned char[16]. */
   XXH32_hash_t memsize;      /*!< Amount of data in @ref mem32 */
   XXH32_hash_t reserved;     /*!< Reserved field. Do not read nor write to it. */
};   /* typedef'd to XXH32_state_t */


#ifndef XXH_NO_LONG_LONG  /* defined when there is no 64-bit support */


struct XXH64_state_s {
   XXH64_hash_t total_len;    /*!< Total length hashed. This is always 64-bit. */
   XXH64_hash_t v[4];         /*!< Accumulator lanes */
   XXH64_hash_t mem64[4];     /*!< Internal buffer for partial reads. Treated as unsigned char[32]. */
   XXH32_hash_t memsize;      /*!< Amount of data in @ref mem64 */
   XXH32_hash_t reserved32;   /*!< Reserved field, needed for padding anyways*/
   XXH64_hash_t reserved64;   /*!< Reserved field. Do not read or write to it. */
};   /* typedef'd to XXH64_state_t */

#endif  /* XXH_NO_LONG_LONG */

#if defined(XXH_INLINE_ALL) || defined(XXH_PRIVATE_API)
#  define XXH_IMPLEMENTATION
#endif

#endif  /* defined(XXH_STATIC_LINKING_ONLY) && !defined(XXHASH_H_STATIC_13879238742) */









#if ( defined(XXH_INLINE_ALL) || defined(XXH_PRIVATE_API) \
   || defined(XXH_IMPLEMENTATION) ) && !defined(XXH_IMPLEM_13a8737387)
#  define XXH_IMPLEM_13a8737387




#ifdef XXH_DOXYGEN

#  define XXH_NO_LONG_LONG
#  undef XXH_NO_LONG_LONG /* don't actually */

#  define XXH_FORCE_MEMORY_ACCESS 0


#  define XXH_SIZE_OPT 0


#  define XXH_FORCE_ALIGN_CHECK 0


#  define XXH_NO_INLINE_HINTS 0


#  define XXH3_INLINE_SECRET 0


#  define XXH32_ENDJMP 0


#  define XXH_OLD_NAMES
#  undef XXH_OLD_NAMES /* don't actually use, it is ugly. */


#  define XXH_NO_STREAM
#  undef XXH_NO_STREAM /* don't actually */
#endif /* XXH_DOXYGEN */


#ifndef XXH_FORCE_MEMORY_ACCESS   /* can be defined externally, on command line for example */

#  if defined(__GNUC__) && !(defined(__ARM_ARCH) && __ARM_ARCH < 7 && defined(__ARM_FEATURE_UNALIGNED))
#    define XXH_FORCE_MEMORY_ACCESS 1
#  endif
#endif

#ifndef XXH_SIZE_OPT

#  if (defined(__GNUC__) || defined(__clang__)) && defined(__OPTIMIZE_SIZE__)
#    define XXH_SIZE_OPT 1
#  else
#    define XXH_SIZE_OPT 0
#  endif
#endif

#ifndef XXH_FORCE_ALIGN_CHECK  /* can be defined externally */

#  if XXH_SIZE_OPT >= 1 || \
      defined(__i386)  || defined(__x86_64__) || defined(__aarch64__) || defined(__ARM_FEATURE_UNALIGNED) \
   || defined(_M_IX86) || defined(_M_X64)     || defined(_M_ARM64)    || defined(_M_ARM) /* visual */
#    define XXH_FORCE_ALIGN_CHECK 0
#  else
#    define XXH_FORCE_ALIGN_CHECK 1
#  endif
#endif

#ifndef XXH_NO_INLINE_HINTS
#  if XXH_SIZE_OPT >= 1 || defined(__NO_INLINE__)  /* -O0, -fno-inline */
#    define XXH_NO_INLINE_HINTS 1
#  else
#    define XXH_NO_INLINE_HINTS 0
#  endif
#endif

#ifndef XXH3_INLINE_SECRET
#  if (defined(__GNUC__) && !defined(__clang__) && __GNUC__ >= 12) \
     || !defined(XXH_INLINE_ALL)
#    define XXH3_INLINE_SECRET 0
#  else
#    define XXH3_INLINE_SECRET 1
#  endif
#endif

#ifndef XXH32_ENDJMP

#  define XXH32_ENDJMP 0
#endif




#include <string.h>   /* memcmp, memcpy */
#include <limits.h>   /* ULLONG_MAX */

#if defined(XXH_NO_STREAM)

#elif defined(XXH_NO_STDLIB)



#if defined (__cplusplus)
extern "C" {
#endif

static XXH_CONSTF void* XXH_malloc(size_t s) { (void)s; return NULL; }
static void XXH_free(void* p) { (void)p; }

#if defined (__cplusplus)
} /* extern "C" */
#endif

#else


#include <stdlib.h>

#if defined (__cplusplus)
extern "C" {
#endif

static XXH_MALLOCF void* XXH_malloc(size_t s) { return malloc(s); }


static void XXH_free(void* p) { free(p); }

#if defined (__cplusplus)
} /* extern "C" */
#endif

#endif  /* XXH_NO_STDLIB */

#if defined (__cplusplus)
extern "C" {
#endif

static void* XXH_memcpy(void* dest, const void* src, size_t size)
{
    return memcpy(dest,src,size);
}

#if defined (__cplusplus)
} /* extern "C" */
#endif


#ifdef _MSC_VER /* Visual Studio warning fix */
#  pragma warning(disable : 4127) /* disable: C4127: conditional expression is constant */
#endif

#if XXH_NO_INLINE_HINTS  /* disable inlining hints */
#  if defined(__GNUC__) || defined(__clang__)
#    define XXH_FORCE_INLINE static __attribute__((unused))
#  else
#    define XXH_FORCE_INLINE static
#  endif
#  define XXH_NO_INLINE static

#elif defined(__GNUC__) || defined(__clang__)
#  define XXH_FORCE_INLINE static __inline__ __attribute__((always_inline, unused))
#  define XXH_NO_INLINE static __attribute__((noinline))
#elif defined(_MSC_VER)  /* Visual Studio */
#  define XXH_FORCE_INLINE static __forceinline
#  define XXH_NO_INLINE static __declspec(noinline)
#elif defined (__cplusplus) \
  || (defined (__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L))   /* C99 */
#  define XXH_FORCE_INLINE static inline
#  define XXH_NO_INLINE static
#else
#  define XXH_FORCE_INLINE static
#  define XXH_NO_INLINE static
#endif

#if XXH3_INLINE_SECRET
#  define XXH3_WITH_SECRET_INLINE XXH_FORCE_INLINE
#else
#  define XXH3_WITH_SECRET_INLINE XXH_NO_INLINE
#endif




#ifndef XXH_DEBUGLEVEL
#  ifdef DEBUGLEVEL /* backwards compat */
#    define XXH_DEBUGLEVEL DEBUGLEVEL
#  else
#    define XXH_DEBUGLEVEL 0
#  endif
#endif

#if (XXH_DEBUGLEVEL>=1)
#  include <assert.h>   /* note: can still be disabled with NDEBUG */
#  define XXH_ASSERT(c)   assert(c)
#else
#  if defined(__INTEL_COMPILER)
#    define XXH_ASSERT(c)   XXH_ASSUME((unsigned char) (c))
#  else
#    define XXH_ASSERT(c)   XXH_ASSUME(c)
#  endif
#endif


#ifndef XXH_STATIC_ASSERT
#  if defined(__STDC_VERSION__) && (__STDC_VERSION__ >= 201112L)    /* C11 */
#    define XXH_STATIC_ASSERT_WITH_MESSAGE(c,m) do { _Static_assert((c),m); } while(0)
#  elif defined(__cplusplus) && (__cplusplus >= 201103L)            /* C++11 */
#    define XXH_STATIC_ASSERT_WITH_MESSAGE(c,m) do { static_assert((c),m); } while(0)
#  else
#    define XXH_STATIC_ASSERT_WITH_MESSAGE(c,m) do { struct xxh_sa { char x[(c) ? 1 : -1]; }; } while(0)
#  endif
#  define XXH_STATIC_ASSERT(c) XXH_STATIC_ASSERT_WITH_MESSAGE((c),#c)
#endif


#if defined(__GNUC__) || defined(__clang__)
#  define XXH_COMPILER_GUARD(var) __asm__("" : "+r" (var))
#else
#  define XXH_COMPILER_GUARD(var) ((void)0)
#endif


#if defined(__clang__) && defined(__ARM_ARCH) && !defined(__wasm__)
#  define XXH_COMPILER_GUARD_CLANG_NEON(var) __asm__("" : "+w" (var))
#else
#  define XXH_COMPILER_GUARD_CLANG_NEON(var) ((void)0)
#endif


#if !defined (__VMS) \
 && (defined (__cplusplus) \
 || (defined (__STDC_VERSION__) && (__STDC_VERSION__ >= 199901L) /* C99 */) )
# ifdef _AIX
#   include <inttypes.h>
# else
#   include <stdint.h>
# endif
  typedef uint8_t xxh_u8;
#else
  typedef unsigned char xxh_u8;
#endif
typedef XXH32_hash_t xxh_u32;

#ifdef XXH_OLD_NAMES
#  warning "XXH_OLD_NAMES is planned to be removed starting v0.9. If the program depends on it, consider moving away from it by employing newer type names directly"
#  define BYTE xxh_u8
#  define U8   xxh_u8
#  define U32  xxh_u32
#endif

#if defined (__cplusplus)
extern "C" {
#endif











#if (defined(XXH_FORCE_MEMORY_ACCESS) && (XXH_FORCE_MEMORY_ACCESS==3))

#elif (defined(XXH_FORCE_MEMORY_ACCESS) && (XXH_FORCE_MEMORY_ACCESS==2))


static xxh_u32 XXH_read32(const void* memPtr) { return *(const xxh_u32*) memPtr; }

#elif (defined(XXH_FORCE_MEMORY_ACCESS) && (XXH_FORCE_MEMORY_ACCESS==1))


#ifdef XXH_OLD_NAMES
typedef union { xxh_u32 u32; } __attribute__((packed)) unalign;
#endif
static xxh_u32 XXH_read32(const void* ptr)
{
    typedef __attribute__((aligned(1))) xxh_u32 xxh_unalign32;
    return *((const xxh_unalign32*)ptr);
}

#else


static xxh_u32 XXH_read32(const void* memPtr)
{
    xxh_u32 val;
    XXH_memcpy(&val, memPtr, sizeof(val));
    return val;
}

#endif   /* XXH_FORCE_DIRECT_MEMORY_ACCESS */





#ifndef XXH_CPU_LITTLE_ENDIAN

#  if defined(_WIN32) /* Windows is always little endian */ \
     || defined(__LITTLE_ENDIAN__) \
     || (defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__)
#    define XXH_CPU_LITTLE_ENDIAN 1
#  elif defined(__BIG_ENDIAN__) \
     || (defined(__BYTE_ORDER__) && __BYTE_ORDER__ == __ORDER_BIG_ENDIAN__)
#    define XXH_CPU_LITTLE_ENDIAN 0
#  else

static int XXH_isLittleEndian(void)
{

    const union { xxh_u32 u; xxh_u8 c[4]; } one = { 1 };
    return one.c[0];
}
#   define XXH_CPU_LITTLE_ENDIAN   XXH_isLittleEndian()
#  endif
#endif





#define XXH_GCC_VERSION (__GNUC__ * 100 + __GNUC_MINOR__)

#ifdef __has_builtin
#  define XXH_HAS_BUILTIN(x) __has_builtin(x)
#else
#  define XXH_HAS_BUILTIN(x) 0
#endif





#if XXH_HAS_BUILTIN(__builtin_unreachable)
#  define XXH_UNREACHABLE() __builtin_unreachable()

#elif defined(_MSC_VER)
#  define XXH_UNREACHABLE() __assume(0)

#else
#  define XXH_UNREACHABLE()
#endif

#if XXH_HAS_BUILTIN(__builtin_assume)
#  define XXH_ASSUME(c) __builtin_assume(c)
#else
#  define XXH_ASSUME(c) if (!(c)) { XXH_UNREACHABLE(); }
#endif


#if !defined(NO_CLANG_BUILTIN) && XXH_HAS_BUILTIN(__builtin_rotateleft32) \
                               && XXH_HAS_BUILTIN(__builtin_rotateleft64)
#  define XXH_rotl32 __builtin_rotateleft32
#  define XXH_rotl64 __builtin_rotateleft64

#elif defined(_MSC_VER)
#  define XXH_rotl32(x,r) _rotl(x,r)
#  define XXH_rotl64(x,r) _rotl64(x,r)
#else
#  define XXH_rotl32(x,r) (((x) << (r)) | ((x) >> (32 - (r))))
#  define XXH_rotl64(x,r) (((x) << (r)) | ((x) >> (64 - (r))))
#endif


#if defined(_MSC_VER)     /* Visual Studio */
#  define XXH_swap32 _byteswap_ulong
#elif XXH_GCC_VERSION >= 403
#  define XXH_swap32 __builtin_bswap32
#else
static xxh_u32 XXH_swap32 (xxh_u32 x)
{
    return  ((x << 24) & 0xff000000 ) |
            ((x <<  8) & 0x00ff0000 ) |
            ((x >>  8) & 0x0000ff00 ) |
            ((x >> 24) & 0x000000ff );
}
#endif





typedef enum {
    XXH_aligned,  /*!< Aligned */
    XXH_unaligned /*!< Possibly unaligned */
} XXH_alignment;


#if (defined(XXH_FORCE_MEMORY_ACCESS) && (XXH_FORCE_MEMORY_ACCESS==3))

XXH_FORCE_INLINE xxh_u32 XXH_readLE32(const void* memPtr)
{
    const xxh_u8* bytePtr = (const xxh_u8 *)memPtr;
    return bytePtr[0]
         | ((xxh_u32)bytePtr[1] << 8)
         | ((xxh_u32)bytePtr[2] << 16)
         | ((xxh_u32)bytePtr[3] << 24);
}

XXH_FORCE_INLINE xxh_u32 XXH_readBE32(const void* memPtr)
{
    const xxh_u8* bytePtr = (const xxh_u8 *)memPtr;
    return bytePtr[3]
         | ((xxh_u32)bytePtr[2] << 8)
         | ((xxh_u32)bytePtr[1] << 16)
         | ((xxh_u32)bytePtr[0] << 24);
}

#else
XXH_FORCE_INLINE xxh_u32 XXH_readLE32(const void* ptr)
{
    return XXH_CPU_LITTLE_ENDIAN ? XXH_read32(ptr) : XXH_swap32(XXH_read32(ptr));
}

static xxh_u32 XXH_readBE32(const void* ptr)
{
    return XXH_CPU_LITTLE_ENDIAN ? XXH_swap32(XXH_read32(ptr)) : XXH_read32(ptr);
}
#endif

XXH_FORCE_INLINE xxh_u32
XXH_readLE32_align(const void* ptr, XXH_alignment align)
{
    if (align==XXH_unaligned) {
        return XXH_readLE32(ptr);
    } else {
        return XXH_CPU_LITTLE_ENDIAN ? *(const xxh_u32*)ptr : XXH_swap32(*(const xxh_u32*)ptr);
    }
}




XXH_PUBLIC_API unsigned XXH_versionNumber (void) { return XXH_VERSION_NUMBER; }





#define XXH_PRIME32_1  0x9E3779B1U  /*!< 0b10011110001101110111100110110001 */
#define XXH_PRIME32_2  0x85EBCA77U  /*!< 0b10000101111010111100101001110111 */
#define XXH_PRIME32_3  0xC2B2AE3DU  /*!< 0b11000010101100101010111000111101 */
#define XXH_PRIME32_4  0x27D4EB2FU  /*!< 0b00100111110101001110101100101111 */
#define XXH_PRIME32_5  0x165667B1U  /*!< 0b00010110010101100110011110110001 */

#ifdef XXH_OLD_NAMES
#  define PRIME32_1 XXH_PRIME32_1
#  define PRIME32_2 XXH_PRIME32_2
#  define PRIME32_3 XXH_PRIME32_3
#  define PRIME32_4 XXH_PRIME32_4
#  define PRIME32_5 XXH_PRIME32_5
#endif


static xxh_u32 XXH32_round(xxh_u32 acc, xxh_u32 input)
{
    acc += input * XXH_PRIME32_2;
    acc  = XXH_rotl32(acc, 13);
    acc *= XXH_PRIME32_1;
#if (defined(__SSE4_1__) || defined(__aarch64__) || defined(__wasm_simd128__)) && !defined(XXH_ENABLE_AUTOVECTORIZE)

    XXH_COMPILER_GUARD(acc);
#endif
    return acc;
}


static xxh_u32 XXH32_avalanche(xxh_u32 hash)
{
    hash ^= hash >> 15;
    hash *= XXH_PRIME32_2;
    hash ^= hash >> 13;
    hash *= XXH_PRIME32_3;
    hash ^= hash >> 16;
    return hash;
}

#define XXH_get32bits(p) XXH_readLE32_align(p, align)


static XXH_PUREF xxh_u32
XXH32_finalize(xxh_u32 hash, const xxh_u8* ptr, size_t len, XXH_alignment align)
{
#define XXH_PROCESS1 do {                             \
    hash += (*ptr++) * XXH_PRIME32_5;                 \
    hash = XXH_rotl32(hash, 11) * XXH_PRIME32_1;      \
} while (0)

#define XXH_PROCESS4 do {                             \
    hash += XXH_get32bits(ptr) * XXH_PRIME32_3;       \
    ptr += 4;                                         \
    hash  = XXH_rotl32(hash, 17) * XXH_PRIME32_4;     \
} while (0)

    if (ptr==NULL) XXH_ASSERT(len == 0);


    if (!XXH32_ENDJMP) {
        len &= 15;
        while (len >= 4) {
            XXH_PROCESS4;
            len -= 4;
        }
        while (len > 0) {
            XXH_PROCESS1;
            --len;
        }
        return XXH32_avalanche(hash);
    } else {
         switch(len&15) /* or switch(bEnd - p) */ {
           case 12:      XXH_PROCESS4;
                         XXH_FALLTHROUGH;  /* fallthrough */
           case 8:       XXH_PROCESS4;
                         XXH_FALLTHROUGH;  /* fallthrough */
           case 4:       XXH_PROCESS4;
                         return XXH32_avalanche(hash);

           case 13:      XXH_PROCESS4;
                         XXH_FALLTHROUGH;  /* fallthrough */
           case 9:       XXH_PROCESS4;
                         XXH_FALLTHROUGH;  /* fallthrough */
           case 5:       XXH_PROCESS4;
                         XXH_PROCESS1;
                         return XXH32_avalanche(hash);

           case 14:      XXH_PROCESS4;
                         XXH_FALLTHROUGH;  /* fallthrough */
           case 10:      XXH_PROCESS4;
                         XXH_FALLTHROUGH;  /* fallthrough */
           case 6:       XXH_PROCESS4;
                         XXH_PROCESS1;
                         XXH_PROCESS1;
                         return XXH32_avalanche(hash);

           case 15:      XXH_PROCESS4;
                         XXH_FALLTHROUGH;  /* fallthrough */
           case 11:      XXH_PROCESS4;
                         XXH_FALLTHROUGH;  /* fallthrough */
           case 7:       XXH_PROCESS4;
                         XXH_FALLTHROUGH;  /* fallthrough */
           case 3:       XXH_PROCESS1;
                         XXH_FALLTHROUGH;  /* fallthrough */
           case 2:       XXH_PROCESS1;
                         XXH_FALLTHROUGH;  /* fallthrough */
           case 1:       XXH_PROCESS1;
                         XXH_FALLTHROUGH;  /* fallthrough */
           case 0:       return XXH32_avalanche(hash);
        }
        XXH_ASSERT(0);
        return hash;   /* reaching this point is deemed impossible */
    }
}

#ifdef XXH_OLD_NAMES
#  define PROCESS1 XXH_PROCESS1
#  define PROCESS4 XXH_PROCESS4
#else
#  undef XXH_PROCESS1
#  undef XXH_PROCESS4
#endif


XXH_FORCE_INLINE XXH_PUREF xxh_u32
XXH32_endian_align(const xxh_u8* input, size_t len, xxh_u32 seed, XXH_alignment align)
{
    xxh_u32 h32;

    if (input==NULL) XXH_ASSERT(len == 0);

    if (len>=16) {
        const xxh_u8* const bEnd = input + len;
        const xxh_u8* const limit = bEnd - 15;
        xxh_u32 v1 = seed + XXH_PRIME32_1 + XXH_PRIME32_2;
        xxh_u32 v2 = seed + XXH_PRIME32_2;
        xxh_u32 v3 = seed + 0;
        xxh_u32 v4 = seed - XXH_PRIME32_1;

        do {
            v1 = XXH32_round(v1, XXH_get32bits(input)); input += 4;
            v2 = XXH32_round(v2, XXH_get32bits(input)); input += 4;
            v3 = XXH32_round(v3, XXH_get32bits(input)); input += 4;
            v4 = XXH32_round(v4, XXH_get32bits(input)); input += 4;
        } while (input < limit);

        h32 = XXH_rotl32(v1, 1)  + XXH_rotl32(v2, 7)
            + XXH_rotl32(v3, 12) + XXH_rotl32(v4, 18);
    } else {
        h32  = seed + XXH_PRIME32_5;
    }

    h32 += (xxh_u32)len;

    return XXH32_finalize(h32, input, len&15, align);
}


XXH_PUBLIC_API XXH32_hash_t XXH32 (const void* input, size_t len, XXH32_hash_t seed)
{
#if !defined(XXH_NO_STREAM) && XXH_SIZE_OPT >= 2

    XXH32_state_t state;
    XXH32_reset(&state, seed);
    XXH32_update(&state, (const xxh_u8*)input, len);
    return XXH32_digest(&state);
#else
    if (XXH_FORCE_ALIGN_CHECK) {
        if ((((size_t)input) & 3) == 0) {   /* Input is 4-bytes aligned, leverage the speed benefit */
            return XXH32_endian_align((const xxh_u8*)input, len, seed, XXH_aligned);
    }   }

    return XXH32_endian_align((const xxh_u8*)input, len, seed, XXH_unaligned);
#endif
}



/*******   Hash streaming   *******/
#ifndef XXH_NO_STREAM

XXH_PUBLIC_API XXH32_state_t* XXH32_createState(void)
{
    return (XXH32_state_t*)XXH_malloc(sizeof(XXH32_state_t));
}

XXH_PUBLIC_API XXH_errorcode XXH32_freeState(XXH32_state_t* statePtr)
{
    XXH_free(statePtr);
    return XXH_OK;
}


XXH_PUBLIC_API void XXH32_copyState(XXH32_state_t* dstState, const XXH32_state_t* srcState)
{
    XXH_memcpy(dstState, srcState, sizeof(*dstState));
}


XXH_PUBLIC_API XXH_errorcode XXH32_reset(XXH32_state_t* statePtr, XXH32_hash_t seed)
{
    XXH_ASSERT(statePtr != NULL);
    memset(statePtr, 0, sizeof(*statePtr));
    statePtr->v[0] = seed + XXH_PRIME32_1 + XXH_PRIME32_2;
    statePtr->v[1] = seed + XXH_PRIME32_2;
    statePtr->v[2] = seed + 0;
    statePtr->v[3] = seed - XXH_PRIME32_1;
    return XXH_OK;
}



XXH_PUBLIC_API XXH_errorcode
XXH32_update(XXH32_state_t* state, const void* input, size_t len)
{
    if (input==NULL) {
        XXH_ASSERT(len == 0);
        return XXH_OK;
    }

    {   const xxh_u8* p = (const xxh_u8*)input;
        const xxh_u8* const bEnd = p + len;

        state->total_len_32 += (XXH32_hash_t)len;
        state->large_len |= (XXH32_hash_t)((len>=16) | (state->total_len_32>=16));

        if (state->memsize + len < 16)  {   /* fill in tmp buffer */
            XXH_memcpy((xxh_u8*)(state->mem32) + state->memsize, input, len);
            state->memsize += (XXH32_hash_t)len;
            return XXH_OK;
        }

        if (state->memsize) {   /* some data left from previous update */
            XXH_memcpy((xxh_u8*)(state->mem32) + state->memsize, input, 16-state->memsize);
            {   const xxh_u32* p32 = state->mem32;
                state->v[0] = XXH32_round(state->v[0], XXH_readLE32(p32)); p32++;
                state->v[1] = XXH32_round(state->v[1], XXH_readLE32(p32)); p32++;
                state->v[2] = XXH32_round(state->v[2], XXH_readLE32(p32)); p32++;
                state->v[3] = XXH32_round(state->v[3], XXH_readLE32(p32));
            }
            p += 16-state->memsize;
            state->memsize = 0;
        }

        if (p <= bEnd-16) {
            const xxh_u8* const limit = bEnd - 16;

            do {
                state->v[0] = XXH32_round(state->v[0], XXH_readLE32(p)); p+=4;
                state->v[1] = XXH32_round(state->v[1], XXH_readLE32(p)); p+=4;
                state->v[2] = XXH32_round(state->v[2], XXH_readLE32(p)); p+=4;
                state->v[3] = XXH32_round(state->v[3], XXH_readLE32(p)); p+=4;
            } while (p<=limit);

        }

        if (p < bEnd) {
            XXH_memcpy(state->mem32, p, (size_t)(bEnd-p));
            state->memsize = (unsigned)(bEnd-p);
        }
    }

    return XXH_OK;
}



XXH_PUBLIC_API XXH32_hash_t XXH32_digest(const XXH32_state_t* state)
{
    xxh_u32 h32;

    if (state->large_len) {
        h32 = XXH_rotl32(state->v[0], 1)
            + XXH_rotl32(state->v[1], 7)
            + XXH_rotl32(state->v[2], 12)
            + XXH_rotl32(state->v[3], 18);
    } else {
        h32 = state->v[2] /* == seed */ + XXH_PRIME32_5;
    }

    h32 += state->total_len_32;

    return XXH32_finalize(h32, (const xxh_u8*)state->mem32, state->memsize, XXH_aligned);
}
#endif /* !XXH_NO_STREAM */

/*******   Canonical representation   *******/


XXH_PUBLIC_API void XXH32_canonicalFromHash(XXH32_canonical_t* dst, XXH32_hash_t hash)
{
    XXH_STATIC_ASSERT(sizeof(XXH32_canonical_t) == sizeof(XXH32_hash_t));
    if (XXH_CPU_LITTLE_ENDIAN) hash = XXH_swap32(hash);
    XXH_memcpy(dst, &hash, sizeof(*dst));
}

XXH_PUBLIC_API XXH32_hash_t XXH32_hashFromCanonical(const XXH32_canonical_t* src)
{
    return XXH_readBE32(src);
}


#ifndef XXH_NO_LONG_LONG



/*******   Memory access   *******/

typedef XXH64_hash_t xxh_u64;

#ifdef XXH_OLD_NAMES
#  define U64 xxh_u64
#endif

#if (defined(XXH_FORCE_MEMORY_ACCESS) && (XXH_FORCE_MEMORY_ACCESS==3))

#elif (defined(XXH_FORCE_MEMORY_ACCESS) && (XXH_FORCE_MEMORY_ACCESS==2))


static xxh_u64 XXH_read64(const void* memPtr)
{
    return *(const xxh_u64*) memPtr;
}

#elif (defined(XXH_FORCE_MEMORY_ACCESS) && (XXH_FORCE_MEMORY_ACCESS==1))


#ifdef XXH_OLD_NAMES
typedef union { xxh_u32 u32; xxh_u64 u64; } __attribute__((packed)) unalign64;
#endif
static xxh_u64 XXH_read64(const void* ptr)
{
    typedef __attribute__((aligned(1))) xxh_u64 xxh_unalign64;
    return *((const xxh_unalign64*)ptr);
}

#else


static xxh_u64 XXH_read64(const void* memPtr)
{
    xxh_u64 val;
    XXH_memcpy(&val, memPtr, sizeof(val));
    return val;
}

#endif   /* XXH_FORCE_DIRECT_MEMORY_ACCESS */

#if defined(_MSC_VER)     /* Visual Studio */
#  define XXH_swap64 _byteswap_uint64
#elif XXH_GCC_VERSION >= 403
#  define XXH_swap64 __builtin_bswap64
#else
static xxh_u64 XXH_swap64(xxh_u64 x)
{
    return  ((x << 56) & 0xff00000000000000ULL) |
            ((x << 40) & 0x00ff000000000000ULL) |
            ((x << 24) & 0x0000ff0000000000ULL) |
            ((x << 8)  & 0x000000ff00000000ULL) |
            ((x >> 8)  & 0x00000000ff000000ULL) |
            ((x >> 24) & 0x0000000000ff0000ULL) |
            ((x >> 40) & 0x000000000000ff00ULL) |
            ((x >> 56) & 0x00000000000000ffULL);
}
#endif



#if (defined(XXH_FORCE_MEMORY_ACCESS) && (XXH_FORCE_MEMORY_ACCESS==3))

XXH_FORCE_INLINE xxh_u64 XXH_readLE64(const void* memPtr)
{
    const xxh_u8* bytePtr = (const xxh_u8 *)memPtr;
    return bytePtr[0]
         | ((xxh_u64)bytePtr[1] << 8)
         | ((xxh_u64)bytePtr[2] << 16)
         | ((xxh_u64)bytePtr[3] << 24)
         | ((xxh_u64)bytePtr[4] << 32)
         | ((xxh_u64)bytePtr[5] << 40)
         | ((xxh_u64)bytePtr[6] << 48)
         | ((xxh_u64)bytePtr[7] << 56);
}

XXH_FORCE_INLINE xxh_u64 XXH_readBE64(const void* memPtr)
{
    const xxh_u8* bytePtr = (const xxh_u8 *)memPtr;
    return bytePtr[7]
         | ((xxh_u64)bytePtr[6] << 8)
         | ((xxh_u64)bytePtr[5] << 16)
         | ((xxh_u64)bytePtr[4] << 24)
         | ((xxh_u64)bytePtr[3] << 32)
         | ((xxh_u64)bytePtr[2] << 40)
         | ((xxh_u64)bytePtr[1] << 48)
         | ((xxh_u64)bytePtr[0] << 56);
}

#else
XXH_FORCE_INLINE xxh_u64 XXH_readLE64(const void* ptr)
{
    return XXH_CPU_LITTLE_ENDIAN ? XXH_read64(ptr) : XXH_swap64(XXH_read64(ptr));
}

static xxh_u64 XXH_readBE64(const void* ptr)
{
    return XXH_CPU_LITTLE_ENDIAN ? XXH_swap64(XXH_read64(ptr)) : XXH_read64(ptr);
}
#endif

XXH_FORCE_INLINE xxh_u64
XXH_readLE64_align(const void* ptr, XXH_alignment align)
{
    if (align==XXH_unaligned)
        return XXH_readLE64(ptr);
    else
        return XXH_CPU_LITTLE_ENDIAN ? *(const xxh_u64*)ptr : XXH_swap64(*(const xxh_u64*)ptr);
}


/*******   xxh64   *******/


#define XXH_PRIME64_1  0x9E3779B185EBCA87ULL  /*!< 0b1001111000110111011110011011000110000101111010111100101010000111 */
#define XXH_PRIME64_2  0xC2B2AE3D27D4EB4FULL  /*!< 0b1100001010110010101011100011110100100111110101001110101101001111 */
#define XXH_PRIME64_3  0x165667B19E3779F9ULL  /*!< 0b0001011001010110011001111011000110011110001101110111100111111001 */
#define XXH_PRIME64_4  0x85EBCA77C2B2AE63ULL  /*!< 0b1000010111101011110010100111011111000010101100101010111001100011 */
#define XXH_PRIME64_5  0x27D4EB2F165667C5ULL  /*!< 0b0010011111010100111010110010111100010110010101100110011111000101 */

#ifdef XXH_OLD_NAMES
#  define PRIME64_1 XXH_PRIME64_1
#  define PRIME64_2 XXH_PRIME64_2
#  define PRIME64_3 XXH_PRIME64_3
#  define PRIME64_4 XXH_PRIME64_4
#  define PRIME64_5 XXH_PRIME64_5
#endif


static xxh_u64 XXH64_round(xxh_u64 acc, xxh_u64 input)
{
    acc += input * XXH_PRIME64_2;
    acc  = XXH_rotl64(acc, 31);
    acc *= XXH_PRIME64_1;
#if (defined(__AVX512F__)) && !defined(XXH_ENABLE_AUTOVECTORIZE)

    XXH_COMPILER_GUARD(acc);
#endif
    return acc;
}

static xxh_u64 XXH64_mergeRound(xxh_u64 acc, xxh_u64 val)
{
    val  = XXH64_round(0, val);
    acc ^= val;
    acc  = acc * XXH_PRIME64_1 + XXH_PRIME64_4;
    return acc;
}


static xxh_u64 XXH64_avalanche(xxh_u64 hash)
{
    hash ^= hash >> 33;
    hash *= XXH_PRIME64_2;
    hash ^= hash >> 29;
    hash *= XXH_PRIME64_3;
    hash ^= hash >> 32;
    return hash;
}


#define XXH_get64bits(p) XXH_readLE64_align(p, align)


static XXH_PUREF xxh_u64
XXH64_finalize(xxh_u64 hash, const xxh_u8* ptr, size_t len, XXH_alignment align)
{
    if (ptr==NULL) XXH_ASSERT(len == 0);
    len &= 31;
    while (len >= 8) {
        xxh_u64 const k1 = XXH64_round(0, XXH_get64bits(ptr));
        ptr += 8;
        hash ^= k1;
        hash  = XXH_rotl64(hash,27) * XXH_PRIME64_1 + XXH_PRIME64_4;
        len -= 8;
    }
    if (len >= 4) {
        hash ^= (xxh_u64)(XXH_get32bits(ptr)) * XXH_PRIME64_1;
        ptr += 4;
        hash = XXH_rotl64(hash, 23) * XXH_PRIME64_2 + XXH_PRIME64_3;
        len -= 4;
    }
    while (len > 0) {
        hash ^= (*ptr++) * XXH_PRIME64_5;
        hash = XXH_rotl64(hash, 11) * XXH_PRIME64_1;
        --len;
    }
    return  XXH64_avalanche(hash);
}

#ifdef XXH_OLD_NAMES
#  define PROCESS1_64 XXH_PROCESS1_64
#  define PROCESS4_64 XXH_PROCESS4_64
#  define PROCESS8_64 XXH_PROCESS8_64
#else
#  undef XXH_PROCESS1_64
#  undef XXH_PROCESS4_64
#  undef XXH_PROCESS8_64
#endif


XXH_FORCE_INLINE XXH_PUREF xxh_u64
XXH64_endian_align(const xxh_u8* input, size_t len, xxh_u64 seed, XXH_alignment align)
{
    xxh_u64 h64;
    if (input==NULL) XXH_ASSERT(len == 0);

    if (len>=32) {
        const xxh_u8* const bEnd = input + len;
        const xxh_u8* const limit = bEnd - 31;
        xxh_u64 v1 = seed + XXH_PRIME64_1 + XXH_PRIME64_2;
        xxh_u64 v2 = seed + XXH_PRIME64_2;
        xxh_u64 v3 = seed + 0;
        xxh_u64 v4 = seed - XXH_PRIME64_1;

        do {
            v1 = XXH64_round(v1, XXH_get64bits(input)); input+=8;
            v2 = XXH64_round(v2, XXH_get64bits(input)); input+=8;
            v3 = XXH64_round(v3, XXH_get64bits(input)); input+=8;
            v4 = XXH64_round(v4, XXH_get64bits(input)); input+=8;
        } while (input<limit);

        h64 = XXH_rotl64(v1, 1) + XXH_rotl64(v2, 7) + XXH_rotl64(v3, 12) + XXH_rotl64(v4, 18);
        h64 = XXH64_mergeRound(h64, v1);
        h64 = XXH64_mergeRound(h64, v2);
        h64 = XXH64_mergeRound(h64, v3);
        h64 = XXH64_mergeRound(h64, v4);

    } else {
        h64  = seed + XXH_PRIME64_5;
    }

    h64 += (xxh_u64) len;

    return XXH64_finalize(h64, input, len, align);
}



XXH_PUBLIC_API XXH64_hash_t XXH64 (XXH_NOESCAPE const void* input, size_t len, XXH64_hash_t seed)
{
#if !defined(XXH_NO_STREAM) && XXH_SIZE_OPT >= 2

    XXH64_state_t state;
    XXH64_reset(&state, seed);
    XXH64_update(&state, (const xxh_u8*)input, len);
    return XXH64_digest(&state);
#else
    if (XXH_FORCE_ALIGN_CHECK) {
        if ((((size_t)input) & 7)==0) {  /* Input is aligned, let's leverage the speed advantage */
            return XXH64_endian_align((const xxh_u8*)input, len, seed, XXH_aligned);
    }   }

    return XXH64_endian_align((const xxh_u8*)input, len, seed, XXH_unaligned);

#endif
}

/*******   Hash Streaming   *******/
#ifndef XXH_NO_STREAM

XXH_PUBLIC_API XXH64_state_t* XXH64_createState(void)
{
    return (XXH64_state_t*)XXH_malloc(sizeof(XXH64_state_t));
}

XXH_PUBLIC_API XXH_errorcode XXH64_freeState(XXH64_state_t* statePtr)
{
    XXH_free(statePtr);
    return XXH_OK;
}


XXH_PUBLIC_API void XXH64_copyState(XXH_NOESCAPE XXH64_state_t* dstState, const XXH64_state_t* srcState)
{
    XXH_memcpy(dstState, srcState, sizeof(*dstState));
}


XXH_PUBLIC_API XXH_errorcode XXH64_reset(XXH_NOESCAPE XXH64_state_t* statePtr, XXH64_hash_t seed)
{
    XXH_ASSERT(statePtr != NULL);
    memset(statePtr, 0, sizeof(*statePtr));
    statePtr->v[0] = seed + XXH_PRIME64_1 + XXH_PRIME64_2;
    statePtr->v[1] = seed + XXH_PRIME64_2;
    statePtr->v[2] = seed + 0;
    statePtr->v[3] = seed - XXH_PRIME64_1;
    return XXH_OK;
}


XXH_PUBLIC_API XXH_errorcode
XXH64_update (XXH_NOESCAPE XXH64_state_t* state, XXH_NOESCAPE const void* input, size_t len)
{
    if (input==NULL) {
        XXH_ASSERT(len == 0);
        return XXH_OK;
    }

    {   const xxh_u8* p = (const xxh_u8*)input;
        const xxh_u8* const bEnd = p + len;

        state->total_len += len;

        if (state->memsize + len < 32) {  /* fill in tmp buffer */
            XXH_memcpy(((xxh_u8*)state->mem64) + state->memsize, input, len);
            state->memsize += (xxh_u32)len;
            return XXH_OK;
        }

        if (state->memsize) {   /* tmp buffer is full */
            XXH_memcpy(((xxh_u8*)state->mem64) + state->memsize, input, 32-state->memsize);
            state->v[0] = XXH64_round(state->v[0], XXH_readLE64(state->mem64+0));
            state->v[1] = XXH64_round(state->v[1], XXH_readLE64(state->mem64+1));
            state->v[2] = XXH64_round(state->v[2], XXH_readLE64(state->mem64+2));
            state->v[3] = XXH64_round(state->v[3], XXH_readLE64(state->mem64+3));
            p += 32 - state->memsize;
            state->memsize = 0;
        }

        if (p+32 <= bEnd) {
            const xxh_u8* const limit = bEnd - 32;

            do {
                state->v[0] = XXH64_round(state->v[0], XXH_readLE64(p)); p+=8;
                state->v[1] = XXH64_round(state->v[1], XXH_readLE64(p)); p+=8;
                state->v[2] = XXH64_round(state->v[2], XXH_readLE64(p)); p+=8;
                state->v[3] = XXH64_round(state->v[3], XXH_readLE64(p)); p+=8;
            } while (p<=limit);

        }

        if (p < bEnd) {
            XXH_memcpy(state->mem64, p, (size_t)(bEnd-p));
            state->memsize = (unsigned)(bEnd-p);
        }
    }

    return XXH_OK;
}



XXH_PUBLIC_API XXH64_hash_t XXH64_digest(XXH_NOESCAPE const XXH64_state_t* state)
{
    xxh_u64 h64;

    if (state->total_len >= 32) {
        h64 = XXH_rotl64(state->v[0], 1) + XXH_rotl64(state->v[1], 7) + XXH_rotl64(state->v[2], 12) + XXH_rotl64(state->v[3], 18);
        h64 = XXH64_mergeRound(h64, state->v[0]);
        h64 = XXH64_mergeRound(h64, state->v[1]);
        h64 = XXH64_mergeRound(h64, state->v[2]);
        h64 = XXH64_mergeRound(h64, state->v[3]);
    } else {
        h64  = state->v[2] /*seed*/ + XXH_PRIME64_5;
    }

    h64 += (xxh_u64) state->total_len;

    return XXH64_finalize(h64, (const xxh_u8*)state->mem64, (size_t)state->total_len, XXH_aligned);
}
#endif /* !XXH_NO_STREAM */

/******* Canonical representation   *******/


XXH_PUBLIC_API void XXH64_canonicalFromHash(XXH_NOESCAPE XXH64_canonical_t* dst, XXH64_hash_t hash)
{
    XXH_STATIC_ASSERT(sizeof(XXH64_canonical_t) == sizeof(XXH64_hash_t));
    if (XXH_CPU_LITTLE_ENDIAN) hash = XXH_swap64(hash);
    XXH_memcpy(dst, &hash, sizeof(*dst));
}


XXH_PUBLIC_API XXH64_hash_t XXH64_hashFromCanonical(XXH_NOESCAPE const XXH64_canonical_t* src)
{
    return XXH_readBE64(src);
}

#if defined (__cplusplus)
}
#endif

#endif  /* XXH_NO_XXH3 */


#endif  /* XXH_IMPLEMENTATION */
/**** ended inlining xxhash.h ****/
#ifndef ZSTD_NO_TRACE
#error Using excluded file: zstd_trace.h (re-amalgamate source to fix)
#else
#  define ZSTD_TRACE 0
#endif


#define ZSTD_STATIC_ASSERT(c) DEBUG_STATIC_ASSERT(c)
#define ZSTD_isError ERR_isError   /* for inlining */
#define FSE_isError  ERR_isError
#define HUF_isError  ERR_isError



#undef MIN
#undef MAX
#define MIN(a,b) ((a)<(b) ? (a) : (b))
#define MAX(a,b) ((a)>(b) ? (a) : (b))
#define BOUNDED(min,val,max) (MAX(min,MIN(val,max)))



#define ZSTD_OPT_NUM    (1<<12)

#define ZSTD_REP_NUM      3                 /* number of repcodes */
static UNUSED_ATTR const U32 repStartValue[ZSTD_REP_NUM] = { 1, 4, 8 };

#define KB *(1 <<10)
#define MB *(1 <<20)
#define GB *(1U<<30)

#define BIT7 128
#define BIT6  64
#define BIT5  32
#define BIT4  16
#define BIT1   2
#define BIT0   1

#define ZSTD_WINDOWLOG_ABSOLUTEMIN 10
static UNUSED_ATTR const size_t ZSTD_fcs_fieldSize[4] = { 0, 2, 4, 8 };
static UNUSED_ATTR const size_t ZSTD_did_fieldSize[4] = { 0, 1, 2, 4 };

#define ZSTD_FRAMEIDSIZE 4   /* magic number size */

#define ZSTD_BLOCKHEADERSIZE 3   /* C standard doesn't allow `static const` variable to be init using another `static const` variable */
static UNUSED_ATTR const size_t ZSTD_blockHeaderSize = ZSTD_BLOCKHEADERSIZE;
typedef enum { bt_raw, bt_rle, bt_compressed, bt_reserved } blockType_e;

#define ZSTD_FRAMECHECKSUMSIZE 4

#define MIN_SEQUENCES_SIZE 1 /* nbSeq==0 */
#define MIN_CBLOCK_SIZE (1 /*litCSize*/ + 1 /* RLE or RAW */)   /* for a non-null block */
#define MIN_LITERALS_FOR_4_STREAMS 6

typedef enum { set_basic, set_rle, set_compressed, set_repeat } SymbolEncodingType_e;

#define LONGNBSEQ 0x7F00

#define MINMATCH 3

#define Litbits  8
#define LitHufLog 11
#define MaxLit ((1<<Litbits) - 1)
#define MaxML   52
#define MaxLL   35
#define DefaultMaxOff 28
#define MaxOff  31
#define MaxSeq MAX(MaxLL, MaxML)   /* Assumption : MaxOff < MaxLL,MaxML */
#define MLFSELog    9
#define LLFSELog    9
#define OffFSELog   8
#define MaxFSELog  MAX(MAX(MLFSELog, LLFSELog), OffFSELog)
#define MaxMLBits 16
#define MaxLLBits 16

#define ZSTD_MAX_HUF_HEADER_SIZE 128 /* header + <= 127 byte tree description */

#define ZSTD_MAX_FSE_HEADERS_SIZE (((MaxML + 1) * MLFSELog + (MaxLL + 1) * LLFSELog + (MaxOff + 1) * OffFSELog + 7) / 8)

static UNUSED_ATTR const U8 LL_bits[MaxLL+1] = {
     0, 0, 0, 0, 0, 0, 0, 0,
     0, 0, 0, 0, 0, 0, 0, 0,
     1, 1, 1, 1, 2, 2, 3, 3,
     4, 6, 7, 8, 9,10,11,12,
    13,14,15,16
};
static UNUSED_ATTR const S16 LL_defaultNorm[MaxLL+1] = {
     4, 3, 2, 2, 2, 2, 2, 2,
     2, 2, 2, 2, 2, 1, 1, 1,
     2, 2, 2, 2, 2, 2, 2, 2,
     2, 3, 2, 1, 1, 1, 1, 1,
    -1,-1,-1,-1
};
#define LL_DEFAULTNORMLOG 6  /* for static allocation */
static UNUSED_ATTR const U32 LL_defaultNormLog = LL_DEFAULTNORMLOG;

static UNUSED_ATTR const U8 ML_bits[MaxML+1] = {
     0, 0, 0, 0, 0, 0, 0, 0,
     0, 0, 0, 0, 0, 0, 0, 0,
     0, 0, 0, 0, 0, 0, 0, 0,
     0, 0, 0, 0, 0, 0, 0, 0,
     1, 1, 1, 1, 2, 2, 3, 3,
     4, 4, 5, 7, 8, 9,10,11,
    12,13,14,15,16
};
static UNUSED_ATTR const S16 ML_defaultNorm[MaxML+1] = {
     1, 4, 3, 2, 2, 2, 2, 2,
     2, 1, 1, 1, 1, 1, 1, 1,
     1, 1, 1, 1, 1, 1, 1, 1,
     1, 1, 1, 1, 1, 1, 1, 1,
     1, 1, 1, 1, 1, 1, 1, 1,
     1, 1, 1, 1, 1, 1,-1,-1,
    -1,-1,-1,-1,-1
};
#define ML_DEFAULTNORMLOG 6  /* for static allocation */
static UNUSED_ATTR const U32 ML_defaultNormLog = ML_DEFAULTNORMLOG;

static UNUSED_ATTR const S16 OF_defaultNorm[DefaultMaxOff+1] = {
     1, 1, 1, 1, 1, 1, 2, 2,
     2, 1, 1, 1, 1, 1, 1, 1,
     1, 1, 1, 1, 1, 1, 1, 1,
    -1,-1,-1,-1,-1
};
#define OF_DEFAULTNORMLOG 5  /* for static allocation */
static UNUSED_ATTR const U32 OF_defaultNormLog = OF_DEFAULTNORMLOG;



static void ZSTD_copy8(void* dst, const void* src) {
#if defined(ZSTD_ARCH_ARM_NEON) && !defined(__aarch64__)
    vst1_u8((uint8_t*)dst, vld1_u8((const uint8_t*)src));
#else
    ZSTD_memcpy(dst, src, 8);
#endif
}
#define COPY8(d,s) do { ZSTD_copy8(d,s); d+=8; s+=8; } while (0)


static void ZSTD_copy16(void* dst, const void* src) {
#if defined(ZSTD_ARCH_ARM_NEON)
    vst1q_u8((uint8_t*)dst, vld1q_u8((const uint8_t*)src));
#elif defined(ZSTD_ARCH_X86_SSE2)
    _mm_storeu_si128((__m128i*)dst, _mm_loadu_si128((const __m128i*)src));
#elif defined(ZSTD_ARCH_RISCV_RVV)
    __riscv_vse8_v_u8m1((uint8_t*)dst, __riscv_vle8_v_u8m1((const uint8_t*)src, 16), 16);
#elif defined(__clang__)
    ZSTD_memmove(dst, src, 16);
#else

    BYTE copy16_buf[16];
    ZSTD_memcpy(copy16_buf, src, 16);
    ZSTD_memcpy(dst, copy16_buf, 16);
#endif
}
#define COPY16(d,s) do { ZSTD_copy16(d,s); d+=16; s+=16; } while (0)

#define WILDCOPY_OVERLENGTH 32
#define WILDCOPY_VECLEN 16

typedef enum {
    ZSTD_no_overlap,
    ZSTD_overlap_src_before_dst

} ZSTD_overlap_e;


MEM_STATIC FORCE_INLINE_ATTR
void ZSTD_wildcopy(void* dst, const void* src, size_t length, ZSTD_overlap_e const ovtype)
{
    ptrdiff_t diff = (BYTE*)dst - (const BYTE*)src;
    const BYTE* ip = (const BYTE*)src;
    BYTE* op = (BYTE*)dst;
    BYTE* const oend = op + length;

    if (ovtype == ZSTD_overlap_src_before_dst && diff < WILDCOPY_VECLEN) {

        do {
            COPY8(op, ip);
        } while (op < oend);
    } else {
        assert(diff >= WILDCOPY_VECLEN || diff <= -WILDCOPY_VECLEN);

        ZSTD_copy16(op, ip);
        if (16 >= length) return;
        op += 16;
        ip += 16;
        do {
            COPY16(op, ip);
            COPY16(op, ip);
        }
        while (op < oend);
    }
}

MEM_STATIC size_t ZSTD_limitCopy(void* dst, size_t dstCapacity, const void* src, size_t srcSize)
{
    size_t const length = MIN(dstCapacity, srcSize);
    if (length > 0) {
        ZSTD_memcpy(dst, src, length);
    }
    return length;
}


#define ZSTD_WORKSPACETOOLARGE_FACTOR 3


#define ZSTD_WORKSPACETOOLARGE_MAXDURATION 128


typedef enum {
    ZSTD_bm_buffered = 0,  /* Buffer the input/output */
    ZSTD_bm_stable = 1     /* ZSTD_inBuffer/ZSTD_outBuffer is stable */
} ZSTD_bufferMode_e;





typedef struct {
    size_t nbBlocks;
    size_t compressedSize;
    unsigned long long decompressedBound;
} ZSTD_frameSizeInfo;   /* decompress & legacy */


void ZSTD_invalidateRepCodes(ZSTD_CCtx* cctx);   /* zstdmt, adaptive_compression (shouldn't get this definition from here) */


typedef struct {
    blockType_e blockType;
    U32 lastBlock;
    U32 origSize;
} blockProperties_t;   /* declared here for decompress and fullbench */



size_t ZSTD_getcBlockSize(const void* src, size_t srcSize,
                          blockProperties_t* bpPtr);



size_t ZSTD_decodeSeqHeaders(ZSTD_DCtx* dctx, int* nbSeqPtr,
                       const void* src, size_t srcSize);


MEM_STATIC int ZSTD_cpuSupportsBmi2(void)
{
    ZSTD_cpuid_t cpuid = ZSTD_cpuid();
    return ZSTD_cpuid_bmi1(cpuid) && ZSTD_cpuid_bmi2(cpuid);
}

#endif   /* ZSTD_CCOMMON_H_MODULE */
/**** ended inlining zstd_internal.h ****/



unsigned ZSTD_versionNumber(void) { return ZSTD_VERSION_NUMBER; }

const char* ZSTD_versionString(void) { return ZSTD_VERSION_STRING; }



#undef ZSTD_isError   /* defined within zstd_internal.h */

unsigned ZSTD_isError(size_t code) { return ERR_isError(code); }


const char* ZSTD_getErrorName(size_t code) { return ERR_getErrorName(code); }


ZSTD_ErrorCode ZSTD_getErrorCode(size_t code) { return ERR_getErrorCode(code); }


const char* ZSTD_getErrorString(ZSTD_ErrorCode code) { return ERR_getErrorString(code); }

int ZSTD_isDeterministicBuild(void)
{
#if ZSTD_IS_DETERMINISTIC_BUILD
    return 1;
#else
    return 0;
#endif
}
/**** ended inlining common/zstd_common.c ****/

/**** start inlining compress/fse_compress.c ****/
/* ******************************************************************
 * FSE : Finite State Entropy encoder
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 *  You can contact the author at :
 *  - FSE source repository : https://github.com/Cyan4973/FiniteStateEntropy
 *  - Public forum : https://groups.google.com/forum/#!forum/lz4c
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
****************************************************************** */


/**** skipping file: ../common/compiler.h ****/
/**** skipping file: ../common/mem.h ****/
/**** skipping file: ../common/debug.h ****/
/**** start inlining hist.h ****/
/* ******************************************************************
 * hist : Histogram functions
 * part of Finite State Entropy project
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 *  You can contact the author at :
 *  - FSE source repository : https://github.com/Cyan4973/FiniteStateEntropy
 *  - Public forum : https://groups.google.com/forum/#!forum/lz4c
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
****************************************************************** */


/**** skipping file: ../common/zstd_deps.h ****/





size_t HIST_count(unsigned* count, unsigned* maxSymbolValuePtr,
                  const void* src, size_t srcSize);

unsigned HIST_isError(size_t code);  /**< tells if a return value is an error code */




#if defined(__ARM_FEATURE_SVE2)
#define HIST_WKSP_SIZE_U32 0
#else
#define HIST_WKSP_SIZE_U32 1024
#endif
#define HIST_WKSP_SIZE    (HIST_WKSP_SIZE_U32 * sizeof(unsigned))

size_t HIST_count_wksp(unsigned* count, unsigned* maxSymbolValuePtr,
                       const void* src, size_t srcSize,
                       void* workSpace, size_t workSpaceSize);


size_t HIST_countFast(unsigned* count, unsigned* maxSymbolValuePtr,
                      const void* src, size_t srcSize);


size_t HIST_countFast_wksp(unsigned* count, unsigned* maxSymbolValuePtr,
                           const void* src, size_t srcSize,
                           void* workSpace, size_t workSpaceSize);


unsigned HIST_count_simple(unsigned* count, unsigned* maxSymbolValuePtr,
                           const void* src, size_t srcSize);


void HIST_add(unsigned* count, const void* src, size_t srcSize);
/**** ended inlining hist.h ****/
/**** skipping file: ../common/bitstream.h ****/
#define FSE_STATIC_LINKING_ONLY
/**** skipping file: ../common/fse.h ****/
/**** skipping file: ../common/error_private.h ****/
#define ZSTD_DEPS_NEED_MALLOC
#define ZSTD_DEPS_NEED_MATH64
/**** skipping file: ../common/zstd_deps.h ****/
/**** skipping file: ../common/bits.h ****/



#define FSE_isError ERR_isError






#ifndef FSE_FUNCTION_EXTENSION
#  error "FSE_FUNCTION_EXTENSION must be defined"
#endif
#ifndef FSE_FUNCTION_TYPE
#  error "FSE_FUNCTION_TYPE must be defined"
#endif


#define FSE_CAT(X,Y) X##Y
#define FSE_FUNCTION_NAME(X,Y) FSE_CAT(X,Y)
#define FSE_TYPE_NAME(X,Y) FSE_CAT(X,Y)





size_t FSE_buildCTable_wksp(FSE_CTable* ct,
                      const short* normalizedCounter, unsigned maxSymbolValue, unsigned tableLog,
                            void* workSpace, size_t wkspSize)
{
    U32 const tableSize = 1 << tableLog;
    U32 const tableMask = tableSize - 1;
    void* const ptr = ct;
    U16* const tableU16 = ( (U16*) ptr) + 2;
    void* const FSCT = ((U32*)ptr) + 1 /* header */ + (tableLog ? tableSize>>1 : 1) ;
    FSE_symbolCompressionTransform* const symbolTT = (FSE_symbolCompressionTransform*) (FSCT);
    U32 const step = FSE_TABLESTEP(tableSize);
    U32 const maxSV1 = maxSymbolValue+1;

    U16* cumul = (U16*)workSpace;   /* size = maxSV1 */
    FSE_FUNCTION_TYPE* const tableSymbol = (FSE_FUNCTION_TYPE*)(cumul + (maxSV1+1));  /* size = tableSize */

    U32 highThreshold = tableSize-1;

    assert(((size_t)workSpace & 1) == 0);  /* Must be 2 bytes-aligned */
    if (FSE_BUILD_CTABLE_WORKSPACE_SIZE(maxSymbolValue, tableLog) > wkspSize) return ERROR(tableLog_tooLarge);

    tableU16[-2] = (U16) tableLog;
    tableU16[-1] = (U16) maxSymbolValue;
    assert(tableLog < 16);   /* required for threshold strategy to work */



     #ifdef __clang_analyzer__
     ZSTD_memset(tableSymbol, 0, sizeof(*tableSymbol) * tableSize);   /* useless initialization, just to keep scan-build happy */
     #endif


    {   U32 u;
        cumul[0] = 0;
        for (u=1; u <= maxSV1; u++) {
            if (normalizedCounter[u-1]==-1) {  /* Low proba symbol */
                cumul[u] = cumul[u-1] + 1;
                tableSymbol[highThreshold--] = (FSE_FUNCTION_TYPE)(u-1);
            } else {
                assert(normalizedCounter[u-1] >= 0);
                cumul[u] = cumul[u-1] + (U16)normalizedCounter[u-1];
                assert(cumul[u] >= cumul[u-1]);  /* no overflow */
        }   }
        cumul[maxSV1] = (U16)(tableSize+1);
    }


    if (highThreshold == tableSize - 1) {

        BYTE* const spread = tableSymbol + tableSize; /* size = tableSize + 8 (may write beyond tableSize) */
        {   U64 const add = 0x0101010101010101ull;
            size_t pos = 0;
            U64 sv = 0;
            U32 s;
            for (s=0; s<maxSV1; ++s, sv += add) {
                int i;
                int const n = normalizedCounter[s];
                MEM_write64(spread + pos, sv);
                for (i = 8; i < n; i += 8) {
                    MEM_write64(spread + pos + i, sv);
                }
                assert(n>=0);
                pos += (size_t)n;
            }
        }

        {   size_t position = 0;
            size_t s;
            size_t const unroll = 2; /* Experimentally determined optimal unroll */
            assert(tableSize % unroll == 0); /* FSE_MIN_TABLELOG is 5 */
            for (s = 0; s < (size_t)tableSize; s += unroll) {
                size_t u;
                for (u = 0; u < unroll; ++u) {
                    size_t const uPosition = (position + (u * step)) & tableMask;
                    tableSymbol[uPosition] = spread[s + u];
                }
                position = (position + (unroll * step)) & tableMask;
            }
            assert(position == 0);   /* Must have initialized all positions */
        }
    } else {
        U32 position = 0;
        U32 symbol;
        for (symbol=0; symbol<maxSV1; symbol++) {
            int nbOccurrences;
            int const freq = normalizedCounter[symbol];
            for (nbOccurrences=0; nbOccurrences<freq; nbOccurrences++) {
                tableSymbol[position] = (FSE_FUNCTION_TYPE)symbol;
                position = (position + step) & tableMask;
                while (position > highThreshold)
                    position = (position + step) & tableMask;   /* Low proba area */
        }   }
        assert(position==0);  /* Must have initialized all positions */
    }


    {   U32 u; for (u=0; u<tableSize; u++) {
        FSE_FUNCTION_TYPE s = tableSymbol[u];   /* note : static analyzer may not understand tableSymbol is properly initialized */
        tableU16[cumul[s]++] = (U16) (tableSize+u);   /* TableU16 : sorted by symbol order; gives next state value */
    }   }


    {   unsigned total = 0;
        unsigned s;
        for (s=0; s<=maxSymbolValue; s++) {
            switch (normalizedCounter[s])
            {
            case  0:

                symbolTT[s].deltaNbBits = ((tableLog+1) << 16) - (1<<tableLog);
                break;

            case -1:
            case  1:
                symbolTT[s].deltaNbBits = (tableLog << 16) - (1<<tableLog);
                assert(total <= INT_MAX);
                symbolTT[s].deltaFindState = (int)(total - 1);
                total ++;
                break;
            default :
                assert(normalizedCounter[s] > 1);
                {   U32 const maxBitsOut = tableLog - ZSTD_highbit32 ((U32)normalizedCounter[s]-1);
                    U32 const minStatePlus = (U32)normalizedCounter[s] << maxBitsOut;
                    symbolTT[s].deltaNbBits = (maxBitsOut << 16) - minStatePlus;
                    symbolTT[s].deltaFindState = (int)(total - (unsigned)normalizedCounter[s]);
                    total +=  (unsigned)normalizedCounter[s];
    }   }   }   }

#if 0  /* debug : symbol costs */
    DEBUGLOG(5, "\n --- table statistics : ");
    {   U32 symbol;
        for (symbol=0; symbol<=maxSymbolValue; symbol++) {
            DEBUGLOG(5, "%3u: w=%3i,   maxBits=%u, fracBits=%.2f",
                symbol, normalizedCounter[symbol],
                FSE_getMaxNbBits(symbolTT, symbol),
                (double)FSE_bitCost(symbolTT, tableLog, symbol, 8) / 256);
    }   }
#endif

    return 0;
}



#ifndef FSE_COMMONDEFS_ONLY


size_t FSE_NCountWriteBound(unsigned maxSymbolValue, unsigned tableLog)
{
    size_t const maxHeaderSize = (((maxSymbolValue+1) * tableLog
                                   + 4 /* bitCount initialized at 4 */
                                   + 2 /* first two symbols may use one additional bit each */) / 8)
                                   + 1 /* round up to whole nb bytes */
                                   + 2 /* additional two bytes for bitstream flush */;
    return maxSymbolValue ? maxHeaderSize : FSE_NCOUNTBOUND;  /* maxSymbolValue==0 ? use default */
}

static size_t
FSE_writeNCount_generic (void* header, size_t headerBufferSize,
                   const short* normalizedCounter, unsigned maxSymbolValue, unsigned tableLog,
                         unsigned writeIsSafe)
{
    BYTE* const ostart = (BYTE*) header;
    BYTE* out = ostart;
    BYTE* const oend = ostart + headerBufferSize;
    int nbBits;
    const int tableSize = 1 << tableLog;
    int remaining;
    int threshold;
    U32 bitStream = 0;
    int bitCount = 0;
    unsigned symbol = 0;
    unsigned const alphabetSize = maxSymbolValue + 1;
    int previousIs0 = 0;


    bitStream += (tableLog-FSE_MIN_TABLELOG) << bitCount;
    bitCount  += 4;


    remaining = tableSize+1;   /* +1 for extra accuracy */
    threshold = tableSize;
    nbBits = (int)tableLog+1;

    while ((symbol < alphabetSize) && (remaining>1)) {  /* stops at 1 */
        if (previousIs0) {
            unsigned start = symbol;
            while ((symbol < alphabetSize) && !normalizedCounter[symbol]) symbol++;
            if (symbol == alphabetSize) break;   /* incorrect distribution */
            while (symbol >= start+24) {
                start+=24;
                bitStream += 0xFFFFU << bitCount;
                if ((!writeIsSafe) && (out > oend-2))
                    return ERROR(dstSize_tooSmall);   /* Buffer overflow */
                out[0] = (BYTE) bitStream;
                out[1] = (BYTE)(bitStream>>8);
                out+=2;
                bitStream>>=16;
            }
            while (symbol >= start+3) {
                start+=3;
                bitStream += 3U << bitCount;
                bitCount += 2;
            }
            bitStream += (symbol-start) << bitCount;
            bitCount += 2;
            if (bitCount>16) {
                if ((!writeIsSafe) && (out > oend - 2))
                    return ERROR(dstSize_tooSmall);   /* Buffer overflow */
                out[0] = (BYTE)bitStream;
                out[1] = (BYTE)(bitStream>>8);
                out += 2;
                bitStream >>= 16;
                bitCount -= 16;
        }   }
        {   int count = normalizedCounter[symbol++];
            int const max = (2*threshold-1) - remaining;
            remaining -= count < 0 ? -count : count;
            count++;   /* +1 for extra accuracy */
            if (count>=threshold)
                count += max;   /* [0..max[ [max..threshold[ (...) [threshold+max 2*threshold[ */
            bitStream += (U32)count << bitCount;
            bitCount  += nbBits;
            bitCount  -= (count<max);
            previousIs0  = (count==1);
            if (remaining<1) return ERROR(GENERIC);
            while (remaining<threshold) { nbBits--; threshold>>=1; }
        }
        if (bitCount>16) {
            if ((!writeIsSafe) && (out > oend - 2))
                return ERROR(dstSize_tooSmall);   /* Buffer overflow */
            out[0] = (BYTE)bitStream;
            out[1] = (BYTE)(bitStream>>8);
            out += 2;
            bitStream >>= 16;
            bitCount -= 16;
    }   }

    if (remaining != 1)
        return ERROR(GENERIC);  /* incorrect normalized distribution */
    assert(symbol <= alphabetSize);


    if ((!writeIsSafe) && (out > oend - 2))
        return ERROR(dstSize_tooSmall);   /* Buffer overflow */
    out[0] = (BYTE)bitStream;
    out[1] = (BYTE)(bitStream>>8);
    out+= (bitCount+7) /8;

    assert(out >= ostart);
    return (size_t)(out-ostart);
}


size_t FSE_writeNCount (void* buffer, size_t bufferSize,
                  const short* normalizedCounter, unsigned maxSymbolValue, unsigned tableLog)
{
    if (tableLog > FSE_MAX_TABLELOG) return ERROR(tableLog_tooLarge);   /* Unsupported */
    if (tableLog < FSE_MIN_TABLELOG) return ERROR(GENERIC);   /* Unsupported */

    if (bufferSize < FSE_NCountWriteBound(maxSymbolValue, tableLog))
        return FSE_writeNCount_generic(buffer, bufferSize, normalizedCounter, maxSymbolValue, tableLog, 0);

    return FSE_writeNCount_generic(buffer, bufferSize, normalizedCounter, maxSymbolValue, tableLog, 1 /* write in buffer is safe */);
}





static unsigned FSE_minTableLog(size_t srcSize, unsigned maxSymbolValue)
{
    U32 minBitsSrc = ZSTD_highbit32((U32)(srcSize)) + 1;
    U32 minBitsSymbols = ZSTD_highbit32(maxSymbolValue) + 2;
    U32 minBits = minBitsSrc < minBitsSymbols ? minBitsSrc : minBitsSymbols;
    assert(srcSize > 1); /* Not supported, RLE should be used instead */
    return minBits;
}

unsigned FSE_optimalTableLog_internal(unsigned maxTableLog, size_t srcSize, unsigned maxSymbolValue, unsigned minus)
{
    U32 maxBitsSrc = ZSTD_highbit32((U32)(srcSize - 1)) - minus;
    U32 tableLog = maxTableLog;
    U32 minBits = FSE_minTableLog(srcSize, maxSymbolValue);
    assert(srcSize > 1); /* Not supported, RLE should be used instead */
    if (tableLog==0) tableLog = FSE_DEFAULT_TABLELOG;
    if (maxBitsSrc < tableLog) tableLog = maxBitsSrc;   /* Accuracy can be reduced */
    if (minBits > tableLog) tableLog = minBits;   /* Need a minimum to safely represent all symbol values */
    if (tableLog < FSE_MIN_TABLELOG) tableLog = FSE_MIN_TABLELOG;
    if (tableLog > FSE_MAX_TABLELOG) tableLog = FSE_MAX_TABLELOG;
    return tableLog;
}

unsigned FSE_optimalTableLog(unsigned maxTableLog, size_t srcSize, unsigned maxSymbolValue)
{
    return FSE_optimalTableLog_internal(maxTableLog, srcSize, maxSymbolValue, 2);
}



static size_t FSE_normalizeM2(short* norm, U32 tableLog, const unsigned* count, size_t total, U32 maxSymbolValue, short lowProbCount)
{
    short const NOT_YET_ASSIGNED = -2;
    U32 s;
    U32 distributed = 0;
    U32 ToDistribute;


    U32 const lowThreshold = (U32)(total >> tableLog);
    U32 lowOne = (U32)((total * 3) >> (tableLog + 1));

    for (s=0; s<=maxSymbolValue; s++) {
        if (count[s] == 0) {
            norm[s]=0;
            continue;
        }
        if (count[s] <= lowThreshold) {
            norm[s] = lowProbCount;
            distributed++;
            total -= count[s];
            continue;
        }
        if (count[s] <= lowOne) {
            norm[s] = 1;
            distributed++;
            total -= count[s];
            continue;
        }

        norm[s]=NOT_YET_ASSIGNED;
    }
    ToDistribute = (1 << tableLog) - distributed;

    if (ToDistribute == 0)
        return 0;

    if ((total / ToDistribute) > lowOne) {

        lowOne = (U32)((total * 3) / (ToDistribute * 2));
        for (s=0; s<=maxSymbolValue; s++) {
            if ((norm[s] == NOT_YET_ASSIGNED) && (count[s] <= lowOne)) {
                norm[s] = 1;
                distributed++;
                total -= count[s];
                continue;
        }   }
        ToDistribute = (1 << tableLog) - distributed;
    }

    if (distributed == maxSymbolValue+1) {

        U32 maxV = 0, maxC = 0;
        for (s=0; s<=maxSymbolValue; s++)
            if (count[s] > maxC) { maxV=s; maxC=count[s]; }
        norm[maxV] += (short)ToDistribute;
        return 0;
    }

    if (total == 0) {

        for (s=0; ToDistribute > 0; s = (s+1)%(maxSymbolValue+1))
            if (norm[s] > 0) { ToDistribute--; norm[s]++; }
        return 0;
    }

    {   U64 const vStepLog = 62 - tableLog;
        U64 const mid = (1ULL << (vStepLog-1)) - 1;
        U64 const rStep = ZSTD_div64((((U64)1<<vStepLog) * ToDistribute) + mid, (U32)total);   /* scale on remaining */
        U64 tmpTotal = mid;
        for (s=0; s<=maxSymbolValue; s++) {
            if (norm[s]==NOT_YET_ASSIGNED) {
                U64 const end = tmpTotal + (count[s] * rStep);
                U32 const sStart = (U32)(tmpTotal >> vStepLog);
                U32 const sEnd = (U32)(end >> vStepLog);
                U32 const weight = sEnd - sStart;
                if (weight < 1)
                    return ERROR(GENERIC);
                norm[s] = (short)weight;
                tmpTotal = end;
    }   }   }

    return 0;
}

size_t FSE_normalizeCount (short* normalizedCounter, unsigned tableLog,
                           const unsigned* count, size_t total,
                           unsigned maxSymbolValue, unsigned useLowProbCount)
{

    if (tableLog==0) tableLog = FSE_DEFAULT_TABLELOG;
    if (tableLog < FSE_MIN_TABLELOG) return ERROR(GENERIC);   /* Unsupported size */
    if (tableLog > FSE_MAX_TABLELOG) return ERROR(tableLog_tooLarge);   /* Unsupported size */
    if (tableLog < FSE_minTableLog(total, maxSymbolValue)) return ERROR(GENERIC);   /* Too small tableLog, compression potentially impossible */

    {   static U32 const rtbTable[] = {     0, 473195, 504333, 520860, 550000, 700000, 750000, 830000 };
        short const lowProbCount = useLowProbCount ? -1 : 1;
        U64 const scale = 62 - tableLog;
        U64 const step = ZSTD_div64((U64)1<<62, (U32)total);   /* <== here, one division ! */
        U64 const vStep = 1ULL<<(scale-20);
        int stillToDistribute = 1<<tableLog;
        unsigned s;
        unsigned largest=0;
        short largestP=0;
        U32 lowThreshold = (U32)(total >> tableLog);

        for (s=0; s<=maxSymbolValue; s++) {
            if (count[s] == total) return 0;   /* rle special case */
            if (count[s] == 0) { normalizedCounter[s]=0; continue; }
            if (count[s] <= lowThreshold) {
                normalizedCounter[s] = lowProbCount;
                stillToDistribute--;
            } else {
                short proba = (short)((count[s]*step) >> scale);
                if (proba<8) {
                    U64 restToBeat = vStep * rtbTable[proba];
                    proba += (count[s]*step) - ((U64)proba<<scale) > restToBeat;
                }
                if (proba > largestP) { largestP=proba; largest=s; }
                normalizedCounter[s] = proba;
                stillToDistribute -= proba;
        }   }
        if (-stillToDistribute >= (normalizedCounter[largest] >> 1)) {

            size_t const errorCode = FSE_normalizeM2(normalizedCounter, tableLog, count, total, maxSymbolValue, lowProbCount);
            if (FSE_isError(errorCode)) return errorCode;
        }
        else normalizedCounter[largest] += (short)stillToDistribute;
    }

#if 0
    {   /* Print Table (debug) */
        U32 s;
        U32 nTotal = 0;
        for (s=0; s<=maxSymbolValue; s++)
            RAWLOG(2, "%3i: %4i \n", s, normalizedCounter[s]);
        for (s=0; s<=maxSymbolValue; s++)
            nTotal += abs(normalizedCounter[s]);
        if (nTotal != (1U<<tableLog))
            RAWLOG(2, "Warning !!! Total == %u != %u !!!", nTotal, 1U<<tableLog);
        getchar();
    }
#endif

    return tableLog;
}


size_t FSE_buildCTable_rle (FSE_CTable* ct, BYTE symbolValue)
{
    void* ptr = ct;
    U16* tableU16 = ( (U16*) ptr) + 2;
    void* FSCTptr = (U32*)ptr + 2;
    FSE_symbolCompressionTransform* symbolTT = (FSE_symbolCompressionTransform*) FSCTptr;


    tableU16[-2] = (U16) 0;
    tableU16[-1] = (U16) symbolValue;


    tableU16[0] = 0;
    tableU16[1] = 0;   /* just in case */


    symbolTT[symbolValue].deltaNbBits = 0;
    symbolTT[symbolValue].deltaFindState = 0;

    return 0;
}


static size_t FSE_compress_usingCTable_generic (void* dst, size_t dstSize,
                           const void* src, size_t srcSize,
                           const FSE_CTable* ct, const unsigned fast)
{
    const BYTE* const istart = (const BYTE*) src;
    const BYTE* const iend = istart + srcSize;
    const BYTE* ip=iend;

    BIT_CStream_t bitC;
    FSE_CState_t CState1, CState2;


    if (srcSize <= 2) return 0;
    { size_t const initError = BIT_initCStream(&bitC, dst, dstSize);
      if (FSE_isError(initError)) return 0; /* not enough space available to write a bitstream */ }

#define FSE_FLUSHBITS(s)  (fast ? BIT_flushBitsFast(s) : BIT_flushBits(s))

    if (srcSize & 1) {
        FSE_initCState2(&CState1, ct, *--ip);
        FSE_initCState2(&CState2, ct, *--ip);
        FSE_encodeSymbol(&bitC, &CState1, *--ip);
        FSE_FLUSHBITS(&bitC);
    } else {
        FSE_initCState2(&CState2, ct, *--ip);
        FSE_initCState2(&CState1, ct, *--ip);
    }


    srcSize -= 2;
    if ((sizeof(bitC.bitContainer)*8 > FSE_MAX_TABLELOG*4+7 ) && (srcSize & 2)) {  /* test bit 2 */
        FSE_encodeSymbol(&bitC, &CState2, *--ip);
        FSE_encodeSymbol(&bitC, &CState1, *--ip);
        FSE_FLUSHBITS(&bitC);
    }


    while ( ip>istart ) {

        FSE_encodeSymbol(&bitC, &CState2, *--ip);

        if (sizeof(bitC.bitContainer)*8 < FSE_MAX_TABLELOG*2+7 )   /* this test must be static */
            FSE_FLUSHBITS(&bitC);

        FSE_encodeSymbol(&bitC, &CState1, *--ip);

        if (sizeof(bitC.bitContainer)*8 > FSE_MAX_TABLELOG*4+7 ) {  /* this test must be static */
            FSE_encodeSymbol(&bitC, &CState2, *--ip);
            FSE_encodeSymbol(&bitC, &CState1, *--ip);
        }

        FSE_FLUSHBITS(&bitC);
    }

    FSE_flushCState(&bitC, &CState2);
    FSE_flushCState(&bitC, &CState1);
    return BIT_closeCStream(&bitC);
}

size_t FSE_compress_usingCTable (void* dst, size_t dstSize,
                           const void* src, size_t srcSize,
                           const FSE_CTable* ct)
{
    unsigned const fast = (dstSize >= FSE_BLOCKBOUND(srcSize));

    if (fast)
        return FSE_compress_usingCTable_generic(dst, dstSize, src, srcSize, ct, 1);
    else
        return FSE_compress_usingCTable_generic(dst, dstSize, src, srcSize, ct, 0);
}


size_t FSE_compressBound(size_t size) { return FSE_COMPRESSBOUND(size); }

#endif   /* FSE_COMMONDEFS_ONLY */
/**** ended inlining compress/fse_compress.c ****/
/**** start inlining compress/hist.c ****/
/* ******************************************************************
 * hist : Histogram functions
 * part of Finite State Entropy project
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 *  You can contact the author at :
 *  - FSE source repository : https://github.com/Cyan4973/FiniteStateEntropy
 *  - Public forum : https://groups.google.com/forum/#!forum/lz4c
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
****************************************************************** */


/**** skipping file: ../common/mem.h ****/
/**** skipping file: ../common/debug.h ****/
/**** skipping file: ../common/error_private.h ****/
/**** skipping file: hist.h ****/

#if defined(ZSTD_ARCH_ARM_SVE2)
#define HIST_FAST_THRESHOLD 500
#else
#define HIST_FAST_THRESHOLD 1500
#endif



unsigned HIST_isError(size_t code) { return ERR_isError(code); }


void HIST_add(unsigned* count, const void* src, size_t srcSize)
{
    const BYTE* ip = (const BYTE*)src;
    const BYTE* const end = ip + srcSize;

    while (ip<end) {
        count[*ip++]++;
    }
}

unsigned HIST_count_simple(unsigned* count, unsigned* maxSymbolValuePtr,
                           const void* src, size_t srcSize)
{
    const BYTE* ip = (const BYTE*)src;
    const BYTE* const end = ip + srcSize;
    unsigned maxSymbolValue = *maxSymbolValuePtr;
    unsigned largestCount=0;

    ZSTD_memset(count, 0, (maxSymbolValue+1) * sizeof(*count));
    if (srcSize==0) { *maxSymbolValuePtr = 0; return 0; }

    while (ip<end) {
        assert(*ip <= maxSymbolValue);
        count[*ip++]++;
    }

    while (!count[maxSymbolValue]) maxSymbolValue--;
    *maxSymbolValuePtr = maxSymbolValue;

    {   U32 s;
        for (s=0; s<=maxSymbolValue; s++)
            if (count[s] > largestCount) largestCount = count[s];
    }

    return largestCount;
}

typedef enum { trustInput, checkMaxSymbolValue } HIST_checkInput_e;

#if defined(ZSTD_ARCH_ARM_SVE2)

#define HIST_SVE2_MAX_CHUNK_SIZE ((1U << 16) - 16)
FORCE_INLINE_TEMPLATE size_t min_size(size_t a, size_t b) { return a < b ? a : b; }

static
svuint16_t HIST_count_6_sve2(const BYTE* const src, size_t size, U32* const dst,
                             const svuint8_t c0, const svuint8_t c1,
                             const svuint8_t c2, const svuint8_t c3,
                             const svuint8_t c4, const svuint8_t c5,
                             const svuint16_t histmax, size_t maxCount)
{
    const svbool_t vl128 = svptrue_pat_b8(SV_VL16);
    svuint16_t hh0 = svdup_n_u16(0);
    svuint16_t hh1 = svdup_n_u16(0);
    svuint16_t hh2 = svdup_n_u16(0);
    svuint16_t hh3 = svdup_n_u16(0);
    svuint16_t hh4 = svdup_n_u16(0);
    svuint16_t hh5 = svdup_n_u16(0);
    svuint16_t hh6 = svdup_n_u16(0);
    svuint16_t hh7 = svdup_n_u16(0);
    svuint16_t hh8 = svdup_n_u16(0);
    svuint16_t hh9 = svdup_n_u16(0);
    svuint16_t hha = svdup_n_u16(0);
    svuint16_t hhb = svdup_n_u16(0);

    size_t i = 0;
    while (i < size) {

        const size_t size240 = min_size(i + 240, size);

        svbool_t pred = svwhilelt_b8_u64(i, size);
        svuint8_t c = svld1rq_u8(pred, src + i);
        svuint8_t h0 = svhistseg_u8(c0, c);
        svuint8_t h1 = svhistseg_u8(c1, c);
        svuint8_t h2 = svhistseg_u8(c2, c);
        svuint8_t h3 = svhistseg_u8(c3, c);
        svuint8_t h4 = svhistseg_u8(c4, c);
        svuint8_t h5 = svhistseg_u8(c5, c);

        for (i += 16; i < size240; i += 16) {
            pred = svwhilelt_b8_u64(i, size);
            c = svld1rq_u8(pred, src + i);
            h0 = svadd_u8_x(vl128, h0, svhistseg_u8(c0, c));
            h1 = svadd_u8_x(vl128, h1, svhistseg_u8(c1, c));
            h2 = svadd_u8_x(vl128, h2, svhistseg_u8(c2, c));
            h3 = svadd_u8_x(vl128, h3, svhistseg_u8(c3, c));
            h4 = svadd_u8_x(vl128, h4, svhistseg_u8(c4, c));
            h5 = svadd_u8_x(vl128, h5, svhistseg_u8(c5, c));
        }

        hh0 = svaddwb_u16(hh0, h0);
        hh1 = svaddwt_u16(hh1, h0);
        hh2 = svaddwb_u16(hh2, h1);
        hh3 = svaddwt_u16(hh3, h1);
        hh4 = svaddwb_u16(hh4, h2);
        hh5 = svaddwt_u16(hh5, h2);
        hh6 = svaddwb_u16(hh6, h3);
        hh7 = svaddwt_u16(hh7, h3);
        hh8 = svaddwb_u16(hh8, h4);
        hh9 = svaddwt_u16(hh9, h4);
        hha = svaddwb_u16(hha, h5);
        hhb = svaddwt_u16(hhb, h5);
    }

    svst1_u32(svwhilelt_b32_u64( 0, maxCount), dst +  0, svshllb_n_u32(hh0, 0));
    svst1_u32(svwhilelt_b32_u64( 4, maxCount), dst +  4, svshllt_n_u32(hh0, 0));
    svst1_u32(svwhilelt_b32_u64( 8, maxCount), dst +  8, svshllb_n_u32(hh1, 0));
    svst1_u32(svwhilelt_b32_u64(12, maxCount), dst + 12, svshllt_n_u32(hh1, 0));
    svst1_u32(svwhilelt_b32_u64(16, maxCount), dst + 16, svshllb_n_u32(hh2, 0));
    svst1_u32(svwhilelt_b32_u64(20, maxCount), dst + 20, svshllt_n_u32(hh2, 0));
    svst1_u32(svwhilelt_b32_u64(24, maxCount), dst + 24, svshllb_n_u32(hh3, 0));
    svst1_u32(svwhilelt_b32_u64(28, maxCount), dst + 28, svshllt_n_u32(hh3, 0));
    svst1_u32(svwhilelt_b32_u64(32, maxCount), dst + 32, svshllb_n_u32(hh4, 0));
    svst1_u32(svwhilelt_b32_u64(36, maxCount), dst + 36, svshllt_n_u32(hh4, 0));
    svst1_u32(svwhilelt_b32_u64(40, maxCount), dst + 40, svshllb_n_u32(hh5, 0));
    svst1_u32(svwhilelt_b32_u64(44, maxCount), dst + 44, svshllt_n_u32(hh5, 0));
    svst1_u32(svwhilelt_b32_u64(48, maxCount), dst + 48, svshllb_n_u32(hh6, 0));
    svst1_u32(svwhilelt_b32_u64(52, maxCount), dst + 52, svshllt_n_u32(hh6, 0));
    svst1_u32(svwhilelt_b32_u64(56, maxCount), dst + 56, svshllb_n_u32(hh7, 0));
    svst1_u32(svwhilelt_b32_u64(60, maxCount), dst + 60, svshllt_n_u32(hh7, 0));
    svst1_u32(svwhilelt_b32_u64(64, maxCount), dst + 64, svshllb_n_u32(hh8, 0));
    svst1_u32(svwhilelt_b32_u64(68, maxCount), dst + 68, svshllt_n_u32(hh8, 0));
    svst1_u32(svwhilelt_b32_u64(72, maxCount), dst + 72, svshllb_n_u32(hh9, 0));
    svst1_u32(svwhilelt_b32_u64(76, maxCount), dst + 76, svshllt_n_u32(hh9, 0));
    svst1_u32(svwhilelt_b32_u64(80, maxCount), dst + 80, svshllb_n_u32(hha, 0));
    svst1_u32(svwhilelt_b32_u64(84, maxCount), dst + 84, svshllt_n_u32(hha, 0));
    svst1_u32(svwhilelt_b32_u64(88, maxCount), dst + 88, svshllb_n_u32(hhb, 0));
    svst1_u32(svwhilelt_b32_u64(92, maxCount), dst + 92, svshllt_n_u32(hhb, 0));

    hh0 = svmax_u16_x(vl128, hh0, hh1);
    hh2 = svmax_u16_x(vl128, hh2, hh3);
    hh4 = svmax_u16_x(vl128, hh4, hh5);
    hh6 = svmax_u16_x(vl128, hh6, hh7);
    hh8 = svmax_u16_x(vl128, hh8, hh9);
    hha = svmax_u16_x(vl128, hha, hhb);
    hh0 = svmax_u16_x(vl128, hh0, hh2);
    hh4 = svmax_u16_x(vl128, hh4, hh6);
    hh8 = svmax_u16_x(vl128, hh8, hha);
    hh0 = svmax_u16_x(vl128, hh0, hh4);
    hh8 = svmax_u16_x(vl128, hh8, histmax);
    return svmax_u16_x(vl128, hh0, hh8);
}

static size_t HIST_count_sve2_chunk(unsigned* count, unsigned* maxSymbolValuePtr,
                                   const void* source, size_t sourceSize,
                                   HIST_checkInput_e check)
{
    const BYTE* ip = (const BYTE*)source;
    const size_t maxCount = *maxSymbolValuePtr + 1;

    assert(*maxSymbolValuePtr <= 255);
    assert(sourceSize <= HIST_SVE2_MAX_CHUNK_SIZE);
    if (!sourceSize) {
        ZSTD_memset(count, 0, maxCount * sizeof(*count));
        *maxSymbolValuePtr = 0;
        return 0;
    }

    {   const svbool_t vl128 = svptrue_pat_b8(SV_VL16);
        const svuint8_t c0 = svreinterpret_u8(svindex_u32(0x0C040800, 0x01010101));
        const svuint8_t c1 = svadd_n_u8_x(vl128, c0, 16);
        const svuint8_t c2 = svadd_n_u8_x(vl128, c0, 32);
        const svuint8_t c3 = svadd_n_u8_x(vl128, c1, 32);

        svuint8_t symbolMax = svdup_n_u8(0);
        svuint16_t hh0 = svdup_n_u16(0);
        svuint16_t hh1 = svdup_n_u16(0);
        svuint16_t hh2 = svdup_n_u16(0);
        svuint16_t hh3 = svdup_n_u16(0);
        svuint16_t hh4 = svdup_n_u16(0);
        svuint16_t hh5 = svdup_n_u16(0);
        svuint16_t hh6 = svdup_n_u16(0);
        svuint16_t hh7 = svdup_n_u16(0);
        svuint16_t max;
        size_t maxSymbolValue;

        size_t i = 0;
        while (i < sourceSize) {

            const size_t size240 = min_size(i + 240, sourceSize);

            svbool_t pred = svwhilelt_b8_u64(i, sourceSize);
            svuint8_t c = svld1rq_u8(pred, ip + i);
            svuint8_t h0 = svhistseg_u8(c0, c);
            svuint8_t h1 = svhistseg_u8(c1, c);
            svuint8_t h2 = svhistseg_u8(c2, c);
            svuint8_t h3 = svhistseg_u8(c3, c);
            symbolMax = svmax_u8_x(vl128, symbolMax, c);

            for (i += 16; i < size240; i += 16) {
                pred = svwhilelt_b8_u64(i, sourceSize);
                c = svld1rq_u8(pred, ip + i);
                h0 = svadd_u8_x(vl128, h0, svhistseg_u8(c0, c));
                h1 = svadd_u8_x(vl128, h1, svhistseg_u8(c1, c));
                h2 = svadd_u8_x(vl128, h2, svhistseg_u8(c2, c));
                h3 = svadd_u8_x(vl128, h3, svhistseg_u8(c3, c));
                symbolMax = svmax_u8_x(vl128, symbolMax, c);
            }

            hh0 = svaddwb_u16(hh0, h0);
            hh1 = svaddwt_u16(hh1, h0);
            hh2 = svaddwb_u16(hh2, h1);
            hh3 = svaddwt_u16(hh3, h1);
            hh4 = svaddwb_u16(hh4, h2);
            hh5 = svaddwt_u16(hh5, h2);
            hh6 = svaddwb_u16(hh6, h3);
            hh7 = svaddwt_u16(hh7, h3);
        }
        maxSymbolValue = svmaxv_u8(vl128, symbolMax);

        if (check && maxSymbolValue > *maxSymbolValuePtr) return ERROR(maxSymbolValue_tooSmall);
        *maxSymbolValuePtr = maxSymbolValue;


        hh0 = svsub_n_u16_m(svptrue_pat_b32(SV_VL1), hh0, -sourceSize & 15);

        svst1_u32(svwhilelt_b32_u64( 0, maxCount), count +  0, svshllb_n_u32(hh0, 0));
        svst1_u32(svwhilelt_b32_u64( 4, maxCount), count +  4, svshllt_n_u32(hh0, 0));
        svst1_u32(svwhilelt_b32_u64( 8, maxCount), count +  8, svshllb_n_u32(hh1, 0));
        svst1_u32(svwhilelt_b32_u64(12, maxCount), count + 12, svshllt_n_u32(hh1, 0));
        svst1_u32(svwhilelt_b32_u64(16, maxCount), count + 16, svshllb_n_u32(hh2, 0));
        svst1_u32(svwhilelt_b32_u64(20, maxCount), count + 20, svshllt_n_u32(hh2, 0));
        svst1_u32(svwhilelt_b32_u64(24, maxCount), count + 24, svshllb_n_u32(hh3, 0));
        svst1_u32(svwhilelt_b32_u64(28, maxCount), count + 28, svshllt_n_u32(hh3, 0));
        svst1_u32(svwhilelt_b32_u64(32, maxCount), count + 32, svshllb_n_u32(hh4, 0));
        svst1_u32(svwhilelt_b32_u64(36, maxCount), count + 36, svshllt_n_u32(hh4, 0));
        svst1_u32(svwhilelt_b32_u64(40, maxCount), count + 40, svshllb_n_u32(hh5, 0));
        svst1_u32(svwhilelt_b32_u64(44, maxCount), count + 44, svshllt_n_u32(hh5, 0));
        svst1_u32(svwhilelt_b32_u64(48, maxCount), count + 48, svshllb_n_u32(hh6, 0));
        svst1_u32(svwhilelt_b32_u64(52, maxCount), count + 52, svshllt_n_u32(hh6, 0));
        svst1_u32(svwhilelt_b32_u64(56, maxCount), count + 56, svshllb_n_u32(hh7, 0));
        svst1_u32(svwhilelt_b32_u64(60, maxCount), count + 60, svshllt_n_u32(hh7, 0));

        hh0 = svmax_u16_x(vl128, hh0, hh1);
        hh2 = svmax_u16_x(vl128, hh2, hh3);
        hh4 = svmax_u16_x(vl128, hh4, hh5);
        hh6 = svmax_u16_x(vl128, hh6, hh7);
        hh0 = svmax_u16_x(vl128, hh0, hh2);
        hh4 = svmax_u16_x(vl128, hh4, hh6);
        max = svmax_u16_x(vl128, hh0, hh4);

        maxSymbolValue = min_size(maxSymbolValue, maxCount);
        if (maxSymbolValue >= 64) {
            const svuint8_t c4 = svadd_n_u8_x(vl128, c0,  64);
            const svuint8_t c5 = svadd_n_u8_x(vl128, c1,  64);
            const svuint8_t c6 = svadd_n_u8_x(vl128, c2,  64);
            const svuint8_t c7 = svadd_n_u8_x(vl128, c3,  64);
            const svuint8_t c8 = svadd_n_u8_x(vl128, c0, 128);
            const svuint8_t c9 = svadd_n_u8_x(vl128, c1, 128);

            max = HIST_count_6_sve2(ip, sourceSize, count + 64, c4, c5, c6, c7,
                                    c8, c9, max, maxCount - 64);

            if (maxSymbolValue >= 160) {
                const svuint8_t ca = svadd_n_u8_x(vl128, c2, 128);
                const svuint8_t cb = svadd_n_u8_x(vl128, c3, 128);
                const svuint8_t cc = svadd_n_u8_x(vl128, c4, 128);
                const svuint8_t cd = svadd_n_u8_x(vl128, c5, 128);
                const svuint8_t ce = svadd_n_u8_x(vl128, c6, 128);
                const svuint8_t cf = svadd_n_u8_x(vl128, c7, 128);

                max = HIST_count_6_sve2(ip, sourceSize, count + 160, ca, cb, cc,
                                        cd, ce, cf, max, maxCount - 160);
            } else if (maxCount > 160) {
                ZSTD_memset(count + 160, 0, (maxCount - 160) * sizeof(*count));
            }
        } else if (maxCount > 64) {
            ZSTD_memset(count + 64, 0, (maxCount - 64) * sizeof(*count));
        }

        return svmaxv_u16(vl128, max);
    }
}

static size_t HIST_count_sve2(unsigned* count, unsigned* maxSymbolValuePtr,
                              const void* source, size_t sourceSize,
                              HIST_checkInput_e check)
{
    if (sourceSize <= HIST_SVE2_MAX_CHUNK_SIZE)
        return HIST_count_sve2_chunk(count, maxSymbolValuePtr, source, sourceSize, check);

    {   const BYTE* const input = (const BYTE*)source;
        unsigned const maxSymbolLimit = *maxSymbolValuePtr;
        unsigned maxSymbolValue = maxSymbolLimit;
        U32 chunkCounts[256];
        size_t largestCount = HIST_count_sve2_chunk(count, &maxSymbolValue, input,
                                                   HIST_SVE2_MAX_CHUNK_SIZE, check);
        size_t offset = HIST_SVE2_MAX_CHUNK_SIZE;
        if (HIST_isError(largestCount)) return largestCount;


        while (offset < sourceSize) {
            size_t const chunkSize = min_size(sourceSize - offset, HIST_SVE2_MAX_CHUNK_SIZE);
            unsigned chunkMaxSymbol = maxSymbolLimit;
            size_t const result = HIST_count_sve2_chunk(chunkCounts, &chunkMaxSymbol,
                                                        input + offset, chunkSize, check);
            unsigned symbol;
            if (HIST_isError(result)) return result;
            if (chunkMaxSymbol > maxSymbolValue) maxSymbolValue = chunkMaxSymbol;
            for (symbol = 0; symbol <= chunkMaxSymbol; ++symbol) {
                count[symbol] += chunkCounts[symbol];
                if (count[symbol] > largestCount) largestCount = count[symbol];
            }
            offset += chunkSize;
        }

        *maxSymbolValuePtr = maxSymbolValue;
        return largestCount;
    }
}
#endif


static UNUSED_ATTR
size_t HIST_count_parallel_wksp(unsigned* count, unsigned* maxSymbolValuePtr,
                                const void* source, size_t sourceSize,
                                HIST_checkInput_e check,
                                U32* const workSpace)
{
    const BYTE* ip = (const BYTE*)source;
    const BYTE* const iend = ip+sourceSize;
    size_t const countSize = (*maxSymbolValuePtr + 1) * sizeof(*count);
    unsigned max=0;
    U32* const Counting1 = workSpace;
    U32* const Counting2 = Counting1 + 256;
    U32* const Counting3 = Counting2 + 256;
    U32* const Counting4 = Counting3 + 256;


    assert(*maxSymbolValuePtr <= 255);
    if (!sourceSize) {
        ZSTD_memset(count, 0, countSize);
        *maxSymbolValuePtr = 0;
        return 0;
    }
    ZSTD_memset(workSpace, 0, 4*256*sizeof(unsigned));


    {   U32 cached = MEM_read32(ip); ip += 4;
        while (ip < iend-15) {
            U32 c = cached; cached = MEM_read32(ip); ip += 4;
            Counting1[(BYTE) c     ]++;
            Counting2[(BYTE)(c>>8) ]++;
            Counting3[(BYTE)(c>>16)]++;
            Counting4[       c>>24 ]++;
            c = cached; cached = MEM_read32(ip); ip += 4;
            Counting1[(BYTE) c     ]++;
            Counting2[(BYTE)(c>>8) ]++;
            Counting3[(BYTE)(c>>16)]++;
            Counting4[       c>>24 ]++;
            c = cached; cached = MEM_read32(ip); ip += 4;
            Counting1[(BYTE) c     ]++;
            Counting2[(BYTE)(c>>8) ]++;
            Counting3[(BYTE)(c>>16)]++;
            Counting4[       c>>24 ]++;
            c = cached; cached = MEM_read32(ip); ip += 4;
            Counting1[(BYTE) c     ]++;
            Counting2[(BYTE)(c>>8) ]++;
            Counting3[(BYTE)(c>>16)]++;
            Counting4[       c>>24 ]++;
        }
        ip-=4;
    }


    while (ip<iend) Counting1[*ip++]++;

    {   U32 s;
        for (s=0; s<256; s++) {
            Counting1[s] += Counting2[s] + Counting3[s] + Counting4[s];
            if (Counting1[s] > max) max = Counting1[s];
    }   }

    {   unsigned maxSymbolValue = 255;
        while (!Counting1[maxSymbolValue]) maxSymbolValue--;
        if (check && maxSymbolValue > *maxSymbolValuePtr) return ERROR(maxSymbolValue_tooSmall);
        *maxSymbolValuePtr = maxSymbolValue;
        ZSTD_memmove(count, Counting1, countSize);   /* in case count & Counting1 are overlapping */
    }
    return (size_t)max;
}


size_t HIST_countFast_wksp(unsigned* count, unsigned* maxSymbolValuePtr,
                          const void* source, size_t sourceSize,
                          void* workSpace, size_t workSpaceSize)
{
    if (sourceSize < HIST_FAST_THRESHOLD) /* heuristic threshold */
        return HIST_count_simple(count, maxSymbolValuePtr, source, sourceSize);
#if defined(ZSTD_ARCH_ARM_SVE2)
    (void)workSpace;
    (void)workSpaceSize;
    return HIST_count_sve2(count, maxSymbolValuePtr, source, sourceSize, trustInput);
#else
    if ((size_t)workSpace & 3) return ERROR(GENERIC);  /* must be aligned on 4-bytes boundaries */
    if (workSpaceSize < HIST_WKSP_SIZE) return ERROR(workSpace_tooSmall);
    return HIST_count_parallel_wksp(count, maxSymbolValuePtr, source, sourceSize, trustInput, (U32*)workSpace);
#endif
}


size_t HIST_count_wksp(unsigned* count, unsigned* maxSymbolValuePtr,
                       const void* source, size_t sourceSize,
                       void* workSpace, size_t workSpaceSize)
{
#if defined(ZSTD_ARCH_ARM_SVE2)
    if (*maxSymbolValuePtr < 255)
        return HIST_count_sve2(count, maxSymbolValuePtr, source, sourceSize, checkMaxSymbolValue);
#else
    if ((size_t)workSpace & 3) return ERROR(GENERIC);  /* must be aligned on 4-bytes boundaries */
    if (workSpaceSize < HIST_WKSP_SIZE) return ERROR(workSpace_tooSmall);
    if (*maxSymbolValuePtr < 255)
        return HIST_count_parallel_wksp(count, maxSymbolValuePtr, source, sourceSize, checkMaxSymbolValue, (U32*)workSpace);
#endif
    *maxSymbolValuePtr = 255;
    return HIST_countFast_wksp(count, maxSymbolValuePtr, source, sourceSize, workSpace, workSpaceSize);
}

#ifndef ZSTD_NO_UNUSED_FUNCTIONS

size_t HIST_countFast(unsigned* count, unsigned* maxSymbolValuePtr,
                     const void* source, size_t sourceSize)
{
    unsigned tmpCounters[HIST_WKSP_SIZE_U32];
    return HIST_countFast_wksp(count, maxSymbolValuePtr, source, sourceSize, tmpCounters, sizeof(tmpCounters));
}

size_t HIST_count(unsigned* count, unsigned* maxSymbolValuePtr,
                 const void* src, size_t srcSize)
{
    unsigned tmpCounters[HIST_WKSP_SIZE_U32];
    return HIST_count_wksp(count, maxSymbolValuePtr, src, srcSize, tmpCounters, sizeof(tmpCounters));
}
#endif
/**** ended inlining compress/hist.c ****/
/**** start inlining compress/huf_compress.c ****/
/* ******************************************************************
 * Huffman encoder, part of New Generation Entropy library
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 *  You can contact the author at :
 *  - FSE+HUF source repository : https://github.com/Cyan4973/FiniteStateEntropy
 *  - Public forum : https://groups.google.com/forum/#!forum/lz4c
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
****************************************************************** */


#ifdef _MSC_VER    /* Visual Studio */
#  pragma warning(disable : 4127)        /* disable: C4127: conditional expression is constant */
#endif



/**** skipping file: ../common/zstd_deps.h ****/
/**** skipping file: ../common/bmi2.h ****/
/**** skipping file: ../common/compiler.h ****/
/**** skipping file: ../common/bitstream.h ****/
/**** skipping file: hist.h ****/
#define FSE_STATIC_LINKING_ONLY   /* FSE_optimalTableLog_internal */
/**** skipping file: ../common/fse.h ****/
/**** skipping file: ../common/huf.h ****/
/**** skipping file: ../common/error_private.h ****/
/**** skipping file: ../common/bits.h ****/



#define HUF_isError ERR_isError
#define HUF_STATIC_ASSERT(c) DEBUG_STATIC_ASSERT(c)   /* use only *after* variable declarations */



typedef struct nodeElt_s {
    U32 count;
    U16 parent;
    BYTE byte;
    BYTE nbBits;
} nodeElt;




#if DEBUGLEVEL >= 2

static size_t showU32(const U32* arr, size_t size)
{
    size_t u;
    for (u=0; u<size; u++) {
        RAWLOG(6, " %u", arr[u]); (void)arr;
    }
    RAWLOG(6, " \n");
    return size;
}

static size_t HUF_getNbBits(HUF_CElt elt);

static size_t showCTableBits(const HUF_CElt* ctable, size_t size)
{
    size_t u;
    for (u=0; u<size; u++) {
        RAWLOG(6, " %zu", HUF_getNbBits(ctable[u])); (void)ctable;
    }
    RAWLOG(6, " \n");
    return size;

}

static size_t showHNodeSymbols(const nodeElt* hnode, size_t size)
{
    size_t u;
    for (u=0; u<size; u++) {
        RAWLOG(6, " %u", hnode[u].byte); (void)hnode;
    }
    RAWLOG(6, " \n");
    return size;
}

static size_t showHNodeBits(const nodeElt* hnode, size_t size)
{
    size_t u;
    for (u=0; u<size; u++) {
        RAWLOG(6, " %u", hnode[u].nbBits); (void)hnode;
    }
    RAWLOG(6, " \n");
    return size;
}

#endif



#define HUF_WORKSPACE_MAX_ALIGNMENT 8

static void* HUF_alignUpWorkspace(void* workspace, size_t* workspaceSizePtr, size_t align)
{
    size_t const mask = align - 1;
    size_t const rem = (size_t)workspace & mask;
    size_t const add = (align - rem) & mask;
    BYTE* const aligned = (BYTE*)workspace + add;
    assert((align & (align - 1)) == 0); /* pow 2 */
    assert(align <= HUF_WORKSPACE_MAX_ALIGNMENT);
    if (*workspaceSizePtr >= add) {
        assert(add < align);
        assert(((size_t)aligned & mask) == 0);
        *workspaceSizePtr -= add;
        return aligned;
    } else {
        *workspaceSizePtr = 0;
        return NULL;
    }
}



#define MAX_FSE_TABLELOG_FOR_HUFF_HEADER 6

typedef struct {
    FSE_CTable CTable[FSE_CTABLE_SIZE_U32(MAX_FSE_TABLELOG_FOR_HUFF_HEADER, HUF_TABLELOG_MAX)];
    U32 scratchBuffer[FSE_BUILD_CTABLE_WORKSPACE_SIZE_U32(HUF_TABLELOG_MAX, MAX_FSE_TABLELOG_FOR_HUFF_HEADER)];
    unsigned count[HUF_TABLELOG_MAX+1];
    S16 norm[HUF_TABLELOG_MAX+1];
} HUF_CompressWeightsWksp;

static size_t
HUF_compressWeights(void* dst, size_t dstSize,
              const void* weightTable, size_t wtSize,
                    void* workspace, size_t workspaceSize)
{
    BYTE* const ostart = (BYTE*) dst;
    BYTE* op = ostart;
    BYTE* const oend = ostart + dstSize;

    unsigned maxSymbolValue = HUF_TABLELOG_MAX;
    U32 tableLog = MAX_FSE_TABLELOG_FOR_HUFF_HEADER;
    HUF_CompressWeightsWksp* wksp = (HUF_CompressWeightsWksp*)HUF_alignUpWorkspace(workspace, &workspaceSize, ZSTD_ALIGNOF(U32));

    if (workspaceSize < sizeof(HUF_CompressWeightsWksp)) return ERROR(GENERIC);


    if (wtSize <= 1) return 0;  /* Not compressible */


    {   unsigned const maxCount = HIST_count_simple(wksp->count, &maxSymbolValue, weightTable, wtSize);   /* never fails */
        if (maxCount == wtSize) return 1;   /* only a single symbol in src : rle */
        if (maxCount == 1) return 0;        /* each symbol present maximum once => not compressible */
    }

    tableLog = FSE_optimalTableLog(tableLog, wtSize, maxSymbolValue);
    CHECK_F( FSE_normalizeCount(wksp->norm, tableLog, wksp->count, wtSize, maxSymbolValue, /* useLowProbCount */ 0) );


    {   CHECK_V_F(hSize, FSE_writeNCount(op, (size_t)(oend-op), wksp->norm, maxSymbolValue, tableLog) );
        op += hSize;
    }


    CHECK_F( FSE_buildCTable_wksp(wksp->CTable, wksp->norm, maxSymbolValue, tableLog, wksp->scratchBuffer, sizeof(wksp->scratchBuffer)) );
    {   CHECK_V_F(cSize, FSE_compress_usingCTable(op, (size_t)(oend - op), weightTable, wtSize, wksp->CTable) );
        if (cSize == 0) return 0;   /* not enough space for compressed data */
        op += cSize;
    }

    return (size_t)(op-ostart);
}

static size_t HUF_getNbBits(HUF_CElt elt)
{
    return elt & 0xFF;
}

static size_t HUF_getNbBitsFast(HUF_CElt elt)
{
    return elt;
}

static size_t HUF_getValue(HUF_CElt elt)
{
    return elt & ~(size_t)0xFF;
}

static size_t HUF_getValueFast(HUF_CElt elt)
{
    return elt;
}

static void HUF_setNbBits(HUF_CElt* elt, size_t nbBits)
{
    assert(nbBits <= HUF_TABLELOG_ABSOLUTEMAX);
    *elt = nbBits;
}

static void HUF_setValue(HUF_CElt* elt, size_t value)
{
    size_t const nbBits = HUF_getNbBits(*elt);
    if (nbBits > 0) {
        assert((value >> nbBits) == 0);
        *elt |= value << (sizeof(HUF_CElt) * 8 - nbBits);
    }
}

HUF_CTableHeader HUF_readCTableHeader(HUF_CElt const* ctable)
{
    HUF_CTableHeader header;
    ZSTD_memcpy(&header, ctable, sizeof(header));
    return header;
}

static void HUF_writeCTableHeader(HUF_CElt* ctable, U32 tableLog, U32 maxSymbolValue)
{
    HUF_CTableHeader header;
    HUF_STATIC_ASSERT(sizeof(ctable[0]) == sizeof(header));
    ZSTD_memset(&header, 0, sizeof(header));
    assert(tableLog < 256);
    header.tableLog = (BYTE)tableLog;
    assert(maxSymbolValue < 256);
    header.maxSymbolValue = (BYTE)maxSymbolValue;
    ZSTD_memcpy(ctable, &header, sizeof(header));
}

typedef struct {
    HUF_CompressWeightsWksp wksp;
    BYTE bitsToWeight[HUF_TABLELOG_MAX + 1];   /* precomputed conversion table */
    BYTE huffWeight[HUF_SYMBOLVALUE_MAX];
} HUF_WriteCTableWksp;

size_t HUF_writeCTable_wksp(void* dst, size_t maxDstSize,
                            const HUF_CElt* CTable, unsigned maxSymbolValue, unsigned huffLog,
                            void* workspace, size_t workspaceSize)
{
    HUF_CElt const* const ct = CTable + 1;
    BYTE* op = (BYTE*)dst;
    U32 n;
    HUF_WriteCTableWksp* wksp = (HUF_WriteCTableWksp*)HUF_alignUpWorkspace(workspace, &workspaceSize, ZSTD_ALIGNOF(U32));

    HUF_STATIC_ASSERT(HUF_CTABLE_WORKSPACE_SIZE >= sizeof(HUF_WriteCTableWksp));

    assert(HUF_readCTableHeader(CTable).maxSymbolValue == maxSymbolValue);
    assert(HUF_readCTableHeader(CTable).tableLog == huffLog);


    if (workspaceSize < sizeof(HUF_WriteCTableWksp)) return ERROR(GENERIC);
    if (maxSymbolValue > HUF_SYMBOLVALUE_MAX) return ERROR(maxSymbolValue_tooLarge);


    wksp->bitsToWeight[0] = 0;
    for (n=1; n<huffLog+1; n++)
        wksp->bitsToWeight[n] = (BYTE)(huffLog + 1 - n);
    for (n=0; n<maxSymbolValue; n++)
        wksp->huffWeight[n] = wksp->bitsToWeight[HUF_getNbBits(ct[n])];


    if (maxDstSize < 1) return ERROR(dstSize_tooSmall);
    {   CHECK_V_F(hSize, HUF_compressWeights(op+1, maxDstSize-1, wksp->huffWeight, maxSymbolValue, &wksp->wksp, sizeof(wksp->wksp)) );
        if ((hSize>1) & (hSize < maxSymbolValue/2)) {   /* FSE compressed */
            op[0] = (BYTE)hSize;
            return hSize+1;
    }   }


    if (maxSymbolValue > (256-128)) return ERROR(GENERIC);   /* should not happen : likely means source cannot be compressed */
    if (((maxSymbolValue+1)/2) + 1 > maxDstSize) return ERROR(dstSize_tooSmall);   /* not enough space within dst buffer */
    op[0] = (BYTE)(128 /*special case*/ + (maxSymbolValue-1));
    wksp->huffWeight[maxSymbolValue] = 0;   /* to be sure it doesn't cause msan issue in final combination */
    for (n=0; n<maxSymbolValue; n+=2)
        op[(n/2)+1] = (BYTE)((wksp->huffWeight[n] << 4) + wksp->huffWeight[n+1]);
    return ((maxSymbolValue+1)/2) + 1;
}


size_t HUF_readCTable (HUF_CElt* CTable, unsigned* maxSymbolValuePtr, const void* src, size_t srcSize, unsigned* hasZeroWeights)
{
    BYTE huffWeight[HUF_SYMBOLVALUE_MAX + 1];   /* init not required, even though some static analyzer may complain */
    U32 rankVal[HUF_TABLELOG_ABSOLUTEMAX + 1];   /* large enough for values from 0 to 16 */
    U32 tableLog = 0;
    U32 nbSymbols = 0;
    HUF_CElt* const ct = CTable + 1;


    CHECK_V_F(readSize, HUF_readStats(huffWeight, HUF_SYMBOLVALUE_MAX+1, rankVal, &nbSymbols, &tableLog, src, srcSize));
    *hasZeroWeights = (rankVal[0] > 0);


    if (tableLog > HUF_TABLELOG_MAX) return ERROR(tableLog_tooLarge);
    if (nbSymbols > *maxSymbolValuePtr+1) return ERROR(maxSymbolValue_tooSmall);

    *maxSymbolValuePtr = nbSymbols - 1;

    HUF_writeCTableHeader(CTable, tableLog, *maxSymbolValuePtr);


    {   U32 n, nextRankStart = 0;
        for (n=1; n<=tableLog; n++) {
            U32 curr = nextRankStart;
            nextRankStart += (rankVal[n] << (n-1));
            rankVal[n] = curr;
    }   }


    {   U32 n; for (n=0; n<nbSymbols; n++) {
            const U32 w = huffWeight[n];
            HUF_setNbBits(ct + n, (BYTE)(tableLog + 1 - w) & -(w != 0));
    }   }


    {   U16 nbPerRank[HUF_TABLELOG_MAX+2]  = {0};  /* support w=0=>n=tableLog+1 */
        U16 valPerRank[HUF_TABLELOG_MAX+2] = {0};
        { U32 n; for (n=0; n<nbSymbols; n++) nbPerRank[HUF_getNbBits(ct[n])]++; }

        valPerRank[tableLog+1] = 0;   /* for w==0 */
        {   U16 min = 0;
            U32 n; for (n=tableLog; n>0; n--) {  /* start at n=tablelog <-> w=1 */
                valPerRank[n] = min;     /* get starting value within each rank */
                min += nbPerRank[n];
                min >>= 1;
        }   }

        { U32 n; for (n=0; n<nbSymbols; n++) HUF_setValue(ct + n, valPerRank[HUF_getNbBits(ct[n])]++); }
    }

    return readSize;
}

U32 HUF_getNbBitsFromCTable(HUF_CElt const* CTable, U32 symbolValue)
{
    const HUF_CElt* const ct = CTable + 1;
    assert(symbolValue <= HUF_SYMBOLVALUE_MAX);
    if (symbolValue > HUF_readCTableHeader(CTable).maxSymbolValue)
        return 0;
    return (U32)HUF_getNbBits(ct[symbolValue]);
}



static U32 HUF_setMaxHeight(nodeElt* huffNode, U32 lastNonNull, U32 targetNbBits)
{
    const U32 largestBits = huffNode[lastNonNull].nbBits;

    if (largestBits <= targetNbBits) return largestBits;

    DEBUGLOG(5, "HUF_setMaxHeight (targetNbBits = %u)", targetNbBits);


    {   int totalCost = 0;
        const U32 baseCost = 1 << (largestBits - targetNbBits);
        int n = (int)lastNonNull;


        while (huffNode[n].nbBits > targetNbBits) {
            totalCost += baseCost - (1 << (largestBits - huffNode[n].nbBits));
            huffNode[n].nbBits = (BYTE)targetNbBits;
            n--;
        }

        assert(huffNode[n].nbBits <= targetNbBits);

        while (huffNode[n].nbBits == targetNbBits) --n;


        assert(((U32)totalCost & (baseCost - 1)) == 0);
        totalCost >>= (largestBits - targetNbBits);
        assert(totalCost > 0);


        {   U32 const noSymbol = 0xF0F0F0F0;
            U32 rankLast[HUF_TABLELOG_MAX+2];


            ZSTD_memset(rankLast, 0xF0, sizeof(rankLast));
            {   U32 currentNbBits = targetNbBits;
                int pos;
                for (pos=n ; pos >= 0; pos--) {
                    if (huffNode[pos].nbBits >= currentNbBits) continue;
                    currentNbBits = huffNode[pos].nbBits;   /* < targetNbBits */
                    rankLast[targetNbBits-currentNbBits] = (U32)pos;
            }   }

            while (totalCost > 0) {

                U32 nBitsToDecrease = ZSTD_highbit32((U32)totalCost) + 1;
                assert(nBitsToDecrease <= HUF_TABLELOG_MAX+1);
                for ( ; nBitsToDecrease > 1; nBitsToDecrease--) {
                    U32 const highPos = rankLast[nBitsToDecrease];
                    U32 const lowPos = rankLast[nBitsToDecrease-1];
                    if (highPos == noSymbol) continue;

                    if (lowPos == noSymbol) break;
                    {   U32 const highTotal = huffNode[highPos].count;
                        U32 const lowTotal = 2 * huffNode[lowPos].count;
                        if (highTotal <= lowTotal) break;
                }   }

                assert(rankLast[nBitsToDecrease] != noSymbol || nBitsToDecrease == 1);

                while ((nBitsToDecrease<=HUF_TABLELOG_MAX) && (rankLast[nBitsToDecrease] == noSymbol))
                    nBitsToDecrease++;
                assert(rankLast[nBitsToDecrease] != noSymbol);

                totalCost -= 1 << (nBitsToDecrease-1);
                huffNode[rankLast[nBitsToDecrease]].nbBits++;


                if (rankLast[nBitsToDecrease-1] == noSymbol)
                    rankLast[nBitsToDecrease-1] = rankLast[nBitsToDecrease];

                if (rankLast[nBitsToDecrease] == 0)    /* special case, reached largest symbol */
                    rankLast[nBitsToDecrease] = noSymbol;
                else {
                    rankLast[nBitsToDecrease]--;
                    if (huffNode[rankLast[nBitsToDecrease]].nbBits != targetNbBits-nBitsToDecrease)
                        rankLast[nBitsToDecrease] = noSymbol;   /* this rank is now empty */
                }
            }   /* while (totalCost > 0) */


            while (totalCost < 0) {  /* Sometimes, cost correction overshoot */

                if (rankLast[1] == noSymbol) {
                    while (huffNode[n].nbBits == targetNbBits) n--;
                    huffNode[n+1].nbBits--;
                    assert(n >= 0);
                    rankLast[1] = (U32)(n+1);
                    totalCost++;
                    continue;
                }
                huffNode[ rankLast[1] + 1 ].nbBits--;
                rankLast[1]++;
                totalCost ++;
            }
        }   /* repay normalized cost */
    }   /* there are several too large elements (at least >= 2) */

    return targetNbBits;
}

typedef struct {
    U16 base;
    U16 curr;
} rankPos;

typedef nodeElt huffNodeTable[2 * (HUF_SYMBOLVALUE_MAX + 1)];


#define RANK_POSITION_TABLE_SIZE 192

typedef struct {
  huffNodeTable huffNodeTbl;
  rankPos rankPosition[RANK_POSITION_TABLE_SIZE];
} HUF_buildCTable_wksp_tables;


#define RANK_POSITION_MAX_COUNT_LOG 32
#define RANK_POSITION_LOG_BUCKETS_BEGIN ((RANK_POSITION_TABLE_SIZE - 1) - RANK_POSITION_MAX_COUNT_LOG - 1 /* == 158 */)
#define RANK_POSITION_DISTINCT_COUNT_CUTOFF (RANK_POSITION_LOG_BUCKETS_BEGIN + ZSTD_highbit32(RANK_POSITION_LOG_BUCKETS_BEGIN) /* == 166 */)


static U32 HUF_getIndex(U32 const count) {
    return (count < RANK_POSITION_DISTINCT_COUNT_CUTOFF)
        ? count
        : ZSTD_highbit32(count) + RANK_POSITION_LOG_BUCKETS_BEGIN;
}


static void HUF_swapNodes(nodeElt* a, nodeElt* b) {
	nodeElt tmp = *a;
	*a = *b;
	*b = tmp;
}


MEM_STATIC int HUF_isSorted(nodeElt huffNode[], U32 const maxSymbolValue1) {
    U32 i;
    for (i = 1; i < maxSymbolValue1; ++i) {
        if (huffNode[i].count > huffNode[i-1].count) {
            return 0;
        }
    }
    return 1;
}


HINT_INLINE void HUF_insertionSort(nodeElt huffNode[], int const low, int const high) {
    int i;
    int const size = high-low+1;
    huffNode += low;
    for (i = 1; i < size; ++i) {
        nodeElt const key = huffNode[i];
        int j = i - 1;
        while (j >= 0 && huffNode[j].count < key.count) {
            huffNode[j + 1] = huffNode[j];
            j--;
        }
        huffNode[j + 1] = key;
    }
}


static int HUF_quickSortPartition(nodeElt arr[], int const low, int const high) {

    U32 const pivot = arr[high].count;
    int i = low - 1;
    int j = low;
    for ( ; j < high; j++) {
        if (arr[j].count > pivot) {
            i++;
            HUF_swapNodes(&arr[i], &arr[j]);
        }
    }
    HUF_swapNodes(&arr[i + 1], &arr[high]);
    return i + 1;
}


static void HUF_simpleQuickSort(nodeElt arr[], int low, int high) {
    int const kInsertionSortThreshold = 8;
    if (high - low < kInsertionSortThreshold) {
        HUF_insertionSort(arr, low, high);
        return;
    }
    while (low < high) {
        int const idx = HUF_quickSortPartition(arr, low, high);
        if (idx - low < high - idx) {
            HUF_simpleQuickSort(arr, low, idx - 1);
            low = idx + 1;
        } else {
            HUF_simpleQuickSort(arr, idx + 1, high);
            high = idx - 1;
        }
    }
}


static void HUF_sort(nodeElt huffNode[], const unsigned count[], U32 const maxSymbolValue, rankPos rankPosition[]) {
    U32 n;
    U32 const maxSymbolValue1 = maxSymbolValue+1;


    ZSTD_memset(rankPosition, 0, sizeof(*rankPosition) * RANK_POSITION_TABLE_SIZE);
    for (n = 0; n < maxSymbolValue1; ++n) {
        U32 lowerRank = HUF_getIndex(count[n]);
        assert(lowerRank < RANK_POSITION_TABLE_SIZE - 1);
        rankPosition[lowerRank].base++;
    }

    assert(rankPosition[RANK_POSITION_TABLE_SIZE - 1].base == 0);

    for (n = RANK_POSITION_TABLE_SIZE - 1; n > 0; --n) {
        rankPosition[n-1].base += rankPosition[n].base;
        rankPosition[n-1].curr = rankPosition[n-1].base;
    }


    for (n = 0; n < maxSymbolValue1; ++n) {
        U32 const c = count[n];
        U32 const r = HUF_getIndex(c) + 1;
        U32 const pos = rankPosition[r].curr++;
        assert(pos < maxSymbolValue1);
        huffNode[pos].count = c;
        huffNode[pos].byte  = (BYTE)n;
    }


    for (n = RANK_POSITION_DISTINCT_COUNT_CUTOFF; n < RANK_POSITION_TABLE_SIZE - 1; ++n) {
        int const bucketSize = rankPosition[n].curr - rankPosition[n].base;
        U32 const bucketStartIdx = rankPosition[n].base;
        if (bucketSize > 1) {
            assert(bucketStartIdx < maxSymbolValue1);
            HUF_simpleQuickSort(huffNode + bucketStartIdx, 0, bucketSize-1);
        }
    }

    assert(HUF_isSorted(huffNode, maxSymbolValue1));
}



#define STARTNODE (HUF_SYMBOLVALUE_MAX+1)


static int HUF_buildTree(nodeElt* huffNode, U32 maxSymbolValue)
{
    nodeElt* const huffNode0 = huffNode - 1;
    int nonNullRank;
    int lowS, lowN;
    int nodeNb = STARTNODE;
    int n, nodeRoot;
    DEBUGLOG(5, "HUF_buildTree (alphabet size = %u)", maxSymbolValue + 1);

    nonNullRank = (int)maxSymbolValue;
    while(huffNode[nonNullRank].count == 0) nonNullRank--;
    lowS = nonNullRank; nodeRoot = nodeNb + lowS - 1; lowN = nodeNb;
    huffNode[nodeNb].count = huffNode[lowS].count + huffNode[lowS-1].count;
    huffNode[lowS].parent = huffNode[lowS-1].parent = (U16)nodeNb;
    nodeNb++; lowS-=2;
    for (n=nodeNb; n<=nodeRoot; n++) huffNode[n].count = (U32)(1U<<30);
    huffNode0[0].count = (U32)(1U<<31);  /* fake entry, strong barrier */


    while (nodeNb <= nodeRoot) {
        int const n1 = (huffNode[lowS].count < huffNode[lowN].count) ? lowS-- : lowN++;
        int const n2 = (huffNode[lowS].count < huffNode[lowN].count) ? lowS-- : lowN++;
        huffNode[nodeNb].count = huffNode[n1].count + huffNode[n2].count;
        huffNode[n1].parent = huffNode[n2].parent = (U16)nodeNb;
        nodeNb++;
    }


    huffNode[nodeRoot].nbBits = 0;
    for (n=nodeRoot-1; n>=STARTNODE; n--)
        huffNode[n].nbBits = huffNode[ huffNode[n].parent ].nbBits + 1;
    for (n=0; n<=nonNullRank; n++)
        huffNode[n].nbBits = huffNode[ huffNode[n].parent ].nbBits + 1;

    DEBUGLOG(6, "Initial distribution of bits completed (%zu sorted symbols)", showHNodeBits(huffNode, maxSymbolValue+1));

    return nonNullRank;
}


static void HUF_buildCTableFromTree(HUF_CElt* CTable, nodeElt const* huffNode, int nonNullRank, U32 maxSymbolValue, U32 maxNbBits)
{
    HUF_CElt* const ct = CTable + 1;

    int n;
    U16 nbPerRank[HUF_TABLELOG_MAX+1] = {0};
    U16 valPerRank[HUF_TABLELOG_MAX+1] = {0};
    int const alphabetSize = (int)(maxSymbolValue + 1);
    for (n=0; n<=nonNullRank; n++)
        nbPerRank[huffNode[n].nbBits]++;

    {   U16 min = 0;
        for (n=(int)maxNbBits; n>0; n--) {
            valPerRank[n] = min;      /* get starting value within each rank */
            min += nbPerRank[n];
            min >>= 1;
    }   }
    for (n=0; n<alphabetSize; n++)
        HUF_setNbBits(ct + huffNode[n].byte, huffNode[n].nbBits);   /* push nbBits per symbol, symbol order */
    for (n=0; n<alphabetSize; n++)
        HUF_setValue(ct + n, valPerRank[HUF_getNbBits(ct[n])]++);   /* assign value within rank, symbol order */

    HUF_writeCTableHeader(CTable, maxNbBits, maxSymbolValue);
}

size_t
HUF_buildCTable_wksp(HUF_CElt* CTable, const unsigned* count, U32 maxSymbolValue, U32 maxNbBits,
                     void* workSpace, size_t wkspSize)
{
    HUF_buildCTable_wksp_tables* const wksp_tables =
        (HUF_buildCTable_wksp_tables*)HUF_alignUpWorkspace(workSpace, &wkspSize, ZSTD_ALIGNOF(U32));
    nodeElt* const huffNode0 = wksp_tables->huffNodeTbl;
    nodeElt* const huffNode = huffNode0+1;
    int nonNullRank;

    HUF_STATIC_ASSERT(HUF_CTABLE_WORKSPACE_SIZE == sizeof(HUF_buildCTable_wksp_tables));

    DEBUGLOG(5, "HUF_buildCTable_wksp (alphabet size = %u)", maxSymbolValue+1);


    if (wkspSize < sizeof(HUF_buildCTable_wksp_tables))
        return ERROR(workSpace_tooSmall);
    if (maxNbBits == 0) maxNbBits = HUF_TABLELOG_DEFAULT;
    if (maxSymbolValue > HUF_SYMBOLVALUE_MAX)
        return ERROR(maxSymbolValue_tooLarge);
    ZSTD_memset(huffNode0, 0, sizeof(huffNodeTable));


    HUF_sort(huffNode, count, maxSymbolValue, wksp_tables->rankPosition);
    DEBUGLOG(6, "sorted symbols completed (%zu symbols)", showHNodeSymbols(huffNode, maxSymbolValue+1));


    nonNullRank = HUF_buildTree(huffNode, maxSymbolValue);


    maxNbBits = HUF_setMaxHeight(huffNode, (U32)nonNullRank, maxNbBits);
    if (maxNbBits > HUF_TABLELOG_MAX) return ERROR(GENERIC);   /* check fit into table */

    HUF_buildCTableFromTree(CTable, huffNode, nonNullRank, maxSymbolValue, maxNbBits);

    return maxNbBits;
}

size_t HUF_estimateCompressedSize(const HUF_CElt* CTable, const unsigned* count, unsigned maxSymbolValue)
{
    HUF_CElt const* ct = CTable + 1;
    size_t nbBits = 0;
    int s;
    for (s = 0; s <= (int)maxSymbolValue; ++s) {
        nbBits += HUF_getNbBits(ct[s]) * count[s];
    }
    return nbBits >> 3;
}

int HUF_validateCTable(const HUF_CElt* CTable, const unsigned* count, unsigned maxSymbolValue) {
    HUF_CTableHeader header = HUF_readCTableHeader(CTable);
    HUF_CElt const* ct = CTable + 1;
    int bad = 0;
    int s;

    assert(header.tableLog <= HUF_TABLELOG_ABSOLUTEMAX);

    if (header.maxSymbolValue < maxSymbolValue)
        return 0;

    for (s = 0; s <= (int)maxSymbolValue; ++s) {
        bad |= (count[s] != 0) & (HUF_getNbBits(ct[s]) == 0);
    }
    return !bad;
}

size_t HUF_compressBound(size_t size) { return HUF_COMPRESSBOUND(size); }



#define HUF_BITS_IN_CONTAINER (sizeof(size_t) * 8)

typedef struct {
    size_t bitContainer[2];
    size_t bitPos[2];

    BYTE* startPtr;
    BYTE* ptr;
    BYTE* endPtr;
} HUF_CStream_t;


static size_t HUF_initCStream(HUF_CStream_t* bitC,
                                  void* startPtr, size_t dstCapacity)
{
    ZSTD_memset(bitC, 0, sizeof(*bitC));
    bitC->startPtr = (BYTE*)startPtr;
    bitC->ptr = bitC->startPtr;
    bitC->endPtr = bitC->startPtr + dstCapacity - sizeof(bitC->bitContainer[0]);
    if (dstCapacity <= sizeof(bitC->bitContainer[0])) return ERROR(dstSize_tooSmall);
    return 0;
}


FORCE_INLINE_TEMPLATE void HUF_addBits(HUF_CStream_t* bitC, HUF_CElt elt, int idx, int kFast)
{
    assert(idx <= 1);
    assert(HUF_getNbBits(elt) <= HUF_TABLELOG_ABSOLUTEMAX);

    bitC->bitContainer[idx] >>= HUF_getNbBits(elt);
    bitC->bitContainer[idx] |= kFast ? HUF_getValueFast(elt) : HUF_getValue(elt);

    bitC->bitPos[idx] += HUF_getNbBitsFast(elt);
    assert((bitC->bitPos[idx] & 0xFF) <= HUF_BITS_IN_CONTAINER);

#if DEBUGLEVEL >= 1
    {
        size_t const nbBits = HUF_getNbBits(elt);
        size_t const dirtyBits = nbBits == 0 ? 0 : ZSTD_highbit32((U32)nbBits) + 1;
        (void)dirtyBits;

        assert(((elt >> dirtyBits) << (dirtyBits + nbBits)) == 0);

        assert(!kFast || (bitC->bitPos[idx] & 0xFF) <= HUF_BITS_IN_CONTAINER);
        (void)dirtyBits;
    }
#endif
}

FORCE_INLINE_TEMPLATE void HUF_zeroIndex1(HUF_CStream_t* bitC)
{
    bitC->bitContainer[1] = 0;
    bitC->bitPos[1] = 0;
}


FORCE_INLINE_TEMPLATE void HUF_mergeIndex1(HUF_CStream_t* bitC)
{
    assert((bitC->bitPos[1] & 0xFF) < HUF_BITS_IN_CONTAINER);
    bitC->bitContainer[0] >>= (bitC->bitPos[1] & 0xFF);
    bitC->bitContainer[0] |= bitC->bitContainer[1];
    bitC->bitPos[0] += bitC->bitPos[1];
    assert((bitC->bitPos[0] & 0xFF) <= HUF_BITS_IN_CONTAINER);
}


FORCE_INLINE_TEMPLATE void HUF_flushBits(HUF_CStream_t* bitC, int kFast)
{

    size_t const nbBits = bitC->bitPos[0] & 0xFF;
    size_t const nbBytes = nbBits >> 3;

    size_t const bitContainer = bitC->bitContainer[0] >> (HUF_BITS_IN_CONTAINER - nbBits);

    bitC->bitPos[0] &= 7;
    assert(nbBits > 0);
    assert(nbBits <= sizeof(bitC->bitContainer[0]) * 8);
    assert(bitC->ptr <= bitC->endPtr);
    MEM_writeLEST(bitC->ptr, bitContainer);
    bitC->ptr += nbBytes;
    assert(!kFast || bitC->ptr <= bitC->endPtr);
    if (!kFast && bitC->ptr > bitC->endPtr) bitC->ptr = bitC->endPtr;

}


static HUF_CElt HUF_endMark(void)
{
    HUF_CElt endMark;
    HUF_setNbBits(&endMark, 1);
    HUF_setValue(&endMark, 1);
    return endMark;
}


static size_t HUF_closeCStream(HUF_CStream_t* bitC)
{
    HUF_addBits(bitC, HUF_endMark(), /* idx */ 0, /* kFast */ 0);
    HUF_flushBits(bitC, /* kFast */ 0);
    {
        size_t const nbBits = bitC->bitPos[0] & 0xFF;
        if (bitC->ptr >= bitC->endPtr) return 0; /* overflow detected */
        return (size_t)(bitC->ptr - bitC->startPtr) + (nbBits > 0);
    }
}

FORCE_INLINE_TEMPLATE void
HUF_encodeSymbol(HUF_CStream_t* bitCPtr, U32 symbol, const HUF_CElt* CTable, int idx, int fast)
{
    HUF_addBits(bitCPtr, CTable[symbol], idx, fast);
}

FORCE_INLINE_TEMPLATE void
HUF_compress1X_usingCTable_internal_body_loop(HUF_CStream_t* bitC,
                                   const BYTE* ip, size_t srcSize,
                                   const HUF_CElt* ct,
                                   int kUnroll, int kFastFlush, int kLastFast)
{

    int n = (int)srcSize;
    int rem = n % kUnroll;
    if (rem > 0) {
        for (; rem > 0; --rem) {
            HUF_encodeSymbol(bitC, ip[--n], ct, 0, /* fast */ 0);
        }
        HUF_flushBits(bitC, kFastFlush);
    }
    assert(n % kUnroll == 0);


    if (n % (2 * kUnroll)) {
        int u;
        for (u = 1; u < kUnroll; ++u) {
            HUF_encodeSymbol(bitC, ip[n - u], ct, 0, 1);
        }
        HUF_encodeSymbol(bitC, ip[n - kUnroll], ct, 0, kLastFast);
        HUF_flushBits(bitC, kFastFlush);
        n -= kUnroll;
    }
    assert(n % (2 * kUnroll) == 0);

    for (; n>0; n-= 2 * kUnroll) {

        int u;
        for (u = 1; u < kUnroll; ++u) {
            HUF_encodeSymbol(bitC, ip[n - u], ct, /* idx */ 0, /* fast */ 1);
        }
        HUF_encodeSymbol(bitC, ip[n - kUnroll], ct, /* idx */ 0, /* fast */ kLastFast);
        HUF_flushBits(bitC, kFastFlush);

        HUF_zeroIndex1(bitC);
        for (u = 1; u < kUnroll; ++u) {
            HUF_encodeSymbol(bitC, ip[n - kUnroll - u], ct, /* idx */ 1, /* fast */ 1);
        }
        HUF_encodeSymbol(bitC, ip[n - kUnroll - kUnroll], ct, /* idx */ 1, /* fast */ kLastFast);

        HUF_mergeIndex1(bitC);
        HUF_flushBits(bitC, kFastFlush);
    }
    assert(n == 0);

}


static size_t HUF_tightCompressBound(size_t srcSize, size_t tableLog)
{
    return ((srcSize * tableLog) >> 3) + 8;
}


FORCE_INLINE_TEMPLATE size_t
HUF_compress1X_usingCTable_internal_body(void* dst, size_t dstSize,
                                   const void* src, size_t srcSize,
                                   const HUF_CElt* CTable)
{
    U32 const tableLog = HUF_readCTableHeader(CTable).tableLog;
    HUF_CElt const* ct = CTable + 1;
    const BYTE* ip = (const BYTE*) src;
    BYTE* const ostart = (BYTE*)dst;
    BYTE* const oend = ostart + dstSize;
    HUF_CStream_t bitC;


    if (dstSize < 8) return 0;   /* not enough space to compress */
    { BYTE* op = ostart;
      size_t const initErr = HUF_initCStream(&bitC, op, (size_t)(oend-op));
      if (HUF_isError(initErr)) return 0; }

    if (dstSize < HUF_tightCompressBound(srcSize, (size_t)tableLog) || tableLog > 11)
        HUF_compress1X_usingCTable_internal_body_loop(&bitC, ip, srcSize, ct, /* kUnroll */ MEM_32bits() ? 2 : 4, /* kFast */ 0, /* kLastFast */ 0);
    else {
        if (MEM_32bits()) {
            switch (tableLog) {
            case 11:
                HUF_compress1X_usingCTable_internal_body_loop(&bitC, ip, srcSize, ct, /* kUnroll */ 2, /* kFastFlush */ 1, /* kLastFast */ 0);
                break;
            case 10: ZSTD_FALLTHROUGH;
            case 9: ZSTD_FALLTHROUGH;
            case 8:
                HUF_compress1X_usingCTable_internal_body_loop(&bitC, ip, srcSize, ct, /* kUnroll */ 2, /* kFastFlush */ 1, /* kLastFast */ 1);
                break;
            case 7: ZSTD_FALLTHROUGH;
            default:
                HUF_compress1X_usingCTable_internal_body_loop(&bitC, ip, srcSize, ct, /* kUnroll */ 3, /* kFastFlush */ 1, /* kLastFast */ 1);
                break;
            }
        } else {
            switch (tableLog) {
            case 11:
                HUF_compress1X_usingCTable_internal_body_loop(&bitC, ip, srcSize, ct, /* kUnroll */ 5, /* kFastFlush */ 1, /* kLastFast */ 0);
                break;
            case 10:
                HUF_compress1X_usingCTable_internal_body_loop(&bitC, ip, srcSize, ct, /* kUnroll */ 5, /* kFastFlush */ 1, /* kLastFast */ 1);
                break;
            case 9:
                HUF_compress1X_usingCTable_internal_body_loop(&bitC, ip, srcSize, ct, /* kUnroll */ 6, /* kFastFlush */ 1, /* kLastFast */ 0);
                break;
            case 8:
                HUF_compress1X_usingCTable_internal_body_loop(&bitC, ip, srcSize, ct, /* kUnroll */ 7, /* kFastFlush */ 1, /* kLastFast */ 0);
                break;
            case 7:
                HUF_compress1X_usingCTable_internal_body_loop(&bitC, ip, srcSize, ct, /* kUnroll */ 8, /* kFastFlush */ 1, /* kLastFast */ 0);
                break;
            case 6: ZSTD_FALLTHROUGH;
            default:
                HUF_compress1X_usingCTable_internal_body_loop(&bitC, ip, srcSize, ct, /* kUnroll */ 9, /* kFastFlush */ 1, /* kLastFast */ 1);
                break;
            }
        }
    }
    assert(bitC.ptr <= bitC.endPtr);

    return HUF_closeCStream(&bitC);
}

#if DYNAMIC_BMI2

static BMI2_TARGET_ATTRIBUTE size_t
HUF_compress1X_usingCTable_internal_bmi2(void* dst, size_t dstSize,
                                   const void* src, size_t srcSize,
                                   const HUF_CElt* CTable)
{
    return HUF_compress1X_usingCTable_internal_body(dst, dstSize, src, srcSize, CTable);
}

static size_t
HUF_compress1X_usingCTable_internal_default(void* dst, size_t dstSize,
                                      const void* src, size_t srcSize,
                                      const HUF_CElt* CTable)
{
    return HUF_compress1X_usingCTable_internal_body(dst, dstSize, src, srcSize, CTable);
}

static size_t
HUF_compress1X_usingCTable_internal(void* dst, size_t dstSize,
                              const void* src, size_t srcSize,
                              const HUF_CElt* CTable, const int flags)
{
    if (ZSTD_USE_BMI2(flags & HUF_flags_bmi2)) {
        return HUF_compress1X_usingCTable_internal_bmi2(dst, dstSize, src, srcSize, CTable);
    }
    (void)flags;
    return HUF_compress1X_usingCTable_internal_default(dst, dstSize, src, srcSize, CTable);
}

#else

static size_t
HUF_compress1X_usingCTable_internal(void* dst, size_t dstSize,
                              const void* src, size_t srcSize,
                              const HUF_CElt* CTable, const int flags)
{
    (void)flags;
    return HUF_compress1X_usingCTable_internal_body(dst, dstSize, src, srcSize, CTable);
}

#endif

size_t HUF_compress1X_usingCTable(void* dst, size_t dstSize, const void* src, size_t srcSize, const HUF_CElt* CTable, int flags)
{
    return HUF_compress1X_usingCTable_internal(dst, dstSize, src, srcSize, CTable, flags);
}

static size_t
HUF_compress4X_usingCTable_internal(void* dst, size_t dstSize,
                              const void* src, size_t srcSize,
                              const HUF_CElt* CTable, int flags)
{
    size_t const segmentSize = (srcSize+3)/4;   /* first 3 segments */
    const BYTE* ip = (const BYTE*) src;
    const BYTE* const iend = ip + srcSize;
    BYTE* const ostart = (BYTE*) dst;
    BYTE* const oend = ostart + dstSize;
    BYTE* op = ostart;

    if (dstSize < 6 + 1 + 1 + 1 + 8) return 0;   /* minimum space to compress successfully */
    if (srcSize < 12) return 0;   /* no saving possible : too small input */
    op += 6;   /* jumpTable */

    assert(op <= oend);
    {   CHECK_V_F(cSize, HUF_compress1X_usingCTable_internal(op, (size_t)(oend-op), ip, segmentSize, CTable, flags) );
        if (cSize == 0 || cSize > 65535) return 0;
        MEM_writeLE16(ostart, (U16)cSize);
        op += cSize;
    }

    ip += segmentSize;
    assert(op <= oend);
    {   CHECK_V_F(cSize, HUF_compress1X_usingCTable_internal(op, (size_t)(oend-op), ip, segmentSize, CTable, flags) );
        if (cSize == 0 || cSize > 65535) return 0;
        MEM_writeLE16(ostart+2, (U16)cSize);
        op += cSize;
    }

    ip += segmentSize;
    assert(op <= oend);
    {   CHECK_V_F(cSize, HUF_compress1X_usingCTable_internal(op, (size_t)(oend-op), ip, segmentSize, CTable, flags) );
        if (cSize == 0 || cSize > 65535) return 0;
        MEM_writeLE16(ostart+4, (U16)cSize);
        op += cSize;
    }

    ip += segmentSize;
    assert(op <= oend);
    assert(ip <= iend);
    {   CHECK_V_F(cSize, HUF_compress1X_usingCTable_internal(op, (size_t)(oend-op), ip, (size_t)(iend-ip), CTable, flags) );
        if (cSize == 0 || cSize > 65535) return 0;
        op += cSize;
    }

    return (size_t)(op-ostart);
}

size_t HUF_compress4X_usingCTable(void* dst, size_t dstSize, const void* src, size_t srcSize, const HUF_CElt* CTable, int flags)
{
    return HUF_compress4X_usingCTable_internal(dst, dstSize, src, srcSize, CTable, flags);
}

typedef enum { HUF_singleStream, HUF_fourStreams } HUF_nbStreams_e;

static size_t HUF_compressCTable_internal(
                BYTE* const ostart, BYTE* op, BYTE* const oend,
                const void* src, size_t srcSize,
                HUF_nbStreams_e nbStreams, const HUF_CElt* CTable, const int flags)
{
    size_t const cSize = (nbStreams==HUF_singleStream) ?
                         HUF_compress1X_usingCTable_internal(op, (size_t)(oend - op), src, srcSize, CTable, flags) :
                         HUF_compress4X_usingCTable_internal(op, (size_t)(oend - op), src, srcSize, CTable, flags);
    if (HUF_isError(cSize)) { return cSize; }
    if (cSize==0) { return 0; }   /* uncompressible */
    op += cSize;

    assert(op >= ostart);
    if ((size_t)(op-ostart) >= srcSize-1) { return 0; }
    return (size_t)(op-ostart);
}

typedef struct {
    unsigned count[HUF_SYMBOLVALUE_MAX + 1];
    HUF_CElt CTable[HUF_CTABLE_SIZE_ST(HUF_SYMBOLVALUE_MAX)];
    union {
        HUF_buildCTable_wksp_tables buildCTable_wksp;
        HUF_WriteCTableWksp writeCTable_wksp;
        U32 hist_wksp[HIST_WKSP_SIZE_U32];
    } wksps;
} HUF_compress_tables_t;

#define SUSPECT_INCOMPRESSIBLE_SAMPLE_SIZE 4096
#define SUSPECT_INCOMPRESSIBLE_SAMPLE_RATIO 10  /* Must be >= 2 */

unsigned HUF_cardinality(const unsigned* count, unsigned maxSymbolValue)
{
    unsigned cardinality = 0;
    unsigned i;

    for (i = 0; i < maxSymbolValue + 1; i++) {
        if (count[i] != 0) cardinality += 1;
    }

    return cardinality;
}

unsigned HUF_minTableLog(unsigned symbolCardinality)
{
    U32 minBitsSymbols = ZSTD_highbit32(symbolCardinality) + 1;
    return minBitsSymbols;
}

unsigned HUF_optimalTableLog(
            unsigned maxTableLog,
            size_t srcSize,
            unsigned maxSymbolValue,
            void* workSpace, size_t wkspSize,
            HUF_CElt* table,
      const unsigned* count,
            int flags)
{
    assert(srcSize > 1); /* Not supported, RLE should be used instead */
    assert(wkspSize >= sizeof(HUF_buildCTable_wksp_tables));

    if (!(flags & HUF_flags_optimalDepth)) {

        return FSE_optimalTableLog_internal(maxTableLog, srcSize, maxSymbolValue, 1);
    }

    {   BYTE* dst = (BYTE*)workSpace + sizeof(HUF_WriteCTableWksp);
        size_t dstSize = wkspSize - sizeof(HUF_WriteCTableWksp);
        size_t hSize, newSize;
        const unsigned symbolCardinality = HUF_cardinality(count, maxSymbolValue);
        const unsigned minTableLog = HUF_minTableLog(symbolCardinality);
        size_t optSize = ((size_t) ~0) - 1;
        unsigned optLog = maxTableLog, optLogGuess;

        DEBUGLOG(6, "HUF_optimalTableLog: probing huf depth (srcSize=%zu)", srcSize);


        for (optLogGuess = minTableLog; optLogGuess <= maxTableLog; optLogGuess++) {
            DEBUGLOG(7, "checking for huffLog=%u", optLogGuess);

            {   size_t maxBits = HUF_buildCTable_wksp(table, count, maxSymbolValue, optLogGuess, workSpace, wkspSize);
                if (ERR_isError(maxBits)) continue;

                if (maxBits < optLogGuess && optLogGuess > minTableLog) break;

                hSize = HUF_writeCTable_wksp(dst, dstSize, table, maxSymbolValue, (U32)maxBits, workSpace, wkspSize);
            }

            if (ERR_isError(hSize)) continue;

            newSize = HUF_estimateCompressedSize(table, count, maxSymbolValue) + hSize;

            if (newSize > optSize + 1) {
                break;
            }

            if (newSize < optSize) {
                optSize = newSize;
                optLog = optLogGuess;
            }
        }
        assert(optLog <= HUF_TABLELOG_MAX);
        return optLog;
    }
}


static size_t
HUF_compress_internal (void* dst, size_t dstSize,
                 const void* src, size_t srcSize,
                       unsigned maxSymbolValue, unsigned huffLog,
                       HUF_nbStreams_e nbStreams,
                       void* workSpace, size_t wkspSize,
                       HUF_CElt* oldHufTable, HUF_repeat* repeat, int flags)
{
    HUF_compress_tables_t* const table = (HUF_compress_tables_t*)HUF_alignUpWorkspace(workSpace, &wkspSize, ZSTD_ALIGNOF(size_t));
    BYTE* const ostart = (BYTE*)dst;
    BYTE* const oend = ostart + dstSize;
    BYTE* op = ostart;

    DEBUGLOG(5, "HUF_compress_internal (srcSize=%zu)", srcSize);
    HUF_STATIC_ASSERT(sizeof(*table) + HUF_WORKSPACE_MAX_ALIGNMENT <= HUF_WORKSPACE_SIZE);


    if (wkspSize < sizeof(*table)) return ERROR(workSpace_tooSmall);
    if (!srcSize) return 0;  /* Uncompressed */
    if (!dstSize) return 0;  /* cannot fit anything within dst budget */
    if (srcSize > HUF_BLOCKSIZE_MAX) return ERROR(srcSize_wrong);   /* current block size limit */
    if (huffLog > HUF_TABLELOG_MAX) return ERROR(tableLog_tooLarge);
    if (maxSymbolValue > HUF_SYMBOLVALUE_MAX) return ERROR(maxSymbolValue_tooLarge);
    if (!maxSymbolValue) maxSymbolValue = HUF_SYMBOLVALUE_MAX;
    if (!huffLog) huffLog = HUF_TABLELOG_DEFAULT;


    if ((flags & HUF_flags_preferRepeat) && repeat && *repeat == HUF_repeat_valid) {
        return HUF_compressCTable_internal(ostart, op, oend,
                                           src, srcSize,
                                           nbStreams, oldHufTable, flags);
    }


    DEBUG_STATIC_ASSERT(SUSPECT_INCOMPRESSIBLE_SAMPLE_RATIO >= 2);
    if ((flags & HUF_flags_suspectUncompressible) && srcSize >= (SUSPECT_INCOMPRESSIBLE_SAMPLE_SIZE * SUSPECT_INCOMPRESSIBLE_SAMPLE_RATIO)) {
        size_t largestTotal = 0;
        DEBUGLOG(5, "input suspected incompressible : sampling to check");
        {   unsigned maxSymbolValueBegin = maxSymbolValue;
            CHECK_V_F(largestBegin, HIST_count_simple (table->count, &maxSymbolValueBegin, (const BYTE*)src, SUSPECT_INCOMPRESSIBLE_SAMPLE_SIZE) );
            largestTotal += largestBegin;
        }
        {   unsigned maxSymbolValueEnd = maxSymbolValue;
            CHECK_V_F(largestEnd, HIST_count_simple (table->count, &maxSymbolValueEnd, (const BYTE*)src + srcSize - SUSPECT_INCOMPRESSIBLE_SAMPLE_SIZE, SUSPECT_INCOMPRESSIBLE_SAMPLE_SIZE) );
            largestTotal += largestEnd;
        }
        if (largestTotal <= ((2 * SUSPECT_INCOMPRESSIBLE_SAMPLE_SIZE) >> 7)+4) return 0;   /* heuristic : probably not compressible enough */
    }


    {   CHECK_V_F(largest, HIST_count_wksp (table->count, &maxSymbolValue, (const BYTE*)src, srcSize, table->wksps.hist_wksp, sizeof(table->wksps.hist_wksp)) );
        if (largest == srcSize) { *ostart = ((const BYTE*)src)[0]; return 1; }   /* single symbol, rle */
        if (largest <= (srcSize >> 7)+4) return 0;   /* heuristic : probably not compressible enough */
    }
    DEBUGLOG(6, "histogram detail completed (%zu symbols)", showU32(table->count, maxSymbolValue+1));


    if ( repeat
      && *repeat == HUF_repeat_check
      && !HUF_validateCTable(oldHufTable, table->count, maxSymbolValue)) {
        *repeat = HUF_repeat_none;
    }

    if ((flags & HUF_flags_preferRepeat) && repeat && *repeat != HUF_repeat_none) {
        return HUF_compressCTable_internal(ostart, op, oend,
                                           src, srcSize,
                                           nbStreams, oldHufTable, flags);
    }


    huffLog = HUF_optimalTableLog(huffLog, srcSize, maxSymbolValue, &table->wksps, sizeof(table->wksps), table->CTable, table->count, flags);
    {   size_t const maxBits = HUF_buildCTable_wksp(table->CTable, table->count,
                                            maxSymbolValue, huffLog,
                                            &table->wksps.buildCTable_wksp, sizeof(table->wksps.buildCTable_wksp));
        CHECK_F(maxBits);
        huffLog = (U32)maxBits;
        DEBUGLOG(6, "bit distribution completed (%zu symbols)", showCTableBits(table->CTable + 1, maxSymbolValue+1));
    }


    {   CHECK_V_F(hSize, HUF_writeCTable_wksp(op, dstSize, table->CTable, maxSymbolValue, huffLog,
                                              &table->wksps.writeCTable_wksp, sizeof(table->wksps.writeCTable_wksp)) );

        if (repeat && *repeat != HUF_repeat_none) {
            size_t const oldSize = HUF_estimateCompressedSize(oldHufTable, table->count, maxSymbolValue);
            size_t const newSize = HUF_estimateCompressedSize(table->CTable, table->count, maxSymbolValue);
            if (oldSize <= hSize + newSize || hSize + 12 >= srcSize) {
                return HUF_compressCTable_internal(ostart, op, oend,
                                                   src, srcSize,
                                                   nbStreams, oldHufTable, flags);
        }   }


        if (hSize + 12ul >= srcSize) { return 0; }
        op += hSize;
        if (repeat) { *repeat = HUF_repeat_none; }
        if (oldHufTable)
            ZSTD_memcpy(oldHufTable, table->CTable, sizeof(table->CTable));  /* Save new table */
    }
    return HUF_compressCTable_internal(ostart, op, oend,
                                       src, srcSize,
                                       nbStreams, table->CTable, flags);
}

size_t HUF_compress1X_repeat (void* dst, size_t dstSize,
                      const void* src, size_t srcSize,
                      unsigned maxSymbolValue, unsigned huffLog,
                      void* workSpace, size_t wkspSize,
                      HUF_CElt* hufTable, HUF_repeat* repeat, int flags)
{
    DEBUGLOG(5, "HUF_compress1X_repeat (srcSize = %zu)", srcSize);
    return HUF_compress_internal(dst, dstSize, src, srcSize,
                                 maxSymbolValue, huffLog, HUF_singleStream,
                                 workSpace, wkspSize, hufTable,
                                 repeat, flags);
}


size_t HUF_compress4X_repeat (void* dst, size_t dstSize,
                      const void* src, size_t srcSize,
                      unsigned maxSymbolValue, unsigned huffLog,
                      void* workSpace, size_t wkspSize,
                      HUF_CElt* hufTable, HUF_repeat* repeat, int flags)
{
    DEBUGLOG(5, "HUF_compress4X_repeat (srcSize = %zu)", srcSize);
    return HUF_compress_internal(dst, dstSize, src, srcSize,
                                 maxSymbolValue, huffLog, HUF_fourStreams,
                                 workSpace, wkspSize,
                                 hufTable, repeat, flags);
}
/**** ended inlining compress/huf_compress.c ****/
/**** start inlining compress/zstd_compress_literals.c ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */


/**** start inlining zstd_compress_literals.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_COMPRESS_LITERALS_H
#define ZSTD_COMPRESS_LITERALS_H

/**** start inlining zstd_compress_internal.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */



#ifndef ZSTD_COMPRESS_H
#define ZSTD_COMPRESS_H


/**** skipping file: ../common/zstd_internal.h ****/
/**** start inlining zstd_cwksp.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_CWKSP_H
#define ZSTD_CWKSP_H


/**** start inlining ../common/allocations.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */



#define ZSTD_DEPS_NEED_MALLOC
/**** skipping file: zstd_deps.h ****/

/**** skipping file: compiler.h ****/
#define ZSTD_STATIC_LINKING_ONLY
/**** skipping file: ../zstd.h ****/

#ifndef ZSTD_ALLOCATIONS_H
#define ZSTD_ALLOCATIONS_H



MEM_STATIC void* ZSTD_customMalloc(size_t size, ZSTD_customMem customMem)
{
    if (customMem.customAlloc)
        return customMem.customAlloc(customMem.opaque, size);
    return ZSTD_malloc(size);
}

MEM_STATIC void* ZSTD_customCalloc(size_t size, ZSTD_customMem customMem)
{
    if (customMem.customAlloc) {

        void* const ptr = customMem.customAlloc(customMem.opaque, size);

        if (ptr == NULL) {
            return NULL;
        }

        ZSTD_memset(ptr, 0, size);
        return ptr;
    }
    return ZSTD_calloc(1, size);
}

MEM_STATIC void ZSTD_customFree(void* ptr, ZSTD_customMem customMem)
{
    if (ptr!=NULL) {
        if (customMem.customFree)
            customMem.customFree(customMem.opaque, ptr);
        else
            ZSTD_free(ptr);
    }
}

#endif /* ZSTD_ALLOCATIONS_H */
/**** ended inlining ../common/allocations.h ****/
/**** skipping file: ../common/zstd_internal.h ****/
/**** skipping file: ../common/portability_macros.h ****/
/**** skipping file: ../common/compiler.h ****/




#ifndef ZSTD_CWKSP_ASAN_REDZONE_SIZE
#define ZSTD_CWKSP_ASAN_REDZONE_SIZE 128
#endif



#define ZSTD_CWKSP_ALIGNMENT_BYTES 64


typedef enum {
    ZSTD_cwksp_alloc_objects,
    ZSTD_cwksp_alloc_aligned_init_once,
    ZSTD_cwksp_alloc_aligned,
    ZSTD_cwksp_alloc_buffers
} ZSTD_cwksp_alloc_phase_e;


typedef enum {
    ZSTD_cwksp_dynamic_alloc,
    ZSTD_cwksp_static_alloc
} ZSTD_cwksp_static_alloc_e;


typedef struct {
    void* workspace;
    void* workspaceEnd;

    void* objectEnd;
    void* tableEnd;
    void* tableValidEnd;
    void* allocStart;
    void* initOnceStart;

    BYTE allocFailed;
    int workspaceOversizedDuration;
    ZSTD_cwksp_alloc_phase_e phase;
    ZSTD_cwksp_static_alloc_e isStatic;
} ZSTD_cwksp;



MEM_STATIC size_t ZSTD_cwksp_available_space(ZSTD_cwksp* ws);
MEM_STATIC void*  ZSTD_cwksp_initialAllocStart(ZSTD_cwksp* ws);

MEM_STATIC void ZSTD_cwksp_assert_internal_consistency(ZSTD_cwksp* ws) {
    (void)ws;
    assert(ws->workspace <= ws->objectEnd);
    assert(ws->objectEnd <= ws->tableEnd);
    assert(ws->objectEnd <= ws->tableValidEnd);
    assert(ws->tableEnd <= ws->allocStart);
    assert(ws->tableValidEnd <= ws->allocStart);
    assert(ws->allocStart <= ws->workspaceEnd);
    assert(ws->initOnceStart <= ZSTD_cwksp_initialAllocStart(ws));
    assert(ws->workspace <= ws->initOnceStart);
#if ZSTD_MEMORY_SANITIZER
    {
        intptr_t const offset = __msan_test_shadow(ws->initOnceStart,
            (U8*)ZSTD_cwksp_initialAllocStart(ws) - (U8*)ws->initOnceStart);
        (void)offset;
#if defined(ZSTD_MSAN_PRINT)
        if(offset!=-1) {
            __msan_print_shadow((U8*)ws->initOnceStart + offset - 8, 32);
        }
#endif
        assert(offset==-1);
    };
#endif
}


MEM_STATIC size_t ZSTD_cwksp_align(size_t size, size_t align) {
    size_t const mask = align - 1;
    assert(ZSTD_isPower2(align));
    return (size + mask) & ~mask;
}


MEM_STATIC size_t ZSTD_cwksp_alloc_size(size_t size) {
    if (size == 0)
        return 0;
#if ZSTD_ADDRESS_SANITIZER && !defined (ZSTD_ASAN_DONT_POISON_WORKSPACE)
    return size + 2 * ZSTD_CWKSP_ASAN_REDZONE_SIZE;
#else
    return size;
#endif
}

MEM_STATIC size_t ZSTD_cwksp_aligned_alloc_size(size_t size, size_t alignment) {
    return ZSTD_cwksp_alloc_size(ZSTD_cwksp_align(size, alignment));
}


MEM_STATIC size_t ZSTD_cwksp_aligned64_alloc_size(size_t size) {
    return ZSTD_cwksp_aligned_alloc_size(size, ZSTD_CWKSP_ALIGNMENT_BYTES);
}


MEM_STATIC size_t ZSTD_cwksp_slack_space_required(void) {

    size_t const slackSpace = ZSTD_CWKSP_ALIGNMENT_BYTES * 2;
    return slackSpace;
}



MEM_STATIC size_t ZSTD_cwksp_bytes_to_align_ptr(void* ptr, const size_t alignBytes) {
    size_t const alignBytesMask = alignBytes - 1;
    size_t const bytes = (alignBytes - ((size_t)ptr & (alignBytesMask))) & alignBytesMask;
    assert(ZSTD_isPower2(alignBytes));
    assert(bytes < alignBytes);
    return bytes;
}


MEM_STATIC void*  ZSTD_cwksp_initialAllocStart(ZSTD_cwksp* ws)
{
    char* endPtr = (char*)ws->workspaceEnd;
    assert(ZSTD_isPower2(ZSTD_CWKSP_ALIGNMENT_BYTES));
    endPtr = endPtr - ((size_t)endPtr % ZSTD_CWKSP_ALIGNMENT_BYTES);
    return (void*)endPtr;
}


MEM_STATIC void*
ZSTD_cwksp_reserve_internal_buffer_space(ZSTD_cwksp* ws, size_t const bytes)
{
    void* const alloc = (BYTE*)ws->allocStart - bytes;
    void* const bottom = ws->tableEnd;
    DEBUGLOG(5, "cwksp: reserving [0x%p]:%zd bytes; %zd bytes remaining",
        alloc, bytes, ZSTD_cwksp_available_space(ws) - bytes);
    ZSTD_cwksp_assert_internal_consistency(ws);
    assert(alloc >= bottom);
    if (alloc < bottom) {
        DEBUGLOG(4, "cwksp: alloc failed!");
        ws->allocFailed = 1;
        return NULL;
    }

    if (alloc < ws->tableValidEnd) {
        ws->tableValidEnd = alloc;
    }
    ws->allocStart = alloc;
    return alloc;
}


MEM_STATIC size_t
ZSTD_cwksp_internal_advance_phase(ZSTD_cwksp* ws, ZSTD_cwksp_alloc_phase_e phase)
{
    assert(phase >= ws->phase);
    if (phase > ws->phase) {

        if (ws->phase < ZSTD_cwksp_alloc_aligned_init_once &&
            phase >= ZSTD_cwksp_alloc_aligned_init_once) {
            ws->tableValidEnd = ws->objectEnd;
            ws->initOnceStart = ZSTD_cwksp_initialAllocStart(ws);

            {   /* Align the start of the tables to 64 bytes. Use [0, 63] bytes */
                void *const alloc = ws->objectEnd;
                size_t const bytesToAlign = ZSTD_cwksp_bytes_to_align_ptr(alloc, ZSTD_CWKSP_ALIGNMENT_BYTES);
                void *const objectEnd = (BYTE *) alloc + bytesToAlign;
                DEBUGLOG(5, "reserving table alignment addtl space: %zu", bytesToAlign);
                RETURN_ERROR_IF(objectEnd > ws->workspaceEnd, memory_allocation,
                                "table phase - alignment initial allocation failed!");
                ws->objectEnd = objectEnd;
                ws->tableEnd = objectEnd;  /* table area starts being empty */
                if (ws->tableValidEnd < ws->tableEnd) {
                    ws->tableValidEnd = ws->tableEnd;
                }
            }
        }
        ws->phase = phase;
        ZSTD_cwksp_assert_internal_consistency(ws);
    }
    return 0;
}


MEM_STATIC int ZSTD_cwksp_owns_buffer(const ZSTD_cwksp* ws, const void* ptr)
{
    return (ptr != NULL) && (ws->workspace <= ptr) && (ptr < ws->workspaceEnd);
}


MEM_STATIC void*
ZSTD_cwksp_reserve_internal(ZSTD_cwksp* ws, size_t bytes, ZSTD_cwksp_alloc_phase_e phase)
{
    void* alloc;
    if (ZSTD_isError(ZSTD_cwksp_internal_advance_phase(ws, phase)) || bytes == 0) {
        return NULL;
    }

#if ZSTD_ADDRESS_SANITIZER && !defined (ZSTD_ASAN_DONT_POISON_WORKSPACE)

    bytes += 2 * ZSTD_CWKSP_ASAN_REDZONE_SIZE;
#endif

    alloc = ZSTD_cwksp_reserve_internal_buffer_space(ws, bytes);

#if ZSTD_ADDRESS_SANITIZER && !defined (ZSTD_ASAN_DONT_POISON_WORKSPACE)

    if (alloc) {
        alloc = (BYTE *)alloc + ZSTD_CWKSP_ASAN_REDZONE_SIZE;
        if (ws->isStatic == ZSTD_cwksp_dynamic_alloc) {

            __asan_unpoison_memory_region(alloc, bytes - 2 * ZSTD_CWKSP_ASAN_REDZONE_SIZE);
        }
    }
#endif

    return alloc;
}


MEM_STATIC BYTE* ZSTD_cwksp_reserve_buffer(ZSTD_cwksp* ws, size_t bytes)
{
    return (BYTE*)ZSTD_cwksp_reserve_internal(ws, bytes, ZSTD_cwksp_alloc_buffers);
}


MEM_STATIC void* ZSTD_cwksp_reserve_aligned_init_once(ZSTD_cwksp* ws, size_t bytes)
{
    size_t const alignedBytes = ZSTD_cwksp_align(bytes, ZSTD_CWKSP_ALIGNMENT_BYTES);
    void* ptr = ZSTD_cwksp_reserve_internal(ws, alignedBytes, ZSTD_cwksp_alloc_aligned_init_once);
    assert(((size_t)ptr & (ZSTD_CWKSP_ALIGNMENT_BYTES-1)) == 0);
    if(ptr && ptr < ws->initOnceStart) {

        ZSTD_memset(ptr, 0, MIN((size_t)((U8*)ws->initOnceStart - (U8*)ptr), alignedBytes));
        ws->initOnceStart = ptr;
    }
#if ZSTD_MEMORY_SANITIZER
    assert(__msan_test_shadow(ptr, bytes) == -1);
#endif
    return ptr;
}


MEM_STATIC void* ZSTD_cwksp_reserve_aligned64(ZSTD_cwksp* ws, size_t bytes)
{
    void* const ptr = ZSTD_cwksp_reserve_internal(ws,
                        ZSTD_cwksp_align(bytes, ZSTD_CWKSP_ALIGNMENT_BYTES),
                        ZSTD_cwksp_alloc_aligned);
    assert(((size_t)ptr & (ZSTD_CWKSP_ALIGNMENT_BYTES-1)) == 0);
    return ptr;
}


MEM_STATIC void* ZSTD_cwksp_reserve_table(ZSTD_cwksp* ws, size_t bytes)
{
    const ZSTD_cwksp_alloc_phase_e phase = ZSTD_cwksp_alloc_aligned_init_once;
    void* alloc;
    void* end;
    void* top;


    if(ws->phase < phase) {
        if (ZSTD_isError(ZSTD_cwksp_internal_advance_phase(ws, phase))) {
            return NULL;
        }
    }
    alloc = ws->tableEnd;
    end = (BYTE *)alloc + bytes;
    top = ws->allocStart;

    DEBUGLOG(5, "cwksp: reserving %p table %zd bytes, %zd bytes remaining",
        alloc, bytes, ZSTD_cwksp_available_space(ws) - bytes);
    assert((bytes & (sizeof(U32)-1)) == 0);
    ZSTD_cwksp_assert_internal_consistency(ws);
    assert(end <= top);
    if (end > top) {
        DEBUGLOG(4, "cwksp: table alloc failed!");
        ws->allocFailed = 1;
        return NULL;
    }
    ws->tableEnd = end;

#if ZSTD_ADDRESS_SANITIZER && !defined (ZSTD_ASAN_DONT_POISON_WORKSPACE)
    if (ws->isStatic == ZSTD_cwksp_dynamic_alloc) {
        __asan_unpoison_memory_region(alloc, bytes);
    }
#endif

    assert((bytes & (ZSTD_CWKSP_ALIGNMENT_BYTES-1)) == 0);
    assert(((size_t)alloc & (ZSTD_CWKSP_ALIGNMENT_BYTES-1)) == 0);
    return alloc;
}


MEM_STATIC void* ZSTD_cwksp_reserve_object(ZSTD_cwksp* ws, size_t bytes)
{
    size_t const roundedBytes = ZSTD_cwksp_align(bytes, sizeof(void*));
    void* alloc = ws->objectEnd;
    void* end = (BYTE*)alloc + roundedBytes;

#if ZSTD_ADDRESS_SANITIZER && !defined (ZSTD_ASAN_DONT_POISON_WORKSPACE)

    end = (BYTE *)end + 2 * ZSTD_CWKSP_ASAN_REDZONE_SIZE;
#endif

    DEBUGLOG(4,
        "cwksp: reserving %p object %zd bytes (rounded to %zd), %zd bytes remaining",
        alloc, bytes, roundedBytes, ZSTD_cwksp_available_space(ws) - roundedBytes);
    assert((size_t)alloc % ZSTD_ALIGNOF(void*) == 0);
    assert(bytes % ZSTD_ALIGNOF(void*) == 0);
    ZSTD_cwksp_assert_internal_consistency(ws);

    if (ws->phase != ZSTD_cwksp_alloc_objects || end > ws->workspaceEnd) {
        DEBUGLOG(3, "cwksp: object alloc failed!");
        ws->allocFailed = 1;
        return NULL;
    }
    ws->objectEnd = end;
    ws->tableEnd = end;
    ws->tableValidEnd = end;

#if ZSTD_ADDRESS_SANITIZER && !defined (ZSTD_ASAN_DONT_POISON_WORKSPACE)

    alloc = (BYTE*)alloc + ZSTD_CWKSP_ASAN_REDZONE_SIZE;
    if (ws->isStatic == ZSTD_cwksp_dynamic_alloc) {
        __asan_unpoison_memory_region(alloc, bytes);
    }
#endif

    return alloc;
}

MEM_STATIC void* ZSTD_cwksp_reserve_object_aligned(ZSTD_cwksp* ws, size_t byteSize, size_t alignment)
{
    size_t const mask = alignment - 1;
    size_t const surplus = (alignment > sizeof(void*)) ? alignment - sizeof(void*) : 0;
    void* const start = ZSTD_cwksp_reserve_object(ws, byteSize + surplus);
    if (start == NULL) return NULL;
    if (surplus == 0) return start;
    assert(ZSTD_isPower2(alignment));
    return (void*)(((size_t)start + surplus) & ~mask);
}

MEM_STATIC void ZSTD_cwksp_mark_tables_dirty(ZSTD_cwksp* ws)
{
    DEBUGLOG(4, "cwksp: ZSTD_cwksp_mark_tables_dirty");

#if ZSTD_MEMORY_SANITIZER && !defined (ZSTD_MSAN_DONT_POISON_WORKSPACE)

    {
        size_t size = (BYTE*)ws->tableValidEnd - (BYTE*)ws->objectEnd;
        assert(__msan_test_shadow(ws->objectEnd, size) == -1);
        if((BYTE*)ws->tableValidEnd < (BYTE*)ws->initOnceStart) {
            __msan_poison(ws->objectEnd, size);
        } else {
            assert(ws->initOnceStart >= ws->objectEnd);
            __msan_poison(ws->objectEnd, (BYTE*)ws->initOnceStart - (BYTE*)ws->objectEnd);
        }
    }
#endif

    assert(ws->tableValidEnd >= ws->objectEnd);
    assert(ws->tableValidEnd <= ws->allocStart);
    ws->tableValidEnd = ws->objectEnd;
    ZSTD_cwksp_assert_internal_consistency(ws);
}

MEM_STATIC void ZSTD_cwksp_mark_tables_clean(ZSTD_cwksp* ws) {
    DEBUGLOG(4, "cwksp: ZSTD_cwksp_mark_tables_clean");
    assert(ws->tableValidEnd >= ws->objectEnd);
    assert(ws->tableValidEnd <= ws->allocStart);
    if (ws->tableValidEnd < ws->tableEnd) {
        ws->tableValidEnd = ws->tableEnd;
    }
    ZSTD_cwksp_assert_internal_consistency(ws);
}


MEM_STATIC void ZSTD_cwksp_clean_tables(ZSTD_cwksp* ws) {
    DEBUGLOG(4, "cwksp: ZSTD_cwksp_clean_tables");
    assert(ws->tableValidEnd >= ws->objectEnd);
    assert(ws->tableValidEnd <= ws->allocStart);
    if (ws->tableValidEnd < ws->tableEnd) {
        ZSTD_memset(ws->tableValidEnd, 0, (size_t)((BYTE*)ws->tableEnd - (BYTE*)ws->tableValidEnd));
    }
    ZSTD_cwksp_mark_tables_clean(ws);
}


MEM_STATIC void ZSTD_cwksp_clear_tables(ZSTD_cwksp* ws)
{
    DEBUGLOG(4, "cwksp: clearing tables!");

#if ZSTD_ADDRESS_SANITIZER && !defined (ZSTD_ASAN_DONT_POISON_WORKSPACE)

    if (ws->isStatic == ZSTD_cwksp_dynamic_alloc) {
        size_t size = (BYTE*)ws->tableValidEnd - (BYTE*)ws->objectEnd;
        __asan_poison_memory_region(ws->objectEnd, size);
    }
#endif

    ws->tableEnd = ws->objectEnd;
    ZSTD_cwksp_assert_internal_consistency(ws);
}


MEM_STATIC void ZSTD_cwksp_clear(ZSTD_cwksp* ws) {
    DEBUGLOG(4, "cwksp: clearing!");

#if ZSTD_MEMORY_SANITIZER && !defined (ZSTD_MSAN_DONT_POISON_WORKSPACE)

    {
        if((BYTE*)ws->tableValidEnd < (BYTE*)ws->initOnceStart) {
            size_t size = (BYTE*)ws->initOnceStart - (BYTE*)ws->tableValidEnd;
            __msan_poison(ws->tableValidEnd, size);
        }
    }
#endif

#if ZSTD_ADDRESS_SANITIZER && !defined (ZSTD_ASAN_DONT_POISON_WORKSPACE)

    if (ws->isStatic == ZSTD_cwksp_dynamic_alloc) {
        size_t size = (BYTE*)ws->workspaceEnd - (BYTE*)ws->objectEnd;
        __asan_poison_memory_region(ws->objectEnd, size);
    }
#endif

    ws->tableEnd = ws->objectEnd;
    ws->allocStart = ZSTD_cwksp_initialAllocStart(ws);
    ws->allocFailed = 0;
    if (ws->phase > ZSTD_cwksp_alloc_aligned_init_once) {
        ws->phase = ZSTD_cwksp_alloc_aligned_init_once;
    }
    ZSTD_cwksp_assert_internal_consistency(ws);
}

MEM_STATIC size_t ZSTD_cwksp_sizeof(const ZSTD_cwksp* ws) {
    return (size_t)((BYTE*)ws->workspaceEnd - (BYTE*)ws->workspace);
}

MEM_STATIC size_t ZSTD_cwksp_used(const ZSTD_cwksp* ws) {
    return (size_t)((BYTE*)ws->tableEnd - (BYTE*)ws->workspace)
         + (size_t)((BYTE*)ws->workspaceEnd - (BYTE*)ws->allocStart);
}


MEM_STATIC void ZSTD_cwksp_init(ZSTD_cwksp* ws, void* start, size_t size, ZSTD_cwksp_static_alloc_e isStatic) {
    DEBUGLOG(4, "cwksp: init'ing workspace with %zd bytes", size);
    assert(((size_t)start & (sizeof(void*)-1)) == 0); /* ensure correct alignment */
    ws->workspace = start;
    ws->workspaceEnd = (BYTE*)start + size;
    ws->objectEnd = ws->workspace;
    ws->tableValidEnd = ws->objectEnd;
    ws->initOnceStart = ZSTD_cwksp_initialAllocStart(ws);
    ws->phase = ZSTD_cwksp_alloc_objects;
    ws->isStatic = isStatic;
    ZSTD_cwksp_clear(ws);
    ws->workspaceOversizedDuration = 0;
    ZSTD_cwksp_assert_internal_consistency(ws);
}

MEM_STATIC size_t ZSTD_cwksp_create(ZSTD_cwksp* ws, size_t size, ZSTD_customMem customMem) {
    void* workspace = ZSTD_customMalloc(size, customMem);
    DEBUGLOG(4, "cwksp: creating new workspace with %zd bytes", size);
    RETURN_ERROR_IF(workspace == NULL, memory_allocation, "NULL pointer!");
    ZSTD_cwksp_init(ws, workspace, size, ZSTD_cwksp_dynamic_alloc);
    return 0;
}

MEM_STATIC void ZSTD_cwksp_free(ZSTD_cwksp* ws, ZSTD_customMem customMem) {
    void *ptr = ws->workspace;
    DEBUGLOG(4, "cwksp: freeing workspace");
#if ZSTD_MEMORY_SANITIZER && !defined(ZSTD_MSAN_DONT_POISON_WORKSPACE)
    if (ptr != NULL && customMem.customFree != NULL) {
        __msan_unpoison(ptr, ZSTD_cwksp_sizeof(ws));
    }
#endif
    ZSTD_memset(ws, 0, sizeof(ZSTD_cwksp));
    ZSTD_customFree(ptr, customMem);
}


MEM_STATIC void ZSTD_cwksp_move(ZSTD_cwksp* dst, ZSTD_cwksp* src) {
    *dst = *src;
    ZSTD_memset(src, 0, sizeof(ZSTD_cwksp));
}

MEM_STATIC int ZSTD_cwksp_reserve_failed(const ZSTD_cwksp* ws) {
    return ws->allocFailed;
}




MEM_STATIC int ZSTD_cwksp_estimated_space_within_bounds(const ZSTD_cwksp *const ws, size_t const estimatedSpace) {

    return (estimatedSpace - ZSTD_cwksp_slack_space_required()) <= ZSTD_cwksp_used(ws) &&
           ZSTD_cwksp_used(ws) <= estimatedSpace;
}


MEM_STATIC size_t ZSTD_cwksp_available_space(ZSTD_cwksp* ws) {
    return (size_t)((BYTE*)ws->allocStart - (BYTE*)ws->tableEnd);
}

MEM_STATIC int ZSTD_cwksp_check_available(ZSTD_cwksp* ws, size_t additionalNeededSpace) {
    return ZSTD_cwksp_available_space(ws) >= additionalNeededSpace;
}

MEM_STATIC int ZSTD_cwksp_check_too_large(ZSTD_cwksp* ws, size_t additionalNeededSpace) {
    return ZSTD_cwksp_check_available(
        ws, additionalNeededSpace * ZSTD_WORKSPACETOOLARGE_FACTOR);
}

MEM_STATIC int ZSTD_cwksp_check_wasteful(ZSTD_cwksp* ws, size_t additionalNeededSpace) {
    return ZSTD_cwksp_check_too_large(ws, additionalNeededSpace)
        && ws->workspaceOversizedDuration > ZSTD_WORKSPACETOOLARGE_MAXDURATION;
}

MEM_STATIC void ZSTD_cwksp_bump_oversized_duration(
        ZSTD_cwksp* ws, size_t additionalNeededSpace) {
    if (ZSTD_cwksp_check_too_large(ws, additionalNeededSpace)) {
        ws->workspaceOversizedDuration++;
    } else {
        ws->workspaceOversizedDuration = 0;
    }
}

#endif /* ZSTD_CWKSP_H */
/**** ended inlining zstd_cwksp.h ****/
#ifdef ZSTD_MULTITHREAD
#error Using excluded file: zstdmt_compress.h (re-amalgamate source to fix)
#endif
/**** skipping file: ../common/bits.h ****/
/**** start inlining zstd_preSplit.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_PRESPLIT_H
#define ZSTD_PRESPLIT_H

#include <stddef.h>  /* size_t */

#define ZSTD_SLIPBLOCK_WORKSPACESIZE 8208


size_t ZSTD_splitBlock(const void* blockStart, size_t blockSize,
                    int level,
                    void* workspace, size_t wkspSize);

#endif /* ZSTD_PRESPLIT_H */
/**** ended inlining zstd_preSplit.h ****/


#define kSearchStrength      8
#define HASH_READ_SIZE       8
#define ZSTD_DUBT_UNSORTED_MARK 1   /* For btlazy2 strategy, index ZSTD_DUBT_UNSORTED_MARK==1 means "unsorted".
                                       It could be confused for a real successor at index "1", if sorted as larger than its predecessor.
                                       It's not a big deal though : candidate will just be sorted again.
                                       Additionally, candidate position 1 will be lost.
                                       But candidate 1 cannot hide a large tree of candidates, so it's a minimal loss.
                                       The benefit is that ZSTD_DUBT_UNSORTED_MARK cannot be mishandled after table reuse with a different strategy.
                                       This constant is required by ZSTD_compressBlock_btlazy2() and ZSTD_reduceTable_internal() */



typedef enum { ZSTDcs_created=0, ZSTDcs_init, ZSTDcs_ongoing, ZSTDcs_ending } ZSTD_compressionStage_e;
typedef enum { zcss_init=0, zcss_load, zcss_flush } ZSTD_cStreamStage;

typedef struct ZSTD_prefixDict_s {
    const void* dict;
    size_t dictSize;
    ZSTD_dictContentType_e dictContentType;
} ZSTD_prefixDict;

typedef struct {
    void* dictBuffer;
    void const* dict;
    size_t dictSize;
    ZSTD_dictContentType_e dictContentType;
    ZSTD_CDict* cdict;
} ZSTD_localDict;

typedef struct {
    HUF_CElt CTable[HUF_CTABLE_SIZE_ST(255)];
    HUF_repeat repeatMode;
} ZSTD_hufCTables_t;

typedef struct {
    FSE_CTable offcodeCTable[FSE_CTABLE_SIZE_U32(OffFSELog, MaxOff)];
    FSE_CTable matchlengthCTable[FSE_CTABLE_SIZE_U32(MLFSELog, MaxML)];
    FSE_CTable litlengthCTable[FSE_CTABLE_SIZE_U32(LLFSELog, MaxLL)];
    FSE_repeat offcode_repeatMode;
    FSE_repeat matchlength_repeatMode;
    FSE_repeat litlength_repeatMode;
} ZSTD_fseCTables_t;

typedef struct {
    ZSTD_hufCTables_t huf;
    ZSTD_fseCTables_t fse;
} ZSTD_entropyCTables_t;

/***********************************************
*  Sequences *
***********************************************/
typedef struct SeqDef_s {
    U32 offBase;   /* offBase == Offset + ZSTD_REP_NUM, or repcode 1,2,3 */
    U16 litLength;
    U16 mlBase;    /* mlBase == matchLength - MINMATCH */
} SeqDef;


typedef enum {
    ZSTD_llt_none = 0,             /* no longLengthType */
    ZSTD_llt_literalLength = 1,    /* represents a long literal */
    ZSTD_llt_matchLength = 2       /* represents a long match */
} ZSTD_longLengthType_e;

typedef struct {
    SeqDef* sequencesStart;
    SeqDef* sequences;      /* ptr to end of sequences */
    BYTE*  litStart;
    BYTE*  lit;             /* ptr to end of literals */
    BYTE*  llCode;
    BYTE*  mlCode;
    BYTE*  ofCode;
    size_t maxNbSeq;
    size_t maxNbLit;


    ZSTD_longLengthType_e longLengthType;
    U32                   longLengthPos;  /* Index of the sequence to apply long length modification to */
} SeqStore_t;

typedef struct {
    U32 litLength;
    U32 matchLength;
} ZSTD_SequenceLength;


MEM_STATIC ZSTD_SequenceLength ZSTD_getSequenceLength(SeqStore_t const* seqStore, SeqDef const* seq)
{
    ZSTD_SequenceLength seqLen;
    seqLen.litLength = seq->litLength;
    seqLen.matchLength = seq->mlBase + MINMATCH;
    if (seqStore->longLengthPos == (U32)(seq - seqStore->sequencesStart)) {
        if (seqStore->longLengthType == ZSTD_llt_literalLength) {
            seqLen.litLength += 0x10000;
        }
        if (seqStore->longLengthType == ZSTD_llt_matchLength) {
            seqLen.matchLength += 0x10000;
        }
    }
    return seqLen;
}

const SeqStore_t* ZSTD_getSeqStore(const ZSTD_CCtx* ctx);   /* compress & dictBuilder */
int ZSTD_seqToCodes(const SeqStore_t* seqStorePtr);   /* compress, dictBuilder, decodeCorpus (shouldn't get its definition from here) */

void ZSTD_deriveSeqStoreChunk(SeqStore_t* resultSeqStore,
                             const SeqStore_t* originalSeqStore,
                             size_t startIdx, size_t endIdx);


/***********************************************
*  Entropy buffer statistics structs and funcs *
***********************************************/

typedef struct {
    SymbolEncodingType_e hType;
    BYTE hufDesBuffer[ZSTD_MAX_HUF_HEADER_SIZE];
    size_t hufDesSize;
} ZSTD_hufCTablesMetadata_t;


typedef struct {
    SymbolEncodingType_e llType;
    SymbolEncodingType_e ofType;
    SymbolEncodingType_e mlType;
    BYTE fseTablesBuffer[ZSTD_MAX_FSE_HEADERS_SIZE];
    size_t fseTablesSize;
    size_t lastCountSize; /* This is to account for bug in 1.3.4. More detail in ZSTD_entropyCompressSeqStore_internal() */
} ZSTD_fseCTablesMetadata_t;

typedef struct {
    ZSTD_hufCTablesMetadata_t hufMetadata;
    ZSTD_fseCTablesMetadata_t fseMetadata;
} ZSTD_entropyCTablesMetadata_t;


size_t ZSTD_buildBlockEntropyStats(
                    const SeqStore_t* seqStorePtr,
                    const ZSTD_entropyCTables_t* prevEntropy,
                          ZSTD_entropyCTables_t* nextEntropy,
                    const ZSTD_CCtx_params* cctxParams,
                          ZSTD_entropyCTablesMetadata_t* entropyMetadata,
                          void* workspace, size_t wkspSize);

/*********************************
*  Compression internals structs *
*********************************/

typedef struct {
    U32 off;            /* Offset sumtype code for the match, using ZSTD_storeSeq() format */
    U32 len;            /* Raw length of match */
} ZSTD_match_t;

typedef struct {
    U32 offset;         /* Offset of sequence */
    U32 litLength;      /* Length of literals prior to match */
    U32 matchLength;    /* Raw length of match */
} rawSeq;

typedef struct {
  rawSeq* seq;          /* The start of the sequences */
  size_t pos;           /* The index in seq where reading stopped. pos <= size. */
  size_t posInSequence; /* The position within the sequence at seq[pos] where reading
                           stopped. posInSequence <= seq[pos].litLength + seq[pos].matchLength */
  size_t size;          /* The number of sequences. <= capacity. */
  size_t capacity;      /* The capacity starting from `seq` pointer */
} RawSeqStore_t;

UNUSED_ATTR static const RawSeqStore_t kNullRawSeqStore = {NULL, 0, 0, 0, 0};

typedef struct {
    int price;  /* price from beginning of segment to this position */
    U32 off;    /* offset of previous match */
    U32 mlen;   /* length of previous match */
    U32 litlen; /* nb of literals since previous match */
    U32 rep[ZSTD_REP_NUM];  /* offset history after previous match */
} ZSTD_optimal_t;

typedef enum { zop_dynamic=0, zop_predef } ZSTD_OptPrice_e;

#define ZSTD_OPT_SIZE (ZSTD_OPT_NUM+3)
typedef struct {

    unsigned* litFreq;           /* table of literals statistics, of size 256 */
    unsigned* litLengthFreq;     /* table of litLength statistics, of size (MaxLL+1) */
    unsigned* matchLengthFreq;   /* table of matchLength statistics, of size (MaxML+1) */
    unsigned* offCodeFreq;       /* table of offCode statistics, of size (MaxOff+1) */
    ZSTD_match_t* matchTable;    /* list of found matches, of size ZSTD_OPT_SIZE */
    ZSTD_optimal_t* priceTable;  /* All positions tracked by optimal parser, of size ZSTD_OPT_SIZE */

    U32  litSum;                 /* nb of literals */
    U32  litLengthSum;           /* nb of litLength codes */
    U32  matchLengthSum;         /* nb of matchLength codes */
    U32  offCodeSum;             /* nb of offset codes */
    U32  litSumBasePrice;        /* to compare to log2(litfreq) */
    U32  litLengthSumBasePrice;  /* to compare to log2(llfreq)  */
    U32  matchLengthSumBasePrice;/* to compare to log2(mlfreq)  */
    U32  offCodeSumBasePrice;    /* to compare to log2(offreq)  */
    ZSTD_OptPrice_e priceType;   /* prices can be determined dynamically, or follow a pre-defined cost structure */
    const ZSTD_entropyCTables_t* symbolCosts;  /* pre-calculated dictionary statistics */
    ZSTD_ParamSwitch_e literalCompressionMode;
} optState_t;

typedef struct {
  ZSTD_entropyCTables_t entropy;
  U32 rep[ZSTD_REP_NUM];
} ZSTD_compressedBlockState_t;

typedef struct {
    BYTE const* nextSrc;       /* next block here to continue on current prefix */
    BYTE const* base;          /* All regular indexes relative to this position */
    BYTE const* dictBase;      /* extDict indexes relative to this position */
    U32 dictLimit;             /* below that point, need extDict */
    U32 lowLimit;              /* below that point, no more valid data */
    U32 nbOverflowCorrections; /* Number of times overflow correction has run since
                                * ZSTD_window_init(). Useful for debugging coredumps
                                * and for ZSTD_WINDOW_OVERFLOW_CORRECT_FREQUENTLY.
                                */
} ZSTD_window_t;

#define ZSTD_WINDOW_START_INDEX 2

typedef struct ZSTD_MatchState_t ZSTD_MatchState_t;

#define ZSTD_ROW_HASH_CACHE_SIZE 8       /* Size of prefetching hash cache for row-based matchfinder */

struct ZSTD_MatchState_t {
    ZSTD_window_t window;   /* State for window round buffer management */
    U32 loadedDictEnd;      /* index of end of dictionary, within context's referential.
                             * When loadedDictEnd != 0, a dictionary is in use, and still valid.
                             * This relies on a mechanism to set loadedDictEnd=0 when dictionary is no longer within distance.
                             * Such mechanism is provided within ZSTD_window_enforceMaxDist() and ZSTD_checkDictValidity().
                             * When dict referential is copied into active context (i.e. not attached),
                             * loadedDictEnd == dictSize, since referential starts from zero.
                             */
    U32 nextToUpdate;       /* index from which to continue table update */
    U32 hashLog3;           /* dispatch table for matches of len==3 : larger == faster, more memory */

    U32 rowHashLog;                          /* For row-based matchfinder: Hashlog based on nb of rows in the hashTable.*/
    BYTE* tagTable;                          /* For row-based matchFinder: A row-based table containing the hashes and head index. */
    U32 hashCache[ZSTD_ROW_HASH_CACHE_SIZE]; /* For row-based matchFinder: a cache of hashes to improve speed */
    U64 hashSalt;                            /* For row-based matchFinder: salts the hash for reuse of tag table */
    U32 hashSaltEntropy;                     /* For row-based matchFinder: collects entropy for salt generation */

    U32* hashTable;
    U32* hashTable3;
    U32* chainTable;

    int forceNonContiguous; /* Non-zero if we should force non-contiguous load for the next window update. */

    int dedicatedDictSearch;  /* Indicates whether this matchState is using the
                               * dedicated dictionary search structure.
                               */
    optState_t opt;         /* optimal parser state */
    const ZSTD_MatchState_t* dictMatchState;
    ZSTD_compressionParameters cParams;
    const RawSeqStore_t* ldmSeqStore;


    int prefetchCDictTables;


    int lazySkipping;
};

typedef struct {
    ZSTD_compressedBlockState_t* prevCBlock;
    ZSTD_compressedBlockState_t* nextCBlock;
    ZSTD_MatchState_t matchState;
} ZSTD_blockState_t;

typedef struct {
    U32 offset;
    U32 checksum;
} ldmEntry_t;

typedef struct {
    BYTE const* split;
    U32 hash;
    U32 checksum;
    ldmEntry_t* bucket;
} ldmMatchCandidate_t;

#define LDM_BATCH_SIZE 64

typedef struct {
    ZSTD_window_t window;   /* State for the window round buffer management */
    ldmEntry_t* hashTable;
    U32 loadedDictEnd;
    BYTE* bucketOffsets;    /* Next position in bucket to insert entry */
    size_t splitIndices[LDM_BATCH_SIZE];
    ldmMatchCandidate_t matchCandidates[LDM_BATCH_SIZE];
} ldmState_t;

typedef struct {
    ZSTD_ParamSwitch_e enableLdm; /* ZSTD_ps_enable to enable LDM. ZSTD_ps_auto by default */
    U32 hashLog;            /* Log size of hashTable */
    U32 bucketSizeLog;      /* Log bucket size for collision resolution, at most 8 */
    U32 minMatchLength;     /* Minimum match length */
    U32 hashRateLog;       /* Log number of entries to skip */
    U32 windowLog;          /* Window log for the LDM */
} ldmParams_t;

typedef struct {
    int collectSequences;
    ZSTD_Sequence* seqStart;
    size_t seqIndex;
    size_t maxSequences;
} SeqCollector;

struct ZSTD_CCtx_params_s {
    ZSTD_format_e format;
    ZSTD_compressionParameters cParams;
    ZSTD_frameParameters fParams;

    int compressionLevel;
    int forceWindow;           /* force back-references to respect limit of
                                * 1<<wLog, even for dictionary */
    size_t targetCBlockSize;   /* Tries to fit compressed block size to be around targetCBlockSize.
                                * No target when targetCBlockSize == 0.
                                * There is no guarantee on compressed block size */
    int srcSizeHint;           /* User's best guess of source size.
                                * Hint is not valid when srcSizeHint == 0.
                                * There is no guarantee that hint is close to actual source size */

    ZSTD_dictAttachPref_e attachDictPref;
    ZSTD_ParamSwitch_e literalCompressionMode;


    int nbWorkers;
    size_t jobSize;
    int overlapLog;
    int rsyncable;


    ldmParams_t ldmParams;


    int enableDedicatedDictSearch;


    ZSTD_bufferMode_e inBufferMode;
    ZSTD_bufferMode_e outBufferMode;


    ZSTD_SequenceFormat_e blockDelimiters;
    int validateSequences;


    ZSTD_ParamSwitch_e postBlockSplitter;
    int preBlockSplitter_level;


    size_t maxBlockSize;


    ZSTD_ParamSwitch_e useRowMatchFinder;


    int deterministicRefPrefix;


    ZSTD_customMem customMem;


    ZSTD_ParamSwitch_e prefetchCDictTables;


    int enableMatchFinderFallback;


    void* extSeqProdState;
    ZSTD_sequenceProducer_F extSeqProdFunc;


    ZSTD_ParamSwitch_e searchForExternalRepcodes;
};  /* typedef'd to ZSTD_CCtx_params within "zstd.h" */

#define COMPRESS_SEQUENCES_WORKSPACE_SIZE (sizeof(unsigned) * (MaxSeq + 2))
#define ENTROPY_WORKSPACE_SIZE (HUF_WORKSPACE_SIZE + COMPRESS_SEQUENCES_WORKSPACE_SIZE)
#define TMP_WORKSPACE_SIZE (MAX(ENTROPY_WORKSPACE_SIZE, ZSTD_SLIPBLOCK_WORKSPACESIZE))


typedef enum {
    ZSTDb_not_buffered,
    ZSTDb_buffered
} ZSTD_buffered_policy_e;


#define ZSTD_MAX_NB_BLOCK_SPLITS 196
typedef struct {
    SeqStore_t fullSeqStoreChunk;
    SeqStore_t firstHalfSeqStore;
    SeqStore_t secondHalfSeqStore;
    SeqStore_t currSeqStore;
    SeqStore_t nextSeqStore;

    U32 partitions[ZSTD_MAX_NB_BLOCK_SPLITS + 1]; /* splits, followed by the end of the block */
    ZSTD_entropyCTablesMetadata_t entropyMetadata;
} ZSTD_blockSplitCtx;

struct ZSTD_CCtx_s {
    ZSTD_compressionStage_e stage;
    int cParamsChanged;                  /* == 1 if cParams(except wlog) or compression level are changed in requestedParams. Triggers transmission of new params to ZSTDMT (if available) then reset to 0. */
#if DYNAMIC_BMI2
    int bmi2;                            /* == 1 if the CPU supports BMI2 and 0 otherwise when CPU state
                                          * is cached per context. Never read this directly: use ZSTD_CCtx_get_bmi2(),
                                          * which also handles builds
                                          * where cached CPU state is not used. */
#endif
    ZSTD_CCtx_params requestedParams;
    ZSTD_CCtx_params appliedParams;
    ZSTD_CCtx_params simpleApiParams;    /* Param storage used by the simple API - not sticky. Must only be used in top-level simple API functions for storage. */
    U32   dictID;
    size_t dictContentSize;

    ZSTD_cwksp workspace; /* manages buffer for dynamic allocations */
    size_t blockSizeMax;
    unsigned long long pledgedSrcSizePlusOne;  /* this way, 0 (default) == unknown */
    unsigned long long consumedSrcSize;
    unsigned long long producedCSize;
    XXH64_state_t xxhState;
    ZSTD_customMem customMem;
    ZSTD_threadPool* pool;
    size_t staticSize;
    SeqCollector seqCollector;
    int isFirstBlock;
    int initialized;

    SeqStore_t seqStore;      /* sequences storage ptrs */
    ldmState_t ldmState;      /* long distance matching state */
    rawSeq* ldmSequences;     /* Storage for the ldm output sequences */
    size_t maxNbLdmSequences;
    RawSeqStore_t externSeqStore; /* Mutable reference to external sequences */
    ZSTD_blockState_t blockState;
    void* tmpWorkspace;  /* used as substitute of stack space - must be aligned for S64 type */
    size_t tmpWkspSize;


    ZSTD_buffered_policy_e bufferedPolicy;


    char*  inBuff;
    size_t inBuffSize;
    size_t inToCompress;
    size_t inBuffPos;
    size_t inBuffTarget;
    char*  outBuff;
    size_t outBuffSize;
    size_t outBuffContentSize;
    size_t outBuffFlushedSize;
    ZSTD_cStreamStage streamStage;
    U32    frameEnded;


    ZSTD_inBuffer expectedInBuffer;
    size_t stableIn_notConsumed; /* nb bytes within stable input buffer that are said to be consumed but are not */
    size_t expectedOutBufferSize;


    ZSTD_localDict localDict;
    const ZSTD_CDict* cdict;
    ZSTD_prefixDict prefixDict;   /* single-usage dictionary */


#ifdef ZSTD_MULTITHREAD
    ZSTDMT_CCtx* mtctx;
#endif


#if ZSTD_TRACE
    ZSTD_TraceCtx traceCtx;
#endif


    ZSTD_blockSplitCtx blockSplitCtx;


    ZSTD_Sequence* extSeqBuf;
    size_t extSeqBufCapacity;
};


MEM_STATIC int ZSTD_CCtx_get_bmi2(const struct ZSTD_CCtx_s* cctx) {
#if DYNAMIC_BMI2
    return cctx->bmi2;
#else
    (void)cctx;
    return 0;
#endif
}

typedef enum { ZSTD_dtlm_fast, ZSTD_dtlm_full } ZSTD_dictTableLoadMethod_e;
typedef enum { ZSTD_tfp_forCCtx, ZSTD_tfp_forCDict } ZSTD_tableFillPurpose_e;

typedef enum {
    ZSTD_noDict = 0,
    ZSTD_extDict = 1,
    ZSTD_dictMatchState = 2,
    ZSTD_dedicatedDictSearch = 3
} ZSTD_dictMode_e;

typedef enum {
    ZSTD_cpm_noAttachDict = 0,  /* Compression with ZSTD_noDict or ZSTD_extDict.
                                 * In this mode we use both the srcSize and the dictSize
                                 * when selecting and adjusting parameters.
                                 */
    ZSTD_cpm_attachDict = 1,    /* Compression with ZSTD_dictMatchState or ZSTD_dedicatedDictSearch.
                                 * In this mode we only take the srcSize into account when selecting
                                 * and adjusting parameters.
                                 */
    ZSTD_cpm_createCDict = 2,   /* Creating a CDict.
                                 * In this mode we take both the source size and the dictionary size
                                 * into account when selecting and adjusting the parameters.
                                 */
    ZSTD_cpm_unknown = 3        /* ZSTD_getCParams, ZSTD_getParams, ZSTD_adjustParams.
                                 * We don't know what these parameters are for. We default to the legacy
                                 * behavior of taking both the source size and the dict size into account
                                 * when selecting and adjusting parameters.
                                 */
} ZSTD_CParamMode_e;

typedef size_t (*ZSTD_BlockCompressor_f) (
        ZSTD_MatchState_t* bs, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
ZSTD_BlockCompressor_f ZSTD_selectBlockCompressor(ZSTD_strategy strat, ZSTD_ParamSwitch_e rowMatchfinderMode, ZSTD_dictMode_e dictMode);


MEM_STATIC U32 ZSTD_LLcode(U32 litLength)
{
    static const BYTE LL_Code[64] = {  0,  1,  2,  3,  4,  5,  6,  7,
                                       8,  9, 10, 11, 12, 13, 14, 15,
                                      16, 16, 17, 17, 18, 18, 19, 19,
                                      20, 20, 20, 20, 21, 21, 21, 21,
                                      22, 22, 22, 22, 22, 22, 22, 22,
                                      23, 23, 23, 23, 23, 23, 23, 23,
                                      24, 24, 24, 24, 24, 24, 24, 24,
                                      24, 24, 24, 24, 24, 24, 24, 24 };
    static const U32 LL_deltaCode = 19;
    return (litLength > 63) ? ZSTD_highbit32(litLength) + LL_deltaCode : LL_Code[litLength];
}


MEM_STATIC U32 ZSTD_MLcode(U32 mlBase)
{
    static const BYTE ML_Code[128] = { 0,  1,  2,  3,  4,  5,  6,  7,  8,  9, 10, 11, 12, 13, 14, 15,
                                      16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31,
                                      32, 32, 33, 33, 34, 34, 35, 35, 36, 36, 36, 36, 37, 37, 37, 37,
                                      38, 38, 38, 38, 38, 38, 38, 38, 39, 39, 39, 39, 39, 39, 39, 39,
                                      40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40, 40,
                                      41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41,
                                      42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42,
                                      42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42 };
    static const U32 ML_deltaCode = 36;
    return (mlBase > 127) ? ZSTD_highbit32(mlBase) + ML_deltaCode : ML_Code[mlBase];
}


MEM_STATIC int ZSTD_cParam_withinBounds(ZSTD_cParameter cParam, int value)
{
    ZSTD_bounds const bounds = ZSTD_cParam_getBounds(cParam);
    if (ZSTD_isError(bounds.error)) return 0;
    if (value < bounds.lowerBound) return 0;
    if (value > bounds.upperBound) return 0;
    return 1;
}


MEM_STATIC const BYTE*
ZSTD_selectAddr(U32 index, U32 lowLimit, const BYTE* candidate, const BYTE* backup)
{
#if defined(__GNUC__) && defined(__x86_64__)
    __asm__ (
        "cmp %1, %2\n"
        "cmova %3, %0\n"
        : "+r"(candidate)
        : "r"(index), "r"(lowLimit), "r"(backup)
        );
    return candidate;
#else
    return index >= lowLimit ? candidate : backup;
#endif
}


MEM_STATIC size_t
ZSTD_noCompressBlock(void* dst, size_t dstCapacity, const void* src, size_t srcSize, U32 lastBlock)
{
    U32 const cBlockHeader24 = lastBlock + (((U32)bt_raw)<<1) + (U32)(srcSize << 3);
    DEBUGLOG(5, "ZSTD_noCompressBlock (srcSize=%zu, dstCapacity=%zu)", srcSize, dstCapacity);
    RETURN_ERROR_IF(srcSize + ZSTD_blockHeaderSize > dstCapacity,
                    dstSize_tooSmall, "dst buf too small for uncompressed block");
    MEM_writeLE24(dst, cBlockHeader24);
    ZSTD_memcpy((BYTE*)dst + ZSTD_blockHeaderSize, src, srcSize);
    return ZSTD_blockHeaderSize + srcSize;
}

MEM_STATIC size_t
ZSTD_rleCompressBlock(void* dst, size_t dstCapacity, BYTE src, size_t srcSize, U32 lastBlock)
{
    BYTE* const op = (BYTE*)dst;
    U32 const cBlockHeader = lastBlock + (((U32)bt_rle)<<1) + (U32)(srcSize << 3);
    RETURN_ERROR_IF(dstCapacity < 4, dstSize_tooSmall, "");
    MEM_writeLE24(op, cBlockHeader);
    op[3] = src;
    return 4;
}



MEM_STATIC size_t ZSTD_minGain(size_t srcSize, ZSTD_strategy strat)
{
    U32 const minlog = (strat>=ZSTD_btultra) ? (U32)(strat) - 1 : 6;
    ZSTD_STATIC_ASSERT(ZSTD_btultra == 8);
    assert(ZSTD_cParam_withinBounds(ZSTD_c_strategy, (int)strat));
    return (srcSize >> minlog) + 2;
}

MEM_STATIC int ZSTD_literalsCompressionIsDisabled(const ZSTD_CCtx_params* cctxParams)
{
    switch (cctxParams->literalCompressionMode) {
    case ZSTD_ps_enable:
        return 0;
    case ZSTD_ps_disable:
        return 1;
    default:
        assert(0 /* impossible: pre-validated */);
        ZSTD_FALLTHROUGH;
    case ZSTD_ps_auto:
        return (cctxParams->cParams.strategy == ZSTD_fast) && (cctxParams->cParams.targetLength > 0);
    }
}


static void
ZSTD_safecopyLiterals(BYTE* op, BYTE const* ip, BYTE const* const iend, BYTE const* ilimit_w)
{
    assert(iend > ilimit_w);
    if (ip <= ilimit_w) {
        ZSTD_wildcopy(op, ip, (size_t)(ilimit_w - ip), ZSTD_no_overlap);
        op += ilimit_w - ip;
        ip = ilimit_w;
    }
    while (ip < iend) *op++ = *ip++;
}


#define REPCODE1_TO_OFFBASE REPCODE_TO_OFFBASE(1)
#define REPCODE2_TO_OFFBASE REPCODE_TO_OFFBASE(2)
#define REPCODE3_TO_OFFBASE REPCODE_TO_OFFBASE(3)
#define REPCODE_TO_OFFBASE(r) (assert((r)>=1), assert((r)<=ZSTD_REP_NUM), (r)) /* accepts IDs 1,2,3 */
#define OFFSET_TO_OFFBASE(o)  (assert((o)>0), o + ZSTD_REP_NUM)
#define OFFBASE_IS_OFFSET(o)  ((o) > ZSTD_REP_NUM)
#define OFFBASE_IS_REPCODE(o) ( 1 <= (o) && (o) <= ZSTD_REP_NUM)
#define OFFBASE_TO_OFFSET(o)  (assert(OFFBASE_IS_OFFSET(o)), (o) - ZSTD_REP_NUM)
#define OFFBASE_TO_REPCODE(o) (assert(OFFBASE_IS_REPCODE(o)), (o))  /* returns ID 1,2,3 */


HINT_INLINE UNUSED_ATTR void
ZSTD_storeSeqOnly(SeqStore_t* seqStorePtr,
              size_t litLength,
              U32 offBase,
              size_t matchLength)
{
    assert((size_t)(seqStorePtr->sequences - seqStorePtr->sequencesStart) < seqStorePtr->maxNbSeq);


    assert(litLength <= ZSTD_BLOCKSIZE_MAX);
    if (UNLIKELY(litLength>0xFFFF)) {
        assert(seqStorePtr->longLengthType == ZSTD_llt_none); /* there can only be a single long length */
        seqStorePtr->longLengthType = ZSTD_llt_literalLength;
        seqStorePtr->longLengthPos = (U32)(seqStorePtr->sequences - seqStorePtr->sequencesStart);
    }
    seqStorePtr->sequences[0].litLength = (U16)litLength;


    seqStorePtr->sequences[0].offBase = offBase;


    assert(matchLength <= ZSTD_BLOCKSIZE_MAX);
    assert(matchLength >= MINMATCH);
    {   size_t const mlBase = matchLength - MINMATCH;
        if (UNLIKELY(mlBase>0xFFFF)) {
            assert(seqStorePtr->longLengthType == ZSTD_llt_none); /* there can only be a single long length */
            seqStorePtr->longLengthType = ZSTD_llt_matchLength;
            seqStorePtr->longLengthPos = (U32)(seqStorePtr->sequences - seqStorePtr->sequencesStart);
        }
        seqStorePtr->sequences[0].mlBase = (U16)mlBase;
    }

    seqStorePtr->sequences++;
}


HINT_INLINE UNUSED_ATTR void
ZSTD_storeSeq(SeqStore_t* seqStorePtr,
              size_t litLength, const BYTE* literals, const BYTE* litLimit,
              U32 offBase,
              size_t matchLength)
{
    BYTE const* const litLimit_w = litLimit - WILDCOPY_OVERLENGTH;
    BYTE const* const litEnd = literals + litLength;
#if defined(DEBUGLEVEL) && (DEBUGLEVEL >= 6)
    static const BYTE* g_start = NULL;
    if (g_start==NULL) g_start = (const BYTE*)literals;  /* note : index only works for compression within a single segment */
    {   U32 const pos = (U32)((const BYTE*)literals - g_start);
        DEBUGLOG(6, "Cpos%7u :%3u literals, match%4u bytes at offBase%7u",
               pos, (U32)litLength, (U32)matchLength, (U32)offBase);
    }
#endif
    assert((size_t)(seqStorePtr->sequences - seqStorePtr->sequencesStart) < seqStorePtr->maxNbSeq);

    assert(seqStorePtr->maxNbLit <= 128 KB);
    assert(seqStorePtr->lit + litLength <= seqStorePtr->litStart + seqStorePtr->maxNbLit);
    assert(literals + litLength <= litLimit);
    if (litEnd <= litLimit_w) {

        ZSTD_STATIC_ASSERT(WILDCOPY_OVERLENGTH >= 16);
        ZSTD_copy16(seqStorePtr->lit, literals);
        if (litLength > 16) {
            ZSTD_wildcopy(seqStorePtr->lit+16, literals+16, litLength-16, ZSTD_no_overlap);
        }
    } else {
        ZSTD_safecopyLiterals(seqStorePtr->lit, literals, litEnd, litLimit_w);
    }
    seqStorePtr->lit += litLength;

    ZSTD_storeSeqOnly(seqStorePtr, litLength, offBase, matchLength);
}


MEM_STATIC void
ZSTD_updateRep(U32 rep[ZSTD_REP_NUM], U32 const offBase, U32 const ll0)
{
    if (OFFBASE_IS_OFFSET(offBase)) {  /* full offset */
        rep[2] = rep[1];
        rep[1] = rep[0];
        rep[0] = OFFBASE_TO_OFFSET(offBase);
    } else {   /* repcode */
        U32 const repCode = OFFBASE_TO_REPCODE(offBase) - 1 + ll0;
        if (repCode > 0) {  /* note : if repCode==0, no change */
            U32 const currentOffset = (repCode==ZSTD_REP_NUM) ? (rep[0] - 1) : rep[repCode];
            rep[2] = (repCode >= 2) ? rep[1] : rep[2];
            rep[1] = rep[0];
            rep[0] = currentOffset;
        } else {   /* repCode == 0 */

        }
    }
}

typedef struct repcodes_s {
    U32 rep[3];
} Repcodes_t;

MEM_STATIC Repcodes_t
ZSTD_newRep(U32 const rep[ZSTD_REP_NUM], U32 const offBase, U32 const ll0)
{
    Repcodes_t newReps;
    ZSTD_memcpy(&newReps, rep, sizeof(newReps));
    ZSTD_updateRep(newReps.rep, offBase, ll0);
    return newReps;
}



MEM_STATIC size_t ZSTD_count(const BYTE* pIn, const BYTE* pMatch, const BYTE* const pInLimit)
{
    const BYTE* const pStart = pIn;
    const BYTE* const pInLoopLimit = pInLimit - (sizeof(size_t)-1);

    if (pIn < pInLoopLimit) {
        { size_t const diff = MEM_readST(pMatch) ^ MEM_readST(pIn);
          if (diff) return ZSTD_NbCommonBytes(diff); }
        pIn+=sizeof(size_t); pMatch+=sizeof(size_t);
        while (pIn < pInLoopLimit) {
            size_t const diff = MEM_readST(pMatch) ^ MEM_readST(pIn);
            if (!diff) { pIn+=sizeof(size_t); pMatch+=sizeof(size_t); continue; }
            pIn += ZSTD_NbCommonBytes(diff);
            return (size_t)(pIn - pStart);
    }   }
    if (MEM_64bits() && (pIn<(pInLimit-3)) && (MEM_read32(pMatch) == MEM_read32(pIn))) { pIn+=4; pMatch+=4; }
    if ((pIn<(pInLimit-1)) && (MEM_read16(pMatch) == MEM_read16(pIn))) { pIn+=2; pMatch+=2; }
    if ((pIn<pInLimit) && (*pMatch == *pIn)) pIn++;
    return (size_t)(pIn - pStart);
}


MEM_STATIC size_t
ZSTD_count_2segments(const BYTE* ip, const BYTE* match,
                     const BYTE* iEnd, const BYTE* mEnd, const BYTE* iStart)
{
    const BYTE* const vEnd = MIN( ip + (mEnd - match), iEnd);
    size_t const matchLength = ZSTD_count(ip, match, vEnd);
    if (match + matchLength != mEnd) return matchLength;
    DEBUGLOG(7, "ZSTD_count_2segments: found a 2-parts match (current length==%zu)", matchLength);
    DEBUGLOG(7, "distance from match beginning to end dictionary = %i", (int)(mEnd - match));
    DEBUGLOG(7, "distance from current pos to end buffer = %i", (int)(iEnd - ip));
    DEBUGLOG(7, "next byte : ip==%02X, istart==%02X", ip[matchLength], *iStart);
    DEBUGLOG(7, "final match length = %zu", matchLength + ZSTD_count(ip+matchLength, iStart, iEnd));
    return matchLength + ZSTD_count(ip+matchLength, iStart, iEnd);
}



static const U32 prime3bytes = 506832829U;
static U32    ZSTD_hash3(U32 u, U32 h, U32 s) { assert(h <= 32); return (((u << (32-24)) * prime3bytes) ^ s)  >> (32-h) ; }
MEM_STATIC size_t ZSTD_hash3Ptr(const void* ptr, U32 h) { return ZSTD_hash3(MEM_readLE32(ptr), h, 0); } /* only in zstd_opt.h */
MEM_STATIC size_t ZSTD_hash3PtrS(const void* ptr, U32 h, U32 s) { return ZSTD_hash3(MEM_readLE32(ptr), h, s); }

static const U32 prime4bytes = 2654435761U;
static U32    ZSTD_hash4(U32 u, U32 h, U32 s) { assert(h <= 32); return ((u * prime4bytes) ^ s) >> (32-h) ; }
static size_t ZSTD_hash4Ptr(const void* ptr, U32 h) { return ZSTD_hash4(MEM_readLE32(ptr), h, 0); }
static size_t ZSTD_hash4PtrS(const void* ptr, U32 h, U32 s) { return ZSTD_hash4(MEM_readLE32(ptr), h, s); }

static const U64 prime5bytes = 889523592379ULL;
static size_t ZSTD_hash5(U64 u, U32 h, U64 s) { assert(h <= 64); return (size_t)((((u  << (64-40)) * prime5bytes) ^ s) >> (64-h)) ; }
static size_t ZSTD_hash5Ptr(const void* p, U32 h) { return ZSTD_hash5(MEM_readLE64(p), h, 0); }
static size_t ZSTD_hash5PtrS(const void* p, U32 h, U64 s) { return ZSTD_hash5(MEM_readLE64(p), h, s); }

static const U64 prime6bytes = 227718039650203ULL;
static size_t ZSTD_hash6(U64 u, U32 h, U64 s) { assert(h <= 64); return (size_t)((((u  << (64-48)) * prime6bytes) ^ s) >> (64-h)) ; }
static size_t ZSTD_hash6Ptr(const void* p, U32 h) { return ZSTD_hash6(MEM_readLE64(p), h, 0); }
static size_t ZSTD_hash6PtrS(const void* p, U32 h, U64 s) { return ZSTD_hash6(MEM_readLE64(p), h, s); }

static const U64 prime7bytes = 58295818150454627ULL;
static size_t ZSTD_hash7(U64 u, U32 h, U64 s) { assert(h <= 64); return (size_t)((((u  << (64-56)) * prime7bytes) ^ s) >> (64-h)) ; }
static size_t ZSTD_hash7Ptr(const void* p, U32 h) { return ZSTD_hash7(MEM_readLE64(p), h, 0); }
static size_t ZSTD_hash7PtrS(const void* p, U32 h, U64 s) { return ZSTD_hash7(MEM_readLE64(p), h, s); }

static const U64 prime8bytes = 0xCF1BBCDCB7A56463ULL;
static size_t ZSTD_hash8(U64 u, U32 h, U64 s) { assert(h <= 64); return (size_t)((((u) * prime8bytes)  ^ s) >> (64-h)) ; }
static size_t ZSTD_hash8Ptr(const void* p, U32 h) { return ZSTD_hash8(MEM_readLE64(p), h, 0); }
static size_t ZSTD_hash8PtrS(const void* p, U32 h, U64 s) { return ZSTD_hash8(MEM_readLE64(p), h, s); }


MEM_STATIC FORCE_INLINE_ATTR
size_t ZSTD_hashPtr(const void* p, U32 hBits, U32 mls)
{

    assert(hBits <= 32);

    switch(mls)
    {
    default:
    case 4: return ZSTD_hash4Ptr(p, hBits);
    case 5: return ZSTD_hash5Ptr(p, hBits);
    case 6: return ZSTD_hash6Ptr(p, hBits);
    case 7: return ZSTD_hash7Ptr(p, hBits);
    case 8: return ZSTD_hash8Ptr(p, hBits);
    }
}

MEM_STATIC FORCE_INLINE_ATTR
size_t ZSTD_hashPtrSalted(const void* p, U32 hBits, U32 mls, const U64 hashSalt) {

    assert(hBits <= 32);

    switch(mls)
    {
        default:
        case 4: return ZSTD_hash4PtrS(p, hBits, (U32)hashSalt);
        case 5: return ZSTD_hash5PtrS(p, hBits, hashSalt);
        case 6: return ZSTD_hash6PtrS(p, hBits, hashSalt);
        case 7: return ZSTD_hash7PtrS(p, hBits, hashSalt);
        case 8: return ZSTD_hash8PtrS(p, hBits, hashSalt);
    }
}



static U64 ZSTD_ipow(U64 base, U64 exponent)
{
    U64 power = 1;
    while (exponent) {
      if (exponent & 1) power *= base;
      exponent >>= 1;
      base *= base;
    }
    return power;
}

#define ZSTD_ROLL_HASH_CHAR_OFFSET 10


static U64 ZSTD_rollingHash_append(U64 hash, void const* buf, size_t size)
{
    BYTE const* istart = (BYTE const*)buf;
    size_t pos;
    for (pos = 0; pos < size; ++pos) {
        hash *= prime8bytes;
        hash += istart[pos] + ZSTD_ROLL_HASH_CHAR_OFFSET;
    }
    return hash;
}


MEM_STATIC U64 ZSTD_rollingHash_compute(void const* buf, size_t size)
{
    return ZSTD_rollingHash_append(0, buf, size);
}


MEM_STATIC U64 ZSTD_rollingHash_primePower(U32 length)
{
    return ZSTD_ipow(prime8bytes, length - 1);
}


MEM_STATIC U64 ZSTD_rollingHash_rotate(U64 hash, BYTE toRemove, BYTE toAdd, U64 primePower)
{
    hash -= (toRemove + ZSTD_ROLL_HASH_CHAR_OFFSET) * primePower;
    hash *= prime8bytes;
    hash += toAdd + ZSTD_ROLL_HASH_CHAR_OFFSET;
    return hash;
}



#define ZSTD_CURRENT_MAX (MEM_64bits() ? 3500U MB : 2000U MB)

#define ZSTD_CHUNKSIZE_MAX                                                     \
    ( ((U32)-1)                  /* Maximum ending current index */            \
    - ZSTD_CURRENT_MAX)          /* Maximum beginning lowLimit */


MEM_STATIC void ZSTD_window_clear(ZSTD_window_t* window)
{
    size_t const endT = (size_t)(window->nextSrc - window->base);
    U32 const end = (U32)endT;

    window->lowLimit = end;
    window->dictLimit = end;
}

MEM_STATIC U32 ZSTD_window_isEmpty(ZSTD_window_t const window)
{
    return window.dictLimit == ZSTD_WINDOW_START_INDEX &&
           window.lowLimit == ZSTD_WINDOW_START_INDEX &&
           (window.nextSrc - window.base) == ZSTD_WINDOW_START_INDEX;
}


MEM_STATIC U32 ZSTD_window_hasExtDict(ZSTD_window_t const window)
{
    return window.lowLimit < window.dictLimit;
}


MEM_STATIC ZSTD_dictMode_e ZSTD_matchState_dictMode(const ZSTD_MatchState_t *ms)
{
    return ZSTD_window_hasExtDict(ms->window) ?
        ZSTD_extDict :
        ms->dictMatchState != NULL ?
            (ms->dictMatchState->dedicatedDictSearch ? ZSTD_dedicatedDictSearch : ZSTD_dictMatchState) :
            ZSTD_noDict;
}


#ifndef ZSTD_WINDOW_OVERFLOW_CORRECT_FREQUENTLY
#  ifdef FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION
#    define ZSTD_WINDOW_OVERFLOW_CORRECT_FREQUENTLY 1
#  else
#    define ZSTD_WINDOW_OVERFLOW_CORRECT_FREQUENTLY 0
#  endif
#endif


MEM_STATIC U32 ZSTD_window_canOverflowCorrect(ZSTD_window_t const window,
                                              U32 cycleLog,
                                              U32 maxDist,
                                              U32 loadedDictEnd,
                                              void const* src)
{
    U32 const cycleSize = 1u << cycleLog;
    U32 const curr = (U32)((BYTE const*)src - window.base);
    U32 const minIndexToOverflowCorrect = cycleSize
                                        + MAX(maxDist, cycleSize)
                                        + ZSTD_WINDOW_START_INDEX;


    U32 const adjustment = window.nbOverflowCorrections + 1;
    U32 const adjustedIndex = MAX(minIndexToOverflowCorrect * adjustment,
                                  minIndexToOverflowCorrect);
    U32 const indexLargeEnough = curr > adjustedIndex;


    U32 const dictionaryInvalidated = curr > maxDist + loadedDictEnd;

    return indexLargeEnough && dictionaryInvalidated;
}


MEM_STATIC U32 ZSTD_window_needOverflowCorrection(ZSTD_window_t const window,
                                                  U32 cycleLog,
                                                  U32 maxDist,
                                                  U32 loadedDictEnd,
                                                  void const* src,
                                                  void const* srcEnd)
{
    U32 const curr = (U32)((BYTE const*)srcEnd - window.base);
    if (ZSTD_WINDOW_OVERFLOW_CORRECT_FREQUENTLY) {
        if (ZSTD_window_canOverflowCorrect(window, cycleLog, maxDist, loadedDictEnd, src)) {
            return 1;
        }
    }
    return curr > ZSTD_CURRENT_MAX;
}


MEM_STATIC
ZSTD_ALLOW_POINTER_OVERFLOW_ATTR
U32 ZSTD_window_correctOverflow(ZSTD_window_t* window, U32 cycleLog,
                                           U32 maxDist, void const* src)
{

    U32 const cycleSize = 1u << cycleLog;
    U32 const cycleMask = cycleSize - 1;
    U32 const curr = (U32)((BYTE const*)src - window->base);
    U32 const currentCycle = curr & cycleMask;

    U32 const currentCycleCorrection = currentCycle < ZSTD_WINDOW_START_INDEX
                                     ? MAX(cycleSize, ZSTD_WINDOW_START_INDEX)
                                     : 0;
    U32 const newCurrent = currentCycle
                         + currentCycleCorrection
                         + MAX(maxDist, cycleSize);
    U32 const correction = curr - newCurrent;

    assert((maxDist & (maxDist - 1)) == 0);
    assert((curr & cycleMask) == (newCurrent & cycleMask));
    assert(curr > newCurrent);
    if (!ZSTD_WINDOW_OVERFLOW_CORRECT_FREQUENTLY) {

        assert(correction > 1<<28);
    }

    window->base += correction;
    window->dictBase += correction;
    if (window->lowLimit < correction + ZSTD_WINDOW_START_INDEX) {
        window->lowLimit = ZSTD_WINDOW_START_INDEX;
    } else {
        window->lowLimit -= correction;
    }
    if (window->dictLimit < correction + ZSTD_WINDOW_START_INDEX) {
        window->dictLimit = ZSTD_WINDOW_START_INDEX;
    } else {
        window->dictLimit -= correction;
    }


    assert(newCurrent >= maxDist);
    assert(newCurrent - maxDist >= ZSTD_WINDOW_START_INDEX);

    assert(window->lowLimit <= newCurrent);
    assert(window->dictLimit <= newCurrent);

    ++window->nbOverflowCorrections;

    DEBUGLOG(4, "Correction of 0x%x bytes to lowLimit=0x%x", correction,
             window->lowLimit);
    return correction;
}


MEM_STATIC void
ZSTD_window_enforceMaxDist(ZSTD_window_t* window,
                     const void* blockEnd,
                           U32   maxDist,
                           U32*  loadedDictEndPtr,
                     const ZSTD_MatchState_t** dictMatchStatePtr)
{
    U32 const blockEndIdx = (U32)((BYTE const*)blockEnd - window->base);
    U32 const loadedDictEnd = (loadedDictEndPtr != NULL) ? *loadedDictEndPtr : 0;
    DEBUGLOG(5, "ZSTD_window_enforceMaxDist: blockEndIdx=%u, maxDist=%u, loadedDictEnd=%u",
                (unsigned)blockEndIdx, (unsigned)maxDist, (unsigned)loadedDictEnd);


    if (blockEndIdx > maxDist + loadedDictEnd) {
        U32 const newLowLimit = blockEndIdx - maxDist;
        if (window->lowLimit < newLowLimit) window->lowLimit = newLowLimit;
        if (window->dictLimit < window->lowLimit) {
            DEBUGLOG(5, "Update dictLimit to match lowLimit, from %u to %u",
                        (unsigned)window->dictLimit, (unsigned)window->lowLimit);
            window->dictLimit = window->lowLimit;
        }

        if (loadedDictEndPtr) *loadedDictEndPtr = 0;
        if (dictMatchStatePtr) *dictMatchStatePtr = NULL;
    }
}


MEM_STATIC void
ZSTD_checkDictValidity(const ZSTD_window_t* window,
                       const void* blockEnd,
                             U32   maxDist,
                             U32*  loadedDictEndPtr,
                       const ZSTD_MatchState_t** dictMatchStatePtr)
{
    assert(loadedDictEndPtr != NULL);
    assert(dictMatchStatePtr != NULL);
    {   U32 const blockEndIdx = (U32)((BYTE const*)blockEnd - window->base);
        U32 const loadedDictEnd = *loadedDictEndPtr;
        DEBUGLOG(5, "ZSTD_checkDictValidity: blockEndIdx=%u, maxDist=%u, loadedDictEnd=%u",
                    (unsigned)blockEndIdx, (unsigned)maxDist, (unsigned)loadedDictEnd);
        assert(blockEndIdx >= loadedDictEnd);

        if (blockEndIdx > loadedDictEnd + maxDist || loadedDictEnd != window->dictLimit) {

            DEBUGLOG(6, "invalidating dictionary for current block (distance > windowSize)");
            *loadedDictEndPtr = 0;
            *dictMatchStatePtr = NULL;
        } else {
            if (*loadedDictEndPtr != 0) {
                DEBUGLOG(6, "dictionary considered valid for current block");
    }   }   }
}

MEM_STATIC void ZSTD_window_init(ZSTD_window_t* window) {
    ZSTD_memset(window, 0, sizeof(*window));
    window->base = (BYTE const*)" ";
    window->dictBase = (BYTE const*)" ";
    ZSTD_STATIC_ASSERT(ZSTD_DUBT_UNSORTED_MARK < ZSTD_WINDOW_START_INDEX); /* Start above ZSTD_DUBT_UNSORTED_MARK */
    window->dictLimit = ZSTD_WINDOW_START_INDEX;    /* start from >0, so that 1st position is valid */
    window->lowLimit = ZSTD_WINDOW_START_INDEX;     /* it ensures first and later CCtx usages compress the same */
    window->nextSrc = window->base + ZSTD_WINDOW_START_INDEX;   /* see issue #1241 */
    window->nbOverflowCorrections = 0;
}


MEM_STATIC
ZSTD_ALLOW_POINTER_OVERFLOW_ATTR
U32 ZSTD_window_update(ZSTD_window_t* window,
                 const void* src, size_t srcSize,
                       int forceNonContiguous)
{
    BYTE const* const ip = (BYTE const*)src;
    U32 contiguous = 1;
    DEBUGLOG(5, "ZSTD_window_update");
    if (srcSize == 0)
        return contiguous;
    assert(window->base != NULL);
    assert(window->dictBase != NULL);

    if (src != window->nextSrc || forceNonContiguous) {

        size_t const distanceFromBase = (size_t)(window->nextSrc - window->base);
        DEBUGLOG(5, "Non contiguous blocks, new segment starts at %u", window->dictLimit);
        window->lowLimit = window->dictLimit;
        assert(distanceFromBase == (size_t)(U32)distanceFromBase);  /* should never overflow */
        window->dictLimit = (U32)distanceFromBase;
        window->dictBase = window->base;
        window->base = ip - distanceFromBase;

        if (window->dictLimit - window->lowLimit < HASH_READ_SIZE) window->lowLimit = window->dictLimit;   /* too small extDict */
        contiguous = 0;
    }
    window->nextSrc = ip + srcSize;

    if ( (ip+srcSize > window->dictBase + window->lowLimit)
       & (ip < window->dictBase + window->dictLimit)) {
        size_t const highInputIdx = (size_t)((ip + srcSize) - window->dictBase);
        U32 const lowLimitMax = (highInputIdx > (size_t)window->dictLimit) ? window->dictLimit : (U32)highInputIdx;
        assert(highInputIdx < UINT_MAX);
        window->lowLimit = lowLimitMax;
        DEBUGLOG(5, "Overlapping extDict and input : new lowLimit = %u", window->lowLimit);
    }
    return contiguous;
}


MEM_STATIC U32 ZSTD_getLowestMatchIndex(const ZSTD_MatchState_t* ms, U32 curr, unsigned windowLog)
{
    U32 const maxDistance = 1U << windowLog;
    U32 const lowestValid = ms->window.lowLimit;
    U32 const withinWindow = (curr - lowestValid > maxDistance) ? curr - maxDistance : lowestValid;
    U32 const isDictionary = (ms->loadedDictEnd != 0);

    U32 const matchLowest = isDictionary ? lowestValid : withinWindow;
    return matchLowest;
}


MEM_STATIC U32 ZSTD_getLowestPrefixIndex(const ZSTD_MatchState_t* ms, U32 curr, unsigned windowLog)
{
    U32    const maxDistance = 1U << windowLog;
    U32    const lowestValid = ms->window.dictLimit;
    U32    const withinWindow = (curr - lowestValid > maxDistance) ? curr - maxDistance : lowestValid;
    U32    const isDictionary = (ms->loadedDictEnd != 0);

    U32    const matchLowest = isDictionary ? lowestValid : withinWindow;
    return matchLowest;
}


MEM_STATIC int ZSTD_index_overlap_check(const U32 prefixLowestIndex, const U32 repIndex) {
    return ((U32)((prefixLowestIndex-1)  - repIndex) >= 3);
}



#if (DEBUGLEVEL>=2)

MEM_STATIC double ZSTD_fWeight(U32 rawStat)
{
    U32 const fp_accuracy = 8;
    U32 const fp_multiplier = (1 << fp_accuracy);
    U32 const newStat = rawStat + 1;
    U32 const hb = ZSTD_highbit32(newStat);
    U32 const BWeight = hb * fp_multiplier;
    U32 const FWeight = (newStat << fp_accuracy) >> hb;
    U32 const weight = BWeight + FWeight;
    assert(hb + fp_accuracy < 31);
    return (double)weight / fp_multiplier;
}


MEM_STATIC void ZSTD_debugTable(const U32* table, U32 max)
{
    unsigned u, sum;
    for (u=0, sum=0; u<=max; u++) sum += table[u];
    DEBUGLOG(2, "total nb elts: %u", sum);
    for (u=0; u<=max; u++) {
        DEBUGLOG(2, "%2u: %5u  (%.2f)",
                u, table[u], ZSTD_fWeight(sum) - ZSTD_fWeight(table[u]) );
    }
}

#endif




#define ZSTD_SHORT_CACHE_TAG_BITS 8
#define ZSTD_SHORT_CACHE_TAG_MASK ((1u << ZSTD_SHORT_CACHE_TAG_BITS) - 1)


MEM_STATIC void ZSTD_writeTaggedIndex(U32* const hashTable, size_t hashAndTag, U32 index) {
    size_t const hash = hashAndTag >> ZSTD_SHORT_CACHE_TAG_BITS;
    U32 const tag = (U32)(hashAndTag & ZSTD_SHORT_CACHE_TAG_MASK);
    assert(index >> (32 - ZSTD_SHORT_CACHE_TAG_BITS) == 0);
    hashTable[hash] = (index << ZSTD_SHORT_CACHE_TAG_BITS) | tag;
}


MEM_STATIC int ZSTD_comparePackedTags(size_t packedTag1, size_t packedTag2) {
    U32 const tag1 = packedTag1 & ZSTD_SHORT_CACHE_TAG_MASK;
    U32 const tag2 = packedTag2 & ZSTD_SHORT_CACHE_TAG_MASK;
    return tag1 == tag2;
}




size_t ZSTD_loadCEntropy(ZSTD_compressedBlockState_t* bs, void* workspace,
                         const void* const dict, size_t dictSize);

void ZSTD_reset_compressedBlockState(ZSTD_compressedBlockState_t* bs);

typedef struct {
    U32 idx;            /* Index in array of ZSTD_Sequence */
    U64 posInSequence;  /* Position within sequence at idx. The sum of its lengths may exceed U32. */
    size_t posInSrc;    /* Number of bytes given by sequences provided so far */
} ZSTD_SequencePosition;


size_t ZSTD_convertBlockSequences(ZSTD_CCtx* cctx,
                        const ZSTD_Sequence* const inSeqs, size_t nbSequences,
                        int repcodeResolution);

typedef struct {
    size_t nbSequences;
    size_t blockSize;
    size_t litSize;
} BlockSummary;

BlockSummary ZSTD_get1BlockSummary(const ZSTD_Sequence* seqs, size_t nbSeqs);




ZSTD_compressionParameters ZSTD_getCParamsFromCCtxParams(
        const ZSTD_CCtx_params* CCtxParams, U64 srcSizeHint, size_t dictSize, ZSTD_CParamMode_e mode);


size_t ZSTD_initCStream_internal(ZSTD_CStream* zcs,
                     const void* dict, size_t dictSize,
                     const ZSTD_CDict* cdict,
                     const ZSTD_CCtx_params* params, unsigned long long pledgedSrcSize);

void ZSTD_resetSeqStore(SeqStore_t* ssPtr);


ZSTD_compressionParameters ZSTD_getCParamsFromCDict(const ZSTD_CDict* cdict);


size_t ZSTD_compressBegin_advanced_internal(ZSTD_CCtx* cctx,
                                    const void* dict, size_t dictSize,
                                    ZSTD_dictContentType_e dictContentType,
                                    ZSTD_dictTableLoadMethod_e dtlm,
                                    const ZSTD_CDict* cdict,
                                    const ZSTD_CCtx_params* params,
                                    unsigned long long pledgedSrcSize);


size_t ZSTD_compress_advanced_internal(ZSTD_CCtx* cctx,
                                       void* dst, size_t dstCapacity,
                                 const void* src, size_t srcSize,
                                 const void* dict,size_t dictSize,
                                 const ZSTD_CCtx_params* params);



size_t ZSTD_writeLastEmptyBlock(void* dst, size_t dstCapacity);



void ZSTD_referenceExternalSequences(ZSTD_CCtx* cctx, rawSeq* seq, size_t nbSeq);


U32 ZSTD_cycleLog(U32 hashLog, ZSTD_strategy strat);


void ZSTD_CCtx_trace(ZSTD_CCtx* cctx, size_t extraCSize);


MEM_STATIC int ZSTD_hasExtSeqProd(const ZSTD_CCtx_params* params) {
    return params->extSeqProdFunc != NULL;
}



size_t ZSTD_compressBegin_usingCDict_deprecated(ZSTD_CCtx* cctx, const ZSTD_CDict* cdict);

size_t ZSTD_compressContinue_public(ZSTD_CCtx* cctx,
                                    void* dst, size_t dstCapacity,
                              const void* src, size_t srcSize);

size_t ZSTD_compressEnd_public(ZSTD_CCtx* cctx,
                               void* dst, size_t dstCapacity,
                         const void* src, size_t srcSize);

size_t ZSTD_compressBlock_deprecated(ZSTD_CCtx* cctx, void* dst, size_t dstCapacity, const void* src, size_t srcSize);


#endif /* ZSTD_COMPRESS_H */
/**** ended inlining zstd_compress_internal.h ****/


size_t ZSTD_noCompressLiterals (void* dst, size_t dstCapacity, const void* src, size_t srcSize);


size_t ZSTD_compressRleLiteralsBlock (void* dst, size_t dstCapacity, const void* src, size_t srcSize);


size_t ZSTD_compressLiterals (void* dst, size_t dstCapacity,
                        const void* src, size_t srcSize,
                              void* entropyWorkspace, size_t entropyWorkspaceSize,
                        const ZSTD_hufCTables_t* prevHuf,
                              ZSTD_hufCTables_t* nextHuf,
                              ZSTD_strategy strategy, int disableLiteralCompression,
                              int suspectUncompressible,
                              int bmi2);

#endif /* ZSTD_COMPRESS_LITERALS_H */
/**** ended inlining zstd_compress_literals.h ****/



#if DEBUGLEVEL >= 2

static size_t showHexa(const void* src, size_t srcSize)
{
    const BYTE* const ip = (const BYTE*)src;
    size_t u;
    for (u=0; u<srcSize; u++) {
        RAWLOG(5, " %02X", ip[u]); (void)ip;
    }
    RAWLOG(5, " \n");
    return srcSize;
}

#endif



size_t ZSTD_noCompressLiterals (void* dst, size_t dstCapacity, const void* src, size_t srcSize)
{
    BYTE* const ostart = (BYTE*)dst;
    U32   const flSize = 1 + (srcSize>31) + (srcSize>4095);

    DEBUGLOG(5, "ZSTD_noCompressLiterals: srcSize=%zu, dstCapacity=%zu", srcSize, dstCapacity);

    RETURN_ERROR_IF(srcSize + flSize > dstCapacity, dstSize_tooSmall, "");

    switch(flSize)
    {
        case 1: /* 2 - 1 - 5 */
            ostart[0] = (BYTE)((U32)set_basic + (srcSize<<3));
            break;
        case 2: /* 2 - 2 - 12 */
            MEM_writeLE16(ostart, (U16)((U32)set_basic + (1<<2) + (srcSize<<4)));
            break;
        case 3: /* 2 - 2 - 20 */
            MEM_writeLE32(ostart, (U32)((U32)set_basic + (3<<2) + (srcSize<<4)));
            break;
        default:   /* not necessary : flSize is {1,2,3} */
            assert(0);
    }

    ZSTD_memcpy(ostart + flSize, src, srcSize);
    DEBUGLOG(5, "Raw (uncompressed) literals: %u -> %u", (U32)srcSize, (U32)(srcSize + flSize));
    return srcSize + flSize;
}

static int allBytesIdentical(const void* src, size_t srcSize)
{
    assert(srcSize >= 1);
    assert(src != NULL);
    {   const BYTE b = ((const BYTE*)src)[0];
        size_t p;
        for (p=1; p<srcSize; p++) {
            if (((const BYTE*)src)[p] != b) return 0;
        }
        return 1;
    }
}

size_t ZSTD_compressRleLiteralsBlock (void* dst, size_t dstCapacity, const void* src, size_t srcSize)
{
    BYTE* const ostart = (BYTE*)dst;
    U32   const flSize = 1 + (srcSize>31) + (srcSize>4095);

    assert(dstCapacity >= 4); (void)dstCapacity;
    assert(allBytesIdentical(src, srcSize));

    switch(flSize)
    {
        case 1: /* 2 - 1 - 5 */
            ostart[0] = (BYTE)((U32)set_rle + (srcSize<<3));
            break;
        case 2: /* 2 - 2 - 12 */
            MEM_writeLE16(ostart, (U16)((U32)set_rle + (1<<2) + (srcSize<<4)));
            break;
        case 3: /* 2 - 2 - 20 */
            MEM_writeLE32(ostart, (U32)((U32)set_rle + (3<<2) + (srcSize<<4)));
            break;
        default:   /* not necessary : flSize is {1,2,3} */
            assert(0);
    }

    ostart[flSize] = *(const BYTE*)src;
    DEBUGLOG(5, "RLE : Repeated Literal (%02X: %u times) -> %u bytes encoded", ((const BYTE*)src)[0], (U32)srcSize, (U32)flSize + 1);
    return flSize+1;
}


static size_t
ZSTD_minLiteralsToCompress(ZSTD_strategy strategy, HUF_repeat huf_repeat)
{
    assert((int)strategy >= 0);
    assert((int)strategy <= 9);

    {   int const shift = MIN(9-(int)strategy, 3);
        size_t const mintc = (huf_repeat == HUF_repeat_valid) ? 6 : (size_t)8 << shift;
        DEBUGLOG(7, "minLiteralsToCompress = %zu", mintc);
        return mintc;
    }
}

size_t ZSTD_compressLiterals (
                  void* dst, size_t dstCapacity,
            const void* src, size_t srcSize,
                  void* entropyWorkspace, size_t entropyWorkspaceSize,
            const ZSTD_hufCTables_t* prevHuf,
                  ZSTD_hufCTables_t* nextHuf,
                  ZSTD_strategy strategy,
                  int disableLiteralCompression,
                  int suspectUncompressible,
                  int bmi2)
{
    size_t const lhSize = 3 + (srcSize >= 1 KB) + (srcSize >= 16 KB);
    BYTE*  const ostart = (BYTE*)dst;
    U32 singleStream = srcSize < 256;
    SymbolEncodingType_e hType = set_compressed;
    size_t cLitSize;

    DEBUGLOG(5,"ZSTD_compressLiterals (disableLiteralCompression=%i, srcSize=%u, dstCapacity=%zu)",
                disableLiteralCompression, (U32)srcSize, dstCapacity);

    DEBUGLOG(6, "Completed literals listing (%zu bytes)", showHexa(src, srcSize));


    ZSTD_memcpy(nextHuf, prevHuf, sizeof(*prevHuf));

    if (disableLiteralCompression)
        return ZSTD_noCompressLiterals(dst, dstCapacity, src, srcSize);


    if (srcSize < ZSTD_minLiteralsToCompress(strategy, prevHuf->repeatMode))
        return ZSTD_noCompressLiterals(dst, dstCapacity, src, srcSize);

    RETURN_ERROR_IF(dstCapacity < lhSize+1, dstSize_tooSmall, "not enough space for compression");
    {   HUF_repeat repeat = prevHuf->repeatMode;
        int const flags = 0
            | (bmi2 ? HUF_flags_bmi2 : 0)
            | (strategy < ZSTD_lazy && srcSize <= 1024 ? HUF_flags_preferRepeat : 0)
            | (strategy >= HUF_OPTIMAL_DEPTH_THRESHOLD ? HUF_flags_optimalDepth : 0)
            | (suspectUncompressible ? HUF_flags_suspectUncompressible : 0);

        typedef size_t (*huf_compress_f)(void*, size_t, const void*, size_t, unsigned, unsigned, void*, size_t, HUF_CElt*, HUF_repeat*, int);
        huf_compress_f huf_compress;
        if (repeat == HUF_repeat_valid && lhSize == 3) singleStream = 1;
        huf_compress = singleStream ? HUF_compress1X_repeat : HUF_compress4X_repeat;
        cLitSize = huf_compress(ostart+lhSize, dstCapacity-lhSize,
                                src, srcSize,
                                HUF_SYMBOLVALUE_MAX, LitHufLog,
                                entropyWorkspace, entropyWorkspaceSize,
                                (HUF_CElt*)nextHuf->CTable,
                                &repeat, flags);
        DEBUGLOG(5, "%zu literals compressed into %zu bytes (before header)", srcSize, cLitSize);
        if (repeat != HUF_repeat_none) {

            DEBUGLOG(5, "reusing statistics from previous huffman block");
            hType = set_repeat;
        }
    }

    {   size_t const minGain = ZSTD_minGain(srcSize, strategy);
        if ((cLitSize==0) || (cLitSize >= srcSize - minGain) || ERR_isError(cLitSize)) {
            ZSTD_memcpy(nextHuf, prevHuf, sizeof(*prevHuf));
            return ZSTD_noCompressLiterals(dst, dstCapacity, src, srcSize);
    }   }
    if (cLitSize==1) {

        if ((srcSize >= 8) || allBytesIdentical(src, srcSize)) {
            ZSTD_memcpy(nextHuf, prevHuf, sizeof(*prevHuf));
            return ZSTD_compressRleLiteralsBlock(dst, dstCapacity, src, srcSize);
    }   }

    if (hType == set_compressed) {

        nextHuf->repeatMode = HUF_repeat_check;
    }


    switch(lhSize)
    {
    case 3: /* 2 - 2 - 10 - 10 */
        if (!singleStream) assert(srcSize >= MIN_LITERALS_FOR_4_STREAMS);
        {   U32 const lhc = hType + ((U32)(!singleStream) << 2) + ((U32)srcSize<<4) + ((U32)cLitSize<<14);
            MEM_writeLE24(ostart, lhc);
            break;
        }
    case 4: /* 2 - 2 - 14 - 14 */
        assert(srcSize >= MIN_LITERALS_FOR_4_STREAMS);
        {   U32 const lhc = hType + (2 << 2) + ((U32)srcSize<<4) + ((U32)cLitSize<<18);
            MEM_writeLE32(ostart, lhc);
            break;
        }
    case 5: /* 2 - 2 - 18 - 18 */
        assert(srcSize >= MIN_LITERALS_FOR_4_STREAMS);
        {   U32 const lhc = hType + (3 << 2) + ((U32)srcSize<<4) + ((U32)cLitSize<<22);
            MEM_writeLE32(ostart, lhc);
            ostart[4] = (BYTE)(cLitSize >> 10);
            break;
        }
    default:  /* not possible : lhSize is {3,4,5} */
        assert(0);
    }
    DEBUGLOG(5, "Compressed literals: %u -> %u", (U32)srcSize, (U32)(lhSize+cLitSize));
    return lhSize+cLitSize;
}
/**** ended inlining compress/zstd_compress_literals.c ****/
/**** start inlining compress/zstd_compress_sequences.c ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */


/**** skipping file: ../common/bmi2.h ****/
/**** start inlining zstd_compress_sequences.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_COMPRESS_SEQUENCES_H
#define ZSTD_COMPRESS_SEQUENCES_H

/**** skipping file: zstd_compress_internal.h ****/
/**** skipping file: ../common/fse.h ****/
/**** skipping file: ../common/zstd_internal.h ****/

typedef enum {
    ZSTD_defaultDisallowed = 0,
    ZSTD_defaultAllowed = 1
} ZSTD_DefaultPolicy_e;

SymbolEncodingType_e
ZSTD_selectEncodingType(
        FSE_repeat* repeatMode, unsigned const* count, unsigned const max,
        size_t const mostFrequent, size_t nbSeq, unsigned const FSELog,
        FSE_CTable const* prevCTable,
        short const* defaultNorm, U32 defaultNormLog,
        ZSTD_DefaultPolicy_e const isDefaultAllowed,
        ZSTD_strategy const strategy);

size_t
ZSTD_buildCTable(void* dst, size_t dstCapacity,
                FSE_CTable* nextCTable, U32 FSELog, SymbolEncodingType_e type,
                unsigned* count, U32 max,
                const BYTE* codeTable, size_t nbSeq,
                const S16* defaultNorm, U32 defaultNormLog, U32 defaultMax,
                const FSE_CTable* prevCTable, size_t prevCTableSize,
                void* entropyWorkspace, size_t entropyWorkspaceSize);

size_t ZSTD_encodeSequences(
            void* dst, size_t dstCapacity,
            FSE_CTable const* CTable_MatchLength, BYTE const* mlCodeTable,
            FSE_CTable const* CTable_OffsetBits, BYTE const* ofCodeTable,
            FSE_CTable const* CTable_LitLength, BYTE const* llCodeTable,
            SeqDef const* sequences, size_t nbSeq, int longOffsets, int bmi2);

size_t ZSTD_fseBitCost(
    FSE_CTable const* ctable,
    unsigned const* count,
    unsigned const max);

size_t ZSTD_crossEntropyCost(short const* norm, unsigned accuracyLog,
                             unsigned const* count, unsigned const max);
#endif /* ZSTD_COMPRESS_SEQUENCES_H */
/**** ended inlining zstd_compress_sequences.h ****/


static unsigned const kInverseProbabilityLog256[256] = {
    0,    2048, 1792, 1642, 1536, 1453, 1386, 1329, 1280, 1236, 1197, 1162,
    1130, 1100, 1073, 1047, 1024, 1001, 980,  960,  941,  923,  906,  889,
    874,  859,  844,  830,  817,  804,  791,  779,  768,  756,  745,  734,
    724,  714,  704,  694,  685,  676,  667,  658,  650,  642,  633,  626,
    618,  610,  603,  595,  588,  581,  574,  567,  561,  554,  548,  542,
    535,  529,  523,  517,  512,  506,  500,  495,  489,  484,  478,  473,
    468,  463,  458,  453,  448,  443,  438,  434,  429,  424,  420,  415,
    411,  407,  402,  398,  394,  390,  386,  382,  377,  373,  370,  366,
    362,  358,  354,  350,  347,  343,  339,  336,  332,  329,  325,  322,
    318,  315,  311,  308,  305,  302,  298,  295,  292,  289,  286,  282,
    279,  276,  273,  270,  267,  264,  261,  258,  256,  253,  250,  247,
    244,  241,  239,  236,  233,  230,  228,  225,  222,  220,  217,  215,
    212,  209,  207,  204,  202,  199,  197,  194,  192,  190,  187,  185,
    182,  180,  178,  175,  173,  171,  168,  166,  164,  162,  159,  157,
    155,  153,  151,  149,  146,  144,  142,  140,  138,  136,  134,  132,
    130,  128,  126,  123,  121,  119,  117,  115,  114,  112,  110,  108,
    106,  104,  102,  100,  98,   96,   94,   93,   91,   89,   87,   85,
    83,   82,   80,   78,   76,   74,   73,   71,   69,   67,   66,   64,
    62,   61,   59,   57,   55,   54,   52,   50,   49,   47,   46,   44,
    42,   41,   39,   37,   36,   34,   33,   31,   30,   28,   26,   25,
    23,   22,   20,   19,   17,   16,   14,   13,   11,   10,   8,    7,
    5,    4,    2,    1,
};

static unsigned ZSTD_getFSEMaxSymbolValue(FSE_CTable const* ctable) {
  void const* ptr = ctable;
  U16 const* u16ptr = (U16 const*)ptr;
  U32 const maxSymbolValue = MEM_read16(u16ptr + 1);
  return maxSymbolValue;
}


static unsigned ZSTD_useLowProbCount(size_t const nbSeq)
{

    return nbSeq >= 2048;
}


static size_t ZSTD_NCountCost(unsigned const* count, unsigned const max,
                              size_t const nbSeq, unsigned const FSELog)
{
    BYTE wksp[FSE_NCOUNTBOUND];
    S16 norm[MaxSeq + 1];
    const U32 tableLog = FSE_optimalTableLog(FSELog, nbSeq, max);
    FORWARD_IF_ERROR(FSE_normalizeCount(norm, tableLog, count, nbSeq, max, ZSTD_useLowProbCount(nbSeq)), "");
    return FSE_writeNCount(wksp, sizeof(wksp), norm, max, tableLog);
}


static size_t ZSTD_entropyCost(unsigned const* count, unsigned const max, size_t const total)
{
    unsigned cost = 0;
    unsigned s;

    assert(total > 0);
    for (s = 0; s <= max; ++s) {
        unsigned norm = (unsigned)((256 * count[s]) / total);
        if (count[s] != 0 && norm == 0)
            norm = 1;
        assert(count[s] < total);
        cost += count[s] * kInverseProbabilityLog256[norm];
    }
    return cost >> 8;
}


size_t ZSTD_fseBitCost(
    FSE_CTable const* ctable,
    unsigned const* count,
    unsigned const max)
{
    unsigned const kAccuracyLog = 8;
    size_t cost = 0;
    unsigned s;
    FSE_CState_t cstate;
    FSE_initCState(&cstate, ctable);
    if (ZSTD_getFSEMaxSymbolValue(ctable) < max) {
        DEBUGLOG(5, "Repeat FSE_CTable has maxSymbolValue %u < %u",
                    ZSTD_getFSEMaxSymbolValue(ctable), max);
        return ERROR(GENERIC);
    }
    for (s = 0; s <= max; ++s) {
        unsigned const tableLog = cstate.stateLog;
        unsigned const badCost = (tableLog + 1) << kAccuracyLog;
        unsigned const bitCost = FSE_bitCost(cstate.symbolTT, tableLog, s, kAccuracyLog);
        if (count[s] == 0)
            continue;
        if (bitCost >= badCost) {
            DEBUGLOG(5, "Repeat FSE_CTable has Prob[%u] == 0", s);
            return ERROR(GENERIC);
        }
        cost += (size_t)count[s] * bitCost;
    }
    return cost >> kAccuracyLog;
}


size_t ZSTD_crossEntropyCost(short const* norm, unsigned accuracyLog,
                             unsigned const* count, unsigned const max)
{
    unsigned const shift = 8 - accuracyLog;
    size_t cost = 0;
    unsigned s;
    assert(accuracyLog <= 8);
    for (s = 0; s <= max; ++s) {
        unsigned const normAcc = (norm[s] != -1) ? (unsigned)norm[s] : 1;
        unsigned const norm256 = normAcc << shift;
        assert(norm256 > 0);
        assert(norm256 < 256);
        cost += count[s] * kInverseProbabilityLog256[norm256];
    }
    return cost >> 8;
}

SymbolEncodingType_e
ZSTD_selectEncodingType(
        FSE_repeat* repeatMode, unsigned const* count, unsigned const max,
        size_t const mostFrequent, size_t nbSeq, unsigned const FSELog,
        FSE_CTable const* prevCTable,
        short const* defaultNorm, U32 defaultNormLog,
        ZSTD_DefaultPolicy_e const isDefaultAllowed,
        ZSTD_strategy const strategy)
{
    ZSTD_STATIC_ASSERT(ZSTD_defaultDisallowed == 0 && ZSTD_defaultAllowed != 0);
    if (mostFrequent == nbSeq) {
        *repeatMode = FSE_repeat_none;
        if (isDefaultAllowed && nbSeq <= 2) {

            DEBUGLOG(5, "Selected set_basic");
            return set_basic;
        }
        DEBUGLOG(5, "Selected set_rle");
        return set_rle;
    }
    if (strategy < ZSTD_lazy) {
        if (isDefaultAllowed) {
            size_t const staticFse_nbSeq_max = 1000;
            size_t const mult = 10 - strategy;
            size_t const baseLog = 3;
            size_t const dynamicFse_nbSeq_min = (((size_t)1 << defaultNormLog) * mult) >> baseLog;  /* 28-36 for offset, 56-72 for lengths */
            assert(defaultNormLog >= 5 && defaultNormLog <= 6);  /* xx_DEFAULTNORMLOG */
            assert(mult <= 9 && mult >= 7);
            if ( (*repeatMode == FSE_repeat_valid)
              && (nbSeq < staticFse_nbSeq_max) ) {
                DEBUGLOG(5, "Selected set_repeat");
                return set_repeat;
            }
            if ( (nbSeq < dynamicFse_nbSeq_min)
              || (mostFrequent < (nbSeq >> (defaultNormLog-1))) ) {
                DEBUGLOG(5, "Selected set_basic");

                *repeatMode = FSE_repeat_none;
                return set_basic;
            }
        }
    } else {
        size_t const basicCost = isDefaultAllowed ? ZSTD_crossEntropyCost(defaultNorm, defaultNormLog, count, max) : ERROR(GENERIC);
        size_t const repeatCost = *repeatMode != FSE_repeat_none ? ZSTD_fseBitCost(prevCTable, count, max) : ERROR(GENERIC);
        size_t const NCountCost = ZSTD_NCountCost(count, max, nbSeq, FSELog);
        size_t const compressedCost = (NCountCost << 3) + ZSTD_entropyCost(count, max, nbSeq);

        if (isDefaultAllowed) {
            assert(!ZSTD_isError(basicCost));
            assert(!(*repeatMode == FSE_repeat_valid && ZSTD_isError(repeatCost)));
        }
        assert(!ZSTD_isError(NCountCost));
        assert(compressedCost < ERROR(maxCode));
        DEBUGLOG(5, "Estimated bit costs: basic=%u\trepeat=%u\tcompressed=%u",
                    (unsigned)basicCost, (unsigned)repeatCost, (unsigned)compressedCost);
        if (basicCost <= repeatCost && basicCost <= compressedCost) {
            DEBUGLOG(5, "Selected set_basic");
            assert(isDefaultAllowed);
            *repeatMode = FSE_repeat_none;
            return set_basic;
        }
        if (repeatCost <= compressedCost) {
            DEBUGLOG(5, "Selected set_repeat");
            assert(!ZSTD_isError(repeatCost));
            return set_repeat;
        }
        assert(compressedCost < basicCost && compressedCost < repeatCost);
    }
    DEBUGLOG(5, "Selected set_compressed");
    *repeatMode = FSE_repeat_check;
    return set_compressed;
}

typedef struct {
    S16 norm[MaxSeq + 1];
    U32 wksp[FSE_BUILD_CTABLE_WORKSPACE_SIZE_U32(MaxSeq, MaxFSELog)];
} ZSTD_BuildCTableWksp;

size_t
ZSTD_buildCTable(void* dst, size_t dstCapacity,
                FSE_CTable* nextCTable, U32 FSELog, SymbolEncodingType_e type,
                unsigned* count, U32 max,
                const BYTE* codeTable, size_t nbSeq,
                const S16* defaultNorm, U32 defaultNormLog, U32 defaultMax,
                const FSE_CTable* prevCTable, size_t prevCTableSize,
                void* entropyWorkspace, size_t entropyWorkspaceSize)
{
    BYTE* op = (BYTE*)dst;
    const BYTE* const oend = op + dstCapacity;
    DEBUGLOG(6, "ZSTD_buildCTable (dstCapacity=%u)", (unsigned)dstCapacity);

    switch (type) {
    case set_rle:
        FORWARD_IF_ERROR(FSE_buildCTable_rle(nextCTable, (BYTE)max), "");
        RETURN_ERROR_IF(dstCapacity==0, dstSize_tooSmall, "not enough space");
        *op = codeTable[0];
        return 1;
    case set_repeat:
        ZSTD_memcpy(nextCTable, prevCTable, prevCTableSize);
        return 0;
    case set_basic:
        FORWARD_IF_ERROR(FSE_buildCTable_wksp(nextCTable, defaultNorm, defaultMax, defaultNormLog, entropyWorkspace, entropyWorkspaceSize), "");  /* note : could be pre-calculated */
        return 0;
    case set_compressed: {
        ZSTD_BuildCTableWksp* wksp = (ZSTD_BuildCTableWksp*)entropyWorkspace;
        size_t nbSeq_1 = nbSeq;
        const U32 tableLog = FSE_optimalTableLog(FSELog, nbSeq, max);
        if (count[codeTable[nbSeq-1]] > 1) {
            count[codeTable[nbSeq-1]]--;
            nbSeq_1--;
        }
        assert(nbSeq_1 > 1);
        assert(entropyWorkspaceSize >= sizeof(ZSTD_BuildCTableWksp));
        (void)entropyWorkspaceSize;
        FORWARD_IF_ERROR(FSE_normalizeCount(wksp->norm, tableLog, count, nbSeq_1, max, ZSTD_useLowProbCount(nbSeq_1)), "FSE_normalizeCount failed");
        assert(oend >= op);
        {   size_t const NCountSize = FSE_writeNCount(op, (size_t)(oend - op), wksp->norm, max, tableLog);   /* overflow protected */
            FORWARD_IF_ERROR(NCountSize, "FSE_writeNCount failed");
            FORWARD_IF_ERROR(FSE_buildCTable_wksp(nextCTable, wksp->norm, max, tableLog, wksp->wksp, sizeof(wksp->wksp)), "FSE_buildCTable_wksp failed");
            return NCountSize;
        }
    }
    default: assert(0); RETURN_ERROR(GENERIC, "impossible to reach");
    }
}

FORCE_INLINE_TEMPLATE size_t
ZSTD_encodeSequences_body(
            void* dst, size_t dstCapacity,
            FSE_CTable const* CTable_MatchLength, BYTE const* mlCodeTable,
            FSE_CTable const* CTable_OffsetBits, BYTE const* ofCodeTable,
            FSE_CTable const* CTable_LitLength, BYTE const* llCodeTable,
            SeqDef const* sequences, size_t nbSeq, int longOffsets)
{
    BIT_CStream_t blockStream;
    FSE_CState_t  stateMatchLength;
    FSE_CState_t  stateOffsetBits;
    FSE_CState_t  stateLitLength;

    assert(MEM_32bits() || !longOffsets);
    RETURN_ERROR_IF(
        ERR_isError(BIT_initCStream(&blockStream, dst, dstCapacity)),
        dstSize_tooSmall, "not enough space remaining");
    DEBUGLOG(6, "available space for bitstream : %i  (dstCapacity=%u)",
                (int)(blockStream.endPtr - blockStream.startPtr),
                (unsigned)dstCapacity);


    FSE_initCState2(&stateMatchLength, CTable_MatchLength, mlCodeTable[nbSeq-1]);
    FSE_initCState2(&stateOffsetBits,  CTable_OffsetBits,  ofCodeTable[nbSeq-1]);
    FSE_initCState2(&stateLitLength,   CTable_LitLength,   llCodeTable[nbSeq-1]);
    BIT_addBits(&blockStream, sequences[nbSeq-1].litLength, LL_bits[llCodeTable[nbSeq-1]]);
    if (MEM_32bits()) BIT_flushBits(&blockStream);
    BIT_addBits(&blockStream, sequences[nbSeq-1].mlBase, ML_bits[mlCodeTable[nbSeq-1]]);
    if (MEM_32bits()) BIT_flushBits(&blockStream);
    if (MEM_32bits() && longOffsets) {
        U32 const ofBits = ofCodeTable[nbSeq-1];
        unsigned const extraBits = ofBits - MIN(ofBits, STREAM_ACCUMULATOR_MIN-1);
        if (extraBits) {
            BIT_addBits(&blockStream, sequences[nbSeq-1].offBase, extraBits);
            BIT_flushBits(&blockStream);
        }
        BIT_addBits(&blockStream, sequences[nbSeq-1].offBase >> extraBits,
                    ofBits - extraBits);
    } else {
        BIT_addBits(&blockStream, sequences[nbSeq-1].offBase, ofCodeTable[nbSeq-1]);
    }
    BIT_flushBits(&blockStream);

    {   size_t n;
        for (n=nbSeq-2 ; n<nbSeq ; n--) {      /* intentional underflow */
            BYTE const llCode = llCodeTable[n];
            BYTE const ofCode = ofCodeTable[n];
            BYTE const mlCode = mlCodeTable[n];
            U32  const llBits = LL_bits[llCode];
            U32  const ofBits = ofCode;
            U32  const mlBits = ML_bits[mlCode];
            DEBUGLOG(6, "encoding: litlen:%2u - matchlen:%2u - offCode:%7u",
                        (unsigned)sequences[n].litLength,
                        (unsigned)sequences[n].mlBase + MINMATCH,
                        (unsigned)sequences[n].offBase);
  /* 64b*/
  /* (7)*/
            FSE_encodeSymbol(&blockStream, &stateOffsetBits, ofCode);       /* 15 */  /* 15 */
            FSE_encodeSymbol(&blockStream, &stateMatchLength, mlCode);      /* 24 */  /* 24 */
            if (MEM_32bits()) BIT_flushBits(&blockStream);                  /* (7)*/
            FSE_encodeSymbol(&blockStream, &stateLitLength, llCode);        /* 16 */  /* 33 */
            if (MEM_32bits() || (ofBits+mlBits+llBits >= 64-7-(LLFSELog+MLFSELog+OffFSELog)))
                BIT_flushBits(&blockStream);                                /* (7)*/
            BIT_addBits(&blockStream, sequences[n].litLength, llBits);
            if (MEM_32bits() && ((llBits+mlBits)>24)) BIT_flushBits(&blockStream);
            BIT_addBits(&blockStream, sequences[n].mlBase, mlBits);
            if (MEM_32bits() || (ofBits+mlBits+llBits > 56)) BIT_flushBits(&blockStream);
            if (MEM_32bits() && longOffsets) {
                unsigned const extraBits = ofBits - MIN(ofBits, STREAM_ACCUMULATOR_MIN-1);
                if (extraBits) {
                    BIT_addBits(&blockStream, sequences[n].offBase, extraBits);
                    BIT_flushBits(&blockStream);                            /* (7)*/
                }
                BIT_addBits(&blockStream, sequences[n].offBase >> extraBits,
                            ofBits - extraBits);                            /* 31 */
            } else {
                BIT_addBits(&blockStream, sequences[n].offBase, ofBits);     /* 31 */
            }
            BIT_flushBits(&blockStream);                                    /* (7)*/
            DEBUGLOG(7, "remaining space : %i", (int)(blockStream.endPtr - blockStream.ptr));
    }   }

    DEBUGLOG(6, "ZSTD_encodeSequences: flushing ML state with %u bits", stateMatchLength.stateLog);
    FSE_flushCState(&blockStream, &stateMatchLength);
    DEBUGLOG(6, "ZSTD_encodeSequences: flushing Off state with %u bits", stateOffsetBits.stateLog);
    FSE_flushCState(&blockStream, &stateOffsetBits);
    DEBUGLOG(6, "ZSTD_encodeSequences: flushing LL state with %u bits", stateLitLength.stateLog);
    FSE_flushCState(&blockStream, &stateLitLength);

    {   size_t const streamSize = BIT_closeCStream(&blockStream);
        RETURN_ERROR_IF(streamSize==0, dstSize_tooSmall, "not enough space");
        return streamSize;
    }
}

static size_t
ZSTD_encodeSequences_default(
            void* dst, size_t dstCapacity,
            FSE_CTable const* CTable_MatchLength, BYTE const* mlCodeTable,
            FSE_CTable const* CTable_OffsetBits, BYTE const* ofCodeTable,
            FSE_CTable const* CTable_LitLength, BYTE const* llCodeTable,
            SeqDef const* sequences, size_t nbSeq, int longOffsets)
{
    return ZSTD_encodeSequences_body(dst, dstCapacity,
                                    CTable_MatchLength, mlCodeTable,
                                    CTable_OffsetBits, ofCodeTable,
                                    CTable_LitLength, llCodeTable,
                                    sequences, nbSeq, longOffsets);
}


#if DYNAMIC_BMI2

static BMI2_TARGET_ATTRIBUTE size_t
ZSTD_encodeSequences_bmi2(
            void* dst, size_t dstCapacity,
            FSE_CTable const* CTable_MatchLength, BYTE const* mlCodeTable,
            FSE_CTable const* CTable_OffsetBits, BYTE const* ofCodeTable,
            FSE_CTable const* CTable_LitLength, BYTE const* llCodeTable,
            SeqDef const* sequences, size_t nbSeq, int longOffsets)
{
    return ZSTD_encodeSequences_body(dst, dstCapacity,
                                    CTable_MatchLength, mlCodeTable,
                                    CTable_OffsetBits, ofCodeTable,
                                    CTable_LitLength, llCodeTable,
                                    sequences, nbSeq, longOffsets);
}

#else

#define ZSTD_encodeSequences_bmi2 ZSTD_encodeSequences_default

#endif

size_t ZSTD_encodeSequences(
            void* dst, size_t dstCapacity,
            FSE_CTable const* CTable_MatchLength, BYTE const* mlCodeTable,
            FSE_CTable const* CTable_OffsetBits, BYTE const* ofCodeTable,
            FSE_CTable const* CTable_LitLength, BYTE const* llCodeTable,
            SeqDef const* sequences, size_t nbSeq, int longOffsets, int bmi2)
{
    DEBUGLOG(5, "ZSTD_encodeSequences: dstCapacity = %u", (unsigned)dstCapacity);
    if (ZSTD_USE_BMI2(bmi2)) {
        return ZSTD_encodeSequences_bmi2(dst, dstCapacity,
                                         CTable_MatchLength, mlCodeTable,
                                         CTable_OffsetBits, ofCodeTable,
                                         CTable_LitLength, llCodeTable,
                                         sequences, nbSeq, longOffsets);
    }
    (void)bmi2;
    return ZSTD_encodeSequences_default(dst, dstCapacity,
                                        CTable_MatchLength, mlCodeTable,
                                        CTable_OffsetBits, ofCodeTable,
                                        CTable_LitLength, llCodeTable,
                                        sequences, nbSeq, longOffsets);
}
/**** ended inlining compress/zstd_compress_sequences.c ****/
/**** start inlining compress/zstd_compress_superblock.c ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */


/**** start inlining zstd_compress_superblock.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_COMPRESS_ADVANCED_H
#define ZSTD_COMPRESS_ADVANCED_H



/**** skipping file: ../zstd.h ****/




size_t ZSTD_compressSuperBlock(ZSTD_CCtx* zc,
                               void* dst, size_t dstCapacity,
                               void const* src, size_t srcSize,
                               unsigned lastBlock);

#endif /* ZSTD_COMPRESS_ADVANCED_H */
/**** ended inlining zstd_compress_superblock.h ****/

/**** skipping file: ../common/zstd_internal.h ****/
/**** skipping file: hist.h ****/
/**** skipping file: zstd_compress_internal.h ****/
/**** skipping file: zstd_compress_sequences.h ****/
/**** skipping file: zstd_compress_literals.h ****/


static size_t
ZSTD_compressSubBlock_literal(const HUF_CElt* hufTable,
                              const ZSTD_hufCTablesMetadata_t* hufMetadata,
                              const BYTE* literals, size_t litSize,
                              void* dst, size_t dstSize,
                              const int bmi2, int writeEntropy, int* entropyWritten)
{
    size_t const header = writeEntropy ? 200 : 0;
    size_t const lhSize = 3 + (litSize >= (1 KB - header)) + (litSize >= (16 KB - header));
    BYTE* const ostart = (BYTE*)dst;
    BYTE* const oend = ostart + dstSize;
    BYTE* op = ostart;
    U32 const singleStream = lhSize == 3;
    SymbolEncodingType_e hType = writeEntropy ? hufMetadata->hType : set_repeat;
    size_t cLitSize = 0;

    DEBUGLOG(5, "ZSTD_compressSubBlock_literal (litSize=%zu, lhSize=%zu, writeEntropy=%d)", litSize, lhSize, writeEntropy);

    *entropyWritten = 0;
    if (litSize == 0 || hufMetadata->hType == set_basic) {
      DEBUGLOG(5, "ZSTD_compressSubBlock_literal using raw literal");
      return ZSTD_noCompressLiterals(dst, dstSize, literals, litSize);
    } else if (hufMetadata->hType == set_rle) {
      DEBUGLOG(5, "ZSTD_compressSubBlock_literal using rle literal");
      RETURN_ERROR_IF(dstSize < 4, dstSize_tooSmall, "");
      return ZSTD_compressRleLiteralsBlock(dst, dstSize, literals, litSize);
    }

    assert(litSize > 0);
    assert(hufMetadata->hType == set_compressed || hufMetadata->hType == set_repeat);

    RETURN_ERROR_IF(dstSize < lhSize, dstSize_tooSmall, "");
    op += lhSize;
    if (writeEntropy && hufMetadata->hType == set_compressed) {
        RETURN_ERROR_IF(hufMetadata->hufDesSize > (size_t)(oend-op),
                        dstSize_tooSmall, "");
        ZSTD_memcpy(op, hufMetadata->hufDesBuffer, hufMetadata->hufDesSize);
        op += hufMetadata->hufDesSize;
        cLitSize += hufMetadata->hufDesSize;
        DEBUGLOG(5, "ZSTD_compressSubBlock_literal (hSize=%zu)", hufMetadata->hufDesSize);
    }

    {   int const flags = bmi2 ? HUF_flags_bmi2 : 0;
        const size_t cSize = singleStream ? HUF_compress1X_usingCTable(op, (size_t)(oend-op), literals, litSize, hufTable, flags)
                                          : HUF_compress4X_usingCTable(op, (size_t)(oend-op), literals, litSize, hufTable, flags);
        if (cSize == 0 || ERR_isError(cSize)) {
            DEBUGLOG(5, "Failed to write entropy tables %s", ZSTD_getErrorName(cSize));
            return 0;
        }
        op += cSize;
        cLitSize += cSize;

        if (!writeEntropy && cLitSize >= litSize) {
            DEBUGLOG(5, "ZSTD_compressSubBlock_literal using raw literal because uncompressible");
            return ZSTD_noCompressLiterals(dst, dstSize, literals, litSize);
        }

        if (lhSize < (size_t)(3 + (cLitSize >= 1 KB) + (cLitSize >= 16 KB))) {
            assert(cLitSize > litSize);
            DEBUGLOG(5, "Literals expanded beyond allowed header size");
            return ZSTD_noCompressLiterals(dst, dstSize, literals, litSize);
        }
        DEBUGLOG(5, "ZSTD_compressSubBlock_literal (cSize=%zu)", cSize);
    }


    switch(lhSize)
    {
    case 3: /* 2 - 2 - 10 - 10 */
        {   U32 const lhc = hType + ((U32)(!singleStream) << 2) + ((U32)litSize<<4) + ((U32)cLitSize<<14);
            MEM_writeLE24(ostart, lhc);
            break;
        }
    case 4: /* 2 - 2 - 14 - 14 */
        {   U32 const lhc = hType + (2 << 2) + ((U32)litSize<<4) + ((U32)cLitSize<<18);
            MEM_writeLE32(ostart, lhc);
            break;
        }
    case 5: /* 2 - 2 - 18 - 18 */
        {   U32 const lhc = hType + (3 << 2) + ((U32)litSize<<4) + ((U32)cLitSize<<22);
            MEM_writeLE32(ostart, lhc);
            ostart[4] = (BYTE)(cLitSize >> 10);
            break;
        }
    default:  /* not possible : lhSize is {3,4,5} */
        assert(0);
    }
    *entropyWritten = 1;
    DEBUGLOG(5, "Compressed literals: %u -> %u", (U32)litSize, (U32)(op-ostart));
    return (size_t)(op-ostart);
}

static size_t
ZSTD_seqDecompressedSize(SeqStore_t const* seqStore,
                   const SeqDef* sequences, size_t nbSeqs,
                         size_t litSize, int lastSubBlock)
{
    size_t matchLengthSum = 0;
    size_t litLengthSum = 0;
    size_t n;
    for (n=0; n<nbSeqs; n++) {
        const ZSTD_SequenceLength seqLen = ZSTD_getSequenceLength(seqStore, sequences+n);
        litLengthSum += seqLen.litLength;
        matchLengthSum += seqLen.matchLength;
    }
    DEBUGLOG(5, "ZSTD_seqDecompressedSize: %u sequences from %p: %u literals + %u matchlength",
                (unsigned)nbSeqs, (const void*)sequences,
                (unsigned)litLengthSum, (unsigned)matchLengthSum);
    if (!lastSubBlock)
        assert(litLengthSum == litSize);
    else
        assert(litLengthSum <= litSize);
    (void)litLengthSum;
    return matchLengthSum + litSize;
}


static size_t
ZSTD_compressSubBlock_sequences(const ZSTD_fseCTables_t* fseTables,
                                const ZSTD_fseCTablesMetadata_t* fseMetadata,
                                const SeqDef* sequences, size_t nbSeq,
                                const BYTE* llCode, const BYTE* mlCode, const BYTE* ofCode,
                                const ZSTD_CCtx_params* cctxParams,
                                void* dst, size_t dstCapacity,
                                const int bmi2, int writeEntropy, int* entropyWritten)
{
    const int longOffsets = cctxParams->cParams.windowLog > STREAM_ACCUMULATOR_MIN;
    BYTE* const ostart = (BYTE*)dst;
    BYTE* const oend = ostart + dstCapacity;
    BYTE* op = ostart;
    BYTE* seqHead;

    DEBUGLOG(5, "ZSTD_compressSubBlock_sequences (nbSeq=%zu, writeEntropy=%d, longOffsets=%d)", nbSeq, writeEntropy, longOffsets);

    *entropyWritten = 0;

    RETURN_ERROR_IF((oend-op) < 3 /*max nbSeq Size*/ + 1 /*seqHead*/,
                    dstSize_tooSmall, "");
    if (nbSeq < 128)
        *op++ = (BYTE)nbSeq;
    else if (nbSeq < LONGNBSEQ)
        op[0] = (BYTE)((nbSeq>>8) + 0x80), op[1] = (BYTE)nbSeq, op+=2;
    else
        op[0]=0xFF, MEM_writeLE16(op+1, (U16)(nbSeq - LONGNBSEQ)), op+=3;
    if (nbSeq==0) {
        return (size_t)(op - ostart);
    }


    seqHead = op++;

    DEBUGLOG(5, "ZSTD_compressSubBlock_sequences (seqHeadSize=%u)", (unsigned)(op-ostart));

    if (writeEntropy) {
        const U32 LLtype = fseMetadata->llType;
        const U32 Offtype = fseMetadata->ofType;
        const U32 MLtype = fseMetadata->mlType;
        DEBUGLOG(5, "ZSTD_compressSubBlock_sequences (fseTablesSize=%zu)", fseMetadata->fseTablesSize);
        RETURN_ERROR_IF(fseMetadata->fseTablesSize > (size_t)(oend-op),
                        dstSize_tooSmall, "");
        *seqHead = (BYTE)((LLtype<<6) + (Offtype<<4) + (MLtype<<2));
        ZSTD_memcpy(op, fseMetadata->fseTablesBuffer, fseMetadata->fseTablesSize);
        op += fseMetadata->fseTablesSize;
    } else {
        const U32 repeat = set_repeat;
        *seqHead = (BYTE)((repeat<<6) + (repeat<<4) + (repeat<<2));
    }

    {   size_t const bitstreamSize = ZSTD_encodeSequences(
                                        op, (size_t)(oend - op),
                                        fseTables->matchlengthCTable, mlCode,
                                        fseTables->offcodeCTable, ofCode,
                                        fseTables->litlengthCTable, llCode,
                                        sequences, nbSeq,
                                        longOffsets, bmi2);
        FORWARD_IF_ERROR(bitstreamSize, "ZSTD_encodeSequences failed");
        op += bitstreamSize;

#ifndef FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION
        if (writeEntropy && fseMetadata->lastCountSize && fseMetadata->lastCountSize + bitstreamSize < 4) {

            assert(fseMetadata->lastCountSize + bitstreamSize == 3);
            DEBUGLOG(5, "Avoiding bug in zstd decoder in versions <= 1.3.4 by "
                        "emitting an uncompressed block.");
            return 0;
        }
#endif
        DEBUGLOG(5, "ZSTD_compressSubBlock_sequences (bitstreamSize=%zu)", bitstreamSize);
    }


#ifndef FUZZING_BUILD_MODE_UNSAFE_FOR_PRODUCTION
    if (op-seqHead < 4) {
        DEBUGLOG(5, "Avoiding bug in zstd decoder in versions <= 1.4.0 by emitting "
                    "an uncompressed block when sequences are < 4 bytes");
        return 0;
    }
#endif

    *entropyWritten = 1;
    return (size_t)(op - ostart);
}


static size_t ZSTD_compressSubBlock(const ZSTD_entropyCTables_t* entropy,
                                    const ZSTD_entropyCTablesMetadata_t* entropyMetadata,
                                    const SeqDef* sequences, size_t nbSeq,
                                    const BYTE* literals, size_t litSize,
                                    const BYTE* llCode, const BYTE* mlCode, const BYTE* ofCode,
                                    const ZSTD_CCtx_params* cctxParams,
                                    void* dst, size_t dstCapacity,
                                    const int bmi2,
                                    int writeLitEntropy, int writeSeqEntropy,
                                    int* litEntropyWritten, int* seqEntropyWritten,
                                    U32 lastBlock)
{
    BYTE* const ostart = (BYTE*)dst;
    BYTE* const oend = ostart + dstCapacity;
    BYTE* op = ostart;
    DEBUGLOG(5, "ZSTD_compressSubBlock (litSize=%zu, nbSeq=%zu, writeLitEntropy=%d, writeSeqEntropy=%d, lastBlock=%d)",
                litSize, nbSeq, writeLitEntropy, writeSeqEntropy, lastBlock);
    RETURN_ERROR_IF(dstCapacity < ZSTD_blockHeaderSize, dstSize_tooSmall, "");
    op += ZSTD_blockHeaderSize;
    {   size_t cLitSize = ZSTD_compressSubBlock_literal((const HUF_CElt*)entropy->huf.CTable,
                                                        &entropyMetadata->hufMetadata, literals, litSize,
                                                        op, (size_t)(oend-op),
                                                        bmi2, writeLitEntropy, litEntropyWritten);
        FORWARD_IF_ERROR(cLitSize, "ZSTD_compressSubBlock_literal failed");
        if (cLitSize == 0) return 0;
        op += cLitSize;
    }
    {   size_t cSeqSize = ZSTD_compressSubBlock_sequences(&entropy->fse,
                                                  &entropyMetadata->fseMetadata,
                                                  sequences, nbSeq,
                                                  llCode, mlCode, ofCode,
                                                  cctxParams,
                                                  op, (size_t)(oend-op),
                                                  bmi2, writeSeqEntropy, seqEntropyWritten);
        FORWARD_IF_ERROR(cSeqSize, "ZSTD_compressSubBlock_sequences failed");
        if (cSeqSize == 0) return 0;
        op += cSeqSize;
    }

    {   size_t cSize = (size_t)(op-ostart) - ZSTD_blockHeaderSize;
        U32 const cBlockHeader24 = lastBlock + (((U32)bt_compressed)<<1) + (U32)(cSize << 3);
        MEM_writeLE24(ostart, cBlockHeader24);
    }
    return (size_t)(op-ostart);
}

static size_t ZSTD_estimateSubBlockSize_literal(const BYTE* literals, size_t litSize,
                                                const ZSTD_hufCTables_t* huf,
                                                const ZSTD_hufCTablesMetadata_t* hufMetadata,
                                                void* workspace, size_t wkspSize,
                                                int writeEntropy)
{
    unsigned* const countWksp = (unsigned*)workspace;
    unsigned maxSymbolValue = 255;
    size_t literalSectionHeaderSize = 3; /* Use hard coded size of 3 bytes */

    if (hufMetadata->hType == set_basic) return litSize;
    else if (hufMetadata->hType == set_rle) return 1;
    else if (hufMetadata->hType == set_compressed || hufMetadata->hType == set_repeat) {
        size_t const largest = HIST_count_wksp (countWksp, &maxSymbolValue, (const BYTE*)literals, litSize, workspace, wkspSize);
        if (ZSTD_isError(largest)) return litSize;
        {   size_t cLitSizeEstimate = HUF_estimateCompressedSize((const HUF_CElt*)huf->CTable, countWksp, maxSymbolValue);
            if (writeEntropy) cLitSizeEstimate += hufMetadata->hufDesSize;
            return cLitSizeEstimate + literalSectionHeaderSize;
    }   }
    assert(0); /* impossible */
    return 0;
}

static size_t ZSTD_estimateSubBlockSize_symbolType(SymbolEncodingType_e type,
                        const BYTE* codeTable, unsigned maxCode,
                        size_t nbSeq, const FSE_CTable* fseCTable,
                        const U8* additionalBits,
                        short const* defaultNorm, U32 defaultNormLog, U32 defaultMax,
                        void* workspace, size_t wkspSize)
{
    unsigned* const countWksp = (unsigned*)workspace;
    const BYTE* ctp = codeTable;
    const BYTE* const ctStart = ctp;
    const BYTE* const ctEnd = ctStart + nbSeq;
    size_t cSymbolTypeSizeEstimateInBits = 0;
    unsigned max = maxCode;

    HIST_countFast_wksp(countWksp, &max, codeTable, nbSeq, workspace, wkspSize);  /* can't fail */
    if (type == set_basic) {

        assert(max <= defaultMax);
        cSymbolTypeSizeEstimateInBits = max <= defaultMax
                ? ZSTD_crossEntropyCost(defaultNorm, defaultNormLog, countWksp, max)
                : ERROR(GENERIC);
    } else if (type == set_rle) {
        cSymbolTypeSizeEstimateInBits = 0;
    } else if (type == set_compressed || type == set_repeat) {
        cSymbolTypeSizeEstimateInBits = ZSTD_fseBitCost(fseCTable, countWksp, max);
    }
    if (ZSTD_isError(cSymbolTypeSizeEstimateInBits)) return nbSeq * 10;
    while (ctp < ctEnd) {
        if (additionalBits) cSymbolTypeSizeEstimateInBits += additionalBits[*ctp];
        else cSymbolTypeSizeEstimateInBits += *ctp; /* for offset, offset code is also the number of additional bits */
        ctp++;
    }
    return cSymbolTypeSizeEstimateInBits / 8;
}

static size_t ZSTD_estimateSubBlockSize_sequences(const BYTE* ofCodeTable,
                                                  const BYTE* llCodeTable,
                                                  const BYTE* mlCodeTable,
                                                  size_t nbSeq,
                                                  const ZSTD_fseCTables_t* fseTables,
                                                  const ZSTD_fseCTablesMetadata_t* fseMetadata,
                                                  void* workspace, size_t wkspSize,
                                                  int writeEntropy)
{
    size_t const sequencesSectionHeaderSize = 3; /* Use hard coded size of 3 bytes */
    size_t cSeqSizeEstimate = 0;
    if (nbSeq == 0) return sequencesSectionHeaderSize;
    cSeqSizeEstimate += ZSTD_estimateSubBlockSize_symbolType(fseMetadata->ofType, ofCodeTable, MaxOff,
                                         nbSeq, fseTables->offcodeCTable, NULL,
                                         OF_defaultNorm, OF_defaultNormLog, DefaultMaxOff,
                                         workspace, wkspSize);
    cSeqSizeEstimate += ZSTD_estimateSubBlockSize_symbolType(fseMetadata->llType, llCodeTable, MaxLL,
                                         nbSeq, fseTables->litlengthCTable, LL_bits,
                                         LL_defaultNorm, LL_defaultNormLog, MaxLL,
                                         workspace, wkspSize);
    cSeqSizeEstimate += ZSTD_estimateSubBlockSize_symbolType(fseMetadata->mlType, mlCodeTable, MaxML,
                                         nbSeq, fseTables->matchlengthCTable, ML_bits,
                                         ML_defaultNorm, ML_defaultNormLog, MaxML,
                                         workspace, wkspSize);
    if (writeEntropy) cSeqSizeEstimate += fseMetadata->fseTablesSize;
    return cSeqSizeEstimate + sequencesSectionHeaderSize;
}

typedef struct {
    size_t estLitSize;
    size_t estBlockSize;
} EstimatedBlockSize;
static EstimatedBlockSize ZSTD_estimateSubBlockSize(const BYTE* literals, size_t litSize,
                                        const BYTE* ofCodeTable,
                                        const BYTE* llCodeTable,
                                        const BYTE* mlCodeTable,
                                        size_t nbSeq,
                                        const ZSTD_entropyCTables_t* entropy,
                                        const ZSTD_entropyCTablesMetadata_t* entropyMetadata,
                                        void* workspace, size_t wkspSize,
                                        int writeLitEntropy, int writeSeqEntropy)
{
    EstimatedBlockSize ebs;
    ebs.estLitSize = ZSTD_estimateSubBlockSize_literal(literals, litSize,
                                                        &entropy->huf, &entropyMetadata->hufMetadata,
                                                        workspace, wkspSize, writeLitEntropy);
    ebs.estBlockSize = ZSTD_estimateSubBlockSize_sequences(ofCodeTable, llCodeTable, mlCodeTable,
                                                         nbSeq, &entropy->fse, &entropyMetadata->fseMetadata,
                                                         workspace, wkspSize, writeSeqEntropy);
    ebs.estBlockSize += ebs.estLitSize + ZSTD_blockHeaderSize;
    return ebs;
}

static int ZSTD_needSequenceEntropyTables(ZSTD_fseCTablesMetadata_t const* fseMetadata)
{
    if (fseMetadata->llType == set_compressed || fseMetadata->llType == set_rle)
        return 1;
    if (fseMetadata->mlType == set_compressed || fseMetadata->mlType == set_rle)
        return 1;
    if (fseMetadata->ofType == set_compressed || fseMetadata->ofType == set_rle)
        return 1;
    return 0;
}

static size_t countLiterals(SeqStore_t const* seqStore, const SeqDef* sp, size_t seqCount)
{
    size_t n, total = 0;
    assert(sp != NULL);
    for (n=0; n<seqCount; n++) {
        total += ZSTD_getSequenceLength(seqStore, sp+n).litLength;
    }
    DEBUGLOG(6, "countLiterals for %zu sequences from %p => %zu bytes", seqCount, (const void*)sp, total);
    return total;
}

#define BYTESCALE 256

static size_t sizeBlockSequences(const SeqDef* sp, size_t nbSeqs,
                size_t targetBudget, size_t avgLitCost, size_t avgSeqCost,
                int firstSubBlock)
{
    size_t n, budget = 0, inSize=0;

    size_t const headerSize = (size_t)firstSubBlock * 120 * BYTESCALE; /* generous estimate */
    assert(firstSubBlock==0 || firstSubBlock==1);
    budget += headerSize;


    budget += sp[0].litLength * avgLitCost + avgSeqCost;
    if (budget > targetBudget) return 1;
    inSize = sp[0].litLength + (sp[0].mlBase+MINMATCH);


    for (n=1; n<nbSeqs; n++) {
        size_t currentCost = sp[n].litLength * avgLitCost + avgSeqCost;
        budget += currentCost;
        inSize += sp[n].litLength + (sp[n].mlBase+MINMATCH);

        if ( (budget > targetBudget)

          && (budget < inSize * BYTESCALE) )
            break;
    }

    return n;
}


static size_t ZSTD_compressSubBlock_multi(const SeqStore_t* seqStorePtr,
                            const ZSTD_compressedBlockState_t* prevCBlock,
                            ZSTD_compressedBlockState_t* nextCBlock,
                            const ZSTD_entropyCTablesMetadata_t* entropyMetadata,
                            const ZSTD_CCtx_params* cctxParams,
                                  void* dst, size_t dstCapacity,
                            const void* src, size_t srcSize,
                            const int bmi2, U32 lastBlock,
                            void* workspace, size_t wkspSize)
{
    const SeqDef* const sstart = seqStorePtr->sequencesStart;
    const SeqDef* const send = seqStorePtr->sequences;
    const SeqDef* sp = sstart; /* tracks progresses within seqStorePtr->sequences */
    size_t const nbSeqs = (size_t)(send - sstart);
    const BYTE* const lstart = seqStorePtr->litStart;
    const BYTE* const lend = seqStorePtr->lit;
    const BYTE* lp = lstart;
    size_t const nbLiterals = (size_t)(lend - lstart);
    BYTE const* ip = (BYTE const*)src;
    BYTE const* const iend = ip + srcSize;
    BYTE* const ostart = (BYTE*)dst;
    BYTE* const oend = ostart + dstCapacity;
    BYTE* op = ostart;
    const BYTE* llCodePtr = seqStorePtr->llCode;
    const BYTE* mlCodePtr = seqStorePtr->mlCode;
    const BYTE* ofCodePtr = seqStorePtr->ofCode;
    size_t const minTarget = ZSTD_TARGETCBLOCKSIZE_MIN; /* enforce minimum size, to reduce undesirable side effects */
    size_t const targetCBlockSize = MAX(minTarget, cctxParams->targetCBlockSize);
    int writeLitEntropy = (entropyMetadata->hufMetadata.hType == set_compressed);
    int writeSeqEntropy = 1;

    DEBUGLOG(5, "ZSTD_compressSubBlock_multi (srcSize=%u, litSize=%u, nbSeq=%u)",
               (unsigned)srcSize, (unsigned)(lend-lstart), (unsigned)(send-sstart));


    if (nbSeqs > 0) {
        EstimatedBlockSize const ebs =
                ZSTD_estimateSubBlockSize(lp, nbLiterals,
                                        ofCodePtr, llCodePtr, mlCodePtr, nbSeqs,
                                        &nextCBlock->entropy, entropyMetadata,
                                        workspace, wkspSize,
                                        writeLitEntropy, writeSeqEntropy);

        size_t const avgLitCost = nbLiterals ? (ebs.estLitSize * BYTESCALE) / nbLiterals : BYTESCALE;
        size_t const avgSeqCost = ((ebs.estBlockSize - ebs.estLitSize) * BYTESCALE) / nbSeqs;
        const size_t nbSubBlocks = MAX((ebs.estBlockSize + (targetCBlockSize/2)) / targetCBlockSize, 1);
        size_t n, avgBlockBudget, blockBudgetSupp=0;
        avgBlockBudget = (ebs.estBlockSize * BYTESCALE) / nbSubBlocks;
        DEBUGLOG(5, "estimated fullblock size=%u bytes ; avgLitCost=%.2f ; avgSeqCost=%.2f ; targetCBlockSize=%u, nbSubBlocks=%u ; avgBlockBudget=%.0f bytes",
                    (unsigned)ebs.estBlockSize, (double)avgLitCost/BYTESCALE, (double)avgSeqCost/BYTESCALE,
                    (unsigned)targetCBlockSize, (unsigned)nbSubBlocks, (double)avgBlockBudget/BYTESCALE);

        if (ebs.estBlockSize > srcSize) return 0;


        assert(nbSubBlocks>0);
        for (n=0; n < nbSubBlocks-1; n++) {

            size_t const seqCount = sizeBlockSequences(sp, (size_t)(send-sp),
                                        avgBlockBudget + blockBudgetSupp, avgLitCost, avgSeqCost, n==0);

            assert(seqCount <= (size_t)(send-sp));
            if (sp + seqCount == send) break;
            assert(seqCount > 0);

            {   int litEntropyWritten = 0;
                int seqEntropyWritten = 0;
                size_t litSize = countLiterals(seqStorePtr, sp, seqCount);
                const size_t decompressedSize =
                        ZSTD_seqDecompressedSize(seqStorePtr, sp, seqCount, litSize, 0);
                size_t const cSize = ZSTD_compressSubBlock(&nextCBlock->entropy, entropyMetadata,
                                                sp, seqCount,
                                                lp, litSize,
                                                llCodePtr, mlCodePtr, ofCodePtr,
                                                cctxParams,
                                                op, (size_t)(oend-op),
                                                bmi2, writeLitEntropy, writeSeqEntropy,
                                                &litEntropyWritten, &seqEntropyWritten,
                                                0);
                FORWARD_IF_ERROR(cSize, "ZSTD_compressSubBlock failed");


                if (cSize > 0 && cSize < decompressedSize) {
                    DEBUGLOG(5, "Committed sub-block compressing %u bytes => %u bytes",
                                (unsigned)decompressedSize, (unsigned)cSize);
                    assert(ip + decompressedSize <= iend);
                    ip += decompressedSize;
                    lp += litSize;
                    op += cSize;
                    llCodePtr += seqCount;
                    mlCodePtr += seqCount;
                    ofCodePtr += seqCount;

                    if (litEntropyWritten) {
                        writeLitEntropy = 0;
                    }
                    if (seqEntropyWritten) {
                        writeSeqEntropy = 0;
                    }
                    sp += seqCount;
                    blockBudgetSupp = 0;
            }   }

        }
    } /* if (nbSeqs > 0) */


    DEBUGLOG(5, "Generate last sub-block: %u sequences remaining", (unsigned)(send - sp));
    {   int litEntropyWritten = 0;
        int seqEntropyWritten = 0;
        size_t litSize = (size_t)(lend - lp);
        size_t seqCount = (size_t)(send - sp);
        const size_t decompressedSize =
                ZSTD_seqDecompressedSize(seqStorePtr, sp, seqCount, litSize, 1);
        size_t const cSize = ZSTD_compressSubBlock(&nextCBlock->entropy, entropyMetadata,
                                            sp, seqCount,
                                            lp, litSize,
                                            llCodePtr, mlCodePtr, ofCodePtr,
                                            cctxParams,
                                            op, (size_t)(oend-op),
                                            bmi2, writeLitEntropy, writeSeqEntropy,
                                            &litEntropyWritten, &seqEntropyWritten,
                                            lastBlock);
        FORWARD_IF_ERROR(cSize, "ZSTD_compressSubBlock failed");


        if (cSize > 0 && cSize < decompressedSize) {
            DEBUGLOG(5, "Last sub-block compressed %u bytes => %u bytes",
                        (unsigned)decompressedSize, (unsigned)cSize);
            assert(ip + decompressedSize <= iend);
            ip += decompressedSize;
            lp += litSize;
            op += cSize;
            llCodePtr += seqCount;
            mlCodePtr += seqCount;
            ofCodePtr += seqCount;

            if (litEntropyWritten) {
                writeLitEntropy = 0;
            }
            if (seqEntropyWritten) {
                writeSeqEntropy = 0;
            }
            sp += seqCount;
        }
    }


    if (writeLitEntropy) {
        DEBUGLOG(5, "Literal entropy tables were never written");
        ZSTD_memcpy(&nextCBlock->entropy.huf, &prevCBlock->entropy.huf, sizeof(prevCBlock->entropy.huf));
    }
    if (writeSeqEntropy && ZSTD_needSequenceEntropyTables(&entropyMetadata->fseMetadata)) {

        DEBUGLOG(5, "Sequence entropy tables were never written => cancel, emit an uncompressed block");
        return 0;
    }

    if (ip < iend) {

        size_t const rSize = (size_t)((iend - ip));
        size_t const cSize = ZSTD_noCompressBlock(op, (size_t)(oend - op), ip, rSize, lastBlock);
        DEBUGLOG(5, "Generate last uncompressed sub-block of %u bytes", (unsigned)(rSize));
        FORWARD_IF_ERROR(cSize, "ZSTD_noCompressBlock failed");
        assert(cSize != 0);
        op += cSize;

        if (sp < send) {
            const SeqDef* seq;
            Repcodes_t rep;
            ZSTD_memcpy(&rep, prevCBlock->rep, sizeof(rep));
            for (seq = sstart; seq < sp; ++seq) {
                ZSTD_updateRep(rep.rep, seq->offBase, ZSTD_getSequenceLength(seqStorePtr, seq).litLength == 0);
            }
            ZSTD_memcpy(nextCBlock->rep, &rep, sizeof(rep));
        }
    }

    DEBUGLOG(5, "ZSTD_compressSubBlock_multi compressed all subBlocks: total compressed size = %u",
                (unsigned)(op-ostart));
    return (size_t)(op-ostart);
}

size_t ZSTD_compressSuperBlock(ZSTD_CCtx* zc,
                               void* dst, size_t dstCapacity,
                               const void* src, size_t srcSize,
                               unsigned lastBlock)
{
    ZSTD_entropyCTablesMetadata_t entropyMetadata;

    FORWARD_IF_ERROR(ZSTD_buildBlockEntropyStats(&zc->seqStore,
          &zc->blockState.prevCBlock->entropy,
          &zc->blockState.nextCBlock->entropy,
          &zc->appliedParams,
          &entropyMetadata,
          zc->tmpWorkspace, zc->tmpWkspSize /* statically allocated in resetCCtx */), "");

    return ZSTD_compressSubBlock_multi(&zc->seqStore,
            zc->blockState.prevCBlock,
            zc->blockState.nextCBlock,
            &entropyMetadata,
            &zc->appliedParams,
            dst, dstCapacity,
            src, srcSize,
            ZSTD_CCtx_get_bmi2(zc), lastBlock,
            zc->tmpWorkspace, zc->tmpWkspSize /* statically allocated in resetCCtx */);
}
/**** ended inlining compress/zstd_compress_superblock.c ****/
/**** start inlining compress/zstd_preSplit.c ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

/**** skipping file: ../common/compiler.h ****/
/**** skipping file: ../common/mem.h ****/
/**** skipping file: ../common/zstd_deps.h ****/
/**** skipping file: ../common/zstd_internal.h ****/
/**** skipping file: hist.h ****/
/**** skipping file: zstd_preSplit.h ****/


#define BLOCKSIZE_MIN 3500
#define THRESHOLD_PENALTY_RATE 16
#define THRESHOLD_BASE (THRESHOLD_PENALTY_RATE - 2)
#define THRESHOLD_PENALTY 3

#define HASHLENGTH 2
#define HASHLOG_MAX 10
#define HASHTABLESIZE (1 << HASHLOG_MAX)
#define HASHMASK (HASHTABLESIZE - 1)
#define KNUTH 0x9e3779b9


FORCE_INLINE_TEMPLATE unsigned hash2(const void *p, unsigned hashLog)
{
    assert(hashLog >= 8);
    if (hashLog == 8) return (U32)((const BYTE*)p)[0];
    assert(hashLog <= HASHLOG_MAX);
    return (U32)(MEM_read16(p)) * KNUTH >> (32 - hashLog);
}


typedef struct {
  unsigned events[HASHTABLESIZE];
  size_t nbEvents;
} Fingerprint;
typedef struct {
    Fingerprint pastEvents;
    Fingerprint newEvents;
} FPStats;

static void initStats(FPStats* fpstats)
{
    ZSTD_memset(fpstats, 0, sizeof(FPStats));
}

FORCE_INLINE_TEMPLATE void
addEvents_generic(Fingerprint* fp, const void* src, size_t srcSize, size_t samplingRate, unsigned hashLog)
{
    const char* p = (const char*)src;
    size_t limit = srcSize - HASHLENGTH + 1;
    size_t n;
    assert(srcSize >= HASHLENGTH);
    for (n = 0; n < limit; n+=samplingRate) {
        fp->events[hash2(p+n, hashLog)]++;
    }
    fp->nbEvents += limit/samplingRate;
}

FORCE_INLINE_TEMPLATE void
recordFingerprint_generic(Fingerprint* fp, const void* src, size_t srcSize, size_t samplingRate, unsigned hashLog)
{
    ZSTD_memset(fp, 0, sizeof(unsigned) * ((size_t)1 << hashLog));
    fp->nbEvents = 0;
    addEvents_generic(fp, src, srcSize, samplingRate, hashLog);
}

typedef void (*RecordEvents_f)(Fingerprint* fp, const void* src, size_t srcSize);

#define FP_RECORD(_rate) ZSTD_recordFingerprint_##_rate

#define ZSTD_GEN_RECORD_FINGERPRINT(_rate, _hSize)                                 \
    static void FP_RECORD(_rate)(Fingerprint* fp, const void* src, size_t srcSize) \
    {                                                                              \
        recordFingerprint_generic(fp, src, srcSize, _rate, _hSize);                \
    }

ZSTD_GEN_RECORD_FINGERPRINT(1, 10)
ZSTD_GEN_RECORD_FINGERPRINT(5, 10)
ZSTD_GEN_RECORD_FINGERPRINT(11, 9)
ZSTD_GEN_RECORD_FINGERPRINT(43, 8)


static U64 ZSTD_abs64(S64 s64) { return (U64)((s64 < 0) ? -s64 : s64); }

static U64 fpDistance(const Fingerprint* fp1, const Fingerprint* fp2, unsigned hashLog)
{
    U64 distance = 0;
    size_t n;
    assert(hashLog <= HASHLOG_MAX);
    for (n = 0; n < ((size_t)1 << hashLog); n++) {
        distance +=
            ZSTD_abs64((S64)fp1->events[n] * (S64)fp2->nbEvents - (S64)fp2->events[n] * (S64)fp1->nbEvents);
    }
    return distance;
}


static int compareFingerprints(const Fingerprint* ref,
                            const Fingerprint* newfp,
                            int penalty,
                            unsigned hashLog)
{
    assert(ref->nbEvents > 0);
    assert(newfp->nbEvents > 0);
    {   U64 p50 = (U64)ref->nbEvents * (U64)newfp->nbEvents;
        U64 deviation = fpDistance(ref, newfp, hashLog);
        U64 threshold = p50 * (U64)(THRESHOLD_BASE + penalty) / THRESHOLD_PENALTY_RATE;
        return deviation >= threshold;
    }
}

static void mergeEvents(Fingerprint* acc, const Fingerprint* newfp)
{
    size_t n;
    for (n = 0; n < HASHTABLESIZE; n++) {
        acc->events[n] += newfp->events[n];
    }
    acc->nbEvents += newfp->nbEvents;
}

static void flushEvents(FPStats* fpstats)
{
    size_t n;
    for (n = 0; n < HASHTABLESIZE; n++) {
        fpstats->pastEvents.events[n] = fpstats->newEvents.events[n];
    }
    fpstats->pastEvents.nbEvents = fpstats->newEvents.nbEvents;
    ZSTD_memset(&fpstats->newEvents, 0, sizeof(fpstats->newEvents));
}

static void removeEvents(Fingerprint* acc, const Fingerprint* slice)
{
    size_t n;
    for (n = 0; n < HASHTABLESIZE; n++) {
        assert(acc->events[n] >= slice->events[n]);
        acc->events[n] -= slice->events[n];
    }
    acc->nbEvents -= slice->nbEvents;
}

#define CHUNKSIZE (8 << 10)
static size_t ZSTD_splitBlock_byChunks(const void* blockStart, size_t blockSize,
                        int level,
                        void* workspace, size_t wkspSize)
{
    static const RecordEvents_f records_fs[] = {
        FP_RECORD(43), FP_RECORD(11), FP_RECORD(5), FP_RECORD(1)
    };
    static const unsigned hashParams[] = { 8, 9, 10, 10 };
    const RecordEvents_f record_f = (assert(0<=level && level<=3), records_fs[level]);
    FPStats* const fpstats = (FPStats*)workspace;
    const char* p = (const char*)blockStart;
    int penalty = THRESHOLD_PENALTY;
    size_t pos = 0;
    assert(blockSize == (128 << 10));
    assert(workspace != NULL);
    assert((size_t)workspace % ZSTD_ALIGNOF(FPStats) == 0);
    ZSTD_STATIC_ASSERT(ZSTD_SLIPBLOCK_WORKSPACESIZE >= sizeof(FPStats));
    assert(wkspSize >= sizeof(FPStats)); (void)wkspSize;

    initStats(fpstats);
    record_f(&fpstats->pastEvents, p, CHUNKSIZE);
    for (pos = CHUNKSIZE; pos <= blockSize - CHUNKSIZE; pos += CHUNKSIZE) {
        record_f(&fpstats->newEvents, p + pos, CHUNKSIZE);
        if (compareFingerprints(&fpstats->pastEvents, &fpstats->newEvents, penalty, hashParams[level])) {
            return pos;
        } else {
            mergeEvents(&fpstats->pastEvents, &fpstats->newEvents);
            if (penalty > 0) penalty--;
        }
    }
    assert(pos == blockSize);
    return blockSize;
    (void)flushEvents; (void)removeEvents;
}


static size_t ZSTD_splitBlock_fromBorders(const void* blockStart, size_t blockSize,
                        void* workspace, size_t wkspSize)
{
#define SEGMENT_SIZE 512
    FPStats* const fpstats = (FPStats*)workspace;
    Fingerprint* middleEvents = (Fingerprint*)(void*)((char*)workspace + 512 * sizeof(unsigned));
    assert(blockSize == (128 << 10));
    assert(workspace != NULL);
    assert((size_t)workspace % ZSTD_ALIGNOF(FPStats) == 0);
    ZSTD_STATIC_ASSERT(ZSTD_SLIPBLOCK_WORKSPACESIZE >= sizeof(FPStats));
    assert(wkspSize >= sizeof(FPStats)); (void)wkspSize;

    initStats(fpstats);
    HIST_add(fpstats->pastEvents.events, blockStart, SEGMENT_SIZE);
    HIST_add(fpstats->newEvents.events, (const char*)blockStart + blockSize - SEGMENT_SIZE, SEGMENT_SIZE);
    fpstats->pastEvents.nbEvents = fpstats->newEvents.nbEvents = SEGMENT_SIZE;
    if (!compareFingerprints(&fpstats->pastEvents, &fpstats->newEvents, 0, 8))
        return blockSize;

    HIST_add(middleEvents->events, (const char*)blockStart + blockSize/2 - SEGMENT_SIZE/2, SEGMENT_SIZE);
    middleEvents->nbEvents = SEGMENT_SIZE;
    {   U64 const distFromBegin = fpDistance(&fpstats->pastEvents, middleEvents, 8);
        U64 const distFromEnd = fpDistance(&fpstats->newEvents, middleEvents, 8);
        U64 const minDistance = SEGMENT_SIZE * SEGMENT_SIZE / 3;
        if (ZSTD_abs64((S64)distFromBegin - (S64)distFromEnd) < minDistance)
            return 64 KB;
        return (distFromBegin > distFromEnd) ? 32 KB : 96 KB;
    }
}

size_t ZSTD_splitBlock(const void* blockStart, size_t blockSize,
                    int level,
                    void* workspace, size_t wkspSize)
{
    DEBUGLOG(6, "ZSTD_splitBlock (level=%i)", level);
    assert(0<=level && level<=4);
    if (level == 0)
        return ZSTD_splitBlock_fromBorders(blockStart, blockSize, workspace, wkspSize);

    return ZSTD_splitBlock_byChunks(blockStart, blockSize, level-1, workspace, wkspSize);
}
/**** ended inlining compress/zstd_preSplit.c ****/
/**** start inlining compress/zstd_compress.c ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */


/**** skipping file: ../common/allocations.h ****/
/**** skipping file: ../common/zstd_deps.h ****/
/**** skipping file: ../common/bmi2.h ****/
/**** skipping file: ../common/mem.h ****/
/**** skipping file: ../common/error_private.h ****/
/**** skipping file: hist.h ****/
#define FSE_STATIC_LINKING_ONLY   /* FSE_encodeSymbol */
/**** skipping file: ../common/fse.h ****/
/**** skipping file: ../common/huf.h ****/
/**** skipping file: zstd_compress_internal.h ****/
/**** skipping file: zstd_compress_sequences.h ****/
/**** skipping file: zstd_compress_literals.h ****/
/**** start inlining zstd_fast.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_FAST_H
#define ZSTD_FAST_H

/**** skipping file: ../common/mem.h ****/
/**** skipping file: zstd_compress_internal.h ****/

void ZSTD_fillHashTable(ZSTD_MatchState_t* ms,
                        void const* end, ZSTD_dictTableLoadMethod_e dtlm,
                        ZSTD_tableFillPurpose_e tfp);
size_t ZSTD_compressBlock_fast(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_fast_dictMatchState(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_fast_extDict(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);

#endif /* ZSTD_FAST_H */
/**** ended inlining zstd_fast.h ****/
/**** start inlining zstd_double_fast.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_DOUBLE_FAST_H
#define ZSTD_DOUBLE_FAST_H

/**** skipping file: ../common/mem.h ****/
/**** skipping file: zstd_compress_internal.h ****/

#ifndef ZSTD_EXCLUDE_DFAST_BLOCK_COMPRESSOR

void ZSTD_fillDoubleHashTable(ZSTD_MatchState_t* ms,
                              void const* end, ZSTD_dictTableLoadMethod_e dtlm,
                              ZSTD_tableFillPurpose_e tfp);

size_t ZSTD_compressBlock_doubleFast(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_doubleFast_dictMatchState(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_doubleFast_extDict(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);

#define ZSTD_COMPRESSBLOCK_DOUBLEFAST ZSTD_compressBlock_doubleFast
#define ZSTD_COMPRESSBLOCK_DOUBLEFAST_DICTMATCHSTATE ZSTD_compressBlock_doubleFast_dictMatchState
#define ZSTD_COMPRESSBLOCK_DOUBLEFAST_EXTDICT ZSTD_compressBlock_doubleFast_extDict
#else
#define ZSTD_COMPRESSBLOCK_DOUBLEFAST NULL
#define ZSTD_COMPRESSBLOCK_DOUBLEFAST_DICTMATCHSTATE NULL
#define ZSTD_COMPRESSBLOCK_DOUBLEFAST_EXTDICT NULL
#endif /* ZSTD_EXCLUDE_DFAST_BLOCK_COMPRESSOR */

#endif /* ZSTD_DOUBLE_FAST_H */
/**** ended inlining zstd_double_fast.h ****/
/**** start inlining zstd_lazy.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_LAZY_H
#define ZSTD_LAZY_H

/**** skipping file: zstd_compress_internal.h ****/


#define ZSTD_LAZY_DDSS_BUCKET_LOG 2

#define ZSTD_ROW_HASH_TAG_BITS 8        /* nb bits to use for the tag */

#if !defined(ZSTD_EXCLUDE_GREEDY_BLOCK_COMPRESSOR) \
 || !defined(ZSTD_EXCLUDE_LAZY_BLOCK_COMPRESSOR) \
 || !defined(ZSTD_EXCLUDE_LAZY2_BLOCK_COMPRESSOR) \
 || !defined(ZSTD_EXCLUDE_BTLAZY2_BLOCK_COMPRESSOR)
U32 ZSTD_insertAndFindFirstIndex(ZSTD_MatchState_t* ms, const BYTE* ip);
void ZSTD_row_update(ZSTD_MatchState_t* const ms, const BYTE* ip);

void ZSTD_dedicatedDictSearch_lazy_loadDictionary(ZSTD_MatchState_t* ms, const BYTE* const ip);

void ZSTD_preserveUnsortedMark (U32* const table, U32 const size, U32 const reducerValue);  /*! used in ZSTD_reduceIndex(). preemptively increase value of ZSTD_DUBT_UNSORTED_MARK */
#endif

#ifndef ZSTD_EXCLUDE_GREEDY_BLOCK_COMPRESSOR
size_t ZSTD_compressBlock_greedy(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_greedy_row(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_greedy_dictMatchState(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_greedy_dictMatchState_row(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_greedy_dedicatedDictSearch(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_greedy_dedicatedDictSearch_row(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_greedy_extDict(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_greedy_extDict_row(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);

#define ZSTD_COMPRESSBLOCK_GREEDY ZSTD_compressBlock_greedy
#define ZSTD_COMPRESSBLOCK_GREEDY_ROW ZSTD_compressBlock_greedy_row
#define ZSTD_COMPRESSBLOCK_GREEDY_DICTMATCHSTATE ZSTD_compressBlock_greedy_dictMatchState
#define ZSTD_COMPRESSBLOCK_GREEDY_DICTMATCHSTATE_ROW ZSTD_compressBlock_greedy_dictMatchState_row
#define ZSTD_COMPRESSBLOCK_GREEDY_DEDICATEDDICTSEARCH ZSTD_compressBlock_greedy_dedicatedDictSearch
#define ZSTD_COMPRESSBLOCK_GREEDY_DEDICATEDDICTSEARCH_ROW ZSTD_compressBlock_greedy_dedicatedDictSearch_row
#define ZSTD_COMPRESSBLOCK_GREEDY_EXTDICT ZSTD_compressBlock_greedy_extDict
#define ZSTD_COMPRESSBLOCK_GREEDY_EXTDICT_ROW ZSTD_compressBlock_greedy_extDict_row
#else
#define ZSTD_COMPRESSBLOCK_GREEDY NULL
#define ZSTD_COMPRESSBLOCK_GREEDY_ROW NULL
#define ZSTD_COMPRESSBLOCK_GREEDY_DICTMATCHSTATE NULL
#define ZSTD_COMPRESSBLOCK_GREEDY_DICTMATCHSTATE_ROW NULL
#define ZSTD_COMPRESSBLOCK_GREEDY_DEDICATEDDICTSEARCH NULL
#define ZSTD_COMPRESSBLOCK_GREEDY_DEDICATEDDICTSEARCH_ROW NULL
#define ZSTD_COMPRESSBLOCK_GREEDY_EXTDICT NULL
#define ZSTD_COMPRESSBLOCK_GREEDY_EXTDICT_ROW NULL
#endif

#ifndef ZSTD_EXCLUDE_LAZY_BLOCK_COMPRESSOR
size_t ZSTD_compressBlock_lazy(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_lazy_row(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_lazy_dictMatchState(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_lazy_dictMatchState_row(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_lazy_dedicatedDictSearch(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_lazy_dedicatedDictSearch_row(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_lazy_extDict(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_lazy_extDict_row(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);

#define ZSTD_COMPRESSBLOCK_LAZY ZSTD_compressBlock_lazy
#define ZSTD_COMPRESSBLOCK_LAZY_ROW ZSTD_compressBlock_lazy_row
#define ZSTD_COMPRESSBLOCK_LAZY_DICTMATCHSTATE ZSTD_compressBlock_lazy_dictMatchState
#define ZSTD_COMPRESSBLOCK_LAZY_DICTMATCHSTATE_ROW ZSTD_compressBlock_lazy_dictMatchState_row
#define ZSTD_COMPRESSBLOCK_LAZY_DEDICATEDDICTSEARCH ZSTD_compressBlock_lazy_dedicatedDictSearch
#define ZSTD_COMPRESSBLOCK_LAZY_DEDICATEDDICTSEARCH_ROW ZSTD_compressBlock_lazy_dedicatedDictSearch_row
#define ZSTD_COMPRESSBLOCK_LAZY_EXTDICT ZSTD_compressBlock_lazy_extDict
#define ZSTD_COMPRESSBLOCK_LAZY_EXTDICT_ROW ZSTD_compressBlock_lazy_extDict_row
#else
#define ZSTD_COMPRESSBLOCK_LAZY NULL
#define ZSTD_COMPRESSBLOCK_LAZY_ROW NULL
#define ZSTD_COMPRESSBLOCK_LAZY_DICTMATCHSTATE NULL
#define ZSTD_COMPRESSBLOCK_LAZY_DICTMATCHSTATE_ROW NULL
#define ZSTD_COMPRESSBLOCK_LAZY_DEDICATEDDICTSEARCH NULL
#define ZSTD_COMPRESSBLOCK_LAZY_DEDICATEDDICTSEARCH_ROW NULL
#define ZSTD_COMPRESSBLOCK_LAZY_EXTDICT NULL
#define ZSTD_COMPRESSBLOCK_LAZY_EXTDICT_ROW NULL
#endif

#ifndef ZSTD_EXCLUDE_LAZY2_BLOCK_COMPRESSOR
size_t ZSTD_compressBlock_lazy2(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_lazy2_row(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_lazy2_dictMatchState(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_lazy2_dictMatchState_row(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_lazy2_dedicatedDictSearch(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_lazy2_dedicatedDictSearch_row(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_lazy2_extDict(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_lazy2_extDict_row(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);

#define ZSTD_COMPRESSBLOCK_LAZY2 ZSTD_compressBlock_lazy2
#define ZSTD_COMPRESSBLOCK_LAZY2_ROW ZSTD_compressBlock_lazy2_row
#define ZSTD_COMPRESSBLOCK_LAZY2_DICTMATCHSTATE ZSTD_compressBlock_lazy2_dictMatchState
#define ZSTD_COMPRESSBLOCK_LAZY2_DICTMATCHSTATE_ROW ZSTD_compressBlock_lazy2_dictMatchState_row
#define ZSTD_COMPRESSBLOCK_LAZY2_DEDICATEDDICTSEARCH ZSTD_compressBlock_lazy2_dedicatedDictSearch
#define ZSTD_COMPRESSBLOCK_LAZY2_DEDICATEDDICTSEARCH_ROW ZSTD_compressBlock_lazy2_dedicatedDictSearch_row
#define ZSTD_COMPRESSBLOCK_LAZY2_EXTDICT ZSTD_compressBlock_lazy2_extDict
#define ZSTD_COMPRESSBLOCK_LAZY2_EXTDICT_ROW ZSTD_compressBlock_lazy2_extDict_row
#else
#define ZSTD_COMPRESSBLOCK_LAZY2 NULL
#define ZSTD_COMPRESSBLOCK_LAZY2_ROW NULL
#define ZSTD_COMPRESSBLOCK_LAZY2_DICTMATCHSTATE NULL
#define ZSTD_COMPRESSBLOCK_LAZY2_DICTMATCHSTATE_ROW NULL
#define ZSTD_COMPRESSBLOCK_LAZY2_DEDICATEDDICTSEARCH NULL
#define ZSTD_COMPRESSBLOCK_LAZY2_DEDICATEDDICTSEARCH_ROW NULL
#define ZSTD_COMPRESSBLOCK_LAZY2_EXTDICT NULL
#define ZSTD_COMPRESSBLOCK_LAZY2_EXTDICT_ROW NULL
#endif

#ifndef ZSTD_EXCLUDE_BTLAZY2_BLOCK_COMPRESSOR
size_t ZSTD_compressBlock_btlazy2(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_btlazy2_dictMatchState(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_btlazy2_extDict(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);

#define ZSTD_COMPRESSBLOCK_BTLAZY2 ZSTD_compressBlock_btlazy2
#define ZSTD_COMPRESSBLOCK_BTLAZY2_DICTMATCHSTATE ZSTD_compressBlock_btlazy2_dictMatchState
#define ZSTD_COMPRESSBLOCK_BTLAZY2_EXTDICT ZSTD_compressBlock_btlazy2_extDict
#else
#define ZSTD_COMPRESSBLOCK_BTLAZY2 NULL
#define ZSTD_COMPRESSBLOCK_BTLAZY2_DICTMATCHSTATE NULL
#define ZSTD_COMPRESSBLOCK_BTLAZY2_EXTDICT NULL
#endif

#endif /* ZSTD_LAZY_H */
/**** ended inlining zstd_lazy.h ****/
/**** start inlining zstd_opt.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_OPT_H
#define ZSTD_OPT_H

/**** skipping file: zstd_compress_internal.h ****/

#if !defined(ZSTD_EXCLUDE_BTLAZY2_BLOCK_COMPRESSOR) \
 || !defined(ZSTD_EXCLUDE_BTOPT_BLOCK_COMPRESSOR) \
 || !defined(ZSTD_EXCLUDE_BTULTRA_BLOCK_COMPRESSOR)

void ZSTD_updateTree(ZSTD_MatchState_t* ms, const BYTE* ip, const BYTE* iend);
#endif

#ifndef ZSTD_EXCLUDE_BTOPT_BLOCK_COMPRESSOR
size_t ZSTD_compressBlock_btopt(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_btopt_dictMatchState(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_btopt_extDict(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);

#define ZSTD_COMPRESSBLOCK_BTOPT ZSTD_compressBlock_btopt
#define ZSTD_COMPRESSBLOCK_BTOPT_DICTMATCHSTATE ZSTD_compressBlock_btopt_dictMatchState
#define ZSTD_COMPRESSBLOCK_BTOPT_EXTDICT ZSTD_compressBlock_btopt_extDict
#else
#define ZSTD_COMPRESSBLOCK_BTOPT NULL
#define ZSTD_COMPRESSBLOCK_BTOPT_DICTMATCHSTATE NULL
#define ZSTD_COMPRESSBLOCK_BTOPT_EXTDICT NULL
#endif

#ifndef ZSTD_EXCLUDE_BTULTRA_BLOCK_COMPRESSOR
size_t ZSTD_compressBlock_btultra(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_btultra_dictMatchState(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);
size_t ZSTD_compressBlock_btultra_extDict(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);


size_t ZSTD_compressBlock_btultra2(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize);

#define ZSTD_COMPRESSBLOCK_BTULTRA ZSTD_compressBlock_btultra
#define ZSTD_COMPRESSBLOCK_BTULTRA_DICTMATCHSTATE ZSTD_compressBlock_btultra_dictMatchState
#define ZSTD_COMPRESSBLOCK_BTULTRA_EXTDICT ZSTD_compressBlock_btultra_extDict
#define ZSTD_COMPRESSBLOCK_BTULTRA2 ZSTD_compressBlock_btultra2
#else
#define ZSTD_COMPRESSBLOCK_BTULTRA NULL
#define ZSTD_COMPRESSBLOCK_BTULTRA_DICTMATCHSTATE NULL
#define ZSTD_COMPRESSBLOCK_BTULTRA_EXTDICT NULL
#define ZSTD_COMPRESSBLOCK_BTULTRA2 NULL
#endif

#endif /* ZSTD_OPT_H */
/**** ended inlining zstd_opt.h ****/
/**** start inlining zstd_ldm.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_LDM_H
#define ZSTD_LDM_H

/**** skipping file: zstd_compress_internal.h ****/
/**** skipping file: ../zstd.h ****/



#define ZSTD_LDM_DEFAULT_WINDOW_LOG ZSTD_WINDOWLOG_LIMIT_DEFAULT

typedef struct {
    U64 rolling;
    U64 stopMask;
} ldmRollingHashState_t;

void ZSTD_ldm_gear_reset(ldmRollingHashState_t* state,
                        BYTE const* data, size_t minMatchLength);
size_t ZSTD_ldm_gear_feed(ldmRollingHashState_t* state,
                         BYTE const* data, size_t size,
                         size_t* splits, unsigned* numSplits);

void ZSTD_ldm_fillHashTable(
            ldmState_t* state, const BYTE* ip,
            const BYTE* iend, ldmParams_t const* params);


size_t ZSTD_ldm_generateSequences(
            ldmState_t* ldms, RawSeqStore_t* sequences,
            ldmParams_t const* params, void const* src, size_t srcSize);


size_t ZSTD_ldm_blockCompress(RawSeqStore_t* rawSeqStore,
            ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
            ZSTD_ParamSwitch_e useRowMatchFinder,
            void const* src, size_t srcSize);


void ZSTD_ldm_skipSequences(RawSeqStore_t* rawSeqStore, size_t srcSize,
    U32 const minMatch);


void ZSTD_ldm_skipRawSeqStoreBytes(RawSeqStore_t* rawSeqStore, size_t nbBytes);


size_t ZSTD_ldm_getTableSize(ldmParams_t params);


size_t ZSTD_ldm_getMaxNbSeq(ldmParams_t params, size_t maxChunkSize);


void ZSTD_ldm_adjustParameters(ldmParams_t* params,
                               ZSTD_compressionParameters const* cParams);

#endif /* ZSTD_FAST_H */
/**** ended inlining zstd_ldm.h ****/
/**** skipping file: zstd_compress_superblock.h ****/
/**** skipping file: ../common/bits.h ****/



#ifndef ZSTD_COMPRESS_HEAPMODE
#  define ZSTD_COMPRESS_HEAPMODE 0
#endif


#ifndef ZSTD_HASHLOG3_MAX
#  define ZSTD_HASHLOG3_MAX 17
#endif



size_t convertSequences_noRepcodes(SeqDef* dstSeqs, const ZSTD_Sequence* inSeqs,
    size_t nbSequences);




size_t ZSTD_compressBound(size_t srcSize) {
    size_t const r = ZSTD_COMPRESSBOUND(srcSize);
    if (r==0) return ERROR(srcSize_wrong);
    return r;
}



struct ZSTD_CDict_s {
    const void* dictContent;
    size_t dictContentSize;
    ZSTD_dictContentType_e dictContentType; /* The dictContentType the CDict was created with */
    U32* entropyWorkspace; /* entropy workspace of HUF_WORKSPACE_SIZE bytes */
    ZSTD_cwksp workspace;
    ZSTD_MatchState_t matchState;
    ZSTD_compressedBlockState_t cBlockState;
    ZSTD_customMem customMem;
    U32 dictID;
    int compressionLevel; /* 0 indicates that advanced API was used to select CDict params */
    ZSTD_ParamSwitch_e useRowMatchFinder; /* Indicates whether the CDict was created with params that would use
                                           * row-based matchfinder. Unless the cdict is reloaded, we will use
                                           * the same greedy/lazy matchfinder at compression time.
                                           */
};  /* typedef'd to ZSTD_CDict within "zstd.h" */

ZSTD_CCtx* ZSTD_createCCtx(void)
{
    return ZSTD_createCCtx_advanced(ZSTD_defaultCMem);
}

static void ZSTD_initCCtx(ZSTD_CCtx* cctx, ZSTD_customMem memManager)
{
    assert(cctx != NULL);
    ZSTD_memset(cctx, 0, sizeof(*cctx));
    cctx->customMem = memManager;
#if DYNAMIC_BMI2
    ZSTD_SET_BMI2(cctx->bmi2, ZSTD_cpuSupportsBmi2());
#endif
    {   size_t const err = ZSTD_CCtx_reset(cctx, ZSTD_reset_parameters);
        assert(!ZSTD_isError(err));
        (void)err;
    }
}

ZSTD_CCtx* ZSTD_createCCtx_advanced(ZSTD_customMem customMem)
{
    ZSTD_STATIC_ASSERT(zcss_init==0);
    ZSTD_STATIC_ASSERT(ZSTD_CONTENTSIZE_UNKNOWN==(0ULL - 1));
    if ((!customMem.customAlloc) ^ (!customMem.customFree)) return NULL;
    {   ZSTD_CCtx* const cctx = (ZSTD_CCtx*)ZSTD_customMalloc(sizeof(ZSTD_CCtx), customMem);
        if (!cctx) return NULL;
        ZSTD_initCCtx(cctx, customMem);
        return cctx;
    }
}

ZSTD_CCtx* ZSTD_initStaticCCtx(void* workspace, size_t workspaceSize)
{
    ZSTD_cwksp ws;
    ZSTD_CCtx* cctx;
    if (workspaceSize <= sizeof(ZSTD_CCtx)) return NULL;  /* minimum size */
    if ((size_t)workspace & 7) return NULL;  /* must be 8-aligned */
    ZSTD_cwksp_init(&ws, workspace, workspaceSize, ZSTD_cwksp_static_alloc);

    cctx = (ZSTD_CCtx*)ZSTD_cwksp_reserve_object(&ws, sizeof(ZSTD_CCtx));
    if (cctx == NULL) return NULL;

    ZSTD_memset(cctx, 0, sizeof(ZSTD_CCtx));
    ZSTD_cwksp_move(&cctx->workspace, &ws);
    cctx->staticSize = workspaceSize;


    if (!ZSTD_cwksp_check_available(&cctx->workspace, TMP_WORKSPACE_SIZE + 2 * sizeof(ZSTD_compressedBlockState_t))) return NULL;
    cctx->blockState.prevCBlock = (ZSTD_compressedBlockState_t*)ZSTD_cwksp_reserve_object(&cctx->workspace, sizeof(ZSTD_compressedBlockState_t));
    cctx->blockState.nextCBlock = (ZSTD_compressedBlockState_t*)ZSTD_cwksp_reserve_object(&cctx->workspace, sizeof(ZSTD_compressedBlockState_t));
    cctx->tmpWorkspace = ZSTD_cwksp_reserve_object(&cctx->workspace, TMP_WORKSPACE_SIZE);
    cctx->tmpWkspSize = TMP_WORKSPACE_SIZE;
#if DYNAMIC_BMI2
    ZSTD_SET_BMI2(cctx->bmi2, ZSTD_cpuSupportsBmi2());
#endif
    return cctx;
}


static void ZSTD_clearAllDicts(ZSTD_CCtx* cctx)
{
    ZSTD_customFree(cctx->localDict.dictBuffer, cctx->customMem);
    ZSTD_freeCDict(cctx->localDict.cdict);
    ZSTD_memset(&cctx->localDict, 0, sizeof(cctx->localDict));
    ZSTD_memset(&cctx->prefixDict, 0, sizeof(cctx->prefixDict));
    cctx->cdict = NULL;
}

static size_t ZSTD_sizeof_localDict(ZSTD_localDict dict)
{
    size_t const bufferSize = dict.dictBuffer != NULL ? dict.dictSize : 0;
    size_t const cdictSize = ZSTD_sizeof_CDict(dict.cdict);
    return bufferSize + cdictSize;
}

static void ZSTD_freeCCtxContent(ZSTD_CCtx* cctx)
{
    assert(cctx != NULL);
    assert(cctx->staticSize == 0);
#ifdef ZSTD_MULTITHREAD
    ZSTDMT_freeCCtx(cctx->mtctx); cctx->mtctx = NULL;  /* pending jobs may use the dictionary */
#endif
    ZSTD_clearAllDicts(cctx);
    ZSTD_cwksp_free(&cctx->workspace, cctx->customMem);
}

size_t ZSTD_freeCCtx(ZSTD_CCtx* cctx)
{
    DEBUGLOG(3, "ZSTD_freeCCtx (address: %p)", (void*)cctx);
    if (cctx==NULL) return 0;   /* support free on NULL */
    RETURN_ERROR_IF(cctx->staticSize, memory_allocation,
                    "not compatible with static CCtx");
    {   int cctxInWorkspace = ZSTD_cwksp_owns_buffer(&cctx->workspace, cctx);
        ZSTD_freeCCtxContent(cctx);
        if (!cctxInWorkspace) ZSTD_customFree(cctx, cctx->customMem);
    }
    return 0;
}


static size_t ZSTD_sizeof_mtctx(const ZSTD_CCtx* cctx)
{
#ifdef ZSTD_MULTITHREAD
    return ZSTDMT_sizeof_CCtx(cctx->mtctx);
#else
    (void)cctx;
    return 0;
#endif
}


size_t ZSTD_sizeof_CCtx(const ZSTD_CCtx* cctx)
{
    if (cctx==NULL) return 0;   /* support sizeof on NULL */

    return (cctx->workspace.workspace == cctx ? 0 : sizeof(*cctx))
           + ZSTD_cwksp_sizeof(&cctx->workspace)
           + ZSTD_sizeof_localDict(cctx->localDict)
           + ZSTD_sizeof_mtctx(cctx);
}

size_t ZSTD_sizeof_CStream(const ZSTD_CStream* zcs)
{
    return ZSTD_sizeof_CCtx(zcs);  /* same object */
}


const SeqStore_t* ZSTD_getSeqStore(const ZSTD_CCtx* ctx) { return &(ctx->seqStore); }


static int ZSTD_rowMatchFinderSupported(const ZSTD_strategy strategy) {
    return (strategy >= ZSTD_greedy && strategy <= ZSTD_lazy2);
}


static int ZSTD_rowMatchFinderUsed(const ZSTD_strategy strategy, const ZSTD_ParamSwitch_e mode) {
    assert(mode != ZSTD_ps_auto);
    return ZSTD_rowMatchFinderSupported(strategy) && (mode == ZSTD_ps_enable);
}


static ZSTD_ParamSwitch_e ZSTD_resolveRowMatchFinderMode(ZSTD_ParamSwitch_e mode,
                                                         const ZSTD_compressionParameters* const cParams) {
#ifdef ZSTD_LINUX_KERNEL

    const unsigned kWindowLogLowerBound = 17;
#else
    const unsigned kWindowLogLowerBound = 14;
#endif
    if (mode != ZSTD_ps_auto) return mode; /* if requested enabled, but no SIMD, we still will use row matchfinder */
    mode = ZSTD_ps_disable;
    if (!ZSTD_rowMatchFinderSupported(cParams->strategy)) return mode;
    if (cParams->windowLog > kWindowLogLowerBound) mode = ZSTD_ps_enable;
    return mode;
}


static ZSTD_ParamSwitch_e ZSTD_resolveBlockSplitterMode(ZSTD_ParamSwitch_e mode,
                                                        const ZSTD_compressionParameters* const cParams) {
    if (mode != ZSTD_ps_auto) return mode;
    return (cParams->strategy >= ZSTD_btopt && cParams->windowLog >= 17) ? ZSTD_ps_enable : ZSTD_ps_disable;
}


static int ZSTD_allocateChainTable(const ZSTD_strategy strategy,
                                   const ZSTD_ParamSwitch_e useRowMatchFinder,
                                   const U32 forDDSDict) {
    assert(useRowMatchFinder != ZSTD_ps_auto);

    return forDDSDict || ((strategy != ZSTD_fast) && !ZSTD_rowMatchFinderUsed(strategy, useRowMatchFinder));
}


static ZSTD_ParamSwitch_e ZSTD_resolveEnableLdm(ZSTD_ParamSwitch_e mode,
                                 const ZSTD_compressionParameters* const cParams) {
    if (mode != ZSTD_ps_auto) return mode;
    return (cParams->strategy >= ZSTD_btopt && cParams->windowLog >= 27) ? ZSTD_ps_enable : ZSTD_ps_disable;
}

static int ZSTD_resolveExternalSequenceValidation(int mode) {
    return mode;
}


static size_t ZSTD_resolveMaxBlockSize(size_t maxBlockSize) {
    if (maxBlockSize == 0) {
        return ZSTD_BLOCKSIZE_MAX;
    } else {
        return maxBlockSize;
    }
}

static ZSTD_ParamSwitch_e ZSTD_resolveExternalRepcodeSearch(ZSTD_ParamSwitch_e value, int cLevel) {
    if (value != ZSTD_ps_auto) return value;
    if (cLevel < 10) {
        return ZSTD_ps_disable;
    } else {
        return ZSTD_ps_enable;
    }
}


static int ZSTD_CDictIndicesAreTagged(const ZSTD_compressionParameters* const cParams) {
    return cParams->strategy == ZSTD_fast || cParams->strategy == ZSTD_dfast;
}

static ZSTD_CCtx_params ZSTD_makeCCtxParamsFromCParams(
        ZSTD_compressionParameters cParams)
{
    ZSTD_CCtx_params cctxParams;

    ZSTD_CCtxParams_init(&cctxParams, ZSTD_CLEVEL_DEFAULT);
    cctxParams.cParams = cParams;


    cctxParams.ldmParams.enableLdm = ZSTD_resolveEnableLdm(cctxParams.ldmParams.enableLdm, &cParams);
    if (cctxParams.ldmParams.enableLdm == ZSTD_ps_enable) {
        ZSTD_ldm_adjustParameters(&cctxParams.ldmParams, &cParams);
        assert(cctxParams.ldmParams.hashLog >= cctxParams.ldmParams.bucketSizeLog);
        assert(cctxParams.ldmParams.hashRateLog < 32);
    }
    cctxParams.postBlockSplitter = ZSTD_resolveBlockSplitterMode(cctxParams.postBlockSplitter, &cParams);
    cctxParams.useRowMatchFinder = ZSTD_resolveRowMatchFinderMode(cctxParams.useRowMatchFinder, &cParams);
    cctxParams.validateSequences = ZSTD_resolveExternalSequenceValidation(cctxParams.validateSequences);
    cctxParams.maxBlockSize = ZSTD_resolveMaxBlockSize(cctxParams.maxBlockSize);
    cctxParams.searchForExternalRepcodes = ZSTD_resolveExternalRepcodeSearch(cctxParams.searchForExternalRepcodes,
                                                                             cctxParams.compressionLevel);
    assert(!ZSTD_checkCParams(cParams));
    return cctxParams;
}

static ZSTD_CCtx_params* ZSTD_createCCtxParams_advanced(
        ZSTD_customMem customMem)
{
    ZSTD_CCtx_params* params;
    if ((!customMem.customAlloc) ^ (!customMem.customFree)) return NULL;
    params = (ZSTD_CCtx_params*)ZSTD_customCalloc(
            sizeof(ZSTD_CCtx_params), customMem);
    if (!params) { return NULL; }
    ZSTD_CCtxParams_init(params, ZSTD_CLEVEL_DEFAULT);
    params->customMem = customMem;
    return params;
}

ZSTD_CCtx_params* ZSTD_createCCtxParams(void)
{
    return ZSTD_createCCtxParams_advanced(ZSTD_defaultCMem);
}

size_t ZSTD_freeCCtxParams(ZSTD_CCtx_params* params)
{
    if (params == NULL) { return 0; }
    ZSTD_customFree(params, params->customMem);
    return 0;
}

size_t ZSTD_CCtxParams_reset(ZSTD_CCtx_params* params)
{
    return ZSTD_CCtxParams_init(params, ZSTD_CLEVEL_DEFAULT);
}

size_t ZSTD_CCtxParams_init(ZSTD_CCtx_params* cctxParams, int compressionLevel) {
    RETURN_ERROR_IF(!cctxParams, GENERIC, "NULL pointer!");
    ZSTD_memset(cctxParams, 0, sizeof(*cctxParams));
    cctxParams->compressionLevel = compressionLevel;
    cctxParams->fParams.contentSizeFlag = 1;
    return 0;
}

#define ZSTD_NO_CLEVEL 0


static void
ZSTD_CCtxParams_init_internal(ZSTD_CCtx_params* cctxParams,
                        const ZSTD_parameters* params,
                              int compressionLevel)
{
    assert(!ZSTD_checkCParams(params->cParams));
    ZSTD_memset(cctxParams, 0, sizeof(*cctxParams));
    cctxParams->cParams = params->cParams;
    cctxParams->fParams = params->fParams;

    cctxParams->compressionLevel = compressionLevel;
    cctxParams->useRowMatchFinder = ZSTD_resolveRowMatchFinderMode(cctxParams->useRowMatchFinder, &params->cParams);
    cctxParams->postBlockSplitter = ZSTD_resolveBlockSplitterMode(cctxParams->postBlockSplitter, &params->cParams);
    cctxParams->ldmParams.enableLdm = ZSTD_resolveEnableLdm(cctxParams->ldmParams.enableLdm, &params->cParams);
    cctxParams->validateSequences = ZSTD_resolveExternalSequenceValidation(cctxParams->validateSequences);
    cctxParams->maxBlockSize = ZSTD_resolveMaxBlockSize(cctxParams->maxBlockSize);
    cctxParams->searchForExternalRepcodes = ZSTD_resolveExternalRepcodeSearch(cctxParams->searchForExternalRepcodes, compressionLevel);
    DEBUGLOG(4, "ZSTD_CCtxParams_init_internal: useRowMatchFinder=%d, useBlockSplitter=%d ldm=%d",
                cctxParams->useRowMatchFinder, cctxParams->postBlockSplitter, cctxParams->ldmParams.enableLdm);
}

size_t ZSTD_CCtxParams_init_advanced(ZSTD_CCtx_params* cctxParams, ZSTD_parameters params)
{
    RETURN_ERROR_IF(!cctxParams, GENERIC, "NULL pointer!");
    FORWARD_IF_ERROR( ZSTD_checkCParams(params.cParams) , "");
    ZSTD_CCtxParams_init_internal(cctxParams, &params, ZSTD_NO_CLEVEL);
    return 0;
}


static void ZSTD_CCtxParams_setZstdParams(
        ZSTD_CCtx_params* cctxParams, const ZSTD_parameters* params)
{
    assert(!ZSTD_checkCParams(params->cParams));
    cctxParams->cParams = params->cParams;
    cctxParams->fParams = params->fParams;

    cctxParams->compressionLevel = ZSTD_NO_CLEVEL;
}

ZSTD_bounds ZSTD_cParam_getBounds(ZSTD_cParameter param)
{
    ZSTD_bounds bounds = { 0, 0, 0 };

    switch(param)
    {
    case ZSTD_c_compressionLevel:
        bounds.lowerBound = ZSTD_minCLevel();
        bounds.upperBound = ZSTD_maxCLevel();
        return bounds;

    case ZSTD_c_windowLog:
        bounds.lowerBound = ZSTD_WINDOWLOG_MIN;
        bounds.upperBound = ZSTD_WINDOWLOG_MAX;
        return bounds;

    case ZSTD_c_hashLog:
        bounds.lowerBound = ZSTD_HASHLOG_MIN;
        bounds.upperBound = ZSTD_HASHLOG_MAX;
        return bounds;

    case ZSTD_c_chainLog:
        bounds.lowerBound = ZSTD_CHAINLOG_MIN;
        bounds.upperBound = ZSTD_CHAINLOG_MAX;
        return bounds;

    case ZSTD_c_searchLog:
        bounds.lowerBound = ZSTD_SEARCHLOG_MIN;
        bounds.upperBound = ZSTD_SEARCHLOG_MAX;
        return bounds;

    case ZSTD_c_minMatch:
        bounds.lowerBound = ZSTD_MINMATCH_MIN;
        bounds.upperBound = ZSTD_MINMATCH_MAX;
        return bounds;

    case ZSTD_c_targetLength:
        bounds.lowerBound = ZSTD_TARGETLENGTH_MIN;
        bounds.upperBound = ZSTD_TARGETLENGTH_MAX;
        return bounds;

    case ZSTD_c_strategy:
        bounds.lowerBound = ZSTD_STRATEGY_MIN;
        bounds.upperBound = ZSTD_STRATEGY_MAX;
        return bounds;

    case ZSTD_c_contentSizeFlag:
        bounds.lowerBound = 0;
        bounds.upperBound = 1;
        return bounds;

    case ZSTD_c_checksumFlag:
        bounds.lowerBound = 0;
        bounds.upperBound = 1;
        return bounds;

    case ZSTD_c_dictIDFlag:
        bounds.lowerBound = 0;
        bounds.upperBound = 1;
        return bounds;

    case ZSTD_c_nbWorkers:
        bounds.lowerBound = 0;
#ifdef ZSTD_MULTITHREAD
        bounds.upperBound = ZSTDMT_NBWORKERS_MAX;
#else
        bounds.upperBound = 0;
#endif
        return bounds;

    case ZSTD_c_jobSize:
        bounds.lowerBound = 0;
#ifdef ZSTD_MULTITHREAD
        bounds.upperBound = ZSTDMT_JOBSIZE_MAX;
#else
        bounds.upperBound = 0;
#endif
        return bounds;

    case ZSTD_c_overlapLog:
#ifdef ZSTD_MULTITHREAD
        bounds.lowerBound = ZSTD_OVERLAPLOG_MIN;
        bounds.upperBound = ZSTD_OVERLAPLOG_MAX;
#else
        bounds.lowerBound = 0;
        bounds.upperBound = 0;
#endif
        return bounds;

    case ZSTD_c_enableDedicatedDictSearch:
        bounds.lowerBound = 0;
        bounds.upperBound = 1;
        return bounds;

    case ZSTD_c_enableLongDistanceMatching:
        bounds.lowerBound = (int)ZSTD_ps_auto;
        bounds.upperBound = (int)ZSTD_ps_disable;
        return bounds;

    case ZSTD_c_ldmHashLog:
        bounds.lowerBound = ZSTD_LDM_HASHLOG_MIN;
        bounds.upperBound = ZSTD_LDM_HASHLOG_MAX;
        return bounds;

    case ZSTD_c_ldmMinMatch:
        bounds.lowerBound = ZSTD_LDM_MINMATCH_MIN;
        bounds.upperBound = ZSTD_LDM_MINMATCH_MAX;
        return bounds;

    case ZSTD_c_ldmBucketSizeLog:
        bounds.lowerBound = ZSTD_LDM_BUCKETSIZELOG_MIN;
        bounds.upperBound = ZSTD_LDM_BUCKETSIZELOG_MAX;
        return bounds;

    case ZSTD_c_ldmHashRateLog:
        bounds.lowerBound = ZSTD_LDM_HASHRATELOG_MIN;
        bounds.upperBound = ZSTD_LDM_HASHRATELOG_MAX;
        return bounds;


    case ZSTD_c_rsyncable:
        bounds.lowerBound = 0;
        bounds.upperBound = 1;
        return bounds;

    case ZSTD_c_forceMaxWindow :
        bounds.lowerBound = 0;
        bounds.upperBound = 1;
        return bounds;

    case ZSTD_c_format:
        ZSTD_STATIC_ASSERT(ZSTD_f_zstd1 < ZSTD_f_zstd1_magicless);
        bounds.lowerBound = ZSTD_f_zstd1;
        bounds.upperBound = ZSTD_f_zstd1_magicless;   /* note : how to ensure at compile time that this is the highest value enum ? */
        return bounds;

    case ZSTD_c_forceAttachDict:
        ZSTD_STATIC_ASSERT(ZSTD_dictDefaultAttach < ZSTD_dictForceLoad);
        bounds.lowerBound = ZSTD_dictDefaultAttach;
        bounds.upperBound = ZSTD_dictForceLoad;       /* note : how to ensure at compile time that this is the highest value enum ? */
        return bounds;

    case ZSTD_c_literalCompressionMode:
        ZSTD_STATIC_ASSERT(ZSTD_ps_auto < ZSTD_ps_enable && ZSTD_ps_enable < ZSTD_ps_disable);
        bounds.lowerBound = (int)ZSTD_ps_auto;
        bounds.upperBound = (int)ZSTD_ps_disable;
        return bounds;

    case ZSTD_c_targetCBlockSize:
        bounds.lowerBound = ZSTD_TARGETCBLOCKSIZE_MIN;
        bounds.upperBound = ZSTD_TARGETCBLOCKSIZE_MAX;
        return bounds;

    case ZSTD_c_srcSizeHint:
        bounds.lowerBound = ZSTD_SRCSIZEHINT_MIN;
        bounds.upperBound = ZSTD_SRCSIZEHINT_MAX;
        return bounds;

    case ZSTD_c_stableInBuffer:
    case ZSTD_c_stableOutBuffer:
        bounds.lowerBound = (int)ZSTD_bm_buffered;
        bounds.upperBound = (int)ZSTD_bm_stable;
        return bounds;

    case ZSTD_c_blockDelimiters:
        bounds.lowerBound = (int)ZSTD_sf_noBlockDelimiters;
        bounds.upperBound = (int)ZSTD_sf_explicitBlockDelimiters;
        return bounds;

    case ZSTD_c_validateSequences:
        bounds.lowerBound = 0;
        bounds.upperBound = 1;
        return bounds;

    case ZSTD_c_splitAfterSequences:
        bounds.lowerBound = (int)ZSTD_ps_auto;
        bounds.upperBound = (int)ZSTD_ps_disable;
        return bounds;

    case ZSTD_c_blockSplitterLevel:
        bounds.lowerBound = 0;
        bounds.upperBound = ZSTD_BLOCKSPLITTER_LEVEL_MAX;
        return bounds;

    case ZSTD_c_useRowMatchFinder:
        bounds.lowerBound = (int)ZSTD_ps_auto;
        bounds.upperBound = (int)ZSTD_ps_disable;
        return bounds;

    case ZSTD_c_deterministicRefPrefix:
        bounds.lowerBound = 0;
        bounds.upperBound = 1;
        return bounds;

    case ZSTD_c_prefetchCDictTables:
        bounds.lowerBound = (int)ZSTD_ps_auto;
        bounds.upperBound = (int)ZSTD_ps_disable;
        return bounds;

    case ZSTD_c_enableSeqProducerFallback:
        bounds.lowerBound = 0;
        bounds.upperBound = 1;
        return bounds;

    case ZSTD_c_maxBlockSize:
        bounds.lowerBound = ZSTD_BLOCKSIZE_MAX_MIN;
        bounds.upperBound = ZSTD_BLOCKSIZE_MAX;
        return bounds;

    case ZSTD_c_repcodeResolution:
        bounds.lowerBound = (int)ZSTD_ps_auto;
        bounds.upperBound = (int)ZSTD_ps_disable;
        return bounds;

    default:
        bounds.error = ERROR(parameter_unsupported);
        return bounds;
    }
}


static size_t ZSTD_cParam_clampBounds(ZSTD_cParameter cParam, int* value)
{
    ZSTD_bounds const bounds = ZSTD_cParam_getBounds(cParam);
    if (ZSTD_isError(bounds.error)) return bounds.error;
    if (*value < bounds.lowerBound) *value = bounds.lowerBound;
    if (*value > bounds.upperBound) *value = bounds.upperBound;
    return 0;
}

#define BOUNDCHECK(cParam, val)                                       \
    do {                                                              \
        RETURN_ERROR_IF(!ZSTD_cParam_withinBounds(cParam,val),        \
                        parameter_outOfBound, "Param out of bounds"); \
    } while (0)


static int ZSTD_isUpdateAuthorized(ZSTD_cParameter param)
{
    switch(param)
    {
    case ZSTD_c_compressionLevel:
    case ZSTD_c_hashLog:
    case ZSTD_c_chainLog:
    case ZSTD_c_searchLog:
    case ZSTD_c_minMatch:
    case ZSTD_c_targetLength:
    case ZSTD_c_strategy:
    case ZSTD_c_blockSplitterLevel:
        return 1;

    case ZSTD_c_format:
    case ZSTD_c_windowLog:
    case ZSTD_c_contentSizeFlag:
    case ZSTD_c_checksumFlag:
    case ZSTD_c_dictIDFlag:
    case ZSTD_c_forceMaxWindow :
    case ZSTD_c_nbWorkers:
    case ZSTD_c_jobSize:
    case ZSTD_c_overlapLog:
    case ZSTD_c_rsyncable:
    case ZSTD_c_enableDedicatedDictSearch:
    case ZSTD_c_enableLongDistanceMatching:
    case ZSTD_c_ldmHashLog:
    case ZSTD_c_ldmMinMatch:
    case ZSTD_c_ldmBucketSizeLog:
    case ZSTD_c_ldmHashRateLog:
    case ZSTD_c_forceAttachDict:
    case ZSTD_c_literalCompressionMode:
    case ZSTD_c_targetCBlockSize:
    case ZSTD_c_srcSizeHint:
    case ZSTD_c_stableInBuffer:
    case ZSTD_c_stableOutBuffer:
    case ZSTD_c_blockDelimiters:
    case ZSTD_c_validateSequences:
    case ZSTD_c_splitAfterSequences:
    case ZSTD_c_useRowMatchFinder:
    case ZSTD_c_deterministicRefPrefix:
    case ZSTD_c_prefetchCDictTables:
    case ZSTD_c_enableSeqProducerFallback:
    case ZSTD_c_maxBlockSize:
    case ZSTD_c_repcodeResolution:
    default:
        return 0;
    }
}

size_t ZSTD_CCtx_setParameter(ZSTD_CCtx* cctx, ZSTD_cParameter param, int value)
{
    DEBUGLOG(4, "ZSTD_CCtx_setParameter (%i, %i)", (int)param, value);
    if (cctx->streamStage != zcss_init) {
        if (ZSTD_isUpdateAuthorized(param)) {
            cctx->cParamsChanged = 1;
        } else {
            RETURN_ERROR(stage_wrong, "can only set params in cctx init stage");
    }   }

    switch(param)
    {
    case ZSTD_c_nbWorkers:
        RETURN_ERROR_IF((value!=0) && cctx->staticSize, parameter_unsupported,
                        "MT not compatible with static alloc");
        break;

    case ZSTD_c_compressionLevel:
    case ZSTD_c_windowLog:
    case ZSTD_c_hashLog:
    case ZSTD_c_chainLog:
    case ZSTD_c_searchLog:
    case ZSTD_c_minMatch:
    case ZSTD_c_targetLength:
    case ZSTD_c_strategy:
    case ZSTD_c_ldmHashRateLog:
    case ZSTD_c_format:
    case ZSTD_c_contentSizeFlag:
    case ZSTD_c_checksumFlag:
    case ZSTD_c_dictIDFlag:
    case ZSTD_c_forceMaxWindow:
    case ZSTD_c_forceAttachDict:
    case ZSTD_c_literalCompressionMode:
    case ZSTD_c_jobSize:
    case ZSTD_c_overlapLog:
    case ZSTD_c_rsyncable:
    case ZSTD_c_enableDedicatedDictSearch:
    case ZSTD_c_enableLongDistanceMatching:
    case ZSTD_c_ldmHashLog:
    case ZSTD_c_ldmMinMatch:
    case ZSTD_c_ldmBucketSizeLog:
    case ZSTD_c_targetCBlockSize:
    case ZSTD_c_srcSizeHint:
    case ZSTD_c_stableInBuffer:
    case ZSTD_c_stableOutBuffer:
    case ZSTD_c_blockDelimiters:
    case ZSTD_c_validateSequences:
    case ZSTD_c_splitAfterSequences:
    case ZSTD_c_blockSplitterLevel:
    case ZSTD_c_useRowMatchFinder:
    case ZSTD_c_deterministicRefPrefix:
    case ZSTD_c_prefetchCDictTables:
    case ZSTD_c_enableSeqProducerFallback:
    case ZSTD_c_maxBlockSize:
    case ZSTD_c_repcodeResolution:
        break;

    default: RETURN_ERROR(parameter_unsupported, "unknown parameter");
    }
    return ZSTD_CCtxParams_setParameter(&cctx->requestedParams, param, value);
}

size_t ZSTD_CCtxParams_setParameter(ZSTD_CCtx_params* CCtxParams,
                                    ZSTD_cParameter param, int value)
{
    DEBUGLOG(4, "ZSTD_CCtxParams_setParameter (%i, %i)", (int)param, value);
    switch(param)
    {
    case ZSTD_c_format :
        BOUNDCHECK(ZSTD_c_format, value);
        CCtxParams->format = (ZSTD_format_e)value;
        return (size_t)CCtxParams->format;

    case ZSTD_c_compressionLevel : {
        FORWARD_IF_ERROR(ZSTD_cParam_clampBounds(param, &value), "");
        if (value == 0)
            CCtxParams->compressionLevel = ZSTD_CLEVEL_DEFAULT; /* 0 == default */
        else
            CCtxParams->compressionLevel = value;
        if (CCtxParams->compressionLevel >= 0) return (size_t)CCtxParams->compressionLevel;
        return 0;  /* return type (size_t) cannot represent negative values */
    }

    case ZSTD_c_windowLog :
        if (value!=0)   /* 0 => use default */
            BOUNDCHECK(ZSTD_c_windowLog, value);
        CCtxParams->cParams.windowLog = (U32)value;
        return CCtxParams->cParams.windowLog;

    case ZSTD_c_hashLog :
        if (value!=0)   /* 0 => use default */
            BOUNDCHECK(ZSTD_c_hashLog, value);
        CCtxParams->cParams.hashLog = (U32)value;
        return CCtxParams->cParams.hashLog;

    case ZSTD_c_chainLog :
        if (value!=0)   /* 0 => use default */
            BOUNDCHECK(ZSTD_c_chainLog, value);
        CCtxParams->cParams.chainLog = (U32)value;
        return CCtxParams->cParams.chainLog;

    case ZSTD_c_searchLog :
        if (value!=0)   /* 0 => use default */
            BOUNDCHECK(ZSTD_c_searchLog, value);
        CCtxParams->cParams.searchLog = (U32)value;
        return (size_t)value;

    case ZSTD_c_minMatch :
        if (value!=0)   /* 0 => use default */
            BOUNDCHECK(ZSTD_c_minMatch, value);
        CCtxParams->cParams.minMatch = (U32)value;
        return CCtxParams->cParams.minMatch;

    case ZSTD_c_targetLength :
        BOUNDCHECK(ZSTD_c_targetLength, value);
        CCtxParams->cParams.targetLength = (U32)value;
        return CCtxParams->cParams.targetLength;

    case ZSTD_c_strategy :
        if (value!=0)   /* 0 => use default */
            BOUNDCHECK(ZSTD_c_strategy, value);
        CCtxParams->cParams.strategy = (ZSTD_strategy)value;
        return (size_t)CCtxParams->cParams.strategy;

    case ZSTD_c_contentSizeFlag :

        DEBUGLOG(4, "set content size flag = %u", (value!=0));
        CCtxParams->fParams.contentSizeFlag = value != 0;
        return (size_t)CCtxParams->fParams.contentSizeFlag;

    case ZSTD_c_checksumFlag :

        CCtxParams->fParams.checksumFlag = value != 0;
        return (size_t)CCtxParams->fParams.checksumFlag;

    case ZSTD_c_dictIDFlag : /* When applicable, dictionary's dictID is provided in frame header (default:1) */
        DEBUGLOG(4, "set dictIDFlag = %u", (value!=0));
        CCtxParams->fParams.noDictIDFlag = !value;
        return !CCtxParams->fParams.noDictIDFlag;

    case ZSTD_c_forceMaxWindow :
        CCtxParams->forceWindow = (value != 0);
        return (size_t)CCtxParams->forceWindow;

    case ZSTD_c_forceAttachDict : {
        const ZSTD_dictAttachPref_e pref = (ZSTD_dictAttachPref_e)value;
        BOUNDCHECK(ZSTD_c_forceAttachDict, (int)pref);
        CCtxParams->attachDictPref = pref;
        return CCtxParams->attachDictPref;
    }

    case ZSTD_c_literalCompressionMode : {
        const ZSTD_ParamSwitch_e lcm = (ZSTD_ParamSwitch_e)value;
        BOUNDCHECK(ZSTD_c_literalCompressionMode, (int)lcm);
        CCtxParams->literalCompressionMode = lcm;
        return CCtxParams->literalCompressionMode;
    }

    case ZSTD_c_nbWorkers :
#ifndef ZSTD_MULTITHREAD
        RETURN_ERROR_IF(value!=0, parameter_unsupported, "not compiled with multithreading");
        return 0;
#else
        FORWARD_IF_ERROR(ZSTD_cParam_clampBounds(param, &value), "");
        CCtxParams->nbWorkers = value;
        return (size_t)(CCtxParams->nbWorkers);
#endif

    case ZSTD_c_jobSize :
#ifndef ZSTD_MULTITHREAD
        RETURN_ERROR_IF(value!=0, parameter_unsupported, "not compiled with multithreading");
        return 0;
#else

        if (value != 0 && value < ZSTDMT_JOBSIZE_MIN)
            value = ZSTDMT_JOBSIZE_MIN;
        FORWARD_IF_ERROR(ZSTD_cParam_clampBounds(param, &value), "");
        assert(value >= 0);
        CCtxParams->jobSize = (size_t)value;
        return CCtxParams->jobSize;
#endif

    case ZSTD_c_overlapLog :
#ifndef ZSTD_MULTITHREAD
        RETURN_ERROR_IF(value!=0, parameter_unsupported, "not compiled with multithreading");
        return 0;
#else
        FORWARD_IF_ERROR(ZSTD_cParam_clampBounds(ZSTD_c_overlapLog, &value), "");
        CCtxParams->overlapLog = value;
        return (size_t)CCtxParams->overlapLog;
#endif

    case ZSTD_c_rsyncable :
#ifndef ZSTD_MULTITHREAD
        RETURN_ERROR_IF(value!=0, parameter_unsupported, "not compiled with multithreading");
        return 0;
#else
        FORWARD_IF_ERROR(ZSTD_cParam_clampBounds(ZSTD_c_overlapLog, &value), "");
        CCtxParams->rsyncable = value;
        return (size_t)CCtxParams->rsyncable;
#endif

    case ZSTD_c_enableDedicatedDictSearch :
        CCtxParams->enableDedicatedDictSearch = (value!=0);
        return (size_t)CCtxParams->enableDedicatedDictSearch;

    case ZSTD_c_enableLongDistanceMatching :
        BOUNDCHECK(ZSTD_c_enableLongDistanceMatching, value);
        CCtxParams->ldmParams.enableLdm = (ZSTD_ParamSwitch_e)value;
        return CCtxParams->ldmParams.enableLdm;

    case ZSTD_c_ldmHashLog :
        if (value!=0)   /* 0 ==> auto */
            BOUNDCHECK(ZSTD_c_ldmHashLog, value);
        CCtxParams->ldmParams.hashLog = (U32)value;
        return CCtxParams->ldmParams.hashLog;

    case ZSTD_c_ldmMinMatch :
        if (value!=0)   /* 0 ==> default */
            BOUNDCHECK(ZSTD_c_ldmMinMatch, value);
        CCtxParams->ldmParams.minMatchLength = (U32)value;
        return CCtxParams->ldmParams.minMatchLength;

    case ZSTD_c_ldmBucketSizeLog :
        if (value!=0)   /* 0 ==> default */
            BOUNDCHECK(ZSTD_c_ldmBucketSizeLog, value);
        CCtxParams->ldmParams.bucketSizeLog = (U32)value;
        return CCtxParams->ldmParams.bucketSizeLog;

    case ZSTD_c_ldmHashRateLog :
        if (value!=0)   /* 0 ==> default */
            BOUNDCHECK(ZSTD_c_ldmHashRateLog, value);
        CCtxParams->ldmParams.hashRateLog = (U32)value;
        return CCtxParams->ldmParams.hashRateLog;

    case ZSTD_c_targetCBlockSize :
        if (value!=0) {  /* 0 ==> default */
            value = MAX(value, ZSTD_TARGETCBLOCKSIZE_MIN);
            BOUNDCHECK(ZSTD_c_targetCBlockSize, value);
        }
        CCtxParams->targetCBlockSize = (U32)value;
        return CCtxParams->targetCBlockSize;

    case ZSTD_c_srcSizeHint :
        if (value!=0)    /* 0 ==> default */
            BOUNDCHECK(ZSTD_c_srcSizeHint, value);
        CCtxParams->srcSizeHint = value;
        return (size_t)CCtxParams->srcSizeHint;

    case ZSTD_c_stableInBuffer:
        BOUNDCHECK(ZSTD_c_stableInBuffer, value);
        CCtxParams->inBufferMode = (ZSTD_bufferMode_e)value;
        return CCtxParams->inBufferMode;

    case ZSTD_c_stableOutBuffer:
        BOUNDCHECK(ZSTD_c_stableOutBuffer, value);
        CCtxParams->outBufferMode = (ZSTD_bufferMode_e)value;
        return CCtxParams->outBufferMode;

    case ZSTD_c_blockDelimiters:
        BOUNDCHECK(ZSTD_c_blockDelimiters, value);
        CCtxParams->blockDelimiters = (ZSTD_SequenceFormat_e)value;
        return CCtxParams->blockDelimiters;

    case ZSTD_c_validateSequences:
        BOUNDCHECK(ZSTD_c_validateSequences, value);
        CCtxParams->validateSequences = value;
        return (size_t)CCtxParams->validateSequences;

    case ZSTD_c_splitAfterSequences:
        BOUNDCHECK(ZSTD_c_splitAfterSequences, value);
        CCtxParams->postBlockSplitter = (ZSTD_ParamSwitch_e)value;
        return CCtxParams->postBlockSplitter;

    case ZSTD_c_blockSplitterLevel:
        BOUNDCHECK(ZSTD_c_blockSplitterLevel, value);
        CCtxParams->preBlockSplitter_level = value;
        return (size_t)CCtxParams->preBlockSplitter_level;

    case ZSTD_c_useRowMatchFinder:
        BOUNDCHECK(ZSTD_c_useRowMatchFinder, value);
        CCtxParams->useRowMatchFinder = (ZSTD_ParamSwitch_e)value;
        return CCtxParams->useRowMatchFinder;

    case ZSTD_c_deterministicRefPrefix:
        BOUNDCHECK(ZSTD_c_deterministicRefPrefix, value);
        CCtxParams->deterministicRefPrefix = !!value;
        return (size_t)CCtxParams->deterministicRefPrefix;

    case ZSTD_c_prefetchCDictTables:
        BOUNDCHECK(ZSTD_c_prefetchCDictTables, value);
        CCtxParams->prefetchCDictTables = (ZSTD_ParamSwitch_e)value;
        return CCtxParams->prefetchCDictTables;

    case ZSTD_c_enableSeqProducerFallback:
        BOUNDCHECK(ZSTD_c_enableSeqProducerFallback, value);
        CCtxParams->enableMatchFinderFallback = value;
        return (size_t)CCtxParams->enableMatchFinderFallback;

    case ZSTD_c_maxBlockSize:
        if (value!=0)    /* 0 ==> default */
            BOUNDCHECK(ZSTD_c_maxBlockSize, value);
        assert(value>=0);
        CCtxParams->maxBlockSize = (size_t)value;
        return CCtxParams->maxBlockSize;

    case ZSTD_c_repcodeResolution:
        BOUNDCHECK(ZSTD_c_repcodeResolution, value);
        CCtxParams->searchForExternalRepcodes = (ZSTD_ParamSwitch_e)value;
        return CCtxParams->searchForExternalRepcodes;

    default: RETURN_ERROR(parameter_unsupported, "unknown parameter");
    }
}

size_t ZSTD_CCtx_getParameter(ZSTD_CCtx const* cctx, ZSTD_cParameter param, int* value)
{
    return ZSTD_CCtxParams_getParameter(&cctx->requestedParams, param, value);
}

size_t ZSTD_CCtxParams_getParameter(
        ZSTD_CCtx_params const* CCtxParams, ZSTD_cParameter param, int* value)
{
    switch(param)
    {
    case ZSTD_c_format :
        *value = (int)CCtxParams->format;
        break;
    case ZSTD_c_compressionLevel :
        *value = CCtxParams->compressionLevel;
        break;
    case ZSTD_c_windowLog :
        *value = (int)CCtxParams->cParams.windowLog;
        break;
    case ZSTD_c_hashLog :
        *value = (int)CCtxParams->cParams.hashLog;
        break;
    case ZSTD_c_chainLog :
        *value = (int)CCtxParams->cParams.chainLog;
        break;
    case ZSTD_c_searchLog :
        *value = (int)CCtxParams->cParams.searchLog;
        break;
    case ZSTD_c_minMatch :
        *value = (int)CCtxParams->cParams.minMatch;
        break;
    case ZSTD_c_targetLength :
        *value = (int)CCtxParams->cParams.targetLength;
        break;
    case ZSTD_c_strategy :
        *value = (int)CCtxParams->cParams.strategy;
        break;
    case ZSTD_c_contentSizeFlag :
        *value = CCtxParams->fParams.contentSizeFlag;
        break;
    case ZSTD_c_checksumFlag :
        *value = CCtxParams->fParams.checksumFlag;
        break;
    case ZSTD_c_dictIDFlag :
        *value = !CCtxParams->fParams.noDictIDFlag;
        break;
    case ZSTD_c_forceMaxWindow :
        *value = CCtxParams->forceWindow;
        break;
    case ZSTD_c_forceAttachDict :
        *value = (int)CCtxParams->attachDictPref;
        break;
    case ZSTD_c_literalCompressionMode :
        *value = (int)CCtxParams->literalCompressionMode;
        break;
    case ZSTD_c_nbWorkers :
#ifndef ZSTD_MULTITHREAD
        assert(CCtxParams->nbWorkers == 0);
#endif
        *value = CCtxParams->nbWorkers;
        break;
    case ZSTD_c_jobSize :
#ifndef ZSTD_MULTITHREAD
        RETURN_ERROR(parameter_unsupported, "not compiled with multithreading");
#else
        assert(CCtxParams->jobSize <= INT_MAX);
        *value = (int)CCtxParams->jobSize;
        break;
#endif
    case ZSTD_c_overlapLog :
#ifndef ZSTD_MULTITHREAD
        RETURN_ERROR(parameter_unsupported, "not compiled with multithreading");
#else
        *value = CCtxParams->overlapLog;
        break;
#endif
    case ZSTD_c_rsyncable :
#ifndef ZSTD_MULTITHREAD
        RETURN_ERROR(parameter_unsupported, "not compiled with multithreading");
#else
        *value = CCtxParams->rsyncable;
        break;
#endif
    case ZSTD_c_enableDedicatedDictSearch :
        *value = CCtxParams->enableDedicatedDictSearch;
        break;
    case ZSTD_c_enableLongDistanceMatching :
        *value = (int)CCtxParams->ldmParams.enableLdm;
        break;
    case ZSTD_c_ldmHashLog :
        *value = (int)CCtxParams->ldmParams.hashLog;
        break;
    case ZSTD_c_ldmMinMatch :
        *value = (int)CCtxParams->ldmParams.minMatchLength;
        break;
    case ZSTD_c_ldmBucketSizeLog :
        *value = (int)CCtxParams->ldmParams.bucketSizeLog;
        break;
    case ZSTD_c_ldmHashRateLog :
        *value = (int)CCtxParams->ldmParams.hashRateLog;
        break;
    case ZSTD_c_targetCBlockSize :
        *value = (int)CCtxParams->targetCBlockSize;
        break;
    case ZSTD_c_srcSizeHint :
        *value = (int)CCtxParams->srcSizeHint;
        break;
    case ZSTD_c_stableInBuffer :
        *value = (int)CCtxParams->inBufferMode;
        break;
    case ZSTD_c_stableOutBuffer :
        *value = (int)CCtxParams->outBufferMode;
        break;
    case ZSTD_c_blockDelimiters :
        *value = (int)CCtxParams->blockDelimiters;
        break;
    case ZSTD_c_validateSequences :
        *value = (int)CCtxParams->validateSequences;
        break;
    case ZSTD_c_splitAfterSequences :
        *value = (int)CCtxParams->postBlockSplitter;
        break;
    case ZSTD_c_blockSplitterLevel :
        *value = CCtxParams->preBlockSplitter_level;
        break;
    case ZSTD_c_useRowMatchFinder :
        *value = (int)CCtxParams->useRowMatchFinder;
        break;
    case ZSTD_c_deterministicRefPrefix:
        *value = (int)CCtxParams->deterministicRefPrefix;
        break;
    case ZSTD_c_prefetchCDictTables:
        *value = (int)CCtxParams->prefetchCDictTables;
        break;
    case ZSTD_c_enableSeqProducerFallback:
        *value = CCtxParams->enableMatchFinderFallback;
        break;
    case ZSTD_c_maxBlockSize:
        *value = (int)CCtxParams->maxBlockSize;
        break;
    case ZSTD_c_repcodeResolution:
        *value = (int)CCtxParams->searchForExternalRepcodes;
        break;
    default: RETURN_ERROR(parameter_unsupported, "unknown parameter");
    }
    return 0;
}


size_t ZSTD_CCtx_setParametersUsingCCtxParams(
        ZSTD_CCtx* cctx, const ZSTD_CCtx_params* params)
{
    DEBUGLOG(4, "ZSTD_CCtx_setParametersUsingCCtxParams");
    RETURN_ERROR_IF(cctx->streamStage != zcss_init, stage_wrong,
                    "The context is in the wrong stage!");
    RETURN_ERROR_IF(cctx->cdict, stage_wrong,
                    "Can't override parameters with cdict attached (some must "
                    "be inherited from the cdict).");

    cctx->requestedParams = *params;
    return 0;
}

size_t ZSTD_CCtx_setCParams(ZSTD_CCtx* cctx, ZSTD_compressionParameters cparams)
{
    ZSTD_STATIC_ASSERT(sizeof(cparams) == 7 * 4 /* all params are listed below */);
    DEBUGLOG(4, "ZSTD_CCtx_setCParams");

    FORWARD_IF_ERROR(ZSTD_checkCParams(cparams), "");
    FORWARD_IF_ERROR(ZSTD_CCtx_setParameter(cctx, ZSTD_c_windowLog, (int)cparams.windowLog), "");
    FORWARD_IF_ERROR(ZSTD_CCtx_setParameter(cctx, ZSTD_c_chainLog, (int)cparams.chainLog), "");
    FORWARD_IF_ERROR(ZSTD_CCtx_setParameter(cctx, ZSTD_c_hashLog, (int)cparams.hashLog), "");
    FORWARD_IF_ERROR(ZSTD_CCtx_setParameter(cctx, ZSTD_c_searchLog, (int)cparams.searchLog), "");
    FORWARD_IF_ERROR(ZSTD_CCtx_setParameter(cctx, ZSTD_c_minMatch, (int)cparams.minMatch), "");
    FORWARD_IF_ERROR(ZSTD_CCtx_setParameter(cctx, ZSTD_c_targetLength, (int)cparams.targetLength), "");
    FORWARD_IF_ERROR(ZSTD_CCtx_setParameter(cctx, ZSTD_c_strategy, (int)cparams.strategy), "");
    return 0;
}

size_t ZSTD_CCtx_setFParams(ZSTD_CCtx* cctx, ZSTD_frameParameters fparams)
{
    ZSTD_STATIC_ASSERT(sizeof(fparams) == 3 * 4 /* all params are listed below */);
    DEBUGLOG(4, "ZSTD_CCtx_setFParams");
    FORWARD_IF_ERROR(ZSTD_CCtx_setParameter(cctx, ZSTD_c_contentSizeFlag, fparams.contentSizeFlag != 0), "");
    FORWARD_IF_ERROR(ZSTD_CCtx_setParameter(cctx, ZSTD_c_checksumFlag, fparams.checksumFlag != 0), "");
    FORWARD_IF_ERROR(ZSTD_CCtx_setParameter(cctx, ZSTD_c_dictIDFlag, fparams.noDictIDFlag == 0), "");
    return 0;
}

size_t ZSTD_CCtx_setParams(ZSTD_CCtx* cctx, ZSTD_parameters params)
{
    DEBUGLOG(4, "ZSTD_CCtx_setParams");

    FORWARD_IF_ERROR(ZSTD_checkCParams(params.cParams), "");

    FORWARD_IF_ERROR(ZSTD_CCtx_setFParams(cctx, params.fParams), "");

    FORWARD_IF_ERROR(ZSTD_CCtx_setCParams(cctx, params.cParams), "");
    return 0;
}

size_t ZSTD_CCtx_setPledgedSrcSize(ZSTD_CCtx* cctx, unsigned long long pledgedSrcSize)
{
    DEBUGLOG(4, "ZSTD_CCtx_setPledgedSrcSize to %llu bytes", pledgedSrcSize);
    RETURN_ERROR_IF(cctx->streamStage != zcss_init, stage_wrong,
                    "Can't set pledgedSrcSize when not in init stage.");
    cctx->pledgedSrcSizePlusOne = pledgedSrcSize+1;
    return 0;
}

static ZSTD_compressionParameters ZSTD_dedicatedDictSearch_getCParams(
        int const compressionLevel,
        size_t const dictSize);
static int ZSTD_dedicatedDictSearch_isSupported(
        const ZSTD_compressionParameters* cParams);
static void ZSTD_dedicatedDictSearch_revertCParams(
        ZSTD_compressionParameters* cParams);
static size_t ZSTD_createCDict_advanced2_internal(
        ZSTD_CDict** cdictPtr,
        const void* dict, size_t dictSize,
        ZSTD_dictLoadMethod_e dictLoadMethod,
        ZSTD_dictContentType_e dictContentType,
        const ZSTD_CCtx_params* originalCctxParams,
        ZSTD_customMem customMem);


static size_t ZSTD_initLocalDict(ZSTD_CCtx* cctx)
{
    ZSTD_localDict* const dl = &cctx->localDict;
    if (dl->dict == NULL) {

        assert(dl->dictBuffer == NULL);
        assert(dl->cdict == NULL);
        assert(dl->dictSize == 0);
        return 0;
    }
    if (dl->cdict != NULL) {

        assert(cctx->cdict == dl->cdict);
        return 0;
    }
    assert(dl->dictSize > 0);
    assert(cctx->cdict == NULL);
    assert(cctx->prefixDict.dict == NULL);

    FORWARD_IF_ERROR(ZSTD_createCDict_advanced2_internal(
            &dl->cdict,
            dl->dict,
            dl->dictSize,
            ZSTD_dlm_byRef,
            dl->dictContentType,
            &cctx->requestedParams,
            cctx->customMem), "");
    cctx->cdict = dl->cdict;
    return 0;
}

size_t ZSTD_CCtx_loadDictionary_advanced(
        ZSTD_CCtx* cctx,
        const void* dict, size_t dictSize,
        ZSTD_dictLoadMethod_e dictLoadMethod,
        ZSTD_dictContentType_e dictContentType)
{
    DEBUGLOG(4, "ZSTD_CCtx_loadDictionary_advanced (size: %u)", (U32)dictSize);
    RETURN_ERROR_IF(cctx->streamStage != zcss_init, stage_wrong,
                    "Can't load a dictionary when cctx is not in init stage.");
    ZSTD_clearAllDicts(cctx);  /* erase any previously set dictionary */
    if (dict == NULL || dictSize == 0)  /* no dictionary */
        return 0;
    if (dictLoadMethod == ZSTD_dlm_byRef) {
        cctx->localDict.dict = dict;
    } else {

        void* dictBuffer;
        RETURN_ERROR_IF(cctx->staticSize, memory_allocation,
                        "static CCtx can't allocate for an internal copy of dictionary");
        dictBuffer = ZSTD_customMalloc(dictSize, cctx->customMem);
        RETURN_ERROR_IF(dictBuffer==NULL, memory_allocation,
                        "allocation failed for dictionary content");
        ZSTD_memcpy(dictBuffer, dict, dictSize);
        cctx->localDict.dictBuffer = dictBuffer;  /* owned ptr to free */
        cctx->localDict.dict = dictBuffer;        /* read-only reference */
    }
    cctx->localDict.dictSize = dictSize;
    cctx->localDict.dictContentType = dictContentType;
    return 0;
}

size_t ZSTD_CCtx_loadDictionary_byReference(
      ZSTD_CCtx* cctx, const void* dict, size_t dictSize)
{
    return ZSTD_CCtx_loadDictionary_advanced(
            cctx, dict, dictSize, ZSTD_dlm_byRef, ZSTD_dct_auto);
}

size_t ZSTD_CCtx_loadDictionary(ZSTD_CCtx* cctx, const void* dict, size_t dictSize)
{
    return ZSTD_CCtx_loadDictionary_advanced(
            cctx, dict, dictSize, ZSTD_dlm_byCopy, ZSTD_dct_auto);
}


size_t ZSTD_CCtx_refCDict(ZSTD_CCtx* cctx, const ZSTD_CDict* cdict)
{
    RETURN_ERROR_IF(cctx->streamStage != zcss_init, stage_wrong,
                    "Can't ref a dict when ctx not in init stage.");

    ZSTD_clearAllDicts(cctx);
    cctx->cdict = cdict;
    return 0;
}

size_t ZSTD_CCtx_refThreadPool(ZSTD_CCtx* cctx, ZSTD_threadPool* pool)
{
    RETURN_ERROR_IF(cctx->streamStage != zcss_init, stage_wrong,
                    "Can't ref a pool when ctx not in init stage.");
#ifdef ZSTD_MULTITHREAD
    if (pool != cctx->pool) {

        ZSTDMT_freeCCtx(cctx->mtctx); cctx->mtctx = NULL;
    }
#endif
    cctx->pool = pool;
    return 0;
}

size_t ZSTD_CCtx_refPrefix(ZSTD_CCtx* cctx, const void* prefix, size_t prefixSize)
{
    return ZSTD_CCtx_refPrefix_advanced(cctx, prefix, prefixSize, ZSTD_dct_rawContent);
}

size_t ZSTD_CCtx_refPrefix_advanced(
        ZSTD_CCtx* cctx, const void* prefix, size_t prefixSize, ZSTD_dictContentType_e dictContentType)
{
    RETURN_ERROR_IF(cctx->streamStage != zcss_init, stage_wrong,
                    "Can't ref a prefix when ctx not in init stage.");
    ZSTD_clearAllDicts(cctx);
    if (prefix != NULL && prefixSize > 0) {
        cctx->prefixDict.dict = prefix;
        cctx->prefixDict.dictSize = prefixSize;
        cctx->prefixDict.dictContentType = dictContentType;
    }
    return 0;
}


size_t ZSTD_CCtx_reset(ZSTD_CCtx* cctx, ZSTD_ResetDirective reset)
{
    if ( (reset == ZSTD_reset_session_only)
      || (reset == ZSTD_reset_session_and_parameters) ) {
#ifdef ZSTD_MULTITHREAD

        if (cctx->mtctx != NULL) ZSTDMT_waitForPendingJobs(cctx->mtctx);
#endif
        cctx->streamStage = zcss_init;
        cctx->pledgedSrcSizePlusOne = 0;
        cctx->stableIn_notConsumed = 0;  /* input pending in the abandoned frame */
    }
    if ( (reset == ZSTD_reset_parameters)
      || (reset == ZSTD_reset_session_and_parameters) ) {
        RETURN_ERROR_IF(cctx->streamStage != zcss_init, stage_wrong,
                        "Reset parameters is only possible during init stage.");
        ZSTD_clearAllDicts(cctx);
        return ZSTD_CCtxParams_reset(&cctx->requestedParams);
    }
    return 0;
}



size_t ZSTD_checkCParams(ZSTD_compressionParameters cParams)
{
    BOUNDCHECK(ZSTD_c_windowLog, (int)cParams.windowLog);
    BOUNDCHECK(ZSTD_c_chainLog,  (int)cParams.chainLog);
    BOUNDCHECK(ZSTD_c_hashLog,   (int)cParams.hashLog);
    BOUNDCHECK(ZSTD_c_searchLog, (int)cParams.searchLog);
    BOUNDCHECK(ZSTD_c_minMatch,  (int)cParams.minMatch);
    BOUNDCHECK(ZSTD_c_targetLength,(int)cParams.targetLength);
    BOUNDCHECK(ZSTD_c_strategy,  (int)cParams.strategy);
    return 0;
}


static ZSTD_compressionParameters
ZSTD_clampCParams(ZSTD_compressionParameters cParams)
{
#   define CLAMP_TYPE(cParam, val, type)                                      \
        do {                                                                  \
            ZSTD_bounds const bounds = ZSTD_cParam_getBounds(cParam);         \
            if ((int)val<bounds.lowerBound) val=(type)bounds.lowerBound;      \
            else if ((int)val>bounds.upperBound) val=(type)bounds.upperBound; \
        } while (0)
#   define CLAMP(cParam, val) CLAMP_TYPE(cParam, val, unsigned)
    CLAMP(ZSTD_c_windowLog, cParams.windowLog);
    CLAMP(ZSTD_c_chainLog,  cParams.chainLog);
    CLAMP(ZSTD_c_hashLog,   cParams.hashLog);
    CLAMP(ZSTD_c_searchLog, cParams.searchLog);
    CLAMP(ZSTD_c_minMatch,  cParams.minMatch);
    CLAMP(ZSTD_c_targetLength,cParams.targetLength);
    CLAMP_TYPE(ZSTD_c_strategy,cParams.strategy, ZSTD_strategy);
    return cParams;
}


U32 ZSTD_cycleLog(U32 hashLog, ZSTD_strategy strat)
{
    U32 const btScale = ((U32)strat >= (U32)ZSTD_btlazy2);
    return hashLog - btScale;
}


static U32 ZSTD_dictAndWindowLog(U32 windowLog, U64 srcSize, U64 dictSize)
{
    const U64 maxWindowSize = 1ULL << ZSTD_WINDOWLOG_MAX;

    if (dictSize == 0) {
        return windowLog;
    }
    assert(windowLog <= ZSTD_WINDOWLOG_MAX);
    assert(srcSize != ZSTD_CONTENTSIZE_UNKNOWN); /* Handled in ZSTD_adjustCParams_internal() */
    {
        U64 const windowSize = 1ULL << windowLog;
        U64 const dictAndWindowSize = dictSize + windowSize;

        if (windowSize >= dictSize + srcSize) {
            return windowLog; /* Window size large enough already */
        } else if (dictAndWindowSize >= maxWindowSize) {
            return ZSTD_WINDOWLOG_MAX; /* Larger than max window log */
        } else  {
            return ZSTD_highbit32((U32)dictAndWindowSize - 1) + 1;
        }
    }
}


static ZSTD_compressionParameters
ZSTD_adjustCParams_internal(ZSTD_compressionParameters cPar,
                            unsigned long long srcSize,
                            size_t dictSize,
                            ZSTD_CParamMode_e mode,
                            ZSTD_ParamSwitch_e useRowMatchFinder)
{
    const U64 minSrcSize = 513; /* (1<<9) + 1 */
    const U64 maxWindowResize = 1ULL << (ZSTD_WINDOWLOG_MAX-1);
    assert(ZSTD_checkCParams(cPar)==0);


#ifdef ZSTD_EXCLUDE_BTULTRA_BLOCK_COMPRESSOR
    if (cPar.strategy == ZSTD_btultra2) {
        cPar.strategy = ZSTD_btultra;
    }
    if (cPar.strategy == ZSTD_btultra) {
        cPar.strategy = ZSTD_btopt;
    }
#endif
#ifdef ZSTD_EXCLUDE_BTOPT_BLOCK_COMPRESSOR
    if (cPar.strategy == ZSTD_btopt) {
        cPar.strategy = ZSTD_btlazy2;
    }
#endif
#ifdef ZSTD_EXCLUDE_BTLAZY2_BLOCK_COMPRESSOR
    if (cPar.strategy == ZSTD_btlazy2) {
        cPar.strategy = ZSTD_lazy2;
    }
#endif
#ifdef ZSTD_EXCLUDE_LAZY2_BLOCK_COMPRESSOR
    if (cPar.strategy == ZSTD_lazy2) {
        cPar.strategy = ZSTD_lazy;
    }
#endif
#ifdef ZSTD_EXCLUDE_LAZY_BLOCK_COMPRESSOR
    if (cPar.strategy == ZSTD_lazy) {
        cPar.strategy = ZSTD_greedy;
    }
#endif
#ifdef ZSTD_EXCLUDE_GREEDY_BLOCK_COMPRESSOR
    if (cPar.strategy == ZSTD_greedy) {
        cPar.strategy = ZSTD_dfast;
    }
#endif
#ifdef ZSTD_EXCLUDE_DFAST_BLOCK_COMPRESSOR
    if (cPar.strategy == ZSTD_dfast) {
        cPar.strategy = ZSTD_fast;
        cPar.targetLength = 0;
    }
#endif

    switch (mode) {
    case ZSTD_cpm_unknown:
    case ZSTD_cpm_noAttachDict:

        break;
    case ZSTD_cpm_createCDict:

        if (dictSize && srcSize == ZSTD_CONTENTSIZE_UNKNOWN)
            srcSize = minSrcSize;
        break;
    case ZSTD_cpm_attachDict:

        dictSize = 0;
        break;
    default:
        assert(0);
        break;
    }


    if ( (srcSize <= maxWindowResize)
      && (dictSize <= maxWindowResize) )  {
        U32 const tSize = (U32)(srcSize + dictSize);
        static U32 const hashSizeMin = 1 << ZSTD_HASHLOG_MIN;
        U32 const srcLog = (tSize < hashSizeMin) ? ZSTD_HASHLOG_MIN :
                            ZSTD_highbit32(tSize-1) + 1;
        if (cPar.windowLog > srcLog) cPar.windowLog = srcLog;
    }
    if (srcSize != ZSTD_CONTENTSIZE_UNKNOWN) {
        U32 const dictAndWindowLog = ZSTD_dictAndWindowLog(cPar.windowLog, (U64)srcSize, (U64)dictSize);
        U32 const cycleLog = ZSTD_cycleLog(cPar.chainLog, cPar.strategy);
        if (cPar.hashLog > dictAndWindowLog+1) cPar.hashLog = dictAndWindowLog+1;
        if (cycleLog > dictAndWindowLog)
            cPar.chainLog -= (cycleLog - dictAndWindowLog);
    }

    if (cPar.windowLog < ZSTD_WINDOWLOG_ABSOLUTEMIN)
        cPar.windowLog = ZSTD_WINDOWLOG_ABSOLUTEMIN;  /* minimum wlog required for valid frame header */


    if (mode == ZSTD_cpm_createCDict && ZSTD_CDictIndicesAreTagged(&cPar)) {
        U32 const maxShortCacheHashLog = 32 - ZSTD_SHORT_CACHE_TAG_BITS;
        if (cPar.hashLog > maxShortCacheHashLog) {
            cPar.hashLog = maxShortCacheHashLog;
        }
        if (cPar.chainLog > maxShortCacheHashLog) {
            cPar.chainLog = maxShortCacheHashLog;
        }
    }



    if (useRowMatchFinder == ZSTD_ps_auto)
        useRowMatchFinder = ZSTD_ps_enable;


    if (ZSTD_rowMatchFinderUsed(cPar.strategy, useRowMatchFinder)) {

        U32 const rowLog = BOUNDED(4, cPar.searchLog, 6);
        U32 const maxRowHashLog = 32 - ZSTD_ROW_HASH_TAG_BITS;
        U32 const maxHashLog = maxRowHashLog + rowLog;
        assert(cPar.hashLog >= rowLog);
        if (cPar.hashLog > maxHashLog) {
            cPar.hashLog = maxHashLog;
        }
    }

    return cPar;
}

ZSTD_compressionParameters
ZSTD_adjustCParams(ZSTD_compressionParameters cPar,
                   unsigned long long srcSize,
                   size_t dictSize)
{
    cPar = ZSTD_clampCParams(cPar);   /* resulting cPar is necessarily valid (all parameters within range) */
    if (srcSize == 0) srcSize = ZSTD_CONTENTSIZE_UNKNOWN;
    return ZSTD_adjustCParams_internal(cPar, srcSize, dictSize, ZSTD_cpm_unknown, ZSTD_ps_auto);
}

static ZSTD_compressionParameters ZSTD_getCParams_internal(int compressionLevel, unsigned long long srcSizeHint, size_t dictSize, ZSTD_CParamMode_e mode);
static ZSTD_parameters ZSTD_getParams_internal(int compressionLevel, unsigned long long srcSizeHint, size_t dictSize, ZSTD_CParamMode_e mode);

static void ZSTD_overrideCParams(
              ZSTD_compressionParameters* cParams,
        const ZSTD_compressionParameters* overrides)
{
    if (overrides->windowLog)    cParams->windowLog    = overrides->windowLog;
    if (overrides->hashLog)      cParams->hashLog      = overrides->hashLog;
    if (overrides->chainLog)     cParams->chainLog     = overrides->chainLog;
    if (overrides->searchLog)    cParams->searchLog    = overrides->searchLog;
    if (overrides->minMatch)     cParams->minMatch     = overrides->minMatch;
    if (overrides->targetLength) cParams->targetLength = overrides->targetLength;
    if (overrides->strategy)     cParams->strategy     = overrides->strategy;
}

ZSTD_compressionParameters ZSTD_getCParamsFromCCtxParams(
        const ZSTD_CCtx_params* CCtxParams, U64 srcSizeHint, size_t dictSize, ZSTD_CParamMode_e mode)
{
    ZSTD_compressionParameters cParams;
    if (srcSizeHint == ZSTD_CONTENTSIZE_UNKNOWN && CCtxParams->srcSizeHint > 0) {
        assert(CCtxParams->srcSizeHint>=0);
        srcSizeHint = (U64)CCtxParams->srcSizeHint;
    }
    cParams = ZSTD_getCParams_internal(CCtxParams->compressionLevel, srcSizeHint, dictSize, mode);
    if (CCtxParams->ldmParams.enableLdm == ZSTD_ps_enable) cParams.windowLog = ZSTD_LDM_DEFAULT_WINDOW_LOG;
    ZSTD_overrideCParams(&cParams, &CCtxParams->cParams);
    assert(!ZSTD_checkCParams(cParams));

    return ZSTD_adjustCParams_internal(cParams, srcSizeHint, dictSize, mode, CCtxParams->useRowMatchFinder);
}

static size_t
ZSTD_sizeof_matchState(const ZSTD_compressionParameters* const cParams,
                       const ZSTD_ParamSwitch_e useRowMatchFinder,
                       const int enableDedicatedDictSearch,
                       const U32 forCCtx)
{

    size_t const chainSize = ZSTD_allocateChainTable(cParams->strategy, useRowMatchFinder, enableDedicatedDictSearch && !forCCtx)
                                ? ((size_t)1 << cParams->chainLog)
                                : 0;
    size_t const hSize = ((size_t)1) << cParams->hashLog;
    U32    const hashLog3 = (forCCtx && cParams->minMatch==3) ? MIN(ZSTD_HASHLOG3_MAX, cParams->windowLog) : 0;
    size_t const h3Size = hashLog3 ? ((size_t)1) << hashLog3 : 0;

    size_t const tableSpace = chainSize * sizeof(U32)
                            + hSize * sizeof(U32)
                            + h3Size * sizeof(U32);
    size_t const optPotentialSpace =
        ZSTD_cwksp_aligned64_alloc_size((MaxML+1) * sizeof(U32))
      + ZSTD_cwksp_aligned64_alloc_size((MaxLL+1) * sizeof(U32))
      + ZSTD_cwksp_aligned64_alloc_size((MaxOff+1) * sizeof(U32))
      + ZSTD_cwksp_aligned64_alloc_size((1<<Litbits) * sizeof(U32))
      + ZSTD_cwksp_aligned64_alloc_size(ZSTD_OPT_SIZE * sizeof(ZSTD_match_t))
      + ZSTD_cwksp_aligned64_alloc_size(ZSTD_OPT_SIZE * sizeof(ZSTD_optimal_t));
    size_t const lazyAdditionalSpace = ZSTD_rowMatchFinderUsed(cParams->strategy, useRowMatchFinder)
                                            ? ZSTD_cwksp_aligned64_alloc_size(hSize)
                                            : 0;
    size_t const optSpace = (forCCtx && (cParams->strategy >= ZSTD_btopt))
                                ? optPotentialSpace
                                : 0;
    size_t const slackSpace = ZSTD_cwksp_slack_space_required();


    ZSTD_STATIC_ASSERT(ZSTD_HASHLOG_MIN >= 4 && ZSTD_WINDOWLOG_MIN >= 4 && ZSTD_CHAINLOG_MIN >= 4);
    assert(useRowMatchFinder != ZSTD_ps_auto);

    DEBUGLOG(4, "chainSize: %u - hSize: %u - h3Size: %u",
                (U32)chainSize, (U32)hSize, (U32)h3Size);
    return tableSpace + optSpace + slackSpace + lazyAdditionalSpace;
}


static size_t ZSTD_maxNbSeq(size_t blockSize, unsigned minMatch, int useSequenceProducer) {
    U32 const divider = (minMatch==3 || useSequenceProducer) ? 3 : 4;
    return blockSize / divider;
}

static size_t ZSTD_estimateCCtxSize_usingCCtxParams_internal(
        const ZSTD_compressionParameters* cParams,
        const ldmParams_t* ldmParams,
        const int isStatic,
        const ZSTD_ParamSwitch_e useRowMatchFinder,
        const size_t buffInSize,
        const size_t buffOutSize,
        const U64 pledgedSrcSize,
        int useSequenceProducer,
        size_t maxBlockSize)
{
    size_t const windowSize = (size_t) BOUNDED(1ULL, 1ULL << cParams->windowLog, pledgedSrcSize);
    size_t const blockSize = MIN(ZSTD_resolveMaxBlockSize(maxBlockSize), windowSize);
    size_t const maxNbSeq = ZSTD_maxNbSeq(blockSize, cParams->minMatch, useSequenceProducer);
    size_t const tokenSpace = ZSTD_cwksp_alloc_size(WILDCOPY_OVERLENGTH + blockSize)
                            + ZSTD_cwksp_aligned64_alloc_size(maxNbSeq * sizeof(SeqDef))
                            + 3 * ZSTD_cwksp_alloc_size(maxNbSeq * sizeof(BYTE));
    size_t const tmpWorkSpace = ZSTD_cwksp_alloc_size(TMP_WORKSPACE_SIZE);
    size_t const blockStateSpace = 2 * ZSTD_cwksp_alloc_size(sizeof(ZSTD_compressedBlockState_t));
    size_t const matchStateSize = ZSTD_sizeof_matchState(cParams, useRowMatchFinder, /* enableDedicatedDictSearch */ 0, /* forCCtx */ 1);

    size_t const ldmSpace = ZSTD_ldm_getTableSize(*ldmParams);
    size_t const maxNbLdmSeq = ZSTD_ldm_getMaxNbSeq(*ldmParams, blockSize);
    size_t const ldmSeqSpace = ldmParams->enableLdm == ZSTD_ps_enable ?
        ZSTD_cwksp_aligned64_alloc_size(maxNbLdmSeq * sizeof(rawSeq)) : 0;


    size_t const bufferSpace = ZSTD_cwksp_alloc_size(buffInSize)
                             + ZSTD_cwksp_alloc_size(buffOutSize);

    size_t const cctxSpace = isStatic ? ZSTD_cwksp_alloc_size(sizeof(ZSTD_CCtx)) : 0;

    size_t const maxNbExternalSeq = ZSTD_sequenceBound(blockSize);
    size_t const externalSeqSpace = useSequenceProducer
        ? ZSTD_cwksp_aligned64_alloc_size(maxNbExternalSeq * sizeof(ZSTD_Sequence))
        : 0;

    size_t const neededSpace =
        cctxSpace +
        tmpWorkSpace +
        blockStateSpace +
        ldmSpace +
        ldmSeqSpace +
        matchStateSize +
        tokenSpace +
        bufferSpace +
        externalSeqSpace;

    DEBUGLOG(5, "estimate workspace : %u", (U32)neededSpace);
    return neededSpace;
}

size_t ZSTD_estimateCCtxSize_usingCCtxParams(const ZSTD_CCtx_params* params)
{
    ZSTD_compressionParameters const cParams =
                ZSTD_getCParamsFromCCtxParams(params, ZSTD_CONTENTSIZE_UNKNOWN, 0, ZSTD_cpm_noAttachDict);
    ldmParams_t ldmParams = params->ldmParams;
    ZSTD_ParamSwitch_e const useRowMatchFinder = ZSTD_resolveRowMatchFinderMode(params->useRowMatchFinder,
                                                                               &cParams);

    RETURN_ERROR_IF(params->nbWorkers > 0, GENERIC, "Estimate CCtx size is supported for single-threaded compression only.");
    if (ldmParams.enableLdm == ZSTD_ps_enable) {
        ZSTD_ldm_adjustParameters(&ldmParams, &cParams);
    }

    return ZSTD_estimateCCtxSize_usingCCtxParams_internal(
        &cParams, &ldmParams, 1, useRowMatchFinder, 0, 0, ZSTD_CONTENTSIZE_UNKNOWN, ZSTD_hasExtSeqProd(params), params->maxBlockSize);
}

size_t ZSTD_estimateCCtxSize_usingCParams(ZSTD_compressionParameters cParams)
{
    ZSTD_CCtx_params initialParams = ZSTD_makeCCtxParamsFromCParams(cParams);
    if (ZSTD_rowMatchFinderSupported(cParams.strategy)) {

        size_t noRowCCtxSize;
        size_t rowCCtxSize;
        initialParams.useRowMatchFinder = ZSTD_ps_disable;
        noRowCCtxSize = ZSTD_estimateCCtxSize_usingCCtxParams(&initialParams);
        initialParams.useRowMatchFinder = ZSTD_ps_enable;
        rowCCtxSize = ZSTD_estimateCCtxSize_usingCCtxParams(&initialParams);
        return MAX(noRowCCtxSize, rowCCtxSize);
    } else {
        return ZSTD_estimateCCtxSize_usingCCtxParams(&initialParams);
    }
}

static size_t ZSTD_estimateCCtxSize_internal(int compressionLevel)
{
    int tier = 0;
    size_t largestSize = 0;
    static const unsigned long long srcSizeTiers[4] = {16 KB, 128 KB, 256 KB, ZSTD_CONTENTSIZE_UNKNOWN};
    for (; tier < 4; ++tier) {

        ZSTD_compressionParameters const cParams = ZSTD_getCParams_internal(compressionLevel, srcSizeTiers[tier], 0, ZSTD_cpm_noAttachDict);
        largestSize = MAX(ZSTD_estimateCCtxSize_usingCParams(cParams), largestSize);
    }
    return largestSize;
}

size_t ZSTD_estimateCCtxSize(int compressionLevel)
{
    int level;
    size_t memBudget = 0;
    for (level=MIN(compressionLevel, 1); level<=compressionLevel; level++) {

        size_t const newMB = ZSTD_estimateCCtxSize_internal(level);
        if (newMB > memBudget) memBudget = newMB;
    }
    return memBudget;
}

size_t ZSTD_estimateCStreamSize_usingCCtxParams(const ZSTD_CCtx_params* params)
{
    RETURN_ERROR_IF(params->nbWorkers > 0, GENERIC, "Estimate CCtx size is supported for single-threaded compression only.");
    {   ZSTD_compressionParameters const cParams =
                ZSTD_getCParamsFromCCtxParams(params, ZSTD_CONTENTSIZE_UNKNOWN, 0, ZSTD_cpm_noAttachDict);
        ldmParams_t ldmParams = params->ldmParams;
        size_t const blockSize = MIN(ZSTD_resolveMaxBlockSize(params->maxBlockSize), (size_t)1 << cParams.windowLog);
        size_t const inBuffSize = (params->inBufferMode == ZSTD_bm_buffered)
                ? ((size_t)1 << cParams.windowLog) + blockSize
                : 0;
        size_t const outBuffSize = (params->outBufferMode == ZSTD_bm_buffered)
                ? ZSTD_compressBound(blockSize) + 1
                : 0;
        ZSTD_ParamSwitch_e const useRowMatchFinder = ZSTD_resolveRowMatchFinderMode(params->useRowMatchFinder, &params->cParams);

        if (ldmParams.enableLdm == ZSTD_ps_enable) {
            ZSTD_ldm_adjustParameters(&ldmParams, &cParams);
        }
        return ZSTD_estimateCCtxSize_usingCCtxParams_internal(
            &cParams, &ldmParams, 1, useRowMatchFinder, inBuffSize, outBuffSize,
            ZSTD_CONTENTSIZE_UNKNOWN, ZSTD_hasExtSeqProd(params), params->maxBlockSize);
    }
}

size_t ZSTD_estimateCStreamSize_usingCParams(ZSTD_compressionParameters cParams)
{
    ZSTD_CCtx_params initialParams = ZSTD_makeCCtxParamsFromCParams(cParams);
    if (ZSTD_rowMatchFinderSupported(cParams.strategy)) {

        size_t noRowCCtxSize;
        size_t rowCCtxSize;
        initialParams.useRowMatchFinder = ZSTD_ps_disable;
        noRowCCtxSize = ZSTD_estimateCStreamSize_usingCCtxParams(&initialParams);
        initialParams.useRowMatchFinder = ZSTD_ps_enable;
        rowCCtxSize = ZSTD_estimateCStreamSize_usingCCtxParams(&initialParams);
        return MAX(noRowCCtxSize, rowCCtxSize);
    } else {
        return ZSTD_estimateCStreamSize_usingCCtxParams(&initialParams);
    }
}

static size_t ZSTD_estimateCStreamSize_internal(int compressionLevel)
{
    ZSTD_compressionParameters const cParams = ZSTD_getCParams_internal(compressionLevel, ZSTD_CONTENTSIZE_UNKNOWN, 0, ZSTD_cpm_noAttachDict);
    return ZSTD_estimateCStreamSize_usingCParams(cParams);
}

size_t ZSTD_estimateCStreamSize(int compressionLevel)
{
    int level;
    size_t memBudget = 0;
    for (level=MIN(compressionLevel, 1); level<=compressionLevel; level++) {
        size_t const newMB = ZSTD_estimateCStreamSize_internal(level);
        if (newMB > memBudget) memBudget = newMB;
    }
    return memBudget;
}


ZSTD_frameProgression ZSTD_getFrameProgression(const ZSTD_CCtx* cctx)
{
#ifdef ZSTD_MULTITHREAD
    if (cctx->appliedParams.nbWorkers > 0) {
        return ZSTDMT_getFrameProgression(cctx->mtctx);
    }
#endif
    {   ZSTD_frameProgression fp;
        size_t const buffered = (cctx->inBuff == NULL) ? 0 :
                                cctx->inBuffPos - cctx->inToCompress;
        if (buffered) assert(cctx->inBuffPos >= cctx->inToCompress);
        assert(buffered <= ZSTD_BLOCKSIZE_MAX);
        fp.ingested = cctx->consumedSrcSize + buffered;
        fp.consumed = cctx->consumedSrcSize;
        fp.produced = cctx->producedCSize;
        fp.flushed  = cctx->producedCSize;   /* simplified; some data might still be left within streaming output buffer */
        fp.currentJobID = 0;
        fp.nbActiveWorkers = 0;
        return fp;
}   }


size_t ZSTD_toFlushNow(ZSTD_CCtx* cctx)
{
#ifdef ZSTD_MULTITHREAD
    if (cctx->appliedParams.nbWorkers > 0) {
        return ZSTDMT_toFlushNow(cctx->mtctx);
    }
#endif
    (void)cctx;
    return 0;   /* over-simplification; could also check if context is currently running in streaming mode, and in which case, report how many bytes are left to be flushed within output buffer */
}

static void ZSTD_assertEqualCParams(ZSTD_compressionParameters cParams1,
                                    ZSTD_compressionParameters cParams2)
{
    (void)cParams1;
    (void)cParams2;
    assert(cParams1.windowLog    == cParams2.windowLog);
    assert(cParams1.chainLog     == cParams2.chainLog);
    assert(cParams1.hashLog      == cParams2.hashLog);
    assert(cParams1.searchLog    == cParams2.searchLog);
    assert(cParams1.minMatch     == cParams2.minMatch);
    assert(cParams1.targetLength == cParams2.targetLength);
    assert(cParams1.strategy     == cParams2.strategy);
}

void ZSTD_reset_compressedBlockState(ZSTD_compressedBlockState_t* bs)
{
    int i;
    for (i = 0; i < ZSTD_REP_NUM; ++i)
        bs->rep[i] = repStartValue[i];
    bs->entropy.huf.repeatMode = HUF_repeat_none;
    bs->entropy.fse.offcode_repeatMode = FSE_repeat_none;
    bs->entropy.fse.matchlength_repeatMode = FSE_repeat_none;
    bs->entropy.fse.litlength_repeatMode = FSE_repeat_none;
}


static void ZSTD_invalidateMatchState(ZSTD_MatchState_t* ms)
{
    ZSTD_window_clear(&ms->window);

    ms->nextToUpdate = ms->window.dictLimit;
    ms->loadedDictEnd = 0;
    ms->opt.litLengthSum = 0;  /* force reset of btopt stats */
    ms->dictMatchState = NULL;
}


typedef enum {
    ZSTDcrp_makeClean,
    ZSTDcrp_leaveDirty
} ZSTD_compResetPolicy_e;


typedef enum {
    ZSTDirp_continue,
    ZSTDirp_reset
} ZSTD_indexResetPolicy_e;

typedef enum {
    ZSTD_resetTarget_CDict,
    ZSTD_resetTarget_CCtx
} ZSTD_resetTarget_e;


static U64 ZSTD_bitmix(U64 val, U64 len) {
    val ^= ZSTD_rotateRight_U64(val, 49) ^ ZSTD_rotateRight_U64(val, 24);
    val *= 0x9FB21C651E98DF25ULL;
    val ^= (val >> 35) + len ;
    val *= 0x9FB21C651E98DF25ULL;
    return val ^ (val >> 28);
}


static void ZSTD_advanceHashSalt(ZSTD_MatchState_t* ms) {
    ms->hashSalt = ZSTD_bitmix(ms->hashSalt, 8) ^ ZSTD_bitmix((U64) ms->hashSaltEntropy, 4);
}

static size_t
ZSTD_reset_matchState(ZSTD_MatchState_t* ms,
                      ZSTD_cwksp* ws,
                const ZSTD_compressionParameters* cParams,
                const ZSTD_ParamSwitch_e useRowMatchFinder,
                const ZSTD_compResetPolicy_e crp,
                const ZSTD_indexResetPolicy_e forceResetIndex,
                const ZSTD_resetTarget_e forWho)
{

    size_t const chainSize = ZSTD_allocateChainTable(cParams->strategy, useRowMatchFinder,
                                                     ms->dedicatedDictSearch && (forWho == ZSTD_resetTarget_CDict))
                                ? ((size_t)1 << cParams->chainLog)
                                : 0;
    size_t const hSize = ((size_t)1) << cParams->hashLog;
    U32    const hashLog3 = ((forWho == ZSTD_resetTarget_CCtx) && cParams->minMatch==3) ? MIN(ZSTD_HASHLOG3_MAX, cParams->windowLog) : 0;
    size_t const h3Size = hashLog3 ? ((size_t)1) << hashLog3 : 0;

    DEBUGLOG(4, "reset indices : %u", forceResetIndex == ZSTDirp_reset);
    assert(useRowMatchFinder != ZSTD_ps_auto);
    if (forceResetIndex == ZSTDirp_reset) {
        ZSTD_window_init(&ms->window);
        ZSTD_cwksp_mark_tables_dirty(ws);
    }

    ms->hashLog3 = hashLog3;
    ms->lazySkipping = 0;

    ZSTD_invalidateMatchState(ms);

    assert(!ZSTD_cwksp_reserve_failed(ws)); /* check that allocation hasn't already failed */

    ZSTD_cwksp_clear_tables(ws);

    DEBUGLOG(5, "reserving table space");

    ms->hashTable = (U32*)ZSTD_cwksp_reserve_table(ws, hSize * sizeof(U32));
    ms->chainTable = (U32*)ZSTD_cwksp_reserve_table(ws, chainSize * sizeof(U32));
    ms->hashTable3 = (U32*)ZSTD_cwksp_reserve_table(ws, h3Size * sizeof(U32));
    RETURN_ERROR_IF(ZSTD_cwksp_reserve_failed(ws), memory_allocation,
                    "failed a workspace allocation in ZSTD_reset_matchState");

    DEBUGLOG(4, "reset table : %u", crp!=ZSTDcrp_leaveDirty);
    if (crp!=ZSTDcrp_leaveDirty) {

        ZSTD_cwksp_clean_tables(ws);
    }

    if (ZSTD_rowMatchFinderUsed(cParams->strategy, useRowMatchFinder)) {

        size_t const tagTableSize = hSize;

        if(forWho == ZSTD_resetTarget_CCtx) {
            ms->tagTable = (BYTE*) ZSTD_cwksp_reserve_aligned_init_once(ws, tagTableSize);
            ZSTD_advanceHashSalt(ms);
        } else {

            ms->tagTable = (BYTE*) ZSTD_cwksp_reserve_aligned64(ws, tagTableSize);
            ZSTD_memset(ms->tagTable, 0, tagTableSize);
            ms->hashSalt = 0;
        }
        {   /* Switch to 32-entry rows if searchLog is 5 (or more) */
            U32 const rowLog = BOUNDED(4, cParams->searchLog, 6);
            assert(cParams->hashLog >= rowLog);
            ms->rowHashLog = cParams->hashLog - rowLog;
        }
    }


    if ((forWho == ZSTD_resetTarget_CCtx) && (cParams->strategy >= ZSTD_btopt)) {
        DEBUGLOG(4, "reserving optimal parser space");
        ms->opt.litFreq = (unsigned*)ZSTD_cwksp_reserve_aligned64(ws, (1<<Litbits) * sizeof(unsigned));
        ms->opt.litLengthFreq = (unsigned*)ZSTD_cwksp_reserve_aligned64(ws, (MaxLL+1) * sizeof(unsigned));
        ms->opt.matchLengthFreq = (unsigned*)ZSTD_cwksp_reserve_aligned64(ws, (MaxML+1) * sizeof(unsigned));
        ms->opt.offCodeFreq = (unsigned*)ZSTD_cwksp_reserve_aligned64(ws, (MaxOff+1) * sizeof(unsigned));
        ms->opt.matchTable = (ZSTD_match_t*)ZSTD_cwksp_reserve_aligned64(ws, ZSTD_OPT_SIZE * sizeof(ZSTD_match_t));
        ms->opt.priceTable = (ZSTD_optimal_t*)ZSTD_cwksp_reserve_aligned64(ws, ZSTD_OPT_SIZE * sizeof(ZSTD_optimal_t));
    }

    ms->cParams = *cParams;

    RETURN_ERROR_IF(ZSTD_cwksp_reserve_failed(ws), memory_allocation,
                    "failed a workspace allocation in ZSTD_reset_matchState");
    return 0;
}


#define ZSTD_INDEXOVERFLOW_MARGIN (16 MB)
static int ZSTD_indexTooCloseToMax(ZSTD_window_t w)
{
    return (size_t)(w.nextSrc - w.base) > (ZSTD_CURRENT_MAX - ZSTD_INDEXOVERFLOW_MARGIN);
}


static int ZSTD_dictTooBig(size_t const loadedDictSize)
{
    return loadedDictSize > ZSTD_CHUNKSIZE_MAX;
}


static size_t ZSTD_resetCCtx_internal(ZSTD_CCtx* zc,
                                      ZSTD_CCtx_params const* params,
                                      U64 const pledgedSrcSize,
                                      size_t const loadedDictSize,
                                      ZSTD_compResetPolicy_e const crp,
                                      ZSTD_buffered_policy_e const zbuff)
{
    ZSTD_cwksp* const ws = &zc->workspace;
    DEBUGLOG(4, "ZSTD_resetCCtx_internal: pledgedSrcSize=%u, wlog=%u, useRowMatchFinder=%d useBlockSplitter=%d",
                (U32)pledgedSrcSize, params->cParams.windowLog, (int)params->useRowMatchFinder, (int)params->postBlockSplitter);
    assert(!ZSTD_isError(ZSTD_checkCParams(params->cParams)));

    zc->isFirstBlock = 1;


    zc->appliedParams = *params;
    params = &zc->appliedParams;

    assert(params->useRowMatchFinder != ZSTD_ps_auto);
    assert(params->postBlockSplitter != ZSTD_ps_auto);
    assert(params->ldmParams.enableLdm != ZSTD_ps_auto);
    assert(params->maxBlockSize != 0);
    if (params->ldmParams.enableLdm == ZSTD_ps_enable) {

        ZSTD_ldm_adjustParameters(&zc->appliedParams.ldmParams, &params->cParams);
        assert(params->ldmParams.hashLog >= params->ldmParams.bucketSizeLog);
        assert(params->ldmParams.hashRateLog < 32);
    }

    {   size_t const windowSize = MAX(1, (size_t)MIN(((U64)1 << params->cParams.windowLog), pledgedSrcSize));
        size_t const blockSize = MIN(params->maxBlockSize, windowSize);
        size_t const maxNbSeq = ZSTD_maxNbSeq(blockSize, params->cParams.minMatch, ZSTD_hasExtSeqProd(params));
        size_t const buffOutSize = (zbuff == ZSTDb_buffered && params->outBufferMode == ZSTD_bm_buffered)
                ? ZSTD_compressBound(blockSize) + 1
                : 0;
        size_t const buffInSize = (zbuff == ZSTDb_buffered && params->inBufferMode == ZSTD_bm_buffered)
                ? windowSize + blockSize
                : 0;
        size_t const maxNbLdmSeq = ZSTD_ldm_getMaxNbSeq(params->ldmParams, blockSize);

        int const indexTooClose = ZSTD_indexTooCloseToMax(zc->blockState.matchState.window);
        int const dictTooBig = ZSTD_dictTooBig(loadedDictSize);
        ZSTD_indexResetPolicy_e needsIndexReset =
            (indexTooClose || dictTooBig || !zc->initialized) ? ZSTDirp_reset : ZSTDirp_continue;

        size_t const neededSpace =
            ZSTD_estimateCCtxSize_usingCCtxParams_internal(
                &params->cParams, &params->ldmParams, zc->staticSize != 0, params->useRowMatchFinder,
                buffInSize, buffOutSize, pledgedSrcSize, ZSTD_hasExtSeqProd(params), params->maxBlockSize);

        FORWARD_IF_ERROR(neededSpace, "cctx size estimate failed!");

        if (!zc->staticSize) ZSTD_cwksp_bump_oversized_duration(ws, 0);

        {   /* Check if workspace is large enough, alloc a new one if needed */
            int const workspaceTooSmall = ZSTD_cwksp_sizeof(ws) < neededSpace;
            int const workspaceWasteful = ZSTD_cwksp_check_wasteful(ws, neededSpace);
            int resizeWorkspace = workspaceTooSmall || workspaceWasteful;
            DEBUGLOG(4, "Need %zu B workspace", neededSpace);
            DEBUGLOG(4, "windowSize: %zu - blockSize: %zu", windowSize, blockSize);

            if (resizeWorkspace) {
                DEBUGLOG(4, "Resize workspaceSize from %zuKB to %zuKB",
                            ZSTD_cwksp_sizeof(ws) >> 10,
                            neededSpace >> 10);

                RETURN_ERROR_IF(zc->staticSize, memory_allocation, "static cctx : no resize");

                needsIndexReset = ZSTDirp_reset;

                ZSTD_cwksp_free(ws, zc->customMem);
                FORWARD_IF_ERROR(ZSTD_cwksp_create(ws, neededSpace, zc->customMem), "");

                DEBUGLOG(5, "reserving object space");

                assert(ZSTD_cwksp_check_available(ws, 2 * sizeof(ZSTD_compressedBlockState_t)));
                zc->blockState.prevCBlock = (ZSTD_compressedBlockState_t*) ZSTD_cwksp_reserve_object(ws, sizeof(ZSTD_compressedBlockState_t));
                RETURN_ERROR_IF(zc->blockState.prevCBlock == NULL, memory_allocation, "couldn't allocate prevCBlock");
                zc->blockState.nextCBlock = (ZSTD_compressedBlockState_t*) ZSTD_cwksp_reserve_object(ws, sizeof(ZSTD_compressedBlockState_t));
                RETURN_ERROR_IF(zc->blockState.nextCBlock == NULL, memory_allocation, "couldn't allocate nextCBlock");
                zc->tmpWorkspace = ZSTD_cwksp_reserve_object(ws, TMP_WORKSPACE_SIZE);
                RETURN_ERROR_IF(zc->tmpWorkspace == NULL, memory_allocation, "couldn't allocate tmpWorkspace");
                zc->tmpWkspSize = TMP_WORKSPACE_SIZE;
        }   }

        ZSTD_cwksp_clear(ws);


        zc->blockState.matchState.cParams = params->cParams;
        zc->blockState.matchState.prefetchCDictTables = params->prefetchCDictTables == ZSTD_ps_enable;
        zc->pledgedSrcSizePlusOne = pledgedSrcSize+1;
        zc->consumedSrcSize = 0;
        zc->producedCSize = 0;
        if (pledgedSrcSize == ZSTD_CONTENTSIZE_UNKNOWN)
            zc->appliedParams.fParams.contentSizeFlag = 0;
        DEBUGLOG(4, "pledged content size : %u ; flag : %u",
            (unsigned)pledgedSrcSize, zc->appliedParams.fParams.contentSizeFlag);
        zc->blockSizeMax = blockSize;

        XXH64_reset(&zc->xxhState, 0);
        zc->stage = ZSTDcs_init;
        zc->dictID = 0;
        zc->dictContentSize = 0;

        ZSTD_reset_compressedBlockState(zc->blockState.prevCBlock);

        FORWARD_IF_ERROR(ZSTD_reset_matchState(
                &zc->blockState.matchState,
                ws,
                &params->cParams,
                params->useRowMatchFinder,
                crp,
                needsIndexReset,
                ZSTD_resetTarget_CCtx), "");

        zc->seqStore.sequencesStart = (SeqDef*)ZSTD_cwksp_reserve_aligned64(ws, maxNbSeq * sizeof(SeqDef));


        if (params->ldmParams.enableLdm == ZSTD_ps_enable) {

            size_t const ldmHSize = ((size_t)1) << params->ldmParams.hashLog;
            zc->ldmState.hashTable = (ldmEntry_t*)ZSTD_cwksp_reserve_aligned64(ws, ldmHSize * sizeof(ldmEntry_t));
            ZSTD_memset(zc->ldmState.hashTable, 0, ldmHSize * sizeof(ldmEntry_t));
            zc->ldmSequences = (rawSeq*)ZSTD_cwksp_reserve_aligned64(ws, maxNbLdmSeq * sizeof(rawSeq));
            zc->maxNbLdmSequences = maxNbLdmSeq;

            ZSTD_window_init(&zc->ldmState.window);
            zc->ldmState.loadedDictEnd = 0;
        }


        if (ZSTD_hasExtSeqProd(params)) {
            size_t const maxNbExternalSeq = ZSTD_sequenceBound(blockSize);
            zc->extSeqBufCapacity = maxNbExternalSeq;
            zc->extSeqBuf =
                (ZSTD_Sequence*)ZSTD_cwksp_reserve_aligned64(ws, maxNbExternalSeq * sizeof(ZSTD_Sequence));
        }




        zc->seqStore.litStart = ZSTD_cwksp_reserve_buffer(ws, blockSize + WILDCOPY_OVERLENGTH);
        zc->seqStore.maxNbLit = blockSize;

        zc->bufferedPolicy = zbuff;
        zc->inBuffSize = buffInSize;
        zc->inBuff = (char*)ZSTD_cwksp_reserve_buffer(ws, buffInSize);
        zc->outBuffSize = buffOutSize;
        zc->outBuff = (char*)ZSTD_cwksp_reserve_buffer(ws, buffOutSize);


        if (params->ldmParams.enableLdm == ZSTD_ps_enable) {

            size_t const numBuckets =
                  ((size_t)1) << (params->ldmParams.hashLog -
                                  params->ldmParams.bucketSizeLog);
            zc->ldmState.bucketOffsets = ZSTD_cwksp_reserve_buffer(ws, numBuckets);
            ZSTD_memset(zc->ldmState.bucketOffsets, 0, numBuckets);
        }


        ZSTD_referenceExternalSequences(zc, NULL, 0);
        zc->seqStore.maxNbSeq = maxNbSeq;
        zc->seqStore.llCode = ZSTD_cwksp_reserve_buffer(ws, maxNbSeq * sizeof(BYTE));
        zc->seqStore.mlCode = ZSTD_cwksp_reserve_buffer(ws, maxNbSeq * sizeof(BYTE));
        zc->seqStore.ofCode = ZSTD_cwksp_reserve_buffer(ws, maxNbSeq * sizeof(BYTE));

        DEBUGLOG(3, "wksp: finished allocating, %zd bytes remain available", ZSTD_cwksp_available_space(ws));
        assert(ZSTD_cwksp_estimated_space_within_bounds(ws, neededSpace));

        zc->initialized = 1;

        return 0;
    }
}


void ZSTD_invalidateRepCodes(ZSTD_CCtx* cctx) {
    int i;
    for (i=0; i<ZSTD_REP_NUM; i++) cctx->blockState.prevCBlock->rep[i] = 0;
    assert(!ZSTD_window_hasExtDict(cctx->blockState.matchState.window));
}


static const size_t attachDictSizeCutoffs[ZSTD_STRATEGY_MAX+1] = {
    8 KB,  /* unused */
    8 KB,  /* ZSTD_fast */
    16 KB, /* ZSTD_dfast */
    32 KB, /* ZSTD_greedy */
    32 KB, /* ZSTD_lazy */
    32 KB, /* ZSTD_lazy2 */
    32 KB, /* ZSTD_btlazy2 */
    32 KB, /* ZSTD_btopt */
    8 KB,  /* ZSTD_btultra */
    8 KB   /* ZSTD_btultra2 */
};

static int ZSTD_shouldAttachDict(const ZSTD_CDict* cdict,
                                 const ZSTD_CCtx_params* params,
                                 U64 pledgedSrcSize)
{
    size_t cutoff = attachDictSizeCutoffs[cdict->matchState.cParams.strategy];
    int const dedicatedDictSearch = cdict->matchState.dedicatedDictSearch;
    return dedicatedDictSearch
        || ( ( pledgedSrcSize <= cutoff
            || pledgedSrcSize == ZSTD_CONTENTSIZE_UNKNOWN
            || params->attachDictPref == ZSTD_dictForceAttach )
          && params->attachDictPref != ZSTD_dictForceCopy
          && !params->forceWindow ); /* dictMatchState isn't correctly
                                      * handled in _enforceMaxDist */
}


static size_t ZSTD_checkDictionaryRepCodes(const U32 rep[ZSTD_REP_NUM], size_t dictContentSize)
{
    U32 u;
    for (u = 0; u < ZSTD_REP_NUM; ++u) {
        RETURN_ERROR_IF(rep[u] == 0 || rep[u] > dictContentSize,
                        dictionary_corrupted,
                        "repcode %u exceeds dictionary content (%zu bytes)",
                        rep[u], dictContentSize);
    }
    return 0;
}

static size_t
ZSTD_resetCCtx_byAttachingCDict(ZSTD_CCtx* cctx,
                        const ZSTD_CDict* cdict,
                        ZSTD_CCtx_params params,
                        U64 pledgedSrcSize,
                        ZSTD_buffered_policy_e zbuff)
{
    DEBUGLOG(4, "ZSTD_resetCCtx_byAttachingCDict() pledgedSrcSize=%llu",
                (unsigned long long)pledgedSrcSize);
    {
        ZSTD_compressionParameters adjusted_cdict_cParams = cdict->matchState.cParams;
        unsigned const windowLog = params.cParams.windowLog;
        assert(windowLog != 0);



        if (cdict->matchState.dedicatedDictSearch) {
            ZSTD_dedicatedDictSearch_revertCParams(&adjusted_cdict_cParams);
        }

        params.cParams = ZSTD_adjustCParams_internal(adjusted_cdict_cParams, pledgedSrcSize,
                                                     cdict->dictContentSize, ZSTD_cpm_attachDict,
                                                     params.useRowMatchFinder);
        params.cParams.windowLog = windowLog;
        params.useRowMatchFinder = cdict->useRowMatchFinder;    /* cdict overrides */
        FORWARD_IF_ERROR(ZSTD_resetCCtx_internal(cctx, &params, pledgedSrcSize,
 0,
                                                 ZSTDcrp_makeClean, zbuff), "");
        assert(cctx->appliedParams.cParams.strategy == adjusted_cdict_cParams.strategy);
    }

    {   const U32 cdictEnd = (U32)( cdict->matchState.window.nextSrc
                                  - cdict->matchState.window.base);
        const U32 cdictLen = cdictEnd - cdict->matchState.window.dictLimit;
        if (cdictLen == 0) {

            DEBUGLOG(4, "skipping attaching empty dictionary");
        } else {

            FORWARD_IF_ERROR(ZSTD_checkDictionaryRepCodes(cdict->cBlockState.rep, cdictLen), "");
            DEBUGLOG(4, "attaching dictionary into context");
            cctx->blockState.matchState.dictMatchState = &cdict->matchState;


            if (cctx->blockState.matchState.window.dictLimit < cdictEnd) {
                cctx->blockState.matchState.window.nextSrc =
                    cctx->blockState.matchState.window.base + cdictEnd;
                ZSTD_window_clear(&cctx->blockState.matchState.window);
            }

            cctx->blockState.matchState.loadedDictEnd = cctx->blockState.matchState.window.dictLimit;
    }   }

    cctx->dictID = cdict->dictID;
    cctx->dictContentSize = cdict->dictContentSize;


    ZSTD_memcpy(cctx->blockState.prevCBlock, &cdict->cBlockState, sizeof(cdict->cBlockState));

    return 0;
}

static void ZSTD_copyCDictTableIntoCCtx(U32* dst, U32 const* src, size_t tableSize,
                                        ZSTD_compressionParameters const* cParams) {
    if (ZSTD_CDictIndicesAreTagged(cParams)){

        size_t i;
        for (i = 0; i < tableSize; i++) {
            U32 const taggedIndex = src[i];
            U32 const index = taggedIndex >> ZSTD_SHORT_CACHE_TAG_BITS;
            dst[i] = index;
        }
    } else {
        ZSTD_memcpy(dst, src, tableSize * sizeof(U32));
    }
}

static size_t ZSTD_resetCCtx_byCopyingCDict(ZSTD_CCtx* cctx,
                            const ZSTD_CDict* cdict,
                            ZSTD_CCtx_params params,
                            U64 pledgedSrcSize,
                            ZSTD_buffered_policy_e zbuff)
{
    const ZSTD_compressionParameters *cdict_cParams = &cdict->matchState.cParams;

    assert(!cdict->matchState.dedicatedDictSearch);
    DEBUGLOG(4, "ZSTD_resetCCtx_byCopyingCDict() pledgedSrcSize=%llu",
                (unsigned long long)pledgedSrcSize);

    {   unsigned const windowLog = params.cParams.windowLog;
        assert(windowLog != 0);

        params.cParams = *cdict_cParams;
        params.cParams.windowLog = windowLog;
        params.useRowMatchFinder = cdict->useRowMatchFinder;
        FORWARD_IF_ERROR(ZSTD_resetCCtx_internal(cctx, &params, pledgedSrcSize,
 0,
                                                 ZSTDcrp_leaveDirty, zbuff), "");
        assert(cctx->appliedParams.cParams.strategy == cdict_cParams->strategy);
        assert(cctx->appliedParams.cParams.hashLog == cdict_cParams->hashLog);
        assert(cctx->appliedParams.cParams.chainLog == cdict_cParams->chainLog);
    }

    ZSTD_cwksp_mark_tables_dirty(&cctx->workspace);
    assert(params.useRowMatchFinder != ZSTD_ps_auto);


    {   size_t const chainSize = ZSTD_allocateChainTable(cdict_cParams->strategy, cdict->useRowMatchFinder, 0 /* DDS guaranteed disabled */)
                                                            ? ((size_t)1 << cdict_cParams->chainLog)
                                                            : 0;
        size_t const hSize =  (size_t)1 << cdict_cParams->hashLog;

        ZSTD_copyCDictTableIntoCCtx(cctx->blockState.matchState.hashTable,
                                cdict->matchState.hashTable,
                                hSize, cdict_cParams);


        if (ZSTD_allocateChainTable(cctx->appliedParams.cParams.strategy, cctx->appliedParams.useRowMatchFinder, 0 /* forDDSDict */)) {
            ZSTD_copyCDictTableIntoCCtx(cctx->blockState.matchState.chainTable,
                                    cdict->matchState.chainTable,
                                    chainSize, cdict_cParams);
        }

        if (ZSTD_rowMatchFinderUsed(cdict_cParams->strategy, cdict->useRowMatchFinder)) {
            size_t const tagTableSize = hSize;
            ZSTD_memcpy(cctx->blockState.matchState.tagTable,
                        cdict->matchState.tagTable,
                        tagTableSize);
            cctx->blockState.matchState.hashSalt = cdict->matchState.hashSalt;
        }
    }


    assert(cctx->blockState.matchState.hashLog3 <= 31);
    {   U32 const h3log = cctx->blockState.matchState.hashLog3;
        size_t const h3Size = h3log ? ((size_t)1 << h3log) : 0;
        assert(cdict->matchState.hashLog3 == 0);
        ZSTD_memset(cctx->blockState.matchState.hashTable3, 0, h3Size * sizeof(U32));
    }

    ZSTD_cwksp_mark_tables_clean(&cctx->workspace);


    {   ZSTD_MatchState_t const* srcMatchState = &cdict->matchState;
        ZSTD_MatchState_t* dstMatchState = &cctx->blockState.matchState;
        dstMatchState->window       = srcMatchState->window;
        dstMatchState->nextToUpdate = srcMatchState->nextToUpdate;
        dstMatchState->loadedDictEnd= srcMatchState->loadedDictEnd;
    }

    cctx->dictID = cdict->dictID;
    cctx->dictContentSize = cdict->dictContentSize;


    ZSTD_memcpy(cctx->blockState.prevCBlock, &cdict->cBlockState, sizeof(cdict->cBlockState));

    return 0;
}


static size_t ZSTD_resetCCtx_usingCDict(ZSTD_CCtx* cctx,
                            const ZSTD_CDict* cdict,
                            const ZSTD_CCtx_params* params,
                            U64 pledgedSrcSize,
                            ZSTD_buffered_policy_e zbuff)
{

    DEBUGLOG(4, "ZSTD_resetCCtx_usingCDict (pledgedSrcSize=%u)",
                (unsigned)pledgedSrcSize);

    if (ZSTD_shouldAttachDict(cdict, params, pledgedSrcSize)) {
        return ZSTD_resetCCtx_byAttachingCDict(
            cctx, cdict, *params, pledgedSrcSize, zbuff);
    } else {
        return ZSTD_resetCCtx_byCopyingCDict(
            cctx, cdict, *params, pledgedSrcSize, zbuff);
    }
}

#define ZSTD_ROWSIZE 16

FORCE_INLINE_TEMPLATE void
ZSTD_reduceTable_internal (U32* const table, U32 const size, U32 const reducerValue, int const preserveMark)
{
    int const nbRows = (int)size / ZSTD_ROWSIZE;
    int cellNb = 0;
    int rowNb;

    U32 const reducerThreshold = reducerValue + ZSTD_WINDOW_START_INDEX;
    assert((size & (ZSTD_ROWSIZE-1)) == 0);  /* multiple of ZSTD_ROWSIZE */
    assert(size < (1U<<31));   /* can be cast to int */

#if ZSTD_MEMORY_SANITIZER && !defined (ZSTD_MSAN_DONT_POISON_WORKSPACE)

    __msan_unpoison(table, size * sizeof(U32));
#endif

    for (rowNb=0 ; rowNb < nbRows ; rowNb++) {
        int column;
        for (column=0; column<ZSTD_ROWSIZE; column++) {
            U32 newVal;
            if (preserveMark && table[cellNb] == ZSTD_DUBT_UNSORTED_MARK) {

                newVal = ZSTD_DUBT_UNSORTED_MARK;
            } else if (table[cellNb] < reducerThreshold) {
                newVal = 0;
            } else {
                newVal = table[cellNb] - reducerValue;
            }
            table[cellNb] = newVal;
            cellNb++;
    }   }
}

static void ZSTD_reduceTable(U32* const table, U32 const size, U32 const reducerValue)
{
    ZSTD_reduceTable_internal(table, size, reducerValue, 0);
}

static void ZSTD_reduceTable_btlazy2(U32* const table, U32 const size, U32 const reducerValue)
{
    ZSTD_reduceTable_internal(table, size, reducerValue, 1);
}


static void ZSTD_reduceIndex (ZSTD_MatchState_t* ms, ZSTD_CCtx_params const* params, const U32 reducerValue)
{
    {   U32 const hSize = (U32)1 << params->cParams.hashLog;
        ZSTD_reduceTable(ms->hashTable, hSize, reducerValue);
    }

    if (ZSTD_allocateChainTable(params->cParams.strategy, params->useRowMatchFinder, (U32)ms->dedicatedDictSearch)) {
        U32 const chainSize = (U32)1 << params->cParams.chainLog;
        if (params->cParams.strategy == ZSTD_btlazy2)
            ZSTD_reduceTable_btlazy2(ms->chainTable, chainSize, reducerValue);
        else
            ZSTD_reduceTable(ms->chainTable, chainSize, reducerValue);
    }

    if (ms->hashLog3) {
        U32 const h3Size = (U32)1 << ms->hashLog3;
        ZSTD_reduceTable(ms->hashTable3, h3Size, reducerValue);
    }
}






int ZSTD_seqToCodes(const SeqStore_t* seqStorePtr)
{
    const SeqDef* const sequences = seqStorePtr->sequencesStart;
    BYTE* const llCodeTable = seqStorePtr->llCode;
    BYTE* const ofCodeTable = seqStorePtr->ofCode;
    BYTE* const mlCodeTable = seqStorePtr->mlCode;
    U32 const nbSeq = (U32)(seqStorePtr->sequences - seqStorePtr->sequencesStart);
    U32 u;
    int longOffsets = 0;
    assert(nbSeq <= seqStorePtr->maxNbSeq);
    for (u=0; u<nbSeq; u++) {
        U32 const llv = sequences[u].litLength;
        U32 const ofCode = ZSTD_highbit32(sequences[u].offBase);
        U32 const mlv = sequences[u].mlBase;
        llCodeTable[u] = (BYTE)ZSTD_LLcode(llv);
        ofCodeTable[u] = (BYTE)ofCode;
        mlCodeTable[u] = (BYTE)ZSTD_MLcode(mlv);
        assert(!(MEM_64bits() && ofCode >= STREAM_ACCUMULATOR_MIN));
        if (MEM_32bits() && ofCode >= STREAM_ACCUMULATOR_MIN)
            longOffsets = 1;
    }
    if (seqStorePtr->longLengthType==ZSTD_llt_literalLength)
        llCodeTable[seqStorePtr->longLengthPos] = MaxLL;
    if (seqStorePtr->longLengthType==ZSTD_llt_matchLength)
        mlCodeTable[seqStorePtr->longLengthPos] = MaxML;
    return longOffsets;
}


static int ZSTD_useTargetCBlockSize(const ZSTD_CCtx_params* cctxParams)
{
    DEBUGLOG(5, "ZSTD_useTargetCBlockSize (targetCBlockSize=%zu)", cctxParams->targetCBlockSize);
    return (cctxParams->targetCBlockSize != 0);
}


static int ZSTD_blockSplitterEnabled(ZSTD_CCtx_params* cctxParams)
{
    DEBUGLOG(5, "ZSTD_blockSplitterEnabled (postBlockSplitter=%d)", cctxParams->postBlockSplitter);
    assert(cctxParams->postBlockSplitter != ZSTD_ps_auto);
    return (cctxParams->postBlockSplitter == ZSTD_ps_enable);
}


typedef struct {
    U32 LLtype;
    U32 Offtype;
    U32 MLtype;
    size_t size;
    size_t lastCountSize; /* Accounts for bug in 1.3.4. More detail in ZSTD_entropyCompressSeqStore_internal() */
    int longOffsets;
} ZSTD_symbolEncodingTypeStats_t;


static ZSTD_symbolEncodingTypeStats_t
ZSTD_buildSequencesStatistics(
                const SeqStore_t* seqStorePtr, size_t nbSeq,
                const ZSTD_fseCTables_t* prevEntropy, ZSTD_fseCTables_t* nextEntropy,
                      BYTE* dst, const BYTE* const dstEnd,
                      ZSTD_strategy strategy, unsigned* countWorkspace,
                      void* entropyWorkspace, size_t entropyWkspSize)
{
    BYTE* const ostart = dst;
    const BYTE* const oend = dstEnd;
    BYTE* op = ostart;
    FSE_CTable* CTable_LitLength = nextEntropy->litlengthCTable;
    FSE_CTable* CTable_OffsetBits = nextEntropy->offcodeCTable;
    FSE_CTable* CTable_MatchLength = nextEntropy->matchlengthCTable;
    const BYTE* const ofCodeTable = seqStorePtr->ofCode;
    const BYTE* const llCodeTable = seqStorePtr->llCode;
    const BYTE* const mlCodeTable = seqStorePtr->mlCode;
    ZSTD_symbolEncodingTypeStats_t stats;

    stats.lastCountSize = 0;

    stats.longOffsets = ZSTD_seqToCodes(seqStorePtr);
    assert(op <= oend);
    assert(nbSeq != 0); /* ZSTD_selectEncodingType() divides by nbSeq */

    {   unsigned max = MaxLL;
        size_t const mostFrequent = HIST_countFast_wksp(countWorkspace, &max, llCodeTable, nbSeq, entropyWorkspace, entropyWkspSize);   /* can't fail */
        DEBUGLOG(5, "Building LL table");
        nextEntropy->litlength_repeatMode = prevEntropy->litlength_repeatMode;
        stats.LLtype = ZSTD_selectEncodingType(&nextEntropy->litlength_repeatMode,
                                        countWorkspace, max, mostFrequent, nbSeq,
                                        LLFSELog, prevEntropy->litlengthCTable,
                                        LL_defaultNorm, LL_defaultNormLog,
                                        ZSTD_defaultAllowed, strategy);
        assert(set_basic < set_compressed && set_rle < set_compressed);
        assert(!(stats.LLtype < set_compressed && nextEntropy->litlength_repeatMode != FSE_repeat_none)); /* We don't copy tables */
        {   size_t const countSize = ZSTD_buildCTable(
                op, (size_t)(oend - op),
                CTable_LitLength, LLFSELog, (SymbolEncodingType_e)stats.LLtype,
                countWorkspace, max, llCodeTable, nbSeq,
                LL_defaultNorm, LL_defaultNormLog, MaxLL,
                prevEntropy->litlengthCTable,
                sizeof(prevEntropy->litlengthCTable),
                entropyWorkspace, entropyWkspSize);
            if (ZSTD_isError(countSize)) {
                DEBUGLOG(3, "ZSTD_buildCTable for LitLens failed");
                stats.size = countSize;
                return stats;
            }
            if (stats.LLtype == set_compressed)
                stats.lastCountSize = countSize;
            op += countSize;
            assert(op <= oend);
    }   }

    {   unsigned max = MaxOff;
        size_t const mostFrequent = HIST_countFast_wksp(
            countWorkspace, &max, ofCodeTable, nbSeq, entropyWorkspace, entropyWkspSize);  /* can't fail */

        ZSTD_DefaultPolicy_e const defaultPolicy = (max <= DefaultMaxOff) ? ZSTD_defaultAllowed : ZSTD_defaultDisallowed;
        DEBUGLOG(5, "Building OF table");
        nextEntropy->offcode_repeatMode = prevEntropy->offcode_repeatMode;
        stats.Offtype = ZSTD_selectEncodingType(&nextEntropy->offcode_repeatMode,
                                        countWorkspace, max, mostFrequent, nbSeq,
                                        OffFSELog, prevEntropy->offcodeCTable,
                                        OF_defaultNorm, OF_defaultNormLog,
                                        defaultPolicy, strategy);
        assert(!(stats.Offtype < set_compressed && nextEntropy->offcode_repeatMode != FSE_repeat_none)); /* We don't copy tables */
        {   size_t const countSize = ZSTD_buildCTable(
                op, (size_t)(oend - op),
                CTable_OffsetBits, OffFSELog, (SymbolEncodingType_e)stats.Offtype,
                countWorkspace, max, ofCodeTable, nbSeq,
                OF_defaultNorm, OF_defaultNormLog, DefaultMaxOff,
                prevEntropy->offcodeCTable,
                sizeof(prevEntropy->offcodeCTable),
                entropyWorkspace, entropyWkspSize);
            if (ZSTD_isError(countSize)) {
                DEBUGLOG(3, "ZSTD_buildCTable for Offsets failed");
                stats.size = countSize;
                return stats;
            }
            if (stats.Offtype == set_compressed)
                stats.lastCountSize = countSize;
            op += countSize;
            assert(op <= oend);
    }   }

    {   unsigned max = MaxML;
        size_t const mostFrequent = HIST_countFast_wksp(
            countWorkspace, &max, mlCodeTable, nbSeq, entropyWorkspace, entropyWkspSize);   /* can't fail */
        DEBUGLOG(5, "Building ML table (remaining space : %i)", (int)(oend-op));
        nextEntropy->matchlength_repeatMode = prevEntropy->matchlength_repeatMode;
        stats.MLtype = ZSTD_selectEncodingType(&nextEntropy->matchlength_repeatMode,
                                        countWorkspace, max, mostFrequent, nbSeq,
                                        MLFSELog, prevEntropy->matchlengthCTable,
                                        ML_defaultNorm, ML_defaultNormLog,
                                        ZSTD_defaultAllowed, strategy);
        assert(!(stats.MLtype < set_compressed && nextEntropy->matchlength_repeatMode != FSE_repeat_none)); /* We don't copy tables */
        {   size_t const countSize = ZSTD_buildCTable(
                op, (size_t)(oend - op),
                CTable_MatchLength, MLFSELog, (SymbolEncodingType_e)stats.MLtype,
                countWorkspace, max, mlCodeTable, nbSeq,
                ML_defaultNorm, ML_defaultNormLog, MaxML,
                prevEntropy->matchlengthCTable,
                sizeof(prevEntropy->matchlengthCTable),
                entropyWorkspace, entropyWkspSize);
            if (ZSTD_isError(countSize)) {
                DEBUGLOG(3, "ZSTD_buildCTable for MatchLengths failed");
                stats.size = countSize;
                return stats;
            }
            if (stats.MLtype == set_compressed)
                stats.lastCountSize = countSize;
            op += countSize;
            assert(op <= oend);
    }   }
    stats.size = (size_t)(op-ostart);
    return stats;
}


#define SUSPECT_UNCOMPRESSIBLE_LITERAL_RATIO 20
MEM_STATIC size_t
ZSTD_entropyCompressSeqStore_internal(
                              void* dst, size_t dstCapacity,
                        const void* literals, size_t litSize,
                        const SeqStore_t* seqStorePtr,
                        const ZSTD_entropyCTables_t* prevEntropy,
                              ZSTD_entropyCTables_t* nextEntropy,
                        const ZSTD_CCtx_params* cctxParams,
                              void* entropyWorkspace, size_t entropyWkspSize,
                        const int bmi2)
{
    ZSTD_strategy const strategy = cctxParams->cParams.strategy;
    unsigned* count = (unsigned*)entropyWorkspace;
    FSE_CTable* CTable_LitLength = nextEntropy->fse.litlengthCTable;
    FSE_CTable* CTable_OffsetBits = nextEntropy->fse.offcodeCTable;
    FSE_CTable* CTable_MatchLength = nextEntropy->fse.matchlengthCTable;
    const SeqDef* const sequences = seqStorePtr->sequencesStart;
    const size_t nbSeq = (size_t)(seqStorePtr->sequences - seqStorePtr->sequencesStart);
    const BYTE* const ofCodeTable = seqStorePtr->ofCode;
    const BYTE* const llCodeTable = seqStorePtr->llCode;
    const BYTE* const mlCodeTable = seqStorePtr->mlCode;
    BYTE* const ostart = (BYTE*)dst;
    BYTE* const oend = ostart + dstCapacity;
    BYTE* op = ostart;
    size_t lastCountSize;
    int longOffsets = 0;

    entropyWorkspace = count + (MaxSeq + 1);
    entropyWkspSize -= (MaxSeq + 1) * sizeof(*count);

    DEBUGLOG(5, "ZSTD_entropyCompressSeqStore_internal (nbSeq=%zu, dstCapacity=%zu)", nbSeq, dstCapacity);
    ZSTD_STATIC_ASSERT(HUF_WORKSPACE_SIZE >= (1<<MAX(MLFSELog,LLFSELog)));
    assert(entropyWkspSize >= HUF_WORKSPACE_SIZE);


    {   size_t const numSequences = (size_t)(seqStorePtr->sequences - seqStorePtr->sequencesStart);

        int const suspectUncompressible = (numSequences == 0) || (litSize / numSequences >= SUSPECT_UNCOMPRESSIBLE_LITERAL_RATIO);

        size_t const cSize = ZSTD_compressLiterals(
                                    op, dstCapacity,
                                    literals, litSize,
                                    entropyWorkspace, entropyWkspSize,
                                    &prevEntropy->huf, &nextEntropy->huf,
                                    cctxParams->cParams.strategy,
                                    ZSTD_literalsCompressionIsDisabled(cctxParams),
                                    suspectUncompressible, bmi2);
        FORWARD_IF_ERROR(cSize, "ZSTD_compressLiterals failed");
        assert(cSize <= dstCapacity);
        op += cSize;
    }


    RETURN_ERROR_IF((oend-op) < 3 /*max nbSeq Size*/ + 1 /*seqHead*/,
                    dstSize_tooSmall, "Can't fit seq hdr in output buf!");
    if (nbSeq < 128) {
        *op++ = (BYTE)nbSeq;
    } else if (nbSeq < LONGNBSEQ) {
        op[0] = (BYTE)((nbSeq>>8) + 0x80);
        op[1] = (BYTE)nbSeq;
        op+=2;
    } else {
        op[0]=0xFF;
        MEM_writeLE16(op+1, (U16)(nbSeq - LONGNBSEQ));
        op+=3;
    }
    assert(op <= oend);
    if (nbSeq==0) {

        ZSTD_memcpy(&nextEntropy->fse, &prevEntropy->fse, sizeof(prevEntropy->fse));
        return (size_t)(op - ostart);
    }
    {   BYTE* const seqHead = op++;

        const ZSTD_symbolEncodingTypeStats_t stats =
                ZSTD_buildSequencesStatistics(seqStorePtr, nbSeq,
                                             &prevEntropy->fse, &nextEntropy->fse,
                                              op, oend,
                                              strategy, count,
                                              entropyWorkspace, entropyWkspSize);
        FORWARD_IF_ERROR(stats.size, "ZSTD_buildSequencesStatistics failed!");
        *seqHead = (BYTE)((stats.LLtype<<6) + (stats.Offtype<<4) + (stats.MLtype<<2));
        lastCountSize = stats.lastCountSize;
        op += stats.size;
        longOffsets = stats.longOffsets;
    }

    {   size_t const bitstreamSize = ZSTD_encodeSequences(
                                        op, (size_t)(oend - op),
                                        CTable_MatchLength, mlCodeTable,
                                        CTable_OffsetBits, ofCodeTable,
                                        CTable_LitLength, llCodeTable,
                                        sequences, nbSeq,
                                        longOffsets, bmi2);
        FORWARD_IF_ERROR(bitstreamSize, "ZSTD_encodeSequences failed");
        op += bitstreamSize;
        assert(op <= oend);

        if (lastCountSize && (lastCountSize + bitstreamSize) < 4) {

            assert(lastCountSize + bitstreamSize == 3);
            DEBUGLOG(5, "Avoiding bug in zstd decoder in versions <= 1.3.4 by "
                        "emitting an uncompressed block.");
            return 0;
        }
    }

    DEBUGLOG(5, "compressed block size : %u", (unsigned)(op - ostart));
    return (size_t)(op - ostart);
}

static size_t
ZSTD_entropyCompressSeqStore_wExtLitBuffer(
                          void* dst, size_t dstCapacity,
                    const void* literals, size_t litSize,
                          size_t blockSize,
                    const SeqStore_t* seqStorePtr,
                    const ZSTD_entropyCTables_t* prevEntropy,
                          ZSTD_entropyCTables_t* nextEntropy,
                    const ZSTD_CCtx_params* cctxParams,
                          void* entropyWorkspace, size_t entropyWkspSize,
                          int bmi2)
{
    size_t const cSize = ZSTD_entropyCompressSeqStore_internal(
                            dst, dstCapacity,
                            literals, litSize,
                            seqStorePtr, prevEntropy, nextEntropy, cctxParams,
                            entropyWorkspace, entropyWkspSize, bmi2);
    if (cSize == 0) return 0;

    if ((cSize == ERROR(dstSize_tooSmall)) & (blockSize <= dstCapacity)) {
        DEBUGLOG(4, "not enough dstCapacity (%zu) for ZSTD_entropyCompressSeqStore_internal()=> do not compress block", dstCapacity);
        return 0;  /* block not compressed */
    }
    FORWARD_IF_ERROR(cSize, "ZSTD_entropyCompressSeqStore_internal failed");


    {   size_t const maxCSize = blockSize - ZSTD_minGain(blockSize, cctxParams->cParams.strategy);
        if (cSize >= maxCSize) return 0;  /* block not compressed */
    }
    DEBUGLOG(5, "ZSTD_entropyCompressSeqStore() cSize: %zu", cSize);

    assert(cSize < ZSTD_BLOCKSIZE_MAX);
    return cSize;
}

static size_t
ZSTD_entropyCompressSeqStore(
                    const SeqStore_t* seqStorePtr,
                    const ZSTD_entropyCTables_t* prevEntropy,
                          ZSTD_entropyCTables_t* nextEntropy,
                    const ZSTD_CCtx_params* cctxParams,
                          void* dst, size_t dstCapacity,
                          size_t srcSize,
                          void* entropyWorkspace, size_t entropyWkspSize,
                          int bmi2)
{
    return ZSTD_entropyCompressSeqStore_wExtLitBuffer(
                dst, dstCapacity,
                seqStorePtr->litStart, (size_t)(seqStorePtr->lit - seqStorePtr->litStart),
                srcSize,
                seqStorePtr,
                prevEntropy, nextEntropy,
                cctxParams,
                entropyWorkspace, entropyWkspSize,
                bmi2);
}


ZSTD_BlockCompressor_f ZSTD_selectBlockCompressor(ZSTD_strategy strat, ZSTD_ParamSwitch_e useRowMatchFinder, ZSTD_dictMode_e dictMode)
{
    static const ZSTD_BlockCompressor_f blockCompressor[4][ZSTD_STRATEGY_MAX+1] = {
        { ZSTD_compressBlock_fast  /* default for 0 */,
          ZSTD_compressBlock_fast,
          ZSTD_COMPRESSBLOCK_DOUBLEFAST,
          ZSTD_COMPRESSBLOCK_GREEDY,
          ZSTD_COMPRESSBLOCK_LAZY,
          ZSTD_COMPRESSBLOCK_LAZY2,
          ZSTD_COMPRESSBLOCK_BTLAZY2,
          ZSTD_COMPRESSBLOCK_BTOPT,
          ZSTD_COMPRESSBLOCK_BTULTRA,
          ZSTD_COMPRESSBLOCK_BTULTRA2
        },
        { ZSTD_compressBlock_fast_extDict  /* default for 0 */,
          ZSTD_compressBlock_fast_extDict,
          ZSTD_COMPRESSBLOCK_DOUBLEFAST_EXTDICT,
          ZSTD_COMPRESSBLOCK_GREEDY_EXTDICT,
          ZSTD_COMPRESSBLOCK_LAZY_EXTDICT,
          ZSTD_COMPRESSBLOCK_LAZY2_EXTDICT,
          ZSTD_COMPRESSBLOCK_BTLAZY2_EXTDICT,
          ZSTD_COMPRESSBLOCK_BTOPT_EXTDICT,
          ZSTD_COMPRESSBLOCK_BTULTRA_EXTDICT,
          ZSTD_COMPRESSBLOCK_BTULTRA_EXTDICT
        },
        { ZSTD_compressBlock_fast_dictMatchState  /* default for 0 */,
          ZSTD_compressBlock_fast_dictMatchState,
          ZSTD_COMPRESSBLOCK_DOUBLEFAST_DICTMATCHSTATE,
          ZSTD_COMPRESSBLOCK_GREEDY_DICTMATCHSTATE,
          ZSTD_COMPRESSBLOCK_LAZY_DICTMATCHSTATE,
          ZSTD_COMPRESSBLOCK_LAZY2_DICTMATCHSTATE,
          ZSTD_COMPRESSBLOCK_BTLAZY2_DICTMATCHSTATE,
          ZSTD_COMPRESSBLOCK_BTOPT_DICTMATCHSTATE,
          ZSTD_COMPRESSBLOCK_BTULTRA_DICTMATCHSTATE,
          ZSTD_COMPRESSBLOCK_BTULTRA_DICTMATCHSTATE
        },
        { NULL  /* default for 0 */,
          NULL,
          NULL,
          ZSTD_COMPRESSBLOCK_GREEDY_DEDICATEDDICTSEARCH,
          ZSTD_COMPRESSBLOCK_LAZY_DEDICATEDDICTSEARCH,
          ZSTD_COMPRESSBLOCK_LAZY2_DEDICATEDDICTSEARCH,
          NULL,
          NULL,
          NULL,
          NULL }
    };
    ZSTD_BlockCompressor_f selectedCompressor;
    ZSTD_STATIC_ASSERT((unsigned)ZSTD_fast == 1);

    assert(ZSTD_cParam_withinBounds(ZSTD_c_strategy, (int)strat));
    DEBUGLOG(5, "Selected block compressor: dictMode=%d strat=%d rowMatchfinder=%d", (int)dictMode, (int)strat, (int)useRowMatchFinder);
    if (ZSTD_rowMatchFinderUsed(strat, useRowMatchFinder)) {
        static const ZSTD_BlockCompressor_f rowBasedBlockCompressors[4][3] = {
            {
                ZSTD_COMPRESSBLOCK_GREEDY_ROW,
                ZSTD_COMPRESSBLOCK_LAZY_ROW,
                ZSTD_COMPRESSBLOCK_LAZY2_ROW
            },
            {
                ZSTD_COMPRESSBLOCK_GREEDY_EXTDICT_ROW,
                ZSTD_COMPRESSBLOCK_LAZY_EXTDICT_ROW,
                ZSTD_COMPRESSBLOCK_LAZY2_EXTDICT_ROW
            },
            {
                ZSTD_COMPRESSBLOCK_GREEDY_DICTMATCHSTATE_ROW,
                ZSTD_COMPRESSBLOCK_LAZY_DICTMATCHSTATE_ROW,
                ZSTD_COMPRESSBLOCK_LAZY2_DICTMATCHSTATE_ROW
            },
            {
                ZSTD_COMPRESSBLOCK_GREEDY_DEDICATEDDICTSEARCH_ROW,
                ZSTD_COMPRESSBLOCK_LAZY_DEDICATEDDICTSEARCH_ROW,
                ZSTD_COMPRESSBLOCK_LAZY2_DEDICATEDDICTSEARCH_ROW
            }
        };
        DEBUGLOG(5, "Selecting a row-based matchfinder");
        assert(useRowMatchFinder != ZSTD_ps_auto);
        selectedCompressor = rowBasedBlockCompressors[(int)dictMode][(int)strat - (int)ZSTD_greedy];
    } else {
        selectedCompressor = blockCompressor[(int)dictMode][(int)strat];
    }
    assert(selectedCompressor != NULL);
    return selectedCompressor;
}

static void ZSTD_storeLastLiterals(SeqStore_t* seqStorePtr,
                                   const BYTE* anchor, size_t lastLLSize)
{
    ZSTD_memcpy(seqStorePtr->lit, anchor, lastLLSize);
    seqStorePtr->lit += lastLLSize;
}

void ZSTD_resetSeqStore(SeqStore_t* ssPtr)
{
    ssPtr->lit = ssPtr->litStart;
    ssPtr->sequences = ssPtr->sequencesStart;
    ssPtr->longLengthType = ZSTD_llt_none;
}


static size_t ZSTD_postProcessSequenceProducerResult(
    ZSTD_Sequence* outSeqs, size_t nbExternalSeqs, size_t outSeqsCapacity, size_t srcSize
) {
    RETURN_ERROR_IF(
        nbExternalSeqs > outSeqsCapacity,
        sequenceProducer_failed,
        "External sequence producer returned error code %lu",
        (unsigned long)nbExternalSeqs
    );

    RETURN_ERROR_IF(
        nbExternalSeqs == 0 && srcSize > 0,
        sequenceProducer_failed,
        "Got zero sequences from external sequence producer for a non-empty src buffer!"
    );

    if (srcSize == 0) {
        ZSTD_memset(&outSeqs[0], 0, sizeof(ZSTD_Sequence));
        return 1;
    }

    {
        ZSTD_Sequence const lastSeq = outSeqs[nbExternalSeqs - 1];


        if (lastSeq.offset == 0 && lastSeq.matchLength == 0) {
            return nbExternalSeqs;
        }


        RETURN_ERROR_IF(
            nbExternalSeqs == outSeqsCapacity,
            sequenceProducer_failed,
            "nbExternalSeqs == outSeqsCapacity but lastSeq is not a block delimiter!"
        );


        ZSTD_memset(&outSeqs[nbExternalSeqs], 0, sizeof(ZSTD_Sequence));
        return nbExternalSeqs + 1;
    }
}


static size_t ZSTD_fastSequenceLengthSum(ZSTD_Sequence const* seqBuf, size_t seqBufSize) {
    size_t matchLenSum, litLenSum, i;
    matchLenSum = 0;
    litLenSum = 0;
    for (i = 0; i < seqBufSize; i++) {
        litLenSum += seqBuf[i].litLength;
        matchLenSum += seqBuf[i].matchLength;
    }
    return litLenSum + matchLenSum;
}


static void ZSTD_validateSeqStore(const SeqStore_t* seqStore, const ZSTD_compressionParameters* cParams)
{
#if DEBUGLEVEL >= 1
    const SeqDef* seq = seqStore->sequencesStart;
    const SeqDef* const seqEnd = seqStore->sequences;
    size_t const matchLenLowerBound = cParams->minMatch == 3 ? 3 : 4;
    for (; seq < seqEnd; ++seq) {
        const ZSTD_SequenceLength seqLength = ZSTD_getSequenceLength(seqStore, seq);
        assert(seqLength.matchLength >= matchLenLowerBound);
        (void)seqLength;
        (void)matchLenLowerBound;
    }
#else
    (void)seqStore;
    (void)cParams;
#endif
}

static size_t
ZSTD_transferSequences_wBlockDelim(ZSTD_CCtx* cctx,
                                   ZSTD_SequencePosition* seqPos,
                             const ZSTD_Sequence* const inSeqs, size_t inSeqsSize,
                             const void* src, size_t blockSize,
                                   ZSTD_ParamSwitch_e externalRepSearch);

typedef enum { ZSTDbss_compress, ZSTDbss_noCompress } ZSTD_BuildSeqStore_e;

static size_t ZSTD_buildSeqStore(ZSTD_CCtx* zc, const void* src, size_t srcSize)
{
    ZSTD_MatchState_t* const ms = &zc->blockState.matchState;
    DEBUGLOG(5, "ZSTD_buildSeqStore (srcSize=%zu)", srcSize);
    assert(srcSize <= ZSTD_BLOCKSIZE_MAX);

    ZSTD_assertEqualCParams(zc->appliedParams.cParams, ms->cParams);

    if (srcSize < MIN_CBLOCK_SIZE+ZSTD_blockHeaderSize+1+1) {
        if (zc->appliedParams.cParams.strategy >= ZSTD_btopt) {
            ZSTD_ldm_skipRawSeqStoreBytes(&zc->externSeqStore, srcSize);
        } else {
            ZSTD_ldm_skipSequences(&zc->externSeqStore, srcSize, zc->appliedParams.cParams.minMatch);
        }
        return ZSTDbss_noCompress; /* don't even attempt compression below a certain srcSize */
    }
    ZSTD_resetSeqStore(&(zc->seqStore));

    ms->opt.symbolCosts = &zc->blockState.prevCBlock->entropy;

    ms->opt.literalCompressionMode = zc->appliedParams.literalCompressionMode;

    assert(ms->dictMatchState == NULL || ms->loadedDictEnd == ms->window.dictLimit);


    {   const BYTE* const base = ms->window.base;
        const BYTE* const istart = (const BYTE*)src;
        const U32 curr = (U32)(istart-base);
        if (sizeof(ptrdiff_t)==8) assert(istart - base < (ptrdiff_t)(U32)(-1));   /* ensure no overflow */
        if (curr > ms->nextToUpdate + 384)
            ms->nextToUpdate = curr - MIN(192, (U32)(curr - ms->nextToUpdate - 384));
    }


    {   ZSTD_dictMode_e const dictMode = ZSTD_matchState_dictMode(ms);
        size_t lastLLSize;
        {   int i;
            for (i = 0; i < ZSTD_REP_NUM; ++i)
                zc->blockState.nextCBlock->rep[i] = zc->blockState.prevCBlock->rep[i];
        }
        if (zc->externSeqStore.pos < zc->externSeqStore.size) {
            assert(zc->appliedParams.ldmParams.enableLdm == ZSTD_ps_disable);


            RETURN_ERROR_IF(
                ZSTD_hasExtSeqProd(&zc->appliedParams),
                parameter_combination_unsupported,
                "Long-distance matching with external sequence producer enabled is not currently supported."
            );


            lastLLSize =
                ZSTD_ldm_blockCompress(&zc->externSeqStore,
                                       ms, &zc->seqStore,
                                       zc->blockState.nextCBlock->rep,
                                       zc->appliedParams.useRowMatchFinder,
                                       src, srcSize);
            assert(zc->externSeqStore.pos <= zc->externSeqStore.size);
        } else if (zc->appliedParams.ldmParams.enableLdm == ZSTD_ps_enable) {
            RawSeqStore_t ldmSeqStore = kNullRawSeqStore;


            RETURN_ERROR_IF(
                ZSTD_hasExtSeqProd(&zc->appliedParams),
                parameter_combination_unsupported,
                "Long-distance matching with external sequence producer enabled is not currently supported."
            );

            ldmSeqStore.seq = zc->ldmSequences;
            ldmSeqStore.capacity = zc->maxNbLdmSequences;

            FORWARD_IF_ERROR(ZSTD_ldm_generateSequences(&zc->ldmState, &ldmSeqStore,
                                               &zc->appliedParams.ldmParams,
                                               src, srcSize), "");

            lastLLSize =
                ZSTD_ldm_blockCompress(&ldmSeqStore,
                                       ms, &zc->seqStore,
                                       zc->blockState.nextCBlock->rep,
                                       zc->appliedParams.useRowMatchFinder,
                                       src, srcSize);
            assert(ldmSeqStore.pos == ldmSeqStore.size);
        } else if (ZSTD_hasExtSeqProd(&zc->appliedParams)) {
            assert(
                zc->extSeqBufCapacity >= ZSTD_sequenceBound(srcSize)
            );
            assert(zc->appliedParams.extSeqProdFunc != NULL);

            {   U32 const windowSize = (U32)1 << zc->appliedParams.cParams.windowLog;

                size_t const nbExternalSeqs = (zc->appliedParams.extSeqProdFunc)(
                    zc->appliedParams.extSeqProdState,
                    zc->extSeqBuf,
                    zc->extSeqBufCapacity,
                    src, srcSize,
                    NULL, 0,  /* dict and dictSize, currently not supported */
                    zc->appliedParams.compressionLevel,
                    windowSize
                );

                size_t const nbPostProcessedSeqs = ZSTD_postProcessSequenceProducerResult(
                    zc->extSeqBuf,
                    nbExternalSeqs,
                    zc->extSeqBufCapacity,
                    srcSize
                );


                if (!ZSTD_isError(nbPostProcessedSeqs)) {
                    ZSTD_SequencePosition seqPos = {0,0,0};
                    size_t const seqLenSum = ZSTD_fastSequenceLengthSum(zc->extSeqBuf, nbPostProcessedSeqs);
                    RETURN_ERROR_IF(seqLenSum > srcSize, externalSequences_invalid, "External sequences imply too large a block!");
                    FORWARD_IF_ERROR(
                        ZSTD_transferSequences_wBlockDelim(
                            zc, &seqPos,
                            zc->extSeqBuf, nbPostProcessedSeqs,
                            src, srcSize,
                            zc->appliedParams.searchForExternalRepcodes
                        ),
                        "Failed to copy external sequences to seqStore!"
                    );
                    ms->ldmSeqStore = NULL;
                    DEBUGLOG(5, "Copied %lu sequences from external sequence producer to internal seqStore.", (unsigned long)nbExternalSeqs);
                    return ZSTDbss_compress;
                }


                if (!zc->appliedParams.enableMatchFinderFallback) {
                    return nbPostProcessedSeqs;
                }


                {   ZSTD_BlockCompressor_f const blockCompressor =
                        ZSTD_selectBlockCompressor(
                            zc->appliedParams.cParams.strategy,
                            zc->appliedParams.useRowMatchFinder,
                            dictMode);
                    ms->ldmSeqStore = NULL;
                    DEBUGLOG(
                        5,
                        "External sequence producer returned error code %lu. Falling back to internal parser.",
                        (unsigned long)nbExternalSeqs
                    );
                    lastLLSize = blockCompressor(ms, &zc->seqStore, zc->blockState.nextCBlock->rep, src, srcSize);
            }   }
        } else {   /* not long range mode and no external matchfinder */
            ZSTD_BlockCompressor_f const blockCompressor = ZSTD_selectBlockCompressor(
                    zc->appliedParams.cParams.strategy,
                    zc->appliedParams.useRowMatchFinder,
                    dictMode);
            ms->ldmSeqStore = NULL;
            lastLLSize = blockCompressor(ms, &zc->seqStore, zc->blockState.nextCBlock->rep, src, srcSize);
        }
        {   const BYTE* const lastLiterals = (const BYTE*)src + srcSize - lastLLSize;
            ZSTD_storeLastLiterals(&zc->seqStore, lastLiterals, lastLLSize);
    }   }
    ZSTD_validateSeqStore(&zc->seqStore, &zc->appliedParams.cParams);
    return ZSTDbss_compress;
}

static size_t ZSTD_copyBlockSequences(SeqCollector* seqCollector, const SeqStore_t* seqStore, const U32 prevRepcodes[ZSTD_REP_NUM])
{
    const SeqDef* inSeqs = seqStore->sequencesStart;
    const size_t nbInSequences = (size_t)(seqStore->sequences - inSeqs);
    const size_t nbInLiterals = (size_t)(seqStore->lit - seqStore->litStart);

    ZSTD_Sequence* outSeqs = seqCollector->seqIndex == 0 ? seqCollector->seqStart : seqCollector->seqStart + seqCollector->seqIndex;
    const size_t nbOutSequences = nbInSequences + 1;
    size_t nbOutLiterals = 0;
    Repcodes_t repcodes;
    size_t i;


    assert(seqCollector->seqIndex <= seqCollector->maxSequences);
    RETURN_ERROR_IF(
        nbOutSequences > (size_t)(seqCollector->maxSequences - seqCollector->seqIndex),
        dstSize_tooSmall,
        "Not enough space to copy sequences");

    ZSTD_memcpy(&repcodes, prevRepcodes, sizeof(repcodes));
    for (i = 0; i < nbInSequences; ++i) {
        U32 rawOffset;
        outSeqs[i].litLength = inSeqs[i].litLength;
        outSeqs[i].matchLength = inSeqs[i].mlBase + MINMATCH;
        outSeqs[i].rep = 0;


        if (i == seqStore->longLengthPos) {
            if (seqStore->longLengthType == ZSTD_llt_literalLength) {
                outSeqs[i].litLength += 0x10000;
            } else if (seqStore->longLengthType == ZSTD_llt_matchLength) {
                outSeqs[i].matchLength += 0x10000;
            }
        }


        if (OFFBASE_IS_REPCODE(inSeqs[i].offBase)) {
            const U32 repcode = OFFBASE_TO_REPCODE(inSeqs[i].offBase);
            assert(repcode > 0);
            outSeqs[i].rep = repcode;
            if (outSeqs[i].litLength != 0) {
                rawOffset = repcodes.rep[repcode - 1];
            } else {
                if (repcode == 3) {
                    assert(repcodes.rep[0] > 1);
                    rawOffset = repcodes.rep[0] - 1;
                } else {
                    rawOffset = repcodes.rep[repcode];
                }
            }
        } else {
            rawOffset = OFFBASE_TO_OFFSET(inSeqs[i].offBase);
        }
        outSeqs[i].offset = rawOffset;


        ZSTD_updateRep(repcodes.rep,
                       inSeqs[i].offBase,
                       inSeqs[i].litLength == 0);

        nbOutLiterals += outSeqs[i].litLength;
    }

    assert(nbInLiterals >= nbOutLiterals);
    {
        const size_t lastLLSize = nbInLiterals - nbOutLiterals;
        outSeqs[nbInSequences].litLength = (U32)lastLLSize;
        outSeqs[nbInSequences].matchLength = 0;
        outSeqs[nbInSequences].offset = 0;
        assert(nbOutSequences == nbInSequences + 1);
    }
    seqCollector->seqIndex += nbOutSequences;
    assert(seqCollector->seqIndex <= seqCollector->maxSequences);

    return 0;
}

size_t ZSTD_sequenceBound(size_t srcSize) {
    const size_t maxNbSeq = (srcSize / ZSTD_MINMATCH_MIN) + 1;
    const size_t maxNbDelims = (srcSize / ZSTD_BLOCKSIZE_MAX_MIN) + 1;
    return maxNbSeq + maxNbDelims;
}

size_t ZSTD_generateSequences(ZSTD_CCtx* zc, ZSTD_Sequence* outSeqs,
                              size_t outSeqsSize, const void* src, size_t srcSize)
{
    const size_t dstCapacity = ZSTD_compressBound(srcSize);
    void* dst; /* Make C90 happy. */
    SeqCollector seqCollector;
    {
        int targetCBlockSize;
        FORWARD_IF_ERROR(ZSTD_CCtx_getParameter(zc, ZSTD_c_targetCBlockSize, &targetCBlockSize), "");
        RETURN_ERROR_IF(targetCBlockSize != 0, parameter_unsupported, "targetCBlockSize != 0");
    }
    {
        int nbWorkers;
        FORWARD_IF_ERROR(ZSTD_CCtx_getParameter(zc, ZSTD_c_nbWorkers, &nbWorkers), "");
        RETURN_ERROR_IF(nbWorkers != 0, parameter_unsupported, "nbWorkers != 0");
    }

    dst = ZSTD_customMalloc(dstCapacity, ZSTD_defaultCMem);
    RETURN_ERROR_IF(dst == NULL, memory_allocation, "NULL pointer!");

    seqCollector.collectSequences = 1;
    seqCollector.seqStart = outSeqs;
    seqCollector.seqIndex = 0;
    seqCollector.maxSequences = outSeqsSize;
    zc->seqCollector = seqCollector;

    {
        const size_t ret = ZSTD_compress2(zc, dst, dstCapacity, src, srcSize);
        ZSTD_customFree(dst, ZSTD_defaultCMem);
        FORWARD_IF_ERROR(ret, "ZSTD_compress2 failed");
    }
    assert(zc->seqCollector.seqIndex <= ZSTD_sequenceBound(srcSize));
    return zc->seqCollector.seqIndex;
}

size_t ZSTD_mergeBlockDelimiters(ZSTD_Sequence* sequences, size_t seqsSize) {
    size_t in = 0;
    size_t out = 0;
    for (; in < seqsSize; ++in) {
        if (sequences[in].offset == 0 && sequences[in].matchLength == 0) {
            if (in != seqsSize - 1) {
                sequences[in+1].litLength += sequences[in].litLength;
            }
        } else {
            sequences[out] = sequences[in];
            ++out;
        }
    }
    return out;
}


static int ZSTD_isRLE(const BYTE* src, size_t length) {
    const BYTE* ip = src;
    const BYTE value = ip[0];
    const size_t valueST = (size_t)((U64)value * 0x0101010101010101ULL);
    const size_t unrollSize = sizeof(size_t) * 4;
    const size_t unrollMask = unrollSize - 1;
    const size_t prefixLength = length & unrollMask;
    size_t i;
    if (length == 1) return 1;

    if (prefixLength && ZSTD_count(ip+1, ip, ip+prefixLength) != prefixLength-1) {
        return 0;
    }
    for (i = prefixLength; i != length; i += unrollSize) {
        size_t u;
        for (u = 0; u < unrollSize; u += sizeof(size_t)) {
            if (MEM_readST(ip + i + u) != valueST) {
                return 0;
    }   }   }
    return 1;
}


static int ZSTD_maybeRLE(SeqStore_t const* seqStore)
{
    size_t const nbSeqs = (size_t)(seqStore->sequences - seqStore->sequencesStart);
    size_t const nbLits = (size_t)(seqStore->lit - seqStore->litStart);

    return nbSeqs < 4 && nbLits < 10;
}

static void
ZSTD_blockState_confirmRepcodesAndEntropyTables(ZSTD_blockState_t* const bs)
{
    ZSTD_compressedBlockState_t* const tmp = bs->prevCBlock;
    bs->prevCBlock = bs->nextCBlock;
    bs->nextCBlock = tmp;
}


static void
writeBlockHeader(void* op, size_t cSize, size_t blockSize, U32 lastBlock)
{
    U32 const cBlockHeader = cSize == 1 ?
                        lastBlock + (((U32)bt_rle)<<1) + (U32)(blockSize << 3) :
                        lastBlock + (((U32)bt_compressed)<<1) + (U32)(cSize << 3);
    MEM_writeLE24(op, cBlockHeader);
    DEBUGLOG(5, "writeBlockHeader: cSize: %zu blockSize: %zu lastBlock: %u", cSize, blockSize, lastBlock);
}


static size_t
ZSTD_buildBlockEntropyStats_literals(void* const src, size_t srcSize,
                               const ZSTD_hufCTables_t* prevHuf,
                                     ZSTD_hufCTables_t* nextHuf,
                                     ZSTD_hufCTablesMetadata_t* hufMetadata,
                               const int literalsCompressionIsDisabled,
                                     void* workspace, size_t wkspSize,
                                     int hufFlags)
{
    BYTE* const wkspStart = (BYTE*)workspace;
    BYTE* const wkspEnd = wkspStart + wkspSize;
    BYTE* const countWkspStart = wkspStart;
    unsigned* const countWksp = (unsigned*)workspace;
    const size_t countWkspSize = (HUF_SYMBOLVALUE_MAX + 1) * sizeof(unsigned);
    BYTE* const nodeWksp = countWkspStart + countWkspSize;
    const size_t nodeWkspSize = (size_t)(wkspEnd - nodeWksp);
    unsigned maxSymbolValue = HUF_SYMBOLVALUE_MAX;
    unsigned huffLog = LitHufLog;
    HUF_repeat repeat = prevHuf->repeatMode;
    DEBUGLOG(5, "ZSTD_buildBlockEntropyStats_literals (srcSize=%zu)", srcSize);


    ZSTD_memcpy(nextHuf, prevHuf, sizeof(*prevHuf));

    if (literalsCompressionIsDisabled) {
        DEBUGLOG(5, "set_basic - disabled");
        hufMetadata->hType = set_basic;
        return 0;
    }


#ifndef COMPRESS_LITERALS_SIZE_MIN
# define COMPRESS_LITERALS_SIZE_MIN 63  /* heuristic */
#endif
    {   size_t const minLitSize = (prevHuf->repeatMode == HUF_repeat_valid) ? 6 : COMPRESS_LITERALS_SIZE_MIN;
        if (srcSize <= minLitSize) {
            DEBUGLOG(5, "set_basic - too small");
            hufMetadata->hType = set_basic;
            return 0;
    }   }


    {   size_t const largest =
            HIST_count_wksp (countWksp, &maxSymbolValue,
                            (const BYTE*)src, srcSize,
                            workspace, wkspSize);
        FORWARD_IF_ERROR(largest, "HIST_count_wksp failed");
        if (largest == srcSize) {

            DEBUGLOG(5, "set_rle");
            hufMetadata->hType = set_rle;
            return 0;
        }
        if (largest <= (srcSize >> 7)+4) {

            DEBUGLOG(5, "set_basic - no gain");
            hufMetadata->hType = set_basic;
            return 0;
    }   }


    if (repeat == HUF_repeat_check
      && !HUF_validateCTable((HUF_CElt const*)prevHuf->CTable, countWksp, maxSymbolValue)) {
        repeat = HUF_repeat_none;
    }


    ZSTD_memset(nextHuf->CTable, 0, sizeof(nextHuf->CTable));
    huffLog = HUF_optimalTableLog(huffLog, srcSize, maxSymbolValue, nodeWksp, nodeWkspSize, nextHuf->CTable, countWksp, hufFlags);
    assert(huffLog <= LitHufLog);
    {   size_t const maxBits = HUF_buildCTable_wksp((HUF_CElt*)nextHuf->CTable, countWksp,
                                                    maxSymbolValue, huffLog,
                                                    nodeWksp, nodeWkspSize);
        FORWARD_IF_ERROR(maxBits, "HUF_buildCTable_wksp");
        huffLog = (U32)maxBits;
    }
    {   /* Build and write the CTable */
        size_t const newCSize = HUF_estimateCompressedSize(
                (HUF_CElt*)nextHuf->CTable, countWksp, maxSymbolValue);
        size_t const hSize = HUF_writeCTable_wksp(
                hufMetadata->hufDesBuffer, sizeof(hufMetadata->hufDesBuffer),
                (HUF_CElt*)nextHuf->CTable, maxSymbolValue, huffLog,
                nodeWksp, nodeWkspSize);

        if (repeat != HUF_repeat_none) {
            size_t const oldCSize = HUF_estimateCompressedSize(
                    (HUF_CElt const*)prevHuf->CTable, countWksp, maxSymbolValue);
            if (oldCSize < srcSize && (oldCSize <= hSize + newCSize || hSize + 12 >= srcSize)) {
                DEBUGLOG(5, "set_repeat - smaller");
                ZSTD_memcpy(nextHuf, prevHuf, sizeof(*prevHuf));
                hufMetadata->hType = set_repeat;
                return 0;
        }   }
        if (newCSize + hSize >= srcSize) {
            DEBUGLOG(5, "set_basic - no gains");
            ZSTD_memcpy(nextHuf, prevHuf, sizeof(*prevHuf));
            hufMetadata->hType = set_basic;
            return 0;
        }
        DEBUGLOG(5, "set_compressed (hSize=%u)", (U32)hSize);
        hufMetadata->hType = set_compressed;
        nextHuf->repeatMode = HUF_repeat_check;
        return hSize;
    }
}



static ZSTD_symbolEncodingTypeStats_t
ZSTD_buildDummySequencesStatistics(ZSTD_fseCTables_t* nextEntropy)
{
    ZSTD_symbolEncodingTypeStats_t stats = {set_basic, set_basic, set_basic, 0, 0, 0};
    nextEntropy->litlength_repeatMode = FSE_repeat_none;
    nextEntropy->offcode_repeatMode = FSE_repeat_none;
    nextEntropy->matchlength_repeatMode = FSE_repeat_none;
    return stats;
}


static size_t
ZSTD_buildBlockEntropyStats_sequences(
                const SeqStore_t* seqStorePtr,
                const ZSTD_fseCTables_t* prevEntropy,
                      ZSTD_fseCTables_t* nextEntropy,
                const ZSTD_CCtx_params* cctxParams,
                      ZSTD_fseCTablesMetadata_t* fseMetadata,
                      void* workspace, size_t wkspSize)
{
    ZSTD_strategy const strategy = cctxParams->cParams.strategy;
    size_t const nbSeq = (size_t)(seqStorePtr->sequences - seqStorePtr->sequencesStart);
    BYTE* const ostart = fseMetadata->fseTablesBuffer;
    BYTE* const oend = ostart + sizeof(fseMetadata->fseTablesBuffer);
    BYTE* op = ostart;
    unsigned* countWorkspace = (unsigned*)workspace;
    unsigned* entropyWorkspace = countWorkspace + (MaxSeq + 1);
    size_t entropyWorkspaceSize = wkspSize - (MaxSeq + 1) * sizeof(*countWorkspace);
    ZSTD_symbolEncodingTypeStats_t stats;

    DEBUGLOG(5, "ZSTD_buildBlockEntropyStats_sequences (nbSeq=%zu)", nbSeq);
    stats = nbSeq != 0 ? ZSTD_buildSequencesStatistics(seqStorePtr, nbSeq,
                                          prevEntropy, nextEntropy, op, oend,
                                          strategy, countWorkspace,
                                          entropyWorkspace, entropyWorkspaceSize)
                       : ZSTD_buildDummySequencesStatistics(nextEntropy);
    FORWARD_IF_ERROR(stats.size, "ZSTD_buildSequencesStatistics failed!");
    fseMetadata->llType = (SymbolEncodingType_e) stats.LLtype;
    fseMetadata->ofType = (SymbolEncodingType_e) stats.Offtype;
    fseMetadata->mlType = (SymbolEncodingType_e) stats.MLtype;
    fseMetadata->lastCountSize = stats.lastCountSize;
    return stats.size;
}



size_t ZSTD_buildBlockEntropyStats(
            const SeqStore_t* seqStorePtr,
            const ZSTD_entropyCTables_t* prevEntropy,
                  ZSTD_entropyCTables_t* nextEntropy,
            const ZSTD_CCtx_params* cctxParams,
                  ZSTD_entropyCTablesMetadata_t* entropyMetadata,
                  void* workspace, size_t wkspSize)
{
    size_t const litSize = (size_t)(seqStorePtr->lit - seqStorePtr->litStart);
    int const huf_useOptDepth = (cctxParams->cParams.strategy >= HUF_OPTIMAL_DEPTH_THRESHOLD);
    int const hufFlags = huf_useOptDepth ? HUF_flags_optimalDepth : 0;

    entropyMetadata->hufMetadata.hufDesSize =
        ZSTD_buildBlockEntropyStats_literals(seqStorePtr->litStart, litSize,
                                            &prevEntropy->huf, &nextEntropy->huf,
                                            &entropyMetadata->hufMetadata,
                                            ZSTD_literalsCompressionIsDisabled(cctxParams),
                                            workspace, wkspSize, hufFlags);

    FORWARD_IF_ERROR(entropyMetadata->hufMetadata.hufDesSize, "ZSTD_buildBlockEntropyStats_literals failed");
    entropyMetadata->fseMetadata.fseTablesSize =
        ZSTD_buildBlockEntropyStats_sequences(seqStorePtr,
                                              &prevEntropy->fse, &nextEntropy->fse,
                                              cctxParams,
                                              &entropyMetadata->fseMetadata,
                                              workspace, wkspSize);
    FORWARD_IF_ERROR(entropyMetadata->fseMetadata.fseTablesSize, "ZSTD_buildBlockEntropyStats_sequences failed");
    return 0;
}


static size_t
ZSTD_estimateBlockSize_literal(const BYTE* literals, size_t litSize,
                               const ZSTD_hufCTables_t* huf,
                               const ZSTD_hufCTablesMetadata_t* hufMetadata,
                               void* workspace, size_t wkspSize,
                               int writeEntropy)
{
    unsigned* const countWksp = (unsigned*)workspace;
    unsigned maxSymbolValue = HUF_SYMBOLVALUE_MAX;
    size_t literalSectionHeaderSize = 3 + (litSize >= 1 KB) + (litSize >= 16 KB);
    U32 singleStream = litSize < 256;

    if (hufMetadata->hType == set_basic) return litSize;
    else if (hufMetadata->hType == set_rle) return 1;
    else if (hufMetadata->hType == set_compressed || hufMetadata->hType == set_repeat) {
        size_t const largest = HIST_count_wksp (countWksp, &maxSymbolValue, (const BYTE*)literals, litSize, workspace, wkspSize);
        if (ZSTD_isError(largest)) return litSize;
        {   size_t cLitSizeEstimate = HUF_estimateCompressedSize((const HUF_CElt*)huf->CTable, countWksp, maxSymbolValue);
            if (writeEntropy) cLitSizeEstimate += hufMetadata->hufDesSize;
            if (!singleStream) cLitSizeEstimate += 6; /* multi-stream huffman uses 6-byte jump table */
            return cLitSizeEstimate + literalSectionHeaderSize;
    }   }
    assert(0); /* impossible */
    return 0;
}


static size_t
ZSTD_estimateBlockSize_symbolType(SymbolEncodingType_e type,
                    const BYTE* codeTable, size_t nbSeq, unsigned maxCode,
                    const FSE_CTable* fseCTable,
                    const U8* additionalBits,
                    short const* defaultNorm, U32 defaultNormLog, U32 defaultMax,
                    void* workspace, size_t wkspSize)
{
    unsigned* const countWksp = (unsigned*)workspace;
    const BYTE* ctp = codeTable;
    const BYTE* const ctStart = ctp;
    const BYTE* const ctEnd = ctStart + nbSeq;
    size_t cSymbolTypeSizeEstimateInBits = 0;
    unsigned max = maxCode;

    HIST_countFast_wksp(countWksp, &max, codeTable, nbSeq, workspace, wkspSize);  /* can't fail */
    if (type == set_basic) {

        assert(max <= defaultMax);
        (void)defaultMax;
        cSymbolTypeSizeEstimateInBits = ZSTD_crossEntropyCost(defaultNorm, defaultNormLog, countWksp, max);
    } else if (type == set_rle) {
        cSymbolTypeSizeEstimateInBits = 0;
    } else if (type == set_compressed || type == set_repeat) {
        cSymbolTypeSizeEstimateInBits = ZSTD_fseBitCost(fseCTable, countWksp, max);
    }
    if (ZSTD_isError(cSymbolTypeSizeEstimateInBits)) {
        return nbSeq * 10;
    }
    while (ctp < ctEnd) {
        if (additionalBits) cSymbolTypeSizeEstimateInBits += additionalBits[*ctp];
        else cSymbolTypeSizeEstimateInBits += *ctp; /* for offset, offset code is also the number of additional bits */
        ctp++;
    }
    return cSymbolTypeSizeEstimateInBits >> 3;
}


static size_t
ZSTD_estimateBlockSize_sequences(const BYTE* ofCodeTable,
                                 const BYTE* llCodeTable,
                                 const BYTE* mlCodeTable,
                                 size_t nbSeq,
                                 const ZSTD_fseCTables_t* fseTables,
                                 const ZSTD_fseCTablesMetadata_t* fseMetadata,
                                 void* workspace, size_t wkspSize,
                                 int writeEntropy)
{
    size_t sequencesSectionHeaderSize = 1 /* seqHead */ + 1 /* min seqSize size */ + (nbSeq >= 128) + (nbSeq >= LONGNBSEQ);
    size_t cSeqSizeEstimate = 0;
    cSeqSizeEstimate += ZSTD_estimateBlockSize_symbolType(fseMetadata->ofType, ofCodeTable, nbSeq, MaxOff,
                                    fseTables->offcodeCTable, NULL,
                                    OF_defaultNorm, OF_defaultNormLog, DefaultMaxOff,
                                    workspace, wkspSize);
    cSeqSizeEstimate += ZSTD_estimateBlockSize_symbolType(fseMetadata->llType, llCodeTable, nbSeq, MaxLL,
                                    fseTables->litlengthCTable, LL_bits,
                                    LL_defaultNorm, LL_defaultNormLog, MaxLL,
                                    workspace, wkspSize);
    cSeqSizeEstimate += ZSTD_estimateBlockSize_symbolType(fseMetadata->mlType, mlCodeTable, nbSeq, MaxML,
                                    fseTables->matchlengthCTable, ML_bits,
                                    ML_defaultNorm, ML_defaultNormLog, MaxML,
                                    workspace, wkspSize);
    if (writeEntropy) cSeqSizeEstimate += fseMetadata->fseTablesSize;
    return cSeqSizeEstimate + sequencesSectionHeaderSize;
}


static size_t
ZSTD_estimateBlockSize(const BYTE* literals, size_t litSize,
                       const BYTE* ofCodeTable,
                       const BYTE* llCodeTable,
                       const BYTE* mlCodeTable,
                       size_t nbSeq,
                       const ZSTD_entropyCTables_t* entropy,
                       const ZSTD_entropyCTablesMetadata_t* entropyMetadata,
                       void* workspace, size_t wkspSize,
                       int writeLitEntropy, int writeSeqEntropy)
{
    size_t const literalsSize = ZSTD_estimateBlockSize_literal(literals, litSize,
                                    &entropy->huf, &entropyMetadata->hufMetadata,
                                    workspace, wkspSize, writeLitEntropy);
    size_t const seqSize = ZSTD_estimateBlockSize_sequences(ofCodeTable, llCodeTable, mlCodeTable,
                                    nbSeq, &entropy->fse, &entropyMetadata->fseMetadata,
                                    workspace, wkspSize, writeSeqEntropy);
    return seqSize + literalsSize + ZSTD_blockHeaderSize;
}


static size_t
ZSTD_buildEntropyStatisticsAndEstimateSubBlockSize(SeqStore_t* seqStore, ZSTD_CCtx* zc)
{
    ZSTD_entropyCTablesMetadata_t* const entropyMetadata = &zc->blockSplitCtx.entropyMetadata;
    DEBUGLOG(6, "ZSTD_buildEntropyStatisticsAndEstimateSubBlockSize()");
    FORWARD_IF_ERROR(ZSTD_buildBlockEntropyStats(seqStore,
                    &zc->blockState.prevCBlock->entropy,
                    &zc->blockState.nextCBlock->entropy,
                    &zc->appliedParams,
                    entropyMetadata,
                    zc->tmpWorkspace, zc->tmpWkspSize), "");
    return ZSTD_estimateBlockSize(
                    seqStore->litStart, (size_t)(seqStore->lit - seqStore->litStart),
                    seqStore->ofCode, seqStore->llCode, seqStore->mlCode,
                    (size_t)(seqStore->sequences - seqStore->sequencesStart),
                    &zc->blockState.nextCBlock->entropy,
                    entropyMetadata,
                    zc->tmpWorkspace, zc->tmpWkspSize,
                    (int)(entropyMetadata->hufMetadata.hType == set_compressed), 1);
}


static size_t ZSTD_countSeqStoreLiteralsBytes(const SeqStore_t* const seqStore)
{
    size_t literalsBytes = 0;
    size_t const nbSeqs = (size_t)(seqStore->sequences - seqStore->sequencesStart);
    size_t i;
    for (i = 0; i < nbSeqs; ++i) {
        SeqDef const seq = seqStore->sequencesStart[i];
        literalsBytes += seq.litLength;
        if (i == seqStore->longLengthPos && seqStore->longLengthType == ZSTD_llt_literalLength) {
            literalsBytes += 0x10000;
    }   }
    return literalsBytes;
}


static size_t ZSTD_countSeqStoreMatchBytes(const SeqStore_t* const seqStore)
{
    size_t matchBytes = 0;
    size_t const nbSeqs = (size_t)(seqStore->sequences - seqStore->sequencesStart);
    size_t i;
    for (i = 0; i < nbSeqs; ++i) {
        SeqDef seq = seqStore->sequencesStart[i];
        matchBytes += seq.mlBase + MINMATCH;
        if (i == seqStore->longLengthPos && seqStore->longLengthType == ZSTD_llt_matchLength) {
            matchBytes += 0x10000;
    }   }
    return matchBytes;
}


void ZSTD_deriveSeqStoreChunk(SeqStore_t* resultSeqStore,
                               const SeqStore_t* originalSeqStore,
                                     size_t startIdx, size_t endIdx)
{
    *resultSeqStore = *originalSeqStore;
    if (startIdx > 0) {
        resultSeqStore->sequences = originalSeqStore->sequencesStart + startIdx;
        resultSeqStore->litStart += ZSTD_countSeqStoreLiteralsBytes(resultSeqStore);
    }


    if (originalSeqStore->longLengthType != ZSTD_llt_none) {
        if (originalSeqStore->longLengthPos < startIdx || originalSeqStore->longLengthPos >= endIdx) {
            resultSeqStore->longLengthType = ZSTD_llt_none;
        } else {
            resultSeqStore->longLengthPos -= (U32)startIdx;
        }
    }
    resultSeqStore->sequencesStart = originalSeqStore->sequencesStart + startIdx;
    resultSeqStore->sequences = originalSeqStore->sequencesStart + endIdx;
    if (endIdx == (size_t)(originalSeqStore->sequences - originalSeqStore->sequencesStart)) {

        assert(resultSeqStore->lit == originalSeqStore->lit);
    } else {
        size_t const literalsBytes = ZSTD_countSeqStoreLiteralsBytes(resultSeqStore);
        resultSeqStore->lit = resultSeqStore->litStart + literalsBytes;
    }
    resultSeqStore->llCode += startIdx;
    resultSeqStore->mlCode += startIdx;
    resultSeqStore->ofCode += startIdx;
}


static U32
ZSTD_resolveRepcodeToRawOffset(const U32 rep[ZSTD_REP_NUM], const U32 offBase, const U32 ll0)
{
    U32 const adjustedRepCode = OFFBASE_TO_REPCODE(offBase) - 1 + ll0;  /* [ 0 - 3 ] */
    assert(OFFBASE_IS_REPCODE(offBase));
    if (adjustedRepCode == ZSTD_REP_NUM) {
        assert(ll0);

        return rep[0] - 1;
    }
    return rep[adjustedRepCode];
}


static void
ZSTD_seqStore_resolveOffCodes(Repcodes_t* const dRepcodes, Repcodes_t* const cRepcodes,
                        const SeqStore_t* const seqStore, U32 const nbSeq)
{
    U32 idx = 0;
    U32 const longLitLenIdx = seqStore->longLengthType == ZSTD_llt_literalLength ? seqStore->longLengthPos : nbSeq;
    for (; idx < nbSeq; ++idx) {
        SeqDef* const seq = seqStore->sequencesStart + idx;
        U32 const ll0 = (seq->litLength == 0) && (idx != longLitLenIdx);
        U32 const offBase = seq->offBase;
        assert(offBase > 0);
        if (OFFBASE_IS_REPCODE(offBase)) {
            U32 const dRawOffset = ZSTD_resolveRepcodeToRawOffset(dRepcodes->rep, offBase, ll0);
            U32 const cRawOffset = ZSTD_resolveRepcodeToRawOffset(cRepcodes->rep, offBase, ll0);

            if (dRawOffset != cRawOffset) {
                seq->offBase = OFFSET_TO_OFFBASE(cRawOffset);
            }
        }

        ZSTD_updateRep(dRepcodes->rep, seq->offBase, ll0);
        ZSTD_updateRep(cRepcodes->rep, offBase, ll0);
    }
}


static size_t
ZSTD_compressSeqStore_singleBlock(ZSTD_CCtx* zc,
                            const SeqStore_t* const seqStore,
                                  Repcodes_t* const dRep, Repcodes_t* const cRep,
                                  void* dst, size_t dstCapacity,
                            const void* src, size_t srcSize,
                                  U32 lastBlock, U32 isPartition)
{
    const U32 rleMaxLength = 25;
    BYTE* op = (BYTE*)dst;
    const BYTE* ip = (const BYTE*)src;
    size_t cSize;
    size_t cSeqsSize;


    Repcodes_t const dRepOriginal = *dRep;
    DEBUGLOG(5, "ZSTD_compressSeqStore_singleBlock");
    if (isPartition)
        ZSTD_seqStore_resolveOffCodes(dRep, cRep, seqStore, (U32)(seqStore->sequences - seqStore->sequencesStart));

    RETURN_ERROR_IF(dstCapacity < ZSTD_blockHeaderSize, dstSize_tooSmall, "Block header doesn't fit");
    cSeqsSize = ZSTD_entropyCompressSeqStore(seqStore,
                &zc->blockState.prevCBlock->entropy, &zc->blockState.nextCBlock->entropy,
                &zc->appliedParams,
                op + ZSTD_blockHeaderSize, dstCapacity - ZSTD_blockHeaderSize,
                srcSize,
                zc->tmpWorkspace, zc->tmpWkspSize /* statically allocated in resetCCtx */,
                ZSTD_CCtx_get_bmi2(zc));
    FORWARD_IF_ERROR(cSeqsSize, "ZSTD_entropyCompressSeqStore failed!");

    if (!zc->isFirstBlock &&
        cSeqsSize < rleMaxLength &&
        ZSTD_isRLE((BYTE const*)src, srcSize)) {

        cSeqsSize = 1;
    }


    if (zc->seqCollector.collectSequences) {
        FORWARD_IF_ERROR(ZSTD_copyBlockSequences(&zc->seqCollector, seqStore, dRepOriginal.rep), "copyBlockSequences failed");
        ZSTD_blockState_confirmRepcodesAndEntropyTables(&zc->blockState);
        return 0;
    }

    if (cSeqsSize == 0) {
        cSize = ZSTD_noCompressBlock(op, dstCapacity, ip, srcSize, lastBlock);
        FORWARD_IF_ERROR(cSize, "Nocompress block failed");
        DEBUGLOG(5, "Writing out nocompress block, size: %zu", cSize);
        *dRep = dRepOriginal; /* reset simulated decompression repcode history */
    } else if (cSeqsSize == 1) {
        cSize = ZSTD_rleCompressBlock(op, dstCapacity, *ip, srcSize, lastBlock);
        FORWARD_IF_ERROR(cSize, "RLE compress block failed");
        DEBUGLOG(5, "Writing out RLE block, size: %zu", cSize);
        *dRep = dRepOriginal; /* reset simulated decompression repcode history */
    } else {
        ZSTD_blockState_confirmRepcodesAndEntropyTables(&zc->blockState);
        writeBlockHeader(op, cSeqsSize, srcSize, lastBlock);
        cSize = ZSTD_blockHeaderSize + cSeqsSize;
        DEBUGLOG(5, "Writing out compressed block, size: %zu", cSize);
    }

    if (zc->blockState.prevCBlock->entropy.fse.offcode_repeatMode == FSE_repeat_valid)
        zc->blockState.prevCBlock->entropy.fse.offcode_repeatMode = FSE_repeat_check;

    return cSize;
}


typedef struct {
    U32* splitLocations;    /* Array of split indices */
    size_t idx;             /* The current index within splitLocations being worked on */
} seqStoreSplits;

#define MIN_SEQUENCES_BLOCK_SPLITTING 300


static void
ZSTD_deriveBlockSplitsHelper(seqStoreSplits* splits, size_t startIdx, size_t endIdx,
                             ZSTD_CCtx* zc, const SeqStore_t* origSeqStore)
{
    SeqStore_t* const fullSeqStoreChunk = &zc->blockSplitCtx.fullSeqStoreChunk;
    SeqStore_t* const firstHalfSeqStore = &zc->blockSplitCtx.firstHalfSeqStore;
    SeqStore_t* const secondHalfSeqStore = &zc->blockSplitCtx.secondHalfSeqStore;
    size_t estimatedOriginalSize;
    size_t estimatedFirstHalfSize;
    size_t estimatedSecondHalfSize;
    size_t midIdx = (startIdx + endIdx)/2;

    DEBUGLOG(5, "ZSTD_deriveBlockSplitsHelper: startIdx=%zu endIdx=%zu", startIdx, endIdx);
    assert(endIdx >= startIdx);
    if (endIdx - startIdx < MIN_SEQUENCES_BLOCK_SPLITTING || splits->idx >= ZSTD_MAX_NB_BLOCK_SPLITS) {
        DEBUGLOG(6, "ZSTD_deriveBlockSplitsHelper: Too few sequences (%zu)", endIdx - startIdx);
        return;
    }
    ZSTD_deriveSeqStoreChunk(fullSeqStoreChunk, origSeqStore, startIdx, endIdx);
    ZSTD_deriveSeqStoreChunk(firstHalfSeqStore, origSeqStore, startIdx, midIdx);
    ZSTD_deriveSeqStoreChunk(secondHalfSeqStore, origSeqStore, midIdx, endIdx);
    estimatedOriginalSize = ZSTD_buildEntropyStatisticsAndEstimateSubBlockSize(fullSeqStoreChunk, zc);
    estimatedFirstHalfSize = ZSTD_buildEntropyStatisticsAndEstimateSubBlockSize(firstHalfSeqStore, zc);
    estimatedSecondHalfSize = ZSTD_buildEntropyStatisticsAndEstimateSubBlockSize(secondHalfSeqStore, zc);
    DEBUGLOG(5, "Estimated original block size: %zu -- First half split: %zu -- Second half split: %zu",
             estimatedOriginalSize, estimatedFirstHalfSize, estimatedSecondHalfSize);
    if (ZSTD_isError(estimatedOriginalSize) || ZSTD_isError(estimatedFirstHalfSize) || ZSTD_isError(estimatedSecondHalfSize)) {
        return;
    }
    if (estimatedFirstHalfSize + estimatedSecondHalfSize < estimatedOriginalSize) {
        DEBUGLOG(5, "split decided at seqNb:%zu", midIdx);
        ZSTD_deriveBlockSplitsHelper(splits, startIdx, midIdx, zc, origSeqStore);
        if (splits->idx >= ZSTD_MAX_NB_BLOCK_SPLITS)
            return;
        splits->splitLocations[splits->idx] = (U32)midIdx;
        splits->idx++;
        ZSTD_deriveBlockSplitsHelper(splits, midIdx, endIdx, zc, origSeqStore);
    }
}


static size_t ZSTD_deriveBlockSplits(ZSTD_CCtx* zc, U32 partitions[], U32 nbSeq)
{
    seqStoreSplits splits;
    splits.splitLocations = partitions;
    splits.idx = 0;
    if (nbSeq <= 4) {
        DEBUGLOG(5, "ZSTD_deriveBlockSplits: Too few sequences to split (%u <= 4)", nbSeq);

        return 0;
    }
    ZSTD_deriveBlockSplitsHelper(&splits, 0, nbSeq, zc, &zc->seqStore);
    assert(splits.idx <= ZSTD_MAX_NB_BLOCK_SPLITS);
    splits.splitLocations[splits.idx] = nbSeq;
    DEBUGLOG(5, "ZSTD_deriveBlockSplits: final nb partitions: %zu", splits.idx+1);
    return splits.idx;
}


static size_t
ZSTD_compressBlock_splitBlock_internal(ZSTD_CCtx* zc,
                                    void* dst, size_t dstCapacity,
                              const void* src, size_t blockSize,
                                    U32 lastBlock, U32 nbSeq)
{
    size_t cSize = 0;
    const BYTE* ip = (const BYTE*)src;
    BYTE* op = (BYTE*)dst;
    size_t i = 0;
    size_t srcBytesTotal = 0;
    U32* const partitions = zc->blockSplitCtx.partitions; /* includes the final block boundary */
    SeqStore_t* const nextSeqStore = &zc->blockSplitCtx.nextSeqStore;
    SeqStore_t* const currSeqStore = &zc->blockSplitCtx.currSeqStore;
    size_t const numSplits = ZSTD_deriveBlockSplits(zc, partitions, nbSeq);


    Repcodes_t dRep;
    Repcodes_t cRep;
    ZSTD_memcpy(dRep.rep, zc->blockState.prevCBlock->rep, sizeof(Repcodes_t));
    ZSTD_memcpy(cRep.rep, zc->blockState.prevCBlock->rep, sizeof(Repcodes_t));
    ZSTD_memset(nextSeqStore, 0, sizeof(SeqStore_t));

    DEBUGLOG(5, "ZSTD_compressBlock_splitBlock_internal (dstCapacity=%u, dictLimit=%u, nextToUpdate=%u)",
                (unsigned)dstCapacity, (unsigned)zc->blockState.matchState.window.dictLimit,
                (unsigned)zc->blockState.matchState.nextToUpdate);

    if (numSplits == 0) {
        size_t cSizeSingleBlock =
            ZSTD_compressSeqStore_singleBlock(zc, &zc->seqStore,
                                            &dRep, &cRep,
                                            op, dstCapacity,
                                            ip, blockSize,
                                            lastBlock, 0 /* isPartition */);
        FORWARD_IF_ERROR(cSizeSingleBlock, "Compressing single block from splitBlock_internal() failed!");
        DEBUGLOG(5, "ZSTD_compressBlock_splitBlock_internal: No splits");
        assert(zc->blockSizeMax <= ZSTD_BLOCKSIZE_MAX);
        assert(cSizeSingleBlock <= zc->blockSizeMax + ZSTD_blockHeaderSize);
        return cSizeSingleBlock;
    }

    ZSTD_deriveSeqStoreChunk(currSeqStore, &zc->seqStore, 0, partitions[0]);
    for (i = 0; i <= numSplits; ++i) {
        size_t cSizeChunk;
        U32 const lastPartition = (i == numSplits);
        U32 lastBlockEntireSrc = 0;

        size_t srcBytes = ZSTD_countSeqStoreLiteralsBytes(currSeqStore) + ZSTD_countSeqStoreMatchBytes(currSeqStore);
        srcBytesTotal += srcBytes;
        if (lastPartition) {

            srcBytes += blockSize - srcBytesTotal;
            lastBlockEntireSrc = lastBlock;
        } else {
            ZSTD_deriveSeqStoreChunk(nextSeqStore, &zc->seqStore, partitions[i], partitions[i+1]);
        }

        cSizeChunk = ZSTD_compressSeqStore_singleBlock(zc, currSeqStore,
                                                      &dRep, &cRep,
                                                       op, dstCapacity,
                                                       ip, srcBytes,
                                                       lastBlockEntireSrc, 1 /* isPartition */);
        DEBUGLOG(5, "Estimated size: %zu vs %zu : actual size",
                    ZSTD_buildEntropyStatisticsAndEstimateSubBlockSize(currSeqStore, zc), cSizeChunk);
        FORWARD_IF_ERROR(cSizeChunk, "Compressing chunk failed!");

        ip += srcBytes;
        op += cSizeChunk;
        dstCapacity -= cSizeChunk;
        cSize += cSizeChunk;
        *currSeqStore = *nextSeqStore;
        assert(cSizeChunk <= zc->blockSizeMax + ZSTD_blockHeaderSize);
    }

    ZSTD_memcpy(zc->blockState.prevCBlock->rep, dRep.rep, sizeof(Repcodes_t));
    return cSize;
}

static size_t
ZSTD_compressBlock_splitBlock(ZSTD_CCtx* zc,
                              void* dst, size_t dstCapacity,
                              const void* src, size_t srcSize, U32 lastBlock)
{
    U32 nbSeq;
    size_t cSize;
    DEBUGLOG(5, "ZSTD_compressBlock_splitBlock");
    assert(zc->appliedParams.postBlockSplitter == ZSTD_ps_enable);

    {   const size_t bss = ZSTD_buildSeqStore(zc, src, srcSize);
        FORWARD_IF_ERROR(bss, "ZSTD_buildSeqStore failed");
        if (bss == ZSTDbss_noCompress) {
            if (zc->blockState.prevCBlock->entropy.fse.offcode_repeatMode == FSE_repeat_valid)
                zc->blockState.prevCBlock->entropy.fse.offcode_repeatMode = FSE_repeat_check;
            RETURN_ERROR_IF(zc->seqCollector.collectSequences, sequenceProducer_failed, "Uncompressible block");
            cSize = ZSTD_noCompressBlock(dst, dstCapacity, src, srcSize, lastBlock);
            FORWARD_IF_ERROR(cSize, "ZSTD_noCompressBlock failed");
            DEBUGLOG(5, "ZSTD_compressBlock_splitBlock: Nocompress block");
            return cSize;
        }
        nbSeq = (U32)(zc->seqStore.sequences - zc->seqStore.sequencesStart);
    }

    cSize = ZSTD_compressBlock_splitBlock_internal(zc, dst, dstCapacity, src, srcSize, lastBlock, nbSeq);
    FORWARD_IF_ERROR(cSize, "Splitting blocks failed!");
    return cSize;
}

static size_t
ZSTD_compressBlock_internal(ZSTD_CCtx* zc,
                            void* dst, size_t dstCapacity,
                            const void* src, size_t srcSize, U32 frame)
{

    const U32 rleMaxLength = 25;
    size_t cSize;
    const BYTE* ip = (const BYTE*)src;
    BYTE* op = (BYTE*)dst;
    DEBUGLOG(5, "ZSTD_compressBlock_internal (dstCapacity=%u, dictLimit=%u, nextToUpdate=%u)",
                (unsigned)dstCapacity, (unsigned)zc->blockState.matchState.window.dictLimit,
                (unsigned)zc->blockState.matchState.nextToUpdate);

    {   const size_t bss = ZSTD_buildSeqStore(zc, src, srcSize);
        FORWARD_IF_ERROR(bss, "ZSTD_buildSeqStore failed");
        if (bss == ZSTDbss_noCompress) {
            RETURN_ERROR_IF(zc->seqCollector.collectSequences, sequenceProducer_failed, "Uncompressible block");
            cSize = 0;
            goto out;
        }
    }

    if (zc->seqCollector.collectSequences) {
        FORWARD_IF_ERROR(ZSTD_copyBlockSequences(&zc->seqCollector, ZSTD_getSeqStore(zc), zc->blockState.prevCBlock->rep), "copyBlockSequences failed");
        ZSTD_blockState_confirmRepcodesAndEntropyTables(&zc->blockState);
        return 0;
    }


    cSize = ZSTD_entropyCompressSeqStore(&zc->seqStore,
            &zc->blockState.prevCBlock->entropy, &zc->blockState.nextCBlock->entropy,
            &zc->appliedParams,
            dst, dstCapacity,
            srcSize,
            zc->tmpWorkspace, zc->tmpWkspSize /* statically allocated in resetCCtx */,
            ZSTD_CCtx_get_bmi2(zc));

    if (frame &&

        !zc->isFirstBlock &&
        cSize < rleMaxLength &&
        ZSTD_isRLE(ip, srcSize))
    {
        cSize = 1;
        op[0] = ip[0];
    }

out:
    if (!ZSTD_isError(cSize) && cSize > 1) {
        ZSTD_blockState_confirmRepcodesAndEntropyTables(&zc->blockState);
    }

    if (zc->blockState.prevCBlock->entropy.fse.offcode_repeatMode == FSE_repeat_valid)
        zc->blockState.prevCBlock->entropy.fse.offcode_repeatMode = FSE_repeat_check;

    return cSize;
}

static size_t ZSTD_compressBlock_targetCBlockSize_body(ZSTD_CCtx* zc,
                               void* dst, size_t dstCapacity,
                               const void* src, size_t srcSize,
                               const size_t bss, U32 lastBlock)
{
    DEBUGLOG(6, "Attempting ZSTD_compressSuperBlock()");
    if (bss == ZSTDbss_compress) {
        if (/* We don't want to emit our first block as a RLE even if it qualifies because
            * doing so will cause the decoder (cli only) to throw a "should consume all input error."
            * This is only an issue for zstd <= v1.4.3
            */
            !zc->isFirstBlock &&
            ZSTD_maybeRLE(&zc->seqStore) &&
            ZSTD_isRLE((BYTE const*)src, srcSize))
        {
            return ZSTD_rleCompressBlock(dst, dstCapacity, *(BYTE const*)src, srcSize, lastBlock);
        }

        {   size_t const cSize =
                ZSTD_compressSuperBlock(zc, dst, dstCapacity, src, srcSize, lastBlock);
            if (cSize != ERROR(dstSize_tooSmall)) {
                size_t const maxCSize =
                    srcSize - ZSTD_minGain(srcSize, zc->appliedParams.cParams.strategy);
                FORWARD_IF_ERROR(cSize, "ZSTD_compressSuperBlock failed");
                if (cSize != 0 && cSize < maxCSize + ZSTD_blockHeaderSize) {
                    ZSTD_blockState_confirmRepcodesAndEntropyTables(&zc->blockState);
                    return cSize;
                }
            }
        }
    } /* if (bss == ZSTDbss_compress)*/

    DEBUGLOG(6, "Resorting to ZSTD_noCompressBlock()");

    return ZSTD_noCompressBlock(dst, dstCapacity, src, srcSize, lastBlock);
}

static size_t ZSTD_compressBlock_targetCBlockSize(ZSTD_CCtx* zc,
                               void* dst, size_t dstCapacity,
                               const void* src, size_t srcSize,
                               U32 lastBlock)
{
    size_t cSize = 0;
    const size_t bss = ZSTD_buildSeqStore(zc, src, srcSize);
    DEBUGLOG(5, "ZSTD_compressBlock_targetCBlockSize (dstCapacity=%u, dictLimit=%u, nextToUpdate=%u, srcSize=%zu)",
                (unsigned)dstCapacity, (unsigned)zc->blockState.matchState.window.dictLimit, (unsigned)zc->blockState.matchState.nextToUpdate, srcSize);
    FORWARD_IF_ERROR(bss, "ZSTD_buildSeqStore failed");

    cSize = ZSTD_compressBlock_targetCBlockSize_body(zc, dst, dstCapacity, src, srcSize, bss, lastBlock);
    FORWARD_IF_ERROR(cSize, "ZSTD_compressBlock_targetCBlockSize_body failed");

    if (zc->blockState.prevCBlock->entropy.fse.offcode_repeatMode == FSE_repeat_valid)
        zc->blockState.prevCBlock->entropy.fse.offcode_repeatMode = FSE_repeat_check;

    return cSize;
}

static void ZSTD_overflowCorrectIfNeeded(ZSTD_MatchState_t* ms,
                                         ZSTD_cwksp* ws,
                                         ZSTD_CCtx_params const* params,
                                         void const* ip,
                                         void const* iend)
{
    U32 const cycleLog = ZSTD_cycleLog(params->cParams.chainLog, params->cParams.strategy);
    U32 const maxDist = (U32)1 << params->cParams.windowLog;
    if (ZSTD_window_needOverflowCorrection(ms->window, cycleLog, maxDist, ms->loadedDictEnd, ip, iend)) {
        U32 const correction = ZSTD_window_correctOverflow(&ms->window, cycleLog, maxDist, ip);
        ZSTD_STATIC_ASSERT(ZSTD_CHAINLOG_MAX <= 30);
        ZSTD_STATIC_ASSERT(ZSTD_WINDOWLOG_MAX_32 <= 30);
        ZSTD_STATIC_ASSERT(ZSTD_WINDOWLOG_MAX <= 31);
        ZSTD_cwksp_mark_tables_dirty(ws);
        ZSTD_reduceIndex(ms, params, correction);
        ZSTD_cwksp_mark_tables_clean(ws);
        if (ms->nextToUpdate < correction) ms->nextToUpdate = 0;
        else ms->nextToUpdate -= correction;

        ms->loadedDictEnd = 0;
        ms->dictMatchState = NULL;
    }
}

/**** skipping file: zstd_preSplit.h ****/

static size_t ZSTD_optimalBlockSize(ZSTD_CCtx* cctx, const void* src, size_t srcSize, size_t blockSizeMax, int splitLevel, ZSTD_strategy strat, S64 savings)
{

    static const int splitLevels[] = { 0, 0, 1, 2, 2, 3, 3, 4, 4, 4 };

    if (srcSize < 128 KB || blockSizeMax < 128 KB)
        return MIN(srcSize, blockSizeMax);

    if (savings < 3) {
        DEBUGLOG(6, "don't attempt splitting: savings (%i) too low", (int)savings);
        return 128 KB;
    }

    if (splitLevel == 1) return 128 KB;
    if (splitLevel == 0) {
        assert(ZSTD_fast <= strat && strat <= ZSTD_btultra2);
        splitLevel = splitLevels[strat];
    } else {
        assert(2 <= splitLevel && splitLevel <= 6);
        splitLevel -= 2;
    }
    return ZSTD_splitBlock(src, blockSizeMax, splitLevel, cctx->tmpWorkspace, cctx->tmpWkspSize);
}


static size_t ZSTD_compress_frameChunk(ZSTD_CCtx* cctx,
                                     void* dst, size_t dstCapacity,
                               const void* src, size_t srcSize,
                                     U32 lastFrameChunk)
{
    size_t blockSizeMax = cctx->blockSizeMax;
    size_t remaining = srcSize;
    const BYTE* ip = (const BYTE*)src;
    BYTE* const ostart = (BYTE*)dst;
    BYTE* op = ostart;
    U32 const maxDist = (U32)1 << cctx->appliedParams.cParams.windowLog;
    S64 savings = (S64)cctx->consumedSrcSize - (S64)cctx->producedCSize;

    assert(cctx->appliedParams.cParams.windowLog <= ZSTD_WINDOWLOG_MAX);

    DEBUGLOG(5, "ZSTD_compress_frameChunk (srcSize=%u, blockSizeMax=%u)", (unsigned)srcSize, (unsigned)blockSizeMax);
    if (cctx->appliedParams.fParams.checksumFlag && srcSize)
        XXH64_update(&cctx->xxhState, src, srcSize);

    while (remaining) {
        ZSTD_MatchState_t* const ms = &cctx->blockState.matchState;
        size_t const blockSize = ZSTD_optimalBlockSize(cctx,
                                ip, remaining,
                                blockSizeMax,
                                cctx->appliedParams.preBlockSplitter_level,
                                cctx->appliedParams.cParams.strategy,
                                savings);
        U32 const lastBlock = lastFrameChunk & (blockSize == remaining);
        assert(blockSize <= remaining);


        RETURN_ERROR_IF(dstCapacity < ZSTD_blockHeaderSize + MIN_CBLOCK_SIZE + 1,
                        dstSize_tooSmall,
                        "not enough space to store compressed block");

        ZSTD_overflowCorrectIfNeeded(
            ms, &cctx->workspace, &cctx->appliedParams, ip, ip + blockSize);
        ZSTD_checkDictValidity(&ms->window, ip + blockSize, maxDist, &ms->loadedDictEnd, &ms->dictMatchState);
        ZSTD_window_enforceMaxDist(&ms->window, ip, maxDist, &ms->loadedDictEnd, &ms->dictMatchState);


        if (ms->nextToUpdate < ms->window.lowLimit) ms->nextToUpdate = ms->window.lowLimit;

        {   size_t cSize;
            if (ZSTD_useTargetCBlockSize(&cctx->appliedParams)) {
                cSize = ZSTD_compressBlock_targetCBlockSize(cctx, op, dstCapacity, ip, blockSize, lastBlock);
                FORWARD_IF_ERROR(cSize, "ZSTD_compressBlock_targetCBlockSize failed");
                assert(cSize > 0);
                assert(cSize <= blockSize + ZSTD_blockHeaderSize);
            } else if (ZSTD_blockSplitterEnabled(&cctx->appliedParams)) {
                cSize = ZSTD_compressBlock_splitBlock(cctx, op, dstCapacity, ip, blockSize, lastBlock);
                FORWARD_IF_ERROR(cSize, "ZSTD_compressBlock_splitBlock failed");
                assert(cSize > 0 || cctx->seqCollector.collectSequences == 1);
            } else {
                cSize = ZSTD_compressBlock_internal(cctx,
                                        op+ZSTD_blockHeaderSize, dstCapacity-ZSTD_blockHeaderSize,
                                        ip, blockSize, 1 /* frame */);
                FORWARD_IF_ERROR(cSize, "ZSTD_compressBlock_internal failed");

                if (cSize == 0) {  /* block is not compressible */
                    cSize = ZSTD_noCompressBlock(op, dstCapacity, ip, blockSize, lastBlock);
                    FORWARD_IF_ERROR(cSize, "ZSTD_noCompressBlock failed");
                } else {
                    U32 const cBlockHeader = cSize == 1 ?
                        lastBlock + (((U32)bt_rle)<<1) + (U32)(blockSize << 3) :
                        lastBlock + (((U32)bt_compressed)<<1) + (U32)(cSize << 3);
                    MEM_writeLE24(op, cBlockHeader);
                    cSize += ZSTD_blockHeaderSize;
                }
            }  /* if (ZSTD_useTargetCBlockSize(&cctx->appliedParams))*/


            savings += (S64)blockSize - (S64)cSize;

            ip += blockSize;
            assert(remaining >= blockSize);
            remaining -= blockSize;
            op += cSize;
            assert(dstCapacity >= cSize);
            dstCapacity -= cSize;
            cctx->isFirstBlock = 0;
            DEBUGLOG(5, "ZSTD_compress_frameChunk: adding a block of size %u",
                        (unsigned)cSize);
    }   }

    if (lastFrameChunk && (op>ostart)) cctx->stage = ZSTDcs_ending;
    return (size_t)(op-ostart);
}


static size_t ZSTD_writeFrameHeader(void* dst, size_t dstCapacity,
                                    const ZSTD_CCtx_params* params,
                                    U64 pledgedSrcSize, U32 dictID)
{
    BYTE* const op = (BYTE*)dst;
    U32   const dictIDSizeCodeLength = (dictID>0) + (dictID>=256) + (dictID>=65536);   /* 0-3 */
    U32   const dictIDSizeCode = params->fParams.noDictIDFlag ? 0 : dictIDSizeCodeLength;   /* 0-3 */
    U32   const checksumFlag = params->fParams.checksumFlag>0;
    U32   const windowSize = (U32)1 << params->cParams.windowLog;
    U32   const singleSegment = params->fParams.contentSizeFlag && (windowSize >= pledgedSrcSize);
    BYTE  const windowLogByte = (BYTE)((params->cParams.windowLog - ZSTD_WINDOWLOG_ABSOLUTEMIN) << 3);
    U32   const fcsCode = params->fParams.contentSizeFlag ?
                     (pledgedSrcSize>=256) + (pledgedSrcSize>=65536+256) + (pledgedSrcSize>=0xFFFFFFFFU) : 0;  /* 0-3 */
    BYTE  const frameHeaderDescriptionByte = (BYTE)(dictIDSizeCode + (checksumFlag<<2) + (singleSegment<<5) + (fcsCode<<6) );
    size_t pos=0;

    assert(!(params->fParams.contentSizeFlag && pledgedSrcSize == ZSTD_CONTENTSIZE_UNKNOWN));
    RETURN_ERROR_IF(dstCapacity < ZSTD_FRAMEHEADERSIZE_MAX, dstSize_tooSmall,
                    "dst buf is too small to fit worst-case frame header size.");
    DEBUGLOG(4, "ZSTD_writeFrameHeader : dictIDFlag : %u ; dictID : %u ; dictIDSizeCode : %u",
                !params->fParams.noDictIDFlag, (unsigned)dictID, (unsigned)dictIDSizeCode);
    if (params->format == ZSTD_f_zstd1) {
        MEM_writeLE32(dst, ZSTD_MAGICNUMBER);
        pos = 4;
    }
    op[pos++] = frameHeaderDescriptionByte;
    if (!singleSegment) op[pos++] = windowLogByte;
    switch(dictIDSizeCode)
    {
        default:
            assert(0); /* impossible */
            ZSTD_FALLTHROUGH;
        case 0 : break;
        case 1 : op[pos] = (BYTE)(dictID); pos++; break;
        case 2 : MEM_writeLE16(op+pos, (U16)dictID); pos+=2; break;
        case 3 : MEM_writeLE32(op+pos, dictID); pos+=4; break;
    }
    switch(fcsCode)
    {
        default:
            assert(0); /* impossible */
            ZSTD_FALLTHROUGH;
        case 0 : if (singleSegment) op[pos++] = (BYTE)(pledgedSrcSize); break;
        case 1 : MEM_writeLE16(op+pos, (U16)(pledgedSrcSize-256)); pos+=2; break;
        case 2 : MEM_writeLE32(op+pos, (U32)(pledgedSrcSize)); pos+=4; break;
        case 3 : MEM_writeLE64(op+pos, (U64)(pledgedSrcSize)); pos+=8; break;
    }
    return pos;
}


size_t ZSTD_writeSkippableFrame(void* dst, size_t dstCapacity,
                                const void* src, size_t srcSize, unsigned magicVariant) {
    BYTE* op = (BYTE*)dst;
    RETURN_ERROR_IF(dstCapacity < srcSize + ZSTD_SKIPPABLEHEADERSIZE /* Skippable frame overhead */,
                    dstSize_tooSmall, "Not enough room for skippable frame");
    RETURN_ERROR_IF(srcSize > (unsigned)0xFFFFFFFF, srcSize_wrong, "Src size too large for skippable frame");
    RETURN_ERROR_IF(magicVariant > 15, parameter_outOfBound, "Skippable frame magic number variant not supported");

    MEM_writeLE32(op, (U32)(ZSTD_MAGIC_SKIPPABLE_START + magicVariant));
    MEM_writeLE32(op+4, (U32)srcSize);
    ZSTD_memcpy(op+8, src, srcSize);
    return srcSize + ZSTD_SKIPPABLEHEADERSIZE;
}


size_t ZSTD_writeLastEmptyBlock(void* dst, size_t dstCapacity)
{
    RETURN_ERROR_IF(dstCapacity < ZSTD_blockHeaderSize, dstSize_tooSmall,
                    "dst buf is too small to write frame trailer empty block.");
    {   U32 const cBlockHeader24 = 1 /*lastBlock*/ + (((U32)bt_raw)<<1);  /* 0 size */
        MEM_writeLE24(dst, cBlockHeader24);
        return ZSTD_blockHeaderSize;
    }
}

void ZSTD_referenceExternalSequences(ZSTD_CCtx* cctx, rawSeq* seq, size_t nbSeq)
{
    assert(cctx->stage == ZSTDcs_init);
    assert(nbSeq == 0 || cctx->appliedParams.ldmParams.enableLdm != ZSTD_ps_enable);
    cctx->externSeqStore.seq = seq;
    cctx->externSeqStore.size = nbSeq;
    cctx->externSeqStore.capacity = nbSeq;
    cctx->externSeqStore.pos = 0;
    cctx->externSeqStore.posInSequence = 0;
}


static size_t ZSTD_compressContinue_internal (ZSTD_CCtx* cctx,
                              void* dst, size_t dstCapacity,
                        const void* src, size_t srcSize,
                               U32 frame, U32 lastFrameChunk)
{
    ZSTD_MatchState_t* const ms = &cctx->blockState.matchState;
    size_t fhSize = 0;

    DEBUGLOG(5, "ZSTD_compressContinue_internal, stage: %u, srcSize: %u",
                cctx->stage, (unsigned)srcSize);
    RETURN_ERROR_IF(cctx->stage==ZSTDcs_created, stage_wrong,
                    "missing init (ZSTD_compressBegin)");

    if (frame && (cctx->stage==ZSTDcs_init)) {
        fhSize = ZSTD_writeFrameHeader(dst, dstCapacity, &cctx->appliedParams,
                                       cctx->pledgedSrcSizePlusOne-1, cctx->dictID);
        FORWARD_IF_ERROR(fhSize, "ZSTD_writeFrameHeader failed");
        assert(fhSize <= dstCapacity);
        dstCapacity -= fhSize;
        dst = (char*)dst + fhSize;
        cctx->stage = ZSTDcs_ongoing;
    }

    if (!srcSize) return fhSize;  /* do not generate an empty block if no input */

    if (!ZSTD_window_update(&ms->window, src, srcSize, ms->forceNonContiguous)) {
        ms->forceNonContiguous = 0;
        ms->nextToUpdate = ms->window.dictLimit;
    }
    if (cctx->appliedParams.ldmParams.enableLdm == ZSTD_ps_enable) {
        ZSTD_window_update(&cctx->ldmState.window, src, srcSize, /* forceNonContiguous */ 0);
    }

    if (!frame) {

        ZSTD_overflowCorrectIfNeeded(
            ms, &cctx->workspace, &cctx->appliedParams,
            src, (BYTE const*)src + srcSize);
    }

    DEBUGLOG(5, "ZSTD_compressContinue_internal (blockSize=%u)", (unsigned)cctx->blockSizeMax);
    {   size_t const cSize = frame ?
                             ZSTD_compress_frameChunk (cctx, dst, dstCapacity, src, srcSize, lastFrameChunk) :
                             ZSTD_compressBlock_internal (cctx, dst, dstCapacity, src, srcSize, 0 /* frame */);
        FORWARD_IF_ERROR(cSize, "%s", frame ? "ZSTD_compress_frameChunk failed" : "ZSTD_compressBlock_internal failed");
        cctx->consumedSrcSize += srcSize;
        cctx->producedCSize += (cSize + fhSize);
        assert(!(cctx->appliedParams.fParams.contentSizeFlag && cctx->pledgedSrcSizePlusOne == 0));
        if (cctx->pledgedSrcSizePlusOne != 0) {  /* control src size */
            ZSTD_STATIC_ASSERT(ZSTD_CONTENTSIZE_UNKNOWN == (unsigned long long)-1);
            RETURN_ERROR_IF(
                cctx->consumedSrcSize+1 > cctx->pledgedSrcSizePlusOne,
                srcSize_wrong,
                "error : pledgedSrcSize = %u, while realSrcSize >= %u",
                (unsigned)cctx->pledgedSrcSizePlusOne-1,
                (unsigned)cctx->consumedSrcSize);
        }
        return cSize + fhSize;
    }
}

size_t ZSTD_compressContinue_public(ZSTD_CCtx* cctx,
                                        void* dst, size_t dstCapacity,
                                  const void* src, size_t srcSize)
{
    DEBUGLOG(5, "ZSTD_compressContinue (srcSize=%u)", (unsigned)srcSize);
    return ZSTD_compressContinue_internal(cctx, dst, dstCapacity, src, srcSize, 1 /* frame mode */, 0 /* last chunk */);
}


size_t ZSTD_compressContinue(ZSTD_CCtx* cctx,
                             void* dst, size_t dstCapacity,
                       const void* src, size_t srcSize)
{
    return ZSTD_compressContinue_public(cctx, dst, dstCapacity, src, srcSize);
}

static size_t ZSTD_getBlockSize_deprecated(const ZSTD_CCtx* cctx)
{
    ZSTD_compressionParameters const cParams = cctx->appliedParams.cParams;
    assert(!ZSTD_checkCParams(cParams));
    return MIN(cctx->appliedParams.maxBlockSize, (size_t)1 << cParams.windowLog);
}


size_t ZSTD_getBlockSize(const ZSTD_CCtx* cctx)
{
    return ZSTD_getBlockSize_deprecated(cctx);
}


size_t ZSTD_compressBlock_deprecated(ZSTD_CCtx* cctx, void* dst, size_t dstCapacity, const void* src, size_t srcSize)
{
    DEBUGLOG(5, "ZSTD_compressBlock: srcSize = %u", (unsigned)srcSize);
    { size_t const blockSizeMax = ZSTD_getBlockSize_deprecated(cctx);
      RETURN_ERROR_IF(srcSize > blockSizeMax, srcSize_wrong, "input is larger than a block"); }

    return ZSTD_compressContinue_internal(cctx, dst, dstCapacity, src, srcSize, 0 /* frame mode */, 0 /* last chunk */);
}


size_t ZSTD_compressBlock(ZSTD_CCtx* cctx, void* dst, size_t dstCapacity, const void* src, size_t srcSize)
{
    return ZSTD_compressBlock_deprecated(cctx, dst, dstCapacity, src, srcSize);
}


static size_t
ZSTD_loadDictionaryContent(ZSTD_MatchState_t* ms,
                        ldmState_t* ls,
                        ZSTD_cwksp* ws,
                        ZSTD_CCtx_params const* params,
                        const void* src, size_t srcSize,
                        ZSTD_dictTableLoadMethod_e dtlm,
                        ZSTD_tableFillPurpose_e tfp)
{
    const BYTE* ip = (const BYTE*) src;
    const BYTE* const iend = ip + srcSize;
    int const loadLdmDict = params->ldmParams.enableLdm == ZSTD_ps_enable && ls != NULL;


    ZSTD_assertEqualCParams(params->cParams, ms->cParams);

    {   /* Ensure large dictionaries can't cause index overflow */


        U32 maxDictSize = ZSTD_CURRENT_MAX - ZSTD_WINDOW_START_INDEX;

        int const CDictTaggedIndices = ZSTD_CDictIndicesAreTagged(&params->cParams);
        if (CDictTaggedIndices && tfp == ZSTD_tfp_forCDict) {

            U32 const shortCacheMaxDictSize = (1u << (32 - ZSTD_SHORT_CACHE_TAG_BITS)) - ZSTD_WINDOW_START_INDEX;
            maxDictSize = MIN(maxDictSize, shortCacheMaxDictSize);
            assert(!loadLdmDict);
        }


        if (srcSize > maxDictSize) {
            ip = iend - maxDictSize;
            src = ip;
            srcSize = maxDictSize;
        }
    }

    if (srcSize > ZSTD_CHUNKSIZE_MAX) {

        assert(ZSTD_window_isEmpty(ms->window));
        if (loadLdmDict) assert(ZSTD_window_isEmpty(ls->window));
    }
    ZSTD_window_update(&ms->window, src, srcSize, /* forceNonContiguous */ 0);

    DEBUGLOG(4, "ZSTD_loadDictionaryContent: useRowMatchFinder=%d", (int)params->useRowMatchFinder);

    if (loadLdmDict) { /* Load the entire dict into LDM matchfinders. */
        DEBUGLOG(4, "ZSTD_loadDictionaryContent: Trigger loadLdmDict");
        ZSTD_window_update(&ls->window, src, srcSize, /* forceNonContiguous */ 0);
        ls->loadedDictEnd = params->forceWindow ? 0 : (U32)(iend - ls->window.base);
        ZSTD_ldm_fillHashTable(ls, ip, iend, &params->ldmParams);
        DEBUGLOG(4, "ZSTD_loadDictionaryContent: ZSTD_ldm_fillHashTable completes");
    }


    {   U32 maxDictSize = 1U << MIN(MAX(params->cParams.hashLog + 3, params->cParams.chainLog + 1), 31);
        if (srcSize > maxDictSize) {
            ip = iend - maxDictSize;
            src = ip;
            srcSize = maxDictSize;
        }
    }

    ms->nextToUpdate = (U32)(ip - ms->window.base);
    ms->loadedDictEnd = params->forceWindow ? 0 : (U32)(iend - ms->window.base);
    ms->forceNonContiguous = params->deterministicRefPrefix;

    if (srcSize <= HASH_READ_SIZE) return 0;

    ZSTD_overflowCorrectIfNeeded(ms, ws, params, ip, iend);

    switch(params->cParams.strategy)
    {
    case ZSTD_fast:
        ZSTD_fillHashTable(ms, iend, dtlm, tfp);
        break;
    case ZSTD_dfast:
#ifndef ZSTD_EXCLUDE_DFAST_BLOCK_COMPRESSOR
        ZSTD_fillDoubleHashTable(ms, iend, dtlm, tfp);
#else
        assert(0); /* shouldn't be called: cparams should've been adjusted. */
#endif
        break;

    case ZSTD_greedy:
    case ZSTD_lazy:
    case ZSTD_lazy2:
#if !defined(ZSTD_EXCLUDE_GREEDY_BLOCK_COMPRESSOR) \
 || !defined(ZSTD_EXCLUDE_LAZY_BLOCK_COMPRESSOR) \
 || !defined(ZSTD_EXCLUDE_LAZY2_BLOCK_COMPRESSOR)
        assert(srcSize >= HASH_READ_SIZE);
        if (ms->dedicatedDictSearch) {
            assert(ms->chainTable != NULL);
            ZSTD_dedicatedDictSearch_lazy_loadDictionary(ms, iend-HASH_READ_SIZE);
        } else {
            assert(params->useRowMatchFinder != ZSTD_ps_auto);
            if (params->useRowMatchFinder == ZSTD_ps_enable) {
                size_t const tagTableSize = ((size_t)1 << params->cParams.hashLog);
                ZSTD_memset(ms->tagTable, 0, tagTableSize);
                ZSTD_row_update(ms, iend-HASH_READ_SIZE);
                DEBUGLOG(4, "Using row-based hash table for lazy dict");
            } else {
                ZSTD_insertAndFindFirstIndex(ms, iend-HASH_READ_SIZE);
                DEBUGLOG(4, "Using chain-based hash table for lazy dict");
            }
        }
#else
        assert(0); /* shouldn't be called: cparams should've been adjusted. */
#endif
        break;

    case ZSTD_btlazy2:   /* we want the dictionary table fully sorted */
    case ZSTD_btopt:
    case ZSTD_btultra:
    case ZSTD_btultra2:
#if !defined(ZSTD_EXCLUDE_BTLAZY2_BLOCK_COMPRESSOR) \
 || !defined(ZSTD_EXCLUDE_BTOPT_BLOCK_COMPRESSOR) \
 || !defined(ZSTD_EXCLUDE_BTULTRA_BLOCK_COMPRESSOR)
        assert(srcSize >= HASH_READ_SIZE);
        DEBUGLOG(4, "Fill %u bytes into the Binary Tree", (unsigned)srcSize);
        ZSTD_updateTree(ms, iend-HASH_READ_SIZE, iend);
#else
        assert(0); /* shouldn't be called: cparams should've been adjusted. */
#endif
        break;

    default:
        assert(0);  /* not possible : not a valid strategy id */
    }

    ms->nextToUpdate = (U32)(iend - ms->window.base);
    return 0;
}



static FSE_repeat ZSTD_dictNCountRepeat(short* normalizedCounter, unsigned dictMaxSymbolValue, unsigned maxSymbolValue)
{
    U32 s;
    if (dictMaxSymbolValue < maxSymbolValue) {
        return FSE_repeat_check;
    }
    for (s = 0; s <= maxSymbolValue; ++s) {
        if (normalizedCounter[s] == 0) {
            return FSE_repeat_check;
        }
    }
    return FSE_repeat_valid;
}

size_t ZSTD_loadCEntropy(ZSTD_compressedBlockState_t* bs, void* workspace,
                         const void* const dict, size_t dictSize)
{
    short offcodeNCount[MaxOff+1];
    unsigned offcodeMaxValue = MaxOff;
    const BYTE* dictPtr = (const BYTE*)dict;    /* skip magic num and dict ID */
    const BYTE* const dictEnd = dictPtr + dictSize;
    dictPtr += 8;
    bs->entropy.huf.repeatMode = HUF_repeat_check;

    {   unsigned maxSymbolValue = 255;
        unsigned hasZeroWeights = 1;
        size_t const hufHeaderSize = HUF_readCTable((HUF_CElt*)bs->entropy.huf.CTable, &maxSymbolValue, dictPtr,
            (size_t)(dictEnd-dictPtr), &hasZeroWeights);


        if (!hasZeroWeights && maxSymbolValue == 255)
            bs->entropy.huf.repeatMode = HUF_repeat_valid;

        RETURN_ERROR_IF(HUF_isError(hufHeaderSize), dictionary_corrupted, "");
        dictPtr += hufHeaderSize;
    }

    {   unsigned offcodeLog;
        size_t const offcodeHeaderSize = FSE_readNCount(offcodeNCount, &offcodeMaxValue, &offcodeLog, dictPtr, (size_t)(dictEnd-dictPtr));
        RETURN_ERROR_IF(FSE_isError(offcodeHeaderSize), dictionary_corrupted, "");
        RETURN_ERROR_IF(offcodeLog > OffFSELog, dictionary_corrupted, "");

        RETURN_ERROR_IF(FSE_isError(FSE_buildCTable_wksp(
                bs->entropy.fse.offcodeCTable,
                offcodeNCount, MaxOff, offcodeLog,
                workspace, HUF_WORKSPACE_SIZE)),
            dictionary_corrupted, "");

        dictPtr += offcodeHeaderSize;
    }

    {   short matchlengthNCount[MaxML+1];
        unsigned matchlengthMaxValue = MaxML, matchlengthLog;
        size_t const matchlengthHeaderSize = FSE_readNCount(matchlengthNCount, &matchlengthMaxValue, &matchlengthLog, dictPtr, (size_t)(dictEnd-dictPtr));
        RETURN_ERROR_IF(FSE_isError(matchlengthHeaderSize), dictionary_corrupted, "");
        RETURN_ERROR_IF(matchlengthLog > MLFSELog, dictionary_corrupted, "");

        RETURN_ERROR_IF(FSE_isError(FSE_buildCTable_wksp(
                bs->entropy.fse.matchlengthCTable,
                matchlengthNCount, MaxML, matchlengthLog,
                workspace, HUF_WORKSPACE_SIZE)),
            dictionary_corrupted, "");
        bs->entropy.fse.matchlength_repeatMode = ZSTD_dictNCountRepeat(matchlengthNCount, matchlengthMaxValue, MaxML);
        dictPtr += matchlengthHeaderSize;
    }

    {   short litlengthNCount[MaxLL+1];
        unsigned litlengthMaxValue = MaxLL, litlengthLog;
        size_t const litlengthHeaderSize = FSE_readNCount(litlengthNCount, &litlengthMaxValue, &litlengthLog, dictPtr, (size_t)(dictEnd-dictPtr));
        RETURN_ERROR_IF(FSE_isError(litlengthHeaderSize), dictionary_corrupted, "");
        RETURN_ERROR_IF(litlengthLog > LLFSELog, dictionary_corrupted, "");

        RETURN_ERROR_IF(FSE_isError(FSE_buildCTable_wksp(
                bs->entropy.fse.litlengthCTable,
                litlengthNCount, MaxLL, litlengthLog,
                workspace, HUF_WORKSPACE_SIZE)),
            dictionary_corrupted, "");
        bs->entropy.fse.litlength_repeatMode = ZSTD_dictNCountRepeat(litlengthNCount, litlengthMaxValue, MaxLL);
        dictPtr += litlengthHeaderSize;
    }

    RETURN_ERROR_IF(dictPtr+12 > dictEnd, dictionary_corrupted, "");
    bs->rep[0] = MEM_readLE32(dictPtr+0);
    bs->rep[1] = MEM_readLE32(dictPtr+4);
    bs->rep[2] = MEM_readLE32(dictPtr+8);
    dictPtr += 12;

    {   size_t const dictContentSize = (size_t)(dictEnd - dictPtr);
        U32 offcodeMax = MaxOff;
        if (dictContentSize <= ((U32)-1) - 128 KB) {
            U32 const maxOffset = (U32)dictContentSize + 128 KB; /* The maximum offset that must be supported */
            offcodeMax = ZSTD_highbit32(maxOffset); /* Calculate minimum offset code required to represent maxOffset */
        }

        bs->entropy.fse.offcode_repeatMode = ZSTD_dictNCountRepeat(offcodeNCount, offcodeMaxValue, MIN(offcodeMax, MaxOff));


        FORWARD_IF_ERROR(ZSTD_checkDictionaryRepCodes(bs->rep, dictContentSize), "");
    }

    return (size_t)(dictPtr - (const BYTE*)dict);
}



static size_t ZSTD_loadZstdDictionary(ZSTD_compressedBlockState_t* bs,
                                      ZSTD_MatchState_t* ms,
                                      ZSTD_cwksp* ws,
                                      ZSTD_CCtx_params const* params,
                                      const void* dict, size_t dictSize,
                                      ZSTD_dictTableLoadMethod_e dtlm,
                                      ZSTD_tableFillPurpose_e tfp,
                                      void* workspace,
                                      U32* dictIDPtr)
{
    const BYTE* dictPtr = (const BYTE*)dict;
    const BYTE* const dictEnd = dictPtr + dictSize;
    U32 dictID;
    size_t eSize;
    ZSTD_STATIC_ASSERT(HUF_WORKSPACE_SIZE >= (1<<MAX(MLFSELog,LLFSELog)));
    assert(dictSize >= 8);
    assert(MEM_readLE32(dictPtr) == ZSTD_MAGIC_DICTIONARY);

    dictID = params->fParams.noDictIDFlag ? 0 :  MEM_readLE32(dictPtr + 4 /* skip magic number */ );
    eSize = ZSTD_loadCEntropy(bs, workspace, dict, dictSize);
    FORWARD_IF_ERROR(eSize, "ZSTD_loadCEntropy failed");
    dictPtr += eSize;

    {
        size_t const dictContentSize = (size_t)(dictEnd - dictPtr);
        FORWARD_IF_ERROR(ZSTD_loadDictionaryContent(
            ms, NULL, ws, params, dictPtr, dictContentSize, dtlm, tfp), "");
    }
    if (tfp == ZSTD_tfp_forCDict) {

        U32 const loadedDictSize = (U32)(ms->window.nextSrc - ms->window.base) - ms->window.lowLimit;
        assert((U32)(ms->window.nextSrc - ms->window.base) >= ms->window.lowLimit);
        FORWARD_IF_ERROR(ZSTD_checkDictionaryRepCodes(bs->rep, loadedDictSize), "");
    }
    *dictIDPtr = dictID;
    return 0;
}


static size_t
ZSTD_compress_insertDictionary(ZSTD_compressedBlockState_t* bs,
                               ZSTD_MatchState_t* ms,
                               ldmState_t* ls,
                               ZSTD_cwksp* ws,
                         const ZSTD_CCtx_params* params,
                         const void* dict, size_t dictSize,
                               ZSTD_dictContentType_e dictContentType,
                               ZSTD_dictTableLoadMethod_e dtlm,
                               ZSTD_tableFillPurpose_e tfp,
                               void* workspace,
                               U32* dictIDPtr)
{
    DEBUGLOG(4, "ZSTD_compress_insertDictionary (dictSize=%u)", (U32)dictSize);
    *dictIDPtr = 0;
    if ((dict==NULL) || (dictSize<8)) {
        RETURN_ERROR_IF(dictContentType == ZSTD_dct_fullDict, dictionary_wrong, "");
        return 0;
    }

    ZSTD_reset_compressedBlockState(bs);


    if (dictContentType == ZSTD_dct_rawContent)
        return ZSTD_loadDictionaryContent(ms, ls, ws, params, dict, dictSize, dtlm, tfp);

    if (MEM_readLE32(dict) != ZSTD_MAGIC_DICTIONARY) {
        if (dictContentType == ZSTD_dct_auto) {
            DEBUGLOG(4, "raw content dictionary detected");
            return ZSTD_loadDictionaryContent(
                ms, ls, ws, params, dict, dictSize, dtlm, tfp);
        }
        RETURN_ERROR_IF(dictContentType == ZSTD_dct_fullDict, dictionary_wrong, "");
        assert(0);   /* impossible */
    }


    return ZSTD_loadZstdDictionary(
        bs, ms, ws, params, dict, dictSize, dtlm, tfp, workspace, dictIDPtr);
}

#define ZSTD_USE_CDICT_PARAMS_SRCSIZE_CUTOFF (128 KB)
#define ZSTD_USE_CDICT_PARAMS_DICTSIZE_MULTIPLIER (6ULL)


static size_t ZSTD_compressBegin_internal(ZSTD_CCtx* cctx,
                                    const void* dict, size_t dictSize,
                                    ZSTD_dictContentType_e dictContentType,
                                    ZSTD_dictTableLoadMethod_e dtlm,
                                    const ZSTD_CDict* cdict,
                                    const ZSTD_CCtx_params* params, U64 pledgedSrcSize,
                                    ZSTD_buffered_policy_e zbuff)
{
    size_t const dictContentSize = cdict ? cdict->dictContentSize : dictSize;
#if ZSTD_TRACE
    cctx->traceCtx = (ZSTD_trace_compress_begin != NULL) ? ZSTD_trace_compress_begin(cctx) : 0;
#endif
    DEBUGLOG(4, "ZSTD_compressBegin_internal: wlog=%u", params->cParams.windowLog);

    assert(!ZSTD_isError(ZSTD_checkCParams(params->cParams)));
    assert(!((dict) && (cdict)));  /* either dict or cdict, not both */
    if ( (cdict)
      && (cdict->dictContentSize > 0)
      && ( pledgedSrcSize < ZSTD_USE_CDICT_PARAMS_SRCSIZE_CUTOFF
        || pledgedSrcSize < cdict->dictContentSize * ZSTD_USE_CDICT_PARAMS_DICTSIZE_MULTIPLIER
        || pledgedSrcSize == ZSTD_CONTENTSIZE_UNKNOWN
        || cdict->compressionLevel == 0)
      && (params->attachDictPref != ZSTD_dictForceLoad) ) {
        return ZSTD_resetCCtx_usingCDict(cctx, cdict, params, pledgedSrcSize, zbuff);
    }

    FORWARD_IF_ERROR( ZSTD_resetCCtx_internal(cctx, params, pledgedSrcSize,
                                     dictContentSize,
                                     ZSTDcrp_makeClean, zbuff) , "");
    {   U32 dictID = 0;
        size_t const dictStatus = cdict ?
                ZSTD_compress_insertDictionary(
                        cctx->blockState.prevCBlock, &cctx->blockState.matchState,
                        &cctx->ldmState, &cctx->workspace, &cctx->appliedParams, cdict->dictContent,
                        cdict->dictContentSize, cdict->dictContentType, dtlm,
                        ZSTD_tfp_forCCtx, cctx->tmpWorkspace, &dictID)
              : ZSTD_compress_insertDictionary(
                        cctx->blockState.prevCBlock, &cctx->blockState.matchState,
                        &cctx->ldmState, &cctx->workspace, &cctx->appliedParams, dict, dictSize,
                        dictContentType, dtlm, ZSTD_tfp_forCCtx, cctx->tmpWorkspace, &dictID);
        FORWARD_IF_ERROR(dictStatus, "ZSTD_compress_insertDictionary failed");
        cctx->dictID = dictID;
        cctx->dictContentSize = dictContentSize;
    }
    return 0;
}

size_t ZSTD_compressBegin_advanced_internal(ZSTD_CCtx* cctx,
                                    const void* dict, size_t dictSize,
                                    ZSTD_dictContentType_e dictContentType,
                                    ZSTD_dictTableLoadMethod_e dtlm,
                                    const ZSTD_CDict* cdict,
                                    const ZSTD_CCtx_params* params,
                                    unsigned long long pledgedSrcSize)
{
    DEBUGLOG(4, "ZSTD_compressBegin_advanced_internal: wlog=%u", params->cParams.windowLog);

    FORWARD_IF_ERROR( ZSTD_checkCParams(params->cParams) , "");
    return ZSTD_compressBegin_internal(cctx,
                                       dict, dictSize, dictContentType, dtlm,
                                       cdict,
                                       params, pledgedSrcSize,
                                       ZSTDb_not_buffered);
}


size_t ZSTD_compressBegin_advanced(ZSTD_CCtx* cctx,
                             const void* dict, size_t dictSize,
                                   ZSTD_parameters params, unsigned long long pledgedSrcSize)
{
    ZSTD_CCtx_params cctxParams;
    ZSTD_CCtxParams_init_internal(&cctxParams, &params, ZSTD_NO_CLEVEL);
    return ZSTD_compressBegin_advanced_internal(cctx,
                                            dict, dictSize, ZSTD_dct_auto, ZSTD_dtlm_fast,
                                            NULL /*cdict*/,
                                            &cctxParams, pledgedSrcSize);
}

static size_t
ZSTD_compressBegin_usingDict_deprecated(ZSTD_CCtx* cctx, const void* dict, size_t dictSize, int compressionLevel)
{
    ZSTD_CCtx_params cctxParams;
    {   ZSTD_parameters const params = ZSTD_getParams_internal(compressionLevel, ZSTD_CONTENTSIZE_UNKNOWN, dictSize, ZSTD_cpm_noAttachDict);
        ZSTD_CCtxParams_init_internal(&cctxParams, &params, (compressionLevel == 0) ? ZSTD_CLEVEL_DEFAULT : compressionLevel);
    }
    DEBUGLOG(4, "ZSTD_compressBegin_usingDict (dictSize=%u)", (unsigned)dictSize);
    return ZSTD_compressBegin_internal(cctx, dict, dictSize, ZSTD_dct_auto, ZSTD_dtlm_fast, NULL,
                                       &cctxParams, ZSTD_CONTENTSIZE_UNKNOWN, ZSTDb_not_buffered);
}

size_t
ZSTD_compressBegin_usingDict(ZSTD_CCtx* cctx, const void* dict, size_t dictSize, int compressionLevel)
{
    return ZSTD_compressBegin_usingDict_deprecated(cctx, dict, dictSize, compressionLevel);
}

size_t ZSTD_compressBegin(ZSTD_CCtx* cctx, int compressionLevel)
{
    return ZSTD_compressBegin_usingDict_deprecated(cctx, NULL, 0, compressionLevel);
}



static size_t ZSTD_writeEpilogue(ZSTD_CCtx* cctx, void* dst, size_t dstCapacity)
{
    BYTE* const ostart = (BYTE*)dst;
    BYTE* op = ostart;

    DEBUGLOG(4, "ZSTD_writeEpilogue");
    RETURN_ERROR_IF(cctx->stage == ZSTDcs_created, stage_wrong, "init missing");


    if (cctx->stage == ZSTDcs_init) {
        size_t fhSize = ZSTD_writeFrameHeader(dst, dstCapacity, &cctx->appliedParams, 0, 0);
        FORWARD_IF_ERROR(fhSize, "ZSTD_writeFrameHeader failed");
        dstCapacity -= fhSize;
        op += fhSize;
        cctx->stage = ZSTDcs_ongoing;
    }

    if (cctx->stage != ZSTDcs_ending) {

        U32 const cBlockHeader24 = 1 /* last block */ + (((U32)bt_raw)<<1) + 0;
        ZSTD_STATIC_ASSERT(ZSTD_BLOCKHEADERSIZE == 3);
        RETURN_ERROR_IF(dstCapacity<3, dstSize_tooSmall, "no room for epilogue");
        MEM_writeLE24(op, cBlockHeader24);
        op += ZSTD_blockHeaderSize;
        dstCapacity -= ZSTD_blockHeaderSize;
    }

    if (cctx->appliedParams.fParams.checksumFlag) {
        U32 const checksum = (U32) XXH64_digest(&cctx->xxhState);
        RETURN_ERROR_IF(dstCapacity<4, dstSize_tooSmall, "no room for checksum");
        DEBUGLOG(4, "ZSTD_writeEpilogue: write checksum : %08X", (unsigned)checksum);
        MEM_writeLE32(op, checksum);
        op += 4;
    }

    cctx->stage = ZSTDcs_created;  /* return to "created but no init" status */
    return (size_t)(op-ostart);
}

void ZSTD_CCtx_trace(ZSTD_CCtx* cctx, size_t extraCSize)
{
#if ZSTD_TRACE
    if (cctx->traceCtx && ZSTD_trace_compress_end != NULL) {
        int const streaming = cctx->inBuffSize > 0 || cctx->outBuffSize > 0 || cctx->appliedParams.nbWorkers > 0;
        ZSTD_Trace trace;
        ZSTD_memset(&trace, 0, sizeof(trace));
        trace.version = ZSTD_VERSION_NUMBER;
        trace.streaming = streaming;
        trace.dictionaryID = cctx->dictID;
        trace.dictionarySize = cctx->dictContentSize;
        trace.uncompressedSize = cctx->consumedSrcSize;
        trace.compressedSize = cctx->producedCSize + extraCSize;
        trace.params = &cctx->appliedParams;
        trace.cctx = cctx;
        ZSTD_trace_compress_end(cctx->traceCtx, &trace);
    }
    cctx->traceCtx = 0;
#else
    (void)cctx;
    (void)extraCSize;
#endif
}

size_t ZSTD_compressEnd_public(ZSTD_CCtx* cctx,
                               void* dst, size_t dstCapacity,
                         const void* src, size_t srcSize)
{
    size_t endResult;
    size_t const cSize = ZSTD_compressContinue_internal(cctx,
                                dst, dstCapacity, src, srcSize,
                                1 /* frame mode */, 1 /* last chunk */);
    FORWARD_IF_ERROR(cSize, "ZSTD_compressContinue_internal failed");
    endResult = ZSTD_writeEpilogue(cctx, (char*)dst + cSize, dstCapacity-cSize);
    FORWARD_IF_ERROR(endResult, "ZSTD_writeEpilogue failed");
    assert(!(cctx->appliedParams.fParams.contentSizeFlag && cctx->pledgedSrcSizePlusOne == 0));
    if (cctx->pledgedSrcSizePlusOne != 0) {  /* control src size */
        ZSTD_STATIC_ASSERT(ZSTD_CONTENTSIZE_UNKNOWN == (unsigned long long)-1);
        DEBUGLOG(4, "end of frame : controlling src size");
        RETURN_ERROR_IF(
            cctx->pledgedSrcSizePlusOne != cctx->consumedSrcSize+1,
            srcSize_wrong,
             "error : pledgedSrcSize = %u, while realSrcSize = %u",
            (unsigned)cctx->pledgedSrcSizePlusOne-1,
            (unsigned)cctx->consumedSrcSize);
    }
    ZSTD_CCtx_trace(cctx, endResult);
    return cSize + endResult;
}


size_t ZSTD_compressEnd(ZSTD_CCtx* cctx,
                        void* dst, size_t dstCapacity,
                  const void* src, size_t srcSize)
{
    return ZSTD_compressEnd_public(cctx, dst, dstCapacity, src, srcSize);
}

size_t ZSTD_compress_advanced (ZSTD_CCtx* cctx,
                               void* dst, size_t dstCapacity,
                         const void* src, size_t srcSize,
                         const void* dict,size_t dictSize,
                               ZSTD_parameters params)
{
    DEBUGLOG(4, "ZSTD_compress_advanced");
    FORWARD_IF_ERROR(ZSTD_checkCParams(params.cParams), "");
    ZSTD_CCtxParams_init_internal(&cctx->simpleApiParams, &params, ZSTD_NO_CLEVEL);
    return ZSTD_compress_advanced_internal(cctx,
                                           dst, dstCapacity,
                                           src, srcSize,
                                           dict, dictSize,
                                           &cctx->simpleApiParams);
}


size_t ZSTD_compress_advanced_internal(
        ZSTD_CCtx* cctx,
        void* dst, size_t dstCapacity,
        const void* src, size_t srcSize,
        const void* dict,size_t dictSize,
        const ZSTD_CCtx_params* params)
{
    DEBUGLOG(4, "ZSTD_compress_advanced_internal (srcSize:%u)", (unsigned)srcSize);
    FORWARD_IF_ERROR( ZSTD_compressBegin_internal(cctx,
                         dict, dictSize, ZSTD_dct_auto, ZSTD_dtlm_fast, NULL,
                         params, srcSize, ZSTDb_not_buffered) , "");
    return ZSTD_compressEnd_public(cctx, dst, dstCapacity, src, srcSize);
}

size_t ZSTD_compress_usingDict(ZSTD_CCtx* cctx,
                               void* dst, size_t dstCapacity,
                         const void* src, size_t srcSize,
                         const void* dict, size_t dictSize,
                               int compressionLevel)
{
    {
        ZSTD_parameters const params = ZSTD_getParams_internal(compressionLevel, srcSize, dict ? dictSize : 0, ZSTD_cpm_noAttachDict);
        assert(params.fParams.contentSizeFlag == 1);
        ZSTD_CCtxParams_init_internal(&cctx->simpleApiParams, &params, (compressionLevel == 0) ? ZSTD_CLEVEL_DEFAULT: compressionLevel);
    }
    DEBUGLOG(4, "ZSTD_compress_usingDict (srcSize=%u)", (unsigned)srcSize);
    return ZSTD_compress_advanced_internal(cctx, dst, dstCapacity, src, srcSize, dict, dictSize, &cctx->simpleApiParams);
}

size_t ZSTD_compressCCtx(ZSTD_CCtx* cctx,
                         void* dst, size_t dstCapacity,
                   const void* src, size_t srcSize,
                         int compressionLevel)
{
    DEBUGLOG(4, "ZSTD_compressCCtx (srcSize=%u)", (unsigned)srcSize);
    assert(cctx != NULL);
    return ZSTD_compress_usingDict(cctx, dst, dstCapacity, src, srcSize, NULL, 0, compressionLevel);
}

size_t ZSTD_compress(void* dst, size_t dstCapacity,
               const void* src, size_t srcSize,
                     int compressionLevel)
{
    size_t result;
#if ZSTD_COMPRESS_HEAPMODE
    ZSTD_CCtx* cctx = ZSTD_createCCtx();
    RETURN_ERROR_IF(!cctx, memory_allocation, "ZSTD_createCCtx failed");
    result = ZSTD_compressCCtx(cctx, dst, dstCapacity, src, srcSize, compressionLevel);
    ZSTD_freeCCtx(cctx);
#else
    ZSTD_CCtx ctxBody;
    ZSTD_initCCtx(&ctxBody, ZSTD_defaultCMem);
    result = ZSTD_compressCCtx(&ctxBody, dst, dstCapacity, src, srcSize, compressionLevel);
    ZSTD_freeCCtxContent(&ctxBody);   /* can't free ctxBody itself, as it's on stack; free only heap content */
#endif
    return result;
}





static size_t ZSTD_estimateCDictSize_internal(size_t dictSize,
                                             size_t matchStateSize,
                                             ZSTD_dictLoadMethod_e dictLoadMethod)
{
    size_t const baseSize = ZSTD_cwksp_alloc_size(sizeof(ZSTD_CDict))
                          + ZSTD_cwksp_alloc_size(HUF_WORKSPACE_SIZE)
                          + matchStateSize;
    if (dictLoadMethod == ZSTD_dlm_byRef) return baseSize;
    {
        size_t const alignedDictSize = ZSTD_cwksp_align(dictSize, sizeof(void*));
        size_t const dictAllocSize = ZSTD_cwksp_alloc_size(alignedDictSize);
        RETURN_ERROR_IF(alignedDictSize < dictSize || dictAllocSize < alignedDictSize,
                        memory_allocation, "CDict size overflow");
        RETURN_ERROR_IF(dictAllocSize > (size_t)-1 - baseSize,
                        memory_allocation, "CDict workspace size overflow");
        return baseSize + dictAllocSize;
    }
}


size_t ZSTD_estimateCDictSize_advanced(
        size_t dictSize, ZSTD_compressionParameters cParams,
        ZSTD_dictLoadMethod_e dictLoadMethod)
{
    DEBUGLOG(5, "sizeof(ZSTD_CDict) : %u", (unsigned)sizeof(ZSTD_CDict));

    return ZSTD_estimateCDictSize_internal(dictSize,
            ZSTD_sizeof_matchState(&cParams, ZSTD_resolveRowMatchFinderMode(ZSTD_ps_auto, &cParams),
 1, /* forCCtx */ 0),
            dictLoadMethod);
}

size_t ZSTD_estimateCDictSize(size_t dictSize, int compressionLevel)
{
    ZSTD_compressionParameters const cParams = ZSTD_getCParams_internal(compressionLevel, ZSTD_CONTENTSIZE_UNKNOWN, dictSize, ZSTD_cpm_createCDict);
    return ZSTD_estimateCDictSize_advanced(dictSize, cParams, ZSTD_dlm_byCopy);
}

size_t ZSTD_sizeof_CDict(const ZSTD_CDict* cdict)
{
    if (cdict==NULL) return 0;   /* support sizeof on NULL */
    DEBUGLOG(5, "sizeof(*cdict) : %u", (unsigned)sizeof(*cdict));

    return (cdict->workspace.workspace == cdict ? 0 : sizeof(*cdict))
        + ZSTD_cwksp_sizeof(&cdict->workspace);
}

static size_t ZSTD_initCDict_internal(
                    ZSTD_CDict* cdict,
              const void* dictBuffer, size_t dictSize,
                    ZSTD_dictLoadMethod_e dictLoadMethod,
                    ZSTD_dictContentType_e dictContentType,
                    ZSTD_CCtx_params params)
{
    DEBUGLOG(3, "ZSTD_initCDict_internal (dictContentType:%u)", (unsigned)dictContentType);
    assert(!ZSTD_checkCParams(params.cParams));
    cdict->matchState.cParams = params.cParams;
    cdict->matchState.dedicatedDictSearch = params.enableDedicatedDictSearch;
    if ((dictLoadMethod == ZSTD_dlm_byRef) || (!dictBuffer) || (!dictSize)) {
        cdict->dictContent = dictBuffer;
    } else {
         void *internalBuffer = ZSTD_cwksp_reserve_object(&cdict->workspace, ZSTD_cwksp_align(dictSize, sizeof(void*)));
        RETURN_ERROR_IF(!internalBuffer, memory_allocation, "NULL pointer!");
        cdict->dictContent = internalBuffer;
        ZSTD_memcpy(internalBuffer, dictBuffer, dictSize);
    }
    cdict->dictContentSize = dictSize;
    cdict->dictContentType = dictContentType;

    cdict->entropyWorkspace = (U32*)ZSTD_cwksp_reserve_object(&cdict->workspace, HUF_WORKSPACE_SIZE);



    ZSTD_reset_compressedBlockState(&cdict->cBlockState);
    FORWARD_IF_ERROR(ZSTD_reset_matchState(
        &cdict->matchState,
        &cdict->workspace,
        &params.cParams,
        params.useRowMatchFinder,
        ZSTDcrp_makeClean,
        ZSTDirp_reset,
        ZSTD_resetTarget_CDict), "");

    {   params.compressionLevel = ZSTD_CLEVEL_DEFAULT;
        params.fParams.contentSizeFlag = 1;
        {   U32 dictID = 0;
            size_t const dictStatus = ZSTD_compress_insertDictionary(
                    &cdict->cBlockState, &cdict->matchState, NULL, &cdict->workspace,
                    &params, cdict->dictContent, cdict->dictContentSize,
                    dictContentType, ZSTD_dtlm_full, ZSTD_tfp_forCDict, cdict->entropyWorkspace,
                    &dictID);
            FORWARD_IF_ERROR(dictStatus, "ZSTD_compress_insertDictionary failed");
            cdict->dictID = dictID;
        }
    }

    return 0;
}

static ZSTD_CDict*
ZSTD_createCDict_advanced_internal(size_t dictSize,
                                ZSTD_dictLoadMethod_e dictLoadMethod,
                                ZSTD_compressionParameters cParams,
                                ZSTD_ParamSwitch_e useRowMatchFinder,
                                int enableDedicatedDictSearch,
                                ZSTD_customMem customMem)
{
    if ((!customMem.customAlloc) ^ (!customMem.customFree)) return NULL;
    DEBUGLOG(3, "ZSTD_createCDict_advanced_internal (dictSize=%u)", (unsigned)dictSize);

    {   size_t const workspaceSize = ZSTD_estimateCDictSize_internal(dictSize,
            ZSTD_sizeof_matchState(&cParams, useRowMatchFinder, enableDedicatedDictSearch, /* forCCtx */ 0),
            dictLoadMethod);
        void* workspace;
        ZSTD_cwksp ws;
        ZSTD_CDict* cdict;

        if (ZSTD_isError(workspaceSize)) return NULL;
        workspace = ZSTD_customMalloc(workspaceSize, customMem);
        if (!workspace) {
            ZSTD_customFree(workspace, customMem);
            return NULL;
        }

        ZSTD_cwksp_init(&ws, workspace, workspaceSize, ZSTD_cwksp_dynamic_alloc);

        cdict = (ZSTD_CDict*)ZSTD_cwksp_reserve_object(&ws, sizeof(ZSTD_CDict));
        assert(cdict != NULL);
        ZSTD_cwksp_move(&cdict->workspace, &ws);
        cdict->customMem = customMem;
        cdict->compressionLevel = ZSTD_NO_CLEVEL; /* signals advanced API usage */
        cdict->useRowMatchFinder = useRowMatchFinder;
        return cdict;
    }
}

ZSTD_CDict* ZSTD_createCDict_advanced(const void* dictBuffer, size_t dictSize,
                                      ZSTD_dictLoadMethod_e dictLoadMethod,
                                      ZSTD_dictContentType_e dictContentType,
                                      ZSTD_compressionParameters cParams,
                                      ZSTD_customMem customMem)
{
    ZSTD_CCtx_params cctxParams;
    ZSTD_memset(&cctxParams, 0, sizeof(cctxParams));
    DEBUGLOG(3, "ZSTD_createCDict_advanced, dictSize=%u, mode=%u", (unsigned)dictSize, (unsigned)dictContentType);
    ZSTD_CCtxParams_init(&cctxParams, 0);
    cctxParams.cParams = cParams;
    cctxParams.customMem = customMem;
    return ZSTD_createCDict_advanced2(
        dictBuffer, dictSize,
        dictLoadMethod, dictContentType,
        &cctxParams, customMem);
}


static size_t ZSTD_createCDict_advanced2_internal(
        ZSTD_CDict** cdictPtr,
        const void* dict, size_t dictSize,
        ZSTD_dictLoadMethod_e dictLoadMethod,
        ZSTD_dictContentType_e dictContentType,
        const ZSTD_CCtx_params* originalCctxParams,
        ZSTD_customMem customMem)
{
    ZSTD_CCtx_params cctxParams = *originalCctxParams;
    ZSTD_compressionParameters cParams;
    ZSTD_CDict* cdict;

    *cdictPtr = NULL;
    DEBUGLOG(3, "ZSTD_createCDict_advanced2, dictSize=%u, mode=%u", (unsigned)dictSize, (unsigned)dictContentType);
    RETURN_ERROR_IF((!customMem.customAlloc) ^ (!customMem.customFree),
                    parameter_combination_unsupported, "Invalid custom allocator");

    if (cctxParams.enableDedicatedDictSearch) {
        cParams = ZSTD_dedicatedDictSearch_getCParams(
            cctxParams.compressionLevel, dictSize);
        ZSTD_overrideCParams(&cParams, &cctxParams.cParams);
    } else {
        cParams = ZSTD_getCParamsFromCCtxParams(
            &cctxParams, ZSTD_CONTENTSIZE_UNKNOWN, dictSize, ZSTD_cpm_createCDict);
    }

    if (!ZSTD_dedicatedDictSearch_isSupported(&cParams)) {

        cctxParams.enableDedicatedDictSearch = 0;
        cParams = ZSTD_getCParamsFromCCtxParams(
            &cctxParams, ZSTD_CONTENTSIZE_UNKNOWN, dictSize, ZSTD_cpm_createCDict);
    }

    DEBUGLOG(3, "ZSTD_createCDict_advanced2: DedicatedDictSearch=%u", cctxParams.enableDedicatedDictSearch);
    cctxParams.cParams = cParams;
    cctxParams.useRowMatchFinder = ZSTD_resolveRowMatchFinderMode(cctxParams.useRowMatchFinder, &cParams);

    cdict = ZSTD_createCDict_advanced_internal(dictSize,
                        dictLoadMethod, cctxParams.cParams,
                        cctxParams.useRowMatchFinder, cctxParams.enableDedicatedDictSearch,
                        customMem);

    RETURN_ERROR_IF(!cdict, memory_allocation, "Could not allocate CDict");
    {   size_t const err = ZSTD_initCDict_internal(cdict,
                                dict, dictSize,
                                dictLoadMethod, dictContentType,
                                cctxParams);
        if (ZSTD_isError(err)) {
            ZSTD_freeCDict(cdict);
            return err;
        }
    }

    *cdictPtr = cdict;
    return 0;
}

ZSTD_CDict* ZSTD_createCDict_advanced2(
        const void* dict, size_t dictSize,
        ZSTD_dictLoadMethod_e dictLoadMethod,
        ZSTD_dictContentType_e dictContentType,
        const ZSTD_CCtx_params* originalCctxParams,
        ZSTD_customMem customMem)
{
    ZSTD_CDict* cdict;
    size_t const err = ZSTD_createCDict_advanced2_internal(
            &cdict, dict, dictSize, dictLoadMethod, dictContentType,
            originalCctxParams, customMem);
    if (ZSTD_isError(err)) return NULL;
    return cdict;
}

ZSTD_CDict* ZSTD_createCDict(const void* dict, size_t dictSize, int compressionLevel)
{
    ZSTD_compressionParameters cParams = ZSTD_getCParams_internal(compressionLevel, ZSTD_CONTENTSIZE_UNKNOWN, dictSize, ZSTD_cpm_createCDict);
    ZSTD_CDict* const cdict = ZSTD_createCDict_advanced(dict, dictSize,
                                                  ZSTD_dlm_byCopy, ZSTD_dct_auto,
                                                  cParams, ZSTD_defaultCMem);
    if (cdict)
        cdict->compressionLevel = (compressionLevel == 0) ? ZSTD_CLEVEL_DEFAULT : compressionLevel;
    return cdict;
}

ZSTD_CDict* ZSTD_createCDict_byReference(const void* dict, size_t dictSize, int compressionLevel)
{
    ZSTD_compressionParameters cParams = ZSTD_getCParams_internal(compressionLevel, ZSTD_CONTENTSIZE_UNKNOWN, dictSize, ZSTD_cpm_createCDict);
    ZSTD_CDict* const cdict = ZSTD_createCDict_advanced(dict, dictSize,
                                     ZSTD_dlm_byRef, ZSTD_dct_auto,
                                     cParams, ZSTD_defaultCMem);
    if (cdict)
        cdict->compressionLevel = (compressionLevel == 0) ? ZSTD_CLEVEL_DEFAULT : compressionLevel;
    return cdict;
}

size_t ZSTD_freeCDict(ZSTD_CDict* cdict)
{
    if (cdict==NULL) return 0;   /* support free on NULL */
    {   ZSTD_customMem const cMem = cdict->customMem;
        int cdictInWorkspace = ZSTD_cwksp_owns_buffer(&cdict->workspace, cdict);
        ZSTD_cwksp_free(&cdict->workspace, cMem);
        if (!cdictInWorkspace) {
            ZSTD_customFree(cdict, cMem);
        }
        return 0;
    }
}


const ZSTD_CDict* ZSTD_initStaticCDict(
                                 void* workspace, size_t workspaceSize,
                           const void* dict, size_t dictSize,
                                 ZSTD_dictLoadMethod_e dictLoadMethod,
                                 ZSTD_dictContentType_e dictContentType,
                                 ZSTD_compressionParameters cParams)
{
    ZSTD_ParamSwitch_e const useRowMatchFinder = ZSTD_resolveRowMatchFinderMode(ZSTD_ps_auto, &cParams);

    size_t const matchStateSize = ZSTD_sizeof_matchState(&cParams, useRowMatchFinder, /* enableDedicatedDictSearch */ 1, /* forCCtx */ 0);
    size_t const neededSize = ZSTD_estimateCDictSize_internal(dictSize, matchStateSize, dictLoadMethod);
    ZSTD_CDict* cdict;
    ZSTD_CCtx_params params;

    DEBUGLOG(4, "ZSTD_initStaticCDict (dictSize==%u)", (unsigned)dictSize);
    if ((size_t)workspace & 7) return NULL;  /* 8-aligned */
    if (ZSTD_isError(neededSize) || workspaceSize < neededSize) return NULL;

    {
        ZSTD_cwksp ws;
        ZSTD_cwksp_init(&ws, workspace, workspaceSize, ZSTD_cwksp_static_alloc);
        cdict = (ZSTD_CDict*)ZSTD_cwksp_reserve_object(&ws, sizeof(ZSTD_CDict));
        if (cdict == NULL) return NULL;
        ZSTD_cwksp_move(&cdict->workspace, &ws);
    }

    ZSTD_CCtxParams_init(&params, 0);
    params.cParams = cParams;
    params.useRowMatchFinder = useRowMatchFinder;
    cdict->useRowMatchFinder = useRowMatchFinder;
    cdict->compressionLevel = ZSTD_NO_CLEVEL;

    if (ZSTD_isError( ZSTD_initCDict_internal(cdict,
                                              dict, dictSize,
                                              dictLoadMethod, dictContentType,
                                              params) ))
        return NULL;

    return cdict;
}

ZSTD_compressionParameters ZSTD_getCParamsFromCDict(const ZSTD_CDict* cdict)
{
    assert(cdict != NULL);
    return cdict->matchState.cParams;
}


unsigned ZSTD_getDictID_fromCDict(const ZSTD_CDict* cdict)
{
    if (cdict==NULL) return 0;
    return cdict->dictID;
}


static size_t ZSTD_compressBegin_usingCDict_internal(
    ZSTD_CCtx* const cctx, const ZSTD_CDict* const cdict,
    ZSTD_frameParameters const fParams, unsigned long long const pledgedSrcSize)
{
    ZSTD_CCtx_params cctxParams;
    DEBUGLOG(4, "ZSTD_compressBegin_usingCDict_internal");
    RETURN_ERROR_IF(cdict==NULL, dictionary_wrong, "NULL pointer!");

    {
        ZSTD_parameters params;
        params.fParams = fParams;
        params.cParams = ( pledgedSrcSize < ZSTD_USE_CDICT_PARAMS_SRCSIZE_CUTOFF
                        || pledgedSrcSize < cdict->dictContentSize * ZSTD_USE_CDICT_PARAMS_DICTSIZE_MULTIPLIER
                        || pledgedSrcSize == ZSTD_CONTENTSIZE_UNKNOWN
                        || cdict->compressionLevel == 0 ) ?
                ZSTD_getCParamsFromCDict(cdict)
              : ZSTD_getCParams(cdict->compressionLevel,
                                pledgedSrcSize,
                                cdict->dictContentSize);
        ZSTD_CCtxParams_init_internal(&cctxParams, &params, cdict->compressionLevel);
    }

    if (pledgedSrcSize != ZSTD_CONTENTSIZE_UNKNOWN) {
        U32 const limitedSrcSize = (U32)MIN(pledgedSrcSize, 1U << 19);
        U32 const limitedSrcLog = limitedSrcSize > 1 ? ZSTD_highbit32(limitedSrcSize - 1) + 1 : 1;
        cctxParams.cParams.windowLog = MAX(cctxParams.cParams.windowLog, limitedSrcLog);
    }
    return ZSTD_compressBegin_internal(cctx,
                                        NULL, 0, ZSTD_dct_auto, ZSTD_dtlm_fast,
                                        cdict,
                                        &cctxParams, pledgedSrcSize,
                                        ZSTDb_not_buffered);
}



size_t ZSTD_compressBegin_usingCDict_advanced(
    ZSTD_CCtx* const cctx, const ZSTD_CDict* const cdict,
    ZSTD_frameParameters const fParams, unsigned long long const pledgedSrcSize)
{
    return ZSTD_compressBegin_usingCDict_internal(cctx, cdict, fParams, pledgedSrcSize);
}


size_t ZSTD_compressBegin_usingCDict_deprecated(ZSTD_CCtx* cctx, const ZSTD_CDict* cdict)
{
    ZSTD_frameParameters const fParams = { 0 /*content*/, 0 /*checksum*/, 0 /*noDictID*/ };
    return ZSTD_compressBegin_usingCDict_internal(cctx, cdict, fParams, ZSTD_CONTENTSIZE_UNKNOWN);
}

size_t ZSTD_compressBegin_usingCDict(ZSTD_CCtx* cctx, const ZSTD_CDict* cdict)
{
    return ZSTD_compressBegin_usingCDict_deprecated(cctx, cdict);
}


static size_t ZSTD_compress_usingCDict_internal(ZSTD_CCtx* cctx,
                                void* dst, size_t dstCapacity,
                                const void* src, size_t srcSize,
                                const ZSTD_CDict* cdict, ZSTD_frameParameters fParams)
{
    FORWARD_IF_ERROR(ZSTD_compressBegin_usingCDict_internal(cctx, cdict, fParams, srcSize), ""); /* will check if cdict != NULL */
    return ZSTD_compressEnd_public(cctx, dst, dstCapacity, src, srcSize);
}


size_t ZSTD_compress_usingCDict_advanced(ZSTD_CCtx* cctx,
                                void* dst, size_t dstCapacity,
                                const void* src, size_t srcSize,
                                const ZSTD_CDict* cdict, ZSTD_frameParameters fParams)
{
    return ZSTD_compress_usingCDict_internal(cctx, dst, dstCapacity, src, srcSize, cdict, fParams);
}


size_t ZSTD_compress_usingCDict(ZSTD_CCtx* cctx,
                                void* dst, size_t dstCapacity,
                                const void* src, size_t srcSize,
                                const ZSTD_CDict* cdict)
{
    ZSTD_frameParameters const fParams = { 1 /*content*/, 0 /*checksum*/, 0 /*noDictID*/ };
    return ZSTD_compress_usingCDict_internal(cctx, dst, dstCapacity, src, srcSize, cdict, fParams);
}





ZSTD_CStream* ZSTD_createCStream(void)
{
    DEBUGLOG(3, "ZSTD_createCStream");
    return ZSTD_createCStream_advanced(ZSTD_defaultCMem);
}

ZSTD_CStream* ZSTD_initStaticCStream(void *workspace, size_t workspaceSize)
{
    return ZSTD_initStaticCCtx(workspace, workspaceSize);
}

ZSTD_CStream* ZSTD_createCStream_advanced(ZSTD_customMem customMem)
{   /* CStream and CCtx are now same object */
    return ZSTD_createCCtx_advanced(customMem);
}

size_t ZSTD_freeCStream(ZSTD_CStream* zcs)
{
    return ZSTD_freeCCtx(zcs);   /* same object */
}





size_t ZSTD_CStreamInSize(void)  { return ZSTD_BLOCKSIZE_MAX; }

size_t ZSTD_CStreamOutSize(void)
{
    return ZSTD_compressBound(ZSTD_BLOCKSIZE_MAX) + ZSTD_blockHeaderSize + 4 /* 32-bits hash */ ;
}

static ZSTD_CParamMode_e ZSTD_getCParamMode(ZSTD_CDict const* cdict, ZSTD_CCtx_params const* params, U64 pledgedSrcSize)
{
    if (cdict != NULL && ZSTD_shouldAttachDict(cdict, params, pledgedSrcSize))
        return ZSTD_cpm_attachDict;
    else
        return ZSTD_cpm_noAttachDict;
}


size_t ZSTD_resetCStream(ZSTD_CStream* zcs, unsigned long long pss)
{

    U64 const pledgedSrcSize = (pss==0) ? ZSTD_CONTENTSIZE_UNKNOWN : pss;
    DEBUGLOG(4, "ZSTD_resetCStream: pledgedSrcSize = %u", (unsigned)pledgedSrcSize);
    FORWARD_IF_ERROR( ZSTD_CCtx_reset(zcs, ZSTD_reset_session_only) , "");
    FORWARD_IF_ERROR( ZSTD_CCtx_setPledgedSrcSize(zcs, pledgedSrcSize) , "");
    return 0;
}


size_t ZSTD_initCStream_internal(ZSTD_CStream* zcs,
                    const void* dict, size_t dictSize, const ZSTD_CDict* cdict,
                    const ZSTD_CCtx_params* params,
                    unsigned long long pledgedSrcSize)
{
    DEBUGLOG(4, "ZSTD_initCStream_internal");
    FORWARD_IF_ERROR( ZSTD_CCtx_reset(zcs, ZSTD_reset_session_only) , "");
    FORWARD_IF_ERROR( ZSTD_CCtx_setPledgedSrcSize(zcs, pledgedSrcSize) , "");
    assert(!ZSTD_isError(ZSTD_checkCParams(params->cParams)));
    zcs->requestedParams = *params;
    assert(!((dict) && (cdict)));  /* either dict or cdict, not both */
    if (dict) {
        FORWARD_IF_ERROR( ZSTD_CCtx_loadDictionary(zcs, dict, dictSize) , "");
    } else {

        FORWARD_IF_ERROR( ZSTD_CCtx_refCDict(zcs, cdict) , "");
    }
    return 0;
}


size_t ZSTD_initCStream_usingCDict_advanced(ZSTD_CStream* zcs,
                                            const ZSTD_CDict* cdict,
                                            ZSTD_frameParameters fParams,
                                            unsigned long long pledgedSrcSize)
{
    DEBUGLOG(4, "ZSTD_initCStream_usingCDict_advanced");
    FORWARD_IF_ERROR( ZSTD_CCtx_reset(zcs, ZSTD_reset_session_only) , "");
    FORWARD_IF_ERROR( ZSTD_CCtx_setPledgedSrcSize(zcs, pledgedSrcSize) , "");
    zcs->requestedParams.fParams = fParams;
    FORWARD_IF_ERROR( ZSTD_CCtx_refCDict(zcs, cdict) , "");
    return 0;
}


size_t ZSTD_initCStream_usingCDict(ZSTD_CStream* zcs, const ZSTD_CDict* cdict)
{
    DEBUGLOG(4, "ZSTD_initCStream_usingCDict");
    FORWARD_IF_ERROR( ZSTD_CCtx_reset(zcs, ZSTD_reset_session_only) , "");
    FORWARD_IF_ERROR( ZSTD_CCtx_refCDict(zcs, cdict) , "");
    return 0;
}



size_t ZSTD_initCStream_advanced(ZSTD_CStream* zcs,
                                 const void* dict, size_t dictSize,
                                 ZSTD_parameters params, unsigned long long pss)
{

    U64 const pledgedSrcSize = (pss==0 && params.fParams.contentSizeFlag==0) ? ZSTD_CONTENTSIZE_UNKNOWN : pss;
    DEBUGLOG(4, "ZSTD_initCStream_advanced");
    FORWARD_IF_ERROR( ZSTD_CCtx_reset(zcs, ZSTD_reset_session_only) , "");
    FORWARD_IF_ERROR( ZSTD_CCtx_setPledgedSrcSize(zcs, pledgedSrcSize) , "");
    FORWARD_IF_ERROR( ZSTD_checkCParams(params.cParams) , "");
    ZSTD_CCtxParams_setZstdParams(&zcs->requestedParams, &params);
    FORWARD_IF_ERROR( ZSTD_CCtx_loadDictionary(zcs, dict, dictSize) , "");
    return 0;
}

size_t ZSTD_initCStream_usingDict(ZSTD_CStream* zcs, const void* dict, size_t dictSize, int compressionLevel)
{
    DEBUGLOG(4, "ZSTD_initCStream_usingDict");
    FORWARD_IF_ERROR( ZSTD_CCtx_reset(zcs, ZSTD_reset_session_only) , "");
    FORWARD_IF_ERROR( ZSTD_CCtx_setParameter(zcs, ZSTD_c_compressionLevel, compressionLevel) , "");
    FORWARD_IF_ERROR( ZSTD_CCtx_loadDictionary(zcs, dict, dictSize) , "");
    return 0;
}

size_t ZSTD_initCStream_srcSize(ZSTD_CStream* zcs, int compressionLevel, unsigned long long pss)
{

    U64 const pledgedSrcSize = (pss==0) ? ZSTD_CONTENTSIZE_UNKNOWN : pss;
    DEBUGLOG(4, "ZSTD_initCStream_srcSize");
    FORWARD_IF_ERROR( ZSTD_CCtx_reset(zcs, ZSTD_reset_session_only) , "");
    FORWARD_IF_ERROR( ZSTD_CCtx_refCDict(zcs, NULL) , "");
    FORWARD_IF_ERROR( ZSTD_CCtx_setParameter(zcs, ZSTD_c_compressionLevel, compressionLevel) , "");
    FORWARD_IF_ERROR( ZSTD_CCtx_setPledgedSrcSize(zcs, pledgedSrcSize) , "");
    return 0;
}

size_t ZSTD_initCStream(ZSTD_CStream* zcs, int compressionLevel)
{
    DEBUGLOG(4, "ZSTD_initCStream");
    FORWARD_IF_ERROR( ZSTD_CCtx_reset(zcs, ZSTD_reset_session_only) , "");
    FORWARD_IF_ERROR( ZSTD_CCtx_refCDict(zcs, NULL) , "");
    FORWARD_IF_ERROR( ZSTD_CCtx_setParameter(zcs, ZSTD_c_compressionLevel, compressionLevel) , "");
    return 0;
}



static size_t ZSTD_nextInputSizeHint(const ZSTD_CCtx* cctx)
{
    if (cctx->appliedParams.inBufferMode == ZSTD_bm_stable) {
        return cctx->blockSizeMax - cctx->stableIn_notConsumed;
    }
    assert(cctx->appliedParams.inBufferMode == ZSTD_bm_buffered);
    {   size_t hintInSize = cctx->inBuffTarget - cctx->inBuffPos;
        if (hintInSize==0) hintInSize = cctx->blockSizeMax;
        return hintInSize;
    }
}


static size_t ZSTD_compressStream_generic(ZSTD_CStream* zcs,
                                          ZSTD_outBuffer* output,
                                          ZSTD_inBuffer* input,
                                          ZSTD_EndDirective const flushMode)
{
    const char* const istart = (assert(input != NULL), (const char*)input->src);
    const char* const iend = (istart != NULL) ? istart + input->size : istart;
    const char* ip = (istart != NULL) ? istart + input->pos : istart;
    char* const ostart = (assert(output != NULL), (char*)output->dst);
    char* const oend = (ostart != NULL) ? ostart + output->size : ostart;
    char* op = (ostart != NULL) ? ostart + output->pos : ostart;
    U32 someMoreWork = 1;


    DEBUGLOG(5, "ZSTD_compressStream_generic, flush=%i, srcSize = %zu", (int)flushMode, input->size - input->pos);
    assert(zcs != NULL);
    if (zcs->appliedParams.inBufferMode == ZSTD_bm_stable) {
        assert(input->pos >= zcs->stableIn_notConsumed);
        input->pos -= zcs->stableIn_notConsumed;
        if (ip) ip -= zcs->stableIn_notConsumed;
        zcs->stableIn_notConsumed = 0;
    }
    if (zcs->appliedParams.inBufferMode == ZSTD_bm_buffered) {
        assert(zcs->inBuff != NULL);
        assert(zcs->inBuffSize > 0);
    }
    if (zcs->appliedParams.outBufferMode == ZSTD_bm_buffered) {
        assert(zcs->outBuff !=  NULL);
        assert(zcs->outBuffSize > 0);
    }
    if (input->src == NULL) assert(input->size == 0);
    assert(input->pos <= input->size);
    if (output->dst == NULL) assert(output->size == 0);
    assert(output->pos <= output->size);
    assert((U32)flushMode <= (U32)ZSTD_e_end);

    while (someMoreWork) {
        switch(zcs->streamStage)
        {
        case zcss_init:
            RETURN_ERROR(init_missing, "call ZSTD_initCStream() first!");

        case zcss_load:
            if ( (flushMode == ZSTD_e_end)
              && ( (size_t)(oend-op) >= ZSTD_compressBound((size_t)(iend-ip))     /* Enough output space */
                || zcs->appliedParams.outBufferMode == ZSTD_bm_stable)  /* OR we are allowed to return dstSizeTooSmall */
              && (zcs->inBuffPos == 0) ) {

                size_t const cSize = ZSTD_compressEnd_public(zcs,
                                                op, (size_t)(oend-op),
                                                ip, (size_t)(iend-ip));
                DEBUGLOG(4, "ZSTD_compressEnd : cSize=%u", (unsigned)cSize);
                FORWARD_IF_ERROR(cSize, "ZSTD_compressEnd failed");
                ip = iend;
                op += cSize;
                zcs->frameEnded = 1;
                ZSTD_CCtx_reset(zcs, ZSTD_reset_session_only);
                someMoreWork = 0; break;
            }

            if (zcs->appliedParams.inBufferMode == ZSTD_bm_buffered) {
                size_t const toLoad = zcs->inBuffTarget - zcs->inBuffPos;
                size_t const loaded = ZSTD_limitCopy(
                                        zcs->inBuff + zcs->inBuffPos, toLoad,
                                        ip, (size_t)(iend-ip));
                zcs->inBuffPos += loaded;
                if (ip) ip += loaded;
                if ( (flushMode == ZSTD_e_continue)
                  && (zcs->inBuffPos < zcs->inBuffTarget) ) {

                    someMoreWork = 0; break;
                }
                if ( (flushMode == ZSTD_e_flush)
                  && (zcs->inBuffPos == zcs->inToCompress) ) {

                    someMoreWork = 0; break;
                }
            } else {
                assert(zcs->appliedParams.inBufferMode == ZSTD_bm_stable);
                if ( (flushMode == ZSTD_e_continue)
                  && ( (size_t)(iend - ip) < zcs->blockSizeMax) ) {

                    zcs->stableIn_notConsumed = (size_t)(iend - ip);
                    ip = iend;  /* pretend to have consumed input */
                    someMoreWork = 0; break;
                }
                if ( (flushMode == ZSTD_e_flush)
                  && (ip == iend) ) {

                    someMoreWork = 0; break;
                }
            }

            DEBUGLOG(5, "stream compression stage (flushMode==%u)", flushMode);
            {   int const inputBuffered = (zcs->appliedParams.inBufferMode == ZSTD_bm_buffered);
                void* cDst;
                size_t cSize;
                size_t oSize = (size_t)(oend-op);
                size_t const iSize = inputBuffered ? zcs->inBuffPos - zcs->inToCompress
                                                   : MIN((size_t)(iend - ip), zcs->blockSizeMax);
                if (oSize >= ZSTD_compressBound(iSize) || zcs->appliedParams.outBufferMode == ZSTD_bm_stable)
                    cDst = op;   /* compress into output buffer, to skip flush stage */
                else
                    cDst = zcs->outBuff, oSize = zcs->outBuffSize;
                if (inputBuffered) {
                    unsigned const lastBlock = (flushMode == ZSTD_e_end) && (ip==iend);
                    cSize = lastBlock ?
                            ZSTD_compressEnd_public(zcs, cDst, oSize,
                                        zcs->inBuff + zcs->inToCompress, iSize) :
                            ZSTD_compressContinue_public(zcs, cDst, oSize,
                                        zcs->inBuff + zcs->inToCompress, iSize);
                    FORWARD_IF_ERROR(cSize, "%s", lastBlock ? "ZSTD_compressEnd failed" : "ZSTD_compressContinue failed");
                    zcs->frameEnded = lastBlock;

                    zcs->inBuffTarget = zcs->inBuffPos + zcs->blockSizeMax;
                    if (zcs->inBuffTarget > zcs->inBuffSize)
                        zcs->inBuffPos = 0, zcs->inBuffTarget = zcs->blockSizeMax;
                    DEBUGLOG(5, "inBuffTarget:%u / inBuffSize:%u",
                            (unsigned)zcs->inBuffTarget, (unsigned)zcs->inBuffSize);
                    if (!lastBlock)
                        assert(zcs->inBuffTarget <= zcs->inBuffSize);
                    zcs->inToCompress = zcs->inBuffPos;
                } else { /* !inputBuffered, hence ZSTD_bm_stable */
                    unsigned const lastBlock = (flushMode == ZSTD_e_end) && (ip + iSize == iend);
                    cSize = lastBlock ?
                            ZSTD_compressEnd_public(zcs, cDst, oSize, ip, iSize) :
                            ZSTD_compressContinue_public(zcs, cDst, oSize, ip, iSize);

                    if (ip) ip += iSize;
                    FORWARD_IF_ERROR(cSize, "%s", lastBlock ? "ZSTD_compressEnd failed" : "ZSTD_compressContinue failed");
                    zcs->frameEnded = lastBlock;
                    if (lastBlock) assert(ip == iend);
                }
                if (cDst == op) {  /* no need to flush */
                    op += cSize;
                    if (zcs->frameEnded) {
                        DEBUGLOG(5, "Frame completed directly in outBuffer");
                        someMoreWork = 0;
                        ZSTD_CCtx_reset(zcs, ZSTD_reset_session_only);
                    }
                    break;
                }
                zcs->outBuffContentSize = cSize;
                zcs->outBuffFlushedSize = 0;
                zcs->streamStage = zcss_flush; /* pass-through to flush stage */
            }
	    ZSTD_FALLTHROUGH;
        case zcss_flush:
            DEBUGLOG(5, "flush stage");
            assert(zcs->appliedParams.outBufferMode == ZSTD_bm_buffered);
            {   size_t const toFlush = zcs->outBuffContentSize - zcs->outBuffFlushedSize;
                size_t const flushed = ZSTD_limitCopy(op, (size_t)(oend-op),
                            zcs->outBuff + zcs->outBuffFlushedSize, toFlush);
                DEBUGLOG(5, "toFlush: %u into %u ==> flushed: %u",
                            (unsigned)toFlush, (unsigned)(oend-op), (unsigned)flushed);
                if (flushed)
                    op += flushed;
                zcs->outBuffFlushedSize += flushed;
                if (toFlush!=flushed) {

                    assert(op==oend);
                    someMoreWork = 0;
                    break;
                }
                zcs->outBuffContentSize = zcs->outBuffFlushedSize = 0;
                if (zcs->frameEnded) {
                    DEBUGLOG(5, "Frame completed on flush");
                    someMoreWork = 0;
                    ZSTD_CCtx_reset(zcs, ZSTD_reset_session_only);
                    break;
                }
                zcs->streamStage = zcss_load;
                break;
            }

        default: /* impossible */
            assert(0);
        }
    }

    input->pos = (size_t)(ip - istart);
    output->pos = (size_t)(op - ostart);
    if (zcs->frameEnded) return 0;
    return ZSTD_nextInputSizeHint(zcs);
}

static size_t ZSTD_nextInputSizeHint_MTorST(const ZSTD_CCtx* cctx)
{
#ifdef ZSTD_MULTITHREAD
    if (cctx->appliedParams.nbWorkers >= 1) {
        assert(cctx->mtctx != NULL);
        return ZSTDMT_nextInputSizeHint(cctx->mtctx);
    }
#endif
    return ZSTD_nextInputSizeHint(cctx);

}

size_t ZSTD_compressStream(ZSTD_CStream* zcs, ZSTD_outBuffer* output, ZSTD_inBuffer* input)
{
    FORWARD_IF_ERROR( ZSTD_compressStream2(zcs, output, input, ZSTD_e_continue) , "");
    return ZSTD_nextInputSizeHint_MTorST(zcs);
}


static void
ZSTD_setBufferExpectations(ZSTD_CCtx* cctx, const ZSTD_outBuffer* output, const ZSTD_inBuffer* input)
{
    DEBUGLOG(5, "ZSTD_setBufferExpectations (for advanced stable in/out modes)");
    if (cctx->appliedParams.inBufferMode == ZSTD_bm_stable) {
        cctx->expectedInBuffer = *input;
    }
    if (cctx->appliedParams.outBufferMode == ZSTD_bm_stable) {
        cctx->expectedOutBufferSize = output->size - output->pos;
    }
}


static size_t ZSTD_checkBufferStability(ZSTD_CCtx const* cctx,
                                        ZSTD_outBuffer const* output,
                                        ZSTD_inBuffer const* input,
                                        ZSTD_EndDirective endOp)
{
    if (cctx->appliedParams.inBufferMode == ZSTD_bm_stable) {
        ZSTD_inBuffer const expect = cctx->expectedInBuffer;
        if (expect.src != input->src || expect.pos != input->pos)
            RETURN_ERROR(stabilityCondition_notRespected, "ZSTD_c_stableInBuffer enabled but input differs!");
    }
    (void)endOp;
    if (cctx->appliedParams.outBufferMode == ZSTD_bm_stable) {
        size_t const outBufferSize = output->size - output->pos;
        if (cctx->expectedOutBufferSize != outBufferSize)
            RETURN_ERROR(stabilityCondition_notRespected, "ZSTD_c_stableOutBuffer enabled but output size differs!");
    }
    return 0;
}


static size_t ZSTD_CCtx_init_compressStream2(ZSTD_CCtx* cctx,
                                             ZSTD_EndDirective endOp,
                                             size_t inSize)
{
    ZSTD_CCtx_params params = cctx->requestedParams;
    ZSTD_prefixDict const prefixDict = cctx->prefixDict;
    FORWARD_IF_ERROR( ZSTD_initLocalDict(cctx) , ""); /* Init the local dict if present. */
    ZSTD_memset(&cctx->prefixDict, 0, sizeof(cctx->prefixDict));   /* single usage */
    assert(prefixDict.dict==NULL || cctx->cdict==NULL);    /* only one can be set */
    if (cctx->cdict && !cctx->localDict.cdict) {

        params.compressionLevel = cctx->cdict->compressionLevel;
    }
    DEBUGLOG(4, "ZSTD_CCtx_init_compressStream2 : transparent init stage");
    if (endOp == ZSTD_e_end) cctx->pledgedSrcSizePlusOne = inSize + 1;  /* auto-determine pledgedSrcSize */

    {   size_t const dictSize = prefixDict.dict
                ? prefixDict.dictSize
                : (cctx->cdict ? cctx->cdict->dictContentSize : 0);
        ZSTD_CParamMode_e const mode = ZSTD_getCParamMode(cctx->cdict, &params, cctx->pledgedSrcSizePlusOne - 1);
        params.cParams = ZSTD_getCParamsFromCCtxParams(
                &params, cctx->pledgedSrcSizePlusOne-1,
                dictSize, mode);
    }

    params.postBlockSplitter = ZSTD_resolveBlockSplitterMode(params.postBlockSplitter, &params.cParams);
    params.ldmParams.enableLdm = ZSTD_resolveEnableLdm(params.ldmParams.enableLdm, &params.cParams);
    params.useRowMatchFinder = ZSTD_resolveRowMatchFinderMode(params.useRowMatchFinder, &params.cParams);
    params.validateSequences = ZSTD_resolveExternalSequenceValidation(params.validateSequences);
    params.maxBlockSize = ZSTD_resolveMaxBlockSize(params.maxBlockSize);
    params.searchForExternalRepcodes = ZSTD_resolveExternalRepcodeSearch(params.searchForExternalRepcodes, params.compressionLevel);

#ifdef ZSTD_MULTITHREAD

    RETURN_ERROR_IF(
        ZSTD_hasExtSeqProd(&params) && params.nbWorkers >= 1,
        parameter_combination_unsupported,
        "External sequence producer isn't supported with nbWorkers >= 1"
    );

    if ((cctx->pledgedSrcSizePlusOne-1) <= ZSTDMT_JOBSIZE_MIN) {
        params.nbWorkers = 0; /* do not invoke multi-threading when src size is too small */
    }
    if (params.nbWorkers > 0) {
# if ZSTD_TRACE
        cctx->traceCtx = (ZSTD_trace_compress_begin != NULL) ? ZSTD_trace_compress_begin(cctx) : 0;
# endif

        if (cctx->mtctx == NULL) {
            DEBUGLOG(4, "ZSTD_compressStream2: creating new mtctx for nbWorkers=%u",
                        params.nbWorkers);
            cctx->mtctx = ZSTDMT_createCCtx_advanced((U32)params.nbWorkers, cctx->customMem, cctx->pool);
            RETURN_ERROR_IF(cctx->mtctx == NULL, memory_allocation, "NULL pointer!");
        }

        DEBUGLOG(4, "call ZSTDMT_initCStream_internal as nbWorkers=%u", params.nbWorkers);
        FORWARD_IF_ERROR( ZSTDMT_initCStream_internal(
                    cctx->mtctx,
                    prefixDict.dict, prefixDict.dictSize, prefixDict.dictContentType,
                    cctx->cdict, params, cctx->pledgedSrcSizePlusOne-1) , "");
        cctx->dictID = cctx->cdict ? cctx->cdict->dictID : 0;
        cctx->dictContentSize = cctx->cdict ? cctx->cdict->dictContentSize : prefixDict.dictSize;
        cctx->consumedSrcSize = 0;
        cctx->producedCSize = 0;
        cctx->streamStage = zcss_load;
        cctx->appliedParams = params;
    } else
#endif  /* ZSTD_MULTITHREAD */
    {   U64 const pledgedSrcSize = cctx->pledgedSrcSizePlusOne - 1;
        assert(!ZSTD_isError(ZSTD_checkCParams(params.cParams)));
        FORWARD_IF_ERROR( ZSTD_compressBegin_internal(cctx,
                prefixDict.dict, prefixDict.dictSize, prefixDict.dictContentType, ZSTD_dtlm_fast,
                cctx->cdict,
                &params, pledgedSrcSize,
                ZSTDb_buffered) , "");
        assert(cctx->appliedParams.nbWorkers == 0);
        cctx->inToCompress = 0;
        cctx->inBuffPos = 0;
        if (cctx->appliedParams.inBufferMode == ZSTD_bm_buffered) {

            cctx->inBuffTarget = cctx->blockSizeMax + (cctx->blockSizeMax == pledgedSrcSize);
        } else {
            cctx->inBuffTarget = 0;
        }
        cctx->outBuffContentSize = cctx->outBuffFlushedSize = 0;
        cctx->streamStage = zcss_load;
        cctx->frameEnded = 0;
    }
    return 0;
}


size_t ZSTD_compressStream2( ZSTD_CCtx* cctx,
                             ZSTD_outBuffer* output,
                             ZSTD_inBuffer* input,
                             ZSTD_EndDirective endOp)
{
    DEBUGLOG(5, "ZSTD_compressStream2, endOp=%u ", (unsigned)endOp);

    RETURN_ERROR_IF(output->pos > output->size, dstSize_tooSmall, "invalid output buffer");
    RETURN_ERROR_IF(input->pos  > input->size, srcSize_wrong, "invalid input buffer");
    RETURN_ERROR_IF((U32)endOp > (U32)ZSTD_e_end, parameter_outOfBound, "invalid endDirective");
    assert(cctx != NULL);


    if (cctx->streamStage == zcss_init) {
        size_t const inputSize = input->size - input->pos;  /* no obligation to start from pos==0 */
        size_t const totalInputSize = inputSize + cctx->stableIn_notConsumed;
        if (cctx->stableIn_notConsumed) {  /* not the first time */

            RETURN_ERROR_IF(cctx->requestedParams.inBufferMode != ZSTD_bm_stable, stabilityCondition_notRespected, "stableInBuffer condition not respected: disabled while input is pending");
            RETURN_ERROR_IF(input->src != cctx->expectedInBuffer.src, stabilityCondition_notRespected, "stableInBuffer condition not respected: wrong src pointer");
            RETURN_ERROR_IF(input->pos != cctx->expectedInBuffer.size, stabilityCondition_notRespected, "stableInBuffer condition not respected: externally modified pos");
        }
        if ( (cctx->requestedParams.inBufferMode == ZSTD_bm_stable) /* input is presumed stable, across invocations */
          && (endOp == ZSTD_e_continue)                             /* no flush requested, more input to come */
          && (totalInputSize < ZSTD_BLOCKSIZE_MAX) ) {              /* not even reached one block yet */

            input->pos = input->size;

            cctx->expectedInBuffer = *input;

            cctx->stableIn_notConsumed += inputSize;

            return ZSTD_FRAMEHEADERSIZE_MIN(cctx->requestedParams.format);  /* at least some header to produce */
        }
        FORWARD_IF_ERROR(ZSTD_CCtx_init_compressStream2(cctx, endOp, totalInputSize), "compressStream2 initialization failed");
        ZSTD_setBufferExpectations(cctx, output, input);   /* Set initial buffer expectations now that we've initialized */
    }


    FORWARD_IF_ERROR(ZSTD_checkBufferStability(cctx, output, input, endOp), "invalid buffers");

#ifdef ZSTD_MULTITHREAD
    if (cctx->appliedParams.nbWorkers > 0) {
        size_t flushMin;

        if ( (cctx->pledgedSrcSizePlusOne != 0)
          && (!ZSTDMT_isFrameEnded(cctx->mtctx)) ) {
            U64 const srcSizeIfAllConsumed = cctx->consumedSrcSize + cctx->stableIn_notConsumed + (U64)(input->size - input->pos);
            ZSTD_STATIC_ASSERT(ZSTD_CONTENTSIZE_UNKNOWN == (unsigned long long)-1);
            RETURN_ERROR_IF(
                (srcSizeIfAllConsumed+1 > cctx->pledgedSrcSizePlusOne)
             || ((endOp == ZSTD_e_end) && (srcSizeIfAllConsumed+1 != cctx->pledgedSrcSizePlusOne)),
                srcSize_wrong,
                "error : pledgedSrcSize = %u, while realSrcSize = %u",
                (unsigned)cctx->pledgedSrcSizePlusOne-1,
                (unsigned)srcSizeIfAllConsumed);
        }
        if (cctx->cParamsChanged) {
            ZSTDMT_updateCParams_whileCompressing(cctx->mtctx, &cctx->requestedParams);
            cctx->cParamsChanged = 0;
        }
        if (cctx->stableIn_notConsumed) {
            assert(cctx->appliedParams.inBufferMode == ZSTD_bm_stable);

            assert(input->pos >= cctx->stableIn_notConsumed);
            input->pos -= cctx->stableIn_notConsumed;
            cctx->stableIn_notConsumed = 0;
        }
        for (;;) {
            size_t const ipos = input->pos;
            size_t const opos = output->pos;
            flushMin = ZSTDMT_compressStream_generic(cctx->mtctx, output, input, endOp);
            cctx->consumedSrcSize += (U64)(input->pos - ipos);
            cctx->producedCSize += (U64)(output->pos - opos);
            if ( ZSTD_isError(flushMin)
              || (endOp == ZSTD_e_end && flushMin == 0) ) { /* compression completed */
                if (flushMin == 0) {

                    assert(cctx->pledgedSrcSizePlusOne == 0 || cctx->pledgedSrcSizePlusOne == cctx->consumedSrcSize+1);
                    ZSTD_CCtx_trace(cctx, 0);
                }
                ZSTD_CCtx_reset(cctx, ZSTD_reset_session_only);
            }
            FORWARD_IF_ERROR(flushMin, "ZSTDMT_compressStream_generic failed");

            if (endOp == ZSTD_e_continue) {

                if (input->pos != ipos || output->pos != opos || input->pos == input->size || output->pos == output->size)
                    break;
            } else {
                assert(endOp == ZSTD_e_flush || endOp == ZSTD_e_end);

                if (flushMin == 0 || output->pos == output->size)
                    break;
            }
        }
        DEBUGLOG(5, "completed ZSTD_compressStream2 delegating to ZSTDMT_compressStream_generic");

        assert(endOp == ZSTD_e_continue || flushMin == 0 || output->pos == output->size);
        ZSTD_setBufferExpectations(cctx, output, input);
        return flushMin;
    }
#endif /* ZSTD_MULTITHREAD */
    FORWARD_IF_ERROR( ZSTD_compressStream_generic(cctx, output, input, endOp) , "");
    DEBUGLOG(5, "completed ZSTD_compressStream2");
    ZSTD_setBufferExpectations(cctx, output, input);
    return cctx->outBuffContentSize - cctx->outBuffFlushedSize; /* remaining to flush */
}

size_t ZSTD_compressStream2_simpleArgs (
                            ZSTD_CCtx* cctx,
                            void* dst, size_t dstCapacity, size_t* dstPos,
                      const void* src, size_t srcSize, size_t* srcPos,
                            ZSTD_EndDirective endOp)
{
    ZSTD_outBuffer output;
    ZSTD_inBuffer  input;
    output.dst = dst;
    output.size = dstCapacity;
    output.pos = *dstPos;
    input.src = src;
    input.size = srcSize;
    input.pos = *srcPos;

    {   size_t const cErr = ZSTD_compressStream2(cctx, &output, &input, endOp);
        *dstPos = output.pos;
        *srcPos = input.pos;
        return cErr;
    }
}

size_t ZSTD_compress2(ZSTD_CCtx* cctx,
                      void* dst, size_t dstCapacity,
                      const void* src, size_t srcSize)
{
    ZSTD_bufferMode_e const originalInBufferMode = cctx->requestedParams.inBufferMode;
    ZSTD_bufferMode_e const originalOutBufferMode = cctx->requestedParams.outBufferMode;
    DEBUGLOG(4, "ZSTD_compress2 (srcSize=%u)", (unsigned)srcSize);
    ZSTD_CCtx_reset(cctx, ZSTD_reset_session_only);

    cctx->requestedParams.inBufferMode = ZSTD_bm_stable;
    cctx->requestedParams.outBufferMode = ZSTD_bm_stable;
    {   size_t oPos = 0;
        size_t iPos = 0;
        size_t const result = ZSTD_compressStream2_simpleArgs(cctx,
                                        dst, dstCapacity, &oPos,
                                        src, srcSize, &iPos,
                                        ZSTD_e_end);

        cctx->requestedParams.inBufferMode = originalInBufferMode;
        cctx->requestedParams.outBufferMode = originalOutBufferMode;

        FORWARD_IF_ERROR(result, "ZSTD_compressStream2_simpleArgs failed");
        if (result != 0) {  /* compression not completed, due to lack of output space */
            assert(oPos == dstCapacity);
            RETURN_ERROR(dstSize_tooSmall, "");
        }
        assert(iPos == srcSize);   /* all input is expected consumed */
        return oPos;
    }
}


static size_t
ZSTD_validateSequence(U32 offBase, U32 matchLength, U32 minMatch,
                      size_t posInSrc, U32 windowLog, size_t dictSize, int useSequenceProducer)
{
    U32 const windowSize = 1u << windowLog;

    size_t const offsetBound = posInSrc > windowSize ? (size_t)windowSize : posInSrc + (size_t)dictSize;
    size_t const matchLenLowerBound = (minMatch == 3 || useSequenceProducer) ? 3 : 4;
    RETURN_ERROR_IF(offBase > OFFSET_TO_OFFBASE(offsetBound), externalSequences_invalid, "Offset too large!");

    RETURN_ERROR_IF(matchLength < matchLenLowerBound, externalSequences_invalid, "Matchlength too small for the minMatch");
    return 0;
}


static U32 ZSTD_finalizeOffBase(U32 rawOffset, const U32 rep[ZSTD_REP_NUM], U32 ll0)
{
    U32 offBase = OFFSET_TO_OFFBASE(rawOffset);

    if (!ll0 && rawOffset == rep[0]) {
        offBase = REPCODE1_TO_OFFBASE;
    } else if (rawOffset == rep[1]) {
        offBase = REPCODE_TO_OFFBASE(2 - ll0);
    } else if (rawOffset == rep[2]) {
        offBase = REPCODE_TO_OFFBASE(3 - ll0);
    } else if (ll0 && rawOffset == rep[0] - 1) {
        offBase = REPCODE3_TO_OFFBASE;
    }
    return offBase;
}


static size_t
ZSTD_transferSequences_wBlockDelim(ZSTD_CCtx* cctx,
                                   ZSTD_SequencePosition* seqPos,
                             const ZSTD_Sequence* const inSeqs, size_t inSeqsSize,
                             const void* src, size_t blockSize,
                                   ZSTD_ParamSwitch_e externalRepSearch)
{
    U32 idx = seqPos->idx;
    U32 const startIdx = idx;
    BYTE const* ip = (BYTE const*)(src);
    const BYTE* const iend = ip + blockSize;
    Repcodes_t updatedRepcodes;
    U32 dictSize;

    DEBUGLOG(5, "ZSTD_transferSequences_wBlockDelim (blockSize = %zu)", blockSize);

    if (cctx->cdict) {
        dictSize = (U32)cctx->cdict->dictContentSize;
    } else if (cctx->prefixDict.dict) {
        dictSize = (U32)cctx->prefixDict.dictSize;
    } else {
        dictSize = 0;
    }
    ZSTD_memcpy(updatedRepcodes.rep, cctx->blockState.prevCBlock->rep, sizeof(Repcodes_t));
    for (; idx < inSeqsSize && (inSeqs[idx].matchLength != 0 || inSeqs[idx].offset != 0); ++idx) {
        U32 const litLength = inSeqs[idx].litLength;
        U32 const matchLength = inSeqs[idx].matchLength;
        U32 offBase;

        if (externalRepSearch == ZSTD_ps_disable) {
            offBase = OFFSET_TO_OFFBASE(inSeqs[idx].offset);
        } else {
            U32 const ll0 = (litLength == 0);
            offBase = ZSTD_finalizeOffBase(inSeqs[idx].offset, updatedRepcodes.rep, ll0);
            ZSTD_updateRep(updatedRepcodes.rep, offBase, ll0);
        }

        DEBUGLOG(6, "Storing sequence: (of: %u, ml: %u, ll: %u)", offBase, matchLength, litLength);
        if (cctx->appliedParams.validateSequences) {
            seqPos->posInSrc += litLength + matchLength;
            FORWARD_IF_ERROR(ZSTD_validateSequence(offBase, matchLength, cctx->appliedParams.cParams.minMatch,
                                                seqPos->posInSrc,
                                                cctx->appliedParams.cParams.windowLog, dictSize,
                                                ZSTD_hasExtSeqProd(&cctx->appliedParams)),
                                                "Sequence validation failed");
        }
        RETURN_ERROR_IF(idx - seqPos->idx >= cctx->seqStore.maxNbSeq, externalSequences_invalid,
                        "Not enough memory allocated. Try adjusting ZSTD_c_minMatch.");
        ZSTD_storeSeq(&cctx->seqStore, litLength, ip, iend, offBase, matchLength);
        ip += matchLength + litLength;
    }
    RETURN_ERROR_IF(idx == inSeqsSize, externalSequences_invalid, "Block delimiter not found.");


    assert(externalRepSearch != ZSTD_ps_auto);
    assert(idx >= startIdx);
    if (externalRepSearch == ZSTD_ps_disable && idx != startIdx) {
        U32* const rep = updatedRepcodes.rep;
        U32 lastSeqIdx = idx - 1; /* index of last non-block-delimiter sequence */

        if (lastSeqIdx >= startIdx + 2) {
            rep[2] = inSeqs[lastSeqIdx - 2].offset;
            rep[1] = inSeqs[lastSeqIdx - 1].offset;
            rep[0] = inSeqs[lastSeqIdx].offset;
        } else if (lastSeqIdx == startIdx + 1) {
            rep[2] = rep[0];
            rep[1] = inSeqs[lastSeqIdx - 1].offset;
            rep[0] = inSeqs[lastSeqIdx].offset;
        } else {
            assert(lastSeqIdx == startIdx);
            rep[2] = rep[1];
            rep[1] = rep[0];
            rep[0] = inSeqs[lastSeqIdx].offset;
        }
    }

    ZSTD_memcpy(cctx->blockState.nextCBlock->rep, updatedRepcodes.rep, sizeof(Repcodes_t));

    if (inSeqs[idx].litLength) {
        DEBUGLOG(6, "Storing last literals of size: %u", inSeqs[idx].litLength);
        ZSTD_storeLastLiterals(&cctx->seqStore, ip, inSeqs[idx].litLength);
        ip += inSeqs[idx].litLength;
        seqPos->posInSrc += inSeqs[idx].litLength;
    }
    RETURN_ERROR_IF(ip != iend, externalSequences_invalid, "Blocksize doesn't agree with block delimiter!");
    seqPos->idx = idx+1;
    return blockSize;
}


static size_t
ZSTD_transferSequences_noDelim(ZSTD_CCtx* cctx,
                               ZSTD_SequencePosition* seqPos,
                         const ZSTD_Sequence* const inSeqs, size_t inSeqsSize,
                         const void* src, size_t blockSize,
                               ZSTD_ParamSwitch_e externalRepSearch)
{
    U32 idx = seqPos->idx;
    U64 startPosInSequence = seqPos->posInSequence;
    U64 endPosInSequence = seqPos->posInSequence + blockSize;
    size_t dictSize;
    const BYTE* const istart = (const BYTE*)(src);
    const BYTE* ip = istart;
    const BYTE* iend = istart + blockSize;  /* May be adjusted if we decide to process fewer than blockSize bytes */
    Repcodes_t updatedRepcodes;
    U32 bytesAdjustment = 0;
    U32 finalMatchSplit = 0;


    (void)externalRepSearch;

    if (cctx->cdict) {
        dictSize = cctx->cdict->dictContentSize;
    } else if (cctx->prefixDict.dict) {
        dictSize = cctx->prefixDict.dictSize;
    } else {
        dictSize = 0;
    }
    DEBUGLOG(5, "ZSTD_transferSequences_noDelim: idx: %u PIS: %llu blockSize: %zu", idx, (unsigned long long)startPosInSequence, blockSize);
    DEBUGLOG(5, "Start seq: idx: %u (of: %u ml: %u ll: %u)", idx, inSeqs[idx].offset, inSeqs[idx].matchLength, inSeqs[idx].litLength);
    ZSTD_memcpy(updatedRepcodes.rep, cctx->blockState.prevCBlock->rep, sizeof(Repcodes_t));
    while (endPosInSequence && idx < inSeqsSize && !finalMatchSplit) {
        const ZSTD_Sequence currSeq = inSeqs[idx];
        U32 litLength = currSeq.litLength;
        U32 matchLength = currSeq.matchLength;
        U64 const sequenceLength = (U64)litLength + matchLength;
        U32 const rawOffset = currSeq.offset;
        U32 offBase;


        if (endPosInSequence >= sequenceLength) {
            if (startPosInSequence >= litLength) {
                startPosInSequence -= litLength;
                litLength = 0;
                matchLength -= (U32)startPosInSequence;
            } else {
                litLength -= (U32)startPosInSequence;
            }

            endPosInSequence -= sequenceLength;
            startPosInSequence = 0;
        } else {

            DEBUGLOG(6, "Require a split: diff: %llu, idx: %u PIS: %llu",
                     (unsigned long long)(sequenceLength - endPosInSequence), idx, (unsigned long long)endPosInSequence);
            if (endPosInSequence > litLength) {
                U32 firstHalfMatchLength;
                litLength = startPosInSequence >= litLength ? 0 : litLength - (U32)startPosInSequence;
                firstHalfMatchLength = (U32)(endPosInSequence - startPosInSequence) - litLength;
                if (matchLength > blockSize && firstHalfMatchLength >= cctx->appliedParams.cParams.minMatch) {

                    U32 secondHalfMatchLength = (U32)(sequenceLength - endPosInSequence);
                    if (secondHalfMatchLength < cctx->appliedParams.cParams.minMatch) {

                        endPosInSequence -= cctx->appliedParams.cParams.minMatch - secondHalfMatchLength;
                        bytesAdjustment = cctx->appliedParams.cParams.minMatch - secondHalfMatchLength;
                        firstHalfMatchLength -= bytesAdjustment;
                    }
                    matchLength = firstHalfMatchLength;

                    finalMatchSplit = 1;
                } else {

                    bytesAdjustment = (U32)(endPosInSequence - currSeq.litLength);
                    endPosInSequence = currSeq.litLength;
                    break;
                }
            } else {

                break;
            }
        }

        assert((U64)litLength + matchLength <= blockSize);

        {   U32 const ll0 = (litLength == 0);
            offBase = ZSTD_finalizeOffBase(rawOffset, updatedRepcodes.rep, ll0);
            ZSTD_updateRep(updatedRepcodes.rep, offBase, ll0);
        }

        if (cctx->appliedParams.validateSequences) {
            seqPos->posInSrc += litLength + matchLength;
            FORWARD_IF_ERROR(ZSTD_validateSequence(offBase, matchLength, cctx->appliedParams.cParams.minMatch, seqPos->posInSrc,
                                                   cctx->appliedParams.cParams.windowLog, dictSize, ZSTD_hasExtSeqProd(&cctx->appliedParams)),
                                                   "Sequence validation failed");
        }
        DEBUGLOG(6, "Storing sequence: (of: %u, ml: %u, ll: %u)", offBase, matchLength, litLength);
        RETURN_ERROR_IF(idx - seqPos->idx >= cctx->seqStore.maxNbSeq, externalSequences_invalid,
                        "Not enough memory allocated. Try adjusting ZSTD_c_minMatch.");
        ZSTD_storeSeq(&cctx->seqStore, litLength, ip, iend, offBase, matchLength);
        ip += matchLength + litLength;
        if (!finalMatchSplit)
            idx++; /* Next Sequence */
    }
    DEBUGLOG(5, "Ending seq: idx: %u (of: %u ml: %u ll: %u)", idx, inSeqs[idx].offset, inSeqs[idx].matchLength, inSeqs[idx].litLength);
    assert(idx == inSeqsSize || endPosInSequence <= (U64)inSeqs[idx].litLength + inSeqs[idx].matchLength);
    seqPos->idx = idx;
    seqPos->posInSequence = endPosInSequence;
    ZSTD_memcpy(cctx->blockState.nextCBlock->rep, updatedRepcodes.rep, sizeof(Repcodes_t));

    iend -= bytesAdjustment;
    if (ip != iend) {

        U32 const lastLLSize = (U32)(iend - ip);
        assert(ip <= iend);
        DEBUGLOG(6, "Storing last literals of size: %u", lastLLSize);
        ZSTD_storeLastLiterals(&cctx->seqStore, ip, lastLLSize);
        seqPos->posInSrc += lastLLSize;
    }

    return (size_t)(iend-istart);
}


typedef size_t (*ZSTD_SequenceCopier_f)(ZSTD_CCtx* cctx,
                                        ZSTD_SequencePosition* seqPos,
                                  const ZSTD_Sequence* const inSeqs, size_t inSeqsSize,
                                  const void* src, size_t blockSize,
                                        ZSTD_ParamSwitch_e externalRepSearch);

static ZSTD_SequenceCopier_f ZSTD_selectSequenceCopier(ZSTD_SequenceFormat_e mode)
{
    assert(ZSTD_cParam_withinBounds(ZSTD_c_blockDelimiters, (int)mode));
    if (mode == ZSTD_sf_explicitBlockDelimiters) {
        return ZSTD_transferSequences_wBlockDelim;
    }
    assert(mode == ZSTD_sf_noBlockDelimiters);
    return ZSTD_transferSequences_noDelim;
}


static size_t
blockSize_explicitDelimiter(const ZSTD_Sequence* inSeqs, size_t inSeqsSize, ZSTD_SequencePosition seqPos)
{
    int end = 0;
    U64 blockSize = 0;
    size_t spos = seqPos.idx;
    DEBUGLOG(6, "blockSize_explicitDelimiter : seq %zu / %zu", spos, inSeqsSize);
    assert(spos <= inSeqsSize);
    while (spos < inSeqsSize) {
        end = (inSeqs[spos].offset == 0);
        blockSize += (U64)inSeqs[spos].litLength + inSeqs[spos].matchLength;
        RETURN_ERROR_IF(blockSize > ZSTD_BLOCKSIZE_MAX, externalSequences_invalid,
                        "sequences incorrectly define a too large block");
        if (end) {
            if (inSeqs[spos].matchLength != 0)
                RETURN_ERROR(externalSequences_invalid, "delimiter format error : both matchlength and offset must be == 0");
            break;
        }
        spos++;
    }
    if (!end)
        RETURN_ERROR(externalSequences_invalid, "Reached end of sequences without finding a block delimiter");
    return (size_t)blockSize;
}

static size_t determine_blockSize(ZSTD_SequenceFormat_e mode,
                           size_t blockSize, size_t remaining,
                     const ZSTD_Sequence* inSeqs, size_t inSeqsSize,
                           ZSTD_SequencePosition seqPos)
{
    DEBUGLOG(6, "determine_blockSize : remainingSize = %zu", remaining);
    if (mode == ZSTD_sf_noBlockDelimiters) {

        return MIN(remaining, blockSize);
    }
    assert(mode == ZSTD_sf_explicitBlockDelimiters);
    {   size_t const explicitBlockSize = blockSize_explicitDelimiter(inSeqs, inSeqsSize, seqPos);
        FORWARD_IF_ERROR(explicitBlockSize, "Error while determining block size with explicit delimiters");
        if (explicitBlockSize > blockSize)
            RETURN_ERROR(externalSequences_invalid, "sequences incorrectly define a too large block");
        if (explicitBlockSize > remaining)
            RETURN_ERROR(externalSequences_invalid, "sequences define a frame longer than source");
        return explicitBlockSize;
    }
}


static size_t
ZSTD_compressSequences_internal(ZSTD_CCtx* cctx,
                                void* dst, size_t dstCapacity,
                          const ZSTD_Sequence* inSeqs, size_t inSeqsSize,
                          const void* src, size_t srcSize)
{
    size_t cSize = 0;
    size_t remaining = srcSize;
    ZSTD_SequencePosition seqPos = {0, 0, 0};

    const BYTE* ip = (BYTE const*)src;
    BYTE* op = (BYTE*)dst;
    ZSTD_SequenceCopier_f const sequenceCopier = ZSTD_selectSequenceCopier(cctx->appliedParams.blockDelimiters);

    DEBUGLOG(4, "ZSTD_compressSequences_internal srcSize: %zu, inSeqsSize: %zu", srcSize, inSeqsSize);

    if (remaining == 0) {
        U32 const cBlockHeader24 = 1 /* last block */ + (((U32)bt_raw)<<1);
        RETURN_ERROR_IF(dstCapacity<4, dstSize_tooSmall, "No room for empty frame block header");
        MEM_writeLE32(op, cBlockHeader24);
        op += ZSTD_blockHeaderSize;
        dstCapacity -= ZSTD_blockHeaderSize;
        cSize += ZSTD_blockHeaderSize;
    }

    while (remaining) {
        size_t compressedSeqsSize;
        size_t cBlockSize;
        size_t blockSize = determine_blockSize(cctx->appliedParams.blockDelimiters,
                                        cctx->blockSizeMax, remaining,
                                        inSeqs, inSeqsSize, seqPos);
        U32 const lastBlock = (blockSize == remaining);
        FORWARD_IF_ERROR(blockSize, "Error while trying to determine block size");
        assert(blockSize <= remaining);
        ZSTD_resetSeqStore(&cctx->seqStore);

        blockSize = sequenceCopier(cctx,
                                   &seqPos, inSeqs, inSeqsSize,
                                   ip, blockSize,
                                   cctx->appliedParams.searchForExternalRepcodes);
        FORWARD_IF_ERROR(blockSize, "Bad sequence copy");



        if (blockSize < MIN_CBLOCK_SIZE+ZSTD_blockHeaderSize+1+1) {
            cBlockSize = ZSTD_noCompressBlock(op, dstCapacity, ip, blockSize, lastBlock);
            FORWARD_IF_ERROR(cBlockSize, "Nocompress block failed");
            DEBUGLOG(5, "Block too small (%zu): data remains uncompressed: cSize=%zu", blockSize, cBlockSize);
            cSize += cBlockSize;
            ip += blockSize;
            op += cBlockSize;
            remaining -= blockSize;
            dstCapacity -= cBlockSize;
            continue;
        }

        RETURN_ERROR_IF(dstCapacity < ZSTD_blockHeaderSize, dstSize_tooSmall, "not enough dstCapacity to write a new compressed block");
        compressedSeqsSize = ZSTD_entropyCompressSeqStore(&cctx->seqStore,
                                &cctx->blockState.prevCBlock->entropy, &cctx->blockState.nextCBlock->entropy,
                                &cctx->appliedParams,
                                op + ZSTD_blockHeaderSize /* Leave space for block header */, dstCapacity - ZSTD_blockHeaderSize,
                                blockSize,
                                cctx->tmpWorkspace, cctx->tmpWkspSize /* statically allocated in resetCCtx */,
                                ZSTD_CCtx_get_bmi2(cctx));
        FORWARD_IF_ERROR(compressedSeqsSize, "Compressing sequences of block failed");
        DEBUGLOG(5, "Compressed sequences size: %zu", compressedSeqsSize);

        if (!cctx->isFirstBlock &&
            ZSTD_maybeRLE(&cctx->seqStore) &&
            ZSTD_isRLE(ip, blockSize)) {

            compressedSeqsSize = 1;
        }

        if (compressedSeqsSize == 0) {

            cBlockSize = ZSTD_noCompressBlock(op, dstCapacity, ip, blockSize, lastBlock);
            FORWARD_IF_ERROR(cBlockSize, "ZSTD_noCompressBlock failed");
            DEBUGLOG(5, "Writing out nocompress block, size: %zu", cBlockSize);
        } else if (compressedSeqsSize == 1) {
            cBlockSize = ZSTD_rleCompressBlock(op, dstCapacity, *ip, blockSize, lastBlock);
            FORWARD_IF_ERROR(cBlockSize, "ZSTD_rleCompressBlock failed");
            DEBUGLOG(5, "Writing out RLE block, size: %zu", cBlockSize);
        } else {
            U32 cBlockHeader;

            ZSTD_blockState_confirmRepcodesAndEntropyTables(&cctx->blockState);
            if (cctx->blockState.prevCBlock->entropy.fse.offcode_repeatMode == FSE_repeat_valid)
                cctx->blockState.prevCBlock->entropy.fse.offcode_repeatMode = FSE_repeat_check;


            cBlockHeader = lastBlock + (((U32)bt_compressed)<<1) + (U32)(compressedSeqsSize << 3);
            MEM_writeLE24(op, cBlockHeader);
            cBlockSize = ZSTD_blockHeaderSize + compressedSeqsSize;
            DEBUGLOG(5, "Writing out compressed block, size: %zu", cBlockSize);
        }

        cSize += cBlockSize;

        if (lastBlock) {
            break;
        } else {
            ip += blockSize;
            op += cBlockSize;
            remaining -= blockSize;
            dstCapacity -= cBlockSize;
            cctx->isFirstBlock = 0;
        }
        DEBUGLOG(5, "cSize running total: %zu (remaining dstCapacity=%zu)", cSize, dstCapacity);
    }

    DEBUGLOG(4, "cSize final total: %zu", cSize);
    return cSize;
}

size_t ZSTD_compressSequences(ZSTD_CCtx* cctx,
                              void* dst, size_t dstCapacity,
                              const ZSTD_Sequence* inSeqs, size_t inSeqsSize,
                              const void* src, size_t srcSize)
{
    BYTE* op = (BYTE*)dst;
    size_t cSize = 0;


    DEBUGLOG(4, "ZSTD_compressSequences (nbSeqs=%zu,dstCapacity=%zu)", inSeqsSize, dstCapacity);
    assert(cctx != NULL);
    FORWARD_IF_ERROR(ZSTD_CCtx_init_compressStream2(cctx, ZSTD_e_end, srcSize), "CCtx initialization failed");


    {   size_t const frameHeaderSize = ZSTD_writeFrameHeader(op, dstCapacity,
                    &cctx->appliedParams, srcSize, cctx->dictID);
        FORWARD_IF_ERROR(frameHeaderSize, "ZSTD_writeFrameHeader failed");
        op += frameHeaderSize;
        assert(frameHeaderSize <= dstCapacity);
        dstCapacity -= frameHeaderSize;
        cSize += frameHeaderSize;
    }
    if (cctx->appliedParams.fParams.checksumFlag && srcSize) {
        XXH64_update(&cctx->xxhState, src, srcSize);
    }


    {   size_t const cBlocksSize = ZSTD_compressSequences_internal(cctx,
                                                           op, dstCapacity,
                                                           inSeqs, inSeqsSize,
                                                           src, srcSize);
        FORWARD_IF_ERROR(cBlocksSize, "Compressing blocks failed!");
        cSize += cBlocksSize;
        assert(cBlocksSize <= dstCapacity);
        dstCapacity -= cBlocksSize;
    }


    if (cctx->appliedParams.fParams.checksumFlag) {
        U32 const checksum = (U32) XXH64_digest(&cctx->xxhState);
        RETURN_ERROR_IF(dstCapacity<4, dstSize_tooSmall, "no room for checksum");
        DEBUGLOG(4, "Write checksum : %08X", (unsigned)checksum);
        MEM_writeLE32((char*)dst + cSize, checksum);
        cSize += 4;
    }

    DEBUGLOG(4, "Final compressed size: %zu", cSize);
    return cSize;
}


#if defined(ZSTD_ARCH_X86_AVX2)

#include <immintrin.h>  /* AVX2 intrinsics */


size_t convertSequences_noRepcodes(
    SeqDef* dstSeqs,
    const ZSTD_Sequence* inSeqs,
    size_t nbSequences)
{

    const __m256i addition = _mm256_setr_epi32(
        ZSTD_REP_NUM, 0, -MINMATCH, 0,    /* for sequence i */
        ZSTD_REP_NUM, 0, -MINMATCH, 0     /* for sequence i+1 */
    );


    const __m256i limit = _mm256_set1_epi32(65535);


    const __m256i mask = _mm256_setr_epi8(

         0, 1, 2, 3,       /* offset+2 */
         4, 5,             /* litLength (16 bits) */
         8, 9,             /* matchLength (16 bits) */
         (BYTE)0x80, (BYTE)0x80, (BYTE)0x80, (BYTE)0x80,
         (BYTE)0x80, (BYTE)0x80, (BYTE)0x80, (BYTE)0x80,


        16,17,18,19,       /* offset+2 */
        20,21,             /* litLength */
        24,25,             /* matchLength */
        (BYTE)0x80, (BYTE)0x80, (BYTE)0x80, (BYTE)0x80,
        (BYTE)0x80, (BYTE)0x80, (BYTE)0x80, (BYTE)0x80
    );


#define PERM_LANE_0X_E8 0xE8  /* [0,2,2,3] in lane indices */

    size_t longLen = 0, i = 0;


    ZSTD_STATIC_ASSERT(sizeof(ZSTD_Sequence) == 16);
    ZSTD_STATIC_ASSERT(offsetof(ZSTD_Sequence, offset) == 0);
    ZSTD_STATIC_ASSERT(offsetof(ZSTD_Sequence, litLength) == 4);
    ZSTD_STATIC_ASSERT(offsetof(ZSTD_Sequence, matchLength) == 8);
    ZSTD_STATIC_ASSERT(sizeof(SeqDef) == 8);
    ZSTD_STATIC_ASSERT(offsetof(SeqDef, offBase) == 0);
    ZSTD_STATIC_ASSERT(offsetof(SeqDef, litLength) == 4);
    ZSTD_STATIC_ASSERT(offsetof(SeqDef, mlBase) == 6);


    for (; i + 1 < nbSequences; i += 2) {

        __m256i vin  = _mm256_loadu_si256((const __m256i*)(const void*)&inSeqs[i]);


        __m256i vadd = _mm256_add_epi32(vin, addition);


        __m256i ll_cmp  = _mm256_cmpgt_epi32(vadd, limit);  /* 0xFFFFFFFF for element > 65535 */
        int ll_res  = _mm256_movemask_epi8(ll_cmp);


        __m256i vshf = _mm256_shuffle_epi8(vadd, mask);



        __m256i vperm = _mm256_permute4x64_epi64(vshf, PERM_LANE_0X_E8);



        _mm_storeu_si128((__m128i *)(void*)&dstSeqs[i], _mm256_castsi256_si128(vperm));



        if (UNLIKELY((ll_res & 0x0FF00FF0) != 0)) {

            if (inSeqs[i].matchLength > 65535+MINMATCH) {
                assert(longLen == 0);
                longLen = i + 1;
            }
            if (inSeqs[i].litLength > 65535) {
                assert(longLen == 0);
                longLen = i + nbSequences + 1;
            }
            if (inSeqs[i+1].matchLength > 65535+MINMATCH) {
                assert(longLen == 0);
                longLen = i + 1 + 1;
            }
            if (inSeqs[i+1].litLength > 65535) {
                assert(longLen == 0);
                longLen = i + 1 + nbSequences + 1;
            }
        }
    }


    if (i < nbSequences) {

        assert(i == nbSequences - 1);
        dstSeqs[i].offBase = OFFSET_TO_OFFBASE(inSeqs[i].offset);
        dstSeqs[i].litLength = (U16)inSeqs[i].litLength;
        dstSeqs[i].mlBase = (U16)(inSeqs[i].matchLength - MINMATCH);

        if (UNLIKELY(inSeqs[i].matchLength > 65535+MINMATCH)) {
            assert(longLen == 0);
            longLen = i + 1;
        }
        if (UNLIKELY(inSeqs[i].litLength > 65535)) {
            assert(longLen == 0);
            longLen = i + nbSequences + 1;
        }
    }

    return longLen;
}

#elif defined (ZSTD_ARCH_RISCV_RVV)
#include <riscv_vector.h>

size_t convertSequences_noRepcodes(SeqDef* dstSeqs, const ZSTD_Sequence* inSeqs, size_t nbSequences) {
    size_t longLen = 0;
    size_t vl = 0;
    typedef uint32_t __attribute__((may_alias)) aliased_u32;

    ZSTD_STATIC_ASSERT(sizeof(ZSTD_Sequence) == 16);
    ZSTD_STATIC_ASSERT(offsetof(ZSTD_Sequence, offset) == 0);
    ZSTD_STATIC_ASSERT(offsetof(ZSTD_Sequence, litLength) == 4);
    ZSTD_STATIC_ASSERT(offsetof(ZSTD_Sequence, matchLength) == 8);
    ZSTD_STATIC_ASSERT(sizeof(SeqDef) == 8);
    ZSTD_STATIC_ASSERT(offsetof(SeqDef, offBase) == 0);
    ZSTD_STATIC_ASSERT(offsetof(SeqDef, litLength) == 4);
    ZSTD_STATIC_ASSERT(offsetof(SeqDef, mlBase) == 6);
    
    for (size_t i = 0; i < nbSequences; i += vl) {

        vl = __riscv_vsetvl_e32m2(nbSequences-i);       
        {
            // Loading structure member variables
            vuint32m2x4_t v_tuple = __riscv_vlseg4e32_v_u32m2x4(
                (const aliased_u32*)((const void*)&inSeqs[i]), 
                vl
            );
            vuint32m2_t v_offset = __riscv_vget_v_u32m2x4_u32m2(v_tuple, 0);
            vuint32m2_t v_lit = __riscv_vget_v_u32m2x4_u32m2(v_tuple, 1);
            vuint32m2_t v_match = __riscv_vget_v_u32m2x4_u32m2(v_tuple, 2);
            // offset + ZSTD_REP_NUM
            vuint32m2_t v_offBase = __riscv_vadd_vx_u32m2(v_offset, ZSTD_REP_NUM, vl); 
            // Check for integer overflow
            // Cast to a 16-bit variable
            vbool16_t lit_overflow = __riscv_vmsgtu_vx_u32m2_b16(v_lit, 65535, vl);
            vuint16m1_t v_lit_clamped = __riscv_vncvt_x_x_w_u16m1(v_lit, vl);

            vbool16_t ml_overflow = __riscv_vmsgtu_vx_u32m2_b16(v_match, 65535+MINMATCH, vl);
            vuint16m1_t v_ml_clamped = __riscv_vncvt_x_x_w_u16m1(__riscv_vsub_vx_u32m2(v_match, MINMATCH, vl), vl);

            // Pack two 16-bit fields into a 32-bit value (little-endian)
            // The lower 16 bits contain litLength, and the upper 16 bits contain mlBase
            vuint32m2_t v_lit_ml_combined = __riscv_vsll_vx_u32m2(
                __riscv_vwcvtu_x_x_v_u32m2(v_ml_clamped, vl), // Convert matchLength to 32-bit
                16, 
                vl
            );
            v_lit_ml_combined = __riscv_vor_vv_u32m2(
                v_lit_ml_combined,
                __riscv_vwcvtu_x_x_v_u32m2(v_lit_clamped, vl),
                vl
            );
            {
                // Create a vector of SeqDef structures
                // Store the offBase, litLength, and mlBase in a vector of SeqDef
                vuint32m2x2_t store_data = __riscv_vcreate_v_u32m2x2(
                    v_offBase,          
                    v_lit_ml_combined   
                );
                __riscv_vsseg2e32_v_u32m2x2(
                    (aliased_u32*)((void*)&dstSeqs[i]), 
                    store_data,             
                    vl                      
                );
            }
            {
                // Find the first index where an overflow occurs
                int first_ml = __riscv_vfirst_m_b16(ml_overflow, vl);
                int first_lit = __riscv_vfirst_m_b16(lit_overflow, vl);

                if (UNLIKELY(first_ml != -1)) {
                    assert(longLen == 0);
                    longLen = i + first_ml + 1;
                }
                if (UNLIKELY(first_lit != -1)) {
                    assert(longLen == 0);
                    longLen = i + first_lit + 1 + nbSequences;
                }
            }
        }
    }
    return longLen;
}



#elif defined(ZSTD_ARCH_ARM_SVE2)


FORCE_INLINE_TEMPLATE int cmpgtz_any_s8(svbool_t g, svint8_t a)
{
    svbool_t ptest = svcmpgt_n_s8(g, a, 0);
    return svptest_any(ptest, ptest);
}

size_t convertSequences_noRepcodes(
    SeqDef* dstSeqs,
    const ZSTD_Sequence* inSeqs,
    size_t nbSequences)
{

    const size_t lanes = 8 * svcntb() / sizeof(ZSTD_Sequence);
    size_t longLen = 0;
    size_t n = 0;


    ZSTD_STATIC_ASSERT(sizeof(ZSTD_Sequence) == 16);
    ZSTD_STATIC_ASSERT(offsetof(ZSTD_Sequence, offset) == 0);
    ZSTD_STATIC_ASSERT(offsetof(ZSTD_Sequence, litLength) == 4);
    ZSTD_STATIC_ASSERT(offsetof(ZSTD_Sequence, matchLength) == 8);
    ZSTD_STATIC_ASSERT(sizeof(SeqDef) == 8);
    ZSTD_STATIC_ASSERT(offsetof(SeqDef, offBase) == 0);
    ZSTD_STATIC_ASSERT(offsetof(SeqDef, litLength) == 4);
    ZSTD_STATIC_ASSERT(offsetof(SeqDef, mlBase) == 6);

    if (nbSequences >= lanes) {
        const svbool_t ptrue = svptrue_b8();

        const svuint32_t vaddition = svreinterpret_u32(
            svunpklo_s32(svreinterpret_s16(svdup_n_u64(ZSTD_REP_NUM | (((U64)(U16)-MINMATCH) << 32)))));

        const svuint16_t vmask = svreinterpret_u16(
            svindex_u64(0x0004000200010000, 0x0008000800080008));

        const svbool_t pmid = svcmpne_n_u8(
            ptrue, svreinterpret_u8(svdup_n_u64(0x0000FFFFFFFF0000)), 0);

        do {

            const svuint32_t vin0 = svld1_vnum_u32(ptrue, &inSeqs[n].offset, 0);
            const svuint32_t vin1 = svld1_vnum_u32(ptrue, &inSeqs[n].offset, 1);
            const svuint32_t vin2 = svld1_vnum_u32(ptrue, &inSeqs[n].offset, 2);
            const svuint32_t vin3 = svld1_vnum_u32(ptrue, &inSeqs[n].offset, 3);
            const svuint32_t vin4 = svld1_vnum_u32(ptrue, &inSeqs[n].offset, 4);
            const svuint32_t vin5 = svld1_vnum_u32(ptrue, &inSeqs[n].offset, 5);
            const svuint32_t vin6 = svld1_vnum_u32(ptrue, &inSeqs[n].offset, 6);
            const svuint32_t vin7 = svld1_vnum_u32(ptrue, &inSeqs[n].offset, 7);


            const svuint16x2_t vadd01 = svcreate2_u16(
                svreinterpret_u16(svadd_u32_x(ptrue, vin0, vaddition)),
                svreinterpret_u16(svadd_u32_x(ptrue, vin1, vaddition)));
            const svuint16x2_t vadd23 = svcreate2_u16(
                svreinterpret_u16(svadd_u32_x(ptrue, vin2, vaddition)),
                svreinterpret_u16(svadd_u32_x(ptrue, vin3, vaddition)));
            const svuint16x2_t vadd45 = svcreate2_u16(
                svreinterpret_u16(svadd_u32_x(ptrue, vin4, vaddition)),
                svreinterpret_u16(svadd_u32_x(ptrue, vin5, vaddition)));
            const svuint16x2_t vadd67 = svcreate2_u16(
                svreinterpret_u16(svadd_u32_x(ptrue, vin6, vaddition)),
                svreinterpret_u16(svadd_u32_x(ptrue, vin7, vaddition)));


            const svuint16_t vout01 = svtbl2_u16(vadd01, vmask);
            const svuint16_t vout23 = svtbl2_u16(vadd23, vmask);
            const svuint16_t vout45 = svtbl2_u16(vadd45, vmask);
            const svuint16_t vout67 = svtbl2_u16(vadd67, vmask);


            const svuint16_t voverflow01 = svuzp2_u16(svget2_u16(vadd01, 0),
                                                      svget2_u16(vadd01, 1));
            const svuint16_t voverflow23 = svuzp2_u16(svget2_u16(vadd23, 0),
                                                      svget2_u16(vadd23, 1));
            const svuint16_t voverflow45 = svuzp2_u16(svget2_u16(vadd45, 0),
                                                      svget2_u16(vadd45, 1));
            const svuint16_t voverflow67 = svuzp2_u16(svget2_u16(vadd67, 0),
                                                      svget2_u16(vadd67, 1));


            const svint8_t voverflow =
                svmax_s8_x(pmid,
                           svtrn1_s8(svreinterpret_s8(voverflow01),
                                     svreinterpret_s8(voverflow23)),
                           svtrn1_s8(svreinterpret_s8(voverflow45),
                                     svreinterpret_s8(voverflow67)));


            svst1_vnum_u32(ptrue, &dstSeqs[n].offBase, 0, svreinterpret_u32(vout01));
            svst1_vnum_u32(ptrue, &dstSeqs[n].offBase, 1, svreinterpret_u32(vout23));
            svst1_vnum_u32(ptrue, &dstSeqs[n].offBase, 2, svreinterpret_u32(vout45));
            svst1_vnum_u32(ptrue, &dstSeqs[n].offBase, 3, svreinterpret_u32(vout67));


            if (UNLIKELY(cmpgtz_any_s8(pmid, voverflow))) {

                size_t i;
                for (i = n; i < n + lanes; i++) {
                    if (inSeqs[i].matchLength > 65535 + MINMATCH) {
                        assert(longLen == 0);
                        longLen = i + 1;
                    }
                    if (inSeqs[i].litLength > 65535) {
                        assert(longLen == 0);
                        longLen = i + nbSequences + 1;
                    }
                }
            }

            n += lanes;
        } while(n <= nbSequences - lanes);
    }


    for (; n < nbSequences; n++) {
        dstSeqs[n].offBase = OFFSET_TO_OFFBASE(inSeqs[n].offset);
        dstSeqs[n].litLength = (U16)inSeqs[n].litLength;
        dstSeqs[n].mlBase = (U16)(inSeqs[n].matchLength - MINMATCH);

        if (UNLIKELY(inSeqs[n].matchLength > 65535 + MINMATCH)) {
            assert(longLen == 0);
            longLen = n + 1;
        }
        if (UNLIKELY(inSeqs[n].litLength > 65535)) {
            assert(longLen == 0);
            longLen = n + nbSequences + 1;
        }
    }
    return longLen;
}

#elif defined(ZSTD_ARCH_ARM_NEON) && (defined(__aarch64__) || defined(_M_ARM64))

size_t convertSequences_noRepcodes(
    SeqDef* dstSeqs,
    const ZSTD_Sequence* inSeqs,
    size_t nbSequences)
{
    size_t longLen = 0;
    size_t n = 0;


    ZSTD_STATIC_ASSERT(sizeof(ZSTD_Sequence) == 16);
    ZSTD_STATIC_ASSERT(offsetof(ZSTD_Sequence, offset) == 0);
    ZSTD_STATIC_ASSERT(offsetof(ZSTD_Sequence, litLength) == 4);
    ZSTD_STATIC_ASSERT(offsetof(ZSTD_Sequence, matchLength) == 8);
    ZSTD_STATIC_ASSERT(sizeof(SeqDef) == 8);
    ZSTD_STATIC_ASSERT(offsetof(SeqDef, offBase) == 0);
    ZSTD_STATIC_ASSERT(offsetof(SeqDef, litLength) == 4);
    ZSTD_STATIC_ASSERT(offsetof(SeqDef, mlBase) == 6);

    if (nbSequences > 3) {
        static const ZSTD_ALIGNED(16) U32 constAddition[4] = {
            ZSTD_REP_NUM, 0, -MINMATCH, 0
        };
        static const ZSTD_ALIGNED(16) U8 constMask[16] = {
            0, 1, 2, 3, 4, 5, 8, 9, 16, 17, 18, 19, 20, 21, 24, 25
        };
        static const ZSTD_ALIGNED(16) U16 constCounter[8] = {
            1, 1, 1, 1, 2, 2, 2, 2
        };

        const uint32x4_t vaddition = vld1q_u32(constAddition);
        const uint8x16_t vmask = vld1q_u8(constMask);
        uint16x8_t vcounter = vld1q_u16(constCounter);
        uint16x8_t vindex01 = vdupq_n_u16(0);
        uint16x8_t vindex23 = vdupq_n_u16(0);

        do {

            const uint32x4_t vin0 = vld1q_u32(&inSeqs[n + 0].offset);
            const uint32x4_t vin1 = vld1q_u32(&inSeqs[n + 1].offset);
            const uint32x4_t vin2 = vld1q_u32(&inSeqs[n + 2].offset);
            const uint32x4_t vin3 = vld1q_u32(&inSeqs[n + 3].offset);


            const uint8x16x2_t vadd01 = { {
                vreinterpretq_u8_u32(vaddq_u32(vin0, vaddition)),
                vreinterpretq_u8_u32(vaddq_u32(vin1, vaddition)),
            } };
            const uint8x16x2_t vadd23 = { {
                vreinterpretq_u8_u32(vaddq_u32(vin2, vaddition)),
                vreinterpretq_u8_u32(vaddq_u32(vin3, vaddition)),
            } };


            const uint8x16_t vout01 = vqtbl2q_u8(vadd01, vmask);
            const uint8x16_t vout23 = vqtbl2q_u8(vadd23, vmask);


            uint16x8_t voverflow01 = vuzp2q_u16(vreinterpretq_u16_u8(vadd01.val[0]),
                                                vreinterpretq_u16_u8(vadd01.val[1]));
            uint16x8_t voverflow23 = vuzp2q_u16(vreinterpretq_u16_u8(vadd23.val[0]),
                                                vreinterpretq_u16_u8(vadd23.val[1]));


            vst1q_u32(&dstSeqs[n + 0].offBase, vreinterpretq_u32_u8(vout01));
            vst1q_u32(&dstSeqs[n + 2].offBase, vreinterpretq_u32_u8(vout23));


            voverflow01 = vcgtzq_s16(vreinterpretq_s16_u16(voverflow01));
            voverflow23 = vcgtzq_s16(vreinterpretq_s16_u16(voverflow23));


            vindex01 = vbslq_u16(voverflow01, vcounter, vindex01);
            vindex23 = vbslq_u16(voverflow23, vcounter, vindex23);


            vcounter = vaddq_u16(vcounter, vdupq_n_u16(4));

            n += 4;
        } while(n < nbSequences - 3);


        {   uint16x8_t nonzero = vtstq_u16(vindex23, vindex23);
            vindex23 = vsubq_u16(vindex23, nonzero);
            vindex23 = vsubq_u16(vindex23, nonzero);
        }


        vindex01 = vmaxq_u16(vindex01, vindex23);
        vindex01 = vmaxq_u16(vindex01, vextq_u16(vindex01, vindex01, 4));


        {   U64 maxLitMatchIndices = vgetq_lane_u64(vreinterpretq_u64_u16(vindex01), 0);
            size_t maxLitIndex = (maxLitMatchIndices >> 16) & 0xFFFF;
            size_t maxMatchIndex = (maxLitMatchIndices >> 32) & 0xFFFF;
            longLen = maxLitIndex > maxMatchIndex ? maxLitIndex + nbSequences
                                                  : maxMatchIndex;
        }
    }


    for (; n < nbSequences; n++) {
        dstSeqs[n].offBase = OFFSET_TO_OFFBASE(inSeqs[n].offset);
        dstSeqs[n].litLength = (U16)inSeqs[n].litLength;
        dstSeqs[n].mlBase = (U16)(inSeqs[n].matchLength - MINMATCH);

        if (UNLIKELY(inSeqs[n].matchLength > 65535 + MINMATCH)) {
            assert(longLen == 0);
            longLen = n + 1;
        }
        if (UNLIKELY(inSeqs[n].litLength > 65535)) {
            assert(longLen == 0);
            longLen = n + nbSequences + 1;
        }
    }
    return longLen;
}

#else /* No vectorization. */

size_t convertSequences_noRepcodes(
    SeqDef* dstSeqs,
    const ZSTD_Sequence* inSeqs,
    size_t nbSequences)
{
    size_t longLen = 0;
    size_t n;
    for (n=0; n<nbSequences; n++) {
        dstSeqs[n].offBase = OFFSET_TO_OFFBASE(inSeqs[n].offset);
        dstSeqs[n].litLength = (U16)inSeqs[n].litLength;
        dstSeqs[n].mlBase = (U16)(inSeqs[n].matchLength - MINMATCH);

        if (UNLIKELY(inSeqs[n].matchLength > 65535+MINMATCH)) {
            assert(longLen == 0);
            longLen = n + 1;
        }
        if (UNLIKELY(inSeqs[n].litLength > 65535)) {
            assert(longLen == 0);
            longLen = n + nbSequences + 1;
        }
    }
    return longLen;
}

#endif


size_t ZSTD_convertBlockSequences(ZSTD_CCtx* cctx,
                const ZSTD_Sequence* const inSeqs, size_t nbSequences,
                int repcodeResolution)
{
    Repcodes_t updatedRepcodes;
    size_t seqNb = 0;

    DEBUGLOG(5, "ZSTD_convertBlockSequences (nbSequences = %zu)", nbSequences);

    RETURN_ERROR_IF(nbSequences >= cctx->seqStore.maxNbSeq, externalSequences_invalid,
                    "Not enough memory allocated. Try adjusting ZSTD_c_minMatch.");

    ZSTD_memcpy(updatedRepcodes.rep, cctx->blockState.prevCBlock->rep, sizeof(Repcodes_t));


    assert(nbSequences >= 1);
    assert(inSeqs[nbSequences-1].matchLength == 0);
    assert(inSeqs[nbSequences-1].offset == 0);


    if (!repcodeResolution) {
        size_t const longl = convertSequences_noRepcodes(cctx->seqStore.sequencesStart, inSeqs, nbSequences-1);
        cctx->seqStore.sequences = cctx->seqStore.sequencesStart + nbSequences-1;
        if (longl) {
            DEBUGLOG(5, "long length");
            assert(cctx->seqStore.longLengthType == ZSTD_llt_none);
            if (longl <= nbSequences-1) {
                DEBUGLOG(5, "long match length detected at pos %zu", longl-1);
                cctx->seqStore.longLengthType = ZSTD_llt_matchLength;
                cctx->seqStore.longLengthPos = (U32)(longl-1);
            } else {
                DEBUGLOG(5, "long literals length detected at pos %zu", longl-nbSequences);
                assert(longl <= 2* (nbSequences-1));
                cctx->seqStore.longLengthType = ZSTD_llt_literalLength;
                cctx->seqStore.longLengthPos = (U32)(longl-(nbSequences-1)-1);
            }
        }
    } else {
        for (seqNb = 0; seqNb < nbSequences - 1 ; seqNb++) {
            U32 const litLength = inSeqs[seqNb].litLength;
            U32 const matchLength = inSeqs[seqNb].matchLength;
            U32 const ll0 = (litLength == 0);
            U32 const offBase = ZSTD_finalizeOffBase(inSeqs[seqNb].offset, updatedRepcodes.rep, ll0);

            DEBUGLOG(6, "Storing sequence: (of: %u, ml: %u, ll: %u)", offBase, matchLength, litLength);
            ZSTD_storeSeqOnly(&cctx->seqStore, litLength, offBase, matchLength);
            ZSTD_updateRep(updatedRepcodes.rep, offBase, ll0);
        }
    }


    if (!repcodeResolution && nbSequences > 1) {
        U32* const rep = updatedRepcodes.rep;

        if (nbSequences >= 4) {
            U32 lastSeqIdx = (U32)nbSequences - 2; /* index of last full sequence */
            rep[2] = inSeqs[lastSeqIdx - 2].offset;
            rep[1] = inSeqs[lastSeqIdx - 1].offset;
            rep[0] = inSeqs[lastSeqIdx].offset;
        } else if (nbSequences == 3) {
            rep[2] = rep[0];
            rep[1] = inSeqs[0].offset;
            rep[0] = inSeqs[1].offset;
        } else {
            assert(nbSequences == 2);
            rep[2] = rep[1];
            rep[1] = rep[0];
            rep[0] = inSeqs[0].offset;
        }
    }

    ZSTD_memcpy(cctx->blockState.nextCBlock->rep, updatedRepcodes.rep, sizeof(Repcodes_t));

    return 0;
}

#if defined(ZSTD_ARCH_X86_AVX2)

BlockSummary ZSTD_get1BlockSummary(const ZSTD_Sequence* seqs, size_t nbSeqs)
{
    size_t i;
    __m256i const zeroVec = _mm256_setzero_si256();
    __m256i sumVec = zeroVec;  /* accumulates match+lit in 32-bit lanes */
    ZSTD_ALIGNED(32) U32 tmp[8];      /* temporary buffer for reduction */
    size_t mSum = 0, lSum = 0;
    ZSTD_STATIC_ASSERT(sizeof(ZSTD_Sequence) == 16);


    for (i = 0; i + 2 <= nbSeqs; i += 2) {

        __m256i data     = _mm256_loadu_si256((const __m256i*)(const void*)&seqs[i]);

        __m256i cmp      = _mm256_cmpeq_epi32(data, zeroVec);
        int cmp_res      = _mm256_movemask_epi8(cmp);

        ZSTD_STATIC_ASSERT(offsetof(ZSTD_Sequence, matchLength) == 8);
        if (cmp_res & 0x0F000F00) break;

        sumVec           = _mm256_add_epi32(sumVec, data);
    }


    _mm256_store_si256((__m256i*)tmp, sumVec);
    lSum = tmp[1] + tmp[5];
    mSum = tmp[2] + tmp[6];


    for (; i < nbSeqs; i++) {
        lSum += seqs[i].litLength;
        mSum += seqs[i].matchLength;
        if (seqs[i].matchLength == 0) break; /* end of block */
    }

    if (i==nbSeqs) {

        BlockSummary bs;
        bs.nbSequences = ERROR(externalSequences_invalid);
        return bs;
    }
    {   BlockSummary bs;
        bs.nbSequences = i+1;
        bs.blockSize = lSum + mSum;
        bs.litSize = lSum;
        return bs;
    }
}

#elif defined (ZSTD_ARCH_RISCV_RVV)

BlockSummary ZSTD_get1BlockSummary(const ZSTD_Sequence* seqs, size_t nbSeqs)
{
    size_t totalMatchSize = 0;
    size_t litSize = 0;
    size_t i = 0;
    int found_terminator = 0; 
    size_t vl_max = __riscv_vsetvlmax_e32m1();
    typedef uint32_t __attribute__((may_alias)) aliased_u32;
    vuint32m1_t v_lit_sum = __riscv_vmv_v_x_u32m1(0, vl_max);
    vuint32m1_t v_match_sum = __riscv_vmv_v_x_u32m1(0, vl_max);

    for (; i  < nbSeqs; ) {
        size_t vl = __riscv_vsetvl_e32m2(nbSeqs - i); 

        vuint32m2x4_t v_tuple = __riscv_vlseg4e32_v_u32m2x4(
            (const aliased_u32*)((const void*)&seqs[i]), 
            vl
        );
        vuint32m2_t v_lit = __riscv_vget_v_u32m2x4_u32m2(v_tuple, 1);
        vuint32m2_t v_match = __riscv_vget_v_u32m2x4_u32m2(v_tuple, 2);

        // Check if any element has a matchLength of 0
        vbool16_t mask = __riscv_vmseq_vx_u32m2_b16(v_match, 0, vl);
        int first_zero = __riscv_vfirst_m_b16(mask, vl);

        if (first_zero >= 0) {
            // Find the first zero byte and set the effective length to that index + 1 to 
            // recompute the cumulative vector length of literals and matches
            vl = first_zero + 1;
            
            // recompute the cumulative vector length of literals and matches
            v_lit_sum = __riscv_vredsum_vs_u32m2_u32m1(__riscv_vslidedown_vx_u32m2(v_lit, 0, vl), v_lit_sum, vl);
            v_match_sum = __riscv_vredsum_vs_u32m2_u32m1(__riscv_vslidedown_vx_u32m2(v_match, 0, vl), v_match_sum, vl);

            i += vl;
            found_terminator = 1; 
            assert(seqs[i - 1].offset == 0);
            break;
        } else {

            v_lit_sum = __riscv_vredsum_vs_u32m2_u32m1(v_lit, v_lit_sum, vl);
            v_match_sum = __riscv_vredsum_vs_u32m2_u32m1(v_match, v_match_sum, vl);
            i += vl;
        }
    }
    litSize = __riscv_vmv_x_s_u32m1_u32(v_lit_sum);
    totalMatchSize = __riscv_vmv_x_s_u32m1_u32(v_match_sum);

    if (!found_terminator && i==nbSeqs) {
        BlockSummary bs;
        bs.nbSequences = ERROR(externalSequences_invalid);
        return bs;
    }
    {   BlockSummary bs;
        bs.nbSequences = i;
        bs.blockSize = litSize + totalMatchSize;
        bs.litSize = litSize;
        return bs;
    }
}

#else


FORCE_INLINE_TEMPLATE int matchLengthHalfIsZero(U64 litMatchLength)
{
    if (MEM_isLittleEndian()) {
        return litMatchLength <= 0xFFFFFFFFULL;
    } else {
        return (U32)litMatchLength == 0;
    }
}

BlockSummary ZSTD_get1BlockSummary(const ZSTD_Sequence* seqs, size_t nbSeqs)
{

    U64 litMatchSize0 = 0;
    U64 litMatchSize1 = 0;
    U64 litMatchSize2 = 0;
    U64 litMatchSize3 = 0;
    size_t n = 0;

    ZSTD_STATIC_ASSERT(offsetof(ZSTD_Sequence, litLength) + 4 == offsetof(ZSTD_Sequence, matchLength));
    ZSTD_STATIC_ASSERT(offsetof(ZSTD_Sequence, matchLength) + 4 == offsetof(ZSTD_Sequence, rep));
    assert(seqs);

    if (nbSeqs > 3) {

        do {

            U64 litMatchLength = MEM_read64(&seqs[n].litLength);
            litMatchSize0 += litMatchLength;
            if (matchLengthHalfIsZero(litMatchLength)) {
                assert(seqs[n].offset == 0);
                goto _out;
            }

            litMatchLength = MEM_read64(&seqs[n + 1].litLength);
            litMatchSize1 += litMatchLength;
            if (matchLengthHalfIsZero(litMatchLength)) {
                n += 1;
                assert(seqs[n].offset == 0);
                goto _out;
            }

            litMatchLength = MEM_read64(&seqs[n + 2].litLength);
            litMatchSize2 += litMatchLength;
            if (matchLengthHalfIsZero(litMatchLength)) {
                n += 2;
                assert(seqs[n].offset == 0);
                goto _out;
            }

            litMatchLength = MEM_read64(&seqs[n + 3].litLength);
            litMatchSize3 += litMatchLength;
            if (matchLengthHalfIsZero(litMatchLength)) {
                n += 3;
                assert(seqs[n].offset == 0);
                goto _out;
            }

            n += 4;
        } while(n < nbSeqs - 3);
    }

    for (; n < nbSeqs; n++) {
        U64 litMatchLength = MEM_read64(&seqs[n].litLength);
        litMatchSize0 += litMatchLength;
        if (matchLengthHalfIsZero(litMatchLength)) {
            assert(seqs[n].offset == 0);
            goto _out;
        }
    }

    {   BlockSummary bs;
        bs.nbSequences = ERROR(externalSequences_invalid);
        return bs;
    }
_out:
    litMatchSize0 += litMatchSize1 + litMatchSize2 + litMatchSize3;
    {   BlockSummary bs;
        bs.nbSequences = n + 1;
        if (MEM_isLittleEndian()) {
            bs.litSize = (U32)litMatchSize0;
            bs.blockSize = bs.litSize + (litMatchSize0 >> 32);
        } else {
            bs.litSize = litMatchSize0 >> 32;
            bs.blockSize = bs.litSize + (U32)litMatchSize0;
        }
        return bs;
    }
}
#endif


static size_t
ZSTD_compressSequencesAndLiterals_internal(ZSTD_CCtx* cctx,
                                void* dst, size_t dstCapacity,
                          const ZSTD_Sequence* inSeqs, size_t nbSequences,
                          const void* literals, size_t litSize, size_t srcSize)
{
    size_t remaining = srcSize;
    size_t cSize = 0;
    BYTE* op = (BYTE*)dst;
    int const repcodeResolution = (cctx->appliedParams.searchForExternalRepcodes == ZSTD_ps_enable);
    assert(cctx->appliedParams.searchForExternalRepcodes != ZSTD_ps_auto);

    DEBUGLOG(4, "ZSTD_compressSequencesAndLiterals_internal: nbSeqs=%zu, litSize=%zu", nbSequences, litSize);
    RETURN_ERROR_IF(nbSequences == 0, externalSequences_invalid, "Requires at least 1 end-of-block");


    if ((nbSequences == 1) && (inSeqs[0].litLength == 0)) {
        U32 const cBlockHeader24 = 1 /* last block */ + (((U32)bt_raw)<<1);
        RETURN_ERROR_IF(dstCapacity<3, dstSize_tooSmall, "No room for empty frame block header");
        MEM_writeLE24(op, cBlockHeader24);
        op += ZSTD_blockHeaderSize;
        dstCapacity -= ZSTD_blockHeaderSize;
        cSize += ZSTD_blockHeaderSize;
    }

    while (nbSequences) {
        size_t compressedSeqsSize, cBlockSize, conversionStatus;
        BlockSummary const block = ZSTD_get1BlockSummary(inSeqs, nbSequences);
        U32 const lastBlock = (block.nbSequences == nbSequences);
        FORWARD_IF_ERROR(block.nbSequences, "Error while trying to determine nb of sequences for a block");
        assert(block.nbSequences <= nbSequences);
        RETURN_ERROR_IF(block.litSize > litSize, externalSequences_invalid, "discrepancy: Sequences require more literals than present in buffer");
        RETURN_ERROR_IF(block.blockSize > cctx->blockSizeMax, externalSequences_invalid, "sequences incorrectly define a too large block");
        ZSTD_resetSeqStore(&cctx->seqStore);

        conversionStatus = ZSTD_convertBlockSequences(cctx,
                            inSeqs, block.nbSequences,
                            repcodeResolution);
        FORWARD_IF_ERROR(conversionStatus, "Bad sequence conversion");
        inSeqs += block.nbSequences;
        nbSequences -= block.nbSequences;
        remaining -= block.blockSize;



        RETURN_ERROR_IF(dstCapacity < ZSTD_blockHeaderSize, dstSize_tooSmall, "not enough dstCapacity to write a new compressed block");

        compressedSeqsSize = ZSTD_entropyCompressSeqStore_internal(
                                op + ZSTD_blockHeaderSize /* Leave space for block header */, dstCapacity - ZSTD_blockHeaderSize,
                                literals, block.litSize,
                                &cctx->seqStore,
                                &cctx->blockState.prevCBlock->entropy, &cctx->blockState.nextCBlock->entropy,
                                &cctx->appliedParams,
                                cctx->tmpWorkspace, cctx->tmpWkspSize /* statically allocated in resetCCtx */,
                                ZSTD_CCtx_get_bmi2(cctx));
        FORWARD_IF_ERROR(compressedSeqsSize, "Compressing sequences of block failed");

        if (compressedSeqsSize > cctx->blockSizeMax) compressedSeqsSize = 0;
        DEBUGLOG(5, "Compressed sequences size: %zu", compressedSeqsSize);
        litSize -= block.litSize;
        literals = (const char*)literals + block.litSize;



        if (compressedSeqsSize == 0) {

            RETURN_ERROR(cannotProduce_uncompressedBlock, "ZSTD_compressSequencesAndLiterals cannot generate an uncompressed block");
        } else {
            U32 cBlockHeader;
            assert(compressedSeqsSize > 1); /* no RLE */

            ZSTD_blockState_confirmRepcodesAndEntropyTables(&cctx->blockState);
            if (cctx->blockState.prevCBlock->entropy.fse.offcode_repeatMode == FSE_repeat_valid)
                cctx->blockState.prevCBlock->entropy.fse.offcode_repeatMode = FSE_repeat_check;


            cBlockHeader = lastBlock + (((U32)bt_compressed)<<1) + (U32)(compressedSeqsSize << 3);
            MEM_writeLE24(op, cBlockHeader);
            cBlockSize = ZSTD_blockHeaderSize + compressedSeqsSize;
            DEBUGLOG(5, "Writing out compressed block, size: %zu", cBlockSize);
        }

        cSize += cBlockSize;
        op += cBlockSize;
        dstCapacity -= cBlockSize;
        cctx->isFirstBlock = 0;
        DEBUGLOG(5, "cSize running total: %zu (remaining dstCapacity=%zu)", cSize, dstCapacity);

        if (lastBlock) {
            assert(nbSequences == 0);
            break;
        }
    }

    RETURN_ERROR_IF(litSize != 0, externalSequences_invalid, "literals must be entirely and exactly consumed");
    RETURN_ERROR_IF(remaining != 0, externalSequences_invalid, "Sequences must represent a total of exactly srcSize=%zu", srcSize);
    DEBUGLOG(4, "cSize final total: %zu", cSize);
    return cSize;
}

size_t
ZSTD_compressSequencesAndLiterals(ZSTD_CCtx* cctx,
                    void* dst, size_t dstCapacity,
                    const ZSTD_Sequence* inSeqs, size_t inSeqsSize,
                    const void* literals, size_t litSize, size_t litCapacity,
                    size_t decompressedSize)
{
    BYTE* op = (BYTE*)dst;
    size_t cSize = 0;


    DEBUGLOG(4, "ZSTD_compressSequencesAndLiterals (dstCapacity=%zu)", dstCapacity);
    assert(cctx != NULL);
    if (litCapacity < litSize || litCapacity - litSize < 8) {
        RETURN_ERROR(workSpace_tooSmall, "literals buffer is not large enough: must be at least 8 bytes larger than litSize (risk of read out-of-bound)");
    }
    FORWARD_IF_ERROR(ZSTD_CCtx_init_compressStream2(cctx, ZSTD_e_end, decompressedSize), "CCtx initialization failed");

    if (cctx->appliedParams.blockDelimiters == ZSTD_sf_noBlockDelimiters) {
        RETURN_ERROR(frameParameter_unsupported, "This mode is only compatible with explicit delimiters");
    }
    if (cctx->appliedParams.validateSequences) {
        RETURN_ERROR(parameter_unsupported, "This mode is not compatible with Sequence validation");
    }
    if (cctx->appliedParams.fParams.checksumFlag) {
        RETURN_ERROR(frameParameter_unsupported, "this mode is not compatible with frame checksum");
    }


    {   size_t const frameHeaderSize = ZSTD_writeFrameHeader(op, dstCapacity,
                    &cctx->appliedParams, decompressedSize, cctx->dictID);
        FORWARD_IF_ERROR(frameHeaderSize, "ZSTD_writeFrameHeader failed");
        op += frameHeaderSize;
        assert(frameHeaderSize <= dstCapacity);
        dstCapacity -= frameHeaderSize;
        cSize += frameHeaderSize;
    }


    {   size_t const cBlocksSize = ZSTD_compressSequencesAndLiterals_internal(cctx,
                                            op, dstCapacity,
                                            inSeqs, inSeqsSize,
                                            literals, litSize, decompressedSize);
        FORWARD_IF_ERROR(cBlocksSize, "Compressing blocks failed!");
        cSize += cBlocksSize;
        assert(cBlocksSize <= dstCapacity);
        dstCapacity -= cBlocksSize;
    }

    DEBUGLOG(4, "Final compressed size: %zu", cSize);
    return cSize;
}



static ZSTD_inBuffer inBuffer_forEndFlush(const ZSTD_CStream* zcs)
{
    const ZSTD_inBuffer nullInput = { NULL, 0, 0 };
    const int stableInput = (zcs->appliedParams.inBufferMode == ZSTD_bm_stable)
                         || (zcs->stableIn_notConsumed > 0);  /* pending input, parameters not applied yet */
    return stableInput ? zcs->expectedInBuffer : nullInput;
}


size_t ZSTD_flushStream(ZSTD_CStream* zcs, ZSTD_outBuffer* output)
{
    ZSTD_inBuffer input = inBuffer_forEndFlush(zcs);
    input.size = input.pos; /* do not ingest more input during flush */
    return ZSTD_compressStream2(zcs, output, &input, ZSTD_e_flush);
}

size_t ZSTD_endStream(ZSTD_CStream* zcs, ZSTD_outBuffer* output)
{
    ZSTD_inBuffer input = inBuffer_forEndFlush(zcs);
    size_t const remainingToFlush = ZSTD_compressStream2(zcs, output, &input, ZSTD_e_end);
    FORWARD_IF_ERROR(remainingToFlush , "ZSTD_compressStream2(,,ZSTD_e_end) failed");
    if (zcs->appliedParams.nbWorkers > 0) return remainingToFlush;   /* minimal estimation */

    {   size_t const lastBlockSize = zcs->frameEnded ? 0 : ZSTD_BLOCKHEADERSIZE;
        size_t const checksumSize = (size_t)(zcs->frameEnded ? 0 : zcs->appliedParams.fParams.checksumFlag * 4);
        size_t const toFlush = remainingToFlush + lastBlockSize + checksumSize;
        DEBUGLOG(4, "ZSTD_endStream : remaining to flush : %u", (unsigned)toFlush);
        return toFlush;
    }
}



/**** start inlining clevels.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_CLEVELS_H
#define ZSTD_CLEVELS_H

#define ZSTD_STATIC_LINKING_ONLY  /* ZSTD_compressionParameters  */
/**** skipping file: ../zstd.h ****/



#define ZSTD_MAX_CLEVEL     22

#ifdef __GNUC__
__attribute__((__unused__))
#endif

static const ZSTD_compressionParameters ZSTD_defaultCParameters[4][ZSTD_MAX_CLEVEL+1] = {
{   /* "default" - for any srcSize > 256 KB */

    { 19, 12, 13,  1,  6,  1, ZSTD_fast    },  /* base for negative levels */
    { 19, 13, 14,  1,  7,  0, ZSTD_fast    },  /* level  1 */
    { 20, 15, 16,  1,  6,  0, ZSTD_fast    },  /* level  2 */
    { 21, 16, 17,  1,  5,  0, ZSTD_dfast   },  /* level  3 */
    { 21, 18, 18,  1,  5,  0, ZSTD_dfast   },  /* level  4 */
    { 21, 18, 19,  3,  5,  2, ZSTD_greedy  },  /* level  5 */
    { 21, 18, 19,  3,  5,  4, ZSTD_lazy    },  /* level  6 */
    { 21, 19, 20,  4,  5,  8, ZSTD_lazy    },  /* level  7 */
    { 21, 19, 20,  4,  5, 16, ZSTD_lazy2   },  /* level  8 */
    { 22, 20, 21,  4,  5, 16, ZSTD_lazy2   },  /* level  9 */
    { 22, 21, 22,  5,  5, 16, ZSTD_lazy2   },  /* level 10 */
    { 22, 21, 22,  6,  5, 16, ZSTD_lazy2   },  /* level 11 */
    { 22, 22, 23,  6,  5, 32, ZSTD_lazy2   },  /* level 12 */
    { 22, 22, 22,  4,  5, 32, ZSTD_btlazy2 },  /* level 13 */
    { 22, 22, 23,  5,  5, 32, ZSTD_btlazy2 },  /* level 14 */
    { 22, 23, 23,  6,  5, 32, ZSTD_btlazy2 },  /* level 15 */
    { 22, 22, 22,  5,  5, 48, ZSTD_btopt   },  /* level 16 */
    { 23, 23, 22,  5,  4, 64, ZSTD_btopt   },  /* level 17 */
    { 23, 23, 22,  6,  3, 64, ZSTD_btultra },  /* level 18 */
    { 23, 24, 22,  7,  3,256, ZSTD_btultra2},  /* level 19 */
    { 25, 25, 23,  7,  3,256, ZSTD_btultra2},  /* level 20 */
    { 26, 26, 24,  7,  3,512, ZSTD_btultra2},  /* level 21 */
    { 27, 27, 25,  9,  3,999, ZSTD_btultra2},  /* level 22 */
},
{   /* for srcSize <= 256 KB */

    { 18, 12, 13,  1,  5,  1, ZSTD_fast    },  /* base for negative levels */
    { 18, 13, 14,  1,  6,  0, ZSTD_fast    },  /* level  1 */
    { 18, 14, 14,  1,  5,  0, ZSTD_dfast   },  /* level  2 */
    { 18, 16, 16,  1,  4,  0, ZSTD_dfast   },  /* level  3 */
    { 18, 16, 17,  3,  5,  2, ZSTD_greedy  },  /* level  4.*/
    { 18, 17, 18,  5,  5,  2, ZSTD_greedy  },  /* level  5.*/
    { 18, 18, 19,  3,  5,  4, ZSTD_lazy    },  /* level  6.*/
    { 18, 18, 19,  4,  4,  4, ZSTD_lazy    },  /* level  7 */
    { 18, 18, 19,  4,  4,  8, ZSTD_lazy2   },  /* level  8 */
    { 18, 18, 19,  5,  4,  8, ZSTD_lazy2   },  /* level  9 */
    { 18, 18, 19,  6,  4,  8, ZSTD_lazy2   },  /* level 10 */
    { 18, 18, 19,  5,  4, 12, ZSTD_btlazy2 },  /* level 11.*/
    { 18, 19, 19,  7,  4, 12, ZSTD_btlazy2 },  /* level 12.*/
    { 18, 18, 19,  4,  4, 16, ZSTD_btopt   },  /* level 13 */
    { 18, 18, 19,  4,  3, 32, ZSTD_btopt   },  /* level 14.*/
    { 18, 18, 19,  6,  3,128, ZSTD_btopt   },  /* level 15.*/
    { 18, 19, 19,  6,  3,128, ZSTD_btultra },  /* level 16.*/
    { 18, 19, 19,  8,  3,256, ZSTD_btultra },  /* level 17.*/
    { 18, 19, 19,  6,  3,128, ZSTD_btultra2},  /* level 18.*/
    { 18, 19, 19,  8,  3,256, ZSTD_btultra2},  /* level 19.*/
    { 18, 19, 19, 10,  3,512, ZSTD_btultra2},  /* level 20.*/
    { 18, 19, 19, 12,  3,512, ZSTD_btultra2},  /* level 21.*/
    { 18, 19, 19, 13,  3,999, ZSTD_btultra2},  /* level 22.*/
},
{   /* for srcSize <= 128 KB */

    { 17, 12, 12,  1,  5,  1, ZSTD_fast    },  /* base for negative levels */
    { 17, 12, 13,  1,  6,  0, ZSTD_fast    },  /* level  1 */
    { 17, 13, 15,  1,  5,  0, ZSTD_fast    },  /* level  2 */
    { 17, 15, 16,  2,  5,  0, ZSTD_dfast   },  /* level  3 */
    { 17, 17, 17,  2,  4,  0, ZSTD_dfast   },  /* level  4 */
    { 17, 16, 17,  3,  4,  2, ZSTD_greedy  },  /* level  5 */
    { 17, 16, 17,  3,  4,  4, ZSTD_lazy    },  /* level  6 */
    { 17, 16, 17,  3,  4,  8, ZSTD_lazy2   },  /* level  7 */
    { 17, 16, 17,  4,  4,  8, ZSTD_lazy2   },  /* level  8 */
    { 17, 16, 17,  5,  4,  8, ZSTD_lazy2   },  /* level  9 */
    { 17, 16, 17,  6,  4,  8, ZSTD_lazy2   },  /* level 10 */
    { 17, 17, 17,  5,  4,  8, ZSTD_btlazy2 },  /* level 11 */
    { 17, 18, 17,  7,  4, 12, ZSTD_btlazy2 },  /* level 12 */
    { 17, 18, 17,  3,  4, 12, ZSTD_btopt   },  /* level 13.*/
    { 17, 18, 17,  4,  3, 32, ZSTD_btopt   },  /* level 14.*/
    { 17, 18, 17,  6,  3,256, ZSTD_btopt   },  /* level 15.*/
    { 17, 18, 17,  6,  3,128, ZSTD_btultra },  /* level 16.*/
    { 17, 18, 17,  8,  3,256, ZSTD_btultra },  /* level 17.*/
    { 17, 18, 17, 10,  3,512, ZSTD_btultra },  /* level 18.*/
    { 17, 18, 17,  5,  3,256, ZSTD_btultra2},  /* level 19.*/
    { 17, 18, 17,  7,  3,512, ZSTD_btultra2},  /* level 20.*/
    { 17, 18, 17,  9,  3,512, ZSTD_btultra2},  /* level 21.*/
    { 17, 18, 17, 11,  3,999, ZSTD_btultra2},  /* level 22.*/
},
{   /* for srcSize <= 16 KB */

    { 14, 12, 13,  1,  5,  1, ZSTD_fast    },  /* base for negative levels */
    { 14, 14, 15,  1,  5,  0, ZSTD_fast    },  /* level  1 */
    { 14, 14, 15,  1,  4,  0, ZSTD_fast    },  /* level  2 */
    { 14, 14, 15,  2,  4,  0, ZSTD_dfast   },  /* level  3 */
    { 14, 14, 14,  4,  4,  2, ZSTD_greedy  },  /* level  4 */
    { 14, 14, 14,  3,  4,  4, ZSTD_lazy    },  /* level  5.*/
    { 14, 14, 14,  4,  4,  8, ZSTD_lazy2   },  /* level  6 */
    { 14, 14, 14,  6,  4,  8, ZSTD_lazy2   },  /* level  7 */
    { 14, 14, 14,  8,  4,  8, ZSTD_lazy2   },  /* level  8.*/
    { 14, 15, 14,  5,  4,  8, ZSTD_btlazy2 },  /* level  9.*/
    { 14, 15, 14,  9,  4,  8, ZSTD_btlazy2 },  /* level 10.*/
    { 14, 15, 14,  3,  4, 12, ZSTD_btopt   },  /* level 11.*/
    { 14, 15, 14,  4,  3, 24, ZSTD_btopt   },  /* level 12.*/
    { 14, 15, 14,  5,  3, 32, ZSTD_btultra },  /* level 13.*/
    { 14, 15, 15,  6,  3, 64, ZSTD_btultra },  /* level 14.*/
    { 14, 15, 15,  7,  3,256, ZSTD_btultra },  /* level 15.*/
    { 14, 15, 15,  5,  3, 48, ZSTD_btultra2},  /* level 16.*/
    { 14, 15, 15,  6,  3,128, ZSTD_btultra2},  /* level 17.*/
    { 14, 15, 15,  7,  3,256, ZSTD_btultra2},  /* level 18.*/
    { 14, 15, 15,  8,  3,256, ZSTD_btultra2},  /* level 19.*/
    { 14, 15, 15,  8,  3,512, ZSTD_btultra2},  /* level 20.*/
    { 14, 15, 15,  9,  3,512, ZSTD_btultra2},  /* level 21.*/
    { 14, 15, 15, 10,  3,999, ZSTD_btultra2},  /* level 22.*/
},
};



#endif  /* ZSTD_CLEVELS_H */
/**** ended inlining clevels.h ****/

int ZSTD_maxCLevel(void) { return ZSTD_MAX_CLEVEL; }
int ZSTD_minCLevel(void) { return (int)-ZSTD_TARGETLENGTH_MAX; }
int ZSTD_defaultCLevel(void) { return ZSTD_CLEVEL_DEFAULT; }

static ZSTD_compressionParameters ZSTD_dedicatedDictSearch_getCParams(int const compressionLevel, size_t const dictSize)
{
    ZSTD_compressionParameters cParams = ZSTD_getCParams_internal(compressionLevel, 0, dictSize, ZSTD_cpm_createCDict);
    switch (cParams.strategy) {
        case ZSTD_fast:
        case ZSTD_dfast:
            break;
        case ZSTD_greedy:
        case ZSTD_lazy:
        case ZSTD_lazy2:
            cParams.hashLog += ZSTD_LAZY_DDSS_BUCKET_LOG;
            break;
        case ZSTD_btlazy2:
        case ZSTD_btopt:
        case ZSTD_btultra:
        case ZSTD_btultra2:
            break;
    }
    return cParams;
}

static int ZSTD_dedicatedDictSearch_isSupported(
        ZSTD_compressionParameters const* cParams)
{
    return (cParams->strategy >= ZSTD_greedy)
        && (cParams->strategy <= ZSTD_lazy2)
        && (cParams->hashLog > cParams->chainLog)
        && (cParams->chainLog <= 24);
}


static void ZSTD_dedicatedDictSearch_revertCParams(
        ZSTD_compressionParameters* cParams) {
    switch (cParams->strategy) {
        case ZSTD_fast:
        case ZSTD_dfast:
            break;
        case ZSTD_greedy:
        case ZSTD_lazy:
        case ZSTD_lazy2:
            cParams->hashLog -= ZSTD_LAZY_DDSS_BUCKET_LOG;
            if (cParams->hashLog < ZSTD_HASHLOG_MIN) {
                cParams->hashLog = ZSTD_HASHLOG_MIN;
            }
            break;
        case ZSTD_btlazy2:
        case ZSTD_btopt:
        case ZSTD_btultra:
        case ZSTD_btultra2:
            break;
    }
}

static U64 ZSTD_getCParamRowSize(U64 srcSizeHint, size_t dictSize, ZSTD_CParamMode_e mode)
{
    switch (mode) {
    case ZSTD_cpm_unknown:
    case ZSTD_cpm_noAttachDict:
    case ZSTD_cpm_createCDict:
        break;
    case ZSTD_cpm_attachDict:
        dictSize = 0;
        break;
    default:
        assert(0);
        break;
    }
    {   int const unknown = srcSizeHint == ZSTD_CONTENTSIZE_UNKNOWN;
        size_t const addedSize = unknown && dictSize > 0 ? 500 : 0;
        return unknown && dictSize == 0 ? ZSTD_CONTENTSIZE_UNKNOWN : srcSizeHint+dictSize+addedSize;
    }
}


static ZSTD_compressionParameters ZSTD_getCParams_internal(int compressionLevel, unsigned long long srcSizeHint, size_t dictSize, ZSTD_CParamMode_e mode)
{
    U64 const rSize = ZSTD_getCParamRowSize(srcSizeHint, dictSize, mode);
    U32 const tableID = (rSize <= 256 KB) + (rSize <= 128 KB) + (rSize <= 16 KB);
    int row;
    DEBUGLOG(5, "ZSTD_getCParams_internal (cLevel=%i)", compressionLevel);


    if (compressionLevel == 0) row = ZSTD_CLEVEL_DEFAULT;   /* 0 == default */
    else if (compressionLevel < 0) row = 0;   /* entry 0 is baseline for fast mode */
    else if (compressionLevel > ZSTD_MAX_CLEVEL) row = ZSTD_MAX_CLEVEL;
    else row = compressionLevel;

    {   ZSTD_compressionParameters cp = ZSTD_defaultCParameters[tableID][row];
        DEBUGLOG(5, "ZSTD_getCParams_internal selected tableID: %u row: %u strat: %u", tableID, row, (U32)cp.strategy);

        if (compressionLevel < 0) {
            int const clampedCompressionLevel = MAX(ZSTD_minCLevel(), compressionLevel);
            cp.targetLength = (unsigned)(-clampedCompressionLevel);
        }

        return ZSTD_adjustCParams_internal(cp, srcSizeHint, dictSize, mode, ZSTD_ps_auto);
    }
}


ZSTD_compressionParameters ZSTD_getCParams(int compressionLevel, unsigned long long srcSizeHint, size_t dictSize)
{
    if (srcSizeHint == 0) srcSizeHint = ZSTD_CONTENTSIZE_UNKNOWN;
    return ZSTD_getCParams_internal(compressionLevel, srcSizeHint, dictSize, ZSTD_cpm_unknown);
}


static ZSTD_parameters
ZSTD_getParams_internal(int compressionLevel, unsigned long long srcSizeHint, size_t dictSize, ZSTD_CParamMode_e mode)
{
    ZSTD_parameters params;
    ZSTD_compressionParameters const cParams = ZSTD_getCParams_internal(compressionLevel, srcSizeHint, dictSize, mode);
    DEBUGLOG(5, "ZSTD_getParams (cLevel=%i)", compressionLevel);
    ZSTD_memset(&params, 0, sizeof(params));
    params.cParams = cParams;
    params.fParams.contentSizeFlag = 1;
    return params;
}


ZSTD_parameters ZSTD_getParams(int compressionLevel, unsigned long long srcSizeHint, size_t dictSize)
{
    if (srcSizeHint == 0) srcSizeHint = ZSTD_CONTENTSIZE_UNKNOWN;
    return ZSTD_getParams_internal(compressionLevel, srcSizeHint, dictSize, ZSTD_cpm_unknown);
}

void ZSTD_registerSequenceProducer(
    ZSTD_CCtx* zc,
    void* extSeqProdState,
    ZSTD_sequenceProducer_F extSeqProdFunc)
{
    assert(zc != NULL);
    ZSTD_CCtxParams_registerSequenceProducer(
        &zc->requestedParams, extSeqProdState, extSeqProdFunc
    );
}

void ZSTD_CCtxParams_registerSequenceProducer(
  ZSTD_CCtx_params* params,
  void* extSeqProdState,
  ZSTD_sequenceProducer_F extSeqProdFunc)
{
    assert(params != NULL);
    if (extSeqProdFunc != NULL) {
        params->extSeqProdFunc = extSeqProdFunc;
        params->extSeqProdState = extSeqProdState;
    } else {
        params->extSeqProdFunc = NULL;
        params->extSeqProdState = NULL;
    }
}
/**** ended inlining compress/zstd_compress.c ****/
// @ivoanjo: Level 1 doesn't use this compressor, so omit it to reduce zstd.c size.
// #include "compress/zstd_double_fast.c"
/**** start inlining compress/zstd_fast.c ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

/**** skipping file: zstd_compress_internal.h ****/
/**** skipping file: zstd_fast.h ****/

static
ZSTD_ALLOW_POINTER_OVERFLOW_ATTR
void ZSTD_fillHashTableForCDict(ZSTD_MatchState_t* ms,
                        const void* const end,
                        ZSTD_dictTableLoadMethod_e dtlm)
{
    const ZSTD_compressionParameters* const cParams = &ms->cParams;
    U32* const hashTable = ms->hashTable;
    U32  const hBits = cParams->hashLog + ZSTD_SHORT_CACHE_TAG_BITS;
    U32  const mls = cParams->minMatch;
    const BYTE* const base = ms->window.base;
    const BYTE* ip = base + ms->nextToUpdate;
    const BYTE* const iend = ((const BYTE*)end) - HASH_READ_SIZE;
    const U32 fastHashFillStep = 3;


    assert(dtlm == ZSTD_dtlm_full);


    for ( ; ip + fastHashFillStep < iend + 2; ip += fastHashFillStep) {
        U32 const curr = (U32)(ip - base);
        {   size_t const hashAndTag = ZSTD_hashPtr(ip, hBits, mls);
            ZSTD_writeTaggedIndex(hashTable, hashAndTag, curr);   }

        if (dtlm == ZSTD_dtlm_fast) continue;

        {   U32 p;
            for (p = 1; p < fastHashFillStep; ++p) {
                size_t const hashAndTag = ZSTD_hashPtr(ip + p, hBits, mls);
                if (hashTable[hashAndTag >> ZSTD_SHORT_CACHE_TAG_BITS] == 0) {  /* not yet filled */
                    ZSTD_writeTaggedIndex(hashTable, hashAndTag, curr + p);
    }   }   }   }
}

static
ZSTD_ALLOW_POINTER_OVERFLOW_ATTR
void ZSTD_fillHashTableForCCtx(ZSTD_MatchState_t* ms,
                        const void* const end,
                        ZSTD_dictTableLoadMethod_e dtlm)
{
    const ZSTD_compressionParameters* const cParams = &ms->cParams;
    U32* const hashTable = ms->hashTable;
    U32  const hBits = cParams->hashLog;
    U32  const mls = cParams->minMatch;
    const BYTE* const base = ms->window.base;
    const BYTE* ip = base + ms->nextToUpdate;
    const BYTE* const iend = ((const BYTE*)end) - HASH_READ_SIZE;
    const U32 fastHashFillStep = 3;


    assert(dtlm == ZSTD_dtlm_fast);


    for ( ; ip + fastHashFillStep < iend + 2; ip += fastHashFillStep) {
        U32 const curr = (U32)(ip - base);
        size_t const hash0 = ZSTD_hashPtr(ip, hBits, mls);
        hashTable[hash0] = curr;
        if (dtlm == ZSTD_dtlm_fast) continue;

        {   U32 p;
            for (p = 1; p < fastHashFillStep; ++p) {
                size_t const hash = ZSTD_hashPtr(ip + p, hBits, mls);
                if (hashTable[hash] == 0) {  /* not yet filled */
                    hashTable[hash] = curr + p;
    }   }   }   }
}

void ZSTD_fillHashTable(ZSTD_MatchState_t* ms,
                        const void* const end,
                        ZSTD_dictTableLoadMethod_e dtlm,
                        ZSTD_tableFillPurpose_e tfp)
{
    if (tfp == ZSTD_tfp_forCDict) {
        ZSTD_fillHashTableForCDict(ms, end, dtlm);
    } else {
        ZSTD_fillHashTableForCCtx(ms, end, dtlm);
    }
}


typedef int (*ZSTD_match4Found) (const BYTE* currentPtr, const BYTE* matchAddress, U32 matchIdx, U32 idxLowLimit);

static int
ZSTD_match4Found_cmov(const BYTE* currentPtr, const BYTE* matchAddress, U32 matchIdx, U32 idxLowLimit)
{

    static const BYTE dummy[] = {0x12,0x34,0x56,0x78};


    const BYTE* mvalAddr = ZSTD_selectAddr(matchIdx, idxLowLimit, matchAddress, dummy);

    if (MEM_read32(currentPtr) != MEM_read32(mvalAddr)) return 0;

#if defined(__GNUC__)
    __asm__("");
#endif
    return matchIdx >= idxLowLimit;
}

static int
ZSTD_match4Found_branch(const BYTE* currentPtr, const BYTE* matchAddress, U32 matchIdx, U32 idxLowLimit)
{

    U32 mval;
    if (matchIdx >= idxLowLimit) {
        mval = MEM_read32(matchAddress);
    } else {
        mval = MEM_read32(currentPtr) ^ 1; /* guaranteed to not match. */
    }

    return (MEM_read32(currentPtr) == mval);
}



FORCE_INLINE_TEMPLATE
ZSTD_ALLOW_POINTER_OVERFLOW_ATTR
size_t ZSTD_compressBlock_fast_noDict_generic(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize,
        U32 const mls, int useCmov)
{
    const ZSTD_compressionParameters* const cParams = &ms->cParams;
    U32* const hashTable = ms->hashTable;
    U32 const hlog = cParams->hashLog;
    size_t const stepSize = cParams->targetLength + !(cParams->targetLength) + 1; /* min 2 */
    const BYTE* const base = ms->window.base;
    const BYTE* const istart = (const BYTE*)src;
    const U32   endIndex = (U32)((size_t)(istart - base) + srcSize);
    const U32   prefixStartIndex = ZSTD_getLowestPrefixIndex(ms, endIndex, cParams->windowLog);
    const BYTE* const prefixStart = base + prefixStartIndex;
    const BYTE* const iend = istart + srcSize;
    const BYTE* const ilimit = iend - HASH_READ_SIZE;

    const BYTE* anchor = istart;
    const BYTE* ip0 = istart;
    const BYTE* ip1;
    const BYTE* ip2;
    const BYTE* ip3;
    U32 current0;

    U32 rep_offset1 = rep[0];
    U32 rep_offset2 = rep[1];
    U32 offsetSaved1 = 0, offsetSaved2 = 0;

    size_t hash0; /* hash for ip0 */
    size_t hash1; /* hash for ip1 */
    U32 matchIdx; /* match idx for ip0 */

    U32 offcode;
    const BYTE* match0;
    size_t mLength;


    size_t step;
    const BYTE* nextStep;
    const size_t kStepIncr = (1 << (kSearchStrength - 1));
    const ZSTD_match4Found matchFound = useCmov ? ZSTD_match4Found_cmov : ZSTD_match4Found_branch;

    DEBUGLOG(5, "ZSTD_compressBlock_fast_generic");
    ip0 += (ip0 == prefixStart);
    {   U32 const curr = (U32)(ip0 - base);
        U32 const windowLow = ZSTD_getLowestPrefixIndex(ms, curr, cParams->windowLog);
        U32 const maxRep = curr - windowLow;
        if (rep_offset2 > maxRep) offsetSaved2 = rep_offset2, rep_offset2 = 0;
        if (rep_offset1 > maxRep) offsetSaved1 = rep_offset1, rep_offset1 = 0;
    }


_start: /* Requires: ip0 */

    step = stepSize;
    nextStep = ip0 + kStepIncr;


    ip1 = ip0 + 1;
    ip2 = ip0 + step;
    ip3 = ip2 + 1;

    if (ip3 >= ilimit) {
        goto _cleanup;
    }

    hash0 = ZSTD_hashPtr(ip0, hlog, mls);
    hash1 = ZSTD_hashPtr(ip1, hlog, mls);

    matchIdx = hashTable[hash0];

    do {

        const U32 rval = MEM_read32(ip2 - rep_offset1);


        current0 = (U32)(ip0 - base);
        hashTable[hash0] = current0;


        if ((MEM_read32(ip2) == rval) & (rep_offset1 > 0)) {
            ip0 = ip2;
            match0 = ip0 - rep_offset1;
            mLength = ip0[-1] == match0[-1];
            ip0 -= mLength;
            match0 -= mLength;
            offcode = REPCODE1_TO_OFFBASE;
            mLength += 4;


            hashTable[hash1] = (U32)(ip1 - base);

            goto _match;
        }

         if (matchFound(ip0, base + matchIdx, matchIdx, prefixStartIndex)) {

            hashTable[hash1] = (U32)(ip1 - base);

            goto _offset;
        }


        matchIdx = hashTable[hash1];


        hash0 = hash1;
        hash1 = ZSTD_hashPtr(ip2, hlog, mls);


        ip0 = ip1;
        ip1 = ip2;
        ip2 = ip3;


        current0 = (U32)(ip0 - base);
        hashTable[hash0] = current0;

         if (matchFound(ip0, base + matchIdx, matchIdx, prefixStartIndex)) {

            if (step <= 4) {

                hashTable[hash1] = (U32)(ip1 - base);
            }
            goto _offset;
        }


        matchIdx = hashTable[hash1];


        hash0 = hash1;
        hash1 = ZSTD_hashPtr(ip2, hlog, mls);


        ip0 = ip1;
        ip1 = ip2;
        ip2 = ip0 + step;
        ip3 = ip1 + step;


        if (ip2 >= nextStep) {
            step++;
            PREFETCH_L1(ip1 + 64);
            PREFETCH_L1(ip1 + 128);
            nextStep += kStepIncr;
        }
    } while (ip3 < ilimit);

_cleanup:



    offsetSaved2 = ((offsetSaved1 != 0) && (rep_offset1 != 0)) ? offsetSaved1 : offsetSaved2;


    rep[0] = rep_offset1 ? rep_offset1 : offsetSaved1;
    rep[1] = rep_offset2 ? rep_offset2 : offsetSaved2;


    return (size_t)(iend - anchor);

_offset: /* Requires: ip0, idx */


    match0 = base + matchIdx;
    rep_offset2 = rep_offset1;
    rep_offset1 = (U32)(ip0-match0);
    offcode = OFFSET_TO_OFFBASE(rep_offset1);
    mLength = 4;


    while (((ip0>anchor) & (match0>prefixStart)) && (ip0[-1] == match0[-1])) {
        ip0--;
        match0--;
        mLength++;
    }

_match: /* Requires: ip0, match0, offcode */


    mLength += ZSTD_count(ip0 + mLength, match0 + mLength, iend);

    ZSTD_storeSeq(seqStore, (size_t)(ip0 - anchor), anchor, iend, offcode, mLength);

    ip0 += mLength;
    anchor = ip0;


    if (ip0 <= ilimit) {

        assert(base+current0+2 > istart);  /* check base overflow */
        hashTable[ZSTD_hashPtr(base+current0+2, hlog, mls)] = current0+2;  /* here because current+2 could be > iend-8 */
        hashTable[ZSTD_hashPtr(ip0-2, hlog, mls)] = (U32)(ip0-2-base);

        if (rep_offset2 > 0) { /* rep_offset2==0 means rep_offset2 is invalidated */
            while ( (ip0 <= ilimit) && (MEM_read32(ip0) == MEM_read32(ip0 - rep_offset2)) ) {

                size_t const rLength = ZSTD_count(ip0+4, ip0+4-rep_offset2, iend) + 4;
                { U32 const tmpOff = rep_offset2; rep_offset2 = rep_offset1; rep_offset1 = tmpOff; } /* swap rep_offset2 <=> rep_offset1 */
                hashTable[ZSTD_hashPtr(ip0, hlog, mls)] = (U32)(ip0-base);
                ip0 += rLength;
                ZSTD_storeSeq(seqStore, 0 /*litLen*/, anchor, iend, REPCODE1_TO_OFFBASE, rLength);
                anchor = ip0;
                continue;   /* faster when present (confirmed on gcc-8) ... (?) */
    }   }   }

    goto _start;
}

#define ZSTD_GEN_FAST_FN(dictMode, mml, cmov)                                                       \
    static size_t ZSTD_compressBlock_fast_##dictMode##_##mml##_##cmov(                              \
            ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],                    \
            void const* src, size_t srcSize)                                                       \
    {                                                                                              \
        return ZSTD_compressBlock_fast_##dictMode##_generic(ms, seqStore, rep, src, srcSize, mml, cmov); \
    }

ZSTD_GEN_FAST_FN(noDict, 4, 1)
ZSTD_GEN_FAST_FN(noDict, 5, 1)
ZSTD_GEN_FAST_FN(noDict, 6, 1)
ZSTD_GEN_FAST_FN(noDict, 7, 1)

ZSTD_GEN_FAST_FN(noDict, 4, 0)
ZSTD_GEN_FAST_FN(noDict, 5, 0)
ZSTD_GEN_FAST_FN(noDict, 6, 0)
ZSTD_GEN_FAST_FN(noDict, 7, 0)

size_t ZSTD_compressBlock_fast(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize)
{
    U32 const mml = ms->cParams.minMatch;

    int const useCmov = ms->cParams.windowLog < 19;
    assert(ms->dictMatchState == NULL);
    if (useCmov) {
        switch(mml)
        {
        default: /* includes case 3 */
        case 4 :
            return ZSTD_compressBlock_fast_noDict_4_1(ms, seqStore, rep, src, srcSize);
        case 5 :
            return ZSTD_compressBlock_fast_noDict_5_1(ms, seqStore, rep, src, srcSize);
        case 6 :
            return ZSTD_compressBlock_fast_noDict_6_1(ms, seqStore, rep, src, srcSize);
        case 7 :
            return ZSTD_compressBlock_fast_noDict_7_1(ms, seqStore, rep, src, srcSize);
        }
    } else {

        switch(mml)
        {
        default: /* includes case 3 */
        case 4 :
            return ZSTD_compressBlock_fast_noDict_4_0(ms, seqStore, rep, src, srcSize);
        case 5 :
            return ZSTD_compressBlock_fast_noDict_5_0(ms, seqStore, rep, src, srcSize);
        case 6 :
            return ZSTD_compressBlock_fast_noDict_6_0(ms, seqStore, rep, src, srcSize);
        case 7 :
            return ZSTD_compressBlock_fast_noDict_7_0(ms, seqStore, rep, src, srcSize);
        }
    }
}

FORCE_INLINE_TEMPLATE
ZSTD_ALLOW_POINTER_OVERFLOW_ATTR
size_t ZSTD_compressBlock_fast_dictMatchState_generic(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize, U32 const mls, U32 const hasStep)
{
    const ZSTD_compressionParameters* const cParams = &ms->cParams;
    U32* const hashTable = ms->hashTable;
    U32 const hlog = cParams->hashLog;

    U32 const stepSize = cParams->targetLength + !(cParams->targetLength);
    const BYTE* const base = ms->window.base;
    const BYTE* const istart = (const BYTE*)src;
    const BYTE* ip0 = istart;
    const BYTE* ip1 = ip0 + stepSize; /* we assert below that stepSize >= 1 */
    const BYTE* anchor = istart;
    const U32   prefixStartIndex = ms->window.dictLimit;
    const BYTE* const prefixStart = base + prefixStartIndex;
    const BYTE* const iend = istart + srcSize;
    const BYTE* const ilimit = iend - HASH_READ_SIZE;
    U32 offset_1=rep[0], offset_2=rep[1];

    const ZSTD_MatchState_t* const dms = ms->dictMatchState;
    const ZSTD_compressionParameters* const dictCParams = &dms->cParams ;
    const U32* const dictHashTable = dms->hashTable;
    const U32 dictStartIndex       = dms->window.dictLimit;
    const BYTE* const dictBase     = dms->window.base;
    const BYTE* const dictStart    = dictBase + dictStartIndex;
    const BYTE* const dictEnd      = dms->window.nextSrc;
    const U32 dictIndexDelta       = prefixStartIndex - (U32)(dictEnd - dictBase);
    const U32 dictAndPrefixLength  = (U32)(istart - prefixStart + dictEnd - dictStart);
    const U32 dictHBits            = dictCParams->hashLog + ZSTD_SHORT_CACHE_TAG_BITS;


    const U32 maxDistance = 1U << cParams->windowLog;
    const U32 endIndex = (U32)((size_t)(istart - base) + srcSize);
    assert(endIndex - prefixStartIndex <= maxDistance);
    (void)maxDistance; (void)endIndex;   /* these variables are not used when assert() is disabled */

    (void)hasStep; /* not currently specialized on whether it's accelerated */


    assert(prefixStartIndex >= (U32)(dictEnd - dictBase));

    if (ms->prefetchCDictTables) {
        size_t const hashTableBytes = (((size_t)1) << dictCParams->hashLog) * sizeof(U32);
        PREFETCH_AREA(dictHashTable, hashTableBytes);
    }


    DEBUGLOG(5, "ZSTD_compressBlock_fast_dictMatchState_generic");
    ip0 += (dictAndPrefixLength == 0);

    assert(offset_1 <= dictAndPrefixLength);
    assert(offset_2 <= dictAndPrefixLength);


    assert(stepSize >= 1);
    while (ip1 <= ilimit) {   /* repcode check at (ip0 + 1) is safe because ip0 < ip1 */
        size_t mLength;
        size_t hash0 = ZSTD_hashPtr(ip0, hlog, mls);

        size_t const dictHashAndTag0 = ZSTD_hashPtr(ip0, dictHBits, mls);
        U32 dictMatchIndexAndTag = dictHashTable[dictHashAndTag0 >> ZSTD_SHORT_CACHE_TAG_BITS];
        int dictTagsMatch = ZSTD_comparePackedTags(dictMatchIndexAndTag, dictHashAndTag0);

        U32 matchIndex = hashTable[hash0];
        U32 curr = (U32)(ip0 - base);
        size_t step = stepSize;
        const size_t kStepIncr = 1 << kSearchStrength;
        const BYTE* nextStep = ip0 + kStepIncr;


        while (1) {
            const BYTE* match = base + matchIndex;
            const U32 repIndex = curr + 1 - offset_1;
            const BYTE* repMatch = (repIndex < prefixStartIndex) ?
                                   dictBase + (repIndex - dictIndexDelta) :
                                   base + repIndex;
            const size_t hash1 = ZSTD_hashPtr(ip1, hlog, mls);
            size_t const dictHashAndTag1 = ZSTD_hashPtr(ip1, dictHBits, mls);
            hashTable[hash0] = curr;   /* update hash table */

            if ((ZSTD_index_overlap_check(prefixStartIndex, repIndex))
                && (MEM_read32(repMatch) == MEM_read32(ip0 + 1))) {
                const BYTE* const repMatchEnd = repIndex < prefixStartIndex ? dictEnd : iend;
                mLength = ZSTD_count_2segments(ip0 + 1 + 4, repMatch + 4, iend, repMatchEnd, prefixStart) + 4;
                ip0++;
                ZSTD_storeSeq(seqStore, (size_t) (ip0 - anchor), anchor, iend, REPCODE1_TO_OFFBASE, mLength);
                break;
            }

            if (dictTagsMatch) {

                const U32 dictMatchIndex = dictMatchIndexAndTag >> ZSTD_SHORT_CACHE_TAG_BITS;
                const BYTE* dictMatch = dictBase + dictMatchIndex;
                if (dictMatchIndex > dictStartIndex &&
                    MEM_read32(dictMatch) == MEM_read32(ip0)) {

                    if (matchIndex <= prefixStartIndex) {
                        U32 const offset = (U32) (curr - dictMatchIndex - dictIndexDelta);
                        mLength = ZSTD_count_2segments(ip0 + 4, dictMatch + 4, iend, dictEnd, prefixStart) + 4;
                        while (((ip0 > anchor) & (dictMatch > dictStart))
                            && (ip0[-1] == dictMatch[-1])) {
                            ip0--;
                            dictMatch--;
                            mLength++;
                        } /* catch up */
                        offset_2 = offset_1;
                        offset_1 = offset;
                        ZSTD_storeSeq(seqStore, (size_t) (ip0 - anchor), anchor, iend, OFFSET_TO_OFFBASE(offset), mLength);
                        break;
                    }
                }
            }

            if (ZSTD_match4Found_cmov(ip0, match, matchIndex, prefixStartIndex)) {

                U32 const offset = (U32) (ip0 - match);
                mLength = ZSTD_count(ip0 + 4, match + 4, iend) + 4;
                while (((ip0 > anchor) & (match > prefixStart))
                       && (ip0[-1] == match[-1])) {
                    ip0--;
                    match--;
                    mLength++;
                } /* catch up */
                offset_2 = offset_1;
                offset_1 = offset;
                ZSTD_storeSeq(seqStore, (size_t) (ip0 - anchor), anchor, iend, OFFSET_TO_OFFBASE(offset), mLength);
                break;
            }


            dictMatchIndexAndTag = dictHashTable[dictHashAndTag1 >> ZSTD_SHORT_CACHE_TAG_BITS];
            dictTagsMatch = ZSTD_comparePackedTags(dictMatchIndexAndTag, dictHashAndTag1);
            matchIndex = hashTable[hash1];

            if (ip1 >= nextStep) {
                step++;
                nextStep += kStepIncr;
            }
            ip0 = ip1;
            ip1 = ip1 + step;
            if (ip1 > ilimit) goto _cleanup;

            curr = (U32)(ip0 - base);
            hash0 = hash1;
        }   /* end inner search loop */


        assert(mLength);
        ip0 += mLength;
        anchor = ip0;

        if (ip0 <= ilimit) {

            assert(base+curr+2 > istart);  /* check base overflow */
            hashTable[ZSTD_hashPtr(base+curr+2, hlog, mls)] = curr+2;  /* here because curr+2 could be > iend-8 */
            hashTable[ZSTD_hashPtr(ip0-2, hlog, mls)] = (U32)(ip0-2-base);


            while (ip0 <= ilimit) {
                U32 const current2 = (U32)(ip0-base);
                U32 const repIndex2 = current2 - offset_2;
                const BYTE* repMatch2 = repIndex2 < prefixStartIndex ?
                        dictBase - dictIndexDelta + repIndex2 :
                        base + repIndex2;
                if ( (ZSTD_index_overlap_check(prefixStartIndex, repIndex2))
                   && (MEM_read32(repMatch2) == MEM_read32(ip0))) {
                    const BYTE* const repEnd2 = repIndex2 < prefixStartIndex ? dictEnd : iend;
                    size_t const repLength2 = ZSTD_count_2segments(ip0+4, repMatch2+4, iend, repEnd2, prefixStart) + 4;
                    U32 tmpOffset = offset_2; offset_2 = offset_1; offset_1 = tmpOffset;   /* swap offset_2 <=> offset_1 */
                    ZSTD_storeSeq(seqStore, 0, anchor, iend, REPCODE1_TO_OFFBASE, repLength2);
                    hashTable[ZSTD_hashPtr(ip0, hlog, mls)] = current2;
                    ip0 += repLength2;
                    anchor = ip0;
                    continue;
                }
                break;
            }
        }


        assert(ip0 == anchor);
        ip1 = ip0 + stepSize;
    }

_cleanup:

    rep[0] = offset_1;
    rep[1] = offset_2;


    return (size_t)(iend - anchor);
}


ZSTD_GEN_FAST_FN(dictMatchState, 4, 0)
ZSTD_GEN_FAST_FN(dictMatchState, 5, 0)
ZSTD_GEN_FAST_FN(dictMatchState, 6, 0)
ZSTD_GEN_FAST_FN(dictMatchState, 7, 0)

size_t ZSTD_compressBlock_fast_dictMatchState(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize)
{
    U32 const mls = ms->cParams.minMatch;
    assert(ms->dictMatchState != NULL);
    switch(mls)
    {
    default: /* includes case 3 */
    case 4 :
        return ZSTD_compressBlock_fast_dictMatchState_4_0(ms, seqStore, rep, src, srcSize);
    case 5 :
        return ZSTD_compressBlock_fast_dictMatchState_5_0(ms, seqStore, rep, src, srcSize);
    case 6 :
        return ZSTD_compressBlock_fast_dictMatchState_6_0(ms, seqStore, rep, src, srcSize);
    case 7 :
        return ZSTD_compressBlock_fast_dictMatchState_7_0(ms, seqStore, rep, src, srcSize);
    }
}


static
ZSTD_ALLOW_POINTER_OVERFLOW_ATTR
size_t ZSTD_compressBlock_fast_extDict_generic(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize, U32 const mls, U32 const hasStep)
{
    const ZSTD_compressionParameters* const cParams = &ms->cParams;
    U32* const hashTable = ms->hashTable;
    U32 const hlog = cParams->hashLog;

    size_t const stepSize = cParams->targetLength + !(cParams->targetLength) + 1;
    const BYTE* const base = ms->window.base;
    const BYTE* const dictBase = ms->window.dictBase;
    const BYTE* const istart = (const BYTE*)src;
    const BYTE* anchor = istart;
    const U32   endIndex = (U32)((size_t)(istart - base) + srcSize);
    const U32   lowLimit = ZSTD_getLowestMatchIndex(ms, endIndex, cParams->windowLog);
    const U32   dictStartIndex = lowLimit;
    const BYTE* const dictStart = dictBase + dictStartIndex;
    const U32   dictLimit = ms->window.dictLimit;
    const U32   prefixStartIndex = dictLimit < lowLimit ? lowLimit : dictLimit;
    const BYTE* const prefixStart = base + prefixStartIndex;
    const BYTE* const dictEnd = dictBase + prefixStartIndex;
    const BYTE* const iend = istart + srcSize;
    const BYTE* const ilimit = iend - 8;
    U32 offset_1=rep[0], offset_2=rep[1];
    U32 offsetSaved1 = 0, offsetSaved2 = 0;

    const BYTE* ip0 = istart;
    const BYTE* ip1;
    const BYTE* ip2;
    const BYTE* ip3;
    U32 current0;


    size_t hash0; /* hash for ip0 */
    size_t hash1; /* hash for ip1 */
    U32 idx; /* match idx for ip0 */
    const BYTE* idxBase; /* base pointer for idx */

    U32 offcode;
    const BYTE* match0;
    size_t mLength;
    const BYTE* matchEnd = 0; /* initialize to avoid warning, assert != 0 later */

    size_t step;
    const BYTE* nextStep;
    const size_t kStepIncr = (1 << (kSearchStrength - 1));

    (void)hasStep; /* not currently specialized on whether it's accelerated */

    DEBUGLOG(5, "ZSTD_compressBlock_fast_extDict_generic (offset_1=%u)", offset_1);


    if (prefixStartIndex == dictStartIndex)
        return ZSTD_compressBlock_fast(ms, seqStore, rep, src, srcSize);

    {   U32 const curr = (U32)(ip0 - base);
        U32 const maxRep = curr - dictStartIndex;
        if (offset_2 >= maxRep) offsetSaved2 = offset_2, offset_2 = 0;
        if (offset_1 >= maxRep) offsetSaved1 = offset_1, offset_1 = 0;
    }


_start: /* Requires: ip0 */

    step = stepSize;
    nextStep = ip0 + kStepIncr;


    ip1 = ip0 + 1;
    ip2 = ip0 + step;
    ip3 = ip2 + 1;

    if (ip3 >= ilimit) {
        goto _cleanup;
    }

    hash0 = ZSTD_hashPtr(ip0, hlog, mls);
    hash1 = ZSTD_hashPtr(ip1, hlog, mls);

    idx = hashTable[hash0];
    idxBase = idx < prefixStartIndex ? dictBase : base;

    do {
        {   /* load repcode match for ip[2] */
            U32 const current2 = (U32)(ip2 - base);
            U32 const repIndex = current2 - offset_1;
            const BYTE* const repBase = repIndex < prefixStartIndex ? dictBase : base;
            U32 rval;
            if ( ((U32)(prefixStartIndex - repIndex) >= 4) /* intentional underflow */
                 & (offset_1 > 0) ) {
                rval = MEM_read32(repBase + repIndex);
            } else {
                rval = MEM_read32(ip2) ^ 1; /* guaranteed to not match. */
            }


            current0 = (U32)(ip0 - base);
            hashTable[hash0] = current0;


            if (MEM_read32(ip2) == rval) {
                ip0 = ip2;
                match0 = repBase + repIndex;
                matchEnd = repIndex < prefixStartIndex ? dictEnd : iend;
                assert((match0 != prefixStart) & (match0 != dictStart));
                mLength = ip0[-1] == match0[-1];
                ip0 -= mLength;
                match0 -= mLength;
                offcode = REPCODE1_TO_OFFBASE;
                mLength += 4;
                goto _match;
        }   }

        {   /* load match for ip[0] */
            U32 const mval = idx >= dictStartIndex ?
                    MEM_read32(idxBase + idx) :
                    MEM_read32(ip0) ^ 1; /* guaranteed not to match */


            if (MEM_read32(ip0) == mval) {

                goto _offset;
        }   }


        idx = hashTable[hash1];
        idxBase = idx < prefixStartIndex ? dictBase : base;


        hash0 = hash1;
        hash1 = ZSTD_hashPtr(ip2, hlog, mls);


        ip0 = ip1;
        ip1 = ip2;
        ip2 = ip3;


        current0 = (U32)(ip0 - base);
        hashTable[hash0] = current0;

        {   /* load match for ip[0] */
            U32 const mval = idx >= dictStartIndex ?
                    MEM_read32(idxBase + idx) :
                    MEM_read32(ip0) ^ 1; /* guaranteed not to match */


            if (MEM_read32(ip0) == mval) {

                goto _offset;
        }   }


        idx = hashTable[hash1];
        idxBase = idx < prefixStartIndex ? dictBase : base;


        hash0 = hash1;
        hash1 = ZSTD_hashPtr(ip2, hlog, mls);


        ip0 = ip1;
        ip1 = ip2;
        ip2 = ip0 + step;
        ip3 = ip1 + step;


        if (ip2 >= nextStep) {
            step++;
            PREFETCH_L1(ip1 + 64);
            PREFETCH_L1(ip1 + 128);
            nextStep += kStepIncr;
        }
    } while (ip3 < ilimit);

_cleanup:



    offsetSaved2 = ((offsetSaved1 != 0) && (offset_1 != 0)) ? offsetSaved1 : offsetSaved2;


    rep[0] = offset_1 ? offset_1 : offsetSaved1;
    rep[1] = offset_2 ? offset_2 : offsetSaved2;


    return (size_t)(iend - anchor);

_offset: /* Requires: ip0, idx, idxBase */


    {   U32 const offset = current0 - idx;
        const BYTE* const lowMatchPtr = idx < prefixStartIndex ? dictStart : prefixStart;
        matchEnd = idx < prefixStartIndex ? dictEnd : iend;
        match0 = idxBase + idx;
        offset_2 = offset_1;
        offset_1 = offset;
        offcode = OFFSET_TO_OFFBASE(offset);
        mLength = 4;


        while (((ip0>anchor) & (match0>lowMatchPtr)) && (ip0[-1] == match0[-1])) {
            ip0--;
            match0--;
            mLength++;
    }   }

_match: /* Requires: ip0, match0, offcode, matchEnd */


    assert(matchEnd != 0);
    mLength += ZSTD_count_2segments(ip0 + mLength, match0 + mLength, iend, matchEnd, prefixStart);

    ZSTD_storeSeq(seqStore, (size_t)(ip0 - anchor), anchor, iend, offcode, mLength);

    ip0 += mLength;
    anchor = ip0;


    if (ip1 < ip0) {
        hashTable[hash1] = (U32)(ip1 - base);
    }


    if (ip0 <= ilimit) {

        assert(base+current0+2 > istart);  /* check base overflow */
        hashTable[ZSTD_hashPtr(base+current0+2, hlog, mls)] = current0+2;  /* here because current+2 could be > iend-8 */
        hashTable[ZSTD_hashPtr(ip0-2, hlog, mls)] = (U32)(ip0-2-base);

        while (ip0 <= ilimit) {
            U32 const repIndex2 = (U32)(ip0-base) - offset_2;
            const BYTE* const repMatch2 = repIndex2 < prefixStartIndex ? dictBase + repIndex2 : base + repIndex2;
            if ( ((ZSTD_index_overlap_check(prefixStartIndex, repIndex2)) & (offset_2 > 0))
                 && (MEM_read32(repMatch2) == MEM_read32(ip0)) ) {
                const BYTE* const repEnd2 = repIndex2 < prefixStartIndex ? dictEnd : iend;
                size_t const repLength2 = ZSTD_count_2segments(ip0+4, repMatch2+4, iend, repEnd2, prefixStart) + 4;
                { U32 const tmpOffset = offset_2; offset_2 = offset_1; offset_1 = tmpOffset; }  /* swap offset_2 <=> offset_1 */
                ZSTD_storeSeq(seqStore, 0 /*litlen*/, anchor, iend, REPCODE1_TO_OFFBASE, repLength2);
                hashTable[ZSTD_hashPtr(ip0, hlog, mls)] = (U32)(ip0-base);
                ip0 += repLength2;
                anchor = ip0;
                continue;
            }
            break;
    }   }

    goto _start;
}

ZSTD_GEN_FAST_FN(extDict, 4, 0)
ZSTD_GEN_FAST_FN(extDict, 5, 0)
ZSTD_GEN_FAST_FN(extDict, 6, 0)
ZSTD_GEN_FAST_FN(extDict, 7, 0)

size_t ZSTD_compressBlock_fast_extDict(
        ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
        void const* src, size_t srcSize)
{
    U32 const mls = ms->cParams.minMatch;
    assert(ms->dictMatchState == NULL);
    switch(mls)
    {
    default: /* includes case 3 */
    case 4 :
        return ZSTD_compressBlock_fast_extDict_4_0(ms, seqStore, rep, src, srcSize);
    case 5 :
        return ZSTD_compressBlock_fast_extDict_5_0(ms, seqStore, rep, src, srcSize);
    case 6 :
        return ZSTD_compressBlock_fast_extDict_6_0(ms, seqStore, rep, src, srcSize);
    case 7 :
        return ZSTD_compressBlock_fast_extDict_7_0(ms, seqStore, rep, src, srcSize);
    }
}
/**** ended inlining compress/zstd_fast.c ****/
// @ivoanjo: Level 1 doesn't use these compressors, so omit them to reduce zstd.c size.
// #include "compress/zstd_lazy.c"
/**** start inlining compress/zstd_ldm.c ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

/**** skipping file: zstd_ldm.h ****/

/**** skipping file: ../common/debug.h ****/
/**** skipping file: ../common/xxhash.h ****/
/**** skipping file: zstd_fast.h ****/
/**** skipping file: zstd_double_fast.h ****/
/**** start inlining zstd_ldm_geartab.h ****/
/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under both the BSD-style license (found in the
 * LICENSE file in the root directory of this source tree) and the GPLv2 (found
 * in the COPYING file in the root directory of this source tree).
 * You may select, at your option, one of the above-listed licenses.
 */

#ifndef ZSTD_LDM_GEARTAB_H
#define ZSTD_LDM_GEARTAB_H

/**** skipping file: ../common/compiler.h ****/
/**** skipping file: ../common/mem.h ****/

static UNUSED_ATTR const U64 ZSTD_ldm_gearTab[256] = {
    0xf5b8f72c5f77775c, 0x84935f266b7ac412, 0xb647ada9ca730ccc,
    0xb065bb4b114fb1de, 0x34584e7e8c3a9fd0, 0x4e97e17c6ae26b05,
    0x3a03d743bc99a604, 0xcecd042422c4044f, 0x76de76c58524259e,
    0x9c8528f65badeaca, 0x86563706e2097529, 0x2902475fa375d889,
    0xafb32a9739a5ebe6, 0xce2714da3883e639, 0x21eaf821722e69e,
    0x37b628620b628,    0x49a8d455d88caf5,  0x8556d711e6958140,
    0x4f7ae74fc605c1f,  0x829f0c3468bd3a20, 0x4ffdc885c625179e,
    0x8473de048a3daf1b, 0x51008822b05646b2, 0x69d75d12b2d1cc5f,
    0x8c9d4a19159154bc, 0xc3cc10f4abbd4003, 0xd06ddc1cecb97391,
    0xbe48e6e7ed80302e, 0x3481db31cee03547, 0xacc3f67cdaa1d210,
    0x65cb771d8c7f96cc, 0x8eb27177055723dd, 0xc789950d44cd94be,
    0x934feadc3700b12b, 0x5e485f11edbdf182, 0x1e2e2a46fd64767a,
    0x2969ca71d82efa7c, 0x9d46e9935ebbba2e, 0xe056b67e05e6822b,
    0x94d73f55739d03a0, 0xcd7010bdb69b5a03, 0x455ef9fcd79b82f4,
    0x869cb54a8749c161, 0x38d1a4fa6185d225, 0xb475166f94bbe9bb,
    0xa4143548720959f1, 0x7aed4780ba6b26ba, 0xd0ce264439e02312,
    0x84366d746078d508, 0xa8ce973c72ed17be, 0x21c323a29a430b01,
    0x9962d617e3af80ee, 0xab0ce91d9c8cf75b, 0x530e8ee6d19a4dbc,
    0x2ef68c0cf53f5d72, 0xc03a681640a85506, 0x496e4e9f9c310967,
    0x78580472b59b14a0, 0x273824c23b388577, 0x66bf923ad45cb553,
    0x47ae1a5a2492ba86, 0x35e304569e229659, 0x4765182a46870b6f,
    0x6cbab625e9099412, 0xddac9a2e598522c1, 0x7172086e666624f2,
    0xdf5003ca503b7837, 0x88c0c1db78563d09, 0x58d51865acfc289d,
    0x177671aec65224f1, 0xfb79d8a241e967d7, 0x2be1e101cad9a49a,
    0x6625682f6e29186b, 0x399553457ac06e50, 0x35dffb4c23abb74,
    0x429db2591f54aade, 0xc52802a8037d1009, 0x6acb27381f0b25f3,
    0xf45e2551ee4f823b, 0x8b0ea2d99580c2f7, 0x3bed519cbcb4e1e1,
    0xff452823dbb010a,  0x9d42ed614f3dd267, 0x5b9313c06257c57b,
    0xa114b8008b5e1442, 0xc1fe311c11c13d4b, 0x66e8763ea34c5568,
    0x8b982af1c262f05d, 0xee8876faaa75fbb7, 0x8a62a4d0d172bb2a,
    0xc13d94a3b7449a97, 0x6dbbba9dc15d037c, 0xc786101f1d92e0f1,
    0xd78681a907a0b79b, 0xf61aaf2962c9abb9, 0x2cfd16fcd3cb7ad9,
    0x868c5b6744624d21, 0x25e650899c74ddd7, 0xba042af4a7c37463,
    0x4eb1a539465a3eca, 0xbe09dbf03b05d5ca, 0x774e5a362b5472ba,
    0x47a1221229d183cd, 0x504b0ca18ef5a2df, 0xdffbdfbde2456eb9,
    0x46cd2b2fbee34634, 0xf2aef8fe819d98c3, 0x357f5276d4599d61,
    0x24a5483879c453e3, 0x88026889192b4b9,  0x28da96671782dbec,
    0x4ef37c40588e9aaa, 0x8837b90651bc9fb3, 0xc164f741d3f0e5d6,
    0xbc135a0a704b70ba, 0x69cd868f7622ada,  0xbc37ba89e0b9c0ab,
    0x47c14a01323552f6, 0x4f00794bacee98bb, 0x7107de7d637a69d5,
    0x88af793bb6f2255e, 0xf3c6466b8799b598, 0xc288c616aa7f3b59,
    0x81ca63cf42fca3fd, 0x88d85ace36a2674b, 0xd056bd3792389e7,
    0xe55c396c4e9dd32d, 0xbefb504571e6c0a6, 0x96ab32115e91e8cc,
    0xbf8acb18de8f38d1, 0x66dae58801672606, 0x833b6017872317fb,
    0xb87c16f2d1c92864, 0xdb766a74e58b669c, 0x89659f85c61417be,
    0xc8daad856011ea0c, 0x76a4b565b6fe7eae, 0xa469d085f6237312,
    0xaaf0365683a3e96c, 0x4dbb746f8424f7b8, 0x638755af4e4acc1,
    0x3d7807f5bde64486, 0x17be6d8f5bbb7639, 0x903f0cd44dc35dc,
    0x67b672eafdf1196c, 0xa676ff93ed4c82f1, 0x521d1004c5053d9d,
    0x37ba9ad09ccc9202, 0x84e54d297aacfb51, 0xa0b4b776a143445,
    0x820d471e20b348e,  0x1874383cb83d46dc, 0x97edeec7a1efe11c,
    0xb330e50b1bdc42aa, 0x1dd91955ce70e032, 0xa514cdb88f2939d5,
    0x2791233fd90db9d3, 0x7b670a4cc50f7a9b, 0x77c07d2a05c6dfa5,
    0xe3778b6646d0a6fa, 0xb39c8eda47b56749, 0x933ed448addbef28,
    0xaf846af6ab7d0bf4, 0xe5af208eb666e49,  0x5e6622f73534cd6a,
    0x297daeca42ef5b6e, 0x862daef3d35539a6, 0xe68722498f8e1ea9,
    0x981c53093dc0d572, 0xfa09b0bfbf86fbf5, 0x30b1e96166219f15,
    0x70e7d466bdc4fb83, 0x5a66736e35f2a8e9, 0xcddb59d2b7c1baef,
    0xd6c7d247d26d8996, 0xea4e39eac8de1ba3, 0x539c8bb19fa3aff2,
    0x9f90e4c5fd508d8,  0xa34e5956fbaf3385, 0x2e2f8e151d3ef375,
    0x173691e9b83faec1, 0xb85a8d56bf016379, 0x8382381267408ae3,
    0xb90f901bbdc0096d, 0x7c6ad32933bcec65, 0x76bb5e2f2c8ad595,
    0x390f851a6cf46d28, 0xc3e6064da1c2da72, 0xc52a0c101cfa5389,
    0xd78eaf84a3fbc530, 0x3781b9e2288b997e, 0x73c2f6dea83d05c4,
    0x4228e364c5b5ed7,  0x9d7a3edf0da43911, 0x8edcfeda24686756,
    0x5e7667a7b7a9b3a1, 0x4c4f389fa143791d, 0xb08bc1023da7cddc,
    0x7ab4be3ae529b1cc, 0x754e6132dbe74ff9, 0x71635442a839df45,
    0x2f6fb1643fbe52de, 0x961e0a42cf7a8177, 0xf3b45d83d89ef2ea,
    0xee3de4cf4a6e3e9b, 0xcd6848542c3295e7, 0xe4cee1664c78662f,
    0x9947548b474c68c4, 0x25d73777a5ed8b0b, 0xc915b1d636b7fc,
    0x21c2ba75d9b0d2da, 0x5f6b5dcf608a64a1, 0xdcf333255ff9570c,
    0x633b922418ced4ee, 0xc136dde0b004b34a, 0x58cc83b05d4b2f5a,
    0x5eb424dda28e42d2, 0x62df47369739cd98, 0xb4e0b42485e4ce17,
    0x16e1f0c1f9a8d1e7, 0x8ec3916707560ebf, 0x62ba6e2df2cc9db3,
    0xcbf9f4ff77d83a16, 0x78d9d7d07d2bbcc4, 0xef554ce1e02c41f4,
    0x8d7581127eccf94d, 0xa9b53336cb3c8a05, 0x38c42c0bf45c4f91,
    0x640893cdf4488863, 0x80ec34bc575ea568, 0x39f324f5b48eaa40,
    0xe9d9ed1f8eff527f, 0x9224fc058cc5a214, 0xbaba00b04cfe7741,
    0x309a9f120fcf52af, 0xa558f3ec65626212, 0x424bec8b7adabe2f,
    0x41622513a6aea433, 0xb88da2d5324ca798, 0xd287733b245528a4,
    0x9a44697e6d68aec3, 0x7b1093be2f49bb28, 0x50bbec632e3d8aad,
    0x6cd90723e1ea8283, 0x897b9e7431b02bf3, 0x219efdcb338a7047,
    0x3b0311f0a27c0656, 0xdb17bf91c0db96e7, 0x8cd4fd6b4e85a5b2,
    0xfab071054ba6409d, 0x40d6fe831fa9dfd9, 0xaf358debad7d791e,
    0xeb8d0e25a65e3e58, 0xbbcbd3df14e08580, 0xcf751f27ecdab2b,
    0x2b4da14f2613d8f4
};

#endif /* ZSTD_LDM_GEARTAB_H */
/**** ended inlining zstd_ldm_geartab.h ****/

#define LDM_BUCKET_SIZE_LOG 4
#define LDM_MIN_MATCH_LENGTH 64
#define LDM_HASH_RLOG 7


static void ZSTD_ldm_gear_init(ldmRollingHashState_t* state, ldmParams_t const* params)
{
    unsigned maxBitsInMask = MIN(params->minMatchLength, 64);
    unsigned hashRateLog = params->hashRateLog;

    state->rolling = ~(U32)0;


    if (hashRateLog > 0 && hashRateLog <= maxBitsInMask) {
        state->stopMask = (((U64)1 << hashRateLog) - 1) << (maxBitsInMask - hashRateLog);
    } else {

        state->stopMask = ((U64)1 << hashRateLog) - 1;
    }
}


void ZSTD_ldm_gear_reset(ldmRollingHashState_t* state,
                        BYTE const* data, size_t minMatchLength)
{
    U64 hash = state->rolling;
    size_t n = 0;

#define GEAR_ITER_ONCE() do {                                  \
        hash = (hash << 1) + ZSTD_ldm_gearTab[data[n] & 0xff]; \
        n += 1;                                                \
    } while (0)
    while (n + 3 < minMatchLength) {
        GEAR_ITER_ONCE();
        GEAR_ITER_ONCE();
        GEAR_ITER_ONCE();
        GEAR_ITER_ONCE();
    }
    while (n < minMatchLength) {
        GEAR_ITER_ONCE();
    }
#undef GEAR_ITER_ONCE
    state->rolling = hash;
}


size_t ZSTD_ldm_gear_feed(ldmRollingHashState_t* state,
                         BYTE const* data, size_t size,
                         size_t* splits, unsigned* numSplits)
{
    size_t n;
    U64 hash, mask;

    hash = state->rolling;
    mask = state->stopMask;
    n = 0;

#define GEAR_ITER_ONCE() do { \
        hash = (hash << 1) + ZSTD_ldm_gearTab[data[n] & 0xff]; \
        n += 1; \
        if (UNLIKELY((hash & mask) == 0)) { \
            splits[*numSplits] = n; \
            *numSplits += 1; \
            if (*numSplits == LDM_BATCH_SIZE) \
                goto done; \
        } \
    } while (0)

    while (n + 3 < size) {
        GEAR_ITER_ONCE();
        GEAR_ITER_ONCE();
        GEAR_ITER_ONCE();
        GEAR_ITER_ONCE();
    }
    while (n < size) {
        GEAR_ITER_ONCE();
    }

#undef GEAR_ITER_ONCE

done:
    state->rolling = hash;
    return n;
}

void ZSTD_ldm_adjustParameters(ldmParams_t* params,
                        const ZSTD_compressionParameters* cParams)
{
    params->windowLog = cParams->windowLog;
    ZSTD_STATIC_ASSERT(LDM_BUCKET_SIZE_LOG <= ZSTD_LDM_BUCKETSIZELOG_MAX);
    DEBUGLOG(4, "ZSTD_ldm_adjustParameters");
    if (params->hashRateLog == 0) {
        if (params->hashLog > 0) {

            assert(params->hashLog <= ZSTD_HASHLOG_MAX);
            if (params->windowLog > params->hashLog) {
                params->hashRateLog = params->windowLog - params->hashLog;
            }
        } else {
            assert(1 <= (int)cParams->strategy && (int)cParams->strategy <= 9);

            params->hashRateLog = 7 - (cParams->strategy/3);
        }
    }
    if (params->hashLog == 0) {
        if (params->windowLog <= params->hashRateLog) {
            params->hashLog = ZSTD_HASHLOG_MIN;
        } else {
            params->hashLog = BOUNDED(ZSTD_HASHLOG_MIN, params->windowLog - params->hashRateLog, ZSTD_HASHLOG_MAX);
        }
    }
    if (params->minMatchLength == 0) {
        params->minMatchLength = LDM_MIN_MATCH_LENGTH;
        if (cParams->strategy >= ZSTD_btultra)
            params->minMatchLength /= 2;
    }
    if (params->bucketSizeLog==0) {
        assert(1 <= (int)cParams->strategy && (int)cParams->strategy <= 9);
        params->bucketSizeLog = BOUNDED(LDM_BUCKET_SIZE_LOG, (U32)cParams->strategy, ZSTD_LDM_BUCKETSIZELOG_MAX);
    }
    params->bucketSizeLog = MIN(params->bucketSizeLog, params->hashLog);
}

size_t ZSTD_ldm_getTableSize(ldmParams_t params)
{
    size_t const ldmHSize = ((size_t)1) << params.hashLog;
    size_t const ldmBucketSizeLog = MIN(params.bucketSizeLog, params.hashLog);
    size_t const ldmBucketSize = ((size_t)1) << (params.hashLog - ldmBucketSizeLog);
    size_t const totalSize = ZSTD_cwksp_alloc_size(ldmBucketSize)
                           + ZSTD_cwksp_alloc_size(ldmHSize * sizeof(ldmEntry_t));
    return params.enableLdm == ZSTD_ps_enable ? totalSize : 0;
}

size_t ZSTD_ldm_getMaxNbSeq(ldmParams_t params, size_t maxChunkSize)
{
    return params.enableLdm == ZSTD_ps_enable ? (maxChunkSize / params.minMatchLength) : 0;
}


static ldmEntry_t* ZSTD_ldm_getBucket(
        const ldmState_t* ldmState, size_t hash, U32 const bucketSizeLog)
{
    return ldmState->hashTable + (hash << bucketSizeLog);
}


static void ZSTD_ldm_insertEntry(ldmState_t* ldmState,
                                 size_t const hash, const ldmEntry_t entry,
                                 U32 const bucketSizeLog)
{
    BYTE* const pOffset = ldmState->bucketOffsets + hash;
    unsigned const offset = *pOffset;

    *(ZSTD_ldm_getBucket(ldmState, hash, bucketSizeLog) + offset) = entry;
    *pOffset = (BYTE)((offset + 1) & ((1u << bucketSizeLog) - 1));

}


static size_t ZSTD_ldm_countBackwardsMatch(
            const BYTE* pIn, const BYTE* pAnchor,
            const BYTE* pMatch, const BYTE* pMatchBase)
{
    size_t matchLength = 0;
    while (pIn > pAnchor && pMatch > pMatchBase && pIn[-1] == pMatch[-1]) {
        pIn--;
        pMatch--;
        matchLength++;
    }
    return matchLength;
}


static size_t ZSTD_ldm_countBackwardsMatch_2segments(
                    const BYTE* pIn, const BYTE* pAnchor,
                    const BYTE* pMatch, const BYTE* pMatchBase,
                    const BYTE* pExtDictStart, const BYTE* pExtDictEnd)
{
    size_t matchLength = ZSTD_ldm_countBackwardsMatch(pIn, pAnchor, pMatch, pMatchBase);
    if (pMatch - matchLength != pMatchBase || pMatchBase == pExtDictStart) {

        return matchLength;
    }
    DEBUGLOG(7, "ZSTD_ldm_countBackwardsMatch_2segments: found 2-parts backwards match (length in prefix==%zu)", matchLength);
    matchLength += ZSTD_ldm_countBackwardsMatch(pIn - matchLength, pAnchor, pExtDictEnd, pExtDictStart);
    DEBUGLOG(7, "final backwards match length = %zu", matchLength);
    return matchLength;
}


static size_t ZSTD_ldm_fillFastTables(ZSTD_MatchState_t* ms,
                                      void const* end)
{
    const BYTE* const iend = (const BYTE*)end;

    switch(ms->cParams.strategy)
    {
    case ZSTD_fast:
        ZSTD_fillHashTable(ms, iend, ZSTD_dtlm_fast, ZSTD_tfp_forCCtx);
        break;

    case ZSTD_dfast:
#ifndef ZSTD_EXCLUDE_DFAST_BLOCK_COMPRESSOR
        ZSTD_fillDoubleHashTable(ms, iend, ZSTD_dtlm_fast, ZSTD_tfp_forCCtx);
#else
        assert(0); /* shouldn't be called: cparams should've been adjusted. */
#endif
        break;

    case ZSTD_greedy:
    case ZSTD_lazy:
    case ZSTD_lazy2:
    case ZSTD_btlazy2:
    case ZSTD_btopt:
    case ZSTD_btultra:
    case ZSTD_btultra2:
        break;
    default:
        assert(0);  /* not possible : not a valid strategy id */
    }

    return 0;
}

void ZSTD_ldm_fillHashTable(
            ldmState_t* ldmState, const BYTE* ip,
            const BYTE* iend, ldmParams_t const* params)
{
    U32 const minMatchLength = params->minMatchLength;
    U32 const bucketSizeLog = params->bucketSizeLog;
    U32 const hBits = params->hashLog - bucketSizeLog;
    BYTE const* const base = ldmState->window.base;
    BYTE const* const istart = ip;
    ldmRollingHashState_t hashState;
    size_t* const splits = ldmState->splitIndices;
    unsigned numSplits;

    DEBUGLOG(5, "ZSTD_ldm_fillHashTable");

    ZSTD_ldm_gear_init(&hashState, params);
    while (ip < iend) {
        size_t hashed;
        unsigned n;

        numSplits = 0;
        hashed = ZSTD_ldm_gear_feed(&hashState, ip, (size_t)(iend - ip), splits, &numSplits);

        for (n = 0; n < numSplits; n++) {
            if (ip + splits[n] >= istart + minMatchLength) {
                BYTE const* const split = ip + splits[n] - minMatchLength;
                U64 const xxhash = XXH64(split, minMatchLength, 0);
                U32 const hash = (U32)(xxhash & (((U32)1 << hBits) - 1));
                ldmEntry_t entry;

                entry.offset = (U32)(split - base);
                entry.checksum = (U32)(xxhash >> 32);
                ZSTD_ldm_insertEntry(ldmState, hash, entry, params->bucketSizeLog);
            }
        }

        ip += hashed;
    }
}



static void ZSTD_ldm_limitTableUpdate(ZSTD_MatchState_t* ms, const BYTE* anchor)
{
    U32 const curr = (U32)(anchor - ms->window.base);
    if (curr > ms->nextToUpdate + 1024) {
        ms->nextToUpdate =
            curr - MIN(512, curr - ms->nextToUpdate - 1024);
    }
}

static
ZSTD_ALLOW_POINTER_OVERFLOW_ATTR
size_t ZSTD_ldm_generateSequences_internal(
        ldmState_t* ldmState, RawSeqStore_t* rawSeqStore,
        ldmParams_t const* params, void const* src, size_t srcSize)
{

    int const extDict = ZSTD_window_hasExtDict(ldmState->window);
    U32 const minMatchLength = params->minMatchLength;
    U32 const entsPerBucket = 1U << params->bucketSizeLog;
    U32 const hBits = params->hashLog - params->bucketSizeLog;

    U32 const dictLimit = ldmState->window.dictLimit;
    U32 const lowestIndex = extDict ? ldmState->window.lowLimit : dictLimit;
    BYTE const* const base = ldmState->window.base;
    BYTE const* const dictBase = extDict ? ldmState->window.dictBase : NULL;
    BYTE const* const dictStart = extDict ? dictBase + lowestIndex : NULL;
    BYTE const* const dictEnd = extDict ? dictBase + dictLimit : NULL;
    BYTE const* const lowPrefixPtr = base + dictLimit;

    BYTE const* const istart = (BYTE const*)src;
    BYTE const* const iend = istart + srcSize;
    BYTE const* const ilimit = iend - HASH_READ_SIZE;

    BYTE const* anchor = istart;
    BYTE const* ip = istart;

    ldmRollingHashState_t hashState;

    size_t* const splits = ldmState->splitIndices;
    ldmMatchCandidate_t* const candidates = ldmState->matchCandidates;
    unsigned numSplits;

    if (srcSize < minMatchLength)
        return iend - anchor;


    ZSTD_ldm_gear_init(&hashState, params);
    ZSTD_ldm_gear_reset(&hashState, ip, minMatchLength);
    ip += minMatchLength;

    while (ip < ilimit) {
        size_t hashed;
        unsigned n;

        numSplits = 0;
        hashed = ZSTD_ldm_gear_feed(&hashState, ip, ilimit - ip,
                                    splits, &numSplits);

        for (n = 0; n < numSplits; n++) {
            BYTE const* const split = ip + splits[n] - minMatchLength;
            U64 const xxhash = XXH64(split, minMatchLength, 0);
            U32 const hash = (U32)(xxhash & (((U32)1 << hBits) - 1));

            candidates[n].split = split;
            candidates[n].hash = hash;
            candidates[n].checksum = (U32)(xxhash >> 32);
            candidates[n].bucket = ZSTD_ldm_getBucket(ldmState, hash, params->bucketSizeLog);
            PREFETCH_L1(candidates[n].bucket);
        }

        for (n = 0; n < numSplits; n++) {
            size_t forwardMatchLength = 0, backwardMatchLength = 0,
                   bestMatchLength = 0, mLength;
            U32 offset;
            BYTE const* const split = candidates[n].split;
            U32 const checksum = candidates[n].checksum;
            U32 const hash = candidates[n].hash;
            ldmEntry_t* const bucket = candidates[n].bucket;
            ldmEntry_t const* cur;
            ldmEntry_t const* bestEntry = NULL;
            ldmEntry_t newEntry;

            newEntry.offset = (U32)(split - base);
            newEntry.checksum = checksum;


            if (split < anchor) {
                ZSTD_ldm_insertEntry(ldmState, hash, newEntry, params->bucketSizeLog);
                continue;
            }

            for (cur = bucket; cur < bucket + entsPerBucket; cur++) {
                size_t curForwardMatchLength, curBackwardMatchLength,
                       curTotalMatchLength;
                if (cur->checksum != checksum || cur->offset <= lowestIndex) {
                    continue;
                }
                if (extDict) {
                    BYTE const* const curMatchBase =
                        cur->offset < dictLimit ? dictBase : base;
                    BYTE const* const pMatch = curMatchBase + cur->offset;
                    BYTE const* const matchEnd =
                        cur->offset < dictLimit ? dictEnd : iend;
                    BYTE const* const lowMatchPtr =
                        cur->offset < dictLimit ? dictStart : lowPrefixPtr;
                    curForwardMatchLength =
                        ZSTD_count_2segments(split, pMatch, iend, matchEnd, lowPrefixPtr);
                    if (curForwardMatchLength < minMatchLength) {
                        continue;
                    }
                    curBackwardMatchLength = ZSTD_ldm_countBackwardsMatch_2segments(
                            split, anchor, pMatch, lowMatchPtr, dictStart, dictEnd);
                } else { /* !extDict */
                    BYTE const* const pMatch = base + cur->offset;
                    curForwardMatchLength = ZSTD_count(split, pMatch, iend);
                    if (curForwardMatchLength < minMatchLength) {
                        continue;
                    }
                    curBackwardMatchLength =
                        ZSTD_ldm_countBackwardsMatch(split, anchor, pMatch, lowPrefixPtr);
                }
                curTotalMatchLength = curForwardMatchLength + curBackwardMatchLength;

                if (curTotalMatchLength > bestMatchLength) {
                    bestMatchLength = curTotalMatchLength;
                    forwardMatchLength = curForwardMatchLength;
                    backwardMatchLength = curBackwardMatchLength;
                    bestEntry = cur;
                }
            }


            if (bestEntry == NULL) {
                ZSTD_ldm_insertEntry(ldmState, hash, newEntry, params->bucketSizeLog);
                continue;
            }


            offset = (U32)(split - base) - bestEntry->offset;
            mLength = forwardMatchLength + backwardMatchLength;
            {
                rawSeq* const seq = rawSeqStore->seq + rawSeqStore->size;


                if (rawSeqStore->size == rawSeqStore->capacity)
                    return ERROR(dstSize_tooSmall);
                seq->litLength = (U32)(split - backwardMatchLength - anchor);
                seq->matchLength = (U32)mLength;
                seq->offset = offset;
                rawSeqStore->size++;
            }


            ZSTD_ldm_insertEntry(ldmState, hash, newEntry, params->bucketSizeLog);

            anchor = split + forwardMatchLength;


            if (anchor > ip + hashed) {
                ZSTD_ldm_gear_reset(&hashState, anchor - minMatchLength, minMatchLength);

                ip = anchor - hashed;
                break;
            }
        }

        ip += hashed;
    }

    return iend - anchor;
}


static void ZSTD_ldm_reduceTable(ldmEntry_t* const table, U32 const size,
                                 U32 const reducerValue)
{
    U32 u;
    for (u = 0; u < size; u++) {
        if (table[u].offset < reducerValue) table[u].offset = 0;
        else table[u].offset -= reducerValue;
    }
}

size_t ZSTD_ldm_generateSequences(
        ldmState_t* ldmState, RawSeqStore_t* sequences,
        ldmParams_t const* params, void const* src, size_t srcSize)
{
    U32 const maxDist = 1U << params->windowLog;
    BYTE const* const istart = (BYTE const*)src;
    BYTE const* const iend = istart + srcSize;
    size_t const kMaxChunkSize = 1 << 20;
    size_t const nbChunks = (srcSize / kMaxChunkSize) + ((srcSize % kMaxChunkSize) != 0);
    size_t chunk;
    size_t leftoverSize = 0;

    assert(ZSTD_CHUNKSIZE_MAX >= kMaxChunkSize);

    assert(ldmState->window.nextSrc >= (BYTE const*)src + srcSize);

    assert(sequences->pos <= sequences->size);
    assert(sequences->size <= sequences->capacity);
    for (chunk = 0; chunk < nbChunks && sequences->size < sequences->capacity; ++chunk) {
        BYTE const* const chunkStart = istart + chunk * kMaxChunkSize;
        size_t const remaining = (size_t)(iend - chunkStart);
        BYTE const *const chunkEnd =
            (remaining < kMaxChunkSize) ? iend : chunkStart + kMaxChunkSize;
        size_t const chunkSize = chunkEnd - chunkStart;
        size_t newLeftoverSize;
        size_t const prevSize = sequences->size;

        assert(chunkStart < iend);

        if (ZSTD_window_needOverflowCorrection(ldmState->window, 0, maxDist, ldmState->loadedDictEnd, chunkStart, chunkEnd)) {
            U32 const ldmHSize = 1U << params->hashLog;
            U32 const correction = ZSTD_window_correctOverflow(
                &ldmState->window, /* cycleLog */ 0, maxDist, chunkStart);
            ZSTD_ldm_reduceTable(ldmState->hashTable, ldmHSize, correction);

            ldmState->loadedDictEnd = 0;
        }

        ZSTD_window_enforceMaxDist(&ldmState->window, chunkEnd, maxDist, &ldmState->loadedDictEnd, NULL);

        newLeftoverSize = ZSTD_ldm_generateSequences_internal(
            ldmState, sequences, params, chunkStart, chunkSize);
        if (ZSTD_isError(newLeftoverSize))
            return newLeftoverSize;


        if (prevSize < sequences->size) {
            sequences->seq[prevSize].litLength += (U32)leftoverSize;
            leftoverSize = newLeftoverSize;
        } else {
            assert(newLeftoverSize == chunkSize);
            leftoverSize += chunkSize;
        }
    }
    return 0;
}

void
ZSTD_ldm_skipSequences(RawSeqStore_t* rawSeqStore, size_t srcSize, U32 const minMatch)
{
    while (srcSize > 0 && rawSeqStore->pos < rawSeqStore->size) {
        rawSeq* seq = rawSeqStore->seq + rawSeqStore->pos;
        if (srcSize <= seq->litLength) {

            seq->litLength -= (U32)srcSize;
            return;
        }
        srcSize -= seq->litLength;
        seq->litLength = 0;
        if (srcSize < seq->matchLength) {

            seq->matchLength -= (U32)srcSize;
            if (seq->matchLength < minMatch) {

                if (rawSeqStore->pos + 1 < rawSeqStore->size) {
                    seq[1].litLength += seq[0].matchLength;
                }
                rawSeqStore->pos++;
            }
            return;
        }
        srcSize -= seq->matchLength;
        seq->matchLength = 0;
        rawSeqStore->pos++;
    }
}


static rawSeq maybeSplitSequence(RawSeqStore_t* rawSeqStore,
                                 U32 const remaining, U32 const minMatch)
{
    rawSeq sequence = rawSeqStore->seq[rawSeqStore->pos];
    assert(sequence.offset > 0);

    if (remaining >= sequence.litLength + sequence.matchLength) {
        rawSeqStore->pos++;
        return sequence;
    }

    if (remaining <= sequence.litLength) {
        sequence.offset = 0;
    } else if (remaining < sequence.litLength + sequence.matchLength) {
        sequence.matchLength = remaining - sequence.litLength;
        if (sequence.matchLength < minMatch) {
            sequence.offset = 0;
        }
    }

    ZSTD_ldm_skipSequences(rawSeqStore, remaining, minMatch);
    return sequence;
}

void ZSTD_ldm_skipRawSeqStoreBytes(RawSeqStore_t* rawSeqStore, size_t nbBytes) {
    U32 currPos = (U32)(rawSeqStore->posInSequence + nbBytes);
    while (currPos && rawSeqStore->pos < rawSeqStore->size) {
        rawSeq currSeq = rawSeqStore->seq[rawSeqStore->pos];
        if (currPos >= currSeq.litLength + currSeq.matchLength) {
            currPos -= currSeq.litLength + currSeq.matchLength;
            rawSeqStore->pos++;
        } else {
            rawSeqStore->posInSequence = currPos;
            break;
        }
    }
    if (currPos == 0 || rawSeqStore->pos == rawSeqStore->size) {
        rawSeqStore->posInSequence = 0;
    }
}

size_t ZSTD_ldm_blockCompress(RawSeqStore_t* rawSeqStore,
    ZSTD_MatchState_t* ms, SeqStore_t* seqStore, U32 rep[ZSTD_REP_NUM],
    ZSTD_ParamSwitch_e useRowMatchFinder,
    void const* src, size_t srcSize)
{
    const ZSTD_compressionParameters* const cParams = &ms->cParams;
    unsigned const minMatch = cParams->minMatch;
    ZSTD_BlockCompressor_f const blockCompressor =
        ZSTD_selectBlockCompressor(cParams->strategy, useRowMatchFinder, ZSTD_matchState_dictMode(ms));

    BYTE const* const istart = (BYTE const*)src;
    BYTE const* const iend = istart + srcSize;

    BYTE const* ip = istart;

    DEBUGLOG(5, "ZSTD_ldm_blockCompress: srcSize=%zu", srcSize);

    if (cParams->strategy >= ZSTD_btopt) {
        size_t lastLLSize;
        ms->ldmSeqStore = rawSeqStore;
        lastLLSize = blockCompressor(ms, seqStore, rep, src, srcSize);
        ZSTD_ldm_skipRawSeqStoreBytes(rawSeqStore, srcSize);
        return lastLLSize;
    }

    assert(rawSeqStore->pos <= rawSeqStore->size);
    assert(rawSeqStore->size <= rawSeqStore->capacity);

    while (rawSeqStore->pos < rawSeqStore->size && ip < iend) {

        rawSeq const sequence = maybeSplitSequence(rawSeqStore,
                                                   (U32)(iend - ip), minMatch);

        if (sequence.offset == 0)
            break;

        assert(ip + sequence.litLength + sequence.matchLength <= iend);


        ZSTD_ldm_limitTableUpdate(ms, ip);
        ZSTD_ldm_fillFastTables(ms, ip);

        DEBUGLOG(5, "pos %u : calling block compressor on segment of size %u", (unsigned)(ip-istart), sequence.litLength);
        {
            int i;
            size_t const newLitLength =
                blockCompressor(ms, seqStore, rep, ip, sequence.litLength);
            ip += sequence.litLength;

            for (i = ZSTD_REP_NUM - 1; i > 0; i--)
                rep[i] = rep[i-1];
            rep[0] = sequence.offset;

            ZSTD_storeSeq(seqStore, newLitLength, ip - newLitLength, iend,
                          OFFSET_TO_OFFBASE(sequence.offset),
                          sequence.matchLength);
            ip += sequence.matchLength;
        }
    }

    ZSTD_ldm_limitTableUpdate(ms, ip);
    ZSTD_ldm_fillFastTables(ms, ip);

    return blockCompressor(ms, seqStore, rep, ip, iend - ip);
}
/**** ended inlining compress/zstd_ldm.c ****/
// @ivoanjo: Level 1 doesn't use these compressors, so omit them to reduce zstd.c size.
// #include "compress/zstd_opt.c"
// #ifdef ZSTD_MULTITHREAD
// @ivoanjo: Multithreading is disabled, so omit this unused source to reduce zstd.c size.
// #include "compress/zstdmt_compress.c"
// #endif

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

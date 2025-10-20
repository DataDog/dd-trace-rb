// BSD-3-Clause License
// Synchronized from blazesym repository
// https://github.com/libbpf/blazesym/blob/capi-v0.1.1/capi/include/blazesym.h
/*
 * Please refer to the documentation hosted at
 *
 *   https://docs.rs/blazesym-c/0.1.1
 */


#ifndef __blazesym_h_
#define __blazesym_h_

#include <stdarg.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

/**
 * An enum providing a rough classification of errors.
 *
 * C ABI compatible version of [`blazesym::ErrorKind`].
 */
typedef int16_t blaze_err;
/**
 * The operation was successful.
 */
#define BLAZE_ERR_OK 0
/**
 * An entity was not found, often a file.
 */
#define BLAZE_ERR_NOT_FOUND -2
/**
 * The operation lacked the necessary privileges to complete.
 */
#define BLAZE_ERR_PERMISSION_DENIED -1
/**
 * An entity already exists, often a file.
 */
#define BLAZE_ERR_ALREADY_EXISTS -17
/**
 * The operation needs to block to complete, but the blocking
 * operation was requested to not occur.
 */
#define BLAZE_ERR_WOULD_BLOCK -11
/**
 * Data not valid for the operation were encountered.
 */
#define BLAZE_ERR_INVALID_DATA -22
/**
 * The I/O operation's timeout expired, causing it to be canceled.
 */
#define BLAZE_ERR_TIMED_OUT -110
/**
 * This operation is unsupported on this platform.
 */
#define BLAZE_ERR_UNSUPPORTED -95
/**
 * An operation could not be completed, because it failed
 * to allocate enough memory.
 */
#define BLAZE_ERR_OUT_OF_MEMORY -12
/**
 * A parameter was incorrect.
 */
#define BLAZE_ERR_INVALID_INPUT -256
/**
 * An error returned when an operation could not be completed
 * because a call to [`write`] returned [`Ok(0)`].
 */
#define BLAZE_ERR_WRITE_ZERO -257
/**
 * An error returned when an operation ould not be completed
 * because an "end of file" was reached prematurely.
 */
#define BLAZE_ERR_UNEXPECTED_EOF -258
/**
 * DWARF input data was invalid.
 */
#define BLAZE_ERR_INVALID_DWARF -259
/**
 * A custom error that does not fall under any other I/O error
 * kind.
 */
#define BLAZE_ERR_OTHER -260

/**
 * The type of a symbol.
 */
typedef uint8_t blaze_sym_type;
/**
 * The symbol type is unspecified or unknown.
 *
 * In input contexts this variant can be used to encompass all
 * other variants (functions and variables), whereas in output
 * contexts it means that the type is not known.
 */
#define BLAZE_SYM_TYPE_UNDEF 0
/**
 * The symbol is a function.
 */
#define BLAZE_SYM_TYPE_FUNC 1
/**
 * The symbol is a variable.
 */
#define BLAZE_SYM_TYPE_VAR 2

/**
 * Information about a looked up symbol.
 */
typedef struct blaze_sym_info {
  /**
   * See [`inspect::SymInfo::name`].
   */
  const char *name;
  /**
   * See [`inspect::SymInfo::addr`].
   */
  uint64_t addr;
  /**
   * See [`inspect::SymInfo::size`].
   *
   * If the symbol's size is not available, this member will be `-1`.
   * Note that some symbol sources may not distinguish between
   * "unknown" size and `0`. In that case the size will be reported
   * as `0` here as well.
   */
  ptrdiff_t size;
  /**
   * See [`inspect::SymInfo::file_offset`].
   */
  uint64_t file_offset;
  /**
   * See [`inspect::SymInfo::module`].
   */
  const char *module;
  /**
   * See [`inspect::SymInfo::sym_type`].
   */
  blaze_sym_type sym_type;
  /**
   * Unused member available for future expansion.
   */
  uint8_t reserved[23];
} blaze_sym_info;

/**
 * C ABI compatible version of [`blazesym::inspect::Inspector`].
 */
typedef struct blaze_inspector blaze_inspector;

/**
 * An object representing an ELF inspection source.
 *
 * C ABI compatible version of [`inspect::source::Elf`].
 */
typedef struct blaze_inspect_elf_src {
  /**
   * The size of this object's type.
   *
   * Make sure to initialize it to `sizeof(<type>)`. This member is used to
   * ensure compatibility in the presence of member additions.
   */
  size_t type_size;
  /**
   * The path to the ELF file. This member is always present.
   */
  const char *path;
  /**
   * Whether or not to consult debug symbols to satisfy the request
   * (if present).
   */
  bool debug_syms;
  /**
   * Unused member available for future expansion. Must be initialized
   * to zero.
   */
  uint8_t reserved[23];
} blaze_inspect_elf_src;

/**
 * C ABI compatible version of [`blazesym::normalize::Normalizer`].
 */
typedef struct blaze_normalizer blaze_normalizer;

/**
 * Options for configuring [`blaze_normalizer`] objects.
 */
typedef struct blaze_normalizer_opts {
  /**
   * The size of this object's type.
   *
   * Make sure to initialize it to `sizeof(<type>)`. This member is used to
   * ensure compatibility in the presence of member additions.
   */
  size_t type_size;
  /**
   * Whether or not to use the `PROCMAP_QUERY` ioctl instead of
   * parsing `/proc/<pid>/maps` for getting available VMA ranges.
   *
   * Refer to
   * [`blaze_supports_procmap_query`][crate::helper::blaze_supports_procmap_query]
   * as a way to check whether your system supports this
   * functionality.
   *
   * # Notes
   *
   * Support for this ioctl is only present in very recent kernels
   * (likely: 6.11+). See <https://lwn.net/Articles/979931/> for
   * details.
   *
   * Furthermore, the ioctl will also be used for retrieving build
   * IDs (if enabled). Build ID reading logic in the kernel is known
   * to be incomplete, with a fix slated to be included only with
   * 6.12.
   */
  bool use_procmap_query;
  /**
   * Whether or not to cache `/proc/<pid>/maps` contents.
   *
   * Setting this flag to `true` is not generally recommended, because it
   * could result in addresses corresponding to mappings added after caching
   * may not be normalized successfully, as there is no reasonable way of
   * detecting staleness.
   */
  bool cache_vmas;
  /**
   * Whether to read and report build IDs as part of the normalization
   * process.
   *
   * Note that build ID read failures will be swallowed without
   * failing the normalization operation.
   */
  bool build_ids;
  /**
   * Whether or not to cache build IDs. This flag only has an effect
   * if build ID reading is enabled in the first place.
   */
  bool cache_build_ids;
  /**
   * Unused member available for future expansion. Must be initialized
   * to zero.
   */
  uint8_t reserved[20];
} blaze_normalizer_opts;

/**
 * The reason why normalization failed.
 *
 * The reason is generally only meant as a hint. Reasons reported may change
 * over time and, hence, should not be relied upon for the correctness of the
 * application.
 */
typedef uint8_t blaze_normalize_reason;
/**
 * The absolute address was not found in the corresponding process' virtual
 * memory map.
 */
#define BLAZE_NORMALIZE_REASON_UNMAPPED 0
/**
 * The `/proc/<pid>/maps` entry corresponding to the address does not have
 * a component (file system path, object, ...) associated with it.
 */
#define BLAZE_NORMALIZE_REASON_MISSING_COMPONENT 1
/**
 * The address belonged to an entity that is currently unsupported.
 */
#define BLAZE_NORMALIZE_REASON_UNSUPPORTED 2

/**
 * The valid variant kind in [`blaze_user_meta`].
 */
typedef uint8_t blaze_user_meta_kind;
/**
 * [`blaze_user_meta_variant::unknown`] is valid.
 */
#define BLAZE_USER_META_KIND_BLAZE_USER_META_UNKNOWN 0
/**
 * [`blaze_user_meta_variant::apk`] is valid.
 */
#define BLAZE_USER_META_KIND_BLAZE_USER_META_APK 1
/**
 * [`blaze_user_meta_variant::elf`] is valid.
 */
#define BLAZE_USER_META_KIND_BLAZE_USER_META_ELF 2

/**
 * C compatible version of [`Apk`].
 */
typedef struct blaze_user_meta_apk {
  /**
   * The canonical absolute path to the APK, including its name.
   * This member is always present.
   */
  char *path;
  /**
   * Unused member available for future expansion.
   */
  uint8_t reserved[16];
} blaze_user_meta_apk;

/**
 * C compatible version of [`Elf`].
 */
typedef struct blaze_user_meta_elf {
  /**
   * Ordinarily, the canonical absolute path to the ELF file,
   * including its name. In case of an ELF file contained inside an
   * APK (see [`blaze_normalize_opts::apk_to_elf`]) this will be an
   * Android style path of the form `<apk>!<elf-in-apk>`. E.g.,
   * `/root/test.apk!/lib/libc.so`.
   *
   * This member is always present.
   */
  char *path;
  /**
   * The length of the build ID, in bytes.
   */
  size_t build_id_len;
  /**
   * The optional build ID of the ELF file, if found and readable.
   */
  uint8_t *build_id;
  /**
   * Unused member available for future expansion.
   */
  uint8_t reserved[16];
} blaze_user_meta_elf;

/**
 * C compatible version of [`Unknown`].
 */
typedef struct blaze_user_meta_unknown {
  /**
   * The reason why normalization failed.
   *
   * The provided reason is a best guess, hinting at what ultimately
   * prevented the normalization from being successful.
   */
  blaze_normalize_reason reason;
  /**
   * Unused member available for future expansion.
   */
  uint8_t reserved[15];
} blaze_user_meta_unknown;

/**
 * The actual variant data in [`blaze_user_meta`].
 */
typedef union blaze_user_meta_variant {
  /**
   * Valid on [`blaze_user_meta_kind::BLAZE_USER_META_APK`].
   */
  struct blaze_user_meta_apk apk;
  /**
   * Valid on [`blaze_user_meta_kind::BLAZE_USER_META_ELF`].
   */
  struct blaze_user_meta_elf elf;
  /**
   * Valid on [`blaze_user_meta_kind::BLAZE_USER_META_UNKNOWN`].
   */
  struct blaze_user_meta_unknown unknown;
} blaze_user_meta_variant;

/**
 * C ABI compatible version of [`UserMeta`].
 */
typedef struct blaze_user_meta {
  /**
   * The variant kind that is present.
   */
  blaze_user_meta_kind kind;
  /**
   * Currently unused bytes.
   */
  uint8_t unused[7];
  /**
   * The actual variant with its data.
   */
  union blaze_user_meta_variant variant;
  /**
   * Unused member available for future expansion. Must be initialized
   * to zero.
   */
  uint8_t reserved[16];
} blaze_user_meta;

/**
 * A file offset or non-normalized address along with an index into the
 * associated [`blaze_user_meta`] array (such as
 * [`blaze_normalized_user_output::metas`]).
 */
typedef struct blaze_normalized_output {
  /**
   * The file offset or non-normalized address.
   */
  uint64_t output;
  /**
   * The index into the associated [`blaze_user_meta`] array.
   */
  size_t meta_idx;
  /**
   * Unused member available for future expansion. Must be initialized
   * to zero.
   */
  uint8_t reserved[16];
} blaze_normalized_output;

/**
 * An object representing normalized user addresses.
 *
 * C ABI compatible version of [`UserOutput`].
 */
typedef struct blaze_normalized_user_output {
  /**
   * The number of [`blaze_user_meta`] objects present in `metas`.
   */
  size_t meta_cnt;
  /**
   * An array of `meta_cnt` objects.
   */
  struct blaze_user_meta *metas;
  /**
   * The number of [`blaze_normalized_output`] objects present in `outputs`.
   */
  size_t output_cnt;
  /**
   * An array of `output_cnt` objects.
   */
  struct blaze_normalized_output *outputs;
  /**
   * Unused member available for future expansion.
   */
  uint8_t reserved[16];
} blaze_normalized_user_output;

/**
 * Options influencing the address normalization process.
 */
typedef struct blaze_normalize_opts {
  /**
   * The size of this object's type.
   *
   * Make sure to initialize it to `sizeof(<type>)`. This member is used to
   * ensure compatibility in the presence of member additions.
   */
  size_t type_size;
  /**
   * Whether or not addresses are sorted (in ascending order) already.
   *
   * Normalization always happens on sorted addresses and if the addresses
   * are sorted already, the library does not need to sort and later restore
   * original ordering, speeding up the normalization process.
   */
  bool sorted_addrs;
  /**
   * Whether to report `/proc/<pid>/map_files/` entry paths or work
   * with symbolic paths mentioned in `/proc/<pid>/maps` instead.
   *
   * Relying on `map_files` may make sense in cases where
   * symbolization happens on the local system and the reported paths
   * can be worked with directly. In most other cases where one wants
   * to attach meaning to symbolic paths on a remote system (e.g., by
   * using them for file look up) symbolic paths are probably the
   * better choice.
   */
  bool map_files;
  /**
   * Normalize addresses inside APKs to the contained ELF file and
   * report a regular
   * [`BLAZE_USER_META_ELF`][blaze_user_meta_kind::BLAZE_USER_META_ELF]
   * meta data entry instead of an
   * [`BLAZE_USER_META_APK`][blaze_user_meta_kind::BLAZE_USER_META_APK]
   * one. As a result, the reported file offset will also be relative
   * to the contained ELF file and not to the APK itself.
   */
  bool apk_to_elf;
  /**
   * Unused member available for future expansion. Must be initialized
   * to zero.
   */
  uint8_t reserved[21];
} blaze_normalize_opts;

/**
 * The reason why symbolization failed.
 *
 * The reason is generally only meant as a hint. Reasons reported may
 * change over time and, hence, should not be relied upon for the
 * correctness of the application.
 */
typedef uint8_t blaze_symbolize_reason;
/**
 * Symbolization was successful.
 */
#define BLAZE_SYMBOLIZE_REASON_SUCCESS 0
/**
 * The absolute address was not found in the corresponding process'
 * virtual memory map.
 */
#define BLAZE_SYMBOLIZE_REASON_UNMAPPED 1
/**
 * The file offset does not map to a valid piece of code/data.
 */
#define BLAZE_SYMBOLIZE_REASON_INVALID_FILE_OFFSET 2
/**
 * The `/proc/<pid>/maps` entry corresponding to the address does
 * not have a component (file system path, object, ...) associated
 * with it.
 */
#define BLAZE_SYMBOLIZE_REASON_MISSING_COMPONENT 3
/**
 * The symbolization source has no or no relevant symbols.
 */
#define BLAZE_SYMBOLIZE_REASON_MISSING_SYMS 4
/**
 * The address could not be found in the symbolization source.
 */
#define BLAZE_SYMBOLIZE_REASON_UNKNOWN_ADDR 5
/**
 * The address belonged to an entity that is currently unsupported.
 */
#define BLAZE_SYMBOLIZE_REASON_UNSUPPORTED 6

/**
 * C ABI compatible version of [`blazesym::symbolize::Symbolizer`].
 *
 * It is returned by [`blaze_symbolizer_new`] and should be free by
 * [`blaze_symbolizer_free`].
 */
typedef struct blaze_symbolizer blaze_symbolizer;

/**
 * Options for configuring [`blaze_symbolizer`] objects.
 */
typedef struct blaze_symbolizer_opts {
  /**
   * The size of this object's type.
   *
   * Make sure to initialize it to `sizeof(<type>)`. This member is used to
   * ensure compatibility in the presence of member additions.
   */
  size_t type_size;
  /**
   * Array of debug directories to search for split debug information.
   *
   * These directories will be consulted (in given order) when resolving
   * debug links in binaries. By default and when this member is NULL,
   * `/usr/lib/debug` and `/lib/debug/` will be searched. Setting an array
   * here will overwrite these defaults, so make sure to include these
   * directories as desired.
   *
   * Note that the directory containing a symbolization source is always an
   * implicit candidate target directory of the highest precedence.
   */
  const char *const *debug_dirs;
  /**
   * The number of array elements in `debug_dirs`.
   */
  size_t debug_dirs_len;
  /**
   * Whether or not to automatically reload file system based
   * symbolization sources that were updated since the last
   * symbolization operation.
   */
  bool auto_reload;
  /**
   * Whether to attempt to gather source code location information.
   *
   * This setting implies `debug_syms` (and forces it to `true`).
   */
  bool code_info;
  /**
   * Whether to report inlined functions as part of symbolization.
   */
  bool inlined_fns;
  /**
   * Whether or not to transparently demangle symbols.
   *
   * Demangling happens on a best-effort basis. Currently supported
   * languages are Rust and C++ and the flag will have no effect if
   * the underlying language does not mangle symbols (such as C).
   */
  bool demangle;
  /**
   * Unused member available for future expansion. Must be initialized
   * to zero.
   */
  uint8_t reserved[20];
} blaze_symbolizer_opts;

/**
 * Configuration for caching of ELF symbolization data.
 */
typedef struct blaze_cache_src_elf {
  /**
   * The size of this object's type.
   *
   * Make sure to initialize it to `sizeof(<type>)`. This member is used to
   * ensure compatibility in the presence of member additions.
   */
  size_t type_size;
  /**
   * The path to the ELF file.
   */
  const char *path;
  /**
   * Unused member available for future expansion. Must be initialized
   * to zero.
   */
  uint8_t reserved[16];
} blaze_cache_src_elf;

/**
 * Configuration for caching of process-level data.
 */
typedef struct blaze_cache_src_process {
  /**
   * The size of this object's type.
   *
   * Make sure to initialize it to `sizeof(<type>)`. This member is used to
   * ensure compatibility in the presence of member additions.
   */
  size_t type_size;
  /**
   * The referenced process' ID.
   */
  uint32_t pid;
  /**
   * Whether to cache the process' VMAs for later use.
   *
   * Caching VMAs can be useful, because it conceptually enables the
   * library to serve a symbolization request targeting a process
   * even if said process has since exited the system.
   *
   * Note that once VMAs have been cached this way, the library will
   * refrain from re-reading updated VMAs unless instructed to.
   * Hence, if you have reason to believe that a process may have
   * changed its memory regions (by loading a new shared object, for
   * example), you would have to make another request to cache them
   * yourself.
   *
   * Note furthermore that if you cache VMAs to later symbolize
   * addresses after the original process has already exited, you
   * will have to opt-out of usage of `/proc/<pid>/map_files/` as
   * part of the symbolization request. Refer to
   * [`blaze_symbolize_src_process::no_map_files`].
   */
  bool cache_vmas;
  /**
   * Unused member available for future expansion. Must be initialized
   * to zero.
   */
  uint8_t reserved[19];
} blaze_cache_src_process;

/**
 * Source code location information for a symbol or inlined function.
 */
typedef struct blaze_symbolize_code_info {
  /**
   * The directory in which the source file resides.
   *
   * This attribute is optional and may be NULL.
   */
  const char *dir;
  /**
   * The file that defines the symbol.
   *
   * This attribute is optional and may be NULL.
   */
  const char *file;
  /**
   * The line number on which the symbol is located in the source
   * code.
   */
  uint32_t line;
  /**
   * The column number of the symbolized instruction in the source
   * code.
   */
  uint16_t column;
  /**
   * Unused member available for future expansion.
   */
  uint8_t reserved[10];
} blaze_symbolize_code_info;

/**
 * Data about an inlined function call.
 */
typedef struct blaze_symbolize_inlined_fn {
  /**
   * The symbol name of the inlined function.
   */
  const char *name;
  /**
   * Source code location information for the inlined function.
   */
  struct blaze_symbolize_code_info code_info;
  /**
   * Unused member available for future expansion.
   */
  uint8_t reserved[8];
} blaze_symbolize_inlined_fn;

/**
 * The result of symbolization of an address.
 *
 * A `blaze_sym` is the information of a symbol found for an
 * address.
 */
typedef struct blaze_sym {
  /**
   * The symbol name is where the given address should belong to.
   *
   * If an address could not be symbolized, this member will be NULL.
   * Check the `reason` member for additional information pertaining
   * the failure.
   */
  const char *name;
  /**
   * The path to or name of the module containing the symbol.
   *
   * Typically this would be the path to a executable or shared
   * object. Depending on the symbol source this member may not be
   * present or it could also just be a file name without path. In
   * case of an ELF file contained inside an APK, this will be an
   * Android style path of the form `<apk>!<elf-in-apk>`. E.g.,
   * `/root/test.apk!/lib/libc.so`.
   */
  const char *module;
  /**
   * The address at which the symbol is located (i.e., its "start").
   *
   * This is the "normalized" address of the symbol, as present in
   * the file (and reported by tools such as `readelf(1)`,
   * `llvm-gsymutil`, or similar).
   */
  uint64_t addr;
  /**
   * The byte offset of the address that got symbolized from the
   * start of the symbol (i.e., from `addr`).
   *
   * E.g., when symbolizing address 0x1337 of a function that starts at
   * 0x1330, the offset will be set to 0x07 (and `addr` will be 0x1330). This
   * member is especially useful in contexts when input addresses are not
   * already normalized, such as when symbolizing an address in a process
   * context (which may have been relocated and/or have layout randomizations
   * applied).
   */
  size_t offset;
  /**
   * The size of the symbol.
   *
   * If the symbol's size is not available, this member will be `-1`.
   * Note that some symbol sources may not distinguish between
   * "unknown" size and `0`. In that case the size will be reported
   * as `0` here as well.
   */
  ptrdiff_t size;
  /**
   * Source code location information for the symbol.
   */
  struct blaze_symbolize_code_info code_info;
  /**
   * The number of symbolized inlined function calls present.
   */
  size_t inlined_cnt;
  /**
   * An array of `inlined_cnt` symbolized inlined function calls.
   */
  const struct blaze_symbolize_inlined_fn *inlined;
  /**
   * On error (i.e., if `name` is NULL), a reason trying to explain
   * why symbolization failed.
   */
  blaze_symbolize_reason reason;
  /**
   * Unused member available for future expansion.
   */
  uint8_t reserved[15];
} blaze_sym;

/**
 * `blaze_syms` is the result of symbolization of a list of addresses.
 *
 * Instances of [`blaze_syms`] are returned by any of the `blaze_symbolize_*`
 * variants. They should be freed by calling [`blaze_syms_free`].
 */
typedef struct blaze_syms {
  /**
   * The number of symbols being reported.
   */
  size_t cnt;
  /**
   * The symbols corresponding to input addresses.
   *
   * Symbolization happens based on the ordering of (input) addresses.
   * Therefore, every input address has an associated symbol.
   */
  struct blaze_sym syms[0];
} blaze_syms;

/**
 * The parameters to load symbols and debug information from a process.
 *
 * Load all ELF files in a process as the sources of symbols and debug
 * information.
 */
typedef struct blaze_symbolize_src_process {
  /**
   * The size of this object's type.
   *
   * Make sure to initialize it to `sizeof(<type>)`. This member is used to
   * ensure compatibility in the presence of member additions.
   */
  size_t type_size;
  /**
   * The referenced process' ID.
   */
  uint32_t pid;
  /**
   * Whether or not to consult debug symbols to satisfy the request
   * (if present).
   */
  bool debug_syms;
  /**
   * Whether to incorporate a process' perf map file into the symbolization
   * procedure.
   */
  bool perf_map;
  /**
   * Whether to work with `/proc/<pid>/map_files/` entries or with
   * symbolic paths mentioned in `/proc/<pid>/maps` instead.
   *
   * `no_map_files` usage is generally discouraged, as symbolic paths
   * are unlikely to work reliably in mount namespace contexts or
   * when files have been deleted from the file system. However, by
   * using symbolic paths (i.e., with `no_map_files` being `true`)
   * the need for requiring the `SYS_ADMIN` capability is eliminated.
   */
  bool no_map_files;
  /**
   * Unused member available for future expansion. Must be initialized
   * to zero.
   */
  uint8_t reserved[17];
} blaze_symbolize_src_process;

/**
 * The parameters to load symbols and debug information from a kernel.
 */
typedef struct blaze_symbolize_src_kernel {
  /**
   * The size of this object's type.
   *
   * Make sure to initialize it to `sizeof(<type>)`. This member is used to
   * ensure compatibility in the presence of member additions.
   */
  size_t type_size;
  /**
   * The path of a `kallsyms` file to use.
   *
   * When `NULL`, this will refer to `kallsyms` of the running kernel.
   * If set to `'\0'` (`""`) usage of `kallsyms` will be disabled.
   * Otherwise the copy at the given path will be used.
   *
   * If both a `vmlinux` as well as a `kallsyms` file are found,
   * `vmlinux` will generally be given preference and `kallsyms` acts
   * as a fallback.
   */
  const char *kallsyms;
  /**
   * The path of the `vmlinux` file to use.
   *
   * `vmlinux` is generally an uncompressed and unstripped object
   * file that is typically used in debugging, profiling, and
   * similar use cases.
   *
   * When `NULL`, the library will search for `vmlinux` candidates in
   * various locations, taking into account the currently running
   * kernel version. If set to `'\0'` (`""`) discovery and usage of a
   * `vmlinux` will be disabled. Otherwise the copy at the given path
   * will be used.
   *
   * If both a `vmlinux` as well as a `kallsyms` file are found,
   * `vmlinux` will generally be given preference and `kallsyms` acts
   * as a fallback.
   */
  const char *vmlinux;
  /**
   * Whether or not to consult debug symbols from `vmlinux` to
   * satisfy the request (if present).
   */
  bool debug_syms;
  /**
   * Unused member available for future expansion. Must be initialized
   * to zero.
   */
  uint8_t reserved[23];
} blaze_symbolize_src_kernel;

/**
 * The parameters to load symbols and debug information from an ELF.
 *
 * Describes the path and address of an ELF file loaded in a
 * process.
 */
typedef struct blaze_symbolize_src_elf {
  /**
   * The size of this object's type.
   *
   * Make sure to initialize it to `sizeof(<type>)`. This member is used to
   * ensure compatibility in the presence of member additions.
   */
  size_t type_size;
  /**
   * The path to the ELF file.
   *
   * The referenced file may be an executable or shared object. For example,
   * passing "/bin/sh" will load symbols and debug information from `sh` and
   * passing "/lib/libc.so.xxx" will load symbols and debug information from
   * libc.
   */
  const char *path;
  /**
   * Whether or not to consult debug symbols to satisfy the request
   * (if present).
   */
  bool debug_syms;
  /**
   * Unused member available for future expansion. Must be initialized
   * to zero.
   */
  uint8_t reserved[23];
} blaze_symbolize_src_elf;

/**
 * The parameters to load symbols and debug information from "raw" Gsym data.
 */
typedef struct blaze_symbolize_src_gsym_data {
  /**
   * The size of this object's type.
   *
   * Make sure to initialize it to `sizeof(<type>)`. This member is used to
   * ensure compatibility in the presence of member additions.
   */
  size_t type_size;
  /**
   * The Gsym data.
   */
  const uint8_t *data;
  /**
   * The size of the Gsym data.
   */
  size_t data_len;
  /**
   * Unused member available for future expansion. Must be initialized
   * to zero.
   */
  uint8_t reserved[16];
} blaze_symbolize_src_gsym_data;

/**
 * The parameters to load symbols and debug information from a Gsym file.
 */
typedef struct blaze_symbolize_src_gsym_file {
  /**
   * The size of this object's type.
   *
   * Make sure to initialize it to `sizeof(<type>)`. This member is used to
   * ensure compatibility in the presence of member additions.
   */
  size_t type_size;
  /**
   * The path to a gsym file.
   */
  const char *path;
  /**
   * Unused member available for future expansion. Must be initialized
   * to zero.
   */
  uint8_t reserved[16];
} blaze_symbolize_src_gsym_file;

/**
 * The level at which to emit traces.
 */
typedef uint8_t blaze_trace_lvl;
/**
 * Emit all trace events.
 *
 * This is the most verbose level and includes all others.
 */
#define BLAZE_TRACE_LVL_TRACE 0
/**
 * Emit debug traces and above.
 *
 * This level excludes traces emitted with "TRACE" verbosity.
 */
#define BLAZE_TRACE_LVL_DEBUG 1
/**
 * Emit info level traces and above.
 *
 * This level excludes traces emitted with "TRACE" or "DEBUG"
 * verbosity.
 */
#define BLAZE_TRACE_LVL_INFO 2
/**
 * Only emit warnings.
 */
#define BLAZE_TRACE_LVL_WARN 3

/**
 * The signature of a callback function as passed to [`blaze_trace`].
 */
typedef void (*blaze_trace_cb)(const char*);

#ifdef __cplusplus
extern "C" {
#endif // __cplusplus

/**
 * Retrieve the error reported by the last fallible API function invoked.
 */
blaze_err blaze_err_last(void);

/**
 * Retrieve a textual representation of the error code.
 */
const char *blaze_err_str(blaze_err err);

/**
 * Check whether the `PROCMAP_QUERY` ioctl is supported by the system.
 *
 * This function returns `true` if the system supports the
 * `PROCMAP_QUERY` ioctl and `false` in all other cases, including when
 * an error occurred. Use [`blaze_err_last`] to optionally retrieve
 * this error.
 */
bool blaze_supports_procmap_query(void);

/**
 * Read the build ID of an ELF file located at the given path.
 *
 * Build IDs can have variable length, depending on which flavor is
 * used (e.g., 20 bytes for `sha1` flavor). Build IDs are
 * reported as "raw" bytes. If you need a hexadecimal representation as
 * reported by tools such as `readelf(1)`, a post processing step is
 * necessary.
 *
 * On success and when a build ID present, the function returns a
 * pointer to the "raw" build ID bytes and `len`, if provided, is set
 * to the build ID's length. The resulting buffer should be released
 * using libc's `free` function once it is no longer needed.
 *
 * On error, the function returns `NULL` and sets the thread's last
 * error to indicate the problem encountered. Use [`blaze_err_last`] to
 * retrieve this error.
 *
 * Similarly, if no build ID is present `NULL` is returned and the last
 * error will be set to [`blaze_err::OK`].
 *
 * # Safety
 * - `path` needs to be a valid pointer to a NUL terminated string
 */
uint8_t *blaze_read_elf_build_id(const char *path,
                                 size_t *len);

/**
 * Lookup symbol information in an ELF file.
 *
 * On success, returns an array with `name_cnt` elements. Each such element, in
 * turn, is NULL terminated array comprised of each symbol found. The returned
 * object should be released using [`blaze_inspect_syms_free`] once it is no
 * longer needed.
 *
 * On error, the function returns `NULL` and sets the thread's last error to
 * indicate the problem encountered. Use [`blaze_err_last`] to retrieve this
 * error.
 *
 * # Safety
 * - `inspector` needs to point to an initialized [`blaze_inspector`] object
 * - `src` needs to point to an initialized [`blaze_inspect_syms_elf`] object
 * - `names` needs to be a valid pointer to `name_cnt` NUL terminated strings
 */
const struct blaze_sym_info *const *blaze_inspect_syms_elf(const blaze_inspector *inspector,
                                                           const struct blaze_inspect_elf_src *src,
                                                           const char *const *names,
                                                           size_t name_cnt);

/**
 * Free an array returned by [`blaze_inspect_syms_elf`].
 *
 * # Safety
 *
 * The pointer must be returned by [`blaze_inspect_syms_elf`].
 */
void blaze_inspect_syms_free(const struct blaze_sym_info *const *syms);

/**
 * Create an instance of a blazesym inspector.
 *
 * C ABI compatible version of [`blazesym::inspect::Inspector::new()`].
 * Please refer to its documentation for the default configuration in
 * use.
 *
 * On success, the function creates a new [`blaze_inspector`] object
 * and returns it. The resulting object should be released using
 * [`blaze_inspector_free`] once it is no longer needed.
 *
 * On error, the function returns `NULL` and sets the thread's last error to
 * indicate the problem encountered. Use [`blaze_err_last`] to retrieve this
 * error.
 */
blaze_inspector *blaze_inspector_new(void);

/**
 * Free a blazesym inspector.
 *
 * Release resources associated with a inspector as created by
 * [`blaze_inspector_new`], for example.
 *
 * # Safety
 * The provided inspector should have been created by
 * [`blaze_inspector_new`].
 */
void blaze_inspector_free(blaze_inspector *inspector);

/**
 * Create an instance of a blazesym normalizer in the default
 * configuration.
 *
 * C ABI compatible version of [`blazesym::normalize::Normalizer::new()`].
 * Please refer to its documentation for the default configuration in use.
 *
 * On success, the function creates a new [`blaze_normalizer`] object and
 * returns it. The resulting object should be released using
 * [`blaze_normalizer_free`] once it is no longer needed.
 *
 * On error, the function returns `NULL` and sets the thread's last error to
 * indicate the problem encountered. Use [`blaze_err_last`] to retrieve this
 * error.
 */
blaze_normalizer *blaze_normalizer_new(void);

/**
 * Create an instance of a blazesym normalizer.
 *
 * On success, the function creates a new [`blaze_normalizer`] object and
 * returns it. The resulting object should be released using
 * [`blaze_normalizer_free`] once it is no longer needed.
 *
 * On error, the function returns `NULL` and sets the thread's last error to
 * indicate the problem encountered. Use [`blaze_err_last`] to retrieve this
 * error.
 *
 * # Safety
 * - `opts` needs to point to a valid [`blaze_normalizer_opts`] object
 */
blaze_normalizer *blaze_normalizer_new_opts(const struct blaze_normalizer_opts *opts);

/**
 * Free a blazesym normalizer.
 *
 * Release resources associated with a normalizer as created by
 * [`blaze_normalizer_new`], for example.
 *
 * # Safety
 * The provided normalizer should have been created by
 * [`blaze_normalizer_new`].
 */
void blaze_normalizer_free(blaze_normalizer *normalizer);

/**
 * Retrieve a textual representation of the reason of a normalization failure.
 */
const char *blaze_normalize_reason_str(blaze_normalize_reason err);

/**
 * Normalize a list of user space addresses.
 *
 * C ABI compatible version of [`Normalizer::normalize_user_addrs`].
 *
 * `pid` should describe the PID of the process to which the addresses
 * belongs. It may be `0` if they belong to the calling process.
 *
 * On success, the function creates a new [`blaze_normalized_user_output`]
 * object and returns it. The resulting object should be released using
 * [`blaze_user_output_free`] once it is no longer needed.
 *
 * On error, the function returns `NULL` and sets the thread's last error to
 * indicate the problem encountered. Use [`blaze_err_last`] to retrieve this
 * error.
 *
 * # Safety
 * - `addrs` needs to be a valid pointer to `addr_cnt` addresses
 */
struct blaze_normalized_user_output *blaze_normalize_user_addrs(const blaze_normalizer *normalizer,
                                                                uint32_t pid,
                                                                const uint64_t *addrs,
                                                                size_t addr_cnt);

/**
 * Normalize a list of user space addresses.
 *
 * C ABI compatible version of [`Normalizer::normalize_user_addrs_opts`].
 *
 * `pid` should describe the PID of the process to which the addresses
 * belongs. It may be `0` if they belong to the calling process.
 *
 * `opts` should point to a valid [`blaze_normalize_opts`] object.
 *
 * On success, the function creates a new [`blaze_normalized_user_output`]
 * object and returns it. The resulting object should be released using
 * [`blaze_user_output_free`] once it is no longer needed.
 *
 * On error, the function returns `NULL` and sets the thread's last error to
 * indicate the problem encountered. Use [`blaze_err_last`] to retrieve this
 * error.
 *
 * # Safety
 * - `addrs` needs to be a valid pointer to `addr_cnt` addresses
 */
struct blaze_normalized_user_output *blaze_normalize_user_addrs_opts(const blaze_normalizer *normalizer,
                                                                     uint32_t pid,
                                                                     const uint64_t *addrs,
                                                                     size_t addr_cnt,
                                                                     const struct blaze_normalize_opts *opts);

/**
 * Free an object as returned by [`blaze_normalize_user_addrs`] or
 * [`blaze_normalize_user_addrs_opts`].
 *
 * # Safety
 * The provided object should have been created by
 * [`blaze_normalize_user_addrs`] or
 * [`blaze_normalize_user_addrs_opts`].
 */
void blaze_user_output_free(struct blaze_normalized_user_output *output);

/**
 * Retrieve a textual representation of the reason of a symbolization
 * failure.
 */
const char *blaze_symbolize_reason_str(blaze_symbolize_reason err);

/**
 * Create an instance of a symbolizer.
 *
 * C ABI compatible version of [`blazesym::symbolize::Symbolizer::new()`].
 * Please refer to its documentation for the default configuration in use.
 *
 * On success, the function creates a new [`blaze_symbolizer`] object
 * and returns it. The resulting object should be released using
 * [`blaze_symbolizer_free`] once it is no longer needed.
 *
 * On error, the function returns `NULL` and sets the thread's last error to
 * indicate the problem encountered. Use [`blaze_err_last`] to retrieve this
 * error.
 */
blaze_symbolizer *blaze_symbolizer_new(void);

/**
 * Create an instance of a symbolizer with configurable options.
 *
 * On success, the function creates a new [`blaze_symbolizer`] object
 * and returns it. The resulting object should be released using
 * [`blaze_symbolizer_free`] once it is no longer needed.
 *
 * On error, the function returns `NULL` and sets the thread's last error to
 * indicate the problem encountered. Use [`blaze_err_last`] to retrieve this
 * error.
 *
 * # Safety
 * - `opts` needs to point to a valid [`blaze_symbolizer_opts`] object
 */
blaze_symbolizer *blaze_symbolizer_new_opts(const struct blaze_symbolizer_opts *opts);

/**
 * Free an instance of blazesym a symbolizer for C API.
 *
 * # Safety
 * The pointer must have been returned by [`blaze_symbolizer_new`] or
 * [`blaze_symbolizer_new_opts`].
 */
void blaze_symbolizer_free(blaze_symbolizer *symbolizer);

/**
 * Cache an ELF symbolization source.
 *
 * Cache symbolization data of an ELF file.
 *
 * The function sets the thread's last error to either
 * [`blaze_err::OK`] to indicate success or a different error code
 * associated with the problem encountered. Use [`blaze_err_last`] to
 * retrieve this error.
 *
 * # Safety
 * - `symbolizer` needs to point to a valid [`blaze_symbolizer`] object
 * - `cache` needs to point to a valid [`blaze_cache_src_process`] object
 */
void blaze_symbolize_cache_elf(blaze_symbolizer *symbolizer,
                               const struct blaze_cache_src_elf *cache);

/**
 * Cache VMA meta data associated with a process.
 *
 * Cache VMA meta data associated with a process. This will speed up
 * subsequent symbolization requests while also enabling symbolization
 * of addresses belonging to processes that exited after being cache
 * this way.
 *
 * If this method fails, any previously cached data is left untouched
 * and will be used subsequently as if no failure occurred. Put
 * differently, this method is only effectful on the happy path.
 *
 * The function sets the thread's last error to either
 * [`blaze_err::OK`] to indicate success or a different error code
 * associated with the problem encountered. Use [`blaze_err_last`] to
 * retrieve this error.
 *
 * # Safety
 * - `symbolizer` needs to point to a valid [`blaze_symbolizer`] object
 * - `cache` needs to point to a valid [`blaze_cache_src_process`] object
 */
void blaze_symbolize_cache_process(blaze_symbolizer *symbolizer,
                                   const struct blaze_cache_src_process *cache);

/**
 * Symbolize a list of process absolute addresses.
 *
 * On success, the function returns a [`blaze_syms`] containing an
 * array of `abs_addr_cnt` [`blaze_sym`] objects. The returned object
 * should be released using [`blaze_syms_free`] once it is no longer
 * needed.
 *
 * On error, the function returns `NULL` and sets the thread's last error to
 * indicate the problem encountered. Use [`blaze_err_last`] to retrieve this
 * error.
 *
 * # Safety
 * - `symbolizer` needs to point to a valid [`blaze_symbolizer`] object
 * - `src` needs to point to a valid [`blaze_symbolize_src_process`] object
 * - `abs_addrs` point to an array of `abs_addr_cnt` addresses
 */
const struct blaze_syms *blaze_symbolize_process_abs_addrs(blaze_symbolizer *symbolizer,
                                                           const struct blaze_symbolize_src_process *src,
                                                           const uint64_t *abs_addrs,
                                                           size_t abs_addr_cnt);

/**
 * Symbolize a list of kernel absolute addresses.
 *
 * On success, the function returns a [`blaze_syms`] containing an
 * array of `abs_addr_cnt` [`blaze_sym`] objects. The returned object
 * should be released using [`blaze_syms_free`] once it is no longer
 * needed.
 *
 * On error, the function returns `NULL` and sets the thread's last error to
 * indicate the problem encountered. Use [`blaze_err_last`] to retrieve this
 * error.
 *
 * # Safety
 * - `symbolizer` needs to point to a valid [`blaze_symbolizer`] object
 * - `src` needs to point to a valid [`blaze_symbolize_src_kernel`] object
 * - `abs_addrs` point to an array of `abs_addr_cnt` addresses
 */
const struct blaze_syms *blaze_symbolize_kernel_abs_addrs(blaze_symbolizer *symbolizer,
                                                          const struct blaze_symbolize_src_kernel *src,
                                                          const uint64_t *abs_addrs,
                                                          size_t abs_addr_cnt);

/**
 * Symbolize virtual offsets in an ELF file.
 *
 * On success, the function returns a [`blaze_syms`] containing an
 * array of `virt_offset_cnt` [`blaze_sym`] objects. The returned
 * object should be released using [`blaze_syms_free`] once it is no
 * longer needed.
 *
 * On error, the function returns `NULL` and sets the thread's last error to
 * indicate the problem encountered. Use [`blaze_err_last`] to retrieve this
 * error.
 *
 * # Safety
 * - `symbolizer` needs to point to a valid [`blaze_symbolizer`] object
 * - `src` needs to point to a valid [`blaze_symbolize_src_elf`] object
 * - `virt_offsets` point to an array of `virt_offset_cnt` addresses
 */
const struct blaze_syms *blaze_symbolize_elf_virt_offsets(blaze_symbolizer *symbolizer,
                                                          const struct blaze_symbolize_src_elf *src,
                                                          const uint64_t *virt_offsets,
                                                          size_t virt_offset_cnt);

/**
 * Symbolize file offsets in an ELF file.
 *
 * On success, the function returns a [`blaze_syms`] containing an
 * array of `file_offset_cnt` [`blaze_sym`] objects. The returned
 * object should be released using [`blaze_syms_free`] once it is no
 * longer needed.
 *
 * On error, the function returns `NULL` and sets the thread's last error to
 * indicate the problem encountered. Use [`blaze_err_last`] to retrieve this
 * error.
 *
 * # Safety
 * - `symbolizer` needs to point to a valid [`blaze_symbolizer`] object
 * - `src` needs to point to a valid [`blaze_symbolize_src_elf`] object
 * - `file_offsets` point to an array of `file_offset_cnt` addresses
 */
const struct blaze_syms *blaze_symbolize_elf_file_offsets(blaze_symbolizer *symbolizer,
                                                          const struct blaze_symbolize_src_elf *src,
                                                          const uint64_t *file_offsets,
                                                          size_t file_offset_cnt);

/**
 * Symbolize virtual offsets using "raw" Gsym data.
 *
 * On success, the function returns a [`blaze_syms`] containing an
 * array of `virt_offset_cnt` [`blaze_sym`] objects. The returned
 * object should be released using [`blaze_syms_free`] once it is no
 * longer needed.
 *
 * On error, the function returns `NULL` and sets the thread's last error to
 * indicate the problem encountered. Use [`blaze_err_last`] to retrieve this
 * error.
 *
 * # Safety
 * - `symbolizer` needs to point to a valid [`blaze_symbolizer`] object
 * - `src` needs to point to a valid [`blaze_symbolize_src_gsym_data`] object
 * - `virt_offsets` point to an array of `virt_offset_cnt` addresses
 */
const struct blaze_syms *blaze_symbolize_gsym_data_virt_offsets(blaze_symbolizer *symbolizer,
                                                                const struct blaze_symbolize_src_gsym_data *src,
                                                                const uint64_t *virt_offsets,
                                                                size_t virt_offset_cnt);

/**
 * Symbolize virtual offsets in a Gsym file.
 *
 * On success, the function returns a [`blaze_syms`] containing an
 * array of `virt_offset_cnt` [`blaze_sym`] objects. The returned
 * object should be released using [`blaze_syms_free`] once it is no
 * longer needed.
 *
 * On error, the function returns `NULL` and sets the thread's last error to
 * indicate the problem encountered. Use [`blaze_err_last`] to retrieve this
 * error.
 *
 * # Safety
 * - `symbolizer` needs to point to a valid [`blaze_symbolizer`] object
 * - `src` needs to point to a valid [`blaze_symbolize_src_gsym_file`] object
 * - `virt_offsets` point to an array of `virt_offset_cnt` addresses
 */
const struct blaze_syms *blaze_symbolize_gsym_file_virt_offsets(blaze_symbolizer *symbolizer,
                                                                const struct blaze_symbolize_src_gsym_file *src,
                                                                const uint64_t *virt_offsets,
                                                                size_t virt_offset_cnt);

/**
 * Free an array returned by any of the `blaze_symbolize_*` variants.
 *
 * # Safety
 * The pointer must have been returned by any of the `blaze_symbolize_*`
 * variants.
 */
void blaze_syms_free(const struct blaze_syms *syms);

/**
 * Enable the main library's tracing infrastructure and invoke a
 * callback function for each emitted trace line.
 *
 * The provided [`blaze_trace_lvl`] determines what kind of traces are
 * emitted.
 *
 * This function should be invoked at most once. Subsequent invocations
 * will not affect tracing behavior.
 *
 * On error the function sets the thread's last error to indicate the
 * problem encountered. Use [`blaze_err_last`] to retrieve this error.
 *
 * # Notes
 * - the format of emitted lines is unspecified and subject to change; it is
 *   meant for human consumption and not programmatic evaluation
 */
void blaze_trace(blaze_trace_lvl lvl,
                 blaze_trace_cb cb);

#ifdef __cplusplus
}  // extern "C"
#endif  // __cplusplus

#endif  /* __blazesym_h_ */
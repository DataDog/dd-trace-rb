#include <ruby.h>
#include <limits.h>
#include <ruby/thread.h>

#include "datadog_ruby_common.h"
#include "http_client.h"

#ifndef HAVE_DDOG_HTTP_CLIENT_NEW

// libdatadog in use does not ship the native HTTP client: the Ruby class is simply not defined.
void http_client_init(DDTRACE_UNUSED VALUE core_module) { }

#else

#include <datadog/http-client.h>
#include <datadog/shared-runtime.h>

// Native HTTP client used by `Datadog::Core::Transport::HTTP::Adapters::Native`.

typedef struct {
  ddog_HttpClient *client;
} http_client_t;

// One tokio runtime shared by every native HTTP client in the process. Created lazily by the first
// client, under the GVL, and kept until the process exits: each client holds its own reference to it, so
// it is never freed here.
//
// Unlike the trace exporter, which has a single instance and so owns its runtime, this one must be paused
// and restarted around forks by the process-wide hooks below, not by each client.
static const ddog_ForkSafeRuntime *shared_runtime = NULL;

static void check_shared_runtime_error(const char *context, ddog_SharedRuntimeFFIError *err);

static const ddog_ForkSafeRuntime *get_or_create_shared_runtime(void) {
  if (shared_runtime == NULL) {
    check_shared_runtime_error("Failed to create the shared runtime", ddog_shared_runtime_new(&shared_runtime));
  }
  return shared_runtime;
}

static void http_client_free_resources(http_client_t *wrapper) {
  if (wrapper->client != NULL) {
    ddog_http_client_drop(wrapper->client);
    wrapper->client = NULL;
  }
}

static void http_client_dfree(void *ptr) {
  http_client_t *wrapper = (http_client_t *) ptr;
  http_client_free_resources(wrapper);
  ruby_xfree(wrapper);
}

static const rb_data_type_t http_client_typed_data = {
  .wrap_struct_name = "Datadog::Core::Transport::HTTP::Adapters::Native::Client",
  .function = {
    .dmark = NULL,
    .dfree = http_client_dfree,
    .dsize = NULL,
  },
  .flags = RUBY_TYPED_FREE_IMMEDIATELY
};

static VALUE http_client_class = Qnil;

static VALUE ok_symbol;
static VALUE error_symbol;

static VALUE error_code_symbol(ddog_HttpClientErrorCode code) {
  switch (code) {
    case DDOG_HTTP_CLIENT_ERROR_CODE_INVALID_ARGUMENT: return ID2SYM(rb_intern_const("invalid_argument"));
    case DDOG_HTTP_CLIENT_ERROR_CODE_INVALID_CONFIG: return ID2SYM(rb_intern_const("invalid_config"));
    case DDOG_HTTP_CLIENT_ERROR_CODE_CONNECTION_FAILED: return ID2SYM(rb_intern_const("connection_failed"));
    case DDOG_HTTP_CLIENT_ERROR_CODE_TIMED_OUT: return ID2SYM(rb_intern_const("timed_out"));
    case DDOG_HTTP_CLIENT_ERROR_CODE_CANCELLED: return ID2SYM(rb_intern_const("cancelled"));
    case DDOG_HTTP_CLIENT_ERROR_CODE_IO: return ID2SYM(rb_intern_const("io"));
    case DDOG_HTTP_CLIENT_ERROR_CODE_RUNTIME: return ID2SYM(rb_intern_const("runtime"));
    case DDOG_HTTP_CLIENT_ERROR_CODE_PANIC: return ID2SYM(rb_intern_const("panic"));
  }
  return ID2SYM(rb_intern_const("unknown"));
}

// Copies the message into `buffer` and frees the error, so it can then be used in a call that raises.
static ddog_HttpClientErrorCode copy_error_and_free(ddog_HttpClientError *error, char *buffer, size_t capacity) {
  ddog_HttpClientErrorCode code = error->code;
  snprintf(buffer, capacity, "%s", error->message != NULL ? error->message : "(unknown error)");
  ddog_http_client_error_free(error);
  return code;
}

static void check_shared_runtime_error(const char *context, ddog_SharedRuntimeFFIError *err) {
  if (err == NULL) return;

  char buf[MAX_RAISE_MESSAGE_SIZE];
  snprintf(buf, sizeof(buf), "%s: %s", context, err->msg != NULL ? err->msg : "(unknown error)");
  ddog_shared_runtime_error_free(err);
  raise_error(rb_eRuntimeError, "%s", buf);
}

static http_client_t *get_open_client(VALUE self) {
  http_client_t *wrapper;
  TypedData_Get_Struct(self, http_client_t, &http_client_typed_data, wrapper);
  if (wrapper->client == NULL) raise_error(rb_eRuntimeError, "The native HTTP client is closed");
  return wrapper;
}

static VALUE hash_get(VALUE hash, const char *key) {
  return rb_hash_aref(hash, ID2SYM(rb_intern(key)));
}

// ========================================================================
// Client#_native_new
// ========================================================================

static VALUE _native_new(DDTRACE_UNUSED VALUE _klass, VALUE config) {
  ENFORCE_TYPE(config, T_HASH);

  VALUE base_url = hash_get(config, "base_url");
  VALUE timeout_ms = hash_get(config, "timeout_ms");
  VALUE unix_socket_path = hash_get(config, "unix_socket_path");

  ENFORCE_TYPE(base_url, T_STRING);
  ENFORCE_TYPE(timeout_ms, T_FIXNUM);
  if (!NIL_P(unix_socket_path)) ENFORCE_TYPE(unix_socket_path, T_STRING);

  long timeout = FIX2LONG(timeout_ms);
  if (timeout <= 0) raise_error(rb_eArgError, "timeout_ms must be greater than zero");

  // Everything that can raise has been done; from here on, the wrapper owns the native resources
  // (the zeroed wrapper is safe to free at any point).
  http_client_t *wrapper;
  VALUE self = TypedData_Make_Struct(http_client_class, http_client_t, &http_client_typed_data, wrapper);

  char buf[MAX_RAISE_MESSAGE_SIZE];

  const ddog_ForkSafeRuntime *runtime = get_or_create_shared_runtime();

  ddog_HttpClientConfig native_config = {
    .base_url = char_slice_from_ruby_string(base_url),
    .timeout_ms = (uint64_t) timeout,
    .unix_socket_path = NIL_P(unix_socket_path) ? DDOG_CHARSLICE_C("") : char_slice_from_ruby_string(unix_socket_path),
    // Agent traffic is a handful of requests every few seconds: see `HttpClientBuilder::periodic`.
    .periodic = true,
  };

  ddog_HttpClientError *error = ddog_http_client_new(&native_config, runtime, &wrapper->client);
  if (error != NULL) {
    ddog_HttpClientErrorCode code = copy_error_and_free(error, buf, sizeof(buf));
    VALUE exception_class =
      (code == DDOG_HTTP_CLIENT_ERROR_CODE_INVALID_ARGUMENT || code == DDOG_HTTP_CLIENT_ERROR_CODE_INVALID_CONFIG) ?
        rb_eArgError : rb_eRuntimeError;
    raise_error(exception_class, "Failed to create the native HTTP client: %s", buf);
  }

  return self;
}

// ========================================================================
// Client#_native_send
// ========================================================================

typedef struct {
  const ddog_HttpClient *client;
  const ddog_HttpRequest *request;
  const ddog_HttpCancellationToken *cancel_token;
  ddog_HttpResponse *response;
  ddog_HttpClientError *error;
  bool send_ran;
} send_without_gvl_arguments;

static void *send_without_gvl(void *data) {
  send_without_gvl_arguments *args = (send_without_gvl_arguments *) data;
  args->error = ddog_http_client_send(args->client, args->request, args->cancel_token, &args->response);
  args->send_ran = true;
  return NULL;
}

// Called by Ruby (from another thread) while we're blocked in `send_without_gvl`, e.g. on `Thread#kill` or
// `Timeout`. Cancelling makes the native send return promptly with the `cancelled` error.
//
// Ruby clears the unblock function under the same lock it's called with before `rb_thread_call_without_gvl2`
// returns, so the token is still alive here.
static void interrupt_send(void *cancel_token) {
  (void) ddog_http_cancel_token_cancel((const ddog_HttpCancellationToken *) cancel_token);
}

static VALUE process_pending_interruptions(DDTRACE_UNUSED VALUE _) {
  rb_thread_check_ints();
  return Qnil;
}

// Checks for a pending Ruby exception without raising it, so we can clean up first.
__attribute__((warn_unused_result))
static int check_if_pending_exception(void) {
  int pending_exception;
  rb_protect(process_pending_interruptions, Qnil, &pending_exception);
  return pending_exception;
}

static ddog_HttpMethod method_from_verb(VALUE verb) {
  ENFORCE_TYPE(verb, T_SYMBOL);

  ID id = SYM2ID(verb);
  if (id == rb_intern("get")) return DDOG_HTTP_METHOD_GET;
  if (id == rb_intern("post")) return DDOG_HTTP_METHOD_POST;
  if (id == rb_intern("put")) return DDOG_HTTP_METHOD_PUT;
  if (id == rb_intern("delete")) return DDOG_HTTP_METHOD_DELETE;
  if (id == rb_intern("head")) return DDOG_HTTP_METHOD_HEAD;
  if (id == rb_intern("patch")) return DDOG_HTTP_METHOD_PATCH;
  if (id == rb_intern("options")) return DDOG_HTTP_METHOD_OPTIONS;

  raise_error(rb_eArgError, "Unknown HTTP verb: %+"PRIsVALUE, verb);
}

// The request borrows its bytes while the GVL is released, and in that time other Ruby threads can mutate the
// original strings, or the GC can move them (short strings live inside the object slot, which compaction may
// relocate). So nothing points into Ruby strings: the whole request (the header and part arrays, and the bytes
// of every string) is copied into one temporary buffer owned by Ruby (`rb_alloc_tmp_buffer`; it is freed by the
// GC if an exception interrupts us, and by `release_prepared_request` otherwise).
typedef struct {
  ddog_HttpRequest request;
  VALUE buffer;
} prepared_request;

static size_t string_length(VALUE string) {
  ENFORCE_TYPE(string, T_STRING);
  return (size_t) RSTRING_LEN(string);
}

static size_t optional_string_length(VALUE string) {
  return NIL_P(string) ? 0 : string_length(string);
}

static size_t checked_add(size_t a, size_t b) {
  if (a > (size_t) LONG_MAX - b) raise_error(rb_eArgError, "The request is too large");
  return a + b;
}

// Copies the bytes of `string` at `*cursor` and returns where they are. Strings are measured before copying and
// no Ruby code runs in between, so running out of room means a broken invariant.
static const char *copy_string(char **cursor, const char *end, VALUE string) {
  size_t length = (size_t) RSTRING_LEN(string);
  if ((size_t) (end - *cursor) < length) raise_error(rb_eRuntimeError, "The request changed while it was being prepared");
  char *destination = *cursor;
  if (length > 0) memcpy(destination, RSTRING_PTR(string), length);
  *cursor += length;
  return destination;
}

static ddog_CharSlice copy_text(char **cursor, const char *end, VALUE string) {
  const char *ptr = copy_string(cursor, end, string);
  return (ddog_CharSlice) {.ptr = ptr, .len = (uintptr_t) RSTRING_LEN(string)};
}

static ddog_CharSlice copy_optional_text(char **cursor, const char *end, VALUE string) {
  return NIL_P(string) ? DDOG_CHARSLICE_C("") : copy_text(cursor, end, string);
}

static ddog_ByteSlice copy_bytes(char **cursor, const char *end, VALUE string) {
  const char *ptr = copy_string(cursor, end, string);
  return (ddog_ByteSlice) {.ptr = (const uint8_t *) ptr, .len = (uintptr_t) RSTRING_LEN(string)};
}

// Fills `prepared` from the Ruby request hash. It can raise at any point: the buffer is then reclaimed by the GC.
static void prepare_request(VALUE request, prepared_request *prepared) {
  ENFORCE_TYPE(request, T_HASH);

  VALUE verb = hash_get(request, "verb");
  VALUE path = hash_get(request, "path");
  VALUE headers = hash_get(request, "headers");
  VALUE body = hash_get(request, "body");
  VALUE multipart = hash_get(request, "multipart");

  ENFORCE_TYPE(headers, T_ARRAY);
  if (!NIL_P(multipart)) ENFORCE_TYPE(multipart, T_ARRAY);

  long headers_count = RARRAY_LEN(headers);
  long parts_count = NIL_P(multipart) ? 0 : RARRAY_LEN(multipart);

  if (parts_count > 0 && !NIL_P(body)) {
    raise_error(rb_eArgError, "A request cannot have both a body and multipart parts");
  }

  prepared->buffer = 0;
  prepared->request = (ddog_HttpRequest) {.method = method_from_verb(verb)};

  // First pass: validate everything and measure how many bytes of strings we need.
  size_t strings_size = string_length(path);
  strings_size = checked_add(strings_size, optional_string_length(body));

  for (long i = 0; i < headers_count; i++) {
    VALUE pair = rb_ary_entry(headers, i);
    ENFORCE_TYPE(pair, T_ARRAY);
    if (RARRAY_LEN(pair) != 2) raise_error(rb_eArgError, "Each header must be a [name, value] pair");
    strings_size = checked_add(strings_size, string_length(rb_ary_entry(pair, 0)));
    strings_size = checked_add(strings_size, string_length(rb_ary_entry(pair, 1)));
  }

  for (long i = 0; i < parts_count; i++) {
    VALUE part = rb_ary_entry(multipart, i);
    ENFORCE_TYPE(part, T_HASH);
    strings_size = checked_add(strings_size, string_length(hash_get(part, "name")));
    strings_size = checked_add(strings_size, string_length(hash_get(part, "data")));
    strings_size = checked_add(strings_size, optional_string_length(hash_get(part, "filename")));
    strings_size = checked_add(strings_size, optional_string_length(hash_get(part, "content_type")));
  }

  // Layout: [headers][parts][string bytes]. The structs come first so that they are suitably aligned.
  size_t headers_size = (size_t) headers_count * sizeof(ddog_HttpHeader);
  size_t parts_size = (size_t) parts_count * sizeof(ddog_HttpMultipartPart);
  size_t total_size = checked_add(checked_add(headers_size, parts_size), strings_size);

  char *buffer = rb_alloc_tmp_buffer(&prepared->buffer, (long) (total_size > 0 ? total_size : 1));
  ddog_HttpHeader *native_headers = (ddog_HttpHeader *) buffer;
  ddog_HttpMultipartPart *native_parts = (ddog_HttpMultipartPart *) (buffer + headers_size);
  char *cursor = buffer + headers_size + parts_size;
  const char *end = buffer + total_size;

  // Second pass: copy.
  prepared->request.url = copy_text(&cursor, end, path);

  for (long i = 0; i < headers_count; i++) {
    VALUE pair = rb_ary_entry(headers, i);
    native_headers[i] = (ddog_HttpHeader) {
      .name = copy_text(&cursor, end, rb_ary_entry(pair, 0)),
      .value = copy_text(&cursor, end, rb_ary_entry(pair, 1)),
    };
  }
  prepared->request.headers = (ddog_Slice_HttpHeader) {.ptr = native_headers, .len = (uintptr_t) headers_count};

  if (!NIL_P(body)) prepared->request.body = copy_bytes(&cursor, end, body);

  for (long i = 0; i < parts_count; i++) {
    VALUE part = rb_ary_entry(multipart, i);
    native_parts[i] = (ddog_HttpMultipartPart) {
      .name = copy_text(&cursor, end, hash_get(part, "name")),
      .data = copy_bytes(&cursor, end, hash_get(part, "data")),
      .filename = copy_optional_text(&cursor, end, hash_get(part, "filename")),
      .content_type = copy_optional_text(&cursor, end, hash_get(part, "content_type")),
    };
  }
  prepared->request.multipart = (ddog_Slice_HttpMultipartPart) {.ptr = native_parts, .len = (uintptr_t) parts_count};
}

static void release_prepared_request(prepared_request *prepared) {
  rb_free_tmp_buffer(&prepared->buffer);
}

static VALUE headers_array_from_response(const ddog_HttpResponse *response) {
  ddog_Slice_HttpHeader headers = ddog_http_response_headers(response);
  VALUE result = rb_ary_new_capa((long) headers.len);
  for (uintptr_t i = 0; i < headers.len; i++) {
    const ddog_HttpHeader *header = &headers.ptr[i];
    rb_ary_push(result, rb_ary_new_from_args(2,
      rb_utf8_str_new(header->name.ptr, (long) header->name.len),
      rb_utf8_str_new(header->value.ptr, (long) header->value.len)
    ));
  }
  return result;
}

static VALUE response_to_ruby(VALUE response_pointer) {
  const ddog_HttpResponse *response = (const ddog_HttpResponse *) response_pointer;
  ddog_ByteSlice body = ddog_http_response_body(response);
  return rb_ary_new_from_args(4,
    ok_symbol,
    UINT2NUM(ddog_http_response_status(response)),
    headers_array_from_response(response),
    rb_str_new((const char *) body.ptr, (long) body.len) // Binary (ASCII-8BIT)
  );
}

static VALUE drop_response(VALUE response_pointer) {
  ddog_http_response_drop((ddog_HttpResponse *) response_pointer);
  return Qnil;
}

// Note: this function handles dynamically-allocated libdatadog objects, so between their creation and their
// release it MUST NOT call anything that can raise.
static VALUE perform_send(const http_client_t *wrapper, prepared_request *prepared) {
  ddog_HttpCancellationToken *cancel_token = ddog_http_cancel_token_new();
  if (cancel_token == NULL) {
    release_prepared_request(prepared);
    raise_error(rb_eRuntimeError, "Failed to create the cancellation token");
  }

  send_without_gvl_arguments args = {
    .client = wrapper->client,
    .request = &prepared->request,
    .cancel_token = cancel_token,
    .response = NULL,
    .error = NULL,
    .send_ran = false,
  };

  // Release the Global VM Lock while the request is pending. We use rb_thread_call_without_gvl2 because, unlike
  // rb_thread_call_without_gvl, it never raises: we do our own exception checking, and only re-raise
  // (`rb_jump_tag`) once everything was cleaned up.
  //
  // An interrupt may make it return before running our code, so we retry, unless the interrupt was caused by
  // a pending exception (e.g. `Thread#kill`).
  int pending_exception = 0;

  while (!args.send_ran && !pending_exception) {
    rb_thread_call_without_gvl2(send_without_gvl, &args, interrupt_send, cancel_token);

    // To make sure we don't leak memory, we never check for pending exceptions if send ran
    if (!args.send_ran) pending_exception = check_if_pending_exception();
  }

  ddog_http_cancel_token_drop(cancel_token);
  release_prepared_request(prepared);

  if (pending_exception) {
    // Nothing was created by a send that didn't run. This does not return.
    rb_jump_tag(pending_exception);
  }

  if (args.error != NULL) {
    // The message is copied out before the error is freed, so that creating the Ruby objects cannot leak it.
    char buf[MAX_RAISE_MESSAGE_SIZE];
    ddog_HttpClientErrorCode code = copy_error_and_free(args.error, buf, sizeof(buf));
    return rb_ary_new_from_args(3, error_symbol, error_code_symbol(code), rb_utf8_str_new_cstr(buf));
  }

  return rb_ensure(response_to_ruby, (VALUE) args.response, drop_response, (VALUE) args.response);
}

static VALUE _native_send(VALUE self, VALUE request) {
  http_client_t *wrapper = get_open_client(self);

  prepared_request prepared;
  prepare_request(request, &prepared);

  VALUE result = perform_send(wrapper, &prepared);

  RB_GC_GUARD(self);
  return result;
}

// ========================================================================
// Client#_native_close and fork-safety hooks
// ========================================================================

// There must be no send in flight when closing: the Ruby adapter has to serialize them.
static VALUE _native_close(VALUE self) {
  http_client_t *wrapper;
  TypedData_Get_Struct(self, http_client_t, &http_client_typed_data, wrapper);
  http_client_free_resources(wrapper);
  return Qnil;
}

// Fork hooks. They act on the process-wide runtime, and do nothing if no client was ever created.
// The Ruby side must call them once per fork (not once per client), and make sure no send is in flight.
static VALUE _native_before_fork(DDTRACE_UNUSED VALUE _klass) {
  if (shared_runtime == NULL) return Qnil;
  check_shared_runtime_error("Failed to prepare for fork", ddog_shared_runtime_before_fork(shared_runtime));
  return Qnil;
}

static VALUE _native_after_fork_in_parent(DDTRACE_UNUSED VALUE _klass) {
  if (shared_runtime == NULL) return Qnil;
  check_shared_runtime_error("Failed to restore after fork in parent", ddog_shared_runtime_after_fork_parent(shared_runtime));
  return Qnil;
}

static VALUE _native_after_fork_in_child(DDTRACE_UNUSED VALUE _klass) {
  if (shared_runtime == NULL) return Qnil;
  check_shared_runtime_error("Failed to restore after fork in child", ddog_shared_runtime_after_fork_child(shared_runtime));
  return Qnil;
}
void http_client_init(VALUE core_module) {
  ok_symbol = ID2SYM(rb_intern_const("ok"));
  error_symbol = ID2SYM(rb_intern_const("error"));

  VALUE transport_module = rb_define_module_under(core_module, "Transport");
  VALUE http_module = rb_define_module_under(transport_module, "HTTP");
  VALUE adapters_module = rb_define_module_under(http_module, "Adapters");
  // The adapter itself is defined in Ruby (adapters/native.rb); both sides agree on `Object` as its superclass.
  VALUE native_class = rb_define_class_under(adapters_module, "Native", rb_cObject);

  http_client_class = rb_define_class_under(native_class, "Client", rb_cObject);
  rb_global_variable(&http_client_class);
  rb_undef_alloc_func(http_client_class);

  rb_define_singleton_method(http_client_class, "_native_new", _native_new, 1);
  rb_define_method(http_client_class, "_native_send", _native_send, 1);
  rb_define_method(http_client_class, "_native_close", _native_close, 0);
  rb_define_singleton_method(http_client_class, "_native_before_fork", _native_before_fork, 0);
  rb_define_singleton_method(http_client_class, "_native_after_fork_in_parent", _native_after_fork_in_parent, 0);
  rb_define_singleton_method(http_client_class, "_native_after_fork_in_child", _native_after_fork_in_child, 0);
}

#endif // HAVE_DDOG_HTTP_CLIENT_NEW

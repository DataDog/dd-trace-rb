#include "virel_serializer.h"
#include "virel_metadata.h"
#include "allocator.h"
#include "compressed_deltas.h"
#include "../collectors_stack.h"
#include "../datadog_ruby_common.h"
#include "../helpers.h"
#include "../private_vm_api_access.h"
#include "../time_helpers.h"

#include <ruby/encoding.h>
#include <ruby/thread.h>
#include <string.h>
#include <unistd.h>

RUBY_EXTERN unsigned int rb_iseq_line_no(const rb_iseq_t *iseq, size_t pos);

#define VIREL_HEADER_SIZE 76
#define VIREL_OUTPUT_CAPACITY MiB_AS_BYTES(64)
#define VIREL_QUEUE_CAPACITY MiB_AS_BYTES(16)
#define VIREL_STRING_LIMIT 1000
#define VIREL_SNAPSHOT_BATCH 128

typedef struct {
  uint32_t key;
  bool has_previous;
  long cpu_time;
  long timestamp;
} virel_thread_context;

static void *thread_contexts_alloc(size_t size) {
  return size > MiB_AS_BYTES(16) ? NULL : miteruby_allocator_alloc(size, "virel_thread_contexts");
}

#define NAME verstable_virel_threads
#define KEY_TY VALUE
#define VAL_TY virel_thread_context
#define HASH_FN vt_hash_integer
#define CMPR_FN vt_cmpr_integer
#define MALLOC_FN thread_contexts_alloc
#define FREE_FN miteruby_allocator_free_sized
#include "hashtable/verstable.h"

typedef enum { VIREL_EMPTY, VIREL_PREPARING, VIREL_NO_GVL, VIREL_FINISHED } virel_status;

typedef struct {
  uint8_t *output;
  size_t output_size;
  size_t last_snapshot;
  uint8_t *events;
  size_t events_size;
  size_t sample_count;
  size_t stack_count;
  size_t location_count;
  verstable_virel_threads threads;
  uint64_t writer_id;
  pid_t pid;
  long start_ns;
  long finish_ns;
  long finish_ticks;
  virel_status status; // Only changed with the GVL; native storage stays allocated throughout VIREL_NO_GVL.
  miteruby_serializer_exit_reason_t error;
} virel_state;

static void serializer_mark(void *data) {
  virel_state *state = data;
  for (verstable_virel_threads_itr entry = verstable_virel_threads_first(&state->threads);
       !verstable_virel_threads_is_end(entry); entry = verstable_virel_threads_next(entry)) {
    rb_gc_mark(entry.data->key);
  }
}

static void serializer_free(void *data) {
  virel_state *state = data;
  miteruby_allocator_free(&state->output);
  miteruby_allocator_free(&state->events);
  verstable_virel_threads_cleanup(&state->threads);
  ruby_xfree(state);
}

static size_t serializer_size(const void *data) {
  const virel_state *state = data;
  return sizeof(virel_state) + miteruby_allocator_alloc_size(state->output) +
    miteruby_allocator_alloc_size(state->events) +
    miteruby_allocator_alloc_size(state->threads.buckets);
}

static const rb_data_type_t serializer_type = {
  .wrap_struct_name = "Datadog::Profiling::Miteruby::VirelSerializer",
  .function = {.dmark = serializer_mark, .dfree = serializer_free, .dsize = serializer_size},
  .flags = RUBY_TYPED_FREE_IMMEDIATELY,
};

static virel_state *get_state(VALUE serializer) {
  virel_state *state;
  TypedData_Get_Struct(serializer, virel_state, &serializer_type, state);
  return state;
}

static uint64_t new_writer_id(void) {
  VALUE random = rb_funcall(rb_path2class("Random"), rb_intern("new"), 0);
  return NUM2ULL(rb_funcall(random, rb_intern("rand"), 1, ULL2NUM(UINT64_MAX))) + 1;
}

static VALUE serializer_new(VALUE klass) {
  virel_state *state;
  VALUE serializer = TypedData_Make_Struct(klass, virel_state, &serializer_type, state);
  verstable_virel_threads_init(&state->threads);
  state->writer_id = new_writer_id();
  state->pid = getpid();
  return serializer;
}

static void write_bytes(virel_state *state, const void *bytes, size_t length) {
  if (state->error != MITERUBY_SERIALIZER_OK) return;
  if (length > miteruby_allocator_alloc_size(state->output) - state->output_size) {
    state->error = MITERUBY_SERIALIZER_VIREL_BUFFER_FULL;
    return;
  }
  memcpy(state->output + state->output_size, bytes, length);
  state->output_size += length;
}

static void write_varint(virel_state *state, uint64_t value) {
  uint8_t bytes[9];
  size_t count = 0;
  while (value >= 128 && count < 8) {
    bytes[count++] = (uint8_t) value | 128;
    value >>= 7;
  }
  bytes[count++] = (uint8_t) value;
  write_bytes(state, bytes, count);
}

static void write_big_endian(uint8_t *target, uint64_t value) {
  for (size_t i = 0; i < 8; i++) target[7 - i] = (uint8_t) (value >> (8 * i));
}

static size_t begin_event(virel_state *state, uint64_t type) {
  size_t offset = state->output_size;
  const uint8_t size[4] = {0};
  write_bytes(state, size, sizeof(size));
  write_varint(state, type);
  return offset;
}

static void end_event(virel_state *state, size_t offset) {
  if (state->error != MITERUBY_SERIALIZER_OK) return;
  size_t size = state->output_size - offset;
  for (size_t i = 0; i < 4; i++) {
    state->output[offset + i] = (uint8_t) (size & 127) | (i < 3 ? 128 : 0);
    size >>= 7;
  }
}

static size_t begin_snapshot(virel_state *state, uint64_t ticks, bool summary) {
  size_t offset = begin_event(state, 1);
  write_varint(state, ticks);
  write_varint(state, 0);
  write_varint(state, state->last_snapshot ? (uint64_t) state->last_snapshot - offset : 0);
  uint8_t flags = summary ? 128 : 0;
  write_bytes(state, &flags, 1);
  state->last_snapshot = offset;
  return offset;
}

static size_t begin_pool(virel_state *state, uint64_t type, size_t count) {
  size_t offset = begin_snapshot(state, 0, false);
  write_varint(state, 1);
  write_varint(state, type);
  write_varint(state, count);
  return offset;
}

static void write_string(virel_state *state, VALUE string) {
  int encoding = rb_enc_get_index(string);
  if (encoding != rb_utf8_encindex() && encoding != rb_usascii_encindex()) {
    string = rb_str_encode(string, rb_enc_from_encoding(rb_utf8_encoding()), ECONV_INVALID_REPLACE | ECONV_UNDEF_REPLACE, Qnil);
  }
  if (rb_enc_str_coderange(string) == ENC_CODERANGE_BROKEN) {
    VALUE scrubbed = rb_str_scrub(string, Qnil);
    if (!NIL_P(scrubbed)) string = scrubbed;
  }
  size_t length = RSTRING_LEN(string);
  const uint8_t *bytes = (const uint8_t *) RSTRING_PTR(string);
  if (length > VIREL_STRING_LIMIT) {
    length = VIREL_STRING_LIMIT;
    while (length > 0 && (bytes[length] & 0xc0) == 0x80) length--;
  }
  uint8_t tag = 3;
  write_bytes(state, &tag, 1);
  write_varint(state, length);
  write_bytes(state, bytes, length);
  RB_GC_GUARD(string);
}

static VALUE thread_display_name(VALUE thread) {
  VALUE name = thread_name_for(thread);
  if (!NIL_P(name)) return name;
  if (thread == rb_thread_main()) return rb_str_new_cstr("main");
  int line;
  VALUE filename = invoke_location_for(thread, &line);
  if (NIL_P(filename)) return rb_str_new_cstr("(Unnamed thread from native code)");
  const char *path = StringValueCStr(filename);
  const char *suffix = "/lib/logging/diagnostic_context.rb";
  size_t length = strlen(path), suffix_length = strlen(suffix);
  if (length >= suffix_length && strcmp(path + length - suffix_length, suffix) == 0) {
    return rb_str_new_cstr("(Unnamed thread)");
  }
  return rb_sprintf("%"PRIsVALUE":%d", filename, line);
}

void miteruby_virel_serializer_check_available(VALUE serializer) {
  if (get_state(serializer)->status == VIREL_NO_GVL)
    miteruby_serializer_raise_if_failed(MITERUBY_SERIALIZER_ALREADY_WORKING);
}

miteruby_serializer_exit_reason_t miteruby_virel_serializer_prepare_serialize(
  VALUE serializer, uint8_t *interned_events_queue, size_t interned_events_pos,
  const miteruby_mark_frame_array_t *frame_array, const miteruby_location_array_t *location_array,
  const verstable_mark_threads_set *threads_set
) {
  virel_state *state = get_state(serializer);
  if (state->status == VIREL_NO_GVL) return MITERUBY_SERIALIZER_ALREADY_WORKING;
  state->status = VIREL_PREPARING;
  miteruby_allocator_free(&state->events);
  state->events = interned_events_queue;
  state->events_size = interned_events_pos;
  state->sample_count = state->stack_count = state->last_snapshot = state->output_size = 0;
  state->location_count = location_array->count;
  state->error = MITERUBY_SERIALIZER_OK;
  state->finish_ticks = monotonic_wall_time_now_ns();
  if (interned_events_pos > VIREL_QUEUE_CAPACITY) return MITERUBY_SERIALIZER_INVALID_EVENT;
  if (state->output == NULL) state->output = miteruby_allocator_alloc(VIREL_OUTPUT_CAPACITY, "virel_output");
  if (state->output == NULL) return MITERUBY_SERIALIZER_ALLOCATION_FAILED;

  uint8_t header[VIREL_HEADER_SIZE] = {0};
  memcpy(header, "VIRL", 4);
  header[7] = 1;
  header[66] = 128;
  header[67] = 2;
  write_big_endian(header + 24, VIREL_HEADER_SIZE);
  write_big_endian(header + 56, 1000000000);
  write_big_endian(header + 68, state->writer_id);
  write_bytes(state, header, sizeof(header));
  write_bytes(state, virel_metadata, sizeof(virel_metadata));

  for (verstable_virel_threads_itr entry = verstable_virel_threads_first(&state->threads);
       !verstable_virel_threads_is_end(entry);) {
    if (verstable_mark_threads_set_is_end(verstable_mark_threads_set_get(threads_set, entry.data->key)) &&
        !is_thread_alive(entry.data->key)) {
      entry = verstable_virel_threads_erase_itr(&state->threads, entry);
    } else {
      entry.data->val.key = 0;
      entry = verstable_virel_threads_next(entry);
    }
  }
  uint32_t thread_key = 0;
  for (verstable_mark_threads_set_itr entry = verstable_mark_threads_set_first(threads_set);
       !verstable_mark_threads_set_is_end(entry); entry = verstable_mark_threads_set_next(entry)) {
    VALUE thread = entry.data->key;
    verstable_virel_threads_itr context = verstable_virel_threads_get_or_insert(&state->threads, thread, (virel_thread_context) {0});
    if (verstable_virel_threads_is_end(context)) return MITERUBY_SERIALIZER_THREAD_CONTEXTS_FULL;
    context.data->val.key = ++thread_key;
    size_t offset = begin_pool(state, VIREL_THREAD, 1);
    write_varint(state, thread_key);
    write_varint(state, NUM2ULL(rb_obj_id(thread)));
    write_string(state, thread_display_name(thread));
    end_event(state, offset);
  }

  for (size_t first = 0; first < frame_array->count; first += VIREL_SNAPSHOT_BATCH) {
    size_t count = frame_array->count - first;
    if (count > VIREL_SNAPSHOT_BATCH) count = VIREL_SNAPSHOT_BATCH;
    size_t offset = begin_pool(state, VIREL_FUNCTION, count);
    for (size_t i = first; i < first + count; i++) {
      miteruby_frame_t frame = frame_array->entries[i];
      char qualified_name[4096];
      ssize_t length = ddtrace_location_label(frame.cme, frame.iseq, qualified_name, sizeof(qualified_name));
      VALUE name = length > 0 ? rb_utf8_str_new(qualified_name, length) : ddtrace_location_base_label(frame.cme, frame.iseq);
      write_varint(state, i + 1);
      write_string(state, name == Qfalse ? rb_str_new_cstr("") : name);
      write_string(state, frame.iseq ? ddtrace_iseq_path(frame.iseq) : rb_str_new_cstr("(TODO: resolve filename for cfuncs)"));
    }
    end_event(state, offset);
    if (state->error != MITERUBY_SERIALIZER_OK) return state->error;
  }
  for (size_t first = 0; first < location_array->count; first += VIREL_SNAPSHOT_BATCH) {
    size_t count = location_array->count - first;
    if (count > VIREL_SNAPSHOT_BATCH) count = VIREL_SNAPSHOT_BATCH;
    size_t offset = begin_pool(state, VIREL_LOCATION, count);
    for (size_t i = first; i < first + count; i++) {
      miteruby_location_t location = location_array->entries[i];
      if (location.frame_id.value >= frame_array->count) return MITERUBY_SERIALIZER_INVALID_EVENT;
      const rb_iseq_t *iseq = frame_array->entries[location.frame_id.value].iseq;
      write_varint(state, i + 1);
      write_varint(state, location.frame_id.value + 1);
      write_varint(state, iseq && location.bytecode_pos.value != UINT16_MAX ? rb_iseq_line_no(iseq, location.bytecode_pos.value) : 0);
    }
    end_event(state, offset);
    if (state->error != MITERUBY_SERIALIZER_OK) return state->error;
  }
  if (state->error == MITERUBY_SERIALIZER_OK) state->status = VIREL_NO_GVL;
  return state->error;
}

static miteruby_serializer_exit_reason_t emit_stacks(virel_state *state, long *first, long *last) {
  for (size_t pos = 0; pos < state->events_size;) {
    if (state->events_size - pos < sizeof(miteruby_event_deduped_sample_t)) return MITERUBY_SERIALIZER_INVALID_EVENT;
    const miteruby_event_deduped_sample_t *event = (const miteruby_event_deduped_sample_t *) (state->events + pos);
    size_t size = event->header.size_bytes;
    if (size < sizeof(miteruby_event_deduped_sample_t) || size % 8 || size > state->events_size - pos ||
        event->header.timestamp.ns < 0 || event->header.cpu_time.ns < -1 || event->stack_id.offset > pos || event->stack_id.offset % 8)
      return MITERUBY_SERIALIZER_INVALID_EVENT;
    long timestamp = event->header.timestamp.ns;
    if (pos && timestamp < *last) return MITERUBY_SERIALIZER_INVALID_EVENT;
    if (pos == 0) *first = timestamp;
    *last = timestamp;
    const miteruby_event_deduped_sample_t *definition = (const miteruby_event_deduped_sample_t *) (state->events + event->stack_id.offset);
    if (definition->stack_id.offset != event->stack_id.offset || definition->header.frame_count != event->header.frame_count)
      return MITERUBY_SERIALIZER_INVALID_EVENT;
    if (event->stack_id.offset == pos) {
      if (event->stack.frame_count > MAX_FRAMES_LIMIT || event->stack.frame_count != event->header.frame_count ||
          event->stack.ids_size > size - offsetof(miteruby_event_deduped_sample_t, stack.ids))
        return MITERUBY_SERIALIZER_INVALID_COMPRESSED_STACK;
      const uint8_t *cursor = event->stack.ids, *end = cursor + event->stack.ids_size;
      uint20_t previous = {0};
      uint32_t locations[MAX_FRAMES_LIMIT];
      for (uint16_t i = 0; i < event->stack.frame_count; i++) {
        uint20_t location;
        if (!miteruby_compressed_deltas_read(previous, &location, &cursor, end) || location.value >= state->location_count)
          return MITERUBY_SERIALIZER_INVALID_COMPRESSED_STACK;
        locations[event->stack.frame_count - 1 - i] = location.value + 1;
        previous = location;
      }
      if (cursor != end) return MITERUBY_SERIALIZER_INVALID_COMPRESSED_STACK;
      size_t offset = begin_pool(state, VIREL_STACK, 1);
      write_varint(state, pos + 1);
      write_varint(state, event->stack.frame_count);
      for (uint16_t i = 0; i < event->stack.frame_count; i++) write_varint(state, locations[i]);
      end_event(state, offset);
      state->stack_count++;
    }

    state->sample_count++;
    pos += size;
    if (state->error != MITERUBY_SERIALIZER_OK) return state->error;
  }
  return MITERUBY_SERIALIZER_OK;
}

static void *serialize_without_gvl(void *pointer) {
  virel_state *state = pointer;
  state->error = MITERUBY_SERIALIZER_OK;
  long anchor = state->finish_ticks, last = state->finish_ticks;
  state->error = emit_stacks(state, &anchor, &last);
  if (state->error != MITERUBY_SERIALIZER_OK) return NULL;
  if (last < state->finish_ticks) last = state->finish_ticks;
  monotonic_to_system_epoch_state converter = MONOTONIC_TO_SYSTEM_EPOCH_INITIALIZER;
  state->start_ns = monotonic_to_system_epoch_ns(&converter, anchor);
  state->finish_ns = state->start_ns + (last - anchor);
  for (size_t pos = 0; pos < state->events_size;) {
    const miteruby_event_deduped_sample_t *event = (const miteruby_event_deduped_sample_t *) (state->events + pos);
    verstable_virel_threads_itr entry = verstable_virel_threads_get(&state->threads, event->thread.value);
    if (verstable_virel_threads_is_end(entry) || entry.data->val.key == 0) {
      state->error = MITERUBY_SERIALIZER_THREAD_CONTEXT_MISSING;
      return NULL;
    }
    virel_thread_context *context = &entry.data->val;
    long cpu = event->header.cpu_time.ns, timestamp = event->header.timestamp.ns;
    if (!context->has_previous) {
      context->cpu_time = cpu;
      context->timestamp = timestamp;
      context->has_previous = true;
    }
    long cpu_delta = cpu == -1 || context->cpu_time == -1 ? 0 : cpu - context->cpu_time;
    long wall_delta = timestamp - context->timestamp;
    if (cpu != -1) context->cpu_time = cpu;
    context->timestamp = timestamp;

    size_t offset = begin_event(state, VIREL_SAMPLE);
    write_varint(state, timestamp - anchor);
    write_varint(state, pos);
    write_varint(state, context->key);
    write_varint(state, event->stack_id.offset + 1);
    uint8_t truncated = event->header.stack_truncated;
    write_bytes(state, &truncated, 1);
    write_varint(state, (uint64_t) cpu);
    write_varint(state, (uint64_t) cpu_delta);
    write_varint(state, (uint64_t) wall_delta);
    end_event(state, offset);
    if (state->error != MITERUBY_SERIALIZER_OK) return NULL;
    pos += event->header.size_bytes;
  }
  size_t snapshot = begin_snapshot(state, last - anchor, true);
  write_varint(state, 1);
  write_varint(state, state->sample_count ? 1 : 0);
  if (state->sample_count) {
    write_varint(state, VIREL_SAMPLE);
    write_varint(state, state->sample_count);
  }
  write_varint(state, 0);
  end_event(state, snapshot);
  size_t end = begin_event(state, 8);
  end_event(state, end);
  if (state->error != MITERUBY_SERIALIZER_OK) return NULL;
  write_big_endian(state->output + 8, state->output_size);
  write_big_endian(state->output + 16, state->last_snapshot);
  write_big_endian(state->output + 32, state->start_ns);
  write_big_endian(state->output + 40, last - anchor);
  write_big_endian(state->output + 48, anchor);
  return NULL;
}

static VALUE release_gvl(VALUE pointer) {
  rb_thread_call_without_gvl(serialize_without_gvl, (void *) pointer, NULL, NULL);
  return Qnil;
}

static VALUE serialization_ensure(VALUE pointer) {
  virel_state *state = (virel_state *) pointer;
  state->status = state->error == MITERUBY_SERIALIZER_OK ? VIREL_FINISHED : VIREL_EMPTY;
  miteruby_allocator_free(&state->events);
  return Qnil;
}

miteruby_serializer_exit_reason_t miteruby_virel_serializer_serialize_no_gvl(VALUE serializer) {
  virel_state *state = get_state(serializer);
  if (state->status != VIREL_NO_GVL) return MITERUBY_SERIALIZER_NOT_COMPLETED;
  state->error = MITERUBY_SERIALIZER_NOT_COMPLETED;
  rb_ensure(release_gvl, (VALUE) state, serialization_ensure, (VALUE) state);
  RB_GC_GUARD(serializer);
  return state->error;
}

static VALUE native_reset_after_fork(VALUE klass, VALUE serializer);

static VALUE native_prepare(DDTRACE_UNUSED VALUE klass, VALUE serializer) {
  if (!is_current_thread_in_main_ractor_and_holding_the_gvl()) rb_raise(rb_eRuntimeError, "Virel serialization requires the main ractor");
  static const miteruby_serializer_backend_t backend = {
    .check_available = miteruby_virel_serializer_check_available,
    .prepare = miteruby_virel_serializer_prepare_serialize,
    .serialize_no_gvl = miteruby_virel_serializer_serialize_no_gvl,
  };
  if (get_state(serializer)->pid != getpid()) native_reset_after_fork(Qnil, serializer);
  miteruby_consumer_prepare_serialize_with_backend(serializer, &backend);
  return serializer;
}

static VALUE native_stats(DDTRACE_UNUSED VALUE klass, VALUE serializer) {
  virel_state *state = get_state(serializer);
  miteruby_virel_serializer_check_available(serializer);
  VALUE stats = rb_hash_new();
  rb_hash_aset(stats, ID2SYM(rb_intern("samples")), SIZET2NUM(state->sample_count));
  rb_hash_aset(stats, ID2SYM(rb_intern("stacks")), SIZET2NUM(state->stack_count));
  rb_hash_aset(stats, ID2SYM(rb_intern("bytes")), SIZET2NUM(state->output_size));
  return stats;
}

static VALUE native_serialize(DDTRACE_UNUSED VALUE klass, VALUE serializer) {
  virel_state *state = get_state(serializer);
  if (state->pid != getpid()) native_reset_after_fork(Qnil, serializer);
  if (state->status != VIREL_FINISHED) rb_raise(rb_eRuntimeError, "Virel recording must be prepared before serialization");
  VALUE bytes = rb_str_new((const char *) state->output, state->output_size);
  VALUE start = rb_time_nano_new(state->start_ns / SECONDS_AS_NS(1), state->start_ns % SECONDS_AS_NS(1));
  VALUE finish = rb_time_nano_new(state->finish_ns / SECONDS_AS_NS(1), state->finish_ns % SECONDS_AS_NS(1));
  VALUE result = rb_ary_new_from_args(4, start, finish, bytes, native_stats(Qnil, serializer));
  state->status = VIREL_EMPTY;
  RB_GC_GUARD(serializer);
  return result;
}

static VALUE native_reset_after_fork(DDTRACE_UNUSED VALUE klass, VALUE serializer) {
  virel_state *state = get_state(serializer);
  if (state->pid == getpid()) miteruby_virel_serializer_check_available(serializer);
  // A forked child can inherit VIREL_NO_GVL after the encoding thread has disappeared.
  state->status = VIREL_EMPTY;
  verstable_virel_threads_clear(&state->threads);
  miteruby_allocator_free(&state->events);
  state->output_size = state->sample_count = state->stack_count = 0;
  state->writer_id = new_writer_id();
  state->pid = getpid();
  return Qtrue;
}

void miteruby_virel_serializer_init(VALUE profiling_module) {
  VALUE miteruby = rb_define_module_under(profiling_module, "Miteruby");
  VALUE klass = rb_define_class_under(miteruby, "VirelSerializer", rb_cObject);
  rb_define_alloc_func(klass, serializer_new);
  rb_define_singleton_method(klass, "_native_prepare_serialize", native_prepare, 1);
  rb_define_singleton_method(klass, "_native_serialize", native_serialize, 1);
  rb_define_singleton_method(klass, "_native_reset_after_fork", native_reset_after_fork, 1);
  rb_define_singleton_method(klass, "_native_stats", native_stats, 1);
}

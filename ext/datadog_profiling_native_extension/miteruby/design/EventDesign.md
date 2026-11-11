# MITERUBY event design

In-memory format for individual events captured by miteruby.

## Structures

Structs use natural alignment; sizes below assume 64-bit pointers, `long`, `size_t`, and `VALUE`, with 8-byte pointer alignment.

### value_thread_t

```c
typedef struct {
  VALUE value;
} value_thread_t; // 8 bytes
```

- `value`: wrapped Ruby thread `VALUE`, visible to GC marking.

### cpu_time_t

```c
typedef struct {
  long ns;
} cpu_time_t;

#define INVALID_CPU_TIME ((cpu_time_t) {.ns = -1})
```

- 8-byte wrapper for cumulative thread CPU time in nanoseconds from `CLOCK_THREAD_CPUTIME_ID`.
- `INVALID_CPU_TIME` represents an unavailable reading.

### monotonic_time_t

```c
typedef struct {
  long ns;
} monotonic_time_t;
```

- 8-byte wrapper for a monotonic observation timestamp in nanoseconds from `CLOCK_MONOTONIC` on Linux
  or `CLOCK_MONOTONIC_RAW` on macOS, not a Unix-epoch timestamp.

### miteruby_event_type_t

```c
typedef enum __attribute__((packed)) {
  MITERUBY_EVENT_INVALID = 0,
  MITERUBY_EVENT_STACK_SAMPLE = 1,
  MITERUBY_EVENT_DEDUPED_SAMPLE = 3,
} miteruby_event_type_t; // 1 byte
```

- The one-byte size is enforced by a compile-time assertion.

### miteruby_event_header_t

```c
typedef struct {
  uint16_t size_bytes;
  uint16_t frame_count;
  miteruby_event_type_t type;
  uint8_t flags;
  monotonic_time_t timestamp;
  cpu_time_t cpu_time;
} miteruby_event_header_t; // 24 bytes
```

- `size_bytes`: entire record including padding, a multiple of 8, at most 65,528 bytes.
  Advance to the next event by this many bytes.
- `frame_count`: number of captured frames; preserved when the sample is interned.
- `type`: event discriminator; `MITERUBY_EVENT_INVALID` is never emitted.
- `flags`: for stack samples, the low two bits (`MITERUBY_EVENT_STACK_STATUS_MASK`, `0x03`) encode
  stack status: `0` = complete, `1` = truncated, `2` = unavailable; `3` is reserved.
  Bit 2 (`MITERUBY_EVENT_FROM_SIGNAL_HANDLER`, `0x04`) is set for the signal-handler sampling path,
  including simulated signal delivery (TODO: stop doing this for simulate), and clear for the masked publishing entry point.
  Stack status must be read independently of this source bit. Other bits are reserved.
- `timestamp`: monotonic observation time, before stack capture.
- `cpu_time`: cumulative CPU time of the sampled thread at publication, or `INVALID_CPU_TIME` when unavailable.

### miteruby_frame_t

```c
typedef struct {
  const rb_callable_method_entry_t *cme;
  const rb_iseq_t *iseq;
} miteruby_frame_t; // 16 bytes
```

- `cme`: callable method entry, where available; identifies C-method frames.
- `iseq == NULL`: C-method frame. Capture must explicitly clear `iseq` for C frames.

Why store both when `rb_profile_frames` (used by StackProf and Vernier) returns only one? Ruby's
`Thread::Backtrace::Location` also stores both, since Ruby 3.4: the CME supplies the method owner for
class-qualified names, while the executing ISEQ supplies source locations and block identity. For a block
or `eval`, the CME can point to the enclosing method, whose ISEQ differs from the executing one.

`rb_profile_frames` prefers the CME when it describes a Ruby method, losing that distinction: blocks can
look like ordinary method frames, and eval frames can report the enclosing method's filename alongside
the eval's line number. The [upstream commit introducing this representation](https://github.com/ruby/ruby/commit/02d5868962417298cf041ce723d406e16a635693)
explicitly acknowledged the loss of block labels. These limitations remain in Ruby 4.0; storing both
preserves the information needed for accurate locations and qualified block labels on modern Rubies too.

### miteruby_bytecode_pos_t

```c
typedef struct {
  uint16_t value;
} miteruby_bytecode_pos_t; // 2 bytes
```

- `value`: adjusted index into the ISEQ's encoded `VALUE` slots, including operands.
  [`miteruby_bytecode_pos`](../../private_vm_api_access.c) applies bounds checks and the `n > 0 ? n - 1 : 0` adjustment.
  `UINT16_MAX` means no usable position stored: unknown, unreliable, or above 65,534. Check before narrowing;
  never truncate or wrap. Skip line lookup for this sentinel, retaining method/file identity with an unknown line.
  C frames use zero. Resolve usable Ruby positions later with `rb_iseq_line_no(iseq, value)`.

### miteruby_event_stack_sample_t

```c
typedef struct {
  miteruby_event_header_t header;
  value_thread_t thread;
  miteruby_frame_t frames[];
} miteruby_event_stack_sample_t; // 32 bytes + 18 * frame_count bytes + 0–6 padding bytes
```

```text
header | thread | frames[N] | bytecode_positions[N] | padding
  24       8       16*N              2*N              0–6      bytes
```

- `thread`: sampled Ruby thread; `thread.value` is the GC-visible `VALUE`.
- Complete captured stack, inline: `N = header.frame_count` reference pairs followed by `N` positions.
  Matching indices form a frame; no `same_frame` dependency on earlier events.
  C declares only the first array; the bytecode positions begin immediately after its `N` entries.
- Frames are ordered oldest/root first, newest last. For a nonempty,
  untruncated stack, index `N - 1` is the currently active frame.
  Truncation retains the oldest frames and omits the newest ones.
- Producers set `size_bytes = round_up_to_8(32 + 18 * frame_count)`.

### miteruby_event_stack_sample_view_t

```c
typedef struct {
  miteruby_frame_t *frames;
  miteruby_bytecode_pos_t *bytecode_positions;
  uint16_t frame_count;
} miteruby_event_stack_sample_view_t; // 24 bytes; local only
```

- Typed access: `view.frames[i].iseq`, `view.frames[i].cme`, and `view.bytecode_positions[i].value`; require `i < frame_count`.
- During capture, `frames` points to `event->frames`, while `bytecode_positions` points to a separate local array
  of `MITERUBY_MAX_FRAMES` entries. `miteruby_rb_profile_frames` writes both arrays and sets `view.frame_count`.
- After capture, the producer copies the positions immediately after the captured frames, then publishes the event.
  The consumer reads them at byte offset
  `offsetof(miteruby_event_stack_sample_t, frames) + header.frame_count * sizeof(miteruby_frame_t)` from the event.
- The view borrows the producer's local storage and is used only during capture.

### miteruby_event_deduped_sample_t

```c
typedef struct {
  size_t offset;
} miteruby_stack_dedup_id_t;

typedef struct __attribute__((packed)) {
  uint16_t frame_count;
  uint16_t ids_size;
  uint8_t ids[];
} miteruby_stored_stack_t;

typedef struct {
  miteruby_event_header_t header;
  value_thread_t thread;
  miteruby_stack_dedup_id_t stack_id;
  miteruby_stored_stack_t stack;
} miteruby_event_deduped_sample_t;
```

- Consumer-only format, stored in `interned_events_queue`; producers still publish inline stack samples.
- `header.type` is `MITERUBY_EVENT_DEDUPED_SAMPLE`. Frame count, flags, timestamps, CPU time, and thread
  are preserved for each sample.
- A new stack stores its frame count, encoded length, and delta-encoded location IDs inline at the end of the sample.
  (The compressed deltas encoding starts from a previous ID of 0 for each stack).
- A known stack stores its `stack_id` with a zeroed inline stack header and no encoded IDs.
- `header.size_bytes` includes padding to align the next sample to 8 bytes. Known-stack samples occupy 48 bytes;
  new-stack samples occupy `round_up(44 + stack.ids_size, 8)` bytes. Padding is ignored.
- `stack_id.offset` is the byte offset of the first sample containing the stack in `interned_events_queue`.
  0 is a valid ID. Stack lookup, reservation, and commit live in `stack_dedup.c`, which borrows the consumer's queue.
- Stack IDs refer to the queue that owns them. Export preparation clears the consumer's stack map before transferring
  that queue to the serializer; subsequent samples use a fresh queue and map. Reset also clears the map.

## Export ownership and GC lifetime

- Under the GVL and consumer mutex, preparation clears the consumer's write position and lookup sets, allocates a fresh
  queue, and transfers ownership of the previous queue to the serializer. The frame/location arrays and thread set remain
  available while the serializer resolves Ruby metadata and emits the strings and locations that depend on it.
- The preparation ensure handler clears the thread set and array counts and releases the mutex on both success and failure.
  Failed preparation discards the batch; it does not restore it for retry. If ownership was transferred, the serializer
  retains responsibility for freeing the queue, including after an exception.
- On success, the serializer finishes emission and compression without the GVL while the consumer fills its new queue.
  The old queue's thread `VALUE`s and the serializer's thread-context keys are used only as opaque identifiers;
  they may no longer refer to live or pinned Ruby objects and must never be dereferenced.
- The serializer frees the old queue after the no-GVL call returns normally. If an exception bypasses that cleanup,
  the next preparation, fork reset, or serializer destruction frees it.

## Rejected writes

The raw queue reports rejected write attempts out of band through `miteruby_raw_events_queue_record_t.rejected_count`.
These reports carry no timestamp or position among accepted events. The consumer currently ignores them; reporting
sample loss remains unfinished. There is no timestamped overflow event in the event format.

## Caveats / open decisions

- **Event size:** miteruby captures at most `MITERUBY_MAX_FRAMES` (400) frames, giving a maximum raw event size of
  7,232 bytes. This fixed limit is independent of the regular profiler's configurable frame limit.
  The 16-bit `size_bytes` field could represent at most 3,638 raw frames with the current layout.
- **16-bit positions:** we support 65,535 positions (0–65,534). Beyond that, we skip recording the line.
- **Alignment:** event storage must be 8-byte aligned. Record sizes are multiples of 8,
  preserving alignment between consecutive events.
- **JIT:** the top frame's PC can be stale. Preserve the current unknown-line behavior by emitting an unknown
  position and skipping line lookup for it.
- **GC:** raw events remain marked and pinned until their references are retained by the consumer. Export preparation
  ends the consumer's GC protection as described above; the serializer must not access Ruby objects afterward.

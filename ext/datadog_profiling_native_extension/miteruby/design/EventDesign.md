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
  MITERUBY_EVENT_OVERFLOW = 2,
  MITERUBY_EVENT_DEDUPED_SAMPLE = 3,
} miteruby_event_type_t; // 1 byte
```

- Enforce the one-byte size with a compile-time assertion when implementing.

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

- `size_bytes`: entire record including padding, a multiple of 8 from 24 to 65,528 bytes.
  Advance to the next event by this many bytes.
- `frame_count`: number of reference pairs and positions; zero for overflow events.
- `type`: event discriminator; `MITERUBY_EVENT_INVALID` is never emitted.
- `flags`: for stack samples, the low two bits (`MITERUBY_EVENT_STACK_STATUS_MASK`, `0x03`) encode
  stack status: `0` = complete, `1` = truncated, `2` = unavailable; `3` is reserved.
  Bit 2 (`MITERUBY_EVENT_FROM_SIGNAL_HANDLER`, `0x04`) is set for the signal-handler sampling path,
  including simulated signal delivery (TODO: stop doing this for simulate), and clear for the masked publishing entry point.
  Stack status must be read independently of this source bit. Other bits are reserved.
- `timestamp`: monotonic observation time, before stack capture.
- `cpu_time`: cumulative CPU time of the sampled thread at publication, or `INVALID_CPU_TIME` when unavailable.

### miteruby_event_frame_refs_t

```c
typedef struct {
  const rb_callable_method_entry_t *cme;
  const rb_iseq_t *iseq;
} miteruby_event_frame_refs_t; // 16 bytes
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

### miteruby_event_frame_position_t

```c
typedef struct {
  uint16_t value;
} miteruby_event_frame_position_t; // 2 bytes
```

- `value`: adjusted index into the ISEQ's encoded `VALUE` slots, including operands. Use
  [`calc_pos`](private_vm_api_access.c)'s bounds checks and `n > 0 ? n - 1 : 0` adjustment.
  `UINT16_MAX` means no usable position stored: unknown, unreliable, or above 65,534. Check before narrowing;
  never truncate or wrap. Skip line lookup for this sentinel, retaining method/file identity with an unknown line.
  C frames use zero. Resolve usable Ruby positions later with `rb_iseq_line_no(iseq, value)`.

### miteruby_event_stack_sample_t

```c
typedef struct {
  miteruby_event_header_t header;
  value_thread_t thread;
  miteruby_event_frame_refs_t refs[];
} miteruby_event_stack_sample_t; // 32 bytes + 18 * frame_count bytes + 0–6 padding bytes
```

```text
header | thread | refs[N] | positions[N] | padding
  24       8       16*N         2*N         0–6      bytes
```

- `thread`: current Ruby thread; `thread.value` is the GC-visible `VALUE`.
- Complete captured stack, inline: `N = header.frame_count` reference pairs followed by `N` positions.
  Matching indices form a frame; no `same_frame` dependency on earlier events.
  C declares only the first array; use the view below for both.
- Frames are ordered oldest/root first, newest last. For a nonempty,
  untruncated stack, index `N - 1` is the currently active frame.
  Truncation retains the oldest frames and omits the newest ones.
- Require `size_bytes == round_up_to_8(32 + 18 * frame_count)` before accessing the arrays.

### miteruby_event_stack_sample_view_t

```c
typedef struct {
  miteruby_event_frame_refs_t *refs;
  miteruby_event_frame_position_t *positions;
  uint16_t frame_count;
} miteruby_event_stack_sample_view_t; // 24 bytes; local only
```

- Typed access: `view.refs[i].iseq`, `view.refs[i].cme`, and `view.positions[i].value`; require `i < frame_count`.
- One helper constructs the view: `refs` points to `event->refs`; `positions` starts at byte offset
  `offsetof(miteruby_event_stack_sample_t, refs) + frame_count * sizeof(miteruby_event_frame_refs_t)` from the event.
  Producers supply the captured count; readers use `header.frame_count` after validating `size_bytes`.
- Borrows the event storage; invalid after storage is reused. No allocation or extra buffer bytes.

### miteruby_event_deduped_sample_t

```c
typedef struct {
  miteruby_event_header_t header;
  value_thread_t thread;
  size_t stack_id;
} miteruby_event_deduped_sample_t;
```

- Consumer-only format, stored in `consumed_events_buffer`; producers still publish inline stack samples.
- `header.type` is `MITERUBY_EVENT_DEDUPED_SAMPLE` and `header.size_bytes` is 40.
  Frame count, flags, timestamps, CPU time, and thread are preserved for each sample.
- `stack_id` is a byte offset into `unique_stacks_array`, including zero as a valid ID.
  See [ConsumerDesign.md](ConsumerDesign.md) for stack storage, deduplication, and lifetime.

### miteruby_event_overflow_t

```c
typedef struct {
  miteruby_event_header_t header;
} miteruby_event_overflow_t; // 24 bytes
```

- Header-only candidate.
- `frame_count` and `flags`: zero.
- `timestamp`: observation time of the first failed event.

## Caveats / open decisions

- **Event size:** 16-bit `size_bytes` fits at most 3,638 frames. The profiler's current 3,000-frame limit requires
  54,032 bytes and fits.
- **16-bit positions:** we support 65,535 positions (0–65,534). Beyond that, we skip recording the line.
- **Alignment:** event storage must be 8-byte aligned. Record sizes are multiples of 8,
  preserving alignment between consecutive events.
- **JIT:** the top frame's PC can be stale. Preserve the current unknown-line behavior by emitting an unknown
  position and skipping line lookup for it.
- **GC:** the thread, CMEs, and ISEQs referenced by an event must remain alive and pinned while the event is retained.

# MITERUBY consumer design

`unique_stacks_array` stores aligned records:

```c
typedef struct {
  uint16_t frame_count;
  miteruby_event_frame_refs_t refs[];
} miteruby_stack_t;
```

Each record occupies `round_up_to_8(8 + 18 * frame_count)` bytes, with positions immediately after the references.
Empty stacks occupy eight bytes, so the next distinct stack receives a different ID.

- Stack identity is frame count, ordered references, and positions; metadata and padding are excluded.
- A verstable map stores cached hashes and maps stacks to byte-offset IDs in `unique_stacks_array`.
  `get_or_insert` uses a borrowed input pointer and frame count; its hash callback returns the cached hash.
- Only new stacks are copied and their frame references retained. The inserted key switches to an offset,
  preserving hash and equality. Array relocation requires no key updates.
- `consumed_events_mutex` protects the map and array. Serialization resolves IDs under this lock.
  Stacks and pinned references survive serialization and reset together on consumer initialization.

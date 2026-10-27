# MITERUBY consumer design

`unique_stacks_array` stores aligned records with a frame-count header:

```text
[frame count + header padding][CME/ISEQ pairs for all frames][bytecode positions for all frames][alignment padding]
```

Each record occupies `round_up_to_8(8 + 18 * frame_count)` bytes, with positions immediately after the references.
The header contains a two-byte frame count and six bytes of alignment padding. Empty stacks occupy
eight bytes and have their own stack ID.

- Stack identity is frame count, ordered references, and positions; metadata and padding are excluded.
- A verstable set stores keys containing cached hashes and byte-offset IDs in `unique_stacks_array`.
  `get_or_insert` takes a borrowed stack view; references and positions may be in separate arrays.
  Its hash callback returns the cached hash of both arrays.
- Only new stacks are copied and their frame references retained. The inserted key switches to an offset,
  preserving hash and equality. Array relocation requires no key updates.
- `consumed_events_mutex` protects the set and array. Serialization resolves IDs under this lock.
  Stacks and pinned references survive serialization and reset together on consumer initialization.
- `get` takes a stack ID and reads the stored frame count to return a view into the arrays. Views must not be
  modified or retained across insertions or resets, which can relocate or replace the storage.

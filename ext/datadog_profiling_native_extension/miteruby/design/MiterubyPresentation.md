# Miteruby: capture now, process later

**An experimental Ruby profiler pipeline that aims to disturb the application less.**

- Capture raw stacks and timing data quickly.
- Move stack deduplication to a background consumer.
- Defer names, files, and line numbers until export.

Branch snapshot: November 2026, using streaming serialization.

---

## 1. Why change the pipeline?

Profiling costs more than walking a stack: scheduling Ruby work, resolving frames, and recording samples also compete with the application.

- The existing profiler uses postponed jobs to process periodic samples under Ruby's Global VM Lock (GVL).
- It can already capture a stack in the signal handler; processing still waits for the postponed job.
- Miteruby explores avoiding that handoff and repeated GVL acquisition by the consumer, with YJIT disruption as a motivating experiment.

**Goal:** less interference with Ruby execution. Performance gains still need measurement.

---

## 2. Same destination, different division of work

| Stage | Existing profiler | Miteruby prototype |
| --- | --- | --- |
| Capture | Signal handler may prepare a stack; schedules a postponed job | Signal handler publishes raw stack + clocks into a ring |
| Process | Postponed job collects thread samples, resolves frames, records them | Background consumer deduplicates raw stacks without the GVL |
| Prepare export | Samples already recorded in libdatadog | Resolve frames and emit pprof fragments under the GVL |
| Encode | Two profile slots allow libdatadog serialization without the GVL | Finish fragment emission and zstd compression without the GVL; preparation also compresses chunks under the GVL |
| Deliver | Existing exporter and transport | Reuses existing exporter and transport |

**The shift:** less work per sampling interruption, more deferred work and retained state.

---

## 3. Reduced contact surface with Ruby VM APIs

For periodic stack samples, miteruby concentrates VM interaction at capture, GC marking, and export.

| When | Existing profiler | Miteruby prototype |
| --- | --- | --- |
| Signal arrives | Checks VM state, optionally captures frames, triggers Ruby's postponed-job API | Checks VM state and captures raw frames; publishes without scheduling a postponed job |
| Between capture and export | Postponed jobs enumerate threads, inspect their state, resolve frames, and read labels under the GVL | Consumer hashes and copies native data; Ruby pointers are opaque IDs, with no Ruby object access |
| GC runs | Marks references retained in sampling buffers and collector state | Marks and pins references in the ring, thread set, and frame array |
| Export preparation | Frame names and thread labels were resolved during sampling | Reads names, files, lines, and thread labels under the GVL |

**Benefit:** fewer execution contexts need to understand Ruby objects and VM rules.

Names and filenames are resolved once per unique frame, and line numbers once per unique location, within each profile.

**Limit:** private VM access still powers stack capture; this is not yet feature-equivalent to the existing profiler.

---

## 4. Capture enough information to decide later

- Each event carries a thread, monotonic timestamp, cumulative thread CPU time, and raw frames.
- Keep both the executing instruction sequence (ISEQ) and callable method entry (CME): together they preserve block/eval locations and method identity.
- Store compact instruction positions; resolve line numbers later. Unknown positions remain unknown.

**Trade-off:** better frame fidelity costs two Ruby references per frame, plus their GC bookkeeping. Capture currently stops at 600 frames.

CPU time is read at capture, so consumer scheduling delays do not become CPU measurements.

---

## 5. A small producer, a dedicated consumer

```text
SIGPROF → raw event → 1 MiB ring → consumer without GVL
                                      ↓
                         samples with shared, compressed stacks
                                      ↓
                           export: resolve → emit → compress
```

- Go-inspired ring: variable-sized records, atomic publication, borrowed reads.
- Producers use a spinlock; signal masking prevents a handler from interrupting a producer holding it. This is not a lock-free queue.
- Repeated stacks share storage; each sample retains its own timing and thread.

**Trade-off:** fewer copies and batched wakeups, but extra synchronization and delayed consumption. A full ring rejects writes; it never waits for free space.

---

## 6. Stay safe around GC compaction

- **Hold the GVL whenever accessing Ruby objects.** Signal capture also skips GC: even the GVL owner can be interrupted during compaction.
- **Mark and pin objects until export preparation ends**, including during transfer from ring to consumer, so they stay alive and cannot move while Ruby metadata is still needed.
- **Outside the GVL, use Ruby object pointers only as opaque identifiers.** Native hash tables compare and hash them without dereferencing objects or calling Ruby APIs.

Together, these rules prevent compaction crashes from touching Ruby objects at the wrong time, while keeping background deduplication independent of the GVL.

Export preparation transfers the interned queue to the serializer and gives the consumer a fresh queue. Once preparation
finishes or fails, the consumer clears its retained references for that batch and releases its mutex. On success, the serializer then
finishes without the GVL; its remaining thread values are opaque lookup keys and must never be dereferenced.

**Trade-off:** pinning limits compaction until preparation ends. Failed preparation discards that batch rather than retrying it.
Full consumer storage raises an error; graceful recovery is unfinished.

---

## 7. Memory footprint

**Arena-style storage:** a contiguous `mmap` region holds variable-size interned events. Each new stack's delta-encoded
location IDs live inline in its first sample; later samples refer to that sample by byte offset and occupy 48 bytes each.

- No individual `malloc`/`free` per event or stack: these regions avoid malloc heap fragmentation and per-record allocator metadata.
- Each mapping records its requested size; allocation/free counters track outstanding capacity exactly. The interned queue's write offset tracks occupied bytes separately.
- Frame and location arrays hold interned CME/ISEQ pairs and `(frame_id, bytecode_pos)` pairs; sets map those values to array indices.
- Native hash-table backing storage uses the same allocator. Linux mapping names help identify these allocations in process memory tools.

**Trade-off:** reserved headroom, alignment padding, and temporary overlap during replacement still cost memory. Accounting covers requested payload bytes, not RSS, page rounding, or allocator headers; Ruby output strings, the profile wrapper, and pinned Ruby objects are additional costs.

---

## 8. Future memory footprint reduction

**Interned events — 48 bytes for a repeated stack:** encode thread IDs and stack IDs compactly, store timestamp/CPU-time deltas, and omit redundant fixed headers. Blocks with absolute starting values allow bounded decoding; unavailable CPU readings need an explicit marker.

**Stacks — already stored as delta-encoded location IDs:** explore prefix reuse and alternative encodings.

- Encode a shared root prefix against a reference stack, followed by the remaining location IDs.
- Pack small location-ID deltas into nibbles, using an escape for larger values. For example, two small codes can share one byte.

Do compression in the consumer, keeping signal capture simple. Periodic full stacks or independently decodable blocks limit dependency chains.

**Trade-off:** prefix reuse and nibble packing would add decoding work and complicate stack lookup. Measure their net savings
and CPU cost against the existing frame/location interning and ZigZag-varint delta encoding.

---

## 9. Own the encoding too

The serializer emits pprof fragments directly from interned events, frame references, and locations using nanopb.

- Resolve function names, filenames, line numbers, and thread labels under the GVL.
- Release the consumer mutex and GVL before emitting functions, profile metadata, and samples, including per-thread CPU and wall-time deltas.
- Batch emitted bytes in a 256 KiB buffer, feeding bundled zstd when more than 128 KiB is used. Finish compression without the GVL and return the result through the existing profile wrapper.
- Serialization tests check decoded profiles, including timing, labels, GC retention, and truncated stacks.

**Still a prototype:** metadata preparation and its compression flushes hold the GVL; thread timing baselines reset at each export.

---

## 10. What if we wanted to move most of it to rust?

**Proposed split:** a small Ruby-facing adapter around a Rust-owned processing pipeline. Here, “Ruby-facing” includes the C extension that accesses VM internals.

| Keep on the Ruby-facing side | Could live entirely in Rust |
| --- | --- |
| VM/GVL/GC checks, Ruby hooks, and raw stack capture | Ring storage, publication, wakeups, and consumer loop |
| GC callbacks that mark and pin retained Ruby objects | Retained-ID sets, stack deduplication, and sample storage |
| Resolve Ruby frame names, files, lines, and thread labels under the GVL | Time deltas, aggregation, profile tables, encoding, and compression |
| Gem configuration, Ruby exceptions, start/stop/fork hooks, and exporter integration | Native memory limits, accounting, diagnostics, and cleanup |

**Shared across the boundary:** a small C ABI carrying raw events (opaque thread/ISEQ/CME IDs, positions, clocks, flags), copied symbol/label data, and encoded bytes.

- Rust exposes retained IDs for Ruby's marking callback; transfer from ring to retained storage must preserve continuous GC protection. IDs stay valid only while their objects remain pinned and alive.
- At export, Ruby resolves IDs under the GVL and hands over owned data. Rust can then finish the profile without accessing Ruby objects or holding the GVL.
- Publication from the signal handler must remain signal-safe; Ruby exceptions and Rust panics must not unwind across the boundary.

**Trade-off:** a smaller VM-dependent layer, but an explicit ownership and synchronization contract. Moving code to Rust alone does not solve GC safety.

---

## 11. What we have, and what comes next

**Built:** an end-to-end experimental stack-sampling pipeline, GC-safe retention, stack deduplication, bounded core storage, diagnostic stats, and streaming pprof serialization.

**Still a prototype:** signal capture requires the main-ractor GVL owner and skips GC; real thread-state classification, capture-time trace IDs, full allocation/heap/GVL feature parity, and lifecycle/overflow recovery remain work.

**Next:** measure application overhead, YJIT effects, export pauses, memory retention, and sample loss against the existing profiler. The branch includes a side-exit experiment and Fibonacci demo; no speedup is claimed here.

Source notes: [raw events queue design](RawEventsQueueDesign.md), [event format](EventDesign.md), [serializer](../serializer.c), [optimization ideas](OptimizationIdeas.md).

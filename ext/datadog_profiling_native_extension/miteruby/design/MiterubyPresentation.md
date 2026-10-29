# Miteruby: capture now, process later

**An experimental Ruby profiler pipeline that aims to disturb the application less.**

- Capture raw stacks and timing data quickly.
- Move stack deduplication to a background consumer.
- Defer names, files, and line numbers until export.

Branch snapshot: October 2026, including the uncommitted custom serializer experiment.

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
| Prepare export | Samples already recorded in libdatadog | Resolve frames and record buffered samples under the GVL |
| Encode | Two profile slots allow libdatadog serialization without the GVL | Dedicated recorder; current experiment compares two encoders under the GVL |
| Deliver | Existing exporter and transport | Reuses existing exporter and transport |

**The shift:** less work per sampling interruption, more deferred work and retained state.

---

## 3. Reduced contact surface with Ruby VM APIs

For periodic stack samples, miteruby concentrates VM interaction at capture, GC marking, and export.

| When | Existing profiler | Miteruby prototype |
| --- | --- | --- |
| Signal arrives | Checks VM state, optionally captures frames, triggers Ruby's postponed-job API | Checks VM state and captures raw frames; publishes without scheduling a postponed job |
| Between capture and export | Postponed jobs enumerate threads, inspect their state, resolve frames, and read labels under the GVL | Consumer hashes and copies native data; Ruby pointers are opaque IDs, with no Ruby object access |
| GC runs | Marks references retained in sampling buffers and collector state | Marks and pins references in the ring and retained-object set |
| Export preparation | Frame names and thread labels were resolved during sampling | Reads names, files, lines, and thread labels under the GVL |

**Benefit:** fewer execution contexts need to understand Ruby objects and VM rules.

**Limit:** private VM access still powers stack capture. Symbolication is deferred, currently still per sample; this is not yet feature-equivalent to the existing profiler.

---

## 4. Capture enough information to decide later

- Each event carries a thread, monotonic timestamp, cumulative thread CPU time, and raw frames.
- Keep both the executing instruction sequence (ISEQ) and callable method entry (CME): together they preserve block/eval locations and method identity.
- Store compact instruction positions; resolve line numbers later. Unknown positions remain unknown.

**Trade-off:** better frame fidelity costs two Ruby references per frame, plus their GC bookkeeping. Capture currently stops at 400 frames.

CPU time is read at capture, so consumer scheduling delays do not become CPU measurements.

---

## 5. A small producer, a dedicated consumer

```text
SIGPROF → raw event → 1 MiB ring → consumer without GVL
                                      ↓
                              unique stacks + sample IDs
                                      ↓
                           export: resolve → record → encode
```

- Go-inspired ring: variable-sized records, atomic publication, borrowed reads.
- Producers use a spinlock; signal masking prevents a handler from interrupting a producer holding it. This is not a lock-free queue.
- Repeated stacks share storage; each sample retains its own timing and thread.

**Trade-off:** fewer copies and batched wakeups, but extra synchronization and delayed consumption. A full ring rejects writes; it never waits for free space.

---

## 6. Stay safe around GC compaction

- **Hold the GVL whenever accessing Ruby objects.** Signal capture also skips GC: even the GVL owner can be interrupted during compaction.
- **Always mark and pin tracked objects**, including during transfer from ring to consumer, so they stay alive and cannot move.
- **Outside the GVL, use Ruby object pointers only as opaque identifiers.** Native hash tables compare and hash them without dereferencing objects or calling Ruby APIs.

Together, these rules prevent compaction crashes from touching Ruby objects at the wrong time, while keeping background deduplication independent of the GVL.

**Trade-off:** pinning limits compaction, and retained stacks/references currently survive exports until reset. Full consumer storage raises an error; graceful recovery is unfinished.

---

## 7. Memory footprint

**Arena-style storage:** large, contiguous `mmap` regions hold consumed events and unique stacks. Events occupy fixed-size slots; stacks append into a byte array, with offsets as IDs.

- No individual `malloc`/`free` per event or stack: these regions avoid malloc heap fragmentation and per-record allocator metadata.
- Each mapping records its requested size; allocation/free counters track outstanding capacity exactly. Event counts and the stack write offset track occupied bytes separately.
- Native hash-table backing storage uses the same allocator. Linux mapping names help identify these allocations in process memory tools.

**Trade-off:** reserved headroom, alignment padding, and temporary overlap during replacement still cost memory. Accounting covers requested payload bytes, not RSS, page rounding, or allocator headers; libdatadog, custom serialization, and pinned Ruby objects are additional costs.

---

## 8. Future memory footprint reduction

**Consumed events — currently 40 bytes each:** encode thread IDs and stack IDs compactly, store timestamp/CPU-time deltas, and omit redundant fixed headers. Blocks with absolute starting values allow bounded decoding; unavailable CPU readings need an explicit marker.

**Stacks array — currently 18 bytes per frame, plus header/padding:** combine delta compression with nibble packing (4-bit units).

- Intern CME/ISEQ pairs as compact frame IDs; keep the actual pinned pointers in a separate table.
- Encode a shared root prefix against a reference stack, followed by changed frames and position deltas.
- Pack small integer deltas into nibbles, using an escape for larger values and unknown positions. For example, two small codes can share one byte.

Do compression in the consumer, keeping signal capture simple. Periodic full stacks or independently decodable blocks limit dependency chains.

**Trade-off:** extra tables and decoding work, more complex stack lookup, and less direct access. Measure net savings and CPU cost; all of these compression ideas remain unimplemented.

---

## 9. Latest experiment: own the encoding too

The committed branch introduced a direct libdatadog recorder, nanopb, bundled zstd, and a bridge for custom encoded profiles.

**Current working-tree addition:** feed the same samples into libdatadog and custom C tables, then encode both.

- Custom path: pprof tables → nanopb → zstd → existing profile wrapper.
- Equivalence specs compare decoded outputs; Ruby callers still receive libdatadog's result.
- Dual recording, linear searches, full intermediate buffers, and holding the GVL favor an inspectable first implementation over efficiency.

**Decision:** establish output equivalence before optimizing or switching the exported result.

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

**Built:** an end-to-end experimental stack-sampling pipeline, GC-safe retention, stack deduplication, bounded core storage, diagnostic stats, and serializer comparison specs.

**Still a prototype:** signal capture requires the main-ractor GVL owner and skips GC; real thread-state classification, capture-time trace IDs, full allocation/heap/GVL feature parity, and lifecycle/overflow recovery remain work.

**Next:** measure application overhead, YJIT effects, export pauses, memory retention, and sample loss against the existing profiler. The branch includes a side-exit experiment and Fibonacci demo; no speedup is claimed here.

Source notes: [buffer design](BufferDesign.md), [event format](EventDesign.md), [serializer experiment](CustomSerializerPresentation.md), [optimization ideas](OptimizationIdeas.md).

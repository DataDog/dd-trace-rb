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

## 3. Capture enough information to decide later

- Each event carries a thread, monotonic timestamp, cumulative thread CPU time, and raw frames.
- Keep both the executing instruction sequence (ISEQ) and callable method entry (CME): together they preserve block/eval locations and method identity.
- Store compact instruction positions; resolve line numbers later. Unknown positions remain unknown.

**Trade-off:** better frame fidelity costs two Ruby references per frame, plus their GC bookkeeping. Capture currently stops at 400 frames.

CPU time is read at capture, so consumer scheduling delays do not become CPU measurements.

---

## 4. A small producer, a dedicated consumer

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

## 5. Stay safe around GC compaction

- **Hold the GVL whenever accessing Ruby objects.** Signal capture also skips GC: even the GVL owner can be interrupted during compaction.
- **Always mark and pin tracked objects**, including during transfer from ring to consumer, so they stay alive and cannot move.
- **Outside the GVL, use Ruby object pointers only as opaque identifiers.** Native hash tables compare and hash them without dereferencing objects or calling Ruby APIs.

Together, these rules prevent compaction crashes from touching Ruby objects at the wrong time, while keeping background deduplication independent of the GVL.

- Named `mmap` allocations, per-structure limits, and usage counters make core storage inspectable.

**Trade-off:** pinning limits compaction, and retained stacks/references currently survive exports until reset. Full consumer storage raises an error; graceful recovery is unfinished.

Bounds on these structures are not a total profiler memory budget: libdatadog and the custom serializer allocate separately.

---

## 6. Latest experiment: own the encoding too

The committed branch introduced a direct libdatadog recorder, nanopb, bundled zstd, and a bridge for custom encoded profiles.

**Current working-tree addition:** feed the same samples into libdatadog and custom C tables, then encode both.

- Custom path: pprof tables → nanopb → zstd → existing profile wrapper.
- Equivalence specs compare decoded outputs; Ruby callers still receive libdatadog's result.
- Dual recording, linear searches, full intermediate buffers, and holding the GVL favor an inspectable first implementation over efficiency.

**Decision:** establish output equivalence before optimizing or switching the exported result.

---

## 7. What we have, and what comes next

**Built:** an end-to-end experimental stack-sampling pipeline, GC-safe retention, stack deduplication, bounded core storage, diagnostic stats, and serializer comparison specs.

**Still a prototype:** signal capture requires the main-ractor GVL owner and skips GC; real thread-state classification, capture-time trace IDs, full allocation/heap/GVL feature parity, and lifecycle/overflow recovery remain work.

**Next:** measure application overhead, YJIT effects, export pauses, memory retention, and sample loss against the existing profiler. The branch includes a side-exit experiment and Fibonacci demo; no speedup is claimed here.

Source notes: [buffer design](BufferDesign.md), [event format](EventDesign.md), [serializer experiment](CustomSerializerPresentation.md), [optimization ideas](OptimizationIdeas.md).

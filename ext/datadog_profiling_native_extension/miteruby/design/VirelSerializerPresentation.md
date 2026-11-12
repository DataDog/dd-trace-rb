# One miteruby pipeline, two serializers

**Virel serializer — end-of-project presentation**

November 2026 · Prototype implementation and review

The project: export miteruby samples as Virel while preserving the existing capture pipeline and a familiar Ruby API.

The result: a native serializer, local recording tool, and independent format validation. The existing pprof serializer remains the default.

---

## 1. Starting point and assignment

Miteruby already captures individual stack samples, deduplicates stacks in a background consumer, and exports zstd-compressed pprof.

This project adds a second destination for those samples:

- Read the Virel specification and map miteruby's data onto it.
- Implement `virel_serializer.c` with a lifecycle similar to the existing serializer.
- Preserve timing semantics, GC safety, and ownership across export.
- Produce recordings that the independently implemented Virel reader accepts.

**Scope:** an alternative serializer and local export path. Production upload integration is follow-up work.

---

## 2. What stays the same: capture and consumption

```text
Signal capture: raw frames + thread CPU clock
                              |
             Stamp monotonic time under the queue producer lock
                              |
                         1 MiB raw ring
                              |
                   Background consumer, no GVL
                              |
          Interned frames, locations, and shared compressed stacks
                     16 MiB bounded event queue
                              |
                  Select one serializer per drain
                      /                    \
        Existing pprof serializer      New Virel serializer
          zstd + EncodedProfile         VIRL + Recording
```

Both receive the same event representation. Stack capture and consumer deduplication are shared, and neither serializer aggregates samples. A shared producer change moves the monotonic timestamp read under the queue lock; CPU clock reads stay at capture.

**A drain consumes the queue:** this dispatch point does not broadcast each batch to both serializers.

---

## 3. What stays the same: ownership and the GVL

| Phase | Shared contract |
| --- | --- |
| Prepare with the GVL and consumer mutex | Detach the event queue, give the consumer a fresh queue, and resolve Ruby names, files, and lines |
| End preparation | Stop borrowing consumer frame/location arrays and release the mutex |
| Finish without the GVL | Decode native stack data and emit sample records; retained Ruby thread values are opaque, GC-pinned keys |
| Retrieve result | Return a completed recording to Ruby; a prepared result is consumed once |
| Failed export | Release the detached batch and report an error; a later preparation can recover |

The integration adds a small backend interface for availability checks, preparation, and encoding without the GVL. The existing pprof encoding algorithm stays intact.

---

## 4. Similar API, different recording object

| Operation | Existing pprof | Virel |
| --- | --- | --- |
| Prepare and encode | `worker.prepare_serialize` returns its serializer | `serializer.prepare_serialize` returns itself |
| `serialize` | `[start, finish, encoded_profile, {}]` | `[start, finish, recording, stats]` |
| `serialize!` | `EncodedProfile` | `VirelSerializer::Recording` |
| Recording bytes | `EncodedProfile#_native_bytes` | `Recording#bytes`, a frozen binary string |
| Statistics | Empty hash | Sample count, unique stack count, and encoded bytes |
| Lifecycle methods | `reset_after_fork`, `stats` | `reset_after_fork`, `stats` |

```ruby
serializer = Datadog::Profiling::Miteruby::VirelSerializer.new
serializer.prepare_serialize
start, finish, recording, stats = serializer.serialize
File.binwrite("recording.virl", recording.bytes)
```

This example assumes a running miteruby worker. `recording.format` is `:virel`.

The tuple shape is compatible, but the result type is different: the current native upload transport requires `EncodedProfile`.

---

## 5. Main format difference: keep stacks shared on disk

Both backends receive deduplicated stacks from the consumer.

```text
Input: three samples refer to the same stack [location A, location B]

pprof: sample 1 → [A, B]       Virel: stack pool K → [A, B]
       sample 2 → [A, B]              sample 1 → K
       sample 3 → [A, B]              sample 2 → K
                                     sample 3 → K
```

- **pprof:** each sample emits its own location-ID vector. Functions, locations, and strings are still shared through tables.
- **Virel:** decode each unique compressed stack once, emit a pooled stack, and reference its key from samples.
- Stack keys use the defining event's queue offset plus one; zero stays reserved for null.
- Both preserve leaf-first frame order.

**Expected benefit to investigate:** less repeated stack decoding and fewer repeated location references. This alone does not establish a size or speed advantage over compressed pprof.

---

## 6. Same measurements, more explicit sample fields

| Information | Existing pprof output | Virel output |
| --- | --- | --- |
| CPU and wall deltas | Sample values in nanoseconds | `cpuDelta` and `wallDelta` |
| Sample count | Value of one per sample | One sample record implies one observation |
| Cumulative CPU clock | Used internally to derive deltas | Also preserved as `cpuTime`; `-1` means unavailable |
| Thread identity | String labels for Ruby object ID and name | Reference to a pooled thread with numeric Ruby object ID and name |
| Enqueue timestamp | Epoch nanoseconds in `end_timestamp_ns` label | Chunk-relative `startTime` plus header clock anchors |
| Truncated stack | Replaces the first location with a synthetic “Truncated Frames” location | Explicit `truncated` flag; retains all captured locations |
| Unavailable stack | Synthetic “In native code” location | Empty pooled stack |
| Extra pprof fields | State/miteruby labels; zero allocation and timeline placeholders | No equivalents emitted in this schema |

Thread identity remains a Ruby object ID, not an operating-system thread ID. Both inherit the same frame-resolution limitations.

---

## 7. Timing rules that must not change

**Both serializers retain per-thread timing baselines across exports when the same serializer instance is reused.**

- A thread's first observation contributes zero CPU and wall delta.
- An unavailable CPU clock contributes zero CPU delta and preserves the last valid CPU baseline.
- Wall delta uses successive observations of that thread in original queue order.
- Reset clears the timing history. An empty export does not.

The baselines belong to each serializer instance. Switching backends does not transfer timing history between them.

This separates two concepts: every output is independently decodable, while a sample's delta may depend on an observation from an earlier export.

---

## 8. Simplification: guarantee order at publication

The targeted Virel specification and reader require nondecreasing unsigned timestamp offsets.

**Solution:** `miteruby_raw_events_queue_try_write` accepts an optional pointer to the caller's timestamp field. After checking capacity, it reads the monotonic clock under the producer lock, stores the result, copies the payload, and publishes it before unlocking.

- The queue knows where to store the timestamp, without knowing the event layout.
- Both serializers receive timestamps in queue order; ties are valid.
- Virel uses two linear passes: stack definitions and validation, then sample emission.
- No sorting or per-sample descriptor buffer is needed. A decreasing timestamp is an invariant violation and rejects the batch.

**Trade-off:** the timestamp now measures enqueue time after stack capture and any lock wait. Stack walking and CPU clock reads remain outside the lock. Both serializers use this revised wall-clock meaning.

---

## 9. What a complete Virel chunk contains

```text
76-byte finalized VIRL header
  → complete XML-v2 metadata
  → thread, function, and location pool snapshots
  → stack pool snapshots
  → samples in queue order
  → cumulative sample-count summary snapshot
  → END_OF_PARTITION
```

- Targets draft 0.1, dated 2026-10-05, and the maintained reference reader.
- Writes native **VIRL**, without a **VIRC** wrapper or compression.
- Each drain includes complete metadata and local pools; chunks can be decoded separately or concatenated.
- Snapshots link backward; the header identifies the final snapshot.
- A generator owns the schema and dynamic type IDs and produces the checked-in C metadata header.

One low-level trap: Virel's integer encoding uses at most nine bytes, with eight payload bits in the ninth byte. Protobuf varint helpers are not interchangeable with it.

---

## 10. Export boundaries and strings also differ

| Detail | Existing pprof | Virel |
| --- | --- | --- |
| Returned start/end | Contiguous export windows, advancing start when the prior result is retrieved | Observed batch window: earliest sample to at least preparation finish; empty batch uses preparation time |
| Timestamp representation | Epoch sample labels | Monotonic relative offsets with epoch/monotonic anchors |
| Names and filenames | String table; capped at 1000 bytes | Inline UTF-8 strings in pooled records; capped at 1000 bytes without splitting characters |
| String encoding | Existing byte-oriented output | Reuse UTF-8/US-ASCII; transcode other encodings and scrub malformed strings |

Virel's chunk range is not a promise that consecutive chunks cover contiguous time windows. Its per-thread delta baselines still persist across those boundaries.

The changes to string handling protect the format's UTF-8 contract; they do not improve the underlying Ruby frame-name or C-function filename resolution.

---

## 11. Resource trade-offs, without a performance claim

| Resource or work | Existing pprof | Virel |
| --- | --- | --- |
| Output | zstd level 1; up to 10 MiB compressed | Up to 64 MiB uncompressed |
| Intermediate storage | 256 KiB staging buffer plus zstd workspace | No per-sample scratch buffer |
| Stack expansion | Once per sample | Once per unique stack |
| Ordering | Queue traversal | Two linear queue traversals; reject decreasing timestamps |
| Work under GVL | Strings/locations and some compression | Metadata and thread/function/location records |
| Result handoff | Copy used bytes to Ruby; replace compressed buffer | Copy used bytes to Ruby; reuse native output allocation |

Both have a bounded detached event queue and a bounded thread-context map. Consumer capture can continue into a fresh queue during encoding.

These are allocation limits, not measured resident memory. Comparing a compressed 10 MiB limit with an uncompressed 64 MiB limit does not compare efficiency. GVL duration, peak memory, throughput, and compressed size still need measurement.

---

## 12. Lifecycle and failure handling

**Shared responsibilities:** retain Ruby references safely, reject invalid lifecycle operations, release detached batches, and allow subsequent exports after failure.

Virel additionally:

- Restricts preparation to the main Ractor and rejects concurrent use/reset while encoding.
- Detects PID changes on preparation and result retrieval, clearing inherited serialization state.
- Gives each instance a nonzero writer ID and renews it on reset or fork.
- Reports malformed events, invalid stack data, allocation failures, and output exhaustion.

The worker still owns resetting the capture/consumer pipeline after fork. Serializer reset alone does not reset the whole profiler.

An export failure discards that batch; this prototype does not provide a retry spool or automatic loss reporting.

---

## 13. Demo: capture Ruby, read with Virel

From the dd-trace-rb repository root, after building the extension:

```sh
bundle exec ruby -Ilib tools/virel/record.rb /tmp/workload.virl /path/to/workload.rb
python3 -B /home/bits/upstream/virel/validators/tcf_reader.py /tmp/workload.virl
```

The command starts a standalone miteruby worker, runs the workload, stops sampling, drains the remaining raw events, and writes a finalized chunk. The workload should not start another profiler.

Recorded smoke-test result:

- 40 sample records in a 3,187-byte recording.
- One metadata record, 16 snapshots, and one end marker.
- The reference reader parsed the entire recording with no foreign spans.

This demonstrates interoperability on a real workload; it is not a size or throughput benchmark. Long recordings need periodic drains to avoid the existing bounded queues filling.

---

## 14. Evidence: correctness at several boundaries

| Check | Result and scope |
| --- | --- |
| Native serializer harness | Passed on Ruby 2.5 and 4.0: varints, pooling, timestamp ties/regression rejection, delta baselines, malformed inputs, allocation/output failures, GC, concurrency, and fork reset |
| Queue timestamp tests | Deterministic clock checks for lock ownership, payload aliasing, rejection, wraparound, signal delivery, and concurrent producer order |
| Independent Virel reader | Six standalone chunks and their concatenation passed; checks include measurements, leaf-first stacks, snapshot links, and summary counts |
| Ruby API specs | Five examples passed on Ruby 2.5 and 4.0, including captured Ruby frames, result consumption, reset, and switching back to pprof |
| Worker and serializer regression specs | 151 examples on each version, zero failures; 16 pending on Ruby 2.5 and six pending on Ruby 4.0 |
| ASan/UBSan | Native harness passed; coverage applies to instrumented serializer/harness code, not the whole Ruby runtime |
| Static checks | Full Steep passed; RuboCop passed for touched Ruby files; generated metadata reproduced byte for byte |

An independent reader matters: it catches format misunderstandings that a writer and a matching home-grown decoder could share.

---

## 15. Deliverables and review map

| Area | Files to start with |
| --- | --- |
| Native writer | [virel_serializer.c](../virel_serializer.c), [virel_serializer.h](../virel_serializer.h) |
| Timestamp publication | [raw_events_queue.c](../raw_events_queue.c), [sample_event.c](../sample_event.c) |
| Shared dispatch | [consumer.c](../consumer.c), [serializer.h](../serializer.h) |
| Existing implementation for comparison | [serializer.c](../serializer.c) |
| Ruby API and types | [virel_serializer.rb](../../../../lib/datadog/profiling/miteruby/virel_serializer.rb), [virel_serializer.rbs](../../../../sig/datadog/profiling/miteruby/virel_serializer.rbs) |
| Schema and demo | [generate_metadata.py](../../../../tools/virel/generate_metadata.py), [record.rb](../../../../tools/virel/record.rb) |
| Validation | [native harness](../../../../spec/datadog/profiling/miteruby_virel_serializer_test.c), [reader assertions](../../../../spec/datadog/profiling/validate_virel.py), [Ruby specs](../../../../spec/datadog/profiling/miteruby/virel_serializer_spec.rb) |
| Usage and contract | [VirelSerializer.md](VirelSerializer.md) |

Suggested review order: shared ownership boundary → timing/order semantics → wire encoding → Ruby result API → failure tests.

---

## 16. What I would carry into the next iteration

**Lessons from this implementation**

- Reusing the consumer boundary kept the new format out of the sampling path.
- Establishing timestamp order at publication removes sorting and scratch memory from every Virel export; the cost is a documented shift to enqueue time.
- Format details such as varints, UTF-8 boundaries, and pool references deserve independent validation.
- A usable demo needs a complete lifecycle, including draining the tail after sampling stops.

**Next experiments**

1. Replay identical captured batches through both serializers; measure GVL time, total encoding time, peak memory, and output size.
2. Evaluate Virel compression and VIRC wrapping against concrete reader and transport requirements.
3. Measure timestamp displacement from stack capture under contention, alongside the cost of reading the clock inside the lock.
4. Design an exporter/transport contract for `Recording` and tune memory limits using measurements.

**Delivered:** a reviewable alternative serializer with shared capture and timing semantics, explicit Virel records, and verified local interoperability.

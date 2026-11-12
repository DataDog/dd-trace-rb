# Virel serializer prototype

`Miteruby::VirelSerializer` encodes the consumer's interned samples as a
self-contained, uncompressed VIRL 0.1 chunk. The default profiler still uses
the pprof serializer. This is a local recording experiment; the existing
Datadog upload transport requires a libdatadog EncodedProfile.

## Try it

From the repository root, build the extension and record a Ruby workload:

```sh
bundle exec rake clean compile
bundle exec ruby -Ilib tools/virel/record.rb /tmp/workload.virl /path/to/workload.rb
python3 -B /path/to/virel/validators/tcf_reader.py /tmp/workload.virl
```

The workload runs under a standalone miteruby worker, without starting the
normal exporter. Do not start another profiler from the workload. The command
stops sampling and drains the raw queue before its final export, using the
prototype's native testing helpers. Long workloads can
exhaust the existing consumer's bounded buffers; use periodic serialization
when collecting longer recordings.

Given a running miteruby worker, the equivalent API is:

```ruby
serializer = Datadog::Profiling::Miteruby::VirelSerializer.new
serializer.prepare_serialize
start, finish, recording, stats = serializer.serialize
File.binwrite("recording.virl", recording.bytes)
```

`serialize!` returns the recording alone. Its bytes are frozen and its
`format` is `:virel`. Each preparation drains the shared consumer, so use a
single exporter for a recording session. Reuse the serializer across drains
to preserve CPU/wall baselines. Preparation snapshots samples already
processed by the consumer; pending raw samples belong to a later drain.
Concatenate the returned byte strings to
build a multi-chunk VIRL file. Every chunk includes complete metadata and
its own pools, and can also be decoded independently.

The serializer resets its writer identity and timing baselines when it
detects a fork on preparation or result retrieval. `reset_after_fork` also
provides an explicit reset. The worker remains responsible for resetting
the capture/consumer pipeline after fork.

## Wire contract

This implementation targets `doc/TraceContainerFormat.md` in the Virel
checkout, draft 0.1 dated 2026-10-05, and its maintained reference reader.
It uses finalized native chunks, XML-v2 metadata with an explicit envelope,
and dynamic type IDs starting at 2^30. The schema and IDs are defined in
`tools/virel/generate_metadata.py`; regenerate the checked-in header with:

```sh
python3 -B tools/virel/generate_metadata.py
```

Each sample contains:

| Field | Meaning |
|---|---|
| startTime | Enqueue time in unsigned nanoseconds since the chunk's monotonic anchor |
| sequence | Byte offset in the drained event queue; identifies append order within the chunk |
| thread | Reference to Ruby object ID and display name |
| stack | Reference to leaf-first location keys; an empty stack means unavailable |
| truncated | Capture reached the frame limit |
| cpuTime | Cumulative thread CPU nanoseconds, or -1 when unavailable |
| cpuDelta | CPU nanoseconds computed with the existing pprof baseline rules |
| wallDelta | Elapsed monotonic nanoseconds computed in original queue order |

Functions contain names and filenames; locations contain function references
and line numbers. UTF-8 and US-ASCII strings bypass transcoding; other encodings
are converted to UTF-8. Only malformed strings need scrubbing. Output is capped
at 1000 bytes without splitting a UTF-8 character. The existing limitations in
C-function filenames and frame-name resolution also apply here.

Stacks use the defining event's offset plus one as their pool key; zero
remains null. Definitions are emitted once per unique stack, and samples
reference them without copying their frame arrays. Pool snapshots link
backward. The last snapshot summarizes emitted sample counts and precedes
the fieldless END_OF_PARTITION record.

The current normative timestamp rule requires nondecreasing offsets. The
raw queue fills an optional caller-provided timestamp destination under its
producer lock before copying and publishing the event. Stack walking and CPU
clock reads remain outside the lock. Both serializers therefore receive
monotonic enqueue timestamps in queue order, including time spent capturing
the stack and waiting for the lock.

Virel traverses that order directly, rejecting decreasing timestamps as an
invalid event. It emits stack definitions and validates events in one pass,
then computes deltas and emits samples in a second pass, without sorting or
per-sample scratch allocation. Equal timestamps retain queue order. Snapshot
and metadata timestamps precede the sample timestamps; the final snapshot
uses the chunk's end time.

## Ownership and limits

Preparation holds the GVL and consumer mutex while resolving names and line
numbers. It takes ownership of the detached event queue before any fallible
work. Stack decoding and sample emission run without the GVL.
Ruby pointers used during that phase are opaque thread-map keys, pinned by
the serializer's mark callback. Consumer frame/location arrays are never
borrowed beyond preparation.

Output is capped at 64 MiB, the detached queue at 16 MiB, and thread-map
storage at 16 MiB. The output allocation is reused, while the detached queue
is freed on completion or interruption. Ruby receives a copy of the used output bytes. Exhaustion
raises and discards the affected recording; subsequent preparations can
proceed. These are prototype memory limits, not upload limits.

Compression, VIRC wrapping, upload support, and the signed-offset dialect
are separate follow-up work.

## Verification

```sh
bundle exec rake 'test:miteruby_virel[/path/to/virel]'
bundle exec rspec spec/datadog/profiling/miteruby/virel_serializer_spec.rb
```

The native task checks the nine-byte varint boundary, pool references,
timestamp ties and regression rejection, cross-chunk baselines, missing CPU clocks, malformed
events, buffer/allocation failures, GC during encoding, concurrent access and
fork reset. With a Virel checkout argument, its independently implemented
reader checks the resulting chunks, stack direction, measurements, summary
counts, and concatenation. No Virel checkout is needed for the native tests.
The Ruby specs exercise real captured frames and the shared consumer boundary,
including switching back to pprof after a Virel drain.

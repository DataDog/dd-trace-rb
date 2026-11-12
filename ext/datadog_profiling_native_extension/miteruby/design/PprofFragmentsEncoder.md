# Building a memory-efficient streaming pprof encoder

A basic exporter constructs one complete pprof `Profile`, encodes it into a
large byte buffer, and compresses that buffer. The design in this guide instead
constructs small generated messages containing individual profile entries,
encodes them consecutively into one compression stream, and releases each entry
afterward. The result is an ordinary pprof that existing readers can decode.

**Encoding one large Profile is equivalent to concatenating encodings of
appropriately declared fragments of that same Profile.** The fragment fields
retain their original protobuf field numbers and types. The protobuf library
handles the encoding details.

The guide is language-independent. You need a protobuf compiler/runtime, the
standard pprof schema, and a streaming compression API.

@ivoanjo: I worked with AI friend to generate this document based on our
prior work in the https://github.com/datadog/libdatadog/ profile exporter that
does a similar thing in spirit.

## 1. What changes from the basic exporter

A basic implementation usually has three separate materialization steps:

```text
export(collection):
    profile = build_complete_generated_Profile(collection)
    uncompressed = protobuf_encode(profile)
    return compress(uncompressed)
```

The collection may already be compact. For example, many observations can share
one stored stack trace or label set. The pprof representation shares individual locations and
strings, but every sample still has its own sequence of location IDs and labels.
For `N` observations sharing a stack of depth `D`, materializing all generated
samples expands that stack into `N × D` location IDs.
(Or in less robotic AI terms: if the same stack shows up with different labels,
it needs to be repeated in the pprof output. This is one thing that other formats,
notably the OpenTelemetry profiles format, improve on.)
The uncompressed output buffer adds another large allocation.

Use this pipeline instead:

```text
compact collection
    -> one generated Sample, Location, Function, etc.
    -> small generated wrapper with the matching Profile field number
    -> existing protobuf encoder
    -> reusable encoding buffer
    -> one streaming compressor
    -> compressed output sink
```

The temporary buffer can hold one fragment or batch several small fragments
before passing them to the compressor. The compressor sees the concatenation
of all fragments. No complete generated `Profile` or complete
uncompressed profile buffer is required to ever exist in memory. The generated encoder still handles
nested messages, lengths, integer encodings, and repeated fields.

| Basic exporter                                   | Streaming exporter                                             |
| ------------------------------------------------ | -------------------------------------------------------------- |
| Construct all generated samples before encoding. | Construct, encode, and release one generated sample at a time. |
| Build a complete uncompressed output buffer.     | Reuse an encoding buffer as fragments are produced.            |
| Compress after encoding the entire profile.      | Feed fragments into the same compression stream.               |
| Retain all source data until export finishes.    | Release source data when its last consumer has finished.       |

The memory improvement comes from avoiding simultaneous expansion. Generated
objects may still need temporary buffers or to copy strings, but only the currently
processed entry needs to be expanded.

## 2. Why splitting a Profile works

A raw protobuf message is a sequence of fields. It has no outer message-length
prefix and no closing marker. Every encoded field identifies its field number
and carries the information needed to decode its value. Message and field names
are not part of the serialized representation.

Consequently, these have exactly the same decoded contents (and, with the same
encoder, nested message definitions, and field order, the same serialized bits):

```text
encode(Profile {
    sample: [A, B],
    string_table: ["", "cpu"]
})

encode(FragmentSample { sample: A })
  || encode(FragmentSample { sample: B })
  || encode(FragmentStringTable { string_table: [""] })
  || encode(FragmentStringTable { string_table: ["cpu"] })
```

Here `FragmentSample.sample` has field number **2**, matching `Profile.sample`, and
`FragmentStringTable.string_table` has field number **6**, matching `Profile.string_table`.
Their payload types also match. `||` means concatenate the ordinary protobuf
serialization of those helper messages. The decoder sees sample entries and
string-table entries belonging to a single `Profile`.

The helpers are essential: serializing a bare `Sample` would leave out the
surrounding `Profile.sample` field. Asking the existing encoder to serialize a
`FragmentSample` supplies that surrounding field automatically.

Use ordinary **raw message serialization**, not a "delimited message" API that
prepends a whole-message length before each fragment. Nested message framing is
still needed and is handled by the generated encoder.

Different profile fields can appear out of numerical order. Samples can precede
sample types, locations, and strings; the reader resolves references after
parsing. Preserve the order of repeated entries wherever it carries meaning,
and emit each singular metadata field only once. These properties follow from
the [protobuf wire format](https://protobuf.dev/programming-guides/encoding/).

This splits **one logical profile**. It is not a way to merge independently
constructed profiles with separate IDs and string tables. Every fragment must
use the same profile-wide namespaces and string indices.

## 3. Generate small companion messages

Add a companion schema containing only the fields your exporter needs.
(The example below omits a few fields that aren't used by the Ruby profiler.)
Its nested types make it self-contained; it does not need to import the full pprof schema.
The package and message names do not affect wire compatibility.

```proto
syntax = "proto3";
package miteruby_pprof;

message FragmentSampleType {
  message ValueType {
    int64 type = 1;
    int64 unit = 2;
  }
  ValueType sample_type = 1;
}
message FragmentSample {
  message Sample {
    message Label {
      int64 key = 1;
      int64 str = 2;
      int64 num = 3;
    }
    repeated uint64 location_id = 1 [packed = true];
    repeated int64 value = 2 [packed = true];
    repeated Label label = 3;
  }
  Sample sample = 2;
}
message FragmentLocation {
  message Location {
    message Line {
      uint64 function_id = 1;
      int64 line = 2;
    }
    uint64 id = 1;
    Line line = 4;
  }
  Location location = 4;
}
message FragmentFunction {
  message Function {
    uint64 id = 1;
    int64 name = 2;
    int64 filename = 4;
  }
  Function function = 5;
}
message FragmentStringTable {
  repeated string string_table = 6;
}
message FragmentProfile {
  int64 time_nanos = 9;
  int64 duration_nanos = 10;
}
```

Compile this file with the same protobuf toolchain as the standard schema.
These helpers are internal to the producer: the receiver still uses the normal
`Profile` declaration. Keep their field numbers and payload types in sync with
that declaration. For additional metadata, copy the original field number,
type, and appropriate presence/repetition behavior into a helper.

The singular message field in each entry fragment represents one occurrence of
a repeated `Profile` field. Proto3 message fields have presence: populate that
field before encoding the fragment. Its encoding is the same as one element of
the original repeated message field, without needing a one-element list in the
wrapper. The repeated numeric fields inside `Sample` use proto3's default packed
encoding; the schema spells it out explicitly.

This subset represents one `Line` per `Location`. If your exporter supports
multiple inline frames, use `repeated Line line = 4` and preserve their order.
Likewise, add mappings, label units, period information, or other fields your
exporter needs using the original schema's field numbers and types. Omitting
fields is appropriate only when the exporter does not need to emit them.

### Preserve the empty first string

**Emit `FragmentStringTable { string_table: [""] }` for string-table index zero.** Its
empty value must be present in the serialized output. It must be the first
*string-table entry*; other kinds of profile fields can be serialized before it.

A plain proto3 scalar string with implicit presence is unsuitable for this
helper: an encoder normally omits its default empty value. This would silently
remove index zero and shift every other string reference.

The repeated string field preserves every element, including `""`. A fragment
can contain one string or several consecutive strings; either way, preserve
their index order. Verify the empty entry in serialized output rather than
relying on the in-memory value alone.

### An alternative without companion declarations

You can also reuse the existing generated `Profile` with just one repeated
entry populated. For example, serialize `Profile { sample: [A] }`, clear it,
then serialize `Profile { sample: [B] }`. A one-element `string_table` containing
`""` preserves the empty entry naturally.

Both approaches reuse the existing encoder. Companion declarations make each
fragment's purpose explicit and prevent unrelated fields from being populated.
When reusing `Profile`, clear every previously populated field before the next
fragment, especially metadata that must not be emitted repeatedly. Ensure the
runtime does not retain previously added entries or grow an arena across the
whole export. Never accumulate the entire profile in the helper.

## 4. Stream generated fragments and consume their inputs

The central operation is small:

```text
emit_fragment(fragment):
    scratch.clear()                       # reset length; reuse capacity
    protobuf_encode_raw(fragment, scratch)
    compressor.write_all(scratch)
```

`protobuf_encode_raw` is your existing encoder's ordinary message serialization
API. If it returns a fresh byte array instead of writing into a reusable buffer,
forward that array and release it before processing the next entry. That still
avoids a whole-profile allocation. If it accepts a stream directly, a buffered
compression input can replace the scratch buffer.

The simple helper above forwards each fragment immediately. To batch small
fragments, append their encodings to a bounded buffer and flush it to the same
compressor when full. Buffer boundaries do not need to coincide with fragment
boundaries. Release or reuse the generated message once its encoding has been
copied into the buffer; it need not stay alive until compression finishes.

For a completed collection interval, one possible export procedure is below.
This example assumes the collection supports releasing individual entries.
Streaming also works when source storage is released in chunks or retained
until the interval finishes; avoiding the complete generated `Profile` and
uncompressed buffer does not depend on incremental source reclamation.

```text
export_owned(collection, sink):
    compressor = none
    scratch = none
    output_complete = false
    try:
        validate_profile_configuration(collection)
        compressor = start_streaming_compression(sink)
        scratch = new_reusable_buffer()

        for observation taken from collection:
            sample = build_generated_Sample(observation, collection.tables)
            emit_fragment(FragmentSample(sample=sample))
            release_or_reuse(sample)
            release(observation)

        for type in collection.sample_types:
            emit_fragment(FragmentSampleType(sample_type=build_generated_ValueType(type)))

        metadata = FragmentProfile(
            time_nanos=collection.start_time_ns,
            duration_nanos=collection.duration_ns)

        for location taken from collection.locations:
            emit_fragment(FragmentLocation(location=build_generated_Location(location)))
            release(location)
        for function taken from collection.functions:
            emit_fragment(FragmentFunction(function=build_generated_Function(function)))
            release(function)

        for string in collection.strings_in_index_order:
            emit_fragment(FragmentStringTable(string_table=[string]))
        release(collection.string_storage)

        emit_fragment(metadata)
        flush_any_buffered_compression_input()
        compressor.finish_frame()
        finish_output_sink(sink)
        result = completed_output(sink)
        output_complete = true
        return result
    finally:
        if not output_complete:
            abort_partial_output(sink)
        dispose_initialized_compression_and_buffer_resources()
        release_remaining_source_and_temporary_storage()
```

Here `emit_fragment` uses the current export's `scratch` and `compressor`.
Every serialization, write, and finalization operation can fail. Ownership and
cleanup must cover validation and initialization failures as well as failures
inside the loops. Disposal must not publish failed output, free a returned
buffer, double-free released entries, or mask the original error. Use scoped
resource management where available. The pseudocode's builders create only one
entry at a time and preserve the basic encoder's conversion behavior.

Keep the generated message stable until encoding finishes. Generated encoders
may calculate a message's size before writing it; concurrent mutation can
invalidate that calculation. If collection continues, rotate to a new interval
or otherwise provide a stable snapshot and keep shared dictionaries alive.

### Choose release order from dependencies

The traversal above works when later records already retain stable wire IDs.
If location conversion still needs function lookup or ID translation, retain
that lookup table until locations have been encoded. Apply the same rule to
string lookups and to mappings if your exporter includes them. The
wire order is flexible; the producer's remaining lookups determine when a table
can be released.

Assign stable indices to strings before encoding references to them, and emit
strings in index order. The traversal above finishes interning strings before
draining the string table. If you add metadata containing string references,
register those strings before draining the table too. A different traversal
can emit strings incrementally, provided indices stay stable and every
referenced string is emitted before the profile is complete. Nothing may
require a string value after its storage has been released.

Retain enrichment and sampling adjustments from the basic encoder. pprof has
no dedicated per-sample timestamp field; a numeric label agreed with the
consumer can carry timestamps. Do not aggregate observations that the existing
encoder kept separate. An expanded-label cache can save repeated work, but it
adds live memory; isolate per-sample labels from shared cached labels.

Releasing entries does not guarantee immediate reduction in resident memory.
Containers can retain backing storage; arenas can retain all generated objects
until reset. In a garbage-collected runtime, advancing an array index still
retains earlier elements unless their references are cleared. Reuse or release
generated objects, buffers, and chunks deliberately. Keep borrowed data alive
until the generated encoder has finished using it.

## 5. Preserve the profile's contract

The generated types handle serialization, but the producer must still supply a
valid and semantically equivalent profile:

| Data         | Invariant                                                                                                                                                                                            |
| ------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| String table | Index zero is `""` and is serialized. Emit all strings in index order. Every string reference is in range.                                                                                           |
| Object IDs   | Location, mapping, and function IDs are separate namespaces of unique nonzero unsigned integers. Keep IDs stable across all fragments.                                                               |
| Samples      | Every sample has one value per sample type, in the corresponding order. The stack contains location IDs, leaf first.                                                                                 |
| Locations    | Referenced locations and functions exist. Mapping ID zero means unknown; every nonzero mapping reference resolves. Preserve inline-frame order and all source information the basic encoder emitted. |
| Mappings     | When present, the first mapping represents the main executable. Preserve that convention even when draining an unordered container.                                                                  |
| Labels       | Preserve string versus numeric meaning, units, enrichment, and per-sample values. Avoid multiple labels with the same key.                                                                           |
| Metadata     | Preserve start time, duration, period, comments, and any other supported fields. Emit singular metadata once.                                                                                        |

A sample type gives the name and unit for a value-vector position. For example,
`[(samples, count), (cpu, nanoseconds)]` makes `[3, 12000]` mean three samples
and 12,000 nanoseconds. Strings in these types and in labels/functions/mappings
are represented by string-table indices, not by separate local tables.

Presence needs attention even when using generated code. Empty repeated entries
must remain elements. Zero measurement values must remain in their vector
positions. Preserve optional-message presence when it matters to the consumer.

Reader behavior also matters. Google's pprof reader drops labels whose string
index, numeric value, and unit index are all zero. Explicitly setting `num = 0`
does not preserve such a label. A nonempty numeric unit preserves zero in that
reader when that unit is appropriate for the measurement; this requires adding
the original `Label.num_unit` field to the subset above. Empty string labels
using string-table index zero can likewise disappear. Test these cases with
the actual reader, not only a protobuf decoder. See the reader's
[label decoding logic](https://github.com/google/pprof/blob/main/profile/encode.go#L311-L327).

## 6. Compression, limits, and memory use

Feed all fragments into the same streaming compressor and finish it once.
If the generated encoder writes many small chunks directly to the compressor,
put a bounded buffer before compression. If using a reusable fragment buffer,
each call already batches a fragment; additional input buffering can still
help for many tiny entries. Measure before choosing buffer sizes.

Conventional pprof files use gzip. Use another codec only when the destination
explicitly accepts it. The [standard pprof schema](https://github.com/google/pprof/blob/main/proto/profile.proto)
defines the gzip on-disk convention. Compression is independent of the split
protobuf declarations.

At completion, flush any buffered input into the compressor, finish the
compression frame, and propagate required sink flush/close errors. Simply
dropping or flushing a compressor may leave an incomplete frame.

Apply the runtime's per-message limits to each fragment, and separately enforce
the size of the **combined uncompressed profile** and compressed output. A
runtime only encoding small helper messages cannot automatically enforce a
whole-profile limit. Accumulate encoded fragment lengths with checked arithmetic,
or count writes for a stream-based encoder. For broad protobuf interoperability,
keep the complete uncompressed profile below 2 GiB and any lower receiver limit.
A small compressed result does not imply a small uncompressed profile.

The live-memory model is:

```text
remaining collection storage and shared tables
  + current generated entry and wrapper
  + reusable encoded-fragment buffer, if needed
  + any caches and bounded compression buffers
  + accumulated compressed output, if using a memory sink
```

The scratch buffer usually retains capacity for its largest fragment. One huge
sample can therefore still cause a large allocation; configure limits or shed
excess capacity when necessary. An external output sink avoids retaining the
complete compressed result, although a transport requiring its length in
advance may still need that result buffered. Total memory is not constant:
tables, caches, and output can grow. The removed costs are the complete expanded
generated profile and complete uncompressed output buffer.

## 7. Migration and verification

1. **Keep the baseline.** Retain the basic encoder and standard generated
   `Profile` decoder for comparison. Fix timestamps and other changing metadata
   so both paths receive equivalent inputs.
2. **Generate the companions.** Compile the split declarations with the existing
   toolchain, or use a one-entry `Profile` helper. Explicitly test empty-string
   serialization with that runtime.
3. **Change the traversal.** Build one generated sample or table entry,
   wrap it, serialize it using the existing encoder, and feed it to compression.
   Preserve IDs, string indices, ordering, metadata, and enrichment. Initially
   keep the source ownership model unchanged to isolate encoding correctness.
4. **Consume and reuse.** Release observations and tables at their last use.
   Reuse temporary buffers or objects where supported. Exercise error paths and
   arena/garbage-collection behavior so data does not silently accumulate.
5. **Validate and measure.** Decode complete output with the standard `Profile`
   decoder and the actual pprof reader. Compare semantic contents and memory
   behavior against the baseline before replacing it.

### A small complete example using generated objects

Consider a profile with one observation of value `1` in function `main`, a
sample type of `(samples, count)`, and strings `["", "samples", "count", "main"]`.
Location and function IDs are both `1` in their respective namespaces. The
following language-neutral constructors use the fragment declarations above;
`Sample`, `ValueType`, `Location`, `Line`, and `Function` name their corresponding
nested types:

```text
emit_fragment(FragmentSample(sample=Sample(location_id=[1], value=[1])))
emit_fragment(FragmentSampleType(sample_type=ValueType(type=1, unit=2)))
emit_fragment(FragmentLocation(location=Location(id=1, line=Line(function_id=1))))
emit_fragment(FragmentFunction(function=Function(id=1, name=3)))
emit_fragment(FragmentStringTable(string_table=[""]))
emit_fragment(FragmentStringTable(string_table=["samples"]))
emit_fragment(FragmentStringTable(string_table=["count"]))
emit_fragment(FragmentStringTable(string_table=["main"]))
flush any buffered compression input
finish compression
```

The receiver decompresses this and invokes its normal `Profile` decoder once.
It sees one sample, one sample type, one location, one function, and four strings.
No helper declarations are needed at the receiver. No mappings or optional
metadata are necessary for this example.

Compare this against the basic encoder's full `Profile` containing the same
entries. Compare decoded fields, not compressed bytes: field ordering and
compression can differ without changing meaning. Resolve references before
comparison if the implementations assign different IDs. Never reorder strings
independently of their indices, or values independently of sample types.

| Test                                                       | What it catches                                                                     |
| ---------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| First string is present and empty                          | A default-omitting helper that shifts all string references.                        |
| Multiple fragments decode as one Profile                   | Wrong helper field numbers/types, bare nested messages, or a delimited-message API. |
| Reuse of helpers across entries                            | Stale repeated entries or duplicated singular metadata.                             |
| Zero values, empty entries, Unicode, optional fields       | Presence and conversion mistakes around the generated encoder.                      |
| Multiple sample types, deep stacks, labels, inline frames  | Changed ordering, unresolved references, or lost information.                       |
| Zero/empty labels in the actual reader                     | Differences between valid protobuf and reader-visible data.                         |
| Large combined output and one huge sample                  | Missing whole-profile limits or unbounded retained scratch capacity.                |
| Failure during initialization, encoding, writes, or finish | Leaks, incomplete cleanup, or a successful result containing partial output.        |

Generated encoding guarantees protobuf structure, not valid profile references
or application semantics. Validate both. For performance, use identical inputs
and compression settings; measure peak resident memory, live allocations,
allocation count, export CPU, and compressed size. Include repeated deep stacks,
high-cardinality labels, low-repetition input, and concurrent collection/export
if production uses it. The expected benefit is less simultaneous storage;
measure throughput rather than assuming a speedup.

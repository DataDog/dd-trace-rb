# MITERUBY optimization ideas

While working on miteruby, a lot of optimization ideas came up that we haven't explored yet. This doc keeps them around
so we can have some starting points for future exploration.

## Storing (iseq, cme) vs only one of them

Other profilers store only one of them (`rb_profile_frames` doesn't even get you a choice). Keeping both increases
accuracy of stacks (see note in EventDesign.md), but trades if off with more memory for storing stacks, and more
work to be done.

Specifically, it gets us:
* Info of if something is a block (optionally, block level)
* File name for `eval`/`instance_eval`

Observation: Given that we could get "block" directly when collecting the stack and encode it separately (e.g. steal one
or more bits somewhere), giving up file name for `eval`/`instance_eval` (expected to be rare) vs reduced memory and cpu-overhead
of tracking HALF the references to Ruby objects, that seems a nice gain.

## Consider generational GC write barriers in our buffers

If we structure our buffers to separate "things that are changed all the time" from "things that stay over from profile
to profile and don't often change", we could better use Ruby's generational GC and avoid needing to mark everything
on every minor GC.

We could even "shard" some of our storage to take better advantage of this.

## Custom serializer ideas (Added by AI friend)

* Replace linear searches for strings, functions, locations, mappings, and aggregate samples with hash tables.
* Grow arrays geometrically and reuse their storage between profiles instead of reallocating on every append.
* Reuse the consumer's deduplicated stacks directly instead of building a second set of tables while recording.
* Reduce temporary allocations and copies, including the Ruby string passed to `EncodedProfile.from_custom`.
* Explore streaming protobuf output into zstd to avoid keeping the entire uncompressed pprof in memory.
* Move custom encoding outside the GVL once ownership and interruption handling have been designed for that path.

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

## Compress bytecode positions in miteruby_event_stack_sample_t

Like we do delta-compression for deduped ids, we could explore the same idea for the bytecode positions. Yet it's unclear
how much (if any) stacks would normally benefit from this.

## Consider generational GC write barriers in our buffers

If we structure our buffers to separate "things that are changed all the time" from "things that stay over from profile
to profile and don't often change", we could better use Ruby's generational GC and avoid needing to mark everything
on every minor GC.

We could even "shard" some of our storage to take better advantage of this.

## Reuse stack prefixes when deduping stacks

It's very common to have stacks that share a prefix:

* [A, B, C, D, E, F]
* [A, B, C]

Right now we would store both of the above stacks separately, as they are unique. We could consider instead having
the ability to reuse chunks -- e.g. we could split the stack into groups of N, and hash those as well into the
unique_stacks map.

Then, for instance for N = 3, we could store only
* [A, B, C, D, E, F]
* [3 frames from previous stack]

This can be as stupid as "prefix reuse only" or a bit fancier.

## Explore serialization without GVL

Currently, in the serializer, we need the GVL to:

* Build thread contexts + emitting thread name/id
* Compute line numbers
* Emit frame names && filenames

Yet, if we wanted to fully release the GVL during serialization, we could cache all of those across multiple
serializations, and reuse their results. Thus, on every serialization, we'd just need to make sure our caches
have everything (possibly by checking ahead of time, again without GVL, and only requiring GVL during a brief period
to get whatever's new/missing).

The trade-off of enabling such "no-GVL" serialization is increased memory usage: we'd be copying a lot of
strings that already live inside the Ruby heap. So it's a bit unclear how worth it is the trade-off.

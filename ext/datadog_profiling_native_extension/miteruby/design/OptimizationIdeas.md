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

## Better memory reporting and limits due to verstable.h

The hash table we're using allows us to have fine-grained control over how/when it allocates and what to do then.

Thus, rather than backing it with regular calloc/free, we could:

* Back it with a named memory location (using anonymous mmap + prctl naming OR memfd mmap, like OTel process context does)
* Force it to only grow up to some size, and stop profiling if we'd need to go over

This would allow us to:

* Accurately report how much memory we actually use
* Avoid any negative interactions with whatever memory allocator is in use for the rest of the app -- no more dealing with heap corruption, fragmentation, etc
* Be able to promise and keep to a memory budget!

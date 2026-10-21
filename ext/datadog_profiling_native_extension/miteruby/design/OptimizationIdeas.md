# MITERUBY optimization ideas

While working on miteruby, a lot of optimization ideas came up that we haven't explored yet. This doc keeps them around
so we can have some starting points for future exploration.

## Storing (iseq, cme) vs only one of them

Other profilers store only one of them (`rb_profile_frames` doesn't even get you a choice). Keeping both increases
accuracy of stacks (see note in EventDesign.md), but trades if off with more memory for storing stacks, and more
work to be done.

Could we do better here?

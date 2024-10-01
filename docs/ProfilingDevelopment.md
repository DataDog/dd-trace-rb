# Profiling Development

This file contains development notes specific to the continuous profiler.

For a more practical view of getting started with development of `datadog`, see <DevelopmentGuide.md>.

There's also a `NativeExtensionDesign.md` file in the `ext/datadog_profiling_native_extension` that contains further profiler implementation design notes.

## Profiling components high-level view

Some of the profiling components referenced below are implemented using C code. As much as possible, that C code is still
organized in Ruby classes, and the Ruby classes are still created in their corresponding `.rb` files.

Components below live inside <../lib/datadog/profiling>:

* `Collectors::CodeProvenance`: Collects library metadata to power grouping and categorization of stack traces (e.g. to help distinguish user code,
from libraries, from the standard library, etc).
* `Collectors::ThreadContext`: Collects samples of living Ruby threads, based on external events (periodic timer, GC happening, allocations, ...),
recording a metric for them (such as elapsed cpu-time or wall-time, in a few cases) and labeling them with thread id and thread name, as well as
with ongoing tracing information, if any. Relies on the `Collectors::Stack` for the actual stack sampling.
* `Collectors::CpuAndWallTimeWorker`: Triggers the periodic execution of `Collectors::ThreadContext`.
* `Collectors::Stack`: Used to gather a stack trace from a given Ruby thread. Stores its output on a `StackRecorder`.
* `Tasks::Setup`: Takes care of loading and applying `Ext::Forking``.
* `HttpTransport`: Implements transmission of profiling payloads to the Datadog agent or backend.
* `Flush`: Entity class used to represent the payload to be reported for a given profile.
* `Profiler`: Profiling entry point, which coordinates collectors and a scheduler.
* `Exporter`: Gathers data from `StackRecorder` and `Collectors::CodeProvenance` to be reported as a profile.
* `Scheduler`: Periodically (every 1 minute) takes data from the `Exporter` and pushes them to the configured transport.
  Runs on its own background thread.
* `StackRecorder`: Stores stack samples in a native libdatadog data structure and exposes Ruby-level serialization APIs.
* `TagBuilder`: Builds a hash of default plus user tags to be included in a profile

## Initialization

When started via `ddprofrb exec` (together with `DD_PROFILING_ENABLED=true`), initialization goes through the following
flow:

1. <../lib/datadog/profiling/preload.rb> triggers the creation of the profiler instance by calling the method `Datadog::Profiling.start_if_enabled`
2. Creation of the profiler instance is handled by `Datadog::Configuration`, which triggers the configuration of all
  `datadog` components in `#build_components`
3. Inside `Datadog::Components`, the `build_profiler_component` method gets called
4. The `Setup` task activates our extensions (`Datadog::Profiling::Ext::Forking`)
5. The `build_profiler_component` method then creates and wires up the Profiler as such:
    ```asciiflow
            +----------------------------------+
            |             Profiler             |
            +-+------------------------------+-+
              |                              |
              v                              v
    +---------+------------------------+   +-+---------+
    | Collectors::CpuAndWallTimeWorker |   | Scheduler |
    +---------+------------------------+   +-+-------+-+
              |                              |       |
              |                              |       v
              |                              |  +----+----------+
    (... see "How sampling happens" ...)     |  | HttpTransport |
              |                              |  +---------------+
              |                              |
              v                              v
      +-------+-------+                   +--+-------+
      | StackRecorder |<------------------| Exporter |
      +---------------+                   +--+-------+
                                             |
                                             v
                              +--------------+-------------+
                              | Collectors::CodeProvenance |
                              +----------------------------+
    ```
6. The profiler gets started when `startup!` is called by `Datadog::Configuration` after component creation.

## Run-time execution

During run-time, the `Scheduler` and the `Collectors::CpuAndWallTimeWorker` each execute on their own background thread.

The `Scheduler` wakes up every 1 minute to flush the results of the `Exporter` into the `HttpTransport` (see above).

### How sampling happens

The `Collectors::CpuAndWallTimeWorker` component is the "active" part of the profiler. It manages periodic timers, tracepoints, etc
and is responsible for deciding when to sample, and what kind of sample it is.

It then kicks off a pipeline of components, each of which is responsible for gathering part of the information for a single sample.

```asciiflow

 Events:    Timing   GC   Allocations
               │      │        │
  ┌────────────v──────v────────v─────┐
  │ Collectors::CpuAndWallTimeWorker │
  └┬─────────────────────────────────┘
   │
   │ Event details
   │
  ┌v──────────────────────────┐
  │ Collectors::ThreadContext │
  └┬──────────────────────────┘
   │
   │ + Values (cpu-time, ...) and labels (thread id, span id, ...)
   │
  ┌v──────────────────┐
  │ Collectors::Stack │
  └┬──────────────────┘
   │
   │ + Stack traces
   │
  ┌v──────────────┐
  │ StackRecorder │
  └┬──────────────┘
   │
   │ Sample
   │
  ┌v───────────┐
  │ libdatadog │
  └────────────┘
```

All of these components are executed synchronously, and at the end of recording the sample in libdatadog, control is returned back "up" the stack
through each one, until the `CpuAndWallTimeWorker` finishes its work and control returns to the Ruby VM.

## How linking of traces to profiles works

The [code hotspots feature](https://docs.datadoghq.com/tracing/profiler/connect_traces_and_profiles) allows users to start
from a trace and then to investigate the profile that corresponds to that trace.

This works in two steps:
1. Linking a trace to the profile that was gathered while it executed
2. Enabling the filtering of a profile to contain only the samples relating to a given trace/span

To link a trace to a profile, we must ensure that both have the same `runtime-id` tag.
This tag is in `Datadog::Runtime::Identity.id` and is automatically added by both the tracer and the profiler to reported
traces/profiles.

The profiler backend links a trace covering a given time interval to the profiles covering the same time interval,
whenever they share the same `runtime-id`.

To further enable filtering of a profile to show only samples related to a given trace/span, each sample taken by the
profiler is tagged with the `local root span id` and `span id` for the given trace/span.

This is done inside the `Collectors::ThreadContext` that retrieves a `root_span_id` and `span_id`, if
available, from the tracer.

Note that if a given trace executes too fast, it's possible that the profiler will not contain any samples for that
specific trace. Nevertheless, the linking still works and is useful, as it allows users to explore what was going on their
profile at that time, even if they can't filter down to the specific request.

## Tracking of cpu-time and wall-time spent during garbage collection

See comments at the top of `collectors_thread_context.c` for an explanation on how that feature is implemented.

## How GVL profiling works

Profiling the Ruby Global VM Lock (GVL) works by using the [GVL instrumentation API](https://github.com/ruby/ruby/pull/5500).

This API currently only works on Ruby 3.2+, although there were a few changes and refinements on Ruby 3.3+ and as of this writing
(September 2024) we _only_ support Ruby 3.3+.

These blog posts are good starting points to understand this API:

* https://ivoanjo.me/blog/2022/07/17/tracing-ruby-global-vm-lock/
* https://ivoanjo.me/blog/2023/02/11/ruby-unexpected-io-vs-cpu-unfairness/
* https://ivoanjo.me/blog/2023/07/23/understanding-the-ruby-global-vm-lock-by-observing-it/

Below follow some notes on how it works. Note that it's possible we'll forget to update this documentation as the code
changes, so take the below info as a starting point to understanding how the feature is integrated, rather than an exact spec.

### Getting VM callbacks in `CpuAndWallTimeWorker`

From our side, the magic starts in the `CpuAndWallTimeWorker` class. When GVL profiling is enabled, we ask the VM to tell
us about two kinds of thread events:

```c
    if (state->gvl_profiling_enabled) {
      state->gvl_profiling_hook = rb_internal_thread_add_event_hook(
        on_gvl_event,
        (
          // For now we're only asking for these events, even though there's more
          // (e.g. check docs or gvl-tracing gem)
          RUBY_INTERNAL_THREAD_EVENT_READY /* waiting for gvl */ |
          RUBY_INTERNAL_THREAD_EVENT_RESUMED /* running/runnable */
        ),
        NULL
      );
    }
```

As the comments hint at:
* `RUBY_INTERNAL_THREAD_EVENT_READY` is emitted by the VM when a thread is ready to start running again. E.g. it's now
waiting for its turn to acquire the GVL. We call this thread "Waiting for GVL" in the profiler code, as well as in the Datadog UX
* `RUBY_INTERNAL_THREAD_EVENT_RESUMED` is emitted by the VM immediately after a thread has acquired the GVL. It's so
immediately after that (looking at the VM code) it may not even have done all the cleanup needed after acquisition for the
thread to start running.

Once one of those events happen, Ruby will tell us by calling our `on_gvl_event` function
(still in the `CpuAndWallTimeWorker`).

Both events above are (as far as I know) emitted by the thread they are representing. But, we need to be very careful
about running code in `on_gvl_event` to handle these events:

* `RUBY_INTERNAL_THREAD_EVENT_READY` is emitted while the thread is not holding the GVL, and thus it can be in parallel with
other things
* All events are emitted _for all Ractors_, and each Ractor has their own GVL (yes yes, naming, see
[the talk linked into](https://ivoanjo.me/blog/2023/07/23/understanding-the-ruby-global-vm-lock-by-observing-it/) for a discussion on this)
* With the Ruby M:N threading, a native thread may play host to multiple Ruby threads so let's not assume too much

All of the above taken together mean that we need to be very careful with what state we mutate or access from `on_gvl_event`, as they
can be concurrent with other operations in the profiler (including sampling).

(The current implementation is similar to GC profiling, which shares similar constraints and limitations in not being able to sample
from the VM callbacks and also messing with cpu/wall-time accounting for threads that are GCing.)

The `ThreadContext` collector exposes three APIs for GVL profiling:

* `void thread_context_collector_on_gvl_waiting(VALUE thread)`
* `bool thread_context_collector_on_gvl_running(VALUE thread)`
* `VALUE thread_context_collector_sample_after_gvl_running(VALUE self_instance)`

The intuition here is that:

* `on_gvl_waiting` tracks when a thread began Waiting for GVL. It should be called when a thread
reports `RUBY_INTERNAL_THREAD_EVENT_READY`
* `on_gvl_running` tracks when a thread acquired the GVL. It should be called when a thread reports
`RUBY_INTERNAL_THREAD_EVENT_RESUMED`
* `sample_after_gvl_running` is the one that actually triggers the creation of a sample to represent
the waiting period. It should be called via the VM postponed job API when `on_gvl_running` returns `true`; e.g. when the
`ThreadContext` collector reports a sample should be taken.

As far as the `CpuAndWallTimeWorker` cares, the above is all it needs to call in response to VM events. You'll notice
that `on_gvl_waiting` and `on_gvl_running` don't need or use any of the `CpuAndWallTimeWorker` or `ThreadContext`
instance state.

The `sample_after_gvl_running` actually does, and that's why it's supposed to be used from a postponed job, which
ensures there's no concurrency (in our setup it only gets called with the GVL + on the main ractor) and thus we're safe to
access and mutate state inside it.

### Tracking thread state and sampling in `ThreadContext`

The weirdest piece of this puzzle is done in the `ThreadContext` collector. Because, as mentioned above,
`on_gvl_waiting` and `on_gvl_running` can get called outside the GVL/in other Ractors, we avoid touching the current
`ThreadContext` instance state in these methods.

Instead, we ask Ruby to hold the data we need for us using the `rb_internal_thread_specific` API. This API provides
an extremely low-level and limited thread-local storage mechanism, but one that's thread-safe and thus a good match
for our needs. (This API is only available on Ruby 3.3+; to support Ruby 3.2 we'll need to figure out an alternative.)

So, here's how this works: the first time the `ThreadContext` collector sees a thread (e.g. when it creates a context
for it), it uses this API to tag this thread as a thread we want to know about:

```c
rb_internal_thread_specific_set(thread, per_thread_gvl_waiting_timestamp_key, (void *) GVL_WAITING_ENABLED_EMPTY);
```

From here on out, `on_gvl_waiting` and `on_gvl_running` know that if a thread has the `per_thread_gvl_waiting_timestamp`
variable set (to any other value than the default of `NULL`/0), it means this thread is known by the `ThreadContext`
collector and thus we should record data about it.
(And threads not in the main Ractor don't get this marker so this is one way we filter them out.)

Could we have stored a pointer to the thread context directly on the thread? Potentially, yes, but we'd need to be
extremely careful when accessing thread contexts and when cleaning them up. (Maybe we'll evolve in this direction in
the future?)

With the storage problem solved, here's what happens: the first part is that `on_gvl_waiting` records a timestamp for
when waiting started in the thread in `per_thread_gvl_waiting_timestamp`.

Then, `on_gvl_running` checks the duration of the waiting (e.g. time between waiting started and current time). This
is a mechanism for reducing overhead: we'll produce at least two samples for every "Waiting for GVL" event that
we choose to sample, so we need to be careful not to allow situations with a lot of threads waiting for very brief
periods to induce too much overhead on the application.

If we decide to sample (duration >= some minimal threshold duration for sampling), we can't sample yet!
As documented above, `on_gvl_running` is called in response to VM `RUBY_INTERNAL_THREAD_EVENT_RESUMED` events that
happen right after the thread acquired the GVL but there's still some book-keeping to do. Thus, we don't sample
from this method, but use the `bool` return to signal the caller when a sample should be taken.

Then, a sample is taken once the caller (`CpuAndWallTimeWorker`) calls into `sample_after_gvl_running`.
This design is similar to GC profiling, where we also can't sample during GC, and thus we trigger a sample to happen immediately after.

### Representing the Waiting for GVL in `ThreadContext`

As far as sampling goes, we represent a Waiting for GVL as a thread state, similar to other thread states we emit.
This state is special, as it "overrides" other states, e.g. if a thread was sleeping, but wants to wake up, even
though the thread is still inside `sleep`, it will have the "Waiting for GVL" state.

Waiting for GVL does not affect the regular flamegraph, only the timeline visualization, as it's a thread state, and
currently we do not represent thread states in any way on the regular flamegraph.

The timestamp of the beginning of waiting for GVL gets used to create a sample that represents the "Waiting for GVL"
period. Because there's some unaccounted for cpu and wall-time between the previous sample and the start of a waiting
period, we also create a sample to account for this.

There's some (lovely?) ASCII art in `handle_gvl_waiting` to explain how we create these two samples.

Once a thread is in the "Waiting for GVL" state, then all regular cpu/wall-time samples triggered by the `CpuAndWallTimeWorker`
will continue to mark the thread as being in this state, until `on_gvl_running` + `sample_after_gvl_running` happen and
clear the `per_thread_gvl_waiting_timestamp`, which will make samples revert back to the regular behavior.

# Profiling Development

This file contains development notes specific to the continuous profiler.

For a more practical view of getting started with development of `datadog`, see <DevelopmentGuide.md>.

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

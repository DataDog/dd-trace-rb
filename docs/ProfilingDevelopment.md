# Profiling Development

This file contains development notes specific to the profiling feature.

For a more practical view of getting started with development of `ddtrace`, see <DevelopmentGuide.md>.

## Profiling components high-level view

Some of the profiling components referenced below are implemented using C code. As much as possible, that C code is still
organized in Ruby classes, and the Ruby classes are still created in their corresponding `.rb` files.

Components below live inside <../lib/datadog/profiling>:

* (Deprecated) `Collectors::OldStack`: Collects stack trace samples from Ruby threads for both CPU-time (if available) and wall-clock.
  Runs on its own background thread.
* `Collectors::CodeProvenance`: Collects library metadata to power grouping and categorization of stack traces (e.g. to help distinguish user code,
from libraries, from the standard library, etc).
* `Collectors::ThreadContext`: Collects samples of living Ruby threads, based on external events (periodic timer, GC happening, allocations, ...),
recording a metric for them (such as elapsed cpu-time or wall-time, in a few cases) and labeling them with thread id and thread name, as well as
with ongoing tracing information, if any. Relies on the `Collectors::Stack` for the actual stack sampling.
* `Collectors::CpuAndWallTimeWorker`: Triggers the periodic execution of `Collectors::ThreadContext`.
* `Collectors::Stack`: Used to gather a stack trace from a given Ruby thread. Stores its output on a `StackRecorder`.

* (Deprecated) `Encoding::Profile::Protobuf`: Encodes gathered data into the pprof format.
* (Deprecated) `Events::Stack`, `Events::StackSample`: Entity classes used to represent stacks.
* `Ext::Forking`: Monkey patches `Kernel#fork`, adding a `Kernel#at_fork` callback mechanism which is used to restore
  profiling abilities after the VM forks (such as re-instrumenting the main thread, and restarting profiler threads).
* (Deprecated) `Pprof::*` (in <../lib/datadog/profiling/pprof>): Used by `Encoding::Profile::Protobuf` to convert samples captured in
  the `OldRecorder` into the pprof format.
* `Tasks::Setup`: Takes care of loading and applying `Ext::Forking``.
* `HttpTransport`: Implements transmission of profiling payloads to the Datadog agent or backend.
* (Deprecated) `TraceIdentifiers::*`: Used to retrieve trace id and span id from tracers, to be used to connect traces to profiles.
* (Deprecated) `BacktraceLocation`: Entity class used to represent an entry in a stack trace.
* (Deprecated) `Buffer`: Bounded buffer used to store profiling events.
* (Deprecated) `Event`
* `Flush`: Entity class used to represent the payload to be reported for a given profile.
* `Profiler`: Profiling entry point, which coordinates collectors and a scheduler.
* (Deprecated) `OldRecorder`: Stores profiling events gathered by the `Collector::OldStack`. (To be removed after migration to libddprof aggregation)
* `Exporter`: Gathers data from `OldRecorder` and `Collectors::CodeProvenance` to be reported as a profile.
* `Scheduler`: Periodically (every 1 minute) takes data from the `Exporter` and pushes them to the configured transport.
  Runs on its own background thread.
* `StackRecorder`: Stores stack samples in a native libdatadog data structure and exposes Ruby-level serialization APIs.
* `TagBuilder`: Builds a hash of default plus user tags to be included in a profile

## Initialization

When started via `ddtracerb exec` (together with `DD_PROFILING_ENABLED=true`), initialization goes through the following
flow:

1. <../lib/datadog/profiling/preload.rb> triggers the creation of the profiler instance by calling the method `Datadog::Profiling.start_if_enabled`
2. Creation of the profiler instance is handled by `Datadog::Configuration`, which triggers the configuration of all
  `ddtrace` components in `#build_components`
3. Inside `Datadog::Components`, the `build_profiler` method triggers the execution of the `Tasks::Setup` task
4. The `Setup` task activates our extensions (`Datadog::Profiling::Ext::Forking`)
5. Still inside `Datadog::Components`, the `build_profiler` method then creates and wires up the Profiler as such:
    ```asciiflow
            +------------+
            |  Profiler  |
            +-+-------+--+
              |       |
              v       v
    +---------+--+  +-+---------+
    | Collectors |  | Scheduler |
    +---------+--+  +-+-------+-+
              |       |       |
              v       |       v
     +--------+-+     |  +----+----------+
     | OldStack |     |  | HttpTransport |
     +--------+-+     |  +---------------+
              |       |
              v       v
    +---------+---+  ++---------+
    | OldRecorder |<-| Exporter |
    +-------------+  +-+--------+
                       |
                       v
        +--------------+--+
        | Code Provenance |
        +-----------------+
    ```
6. The profiler gets started when `startup!` is called by `Datadog::Configuration` after component creation.

### Work in progress

The profiler is undergoing a lot of refactoring. After this work is done, this is how we expect it will be wired up:

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

## Run-time execution

During run-time, the `Scheduler` and the `Collectors::CpuAndWallTimeWorker` (`Collectors::OldStack` for the legacy profiler) each execute on their own background thread.

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

All of these components are executed synchronously, and at the end of recording the sample in libdatadog, control is returned back "up"
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

This is done using the `Datadog::Profiling::TraceIdentifiers::Helper` that retrieves a `root_span_id` and `span_id`, if
available, from the supported tracers. This helper is called by the `Collectors::OldStack` during sampling.

Note that if a given trace executes too fast, it's possible that the profiler will not contain any samples for that
specific trace. Nevertheless, the linking still works and is useful, as it allows users to explore what was going on their
profile at that time, even if they can't filter down to the specific request.

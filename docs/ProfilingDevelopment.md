# Profiling Development

This file contains development notes specific to the profiling feature.

For a more practical view of getting started with development of `ddtrace`, see <DevelopmentGuide.md>.

## Profiling components high-level view

Components below live inside <../lib/ddtrace/profiling>:

* `Collectors::Stack`: Collects stack trace samples from Ruby threads for both CPU-time (if available) and wall-clock.
  Runs on its own background thread.
* `Collectors::CodeProvenance`: Collects library metadata to power grouping and categorization of stack traces (e.g. to help distinguish user code, from libraries, from the standard library, etc).
* `Encoding::Profile`: Encodes gathered data into the pprof format.
* `Events::Stack`, `Events::StackSample`: Entity classes used to represent stacks.
* `Ext::Forking`: Monkey patches `Kernel#fork`, adding a `Kernel#at_fork` callback mechanism which is used to restore
  profiling abilities after the VM forks (such as re-instrumenting the main thread, and restarting profiler threads).
* `Pprof::*` (in <../lib/ddtrace/profiling/pprof>): Converts samples captured in the `Recorder` into the pprof format.
* `Tasks::Setup`: Takes care of loading our extensions/monkey patches to handle fork().
* `Transport::*` (in <../lib/ddtrace/profiling/transport>): Implements transmission of profiling payloads to the Datadog agent
  or backend.
* `TraceIdentifiers::*`: Used to retrieve trace id and span id from tracers, to be used to connect traces to profiles.
* `BacktraceLocation`: Entity class used to represent an entry in a stack trace.
* `Buffer`: Bounded buffer used to store profiling events.
* `Exporter`: Writes profiling data to a given transport.
* `Flush`: Entity class used to represent metadata for a given profile.
* `Profiler`: Profiling entry point, which coordinates collectors and a scheduler.
* `Recorder`: Stores profiling events gathered by `Collector`s.
* `Scheduler`: Periodically (every 1 minute) takes data from the `Recorder` and pushes them to all configured
  `Exporter`s. Runs on its own background thread.

## Initialization

When started via `ddtracerb exec` (together with `DD_PROFILING_ENABLED=true`), initialization goes through the following
flow:

1. <../lib/ddtrace/profiling/preload.rb> triggers the creation of the `Datadog.profiler` instance by calling the method
2. `Datadog.profiler` is handled by `Datadog::Configuration`, which triggers the configuration of `ddtrace` components
   in `#build_components`
3. Inside `Datadog::Components`, the `build_profiler` method triggers the execution of the `Tasks::Setup`
4. The `Setup` task activates our extensions
    * `Datadog::Profiling::Ext::Forking`
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
        +-----+-+     |  +----+------+
        | Stack |     |  | Exporters |
        +-----+-+     |  +-----------+
              |       |
              v       v
            +-+-------+-+
            | Recorder  |
            +-----------+
              |
              v
        +-----------------+
        | Code Provenance |
        +-----------------+
    ```
6. The profiler gets started when `startup!` is called by `Datadog::Configuration` after component creation.

## Run-time execution

During run-time, the `Scheduler` and the `Collectors::Stack` each execute on their own background thread.

The `Collectors::Stack` samples stack traces of threads, capturing both CPU-time (if available) and wall-clock, storing
them in the `Recorder`.

The `Scheduler` wakes up every 1 minute to flush the results of the `Recorder` into one or more `exporter`s.
Usually only one exporter is in use. By default, the `Exporter` delegates to the default `Transport::HTTP` transport, which
takes care of encoding the data and reporting it to the datadog agent (or to the API, when running without an agent).

## How CPU-time profiling works

**TODO**: Document our pthread-based approach to getting CPU-time for threads.

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
available, from the supported tracers. This helper is called by the `Collectors::Stack` during sampling.

Note that if a given trace executes too fast, it's possible that the profiler will not contain any samples for that
specific trace. Nevertheless, the linking still works and is useful, as it allows users to explore what was going on their
profile at that time, even if they can't filter down to the specific request.

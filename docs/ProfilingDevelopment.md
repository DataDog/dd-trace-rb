# Profiling Development

## What?

This file contains development notes specific to the profiling feature.

For a more practical view of getting started with development of `ddtrace`, see <DevelopmentGuide.md>.

## Profiling components high-level view

Components below live inside <../lib/ddtrace/profiling>:

* `Collectors::Stack`: Collects stack trace samples from Ruby threads for both CPU-time (if available) and wall-clock.
  Runs on its own background thread.
* `Encoding::Profiler`: Encodes gathered data into the pprof format.
* `Events::Stack`, `Events::StackSample`, `Events::StackExceptionSample`: Entity classes used to represent stacks.
* `Ext::CPU`: Monkey patches Ruby's `Thread` with our `Ext::CThread` to enable CPU-time profiling.
* `Ext::CThread`: Extension used to enable CPU-time profiling via use of Pthread's `getcpuclockid`.
* `Ext::Forking`: Monkey patches `Kernel#fork`, adding a `Kernel#at_fork` callback mechanism which is used to restore
  profiling abilities after the VM forks (re-instrument main thread, restart profiler threads).
* `Pprof::*` (in <../lib/ddtrace/profiling/pprof>): Converts samples captured in the `Recorder` into the pprof format.
* `Tasks::Setup`: Takes care of loading our extensions/monkey patches and starting up profiler. See initialization
  section below for more details.
* `Transport::*` (in <../lib/ddtrace/profiling/transport>): Implements reporting of pprof payloads to the datadog agent
  or backend.
* `BacktraceLocation`: Entity class used to represent an entry in a stack trace.
* `Buffer`: Bounded buffer used to store profiling events.
* `Exporter`: Writes profiling data to a given transport.
* `Flush`: Entity class used to represent metadata for a given profile.
* `Profiler`: Profiling entry point, which coordinates collectors and a scheduler.
* `Recorder`: Stores profiling events gathered by `Collectors`.
* `Scheduler`: Periodically (every 1 minute) takes data from the `Recorder` and pushes them to all configured
  `Exporter`s.

## Initialization

When started via `ddtracerb exec` (together with `DD_PROFILING_ENABLED=true`), initialization goes through the following
flow:

1. <../lib/ddtrace/profiling/preload.rb> Creates a new `Datadog::Profiling::Tasks::Setup` and runs it.
2. The `Setup` task activates our extensions (see high level view for details)
    * `Datadog::Profiling::Ext::Forking`
    * `Datadog::Profiling::Ext::CPU`
3. The `Setup` task triggers the creation of the `Datadog.profiler` instance by calling the method
4. `Datadog.profiler` is handled by `Datadog::Configuration`, which triggers the configuration of `ddtrace` components
   in `#build_components`
5. `Datadog::Configuration::Components` then starts and wires up the Profiler:
    ```ruby
          recorder = build_profiler_recorder(settings)
          collectors = build_profiler_collectors(settings, recorder)
          exporters = build_profiler_exporters(settings)
          scheduler = build_profiler_scheduler(settings, recorder, exporters)

          Datadog::Profiler.new(collectors, scheduler)
    ```
    ```asciiflow
            +------------+
            |  Profiler  |
            +-+--------+-+
              |        |
              v        v
    +---------+--+  +--+--------+
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
    ```
6. The `Setup` task starts the profiler

## Run-time execution

During run-time, the `Scheduler` and the `Collectors::Stack` each execute on their own background thread.

The `Collectors::Stack` samples stack traces of threads, capturing both CPU-time (if available) and wall-clock, storing
them in the `Recorder`.

The `Scheduler` wakes up every 1 minute to flush the results of the `Recorder` into one or more `exporter`s.
Usually only one exporter is in use. The `Exporter` delegates to the default `Transport::HTTP` transport, which
takes care of encoding the data and reporting it to the datadog agent (or to the API, when running without an agent).

## How CPU-time profiling works

**TODO**: Document our pthread-based approach to getting CPU-time for threads.

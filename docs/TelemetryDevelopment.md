# Telemetry Development

## Telemetry Presence

`dd-trace-rb` is written to assume that the telemetry component is always
present. If telemetry is disabled, the component is still created but does
nothing.

Most components call methods on `telemetry` unconditionally. There are two
exceptons: DI and Data Streams are written to assume that `telemetry` may be nil.
However, this assumption is not necessary and these components may be
changed in the future to assume that `telemetry` is always present.

## Event Submission Prior To Start

Telemetry is unique among other components in that it permits events to be
submitted to it prior to its worker starting. This is done so that errors
during `Datadog.configure` processing can be reported via telemetry, because
the errors can be produced prior to telemetry worker starting. The telemetry
component keeps the events and sends them after the worker starts.

## Initial Event

`dd-trace-rb` can be initialized multiple times during application boot.
For example, if customers follow our documentation and require
`datadog/auto_instrument`, and call `Datadog.configure`, they would get
`Datadog.configure` invoked two times total (the first time by `auto_instrument`)
and thus telemetry instance would be created twice. This happens in the
applications used with system tests.

System tests, on the other hand, require that there is only one `app-started`
event emitted, because they think the application is launched once.
To deal with this we have a hack in the telemetry code to send an
`app-client-configuration-change` event instead of the second `app-started`
event. This is implemented via the `SynthAppClientConfigurationChange` class.

## Fork Handling

We must send telemetry data from forked children.

Telemetry started out as a diagnostic tool used during application boot,
but is now used for reporting application liveness (and settings/state)
throughout the application lifetime. Live Debugger / Dynamic Instrumentation,
for example, require ongoing `app-heartbeat` events emitted via telemetry
to provide a working UI to customers.

It is somewhat common for customers to preload the application in the parent
web server process and process requests from children. This means telemetry
is initialized from the parent process, and it must emit events in the
forked children.

We use the standard worker `after_fork` handler to recreated the worker
thread in forked children. However, there are two caveats to keep in mind
which are specific to telemetry:

1. Due to telemetry permitting event submission prior to its start, it is
not sufficient to simply reset the state from the worker's `perform` method,
as is done in other components. We must only reset the state when we are
in the forked child, otherwise we'll trash any events submitted to telemetry
prior to its worker starting.

2. The child process is a brand new application as far as the backend/UI is
concerned, having a new runtime ID, and therefore the initial event in the
forked child must always be `app-started`. Since we track the initial event
in the telemetry component, this event must be changed to `app-started` in
forked children regardless of what it was in the parent.

## Native trace exporter metrics

The experimental native transport can run libdatadog's `MetricsLogs` worker on
its existing shared runtime. Ruby retains application lifecycle, configuration,
dependencies, and unrelated metrics. Native exporter series keep
`src_library:libdatadog`.

Enablement requires tracing, telemetry, and metrics to be enabled, Agent-based
telemetry, and native headers and symbols supporting mutable identity and bounded shutdown.
The pinned libdatadog 44.0.1 package lacks these APIs; development requires a
matching `LIBDATADOG_VENDOR_OVERRIDE` build. Agentless telemetry, including its
URL override, does not enable the native worker.

Native delivery uses Ruby's heartbeat interval, converted to milliseconds. Its
aggregation interval is the smaller of that interval and ten seconds; Ruby's
independently configurable metrics aggregation interval does not change it.
Native endpoint-error handling is independent of Ruby's unsupported-endpoint
disablement.

Fork preparation pauses native workers and drains active sends. The child
publishes Ruby's runtime and session ancestry before resetting and restarting
workers; pending parent observations are discarded. Parent and failed-fork
paths retain identity, pending observations, and sequence state. Native sequence
counters remain independent of Ruby's emitter; backend acceptance of this
arrangement must be confirmed before package uptake.

Explicit close bounds worker flushing by Ruby's telemetry shutdown timeout,
outside the GVL. Disabling telemetry before close discards pending native data. Garbage
collection discards the exporter and its exclusively owned runtime without a
network flush. Pausing an already active telemetry request waits for its response
or native endpoint timeout (three seconds by default); trace-send cancellation
does not cancel the telemetry worker.

These deadlines do not bound system DNS resolution: the current Hyper connector
uses blocking resolver tasks, and runtime destruction joins those tasks. The
local timeout regressions use IP addresses and Unix sockets; they do not establish
a process-wide deadline for hostname resolution.

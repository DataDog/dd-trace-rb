# Telemetry Migration Design

Status: draft. Internal design for dd-trace-rb. The shared proposal, the
coverage matrix, and the gap asks to libdatadog live in
`docs/NativeTelemetryAdoption.md`. Read that document first.

Non-goals: the public telemetry API never changes. Client-side stats and
the trace transport are separate projects.

## End state

One host-owned Rust telemetry worker per process, created by the Ruby
component. All subsystems keep calling the Ruby facade. The traffic map
and the invariants are in the shared proposal.

## Backend seam

The component delegates to a backend object. Both implementations respond
to the same methods:

- `inc(namespace, name, value, tags:, common:)`
- `dec`, `gauge`, `rate`, `distribution` with the same arguments
- `add_log(id, message, level, stack_trace)`
- `add_dependency(name, version)`
- `add_integration(name, version, enabled, compatible, auto_enabled)`
- `start`, `stop`, `after_fork`, `shutdown!`

`RubyBackend` is the current `MetricsManager`, worker, and HTTP transport,
moved unchanged behind the interface. `NativeBackend` binds
`datadog/telemetry.h`. Its metric methods translate to
`ddog_telemetry_handle_register_metric_context` (once per metric) and
`ddog_telemetry_handle_add_point` (per call). The builder receives the same
service, env, runtime, and language fields that the Ruby emitter puts in
every message today.

The component selects the backend at build time, in
`core/configuration/components.rb`, next to the existing
`build_native_transport` pattern. The setting is
`settings.telemetry.native_worker`, default `false`, with an environment
variable. Add it to `docs/GettingStarted.md` and run
`rake local_config_map:generate` when the setting lands.

The component owns one worker instance across reconfigures, so a double
`Datadog.configure` during boot never produces a second `app-started`.

## C bindings

New file `ext/libdatadog_api/telemetry.c`. It follows the existing pattern
of one file per libdatadog component (see `crashtracker.c`, `ddsketch.c`,
`trace_exporter.c`). It binds the builder methods, the handle methods, and
the shutdown functions. If the build fails, the extension degrades to
`LIBDATADOG_API_FAILURE`. The component then builds the Ruby backend.

## Steps, each a two-way door

1. Seam extraction. Move `MetricsManager` and the worker behind
`RubyBackend` inside the component. No behavior change, no gate. Revert by
reverting the commit.
2. Bind the worker. Add `telemetry.c`. `NativeBackend` implements the
metric and log methods on one worker. Gate it with `native_worker`. The
exporter observations keep flowing through the existing Ruby bridge, but
land in `add_point` on the worker. Revert by flag off. Ruby answers again.
3. Lifecycle events on the worker. Enable lifecycle emission after steps 1
and 2 soak. Before this step ships, verify the event parity items from the
shared proposal. The checks: one `app-started` across reconfigures,
heartbeat intervals at the expected values, and a story for
`app_endpoints_loaded`. That event has no native equivalent today. Revert
by flag off, back to the Ruby event layer.
4. Remove the in-process hop. This step needs a libdatadog setter that
hands an existing `TelemetryWorkerHandle` to the trace exporter config.
Until that setter ships, the hop stays. It is a cheap struct pass and FFI
call, not an HTTP round trip.

`ddog_trace_exporter_config_enable_telemetry` (a private worker inside the
exporter) exists in the vendored library. It stays out of the shipped plan
because it breaks the one-emitter invariant. It can serve as a spike or a
canary, never as the default.

## What stays in Ruby

- The public component API and the backend selection.
- The pre-start event queue.
- `app_endpoints_loaded` and the `SynthAppClientConfigurationChange` hack,
until step 3 proves them replaceable.

## References

- `docs/NativeTelemetryAdoption.md` for the proposal, coverage matrix, and
gap asks.
- `docs/TelemetryDevelopment.md` for current component behavior.
- `lib/datadog/tracing/transport/telemetry.rb` for the current observation
bridge and its `COUNTS` metric table.
- `lib/datadog/tracing/transport/native.rb` for the native transport and
its fork and telemetry bridge patterns.
- `datadog/telemetry.h` in the vendored libdatadog 46.1 for the full native
API.

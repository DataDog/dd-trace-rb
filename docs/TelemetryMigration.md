# Telemetry Migration: Requirements, Spec and Design

Status: draft. This is a plan, not shipped behavior. It explains how the
telemetry component can move its metrics and logs work to the native Rust
worker in libdatadog. Each step is revertible on its own.

## Background

The telemetry component today is pure Ruby. It lives in
`lib/datadog/core/telemetry/`. It owns a background worker, its own HTTP
transport to the agent, an event layer, and a metrics manager.

libdatadog ships a native telemetry worker. The `libdatadog` gem that
dd-trace-rb already depends on (`~> 46.1`) vendors the compiled worker. The
C API is in `vendor/.../include/datadog/telemetry.h`. The symbols are
present in the shipped `libdatadog_profiling` library. Nothing in
`ext/libdatadog_api/` binds it yet.

The immediate pain point is the native trace exporter. It produces send
observations (`ddog_TraceExporterObservations`) on every send. Today those
cross into Ruby, and `Tracing::Transport::Telemetry` converts them into
telemetry metrics that the Ruby component ships to the agent. Rust hands
data to Ruby only so Ruby can re-serialize and send it.

The end state is one telemetry emitter per process: a single Rust worker
owned by the telemetry component. The exporter keeps its current bridge,
but the bridge feeds `add_point` calls into the same worker. No private
worker inside the exporter, and no second telemetry stream.

Non-goals:

- Changing the public telemetry API that other subsystems call.
- Implementing client-side stats. That is a separate project on the stats
pipe. Telemetry only reports its health counters.
- Removing agent-side telemetry. Messages still go to the agent
(`/api/v2/apmtelemetry`). The Rust worker, not Ruby, sends them.
- Migrating the trace transport. The native transport
(`Tracing::Transport::Native`) stays as this document found it.

## Requirements

R1. Call sites never change. AppSec, DI, profiling, and core keep calling
`Datadog.configuration.telemetry`, `telemetry.inc`, and the `emit_*`
methods.

R2. The agent sees the same messages in both modes: same event types, metric
names, namespaces, tags, and flush cadence. System tests and the telemetry
specs are the equivalence contract. They must pass against both backends.

R3. Telemetry failures never raise into application code, in either backend.
A native call error drops the point or falls back. It never surfaces.

R4. A missing native extension, or a worker that fails to start, silently
selects the Ruby backend. No configuration state can leave telemetry broken.

R5. Every new path sits behind a setting that defaults to off. Each step
ships behind its own gate. Anyone can revert a step by flipping the setting
or by reverting one commit. The Ruby implementation stays alive until the
native path soaks with the default on. It stays deletable only after that.

R6. Exactly one telemetry emitter runs per process at any time. The exporter
must never run a private telemetry worker while the component worker also
runs. Metric double counting is a bug, not a trade-off.

R7. Shutdown behavior is preserved. `Component#shutdown!` flushes with the
same timeout budget the Ruby worker uses today.

R8. Fork safety: after fork, children keep emitting telemetry. The native
handle is cloned or rebuilt in the child. Follow the same fork hook pattern
that the native transport already uses.

## What the native worker does by itself

Reading the libdd-telemetry worker source (docs.rs, libdatadog master)
settles the biggest design question. The worker emits the lifecycle events
on its own schedule. It does not need the host to push them:

- `Lifecycle(Start)` sends `app-started`. It includes configuration and
products. It excludes dependencies and integrations, because the backend
rejects them there.
- `Lifecycle(FlushData)` sends `app-heartbeat`. When app events are pending,
it batches them into a `message-batch` that ends with the heartbeat.
- `Lifecycle(ExtendedHeartbeat)` sends `app-extended-heartbeat`. It first
flushes delta app events, then bundles dependencies, integrations, and
configurations.
- `Lifecycle(Stop)` sends `app-closing` after it flushes metric aggregates
and app events.
- The `builder_run_metric_logs` flavor does not schedule `app-started`.
dd-trace-rs gates lifecycle emission with an `emit_app_lifecycle` flag and
calls `send_stop()` on shutdown.

So a host-owned worker can carry the full event layer, not only metrics and
logs. Two Ruby behaviors still need proof before events move: the
one-`app-started` rule across reconfigures, and the heartbeat intervals
(R9 and the open questions below).

R9. If the Rust worker emits lifecycle events, their intervals and their
one-`app-started` behavior must match what system tests expect today.

## Use case inventory and native coverage

This inventory lists every use case of the Ruby component, and how much of
it the native worker already covers. The gap list at the end is the ask we
hand to the libdatadog team.

### Events

The Ruby component emits these events: `app-started`, `app-heartbeat`,
`app-extended-heartbeat`, `app-closing`, `app-dependencies-loaded`,
`app-integrations-change`, `app-client-configuration-change`,
`app_endpoints_loaded`, `message-batch`, and log events with dedup counts
(`lib/datadog/core/telemetry/worker.rb`, `event/`).

### Metrics and transport

Metrics: `inc`, `dec`, `gauge`, `rate`, and `distribution`, namespaces
`appsec` and `tracers`, free-form tags, the `common` flag, and an on-demand
`flush(timeout:)`.

Transport: agent proxy and agentless with api key, test token, timeout,
and all application, runtime, and host fields.

### Consumers

- About 30 `telemetry.report` and `telemetry.error` call sites. They cover
AppSec, AI Guard, OpenFeature, profiling, symbol database, the core
metrics client, and the rails patcher.
- AppSec and AI Guard metrics: `waf.requests`, `rasp.*`, `api_security.*`,
and the WAF lifecycle metrics in `security_engine/engine.rb`.
- The trace exporter bridge: `trace_api.*` and friends in
`tracing/transport/telemetry.rb`.
- `integrations_change!` from contrib, `app_endpoints_loaded` from DI, and
`client_configuration_change!` from reconfigures and remote config.

### Coverage

| Use case | Native status |
|---|---|
| app-started, heartbeat, extended-heartbeat, app-closing | Covered. The worker emits them itself. |
| dependencies-loaded, integrations-change | Covered. `handle_add_dependency`, `handle_add_integration`. |
| Log events | Partially. `handle_add_log` has no count field for dedup batches. |
| inc, dec, gauge, rate, distribution | Covered. `dec` maps to a negative count point. |
| Tags, common flag, namespaces | Covered. Tags at registration and per point. |
| Agentless transport, api key, test token, timeout, runtime fields | Covered. Builder endpoints and `with_str_*` fields. |
| Fork | Covered. `handle_clone`. |
| On-demand `flush(timeout:)` | Not covered. Only `wait_for_shutdown` exists. |
| Heartbeat and flush intervals | Unclear. No interval setter is visible in `telemetry.h`. |

### Gap list for libdatadog

1. Post-start configuration change. `builder_with_config` runs at builder
time only. There is no `handle_add_config`. Reconfigures and remote-config
driven changes cannot be reported without it. The synth
second-`app-started` workaround also needs it.
2. `app_endpoints_loaded`. No API exists. DI depends on it.
3. Interval setters. Heartbeat, extended-heartbeat, and metrics flush
intervals must be settable through the FFI builder, at the values system
tests expect.
4. Force flush. The handle needs an on-demand flush call, for parity with
`Component#flush(timeout:)`.
5. Log dedup counts. Either a count parameter on `handle_add_log`, or
confirmation that the worker dedupes internally.
6. Exporter external handle. Let the trace exporter receive an existing
`TelemetryWorkerHandle`, so its metrics join the shared worker.

Two items are ours, not theirs. The one-`app-started` rule means the
component owns one worker across reconfigures. The pre-start event queue
stays host-side, in Ruby.

## Specification

### Configuration

New setting: `settings.telemetry.native_worker`, default `false`. It
enables the native backend for metrics and logs. When true but the native
extension is unavailable, the component logs once at debug and builds the
Ruby backend (R4).

The setting has an environment variable. The name follows the standard
naming pattern. Add it to `docs/GettingStarted.md` and run
`rake local_config_map:generate` when the setting lands.

### Backend interface

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

### Traffic map, end state

```
             metrics and logs (appsec, core, exporter observations)
subsystems -> Ruby Telemetry::Component (facade)
                      | add_point / add_log
                      v
             ONE Rust telemetry worker  ->  agent /apmtelemetry

traces -> native exporter -> agent /traces   (trace pipe, unchanged)
```

One telemetry pipe. One trace pipe. One active implementation of each.

### Behavior contract

1. Both backends produce the same wire messages (R2). The spec suite under
`spec/datadog/core/telemetry/` runs against both.
2. `NativeBackend` holds no durable state of its own. If it fails at any
point, the process continues with Ruby semantics on the next call.
3. The component selects the backend at build time, in
`core/configuration/components.rb`, next to the existing
`build_native_transport` pattern.
4. The component owns one worker instance across reconfigures, so a double
`Datadog.configure` during boot never produces a second `app-started`.

## Design

### Steps, each a two-way door

1. Seam extraction. Move `MetricsManager` and the worker behind
`RubyBackend` inside the component. No behavior change, no gate. Revert by
reverting the commit.
2. Bind the worker. Add `ext/libdatadog_api/telemetry.c`. `NativeBackend`
implements the metric and log methods on one worker. Gate it with
`native_worker`. The exporter observations keep flowing through the
existing Ruby bridge, but land in `add_point` on the worker. Revert by flag
off. Ruby answers again.
3. Lifecycle events on the worker. Enable lifecycle emission after steps 1
and 2 soak. Before this step ships, verify R9. The checks: one
`app-started` across reconfigures, heartbeat intervals at the expected
values, and a story for `app_endpoints_loaded`. That event has no native
equivalent today. Revert by flag off, back to the Ruby event layer.
4. Remove the in-process hop. This step needs a libdatadog setter that
hands an existing `TelemetryWorkerHandle` to the trace exporter config.
Until that setter ships, the hop stays. It is a cheap struct pass and FFI
call, not an HTTP round trip.

`ddog_trace_exporter_config_enable_telemetry` (a private worker inside the
exporter) exists in the vendored library. It stays out of the shipped plan
because it violates R6. It can serve as a spike or a canary, never as the
default.

### What stays in Ruby

- The public component API and the backend selection.
- The pre-start event queue.
- `app_endpoints_loaded` and the `SynthAppClientConfigurationChange` hack,
until step 3 proves them replaceable.

### C bindings

New file `ext/libdatadog_api/telemetry.c`. It follows the existing pattern
of one file per libdatadog component (see `crashtracker.c`, `ddsketch.c`,
`trace_exporter.c`). It binds the builder methods, the handle methods, and
the shutdown functions. If the build fails, the extension degrades to
`LIBDATADOG_API_FAILURE`. The component treats that as R4.

## Open questions

1. Reconfigure behavior: does one worker instance emit exactly one
`app-started` when `Datadog.configure` runs twice during boot? If the
component owns one worker, the worker source suggests yes. System tests
must confirm it.
2. Agent compatibility of the Rust worker's requests from a Ruby runtime.
Check the headers, the runtime name, the version fields, and the sequence
numbers next to the Ruby stream during rollout.

## References

- `docs/TelemetryDevelopment.md` for current component behavior.
- `lib/datadog/tracing/transport/telemetry.rb` for the current observation
bridge and its `COUNTS` metric table.
- `lib/datadog/tracing/transport/native.rb` for the native transport and
its fork and telemetry bridge patterns.
- `datadog/telemetry.h` in the vendored libdatadog 46.1 for the full native
API.
- libdd-telemetry worker source, `libdd-telemetry/src/worker/mod.rs` on
libdatadog master, for the lifecycle event behavior in this document.

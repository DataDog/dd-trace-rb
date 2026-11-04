# Native Telemetry Adoption: Proposal and Gap Analysis

Status: proposal. This document is the shared basis for dd-trace-rb and
libdatadog. The migration design that follows from it is internal to
dd-trace-rb and lives in `docs/TelemetryMigration.md`.

## Problem

The native trace exporter produces send observations on every send. Today
those observations cross into Ruby, and the Ruby telemetry component
re-serializes and ships them to the agent. Rust hands data to Ruby only so
Ruby can send it.

The end state is one host-owned Rust telemetry worker per process, created
by the Ruby component. The exporter feeds the same worker. No private
worker runs anywhere, and one switch moves the whole component.

## Proposed end state

```
             metrics and logs (appsec, core, exporter observations)
subsystems -> Ruby Telemetry::Component (facade)
                      | add_point / add_log
                      v
             ONE Rust telemetry worker  ->  agent /apmtelemetry

traces -> native exporter -> agent /traces   (trace pipe, unchanged)
```

Invariants:

1. Call sites never change. All subsystems keep the current Ruby API.
2. Exactly one telemetry emitter runs per process. Metric double counting
is a bug, not a trade-off.
3. Wire parity: the agent sees the same messages in both modes. The spec
suite and system tests are the contract, and they run against both
backends.
4. A missing native extension, or a worker that fails to start, silently
selects the Ruby implementation.
5. Every new path ships behind a default-off gate. Anyone can revert a step
by flipping the setting or reverting one commit.

## What the native worker already does

The libdd-telemetry worker emits the lifecycle events on its own schedule.
It sends `app-started` on start. It sends `app-heartbeat` with batched app
events on flush. It sends `app-extended-heartbeat` with dependencies,
integrations, and configurations. It sends `app-closing` on stop. The
`builder_run_metric_logs` flavor skips lifecycle emission.

Source: `libdd-telemetry/src/worker/mod.rs` on libdatadog master. This is
why a single worker can carry the full event layer, not only metrics and
logs.

## Coverage matrix

Each row with a gap is a work item. The owner column says which team
implements it. The blocks column says what waits for it.

| Use case | Native status | Owner | Blocks |
|---|---|---|---|
| app-started, heartbeat, extended-heartbeat, app-closing | Covered. The worker emits them. | - | - |
| Dependencies and integrations events | Covered. `handle_add_dependency`, `handle_add_integration`. | - | - |
| Metrics: inc, dec, gauge, rate, distribution | Covered. `dec` maps to a negative count point. | - | - |
| Tags, common flag, namespaces (appsec, tracers) | Covered. Tags at registration and per point. | - | - |
| Agentless transport, api key, test token, timeout, runtime fields | Covered. Builder endpoints and `with_str_*` fields. | - | - |
| Fork handling | Covered. `handle_clone`. | - | - |
| Log events with dedup counts | Partial. `handle_add_log` has no count field. | libdatadog | parity |
| On-demand flush | Missing. Only `wait_for_shutdown` exists. | libdatadog | parity |
| Post-start configuration change | Missing. `builder_with_config` runs at builder time only. | libdatadog | step 3, remote config |
| `app_endpoints_loaded` | Missing. No API exists. | libdatadog | DI |
| Heartbeat, extended-heartbeat, metrics flush intervals | Unclear. No interval setter is visible in `telemetry.h`. | libdatadog | step 3 |
| Exporter reports into a shared worker | Missing. `enable_telemetry` creates a private worker. | libdatadog | step 4 |

## Gap asks to libdatadog

P0. These gate the event migration:

1. Runtime configuration change. Add `ddog_telemetry_handle_add_config` or
an equivalent post-start API. Without it, reconfigures and remote-config
driven changes cannot be reported. The Ruby workaround for the second
`app-started` also has no replacement.
2. Interval setters. Expose heartbeat, extended-heartbeat, and metrics flush
intervals through the FFI builder. The host needs them to match the values
system tests expect.

P1. These can follow:

3. `app_endpoints_loaded`. DI depends on this event.
4. Force flush. An on-demand flush call on the handle, for parity with
`Component#flush(timeout:)`.
5. Log dedup counts. A count parameter on `handle_add_log`, or confirmation
that the worker dedupes internally.
6. Exporter external handle. Let the trace exporter receive an existing
`TelemetryWorkerHandle`, so its metrics join the shared worker instead of a
private one.

## dd-trace-rb commitments

1. The component owns one worker instance across reconfigures, so a double
`Datadog.configure` never produces a second `app-started`.
2. The pre-start event queue stays host-side, in Ruby.
3. The parity test suites run against both backends and gate every step.

## Open questions

1. Does one worker instance emit exactly one `app-started` when
`Datadog.configure` runs twice during boot? System tests must confirm it.
2. Agent compatibility of the Rust worker's requests from a Ruby runtime.
Check the headers, the runtime name, the version fields, and the sequence
numbers next to the Ruby stream during rollout.

# Telemetry migration: session progress and handoff notes

Status date: 2026-11-04. This file is local working notes; it is not part of
the PR. Delete it when the migration work is done.

Status date: 2026-11-04 (evening, before step 3). This file is local working
notes; it is not part of the PR. Delete it when the migration work is done.

## Where things stand

Branch `tonyc.t.hsu/telemetry-migration-doc`, pushed to `DataDog/dd-trace-rb`
EXCEPT the parity commit. Draft PR #6629 (label: AI Generated), base master.
Working tree is clean except this file and pre-existing untracked
`Steepfile.probe` and `review-followups.md`. PUSH PENDING: parity commit
`456f1d5eda` (backend parity spec + Rakefile registration) is committed
locally but not pushed; user consent was requested.

Commits on the branch, in order:

1. `34b42b44b4` Add telemetry migration planning document
2. `543eeb1476` Split telemetry migration doc into shared proposal and internal design
3. `d846b3b8b6` Extract RubyBackend telemetry seam (step 1 of the migration doc)
4. `e4a78d7942` Bind native telemetry worker behind native_worker setting (step 2)
5. `0e37cb82c9` Use a block for trace length sum to satisfy Steep (unrelated fix found by full typecheck)
6. `f6a894825d` Fill changelog fragment PR number
7. `456f1d5eda` Add telemetry backend parity spec (NOT pushed)

Step 1 and step 2 are done and verified. The libdatadog POC closed all
three remaining gaps (verified on the wire, see the POC verification
section). Step 3 development starts NOW on a local branch off the bindings
branch, working against the local POC build via
`LIBDATADOG_VENDOR_OVERRIDE`; shipping stays gated on the libdatadog
release + gemspec pin bump. Step 4 (remove the in-process hop) still
needs a libdatadog setter that hands an existing `TelemetryWorkerHandle`
to the trace exporter; file it as a follow-up item in the upstream POC
PR.

## Files added or changed in steps 1-2

- `ext/libdatadog_api/telemetry.c` + `telemetry.h`: bindings for the
  telemetry FFI. Registered in `init.c` under
  `Datadog::Core::Telemetry::Native::Worker` and `Native::MetricContext`.
- `lib/datadog/core/telemetry/ruby_backend.rb`: RubyBackend seam (step 1).
- `lib/datadog/core/telemetry/native_backend.rb`: NativeBackend (step 2).
- `lib/datadog/core/telemetry/component.rb`: builds events, delegates to
  `@backend`, selects the backend at build time. `log!` goes through
  `backend.add_log(event)`.
- `lib/datadog/core/telemetry/ext.rb`: `ENV_NATIVE_WORKER`.
- `lib/datadog/core/configuration/settings.rb`:
  `c.telemetry.native_worker`, default false.
- `supported-configurations.json` + regenerated
  `lib/datadog/core/configuration/supported_configurations.rb`.
- `docs/GettingStarted.md`: settings table row for
  `telemetry.native_worker`.
- `unreleased/20261104105234.json`: changelog fragment, PR number filled.
- Specs: `spec/datadog/core/telemetry/native_backend_spec.rb` (stubbed
  extension), all other telemetry specs unchanged and passing.
- Signatures: `sig/datadog/core/telemetry/{native,native_backend,`
  `ruby_backend,component,ext}.rbs`.

Gate: `DD_TELEMETRY_NATIVE_WORKER` env var or `c.telemetry.native_worker`.
Default off. Agent-based only: agentless or missing extension silently
selects RubyBackend.

## Open items for step 3

All four gaps from `docs/NativeTelemetryAdoption.md` are resolved as of
2026-11-04 evening: gaps 1, 2, 3 implemented in the libdatadog POC and
verified on the wire (see the POC verification section); gap 4 (log dedup)
verified working in vendored 46.1, no ask needed. The only remaining
upstream item is the step 4 ask: a setter handing an existing
`TelemetryWorkerHandle` to the trace exporter. File it as a follow-up
item in the upstream POC PR.

## Step 3 work plan (starting now, local branch)

Working mode: branch off the local bindings branch
`tonyc.t.hsu/telemetry-native-poc-bindings` (commit `0acd97b522`). The
extension is compiled with `LIBDATADOG_VENDOR_OVERRIDE` pointing at the
POC build. Everything is locally verifiable (specs, parity suite,
mock-agent smokes). Shipping stays gated on the libdatadog release plus
the gemspec pin bump. The C binding layer isolates any upstream
signature drift; re-verify with the parity suite after the real release.

Work items, in order:

1. One worker instance across reconfigures (`components.rb`), so a
   double `Datadog.configure` never produces a second emitter. Not
   libdatadog-dependent. About 30 minutes.
   DONE 2026-11-04 (commit `f13bf92e92` on branch
   `tonyc.t.hsu/telemetry-native-lifecycle`): `replace_components!`
   captures `old.telemetry` before building the new tree and passes it
   through `Components.new(previous_telemetry:)` -> `build_telemetry`
   -> `Component.build` -> `NativeBackend.new(previous_backend:)`.
   Adoption requires identical worker args; otherwise a fresh worker is
   built and the old one stopped. The metric context cache travels with
   the worker (Rust registers each context as a separate payload entry,
   re-registering would duplicate wire metrics). Verified: adoption
   specs + a Datadog.configure-driven reuse spec, 677 configuration
   specs, 239 native-transport specs including the parity suite, Steep
   and RuboCop clean. Rediscovered: bare `super` in a method with new
   kwargs forwards them upstream; use an explicit `super(...)`, and an
   `attr_reader` collides with a same-named private method.
2. Switch `NativeBackend` to `full_flavor: true` (`builder_run`) and
   stop lifecycle events on the Ruby event layer when native is on.
   One to two hours.
3. Integrate `_add_config` and `_add_endpoint` into the component
   (`client_configuration_change!`, `app_endpoints_loaded`), and delete
   the `SynthAppClientConfigurationChange` hack. Two to three hours
   including wire verification. Note: `handle_add_config` takes string
   values only; serialize booleans and nil at the seam.
4. Bind `add_dependency` and `add_integration`, and route
   `app-dependencies-loaded` and `app-integrations-loaded` natively.
   About two hours.
5. Decide the rate divergence (RubyBackend divides by the 10s aggregation
   interval, NativeBackend submits raw; fix at the seam means dividing
   by the effective heartbeat interval) and the fork story (children
   currently fall back to Ruby aggregation; `ponytail:` marker in
   `NativeBackend#after_fork`). About one hour for the rate fix.
6. Extend the parity suite to the new event types (config-change,
   endpoints, dependencies, integrations) so step 3 has the same gate as
   steps 1-2. About two hours.

Total: roughly two days of focused work.

## Wiring a local libdatadog prototype into dd-trace-rb

The `libdatadog` gem honors `LIBDATADOG_VENDOR_OVERRIDE` (checked in the
gem's `lib/libdatadog.rb`). The loop:

```bash
# In the libdatadog clone (prototype branch tonyc.t.hsu/telemetry-poc-46.1rb):
# --release sets PROFILE=release for the artifacts. WITHOUT it everything
# builds debug. The feature flag is MANDATORY: without it the build omits
# ddog_trace_exporter_config_enable_observations and dd-trace-rb's trace
# exporter segfaults on a NULL jump.
cargo run --release --bin release --features data-pipeline-external-observations -- --out my-libdatadog-build/arm64-darwin-25
ln -sfn arm64-darwin-25 my-libdatadog-build/arm64-darwin  # gem resolves arm64-darwin
# Result must contain include/ and lib/.

# In dd-trace-rb:
export LIBDATADOG_VENDOR_OVERRIDE=$(pwd)/../libdatadog/my-libdatadog-build/  # absolute, no platform suffix
bundle exec rake clean compile
# iterate with: bundle exec rake compile (clean not needed per iteration)
```

Unset the variable and `rake clean compile` to return to stock 46.1. The
runtime version check compares the installed gem's `Libdatadog::VERSION`
on both compile and run sides, so an override build does not trip it; keep
the same gem installed. The gemspec pin and `EXPECTED_LIBDATADOG_VERSION`
only matter when shipping.

Verification when the prototype lands, gap by gap (verify from wire
behavior, not headers):

1. Gap 4: same log twice through NativeBackend, assert one entry with
   `count: 2` in the flushed batch. Works against stock 46.1, no prototype
   needed.
2. Gap 1: exercise the new config API during a reconfigure; mock agent
   must show `app-client-configuration-change`; a double
   `Datadog.configure` must yield exactly one `app-started`.
3. Gap 2: set intervals through the new setters; assert flush cadence from
   request timestamps at the mock agent.
4. Gap 3: submit endpoints through the new API; diff the payload against
   the Ruby `AppEndpointsLoaded` event field by field.

Final instruments: the parity suite, then system tests with the flag on.

## POC verification results (2026-11-04, later)

The libdatadog POC branch `tonyc.t.hsu/telemetry-poc-46.1rb` (in
`~/datadog/libdatadog`, cherry-picked onto `origin/release/v46.1` + the
POC commit `c58cdc7e9`) implements all three remaining gap APIs. All three
gaps are now verified on the wire against the POC build:

- Gap 1, `ddog_telemetry_handle_add_config`: flushed an
  `app-client-configuration-change` payload with both entries, fields
  matching the Ruby event exactly (name, value, origin, config_id,
  seq_id).
- Gap 2, interval setters: `heartbeat_interval_seconds: 2.0` at worker
  build produced a ~2s flush cadence (3 heartbeats in 7s). The settings
  now flow from dd-trace-rb into the builder.
- Gap 3, `ddog_telemetry_handle_add_endpoint` + `ddog_EndpointData`:
  flushed an `app-endpoints` payload with full field parity to the Ruby
  event (type, method, path, operation_name, resource_name, plus null
  body/response fields).

Critical discoveries for reproducing the local build:

- The libdatadog gem 46.1.0.1.1 is built from the `release/v46.1` branch
  (origin/release/v46.1), NOT the `v46.1.0` tag. Building the POC from
  the tag segfaults the trace exporter: the vendored lib contains
  `ddog_ThreadContextHandle`, which the tag lacks.
- Local builder builds must pass
  `--features data-pipeline-external-observations`: the builder crate's
  defaults omit it, and dd-trace-rb's trace exporter calls
  `ddog_trace_exporter_config_enable_observations` unconditionally.
  Without the symbol, Ruby's lazy symbol binding turns the call into a
  NULL jump and `_native_exporter_new` segfaults.
- Build with `cargo run --release --bin release` (the `--release` flag
  sets PROFILE=release; without it everything builds debug).
- The `AddConfig` and `AddEndpoint` worker actions are ignored by the
  `run_metric_logs` flavor. They only flow through the full
  `builder_run` flavor, which is the step-3 flavor. The bindings branch
  adds a `full_flavor: true` option to `_native_new` for that spike.
- `handle_add_config` takes a string value; dd-trace-rb configuration
  values can be booleans or nil, so the seam must serialize them. Flag
  this to the libdatadog team when the ask is filed.

Local branch `tonyc.t.hsu/telemetry-native-poc-bindings` (commit
`0acd97b522`) holds the dd-trace-rb side: `_add_config`,
`_add_endpoint`, interval kwargs, and the `full_flavor` option. It
cannot compile in CI against vendored 46.1, so it stays local until a
libdatadog release ships the symbols, then it lands with step 3.

The current compiled extension in `lib/` is built against the POC; run
`bundle exec rake clean compile` without
`LIBDATADOG_VENDOR_OVERRIDE` to return to stock.

## Hard-won technical facts (do not rediscover these)

- `ddog_MaybeError` is `ddog_Option_Error`. Error when
  `tag == DDOG_OPTION_ERROR_SOME_ERROR`, message at `.some` (not `.err`).
  Drop via `read_ddogerr_string_and_drop(&result.some, ...)`.
- `ddog_Vec_Tag` passed by value transfers ownership to Rust. Do not drop
  it after `register_metric_context` or `add_point_with_tags`, not even on
  the error path. Dropping caused a segfault during shutdown.
- `ddog_telemetry_builder_run_metric_logs` consumes the builder (Rust
  takes the Box). There is no `builder_free`; if a builder setter fails
  mid-setup the builder leaks. Setters only fail on allocation.
- Endpoint: pass the agent base URL (for example
  `http://127.0.0.1:8126/`). Rust replaces the path itself:
  `/telemetry/proxy/api/v2/apmtelemetry` in agent mode,
  `/api/v2/apmtelemetry` in direct submission mode (api_key set plus
  direct submission enabled). Pass empty api_key and test_token for agent
  mode, and `false` for `use_system_resolver` (fork-safe in-process
  resolver).
- Metric contexts: register once per [type, namespace, name, common] with
  an empty tag vec; pass full tags per point through
  `add_point_with_tags`. Context keys belong to one worker instance.
  NativeBackend caches them under a string key
  `"#{type}:#{namespace}:#{name}:#{common}"` guarded by a mutex.
- dd-trace-rb call sites pass metric namespaces as strings ("tracers",
  "appsec"). The C binding takes symbols. NativeBackend converts with
  `namespace.to_sym`.
- Metric types: inc and dec both map to `:count`; dec submits a negative
  value. gauge, rate, distribution map to their own types. Distributions
  ship as sketches (`sketch_b64`), not points.
- Flush behavior of the metric_logs worker: `FlushMetricAggr` rolls points
  into buckets, `FlushData` sends a message-batch (logs,
  generate-metrics, sketches) and only sends when non-empty. `FlushData`
  runs at the heartbeat interval; on Stop the worker flushes a final
  batch. Interval defaults: heartbeat 60s, extended heartbeat 24h.
- Fork behavior: the Rust worker runs on its own spawned thread. It does
  not survive a fork. A worker rebuilt in a child (after a live worker
  existed in the parent at fork time) never flushes. A worker created
  only in the child works fine. Current decision: `after_fork` drops the
  native worker and metric and log calls fall back to the inherited Ruby
  paths (super), so fork children keep sending metrics with a fresh
  runtime_id through the Ruby layer. Marked with a `ponytail:` comment;
  revisit when libdatadog has a fork-safe telemetry worker.
- Load order trap: the `libdatadog_api` extension loads inside
  `require "datadog/core"` AFTER the requires at the top of core.rb, and
  the telemetry component files load BEFORE that. Never reference
  `Native::Worker` at Ruby file load time; reference it lazily at runtime
  (see `NativeBackend.unsupported_reason` and `start_native_worker`). Do
  not `require "datadog/core"` from telemetry files.
- Log events: `Event::Log#level` is the STRING "ERROR" or "WARN";
  `NativeBackend::LOG_LEVELS` maps it back to the `:error`/`:warn`
  symbols the C binding takes. `identifier` for `handle_add_log` is the
  message itself (dd-trace-rb messages are low-cardinality templates).
- `TypedData` classes need `rb_undef_alloc_func` to avoid the allocator
  warning.
- Steep: hash splats into required keyword arguments cannot be proven;
  `start_native_worker` carries a trailing
  `# steep:ignore InsufficientKeywordArguments`. The repo convention is a
  trailing same-line comment.
- Wire parity verified in step 2 against a mock agent: generate-metrics
  series (tags, interval, count/gauge/rate), sketches for distributions,
  logs with counts, alongside unchanged Ruby lifecycle events
  (app-started, app-dependencies-loaded, app-heartbeat).

## Proposed upstream asks (for the libdatadog prototype)

- `ddog_telemetry_handle_add_config(handle, name, value, origin,
  config_id, seq_id)` mirroring `ddog_telemetry_builder_with_config` for
  post-start configuration changes.
- Builder interval setters for heartbeat, extended heartbeat, and metrics
  flush, writing `config.telemetry_heartbeat_interval` and
  `telemetry_extended_heartbeat_interval`.
- An `app_endpoints_loaded` payload type plus a handle method; payload
  shape to be agreed with the DI team.
- Exporter external handle (P1, step 4): let the trace exporter receive an
  existing `TelemetryWorkerHandle` so its metrics join the shared worker.
  `ddog_trace_exporter_config_enable_telemetry` exists but creates a
  private worker and breaks the one-emitter invariant; use it only as a
  spike or canary.

## Environment notes

- Local Rubies: rbenv 4.0.5 (default) and 3.2.8; both have the extension
  compiled and all telemetry specs passing.
- No mise, no working docker/podman VM, so Ruby 2.6 verification was not
  possible locally. The code uses explicit kwargs only, so 2.x risk is
  low, but it is unverified.
- Tests must run via rake tasks, not bare rspec (repo rule). Telemetry
  specs: `bundle exec rake test:main` covers them; native transport specs
  need `spec:native_transport` (compiles the extension).
- cmake is installed via brew (required by the libdatadog builder).
- lldb cannot be used: macOS Developer Tools authorization was never
  approved. For crash triage, use the `.ips` crash reports under
  `~/Library/Logs/DiagnosticReports`, `objdump -d` on the bundle to map
  offsets, `otool -Iv` for stub symbol mapping, and
  `RUBY_C_BACKTRACE=1`. Note that reported `_func+N` frames come from
  the return address, so the crash is inside the CALLED function.
- libdatadog clone branches: `tonyc.t.hsu/telemetry-poc-46.1rb` is the
  GOOD POC branch (release/v46.1 base + POC commit, built with
  `--features data-pipeline-external-observations` in release profile
  into `my-libdatadog-build/`). `tonyc.t.hsu/telemetry-poc-46.1` (tag
  base) and `tonyc.t.hsu/telemetry-poc` (main base) are dead ends.
  `my-libdatadog-build-stock/` is stale (built without the
  external-observations feature); do not use it.
- The dd-trace-rb extension currently in `lib/` is compiled against the
  POC. Return to stock with `bundle exec rake clean compile` and no
  `LIBDATADOG_VENDOR_OVERRIDE`.
- Smoke scripts in `/tmp` are throwaway: `poc_full_flavor_smoke.rb`
  (full-flavor config/endpoints verification), `poc_gap_smoke.rb`
  (metric_logs + interval cadence), `dedup_smoke.rb`,
  `parity_probe.rb`, `min_trace_smoke.rb`, `lldb_trace_smoke.rb`.

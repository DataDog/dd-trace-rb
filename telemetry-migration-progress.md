# Telemetry migration: session progress and handoff notes

Status date: 2026-11-25 (after the master rebase; mid step 3). This file is
local working notes; it is not part of the PR. Delete it when the migration work is done.

## Where things stand

Branch `tonyc.t.hsu/telemetry-native-lifecycle` (local, step-3 work),
REBASED 2026-11-25 onto the rebased `tonyc.t.hsu/telemetry-native-poc-bindings`
(`b81e00aa0d`), which sits on the rebased PR branch
`tonyc.t.hsu/telemetry-migration-doc`. Everything is LOCAL ONLY: the PR
branch needs a force-push to update #6629 (consent pending), and the
step-3 branches still need the v51 libdatadog override to compile (see
the build recipe below).

Rebase details (2026-11-25): master had moved 288 commits; PR #6629 was
CONFLICTING. Conflicts were small: `sig/datadog/core/telemetry/ext.rbs`
(master switched `String` to `::String`) and
`sig/datadog/core/configuration/components.rbs` (master added data-streams
retirement fields; kept both). Semantic check passed: `replace_components!`
still captures `old.telemetry` before building the new tree. The rebased
PR branch was verified green against stock libdatadog 49: 239
native-transport + 317 telemetry specs, 0 failures.

Commits on the lifecycle branch, in order (post-rebase hashes):

1. `66c56c4bfa` Reuse the native telemetry worker across reconfigures
   (item 1 of the step-3 plan; fully verified: unit specs + a real
   Datadog.configure reuse spec + 677 configuration specs + 239
   native-transport specs + Steep/RuboCop clean)
2. `dabac70200` WIP checkpoint (user commit): the C bindings for
   dependency/integration, the full-flavor lifecycle routing, the worker
   fork-guard change, adoption specs, and an earlier version of this
   notes file

Previously-uncommitted work was checkpointed as `6641662b75` (WIP:
lifecycle on native worker, builder config feed, parity rework). The
tree is clean; that commit contains (each piece verified individually
except the parity suite, see the parity section below):

- `lib/datadog/core/telemetry/configuration_snapshot.rb` (NEW): the
  configuration-list builder extracted from `Event::AppStarted`, shared
  by the event and the native worker's builder feed.
- `lib/datadog/core/telemetry/event/app_started.rb` and
  `app_extended_heartbeat.rb`: refactored to use ConfigurationSnapshot.
- `lib/datadog/core/telemetry/native_backend.rb`: builder config feed
  (`initial_configuration` in worker args), and the Synth handle-feed
  now applying only to adopted workers.
- `ext/libdatadog_api/telemetry.c`: `initial_configuration` kwarg loop
  calling `ddog_telemetry_builder_with_config` (a stock 46.1 symbol, no
  POC needed) before `builder_run`.
- `spec/datadog/core/telemetry/backend_parity_spec.rb`: reworked, exec
  based (see the parity section below). NOT GREEN YET: the first full
  run timed out after 900 seconds and the cause is not yet diagnosed.
- `spec/datadog/core/telemetry/backend_parity_child.rb` (NEW): the
  self-contained child script for the parity suite.

PR branch `tonyc.t.hsu/telemetry-migration-doc` (PR #6629): unchanged.
Parity commit `456f1d5eda` on it is still unpushed (user consent pending).

Step 4 (remove the in-process hop) still needs a libdatadog setter that
hands an existing `TelemetryWorkerHandle` to the trace exporter; file it
as a follow-up item in the upstream POC PR.

## Step 3 status

1. Worker adoption across reconfigures: DONE (`f13bf92e92`). Facts
   worth keeping: bare `super` in a method with new kwargs forwards them
   upstream, use an explicit `super(...)`; an `attr_reader` collides
   with a same-named private method.
2. Full flavor + Ruby lifecycle stopped when native is on: DONE in code,
   wire-verified via `/tmp/poc_lifecycle_smoke.rb` (details below).
3. Config-change + endpoints on the native worker: DONE. The Synth hack
   stays for the Ruby backend. Natively a reconfigure flushes only the
   CHANGED entries (Rust dedupes exact-duplicate entries by the full
   entry key), which is better wire behavior than Ruby's full snapshot
   resend.
4. Dependency/integration bindings: DONE (`_add_dependency`,
   `_add_integration` with tri-state compatible/auto_enabled).
5. Decisions: rate divergence ACCEPTED and documented (no internal
   callers; the parity spec asserts backend-specific values 0.7 vs 7.0).
   Fork story: children fall back to full Ruby telemetry, wire-verified
   (the child's app-started carries products + install_signature).
6. Parity suite extension: IN PROGRESS, blocked on the exec-rework
   debug. See the parity section below.

### Wire verification (all green, `/tmp/poc_lifecycle_smoke.rb`)

Run with `require "datadog"` (NOT `datadog/core`: the minimal require
lacks appsec settings and AppClientConfigurationChange#payload raises on
`config.dig("appsec", ...)`, silently rescued inside enqueue). Set
DD_TELEMETRY_HEARTBEAT_INTERVAL=2 and point the agent with
`c.agent.host`/`c.agent.port` (DD_AGENT_PORT does not resolve).

Observed on the wire through the real component, all native: one
app-started (220 config entries) across a reconfigure, app-closing,
app-dependencies-loaded (23), app-integrations-change, app-heartbeat at
the configured interval, app-client-configuration-change with the
correct remote_config entry, app-endpoints with is_first,
generate-metrics, logs. A reconfigure with a changed setting flushes
exactly the one changed entry as config-change. A fork child replays a
full Ruby-shaped app-started (products + install_signature present).

Known native divergences (documented, need FFI upstream): app-started
lacks products and install_signature (no FFI), config values are
strings (booleans serialize), integrations lack the error field,
endpoints lack body/response fields, and app-dependencies-loaded is
delayed to the first heartbeat instead of following app-started
immediately.

## Parity suite: findings and current block

The parity spec runs each backend+scenario in a child process against a
capturing mock agent. Three separate problems were found while extending
it to lifecycle events:

1. An in-process THREAD agent starves: the native shutdown FFI call
   blocks the main thread holding the GVL, the agent thread cannot
   accept the worker's final POST, and the 1s shutdown cancel deadline
   kills it. Fix (in place): fork-based agent, the conformance-spec
   pattern.
2. A forked child that then BUILDS a native worker has an unreliable
   worker: the tokio runtime threads do not survive the fork, the task
   runs late (~2s or more), and the Stop-flush POST often lands after
   the shutdown cancel deadline. Nondeterministic (~4 of 9 children)
   when forked from the rspec process. Direct `_add_point` calls all
   succeed; only the flush is lost. Real applications do not hit this
   (after_fork drops the native worker), but it is worth an upstream
   issue: building the telemetry worker in a forked process is not
   fork-safe.
3. Feeding the initial configuration as ~200 `_add_config` handle
   messages before `_start` is wrong regardless: it pressures the worker
   channel and risks dropping traffic behind it. Fix (in place): feed
   `ddog_telemetry_builder_with_config` (stock 46.1 symbol) at
   construction, so app-started carries the config with no channel
   traffic. The Synth reconfigure snapshot still goes through handle
   calls, but only on an ADOPTED (already running) worker; a fresh
   worker built during a reconfigure gets the new snapshot from its own
   builder.

The suite was restructured so children are FRESH processes, not forks:
`run_child` spawns `RbConfig.ruby -I <repo>/lib
spec/datadog/core/telemetry/backend_parity_child.rb <native> <scenario>`
with DD_TELEMETRY_HEARTBEAT_INTERVAL=2 in the environment. The child
script contains the agent, the configure block, `run_scenario(name,
component)`, the sleeps, and prints the JSON report as its last stdout
line. The spec scenarios are now names (:metrics, :logs, :lifecycle).

CURRENT BLOCK: the first full run of the reworked suite TIMED OUT at
900 seconds. Not yet diagnosed. Debug entry points:

1. Run the child standalone:
   `DD_TELEMETRY_HEARTBEAT_INTERVAL=2 ruby -I lib spec/datadog/core/telemetry/backend_parity_child.rb true metrics`
   It must print one JSON line and exit within ~6 seconds. Suspects:
   `require "bundler/setup"` in the child (check the spawn environment
   carries BUNDLE_GEMFILE), the agent fork holding the stdout pipe write
   end (the parent's read only sees EOF after the agent exits, and
   agent.stop's TERM sits AFTER read_requests), or the child waiting on
   something else entirely.
2. If the child is fine standalone, time each run_child from rspec and
   find which example hangs.
3. After green: run the whole suite twice with different seeds to check
   determinism.

The lifecycle parity expectations already in the spec: config-change
entry parity (value stringified on the native side), endpoint field
parity (5 shared fields), and shared types app-started +
app-dependencies-loaded + app-closing (the native child also sends
heartbeat and integrations-change; Ruby child timing differs, so type
equality is NOT asserted).

## Remaining work for step 3

0. Retarget the C seam to v51.0.1 (deltas above: drop interval setters,
   rework _add_endpoint, Option value in _add_config), recompile with
   the v51 override, re-run the smokes.
1. Debug the parity suite exec rework (entry points above), get 18/18
   green twice with different seeds.
2. Sigs: `native_backend.rbs` (start/enqueue/flush, add_native_* helpers,
   @adopted), a NEW sig for configuration_snapshot.rb, and
   worker.rbs prepare_initial_event. Read
   `.agents/skills/write-rbs/SKILL.md` first.
3. Full verification: `bundle exec rake test:main` (telemetry specs),
   `spec:native_transport` (parity suite), standard + rubocop +
   typecheck.
4. Commits: do NOT amend the WIP commit (repo rule); add new commits on
   top. Suggested split: (a) ConfigurationSnapshot extraction, (b)
   lifecycle on the native worker (C + Ruby + specs), (c) parity suite
   lifecycle scenarios.
5. A changelog fragment when this ships (the work is behind
   DD_TELEMETRY_NATIVE_WORKER, still default-off).
6. Force-push the rebased PR branch to update #6629 (needs user
   consent).

## 2026-11-25: the libdatadog POC is superseded by upstream

PR #2872 ("expose config, product change, endpoint, flush and extended
heartbeat messages", merged as `6102b08df6`, released in v50.0.0+) plus
earlier merges give upstream `origin/main` EVERY FFI symbol our POC
branch added, verified by symbol diff. The POC branch
`tonyc.t.hsu/telemetry-poc-46.1rb` is dead; do not rebase it. All three
POC branches are deletable. Local build now comes from tag `v51.0.1`.

What upstream now has beyond our POC: `add_product_change` (closes the
products divergence), `add_endpoint` with method/operation/resource/body
types/response codes, `add_config` with an Option value (nil and "" stay
distinct), `send_extended_heartbeat`, `flush_metrics`, `flush_data`.

Upstream flavor model matches our design: `builder_run` = full flavor by
default, `builder_run_metric_logs` = metrics+logs only. No
`full_flavor` kwarg is needed upstream.

C-seam deltas vs v51.0.1 (the retarget work, BEFORE compiling against
the new build):

1. INTERVAL SETTERS DO NOT EXIST upstream. Our calls to
   `ddog_telemetry_builder_with_heartbeat_interval` and
   `..._with_extended_heartbeat_interval` must be dropped. Upstream
   `builder_instantiate` runs `Config::from_env()`, so the env vars
   `DD_TELEMETRY_HEARTBEAT_INTERVAL` and
   `DD_TELEMETRY_EXTENDED_HEARTBEAT_INTERVAL` are honored. Code-set
   intervals (`c.telemetry.heartbeat_interval = 5`) would diverge from
   the native worker: file an upstream ask for builder interval
   setters; until then document the env-only path.
2. `_add_endpoint` must be reworked to the upstream signature:
   (method: Option<Method>, path, operation_name, resource_name,
   request_body_type: Slice<CharSlice>, response_body_type:
   Slice<CharSlice>, response_code: Slice<u32>). No `kind` field, no
   EndpointData by value. Closes MORE of the endpoints divergence than
   the POC did (body types, response codes).
3. `_add_config`: upstream value is `Option<CharSlice>`; map Ruby nil
   to DDOG_OPTION_CHARSLICE_NONE instead of an empty slice.
4. `_add_dependency` / `_add_integration` / `builder_with_config` /
   full-flavor `builder_run`: exact match with our seam, no work.
5. Optional adoptions: route AppExtendedHeartbeat via
   `send_extended_heartbeat` (currently dropped), real flush via
   `flush_data` (currently `flush` returns true).

Remaining upstream gaps after v51: install_signature on app-started,
the integration `error` field, the step-4 exporter handle setter, the
fork-safety of the tokio runtime, and now the interval setters.

## Wiring a local libdatadog prototype into dd-trace-rb

The `libdatadog` gem honors `LIBDATADOG_VENDOR_OVERRIDE` (checked in the
gem's `lib/libdatadog.rb`). The loop:

```bash
# In the libdatadog clone (upstream tag v51.0.1, worktree .worktrees/v51.0.1):
# The feature was RENAMED: data-pipeline-external-observations ->
# libdd-data-pipeline-ffi/external-observations. Without it the build
# omits ddog_trace_exporter_config_enable_observations and dd-trace-rb's
# trace exporter segfaults on a NULL jump.
cargo run --release --bin release --features libdd-data-pipeline-ffi/external-observations -- --out my-libdatadog-build/arm64-darwin-25
ln -sfn arm64-darwin-25 my-libdatadog-build/arm64-darwin  # gem resolves arm64-darwin
# Result must contain include/ and lib/. Build takes ~15-25 min.

# In dd-trace-rb:
export LIBDATADOG_VENDOR_OVERRIDE=$(pwd)/../libdatadog/my-libdatadog-build/  # absolute, no platform suffix
bundle exec rake clean compile
# iterate with: bundle exec rake compile (clean not needed per iteration)
```

Unset the variable and `rake clean compile` to return to stock (49 on
master after the rebase). The
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

## Upstream asks (updated 2026-11-25; first two are now CLOSED upstream)

- DONE upstream (PR #2872, v50+): `handle_add_config`, `handle_add_endpoint`
  (with body types and response codes), `add_product_change`,
  `send_extended_heartbeat`, `flush_metrics`, `flush_data`.
- STILL OPEN: builder interval setters for heartbeat and extended
  heartbeat, writing `config.telemetry_heartbeat_interval` and
  `telemetry_extended_heartbeat_interval`. Upstream only reads the env
  vars, so code-configured intervals diverge from the native worker.
- STILL OPEN: install_signature FFI for app-started.
- STILL OPEN: the integration `error` field in `handle_add_integration`.
- STILL OPEN: fork-safety of building the telemetry worker in a forked
  process (tokio runtime threads do not survive the fork).
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
- Smoke scripts in `/tmp` are throwaway: `poc_lifecycle_smoke.rb` (the main
  step-3 wire smoke, full gem require), `poc_full_flavor_smoke.rb`
  (direct worker construction), `probe_parity_child2.rb` and
  `probe_agentproc.rb` (the parity child and the separate-process agent
  experiments). All have the FakeAgent inlined.

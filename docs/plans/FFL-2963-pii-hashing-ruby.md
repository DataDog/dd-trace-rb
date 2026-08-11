# FFL-2963 — dd-trace-rb: parse `observeFullEvaluationData` + hash `targeting_key`

Implementation plan for the Ruby SDK fan-out of the PII-hashing contract
(FFL-2780 umbrella). Pilot reference: `dd-trace-java#12042` (FFL-2790).
Contract of record: FFL-2784 (corrected by the cluster README — see
`ffe-codegen-tools/.../pii-flagevaluations-hashing/README.md`).

## Goal

Make the no-PII path the default for server-side EVP `flagevaluation` events in
`dd-trace-rb`, gated by the top-level UFC boolean `observeFullEvaluationData`:

| `observeFullEvaluationData` | `targeting_key`            | `context.evaluation` |
| --------------------------- | -------------------------- | --------------------- |
| `true`                      | raw, as-is                 | included, raw         |
| `false` / absent / null / wrong-typed (default) | `sha256_` + 64-char lowercase hex (71 chars) | omitted entirely (absent key, not `nil`, not `{}`) |

Kill switch `DD_FLAGGING_EVALUATION_COUNTS_ENABLED` (already wired) still wins
over everything and emits nothing. `DoLog` has no effect on this track.

## Architecture finding (drives the design)

Ruby's **evaluation** path goes through the libdatadog C extension
(`Core::FeatureFlags::Configuration`, `ext/libdatadog_api/feature_flags.c`).
The raw UFC JSON string arrives from Remote Config **unparsed** in Ruby
(`remote.rb#read_content` returns `content.data`) and is handed straight to
`NativeEvaluator.new(configuration)` → the C extension. Ruby never parses the
UFC.

Ruby's **writer/aggregation** path is pure Ruby (`flag_evaluation/{aggregator,writer}.rb`)
and does NOT go through libdatadog — confirmed by the FFL-2963 ticket.

Consequence: to read `observeFullEvaluationData` we must parse the consent
boolean from the raw UFC JSON string **in Ruby** at reconfigure time (the C
extension does not expose it). Hashing is in-language: `Digest::SHA256.hexdigest`
+ literal `sha256_` prefix.

Canonical vector verified locally:
`"jane.doe@datadoghq.com"` →
`sha256_b4698f9b6d186781fa8dc59e533578fa2d8379a46b1cf6db85cda6aa9c99e51b` (71 chars). ✅

## Consent lifecycle (the Java pilot's core lesson)

> Consent must travel with the evaluation, not be looked up later. No component
> downstream of the evaluator may read live config. Delete any global accessor
> so the race cannot be reintroduced.

Ruby is cleaner than Java here: there is **no global `CURRENT_CONFIG` accessor**
at all. The evaluator holds `@configuration`; the engine holds `@evaluator`;
`reconfigure!` swaps the whole evaluator atomically. So consent snapshot =
read it off the evaluator instance that holds the UFC, stamp it onto evaluation
metadata, and read it only from metadata downstream.

## Changes by file

### 1. `lib/datadog/open_feature/native_evaluator.rb` — parse consent

- In `initialize`, after building `@configuration`, parse
  `observeFullEvaluationData` from the raw UFC JSON string.
- Add `attr_reader :observe_full_evaluation_data`.
- **Lenient parse** (fail-closed on privacy without cascading to fail-closed on
  availability — Java `concern:malformed-ufc-consent-tolerance`):
  - absent / `null` / wrong-typed → `false`
  - `true` (boolean) → `true`
  - wrap in `begin/rescue JSON::ParserError → false`. Do NOT raise; the C
    extension separately owns full UFC parse and will raise `ReconfigurationError`
    on truly malformed JSON. The consent read must never be the thing that strands
    a pod on `PROVIDER_NOT_READY`.
- Use `JSON.parse(configuration)` and read `["observeFullEvaluationData"]` from
  the **top level** (sibling of `environment`), NOT from `environment`. Per the
  RFC and `ddoghq/dd-source#22826`, the field lives at the UFC root.

### 2. `lib/datadog/open_feature/noop_evaluator.rb` — consent default

- Add `def observe_full_evaluation_data; false; end` (pre-config / not-ready
  state is privacy-preserving default).

### 3. `lib/datadog/open_feature/evaluation_engine.rb` — expose consent

- Add `def observe_full_evaluation_data; @evaluator.observe_full_evaluation_data; end`.
- In `fetch_value`, stamp consent onto the returned result's `flag_metadata`
  using the **same `@evaluator` local** used for `get_assignment` (bulletproof
  against a mid-eval `reconfigure!` swap):
  ```ruby
  evaluator = @evaluator
  result = evaluator.get_assignment(...)
  result.flag_metadata = (result.flag_metadata || {}).merge(
    Ext::METADATA_OBSERVE_FULL_EVALUATION_DATA => evaluator.observe_full_evaluation_data
  ) if result.respond_to?(:flag_metadata=)
  ```
  - Note: the C extension `ResolutionDetails#flag_metadata` returns a fresh Hash
    per call and has no setter; the Ruby `ResolutionDetails` is a Struct with a
    writer. For C-extension results, stamping may need to go via the provider
    (see step 4). **Decide during implementation**: if the C result's metadata
    hash is not stably mutable, fall back to stamping in the provider from
    `engine.observe_full_evaluation_data` (residual race is negligible under
    MRI GIL + rare reconfigure; the key Java invariant — no global accessor —
    is already satisfied).

### 4. `lib/datadog/open_feature/provider.rb` — stamp consent into metadata

- In `evaluate`, after `build_flag_metadata(result, eval_time_ms)`, add:
  ```ruby
  flag_meta[Ext::METADATA_OBSERVE_FULL_EVALUATION_DATA] =
    engine&.observe_full_evaluation_data || false
  ```
  (`engine = OpenFeature.engine` is already in scope.)
- `build_flag_metadata` already does `result.flag_metadata&.dup || {}`, so any
  consent stamped in step 3 is preserved; step 4 is the authoritative stamp if
  step 3 can't mutate the C result.

### 5. `lib/datadog/open_feature/ext.rb` — new constant

- `METADATA_OBSERVE_FULL_EVALUATION_DATA = "observe_full_evaluation_data"`
  (unprefixed, snake_case — the cross-SDK contract key, confirmed by Vickie
  2026-07-30).

### 6. `lib/datadog/open_feature/hooks/flag_eval_evp_hook.rb` — read consent, skip context

- In `finally`, read consent:
  ```ruby
  metadata = evaluation_details.flag_metadata
  consent = metadata.is_a?(Hash) ? metadata[Ext::METADATA_OBSERVE_FULL_EVALUATION_DATA] : nil
  consent = false unless consent == true   # absent/nil/false/wrong → false
  ```
- **Skip context capture on the hot path when consent off** (Java
  `concern:consent-off-bucket-keying` optimization): when `consent` is false,
  pass `attrs: {}` (do not call `extract_attributes`). Context is omitted on
  emit, so no copy work.
- Capture `error_code` alongside `error_message` (for the `error.message`
  redaction rule in step 8). `evaluation_details` already responds to
  `error_code` (used by `runtime_default?`).
- Pass `observe_full_evaluation_data:` and `error_code:` through `writer.enqueue`.

### 7. `lib/datadog/open_feature/flag_evaluation/aggregator.rb` — consent in bucket key

- `record` gains `observe_full_evaluation_data:` keyword (Boolean, default false).
- **Bucket key changes** (Java `concern:consent-in-bucket-key` +
  `concern:consent-off-bucket-keying`):
  - consent **on**: `full_key = [flag_key, variant, allocation_key, runtime_default, error_message, targeting_key, context_key, true]`; store `context_attrs`.
  - consent **off**: `full_key = [flag_key, variant, allocation_key, runtime_default, error_message, targeting_key, false]` — **drop `context_key`** and **do not store `context_attrs`** (the context dimension is discarded at serialization, so keying on it would burn the per-flag bucket cap on privacy-protected traffic).
  - `degraded_key` gains a consent element too (defense-in-depth, matching Java), though degraded buckets omit PII fields either way.
- Store `observe_full_evaluation_data` on the entry so the writer can read it
  at serialization (or read it from the key in `build_events`).
- Keep the AND-fold defense: when reading consent from the entry, AND-fold with
  the key's consent element in case they drift.

### 8. `lib/datadog/open_feature/flag_evaluation/writer.rb` — serialize per consent

- `enqueue` gains `observe_full_evaluation_data:` and `error_code:` keywords;
  thread both into the bounded event and through `drain_queue` →
  `aggregator.record`.
- `build_events` / `build_event`:
  - consent **off**: `targeting_key` → `"sha256_" + Digest::SHA256.hexdigest(targeting_key)`;
    omit `context` entirely (already absent because `context_attrs` not stored);
    **redact `error.message`** (Java `concern:error-message-carries-pii`): emit
    `error.message` = `error_code` string when an error is present (stable
    signal, no raw context), or omit `error` if no error code. Do NOT emit the
    raw `error_message`.
  - consent **on**: raw `targeting_key`, full `context.evaluation`, raw `error.message`.
- `require "digest"` at top.
- **Pre-queue capacity check before copy** (cross-SDK memory-boundedness
  contract): in `enqueue`, before `snapshot_context_value`, check
  `@queue.size >= QUEUE_SIZE` → drop + increment a pre-queue overflow counter
  (O(1), no copy work). Keep the existing `ThreadError` rescue as the
  enqueue-drop (race) counter. Three telemetry signals:
  1. pre-queue overflow (queue full before copy)
  2. context-truncated with reason label (existing `prune_context` skips — add a
     reason tag identifying which cap: `max_context_fields` / `max_field_length`)
  3. enqueue-drop (existing `dropped_queue_overflow`)
  - Note: the existing Ruby design prunes context in the **background** writer
    (`record`), not on the eval thread. The cross-SDK contract wants full
    pruning **before the async queue, on the evaluation thread**. The current
    `snapshot_context_value` only does a depth-capped deep dup. **Aligning this
    fully is a larger refactor**; for FFL-2963, ensure the pre-queue check is in
    place and tag the existing pruning with reasons. Flag the eval-thread
    pruning gap explicitly in the PR if not fully closed.

### 9. RBS signatures — update in lockstep (repo typechecks in CI)

- `sig/datadog/open_feature/native_evaluator.rbs`: add
  `attr_reader observe_full_evaluation_data: bool` and `@observe_full_evaluation_data: bool`.
- `sig/datadog/open_feature/noop_evaluator.rbs`: add
  `def observe_full_evaluation_data: () -> false`.
- `sig/datadog/open_feature/evaluation_engine.rbs`: add
  `def observe_full_evaluation_data: () -> bool`.
- `sig/datadog/open_feature/hooks/flag_eval_evp_hook.rbs`: update `finally`
  signature; add private `extract_error_code`.
- `sig/datadog/open_feature/flag_evaluation/aggregator.rbs`: update `record`
  signature with `observe_full_evaluation_data: bool`; update key/entry shapes.
- `sig/datadog/open_feature/flag_evaluation/writer.rbs`: update `enqueue`,
  `drain_queue`, `build_events`, `build_event` signatures.
- `sig/datadog/open_feature/ext.rbs`: add `METADATA_OBSERVE_FULL_EVALUATION_DATA`.

## Tests (L1)

All under `spec/datadog/open_feature/`. Assert on **raw wire bytes** — the hash
is present AND the raw subject string appears nowhere in the payload.

- `flag_evaluation/aggregator_spec.rb`:
  - consent off → bucket key excludes context dimension; mixed-consent
    evaluations land in distinct buckets; context_attrs not stored.
  - consent on → context in key; context_attrs stored.
- `flag_evaluation/writer_spec.rb`:
  - canonical vector: `"jane.doe@datadoghq.com"` →
    `sha256_b4698f9b6d186781fa8dc59e533578fa2d8379a46b1cf6db85cda6aa9c99e51b`.
  - consent off → `targeting_key` hashed, `context` absent (not `nil`, not `{}`),
    raw subject string nowhere in payload (negative wire assertion).
  - consent on → raw `targeting_key` + full `context.evaluation`.
  - consent off + error → `error.message` carries only the error code, never raw
    context (negative wire assertion for `error.message` PII).
  - kill switch off → no events.
- `hooks/flag_eval_evp_hook_spec.rb`:
  - reads consent from metadata, not live config; `ignoresGatewayConsentEvenWhenItDisagreesWithMetadata`
    regression guard (Java's whole point).
  - skips attrs capture when consent off.
- `native_evaluator_spec.rb` / `evaluation_engine_spec.rb`:
  - UFC absent / `false` / `true` / explicit `null` / wrong-typed → consent
    false/false/true/false/false; malformed JSON → false (no raise).
  - `observeFullEvaluationData` read from UFC **root**, not `environment`.
- `DoLog` non-impact proof: assignments emit the same hashed/unhashed shape
  regardless of `DoLog`.

## L3 caveat (read before starting)

`system-tests/manifests/ruby.yml` line ~1991 gates the whole of
`tests/ffe/test_flag_eval_evp.py` as `missing_feature (FFL-2446)` even though
the base track merged 2026-06-30. **Ruby's PII tests stay dark unless that
file-level gate is addressed.** Either activate the file as part of this ticket
(flip to `missing_feature (FFL-2784)` for the three `ObserveFullData` rows, like
Go), or state explicitly in the PR that L3 did not run and why. Landing PII with
no contract test running is the failure mode to avoid. Coordinate with
system-tests (FFL-2783); the merged `system-tests#7316` already carries the
three `Test_FFE_EVP_Flagevaluation_ObserveFullData_*` tests.

## L2

`ffe-dogfooding` `apps/ruby`, per
`references/knowledge/playbooks/ffe-dogfooding-evp-pup-validation.md`.

## Validation order

1. L1 unit tests (above).
2. `bundle exec rake standard typecheck` (RBS + Standard).
3. `bundle exec rake test:main` for the open_feature specs.
4. L3: address the manifest gate, then run
   `tests/ffe/test_flag_eval_evp.py::Test_FFE_EVP_Flagevaluation_ObserveFullData_*`
   locally against a Ruby weblog.
5. L2 dogfooding.

## Open decisions for this PR

- **Where consent is stamped** (step 3 vs step 4): confirm whether the C
  extension `ResolutionDetails#flag_metadata` hash is stably mutable. If not,
  stamp authoritatively in the provider (step 4) and document the negligible
  residual race.
- **`error.message` redaction shape**: substitute `error_code` (Java approach,
  keeps operator signal) vs omit `error` entirely. Recommend substitute to
  match Java and keep the signal.
- **Eval-thread context pruning**: the cross-SDK contract wants full pruning
  before the async queue; the current Ruby design prunes in the background.
  Decide whether to close this fully in FFL-2963 or flag it as a follow-up.

## Lessons to contribute back

After landing, contribute lessons to `DataDog/ffe-codegen-tools` (per ticket):
- Ruby's evaluator is libdatadog (C extension); consent must be parsed in Ruby
  from the raw UFC JSON at reconfigure time. No global accessor exists, so the
  Java consent-lifecycle race is structurally simpler here.
- `error.message` redaction and the UFC-root (not `environment`) placement are
  the two contract details most likely to be missed.
- The `manifests/ruby.yml` file-level `missing_feature (FFL-2446)` gate is a
  pre-existing L3 gap independent of PII; resolve before layering PII.

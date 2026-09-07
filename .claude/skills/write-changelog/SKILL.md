---
name: write-changelog
description: 'Use when a change in this repo needs a customer-facing changelog entry — e.g. "add a changelog entry", "this needs a changelog fragment", or when an approved PR that changes user-visible behavior in lib/, ext/, or docs/GettingStarted.md is about to merge. Enforces dd-trace-rb changelog fragment conventions.'
---

# Writing changelog fragments

READ `unreleased/README.md` FIRST — it documents the fragment system. This
skill covers how to do the work.

Invoke when the PR is complete and approved, right before merging: the
diff is final, so grounding and triage see the complete change. A fragment
written earlier must be re-grounded against the final diff.

## Grounding

The core principle: a fragment states what the diff makes true; every
claim traces to the diff, NEVER to memory — lint and vale check form only,
so grounding falls to the author and reviewer alone.

Read the diff and triage first; the answers drive every later step:

- Effect: what does this PR make true when it lands? If the effect arrives
  only in a later change (groundwork, flag plumbed but off), there is
  nothing to write yet
- Count: one change or several distinct effects? Several → ASK the user
  before writing several fragments — exceptional, and the count is the
  user's call
- Product: which product each effect belongs to — by effect, not code
  location (a core fix to a profiler crash is Profiling); diffuse
  core-wide → `Core`. Closed list: `ReleasePrep::Fragment::PREFIXES`
  (`tasks/release_prep/fragment.rb`); the integration name (Redis) goes
  in the `message`, not the `prefix`
- Type: `Added` (new capability), `Changed` (behavior change), `Fixed`
  (bug fix)

Then keep every written claim grounded:

- Verify identifiers (settings, classes, methods, env vars, gems) against
  the hunks, not recalled conventions
- Verify versions against the diff (gemspec, Matrixfile, CI), not
  ecosystem memory
- Verify behavior against the diff's tests — no test, no behavioral claim
- A claim that traces to nothing is dropped or weakened, never hedged

## Deciding

- Add: new features, behavior changes, customer-affecting bug fixes — one
  fragment per customer-visible change, never a catch-all tail ("and more",
  "etc.")

  ```markdown
  <!-- Bad: two effects bundled behind "and more" -->
  Add support for Bundler deployment mode, report UI-oriented injection results, and more.

  <!-- Good: one effect stated whole; the PR's other effects each get their own fragment -->
  Add support for Bundler deployment mode.
  ```
- Never add: internal refactors, test-only, CI/tooling, docs outside
  `docs/GettingStarted.md`
- When unsure, add — a reviewer can delete an entry; a missing one leaves
  customers unaware

## Creating the fragment

1. No PR yet → open a draft first; `pull_request` needs a real number, and
   nothing checks it mechanically
2. PR already has a fragment for this change → update it, don't add
   another; fragments for other changes stay untouched
3. Copy the closest template from `unreleased/examples/` — never a blank
   file:

   ```bash
   cp unreleased/examples/basic.json "unreleased/$(date -u +%Y%m%d%H%M%S).json"
   ```

4. Omit `author` unless writing for an external contributor, to their
   GitHub handle

## Writing the message

Run `unreleased:lint` while drafting; the judgment below is what it and
vale cannot check, in drafting order. Each rule carries a minimal pair in
a fenced block: the bad entry is the good one with exactly the violation.

- Structure by type — the reader's question differs:
  - `Fixed`: the symptom they recognize → the trigger

    ```markdown
    <!-- Bad: symptom without the trigger -->
    Fix `ArgumentError` in `pg` instrumentation.

    <!-- Good: symptom + trigger -->
    Fix `pg` instrumentation which raised `ArgumentError` when calling `exec_params`, `exec_prepared` without a `params` argument, or their `async_`/`sync_` variants.
    ```

  - `Added`: the capability → the access point, the setting/API that gets it for them

    ```markdown
    <!-- Bad: capability without the access point -->
    Add flag evaluation metrics.

    <!-- Good: capability + access point -->
    Add flag evaluation metrics, collected via OpenTelemetry.
    ```

  - `Changed`: the new behavior → the action or escape hatch

    ```markdown
    <!-- Bad: new behavior without the action -->
    Deprecate `time_now_provider`.

    <!-- Good: new behavior + action + why it is safe -->
    Deprecate the `time_now_provider` setting for removal; it no longer has an effect. Remove it from your `Datadog.configure` block. The gem always uses real time, even when the `timecop` gem monkey-patches `Time`.
    ```

- For a customer, not the diff: what changed and why it matters to a gem
  user; no code-review jargon ("refactored", "cleaned up") or internal
  file names; match existing `CHANGELOG.md` entries

  ```markdown
  <!-- Bad: internal description — jargon, file name, no user-visible claim -->
  Refactored peer_tags.rb in the tracer to fix the nil case in Tags#populate.

  <!-- Good: customer framing, grounded, code spans -->
  Fix missing peer tags for database queries traced through `ActiveRecord`.
  ```

- Start with an imperative verb (Add, Fix, Support, Improve, ...) — CI
  rejects "This PR fixes...", "The gem now supports...", "Also fixes..."

  ```markdown
  <!-- Bad: the PR is the subject -->
  This PR adds support for `Resque`.

  <!-- Good: imperative verb, the change is the subject -->
  Add support for `Resque`.
  ```

- Wrap identifiers (`DD_...` env vars, snake_case, CONSTANT_CASE,
  `Foo.bar`) in code spans; never plain English — code spans name
  identifiers, they are not emphasis

  ```markdown
  <!-- Bad: identifier in plain text -->
  Set DD_TRACE_ENABLED to 1.

  <!-- Good: identifier in a code span -->
  Set `DD_TRACE_ENABLED=1`.
  ```

- Never repeat the prefix verbatim — with prefix `AppSec`, "Add AppSec
  detection..." says it twice; lowercase technical phrasing ("GC
  profiling") is fine

  ```markdown
  <!-- Bad: the prefix said twice -->
  Add AppSec detection of response splitting.

  <!-- Good: the prefix already renders beside the entry -->
  Add detection of response splitting.
  ```

- No PR references in the message — the number renders from
  `pull_request` automatically

  ```markdown
  <!-- Bad: PR reference in the message -->
  Fixes #4821 by hardening the transport against dropped payloads.

  <!-- Good: no reference; the number renders from `pull_request` -->
  Harden the transport against dropped payloads.
  ```

- Exact versions and platforms, never "recent" or "newer"

  ```markdown
  <!-- Bad: vague version -->
  Fix GC profiling being incorrectly disabled on recent Ruby versions.

  <!-- Good: patch-level versions -->
  Fix GC profiling being incorrectly disabled on Ruby 3.2.10 and 3.2.11.
  ```

- Performance claims need numbers from the diff; unmeasured stays
  directional, never "significantly improve"

  ```markdown
  <!-- Bad: unmeasured vague quantifier -->
  Improve profiler performance significantly.

  <!-- Good: measured number plus mechanism -->
  Reduce profiler overhead by up to 50% by skipping redundant samples for threads without the GVL.
  ```

## Before finishing

Re-read and revise until every item holds:

- Every claim visible in the diff
- Reads as written for a customer
- `Fixed` names the symptom; `Added` the access point; `Changed` the
  escape hatch
- No vague quantifiers or catch-all tails
- Identifiers in code spans; no verbatim prefix; no PR references
- `bundle exec rake unreleased:lint` and `unreleased:render` pass

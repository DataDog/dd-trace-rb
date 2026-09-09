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
  core-wide → `Core`. Closed list: `ReleasePrep::Fragment::PRODUCTS`
  (`tasks/release_prep/fragment.rb`); the integration name (Redis) goes
  in the `message`, not the `product`
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
3. Generate the scaffold — never a blank file:

   ```bash
   bundle exec rake unreleased:new
   ```

   The placeholders name what each field needs; filled-in references live
   in `unreleased/examples/`.

4. Omit `author` unless writing for an external contributor, to their
   `@`-prefixed GitHub handle

## Writing the message

Run `unreleased:lint` while drafting; the judgment below is what it and
vale cannot check, in drafting order. Each rule carries a minimal pair in
a fenced block: the bad entry is the good one with exactly the violation.

- Structure by type — the reader's question differs:
  - `Fixed`: the symptom they recognize → the trigger — but the trigger
    only when the customer can perform or observe it (a call they make, a
    setting they use); an unobservable race bottoms out at "a rare race",
    never internal sequencing

    ```markdown
    <!-- Bad: the implementation — no symptom, no trigger -->
    Ignore `SignalException` from crashtracker as unhandled exception errors.

    <!-- Good: the symptom they recognize + the trigger they perform -->
    Fix false unhandled-exception crash reports in Error Tracking: `SIGTERM` and other `SignalException`s raised while the process stops — every rolling deploy, scale-in, or pod eviction — are no longer reported as crashes.
    ```

  - `Added`: the capability → the access point, the setting/API that gets it for them

    ```markdown
    <!-- Bad: the setting named vaguely — no access point the customer can find -->
    Add experimental profiling setting to show class/module names in stack frames.

    <!-- Good: capability + example of what you get + the exact access point -->
    Show class and module names in profiler stack frames (`Foo::Bar#baz` instead of `baz`), making hot methods easier to identify; enable it with `DD_PROFILING_EXPERIMENTAL_SHOW_CLASSES_ENABLED=true`.
    ```

  - `Changed`: the new behavior → why it matters, or the action/escape hatch

    ```markdown
    <!-- Bad: the flip stated, but not why it matters, and no way back -->
    Change default logger output from stdout to stderr.

    <!-- Good: new behavior + why it matters + escape hatch -->
    Move the gem's diagnostic logs from stdout to stderr, so stdout stays clean for application output; restore the old default with `c.logger.instance = Logger.new($stdout)` in `Datadog.configure`.
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

- The first sentence carries the customer effect — what they observe,
  do, or get — never the gem's mechanics; those follow, never lead

  ```markdown
  <!-- Bad: the mechanism enforced; the customer's delta never appears -->
  Enforce process-wide rate limit across all probes.

  <!-- Good: the customer's observable delta leads, the numbers follow -->
  Cap probe output process-wide: with multiple probes set, they can emit less than their individual limits allow — 20 snapshots/s, 5000 log events/s.
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

- Never repeat the product verbatim — with product `AppSec`, "Add AppSec
  detection..." says it twice; lowercase technical phrasing ("GC
  profiling") is fine

  ```markdown
  <!-- Bad: the product said twice -->
  Add AppSec detection of response splitting.

  <!-- Good: the product already renders beside the entry -->
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

Re-read the message; revise until every item holds:

- Every claim visible in the diff
- Written for a customer
- Lead states the customer effect, not the gem's mechanics
- Terse — every word earns its place
- `Fixed` symptom; `Added` access point; `Changed` consequence or escape hatch
- No vague quantifiers or catch-all tails
- Identifiers in code spans; no verbatim product; no PR references
- `unreleased:lint` and `unreleased:render` pass

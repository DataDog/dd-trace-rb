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

## The customer

Every message targets one reader: a Ruby developer using this gem in
their application, scanning `CHANGELOG.md` to decide whether an upgrade
affects them. They read for what changes in their application — what
they observe, do, or get — never for the gem's internals. The exact
version they run is their context; their time is short.

## Core principles

- ALWAYS ground every claim in the diff — NEVER in memory
- ALWAYS write for the customer, not the diff
- ALWAYS lead with the customer effect; supporting detail follows,
  NEVER leads, and only to scope who is affected (versions, platforms,
  triggers, workloads) — NEVER implementation narrative
- ALWAYS stay terse — every word earns its place
- `Fixed` names the symptom; `Added` names the access point; `Changed`
  names the consequence or escape hatch
- ALWAYS name exact versions and measured numbers; NEVER vague
  quantifiers ("significantly", "recent") or catch-all tails ("and more")
- ALWAYS wrap identifiers in code spans; NEVER repeat the product
  verbatim or reference the PR in the message

Lint and vale check form only; these principles fall to the author and
reviewer alone.

## Grounding

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
  (`tasks/lib/release_prep/fragment.rb`); the integration name (Redis) goes
  in the `message`, not the `product`
- Type: `Added` (new capability), `Changed` (behavior change), `Fixed`
  (bug fix)

Then keep every written claim grounded:

- Verify identifiers (settings, classes, methods, env vars, gems) against
  the hunks, not recalled conventions
- Verify versions against the diff (gemspec, Matrixfile, CI), not
  ecosystem memory
- Verify behavior against the diff's tests — no test, no behavioral claim
- ALWAYS drop or weaken a claim that traces to nothing; NEVER hedge it

## Deciding

- ALWAYS add a fragment for new features, behavior changes, and
  customer-affecting bug fixes — one fragment per customer-visible change

  ```markdown
  <!-- Bad: several effects bundled behind "and more" -->
  Add support for Bundler deployment mode, report UI-oriented injection results, and more.

  <!-- Good: one effect stated whole; the PR's other effects each get their own fragment -->
  Add support for Bundler deployment mode.
  ```
- NEVER add a fragment for internal refactors, test-only, CI/tooling, or
  docs outside `docs/GettingStarted.md`
- SHOULD add when unsure — a reviewer can delete an entry; a missing one
  leaves customers unaware

## Creating the fragment

- ALWAYS write against a real PR number; with no PR yet, open a draft
  first — nothing checks the number mechanically
- ALWAYS update the existing fragment for this change; NEVER add a second
  one. Fragments for other changes stay untouched
- ALWAYS generate the scaffold with `bundle exec rake unreleased:new`;
  NEVER create a blank file by hand

  The placeholders name what each field needs; filled-in references live
  in `unreleased/examples/`.

- ALWAYS set `author` to the external contributor's `@`-prefixed GitHub
  handle; NEVER set `author` for a Datadog contributor

## Writing the message

Run `unreleased:lint` while drafting; the judgment below is what it and
vale cannot check, in drafting order. Each rule carries a minimal pair in
a fenced block: the bad entry is the good one with exactly the violation.

- Structure by type — the reader's question differs:
  - `Fixed`: ALWAYS name the symptom they recognize, then the trigger
    they can perform or observe (a call they make, a setting they use);
    when nothing is observable, bottom out at "a rare race" — NEVER
    internal sequencing

    ```markdown
    <!-- Bad: the trigger named, but no symptom to recognize -->
    Fix `Process.spawn` when passing an environment Hash.

    <!-- Good: the symptom they recognize + the trigger they perform -->
    Fix `TypeError` from `Process.spawn` when passing an environment Hash.
    ```

  - `Added`: ALWAYS name the capability, then the access point — the
    setting/API that gets it for them

    ```markdown
    <!-- Bad: the setting named vaguely — no access point the customer can find -->
    Add experimental profiling setting to show class/module names in stack frames.

    <!-- Good: capability + example of what you get + the exact access point -->
    Show class and module names in profiler stack frames (`Foo::Bar#baz` instead of `baz`), making hot methods easier to identify; enable it with `DD_PROFILING_EXPERIMENTAL_SHOW_CLASSES_ENABLED=true`.
    ```

  - `Changed`: ALWAYS name the new behavior, then why it matters, or the
    action/escape hatch

    ```markdown
    <!-- Bad: the flip stated, but not why it matters, and no way back -->
    Change default logger output from stdout to stderr.

    <!-- Good: new behavior + why it matters + escape hatch -->
    Move the gem's diagnostic logs from stdout to stderr, so stdout stays clean for application output; restore the old default with `c.logger.instance = Datadog::Core::Logger.new($stdout)` in `Datadog.configure`.
    ```

- ALWAYS state what changed and why it matters to the customer; NEVER
  code-review jargon ("refactored", "cleaned up") or internal file names.

  ```markdown
  <!-- Bad: internal description — jargon, file name, no user-visible claim -->
  Set `Tracing::Metadata::Ext::TAG_KIND` on spans in the ActiveRecord `sql` event handler (`events/sql.rb`).

  <!-- Good: customer framing, grounded, code spans -->
  Fix missing peer tags for database queries traced through `ActiveRecord`.
  ```

- ALWAYS start with an imperative verb (Add, Fix, Support, Improve, ...) —
  CI rejects "This PR fixes...", "The gem now supports...", "Also fixes..."

- ALWAYS open the first sentence with the customer effect — what they
  observe, do, or get; supporting detail follows, NEVER leads, and only
  to scope who is affected — NEVER implementation narrative

  ```markdown
  <!-- Bad: the mechanism enforced; the customer's delta never appears -->
  Enforce process-wide rate limit across all probes.

  <!-- Good: the customer's observable delta leads, the numbers follow -->
  Cap probe output process-wide: with multiple probes set, they can emit less than their individual limits allow — combined output is capped at 20 snapshots/s and 5000 log events/s per process.
  ```

- ALWAYS wrap identifiers (`DD_...` env vars, snake_case, CONSTANT_CASE,
  `Foo.bar`) in code spans — code spans name identifiers, they are not
  emphasis

  ```markdown
  <!-- Bad: identifier in plain text -->
  Set DD_TRACE_ENABLED to 1.

  <!-- Good: identifier in a code span -->
  Set `DD_TRACE_ENABLED=1`.
  ```

- NEVER repeat the product verbatim — with product `AppSec`, "Add AppSec
  detection..." says it twice; lowercase technical phrasing ("GC
  profiling") is fine

  ```markdown
  <!-- Bad: the product said twice -->
  Add AppSec detection of response splitting.

  <!-- Good: the product already renders beside the entry -->
  Add detection of response splitting.
  ```

- NEVER reference the PR in the message — the number renders from
  `pull_request` automatically

  ```markdown
  <!-- Bad: PR reference in the message -->
  Fixes #4821 by hardening the transport against dropped payloads.

  <!-- Good: no reference; the number renders from `pull_request` -->
  Harden the transport against dropped payloads.
  ```

- ALWAYS name exact versions and platforms — NEVER "recent" or "newer"

  ```markdown
  <!-- Bad: vague version -->
  Fix a `SIGSEGV` crash that could happen with experimental heap profiling enabled on recent Ruby versions.

  <!-- Good: exact version -->
  Fix a `SIGSEGV` crash that could happen with experimental heap profiling enabled on Ruby 4.0.
  ```

- ALWAYS back performance claims with numbers from the diff; unmeasured
  claims stay directional — NEVER "significantly improve"

  ```markdown
  <!-- Bad: unmeasured vague quantifier -->
  Improve profiler performance significantly.

  <!-- Good: measured number plus the scope that decides who benefits -->
  Reduce profiler overhead by up to 50% for applications with many idle or blocked threads by skipping samples of threads that stay suspended between ticks; skipped threads are still reported each period.
  ```

## Finishing loop

Run the three steps in order; ANY revision restarts the loop from step 1.
Done when a pass makes no revision:

1. `bundle exec rake unreleased:lint` — fix every reported violation
2. `bundle exec rake unreleased:render` — re-read the rendered entry
   against the Core principles and revise
3. Re-read the message against the diff — drop or weaken every claim not
   visible there

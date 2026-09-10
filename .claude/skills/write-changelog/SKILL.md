---
name: write-changelog
description: 'Use when a change in this repo needs a customer-facing changelog entry — e.g. "add a changelog entry" — or when an approved PR that changes user-visible behavior in lib/, ext/, or docs/GettingStarted.md is about to merge.'
---

# Writing changelog fragments

READ `unreleased/README.md` FIRST — it is the human-facing description of
the fragment system and its fields. This skill is the agent-facing
checklist.

A fragment may be written as soon as the PR exists, but its grounding is
only final when the diff is: re-ground the message against the final
diff when the PR is complete and approved, right before merging —
grounding and triage see the complete change only there.

## The customer

Every message targets one reader: a Ruby developer using this gem in
their application, scanning `CHANGELOG.md` to decide whether an upgrade
affects them. They read for what changes in their application — what
they observe, do, or get. The exact version they run is their context.

## Core principles

- ALWAYS write for the customer, not the diff
- ALWAYS lead with the customer effect; supporting detail follows
- ALWAYS scope who is affected — versions, platforms, triggers, workloads
  — whenever the scope decides it
- NEVER narrate the implementation
  Scope names what the customer runs; narrative names what the code does

## Grounding

Read the diff and triage first; the answers drive every later step:

- Effect: what does this PR make true when it lands? If the effect arrives
  only in a later change (groundwork, flag plumbed but off), there is
  nothing to write yet
- Count: one change or several distinct effects? Several → ASK the user
  to confirm the split before writing several fragments; NEVER bundle
  several effects into one

  ```markdown
  <!-- Bad: two effects bundled into one fragment -->
  Add support for Bundler deployment mode (`bundle install --deployment`) and report UI-oriented injection results.

  <!-- Good: one effect stated whole; the PR's other effects each get their own fragment -->
  Add support for Bundler deployment mode (`bundle install --deployment`).
  ```

- Product: which product each effect belongs to — by effect, not code
  location (a core fix to a profiler crash is Profiling); diffuse
  core-wide → `Core`. Closed list: `ReleasePrep::Fragment::PRODUCTS`
  (`tasks/lib/release_prep/fragment.rb`); the integration name (Redis) goes
  in the `message`, not the `product`
- Type: `Added` (new capability), `Changed` (behavior change), `Fixed`
  (bug fix); performance changes are `Changed`, or `Fixed` when they
  restore performance an earlier version had

Then keep every written claim grounded:

- Verify identifiers (settings, classes, methods, env vars, gems) against
  the hunks, not recalled conventions
- Verify versions against the diff (gemspec, Matrixfile, CI), not
  ecosystem memory
- Measured numbers: the diff, its benchmark output, or the author's
  reported result — a benchmark's output often lives only in the PR; no
  source there, and the claim stays directional
- Verify behavior against the diff's tests — no test, no behavioral claim
- A reproducible defect with no test: ASK the PR to add the test; the
  behavioral claim waits for it
- A PR that merges without the test grounds its entry in what inspection
  establishes — the claim caps there, and the review thread notes the
  missing test
- When a deterministic test cannot reproduce the defect — it depends on
  timing or uncontrolled external state — verification falls back to
  inspection: the change the diff adds is the evidence, and the message
  claims no more than it establishes
- ALWAYS drop or weaken a claim that traces to nothing; NEVER hedge it

## Deciding

- ALWAYS add a fragment for new features, behavior changes, and
  customer-affecting bug fixes
- NEVER add a fragment for internal refactors, test-only, CI/tooling, or
  docs outside `docs/GettingStarted.md`
- SHOULD add when unsure — a reviewer can delete an entry; a missing one
  leaves customers unaware

## Creating the fragment

- ALWAYS write against a real PR number; with no PR yet, open a draft
  first — nothing checks the number mechanically
- ALWAYS update the existing fragment for this effect; NEVER add a second
  one for the same effect. Fragments for other effects stay untouched
- ALWAYS generate the scaffold with `bundle exec rake unreleased:new`;
  NEVER create a blank file by hand

  The placeholders name what each field needs; filled-in references live
  in `unreleased/examples/`.

- ALWAYS set `author` to the external contributor's `@`-prefixed GitHub
  handle; NEVER set `author` for a Datadog contributor

## Writing the message

Run `unreleased:lint` and `unreleased:vale` while drafting — they enforce
the mechanical floor: code spans, casing, banned openers, PR references,
the 240-character and 3-sentence caps. The rules below add the judgment
they cannot check, in drafting order. When the structure will not fit the
caps, keep the customer effect, its scope, and any access point or escape
hatch — the compressible rest is the explanatory detail, never the
actionable.

- Structure by type — the reader's question differs:
  - `Fixed`: ALWAYS name the symptom they recognize, then the trigger
    they can perform or observe (a call they make, a setting they use);
    when nothing is observable, bottom out at what the evidence
    establishes, and NEVER below it, into internal sequencing

    ```markdown
    <!-- Bad: the trigger named, but no symptom to recognize -->
    Fix `Process.spawn` when passing an environment Hash.

    <!-- Good: the symptom they recognize + the trigger they perform -->
    Fix `TypeError` from `Process.spawn` when passing an environment Hash.
    ```

  - `Added`: ALWAYS name the capability, then the access point — the
    setting/API that gets it for them

    ```markdown
    <!-- Bad: the capability stated, but no access point to enable it -->
    Show class and module names in profiler stack frames (`Foo::Bar#baz` instead of `baz`), making hot methods easier to identify.

    <!-- Good: capability + example + why it helps + the exact access point -->
    Show class and module names in profiler stack frames (`Foo::Bar#baz` instead of `baz`), making hot methods easier to identify; enable it with `DD_PROFILING_EXPERIMENTAL_SHOW_CLASSES_ENABLED=true`.
    ```

  - `Changed`: ALWAYS name the new behavior and the escape hatch when
    one exists; SHOULD follow with why it matters

    ```markdown
    <!-- Bad: the new behavior and why, but no way back -->
    Move the gem's diagnostic logs from stdout to stderr, so stdout stays clean for application output.

    <!-- Good: new behavior + why it matters + escape hatch -->
    Move the gem's diagnostic logs from stdout to stderr, so stdout stays clean for application output; restore the old default with `c.logger.instance = Datadog::Core::Logger.new($stdout)` in `Datadog.configure`.
    ```

- ALWAYS state what changed, in customer terms; NEVER code-review
  jargon ("refactored", "cleaned up") or internal file names.

  ```markdown
  <!-- Bad: code-review terms lead — jargon, file name, the customer claim buried at the end -->
  Set `Tracing::Metadata::Ext::TAG_KIND` on spans in the `ActiveRecord` `sql` event handler (`events/sql.rb`) to fix missing peer tags for database queries.

  <!-- Good: customer framing, grounded, code spans -->
  Fix missing peer tags for database queries traced through `ActiveRecord`.
  ```

- ALWAYS start with an imperative verb (Add, Fix, Support, Improve, ...) —
  vale rejects the process-speak and subject-first openers ("This PR
  fixes...", "The gem now supports...", "Also fixes..."); a wrong verb
  form ("Fixed a crash...") still passes, so the verb choice falls to the
  author and reviewer

  ```markdown
  <!-- Bad: the verb form passes vale, but the message reads as a report, not an entry -->
  Fixed missing peer tags for database queries traced through `ActiveRecord`.

  <!-- Good: the imperative verb opens the entry -->
  Fix missing peer tags for database queries traced through `ActiveRecord`.
  ```

- ALWAYS open on the customer's observable delta; the mechanism, scope,
  and numbers follow it

  ```markdown
  <!-- Bad: the mechanism opens; the customer's delta never leads -->
  Enforce a process-wide rate limit across all probes: with multiple probes set, they can emit less than their individual limits allow — combined output is capped at 20 snapshots/s and 5000 log events/s per process.

  <!-- Good: the customer's observable delta leads, the numbers follow -->
  Cap probe output process-wide: with multiple probes set, they can emit less than their individual limits allow — combined output is capped at 20 snapshots/s and 5000 log events/s per process.
  ```

- CamelCase is the code-span judgment call lint cannot make: span what
  names the code you run (`ActiveRecord`), leave product names bare in
  prose (Bundler)

- NEVER repeat the product verbatim — with product `AppSec`, "Add AppSec
  detection..." says it twice; lowercase technical phrasing ("GC
  profiling") is fine

  ```markdown
  <!-- Bad: the product said twice -->
  Add AppSec detection of response splitting.

  <!-- Good: the product already renders beside the entry -->
  Add detection of response splitting.
  ```


- ALWAYS name exact versions and platforms when they decide who is
  affected — NEVER vague quantifiers ("recent", "newer")

  ```markdown
  <!-- Bad: vague version -->
  Disable live heap size profiling on recent Ruby versions due to incompatibility.

  <!-- Good: exact version -->
  Disable live heap size profiling on Ruby 4.0 due to incompatibility.
  ```

- SHOULD back performance claims with measured numbers from the PR's own
  evidence (Grounding); a claim with no measured number there stays
  directional

  ```markdown
  <!-- Bad: the vague quantifier stands in for the directional claim -->
  Reduce profiler overhead significantly for applications with many idle or blocked threads by skipping samples that would carry no new information; skipped threads are still reported each period.

  <!-- Good: directional with scope — the PR's evidence carries no measured number -->
  Reduce profiler overhead for applications with many idle or blocked threads by skipping samples that would carry no new information; skipped threads are still reported each period.
  ```

## Finishing loop

Run the three steps in order; ANY revision restarts the loop from step 1.
Done when a pass makes no revision:

1. `bundle exec rake unreleased:lint` and `bundle exec rake unreleased:vale` —
   fix every reported violation
2. `bundle exec rake unreleased:render` — check the rendered entry
   against every Core principle and every Writing rule in turn, and
   revise; done when each one is accounted for
3. Re-run the Grounding triage against the final diff — effect, count,
   product, and type, then every identifier, version, number, and
   behavioral claim traced to a specific hunk, benchmark output, or
   test; drop or weaken each one that traces to nothing. A count that
   grew means a new effect: the ASK re-fires and it gets its own
   fragment

---
name: write-changelog
description: 'Use when a change in this repo needs a customer-facing changelog entry — e.g. "add a changelog entry" — or when an approved PR that changes user-visible behavior in lib/, ext/, or docs/GettingStarted.md is about to merge.'
---

# Writing changelog fragments

Read `unreleased/README.md` first: it explains the fragment format and its fields.

You can write the fragment as soon as the PR exists, but check it again
against the final diff once the PR is approved, right before merging.

## Audience

A Ruby developer using this gem, reading `CHANGELOG.md` to decide whether
upgrading affects their application. Tell them what changes for them: what
they will see, what they need to do, or what they get. Don't describe the
implementation.

## Before writing

Read the diff and answer these questions:

- What does this PR change for users once merged? If nothing yet
  (groundwork, a feature flag that is still off), don't write a fragment.
- Does it have one user-visible effect or several? Write one fragment per
  effect, never combine them. If there are several, ask the user to confirm
  the split first.

  ```markdown
  <!-- Bad: two effects in one fragment -->
  Add support for Bundler deployment mode (`bundle install --deployment`) and report UI-oriented injection results.

  <!-- Good: one effect; the other effect gets its own fragment -->
  Add support for Bundler deployment mode (`bundle install --deployment`).
  ```

- Which product? Decide by the effect, not by where the code lives: a core
  fix for a profiler crash is `Profiling`. Use `Core` for changes that
  affect everything. Valid values are in `ReleasePrep::Fragment::PRODUCTS`
  (`tasks/lib/release_prep/fragment.rb`). Integration names like Redis go
  in the message, not in `product`.
- Which type? `Added` for a new capability, `Changed` for a behavior
  change, `Fixed` for a bug fix. Performance improvements are `Changed`,
  or `Fixed` when they restore the performance of an earlier version.

## Only claim what you can verify

- Check every identifier (setting, class, method, env var, gem) against
  the diff, not from memory.
- Check versions against the diff (gemspec, `Matrixfile`, CI config).
- Only cite numbers found in the diff, its benchmark output, or the PR
  description.
- Only claim a behavior change if a test in the diff shows it. If a
  reproducible bug has no test, ask for one. If the PR merges without it,
  limit the message to what reading the code confirms, and note the
  missing test in the review.
- If the bug can't be reproduced by a deterministic test (it depends on
  timing or external state), limit the message to what the code change
  itself shows.
- If a claim can't be verified, remove it or make it less specific. Don't
  hedge it.

## When to add a fragment

- Add one for new features, behavior changes, and bug fixes users can
  notice.
- Don't add one for internal refactors, test-only changes, CI/tooling, or
  docs other than `docs/GettingStarted.md`.
- When unsure, add one. A reviewer can delete it, but a missing entry
  leaves customers unaware.

## Creating the fragment

- Generate it with `bundle exec rake unreleased:new`, don't create the file
  by hand. The placeholders describe each field. Complete examples are in
  `unreleased/examples/`.
- Use the real PR number. If there is no PR yet, open a draft first.
  Nothing validates the number.
- If a fragment for the same effect already exists, update it instead of
  adding another. Leave fragments for other effects alone.
- Set `author` to the `@`-prefixed GitHub handle of external contributors.
  Leave it unset for Datadog contributors.

## Writing the message

`bundle exec rake unreleased:lint` and `unreleased:vale` check some of the
rules below. Passing them doesn't mean the message is good: follow all the
rules.

If the message is too long, cut the explanation first. Keep the effect, who
is affected, and how to enable or opt out.

- Structure depends on the type:
  - `Fixed`: the symptom users recognize, then what triggers it (a call
    they make, a setting they use). If there is no visible symptom, state
    only what the evidence shows, without describing internals.

    ```markdown
    <!-- Bad: the trigger, but no symptom -->
    Fix `Process.spawn` when passing an environment Hash.

    <!-- Good: symptom + trigger -->
    Fix `TypeError` from `Process.spawn` when passing an environment Hash.
    ```

  - `Added`: the capability, then the setting or API to use it.

    ```markdown
    <!-- Bad: no way to enable it -->
    Show class and module names in profiler stack frames (`Foo::Bar#baz` instead of `baz`), making hot methods easier to identify.

    <!-- Good: capability + example + why it helps + how to enable it -->
    Show class and module names in profiler stack frames (`Foo::Bar#baz` instead of `baz`), making hot methods easier to identify; enable it with `DD_PROFILING_EXPERIMENTAL_SHOW_CLASSES_ENABLED=true`.
    ```

  - `Changed`: the new behavior, how to get the old behavior back if
    possible, and ideally why it matters.

    ```markdown
    <!-- Bad: no way to get the old behavior back -->
    Move the gem's diagnostic logs from stdout to stderr, so stdout stays clean for application output.

    <!-- Good: new behavior + why + how to revert -->
    Move the gem's diagnostic logs from stdout to stderr, so stdout stays clean for application output; restore the old default with `c.logger.instance = Datadog::Core::Logger.new($stdout)` in `Datadog.configure`.
    ```

- Describe the change in user terms. No code-review jargon ("refactored",
  "cleaned up") and no internal file names.

  ```markdown
  <!-- Bad: internal constant and file name first, user impact last -->
  Set `Tracing::Metadata::Ext::TAG_KIND` on spans in the `ActiveRecord` `sql` event handler (`events/sql.rb`) to fix missing peer tags for database queries.

  <!-- Good -->
  Fix missing peer tags for database queries traced through `ActiveRecord`.
  ```

- Start with an imperative verb (Add, Fix, Support, Improve, ...). Not
  "Fixed a crash...", "This PR fixes...", or "The gem now supports...".

  ```markdown
  <!-- Bad -->
  This PR fixes missing peer tags for database queries traced through `ActiveRecord`.

  <!-- Good -->
  Fix missing peer tags for database queries traced through `ActiveRecord`.
  ```

- End with a period.

- Start with what the user observes. The mechanism, scope, and numbers
  come after.

  ```markdown
  <!-- Bad: starts with the mechanism -->
  Enforce a process-wide rate limit across all probes: with multiple probes set, they can emit less than their individual limits allow — combined output is capped at 20 snapshots/s and 5000 log events/s per process.

  <!-- Good: starts with what changes for the user -->
  Cap probe output process-wide: with multiple probes set, they can emit less than their individual limits allow — combined output is capped at 20 snapshots/s and 5000 log events/s per process.
  ```

- Put code names in backticks (`ActiveRecord`), but not product names
  (Bundler).

- Don't repeat the product name, it is already shown next to the entry.
  Lowercase technical terms like "GC profiling" are fine.

  ```markdown
  <!-- Bad, with product AppSec -->
  Add AppSec detection of response splitting.

  <!-- Good -->
  Add detection of response splitting.
  ```

- Give exact versions and platforms when they decide who is affected, not
  "recent" or "newer".

  ```markdown
  <!-- Bad -->
  Disable live heap size profiling on recent Ruby versions due to incompatibility.

  <!-- Good -->
  Disable live heap size profiling on Ruby 4.0 due to incompatibility.
  ```

- Back performance claims with numbers from the PR. Without numbers, just
  say what improves, without "significantly" and similar.

  ```markdown
  <!-- Bad: "significantly" with no number behind it -->
  Reduce profiler overhead significantly for applications with many idle or blocked threads by skipping samples that would carry no new information; skipped threads are still reported each period.

  <!-- Good -->
  Reduce profiler overhead for applications with many idle or blocked threads by skipping samples that would carry no new information; skipped threads are still reported each period.
  ```

## Before finishing

Repeat these steps until a pass makes no changes:

1. Run `bundle exec rake unreleased:lint` and
   `bundle exec rake unreleased:vale`, and fix every violation.
2. Run `bundle exec rake unreleased:render` and check the rendered entry
   against each rule in "Writing the message".
3. Check the fragment against the final diff again, as in "Before writing"
   and "Only claim what you can verify". If there is a new effect, ask about
   the split and give it its own fragment.

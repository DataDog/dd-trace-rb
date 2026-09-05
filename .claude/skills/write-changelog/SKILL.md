---
name: write-changelog
description: 'Use when a change in this repo needs a customer-facing changelog entry — e.g. "add a changelog entry", "this needs a changelog fragment", or when finishing a PR that changes user-visible behavior in lib/, ext/, or docs/GettingStarted.md. Enforces dd-trace-rb changelog fragment conventions.'
---

# Writing changelog fragments

Fragments live in `unreleased/`, one JSON file per notable change, committed
alongside the change. A release renders every pending fragment into
`CHANGELOG.md` and the GitHub draft release, then consumes the files. See
`unreleased/README.md` for the human-facing version of this workflow

## Core rules

- MUST add an entry for new features, behavior changes to existing features,
  and bug fixes that affect customers
- NEVER add an entry for internal refactors, test-only changes, CI/tooling
  changes, or documentation-only changes outside `docs/GettingStarted.md`
- SHOULD add one when unsure — a reviewer can delete an unnecessary entry,
  but a missing one leaves customers unaware of the change
- MUST set `type` to one of `Added` (a capability that didn't exist before),
  `Changed` (a behavior change to something that existed), `Fixed` (a bug fix)
- MUST set `prefix` to the product area owning the change, matching the
  top-level `lib/datadog/*` directory: `Core`, `Tracing`, `Profiling`,
  `AppSec`, `AI Guard`, `Dynamic Instrumentation`, `Data Streams`,
  `Error Tracking`, `Open Feature`, `OpenTelemetry`. The specific integration
  name (Redis) belongs in the `message`, not the `prefix`
- MUST write the message for a customer: what changed and why it matters to
  someone using the gem — NEVER as an internal description of the diff
- MUST start the message with a verb in the imperative (Add, Fix, Support,
  Improve, ...) — CI rejects process-speak and subject-first openers ("This
  PR fixes...", "The gem now supports...", "Also fixes...")
- NEVER use code-review jargon ("refactored", "cleaned up") or internal file
  names in the message; ALWAYS use inline code spans for identifiers,
  matching existing `CHANGELOG.md` entries:

  ```markdown
  <!-- Good – customer framing, grounded, canonical casing, code spans -->
  Fix missing peer tags for database queries traced through `ActiveRecord`.
  Fix a rare crash (`SIGSEGV`) in the profiler that could occur when sampling a
  thread during `Thread.new`.

  <!-- Bad – internal description: jargon, file names, no user-visible claim -->
  Refactored peer_tags.rb in the tracer to fix the nil case in Tags#populate.

  <!-- Bad – vague quantifiers hedging claims the diff may not make -->
  Improve performance of the appsec rules and fix various issues significantly.
  ```

- MUST wrap identifiers — settings, classes, methods, gems, env vars — in
  code spans; CI flags a naked `DD_...` env var, snake_case, CONSTANT_CASE, or
  `Foo.bar` method in prose, and lint rejects unbalanced or empty spans
- NEVER put plain English words in code spans: they name identifiers, they
  are not emphasis
- NEVER repeat the prefix verbatim in the message — the rendered entry
  already opens with it, so "AppSec: Add AppSec detection..." says it twice;
  lowercase technical phrasing ("GC profiling", "when tracing is disabled")
  is fine, only the verbatim prefix is redundant
- MUST ground every claim in the diff being described: component and gem
  names, versions, and behavior come from the change itself, NEVER from
  memory. If you cannot point at where in the diff a claim comes from, the
  message does not get to make it
- MUST use the canonical casing: `AppSec`, `OpenTelemetry`, `OTel`,
  `Dynamic Instrumentation`, `Data Streams`, `Open Feature` — lint rejects
  `appsec`, `opentelemetry`, and `otel`
- MUST end the message with terminal punctuation (`.`, `!`, or `?`) and keep
  it at most 240 characters
- MUST keep one fragment to one change: at most three sentences, NEVER a
  bundle tail ("and more", "etc.") — lint rejects both, and a second
  user-visible change is a second fragment
- NEVER reference the PR in the message; the PR number is rendered
  automatically from the pull_request field, and lint rejects `#123`-style
  references
- For `Fixed` entries, MUST name the user-visible symptom a customer
  recognizes (`Fix `Process.waitall` hanging`), NEVER only the fix's
  internals (`Refactor the tags population code path`)
- For `Changed` entries that alter defaults, MUST include the action or
  escape hatch — name the setting that restores the previous behavior
- MUST name exact versions and platforms (`Ruby 2.6 to 3.1`), NEVER
  "recent" or "newer" hedges
- MUST back performance claims with numbers from the diff (`Reduce overhead
  by up to 50%`); an unmeasured claim stays directional and modest (`Reduce
  overhead`), NEVER "significantly improve performance"
- MUST fill `pull_request` with the full PR URL,
  `https://github.com/DataDog/dd-trace-rb/pull/NNNN` — open the PR first,
  even as a draft, so the number is known. Lint rejects any other form
  (issue links, fork URLs, placeholders like `pull/TBD`), and release-prep
  later checks the number against merged history
- MUST set `author` ONLY for external (non-Datadog) contributors, to their
  GitHub handle; omit it otherwise

## Before finishing

Re-read the message and revise until every item holds:

- Every claim (names, versions, behavior) is visible in the diff
- It reads as written for a customer — no internal jargon or file names
- One change per fragment — no bundle tails, no second change hiding in a
  second sentence
- `Fixed` names the symptom a customer recognizes; `Changed` names the
  escape hatch
- Canonical casing throughout, ≤240 characters, ≤3 sentences, terminal
  punctuation, and no vague quantifiers ("various", "several",
  "significantly")
- Identifiers sit in code spans; plain English words don't
- The prefix is not repeated verbatim in the message

## Creating the file

Copy the closest template, then rename it to the current UTC timestamp and
edit its fields:

```bash
cp unreleased/examples/basic.json "unreleased/$(date -u +%Y%m%d%H%M%S).json"
```

`unreleased/examples/` holds real-life-flavored templates per type and per
product area (`added.json`, `changed.json`, `fixed.json`, `appsec.json`,
`di.json`, ...) — ALWAYS start from the closest one rather than a blank
file. `with_author.json` is the starting point when crediting an external
contributor

## Validation

```bash
bundle exec rake unreleased:lint
bundle exec rake unreleased:render
```

`unreleased:lint` checks the schema (required fields, closed enums, canonical
casing) and reports every violation across every pending fragment in one run.
`unreleased:render` previews how the entry will look once rendered into
`CHANGELOG.md`. Release-prep additionally verifies each `pull_request`
number against the repository's merged history.

Message hygiene (weasel words, corporate speak, grammar, punctuation,
trailing whitespace) is enforced by CI with vale — it is NOT part of local
validation. If CI reports a hygiene finding, revise the message per the
annotation and push again; CI reports every violation in one run, so one
revision round-trip clears all findings. The self-review above is what keeps
those round-trips rare

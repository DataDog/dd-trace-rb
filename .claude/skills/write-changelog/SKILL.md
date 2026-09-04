---
name: write-changelog
description: Use whenever a change in this repo needs a customer-facing changelog entry — e.g. "add a changelog entry", "this needs a changelog fragment", or when finishing a PR that changes user-visible behavior in lib/, ext/, or docs/GettingStarted.md.
---

# Writing a changelog fragment

This repo replaced PR-description changelog entries with fragment files
under `unreleased/`. See `unreleased/README.md` for the human-facing
version of this workflow; this skill is the agent-facing checklist.

## 1. Decide whether an entry is needed

Add an entry for: new features, behavior changes to existing features,
and bug fixes that affect customers.

Skip an entry for: internal refactors, test-only changes, CI/tooling
changes, and documentation-only changes that aren't `docs/GettingStarted.md`.

If unsure, add one — a reviewer can always delete an unnecessary entry
during review, per `unreleased/README.md`.

## 2. Pick `type`

- `Added` — a new capability that didn't exist before.
- `Changed` — a behavior change to something that already existed.
- `Fixed` — a bug fix.

## 3. Pick `prefix`

One of: `Core`, `Tracing`, `Profiling`, `AppSec`, `AI Guard`,
`Dynamic Instrumentation`, `Data Streams`, `Error Tracking`, `Open Feature`,
`OpenTelemetry`.

Match it to the top-level `lib/datadog/*` directory the change lives
under. A change under `lib/datadog/tracing/contrib/redis`, for example,
is `Tracing` — the specific integration name (Redis) belongs in the
`message`, not the `prefix`.

## 4. Write `message`

A customer-facing sentence in Markdown, describing what changed and why
it matters to someone using the gem — not an internal description of the
diff. No code-review jargon ("refactored", "cleaned up"), no internal
file names. Use inline code spans for identifiers, matching existing
`CHANGELOG.md` entries:

> Fix missing peer tags for database queries traced through `ActiveRecord`.

End with terminal punctuation (`.`, `!`, or `?`) and keep it at most 240
characters — CI lints this with vale plus Ruby checks and reports every
violation in one run.

## 5. Fill `pull_request` and `author`

- `pull_request`: the full PR URL, e.g.
  `https://github.com/DataDog/dd-trace-rb/pull/6300`. If the PR doesn't
  exist yet, open it first — even as a draft — so the number is known;
  `unreleased:lint` rejects any other form (issue links, fork URLs,
  placeholders like `pull/TBD`). Lint checks the URL's form, not that it
  resolves.
- `author`: only set this for an external (non-Datadog) contributor,
  to their GitHub handle. Omit it otherwise.

## 6. Create the file

Copy `unreleased/examples/basic.json` (or `with_author.json` if crediting
an external contributor) to `unreleased/<timestamp>.json`, using the
current UTC time as the filename:

```bash
cp unreleased/examples/basic.json "unreleased/$(date -u +%Y%m%d%H%M%S).json"
```

Then edit the new file's fields per steps 2-5 above.

## 7. Validate

```bash
bundle exec rake unreleased:lint
bundle exec rake unreleased:render
```

`unreleased:lint` checks the schema (required fields, closed enums).
`unreleased:render` previews how the entry will look once rendered into
`CHANGELOG.md`. Message hygiene is checked by `unreleased:vale`,
which runs both a Ruby-based trailing-whitespace check and vale for
punctuation and style validation. CI runs this as a required step after
installing a pinned vale binary.

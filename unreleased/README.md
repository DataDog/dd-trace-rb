# Changelog fragments

Every pull request that changes customer-visible behavior should add one
changelog fragment per notable change to this directory.

## Adding an entry

1. Copy a file from `examples/` (e.g. `examples/basic.json`; there are
   also real-life-flavored templates per type and for every product
   area — `added.json`, `changed.json`, `fixed.json`, `ai_guard.json`,
   `appsec.json`, `data_streams.json`, `di.json`, `error_tracking.json`,
   `otel.json`, `open_feature.json`).
2. Rename it to a timestamp, e.g. `$(date +%Y%m%d%H%M%S).json`.
3. Fill in the fields:
   - `type`: `Added`, `Changed`, or `Fixed`.
   - `prefix`: the product area this change belongs to. One of `Core`,
     `Tracing`, `Profiling`, `AppSec`, `AI Guard`, `Dynamic Instrumentation`,
     `Data Streams`, `Error Tracking`, `Open Feature`, `OpenTelemetry`.
   - `pull_request`: the full URL of this pull request, in the canonical
     `https://github.com/DataDog/dd-trace-rb/pull/NNNN` form; lint rejects
     issue links, fork URLs, and placeholders.
   - `message`: a customer-facing description, written as Markdown, at most
     240 characters, ending in terminal punctuation.
   - `author` (optional): your GitHub handle, if you're an external
     contributor and want credit in `CHANGELOG.md`.
4. Commit the file alongside your change.

Not every pull request needs an entry — internal refactors, test-only
changes, and CI/tooling changes usually don't. If you're unsure, ask in
review.

## Release highlights

To add release-page highlights (shown above the changelog entries on the
GitHub release, not inside `CHANGELOG.md` itself), create or edit
`unreleased/highlights.md` with free-form Markdown.

## Validating your entry

Run `bundle exec rake unreleased:lint` to check the fields, enums,
canonical casing, and message shape (sentence cap, balanced non-empty
code spans, no PR references) — it
reports every violation across every pending fragment in one run — and
`bundle exec rake unreleased:render` to preview how your entry (and every
other pending entry) will render in the next `CHANGELOG.md`.

Message hygiene (weasel words, corporate speak, non-verb openers,
catchall tails, naked identifiers outside code spans, grammar,
punctuation, trailing whitespace) is enforced by CI with vale, not run
locally: a
message that fails it fails your PR, with one annotation per finding.
Revise per the annotations and push again — CI reports every violation in
one run, so a single revision clears all findings. Write messages that
pass it by following the rules above and reviewing your message before
committing.

## Keeping the rules honest

The hygiene rules were calibrated against the 13 GitHub releases the
primary release manager has cut, v2.0.0 and later (see `.vale.ini`), and
they hold a standing feedback policy:

- A rule that has not fired across several releases is ceremony —
  demote or remove it.
- A message problem that reaches `CHANGELOG.md` is a gap: convert it
  into a new deterministic check (when machine-checkable, e.g. the
canonical-casing check in `unreleased:lint`) or a new instruction in
the write-changelog skill (when it is a judgment call).
- Style package bumps are deliberate: bump the pinned version and
  SHA256 together, then re-run the calibration corpus and update the
  `.vale.ini` overrides if anything newly fires.

## What happens at release time

The release-prep workflow renders every fragment in this directory (plus
`highlights.md`, if present) into the new GitHub draft release and
`CHANGELOG.md`, then deletes the consumed fragments.

# Changelog fragments

Every pull request that changes customer-visible behavior should add one
changelog fragment per notable change to this directory.

## Adding an entry

1. Copy a file from `examples/` (e.g. `examples/basic.json`; there are
   also real-life-flavored templates per type and product area —
   `added.json`, `changed.json`, `fixed.json`, `di.json`, `appsec.json`,
   `otel.json`).
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

Run `bundle exec rake unreleased:lint` to check the schema — it reports
every violation across every pending fragment in one run — and
`bundle exec rake unreleased:render` to preview how your entry (and every
other pending entry) will render in the next `CHANGELOG.md`. Message hygiene
is checked separately by `bundle exec rake unreleased:vale`, which
runs both a Ruby-based trailing-whitespace check and vale for punctuation
and style validation. CI runs this as a required step, so a message that
fails it will fail your PR.

## What happens at release time

The release-prep workflow renders every fragment in this directory (plus
`highlights.md`, if present) into the new GitHub draft release and
`CHANGELOG.md`, then deletes the consumed fragments.

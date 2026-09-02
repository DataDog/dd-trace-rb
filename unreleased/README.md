# Changelog fragments

Every pull request that changes customer-visible behavior should add one
changelog fragment per notable change to this directory.

## Adding an entry

1. Copy a file from `examples/` (e.g. `examples/basic.json`).
2. Rename it to a timestamp, e.g. `date +%Y%m%d%H%M%S`.json`.
3. Fill in the fields:
   - `type`: `Added`, `Changed`, or `Fixed`.
   - `prefix`: the product area this change belongs to. One of `Core`,
     `Tracing`, `Profiling`, `AppSec`, `AI Guard`, `Dynamic Instrumentation`,
     `Data Streams`, `Error Tracking`, `Open Feature`, `OpenTelemetry`.
   - `pull_request`: the full URL of this pull request.
   - `message`: a customer-facing description, written as Markdown, ending
     in terminal punctuation.
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

Run `bundle exec rake changelog:lint` to check the schema, and
`bundle exec rake changelog:render` to preview how your entry (and every
other pending entry) will render in the next `CHANGELOG.md`.

## What happens at release time

The release-prep workflow renders every fragment in this directory (plus
`highlights.md`, if present) into the new GitHub draft release and
`CHANGELOG.md`, then deletes the consumed fragments.

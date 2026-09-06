# Changelog fragments

Customer-visible changes get one JSON fragment per notable change in this
directory. A release flushes all pending fragments into `CHANGELOG.md`
and the GitHub draft release.

## Using an agent

The system is designed for a coding agent to write the fragment — if you
use one, invoke the skill directly:

> Use the write-changelog skill to add a changelog fragment for this
> pull request.

## Adding an entry

A fragment is a small JSON file in this directory, one per notable
change. Its fields:

- `type`: the kind of change — `Added`, `Changed`, or `Fixed`.
- `prefix`: the product area owning the change. The list is
  `ReleasePrep::Fragment::PREFIXES`
  ([`tasks/release_prep/fragment.rb`](../tasks/release_prep/fragment.rb)).
- `pull_request`: this PR's URL,
  `https://github.com/DataDog/dd-trace-rb/pull/NNNN`.
- `message`: customer-facing message in Markdown.
- `author` (external contributors only): GitHub handle, for credit
  in `CHANGELOG.md`.

[`examples/`](examples/) holds real-life-flavored fragments per type and product area —
check them out. Tip: start by copy-pasting the closest one and editing
its fields; the filename is irrelevant, only the fields are read. Commit
the file alongside your change.

Internal refactors, test-only, and CI/tooling changes don't need one.
When unsure, add one — a reviewer can delete an unnecessary entry, but a
missing one leaves customers unaware.

## Validating

To check the schema and reports every violation in one run:
```
bundle exec rake unreleased:lint
```

To preview the rendered entry.
```
bundle exec rake unreleased:render
```

Messages also follow house hygiene rules ([`.vale.ini`](../.vale.ini)),
enforced by vale in CI only.

## Release highlights

Release-page highlights — shown above the changelog entries on the GitHub
release, not inside `CHANGELOG.md` — go in `highlights.md`.

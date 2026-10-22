---
name: write-pull-request
description: 'Use when opening a pull request in this repo, or when writing or updating a PR description. For example, "create the PR" or "write the PR body". Covers only the description. The branch, commits, and gh commands are out of scope.'
---

# Writing pull request descriptions

One reader: a senior Ruby engineer deciding whether to care and how
carefully to look. The size limits are the signal-extraction mechanism:
every sentence past the cap is noise the reviewer pays for.
Implementation narration is the worst noise, because it goes stale
when code changes. Why, What, and Risk carry intent and stance. The
diff carries the how.

The template is `.github/PULL_REQUEST_TEMPLATE.md`. CI (check.yml,
`pr-body` job) enforces the caps on every PR, drafts included.

## The contract

Four slots in order. `### Why`, `### What`, and `### Risk` are
required. `### Details` is optional.

- ALWAYS at most 2 sentences and 50 words per required field
- ALWAYS high level and terse in Why and What: these slots reveal the
  intent of the change. Senior Ruby engineers know the codebase. Name
  the effect and its trigger, not the mechanism. A sentence that names
  a file or a spec helper is too deep
- ALWAYS ground What and Risk in the diff, never in memory of the work
  session. Why grounds in the request or issue that motivated the
  work: intent is not in the diff
- ALWAYS make the required fields stand alone: a reader who opens
  nothing else can decide whether to care
- NEVER narrate the implementation
- Links in required fields use markdown style: link text carries the
  meaning, the URL is optional context. Bare URLs go in Details

### Why

The change's intent, in terms the reviewer recognizes. One sentence
for the problem, one for the trigger or scope when it decides who
cares.

### What

The effect at the level that decides review effort.

### Risk

The merge stance: door type (two-way or one-way), the blast radius, and
the mechanical revert. Categorize with the taxonomy in `risk.md`. Merge
preconditions live here, not in Details. A whole field: "Two-way door,
scoped to the AppSec rules engine. Revert by re-running the update
task."

### Details

Optional, and always collapsible. Everything that overflows the caps
goes here, wrapped in `<details><summary>Notes</summary>` and
`</details>`: links, benchmarks, plans, test instructions, any longer
explanation. Never appended to a required field, never loose in the
body. A reader must not need it.

## Grounding and drift

Ground What and Risk in the diff at creation. When review changes the
diff, re-ground Why, What, and Risk against the final diff before
merge: dead effects come out, new effects go in. The caps hold after
every edit.

## Examples

The CI fixtures are worked examples:

- Imitate `.github/scripts/check/fixtures/pass_contract_body.md`
- Automation shape: `pass_automation_shape.md`
- Each `fail_*.md` fixture names one rejection

Verify a draft before opening the PR:

```
PR_BODY="$(cat draft.md)" ruby .github/scripts/check/pr_body.rb
```

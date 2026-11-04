---
name: write-pull-request
description: 'Use when opening a pull request in this repo, or when writing or updating a PR description. For example, "create the PR" or "write the PR body". Covers only the description. The branch, commits, and gh commands are out of scope.'
---

# Writing pull request descriptions

The reader is a senior Ruby engineer who knows the codebase and wants to
know quickly whether to review this PR and how carefully. Keep it short.
Do not describe the implementation: the diff already shows it, and the
description gets out of date when the code changes.

The template is `.github/PULL_REQUEST_TEMPLATE.md`. CI (`check.yml`,
`pr-body` job) checks the length limits on every PR, drafts included.

## Rules

Four sections, in this order: `### Why`, `### What`, `### Risk` (required)
and `### Details` (optional).

- Each required section has at most 2 sentences and 50 words.
- Keep Why and What high level: the effect and when it happens, not how
  it is implemented. If a sentence names a file or a spec helper, it is
  too detailed.
- Base What and Risk on the diff, not on what you remember doing. Base Why
  on the request or issue that motivated the change.
- The required sections must make sense on their own, without opening
  anything else.
- Never use the `<!-- pr-body: skip -->` marker. It is for exceptions
  decided by a human. Make the description fit instead.
- Links in required sections use markdown syntax, with meaningful link
  text. Put bare URLs in Details.

### Why

Why the change is needed: one sentence for the problem, and optionally one
for who is affected or when it happens.

### What

What the change does, at the level needed to judge how much review it
needs.

### Risk

Whether the change can be undone (two-way door) or not (one-way door), what
it can affect, and how to revert it. See `risk.md` for how to assess it.
Conditions to meet before merging go here, not in Details. Example: "Two-way
door, scoped to the AppSec rules engine. Revert by re-running the update
task."

### Details

Optional, collapsed in `<details><summary>Notes</summary>` ... `</details>`.
Anything that does not fit in the other sections goes here: links,
benchmarks, plans, steps for testing, longer explanations. Never put it
after a required section or loose in the body. The PR must be
understandable without reading it.

## Keeping it up to date

If the diff changes during review, update Why, What, and Risk before
merging. Remove what no longer applies, add what is new, and stay within
the limits.

## Examples

The CI fixtures in `.github/scripts/check/fixtures/` are examples:

- `pass_contract_body.md` is the one to imitate
- `pass_automation_shape.md` is the shape for automated PRs
- each `fail_*.md` shows one rejected case

Check a draft before opening the PR:

```
PR_BODY="$(cat draft.md)" ruby .github/scripts/check/pr_body.rb
```

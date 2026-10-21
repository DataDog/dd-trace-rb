---
name: write-pull-request
description: 'Use when opening a pull request in this repo, or when writing or updating a PR description. For example, "create the PR" or "write the PR body". Covers only the description. The branch, commits, and gh commands are out of scope.'
---

# Writing pull request descriptions

A PR description in this repo has one reader: a reviewer deciding whether
to care and how carefully to look. The code is the implementation. The
description never narrates it. The template is
`.github/PULL_REQUEST_TEMPLATE.md`. CI (check.yml, `pr-body` job) enforces
the caps below on every PR, drafts included.

## The contract

Four slots, in order. `### Why`, `### What`, and `### Risk` are required.
`### Details` is optional.

- ALWAYS fill each required field with at most 2 sentences and 50 words
- ALWAYS write from the diff, never from memory of the work session
- ALWAYS make the three required fields stand alone. A reader who opens
  nothing else can decide whether to care
- NEVER narrate the implementation in Why, What, or Risk. No file names,
  no spec mechanics, no step-by-step of what the code does. The reviewer
  reads the diff for that
- Links in Why, What, and Risk must use markdown style. The link text
  carries the meaning, and the URL is optional context. CI rejects bare URLs
  there. Bare URLs and link dumps go in Details only

### Why

The problem or motivation, in reviewer terms. One sentence the reviewer
recognizes. A second sentence for the trigger or scope when it decides
who cares.

### What

What changes at the level that decides review effort. State the effect,
not the mechanism. If a sentence names a file or a spec helper, it is too
deep.

### Risk

The merge stance. Open with two-way or one-way door. Then the blast
radius and how to revert, within the caps. This is a whole field:
"Two-way door, scoped to the AppSec rules engine. Revert by re-running
the update task."

### Details

Optional and collapsible. Links, benchmarks, plans, test instructions,
anything longer than two sentences. A reader must not need this section.

## Grounding and drift

The body is grounded in the diff at creation. When review rounds change
the diff, re-ground Why, What, and Risk against the final diff before
merge. An effect that no longer exists comes out. A newly added effect
goes in. The caps hold after every edit.

## Examples

The check's fixtures are worked examples, and CI re-validates them on
every PR, so they can never drift from the rules above:

- A body to imitate: `.github/scripts/check/fixtures/pass_contract_body.md`
- Automation bodies: `.github/scripts/check/fixtures/pass_automation_shape.md`
- Each `fail_*.md` fixture shows one named rejection. For example,
  `fail_wall_of_text.md` is the narration this skill forbids

Before opening the PR, verify the draft body locally. The findings name
the exact field and violation:

```
PR_BODY="$(cat draft.md)" ruby .github/scripts/check/pr_body.rb
```

## Common mistakes

Each of these passed older templates in this repo. CI now rejects the
first. Judgment must reject the rest.

| Mistake | Reality |
| --- | --- |
| "The reviewer needs the spec changes explained" | The diff shows them. Narration is what goes stale when code changes. |
| "Test instructions belong in the body" | They belong in Details, and only when they are longer than one command a reviewer can run. |
| "I will fill the fields fully once the PR is final" | CI checks drafts too. Write the body when the PR opens. |
| "A link to the plan is easier" | Why, What, and Risk must stand alone, so link text must carry the meaning. A bare URL says nothing and goes in Details. |

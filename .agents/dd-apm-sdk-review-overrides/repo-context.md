# Repo context — dd-trace-rb

Read only by the orchestrator (Step 0 of `SKILL.md`), not by individual reviewers. Repo-specific; not part of the shared core. This whole `.agents/dd-apm-sdk-review-overrides/` folder is owned by this repo — edit it freely, unlike `.agents/skills/dd-apm-sdk-review/`, which is a verbatim copy of the shared core.

## Related skills in this repo

The other skills in this repo author specific things; this one is the general multi-perspective push gate. Cite them as authoritative for their own area, do not invoke them, and note they must not invoke this skill either:

- `write-comment` — when a comment earns its place. Defer for comment-only questions.
- `write-rbs` — RBS / Steep signatures. Defer for type-signature work.

Cursor personas under `.cursor/rules/` (`code-style.mdc`, `testing.mdc`) are local editor guidance, not skills. Cite them when a conventions finding is really "the persona already said this."

---
name: write-comments
description: 'Use whenever writing or reviewing a code comment anywhere in this repo (lib, ext, spec, sig, docs, CI config, etc.) – e.g. "add a comment", "explain this in a comment", "is this comment worth keeping". Enforces dd-trace-rb comment-noise conventions.'
---

# Writing code comments

## Code comments

Default to **no comment**. A comment must earn its place by saying something the code cannot.

**Write a comment only when:**

- It explains *why*, not *what*: a non-obvious tradeoff, a workaround for an upstream bug (link it), a perf choice that looks wrong but isn't.
- It warns of a real hazard: ordering constraints, thread/async safety, mutation of a shared value, a caller invariant that isn't type-enforced.
- It documents a public API contract in the project's docstring format (JSDoc/godoc/docstring) — and only for exported/public surfaces.
- It cites an external source: spec section, RFC, ticket, formula, algorithm name.

**Never write:**

- Restatements of the next line. `// increment counter` above `counter++`. `// loop over users` above a `for`. `// return the result`.
- Section banners and scaffolding: `// ---- Helpers ----`, `// Constants`, `// Main logic`, `// Step 1: ... // Step 2: ...`.
- Repetition of what a good name already says. If the comment and the identifier say the same thing, delete the comment; if the name is bad, fix the name instead.
- Restatements of the type signature in prose (`@param userId The user id`).
- Duplicates of something already stated in a nearby docstring, the README, or the ADR. State it once, in the most discoverable place.
- Narration of the change or of your own process: `// Added error handling`, `// Fixed the bug`, `// Now using the new API`, `// As requested`. That belongs in the commit message or PR description.
- Commented-out code. Delete it; git has it.
- `TODO`/`FIXME` without an owner or ticket.
- Comments on obvious imports, getters/setters, or trivial one-line wrappers.

**Ratio check before finishing:** if a diff has more than roughly one comment per 15 lines of new code, or if any comment would still be true after deleting the line below it, cut comments until that stops being the case.

**When editing existing files:** match the file's existing comment density and style. Do not add comments to code you merely moved or reformatted. Do not remove existing comments unless they are now factually wrong.

**Prefer over commenting:** a clearer name, an extracted well-named function, a named constant instead of a literal, or a test that demonstrates the behavior.

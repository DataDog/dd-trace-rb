---
name: write-comment
description: 'Use whenever writing or reviewing a code comment anywhere in this repo (lib, ext, spec, sig, docs, CI config, etc.) – e.g. "add a comment", "explain this in a comment", "is this comment worth keeping". Enforces dd-trace-rb comment-noise conventions.'
---

# Writing code comments

## Code comments

Default to **no comment**: a comment must earn its place by saying something the code cannot.

**Exception:** `@public_api` docstrings follow normal YARD conventions (`@param`, `@return`, `@raise`, `@example`, `@see`) — they're shipped customer docs (`docs/PublicApi.md`). The method body still follows the rules below. E.g.:
```ruby
# Returns the baggage for the current trace.
#
# If there is no active trace, a new one is created.
#
# @return [Datadog::Tracing::Distributed::Baggage] The baggage for the current trace.
# @public_api
def baggage
```

**Write a comment only when:**

- It explains *why*, not *what*: a non-obvious tradeoff, a workaround for an upstream bug (link it), a perf choice that looks wrong but isn't. E.g.:
  ```ruby
  # We use a custom random number generator because we want no interference
  # with the default one. Using the default prng, we could break code that
  # would rely on srand/rand sequences.
  def self.id_rng
    @id_rng ||= Random.new
  end
  ```
- It warns of a real hazard: ordering constraints, thread/async safety, mutation of a shared value, a caller invariant that isn't type-enforced. E.g.:
  ```ruby
  # Supports synchronous code flow *only*. Usage across
  # multiple threads will result in incorrect relationships.
  # For async support, a {Datadog::Tracing::TraceOperation} should be employed
  # per execution context (e.g. Thread, etc.)
  class TraceOperation
  ```
- Cites an external source (spec, RFC, ticket, formula, algorithm) — never an internal-only one (wiki, Slack, JIRA, incident), even by name. Only cite what a non-Datadog reader can look up. E.g.:
  ```ruby
  # Golden ratio constant for optimal distribution.
  # @see https://en.wikipedia.org/wiki/Hash_function#Fibonacci_hashing
  DEFAULT_KNUTH_FACTOR = 11400714819323198485
  ```
- It documents a struct/instance field or other declaration that has no body to narrate: its valid states, invariants, or concurrency rules aren't derivable from the declaration itself. E.g.:
  ```c
  // Accessed under the GVL for most functions EXCEPT on_gvl_waiting(),
  // which writes to it without the GVL.
  long gvl_waiting_at;
  ```

**NEVER write:**

- Narration of nearby code — the comment just restates in prose what a block, loop, or call already does. E.g.:
  ```ruby
  # increment counter
  counter += 1
  ```
  Or narrating a whole method:
  ```ruby
  # Gets the value of the header with the given name.
  def get(header_name)
    @env[Header.to_rack_header(header_name)]
  end
  ```
- Section banners and scaffolding. E.g.:
  ```ruby
  # ---- Helpers ----
  # Step 1: parse input
  # Step 2: validate
  ```
- Repetition of what a good name already says. Delete the comment, or rename if the identifier is the weak link.
- Type restatements in prose (non-public surfaces). Type it in `sig/` instead (`write-rbs` skill). E.g.:
  ```ruby
  # @param [TraceOperation] trace
  # @return [Boolean]
  def match?(trace)
  ```
- Duplicates of a nearby docstring or README. State it once, in the most discoverable place.
- The same comment copy-pasted across multiple sites in one diff. Consolidate into one place and reference it.
- Narration of the change or of your own process. That belongs in the commit message or PR description. E.g.:
  ```ruby
  # Added error handling
  # Now using the new API
  ```
- Comments on obvious imports, getters/setters, or trivial one-line wrappers.

**Ratio check before finishing:** if a diff has more than roughly one comment per 15 lines of new code, or if any comment would still be true after deleting the code it narrates, cut comments until that stops being the case. Exempt declaration-only blocks (struct/instance field docs with no accompanying logic) from the ratio — density there doesn't imply narration.

**When editing existing files:** don't add comments to code you merely moved or reformatted. Don't remove comments outside your change's scope unless they're now wrong — that's unrelated churn. Comments on code you're actually touching still follow the rules above.

**Prefer over commenting:** a clearer name, an extracted well-named function, a named constant instead of a literal, or a test that demonstrates the behavior.

## Removing existing comments

Applies only to reviewing/deleting existing comments, not writing new ones:

- **Fix the named defect, don't just delete.** Rename the identifier (repetition), relocate to `sig/` (type restatement), add a shared reference (copy-paste) — apply it, or verify the destination already carries the information (e.g. the `.rbs` actually declares the type), before removing.
- **A deletable comment can contain a keeper.** Judge multi-line comments per line: delete the narration, keep an embedded hazard/why/citation line.
- **A tag and its wrapped continuation are one unit.** Remove both together, then re-read the docstring for a complete, consistent signature.
- **Bulk sweeps hide repeated defects.** One file or module per commit, so a systematic mistake surfaces on file one.

## Style

Always be terse. One line beats a paragraph; a fragment beats a full sentence. E.g.:

```ruby
# Workaround for JRuby not supporting Process.fork.
```

not:

```ruby
# This is a workaround that we need because JRuby does not support
# the Process.fork method, which is used elsewhere in this codebase.
```

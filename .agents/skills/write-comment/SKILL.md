---
name: write-comment
description: 'Use whenever writing or reviewing a code comment anywhere in this repo (lib, ext, spec, sig, docs, CI config), for example "add a comment", "explain this in a comment", "is this comment worth keeping". Enforces dd-trace-rb comment-noise conventions.'
---

# Writing code comments

## Code comments

Default to **no comment**: a comment must earn its place by saying something
the code cannot.

**Exception:** `@public_api` docstrings follow normal YARD conventions
(`@param`, `@return`, `@raise`, `@example`, `@see`). They are shipped
customer docs (`docs/PublicApi.md`). The method body still follows the rules
below. For example:
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

- It explains *why*, not *what*. Examples: a non-obvious tradeoff, an
  upstream bug workaround (link it), or a perf choice that looks wrong but
  is not. For example:
  ```ruby
  # We use a custom random number generator because we want no interference
  # with the default one. Using the default prng, we could break code that
  # would rely on srand/rand sequences.
  def self.id_rng
    @id_rng ||= Random.new
  end
  ```
- It warns of a real hazard: ordering constraints, thread/async safety,
  mutation of a shared value. Also a caller invariant that the types do not
  enforce. For example:
  ```ruby
  # Supports synchronous code flow *only*. Usage across
  # multiple threads will result in incorrect relationships.
  # For async support, a {Datadog::Tracing::TraceOperation} should be employed
  # per execution context (e.g. Thread, etc.)
  class TraceOperation
  ```
- It cites an external source (spec, RFC, ticket, formula, algorithm).
  Never cite an internal-only one (wiki, Slack, JIRA, incident), even by
  name. Cite only what a non-Datadog reader can look up. For example:
  ```ruby
  # Golden ratio constant for optimal distribution.
  # @see https://en.wikipedia.org/wiki/Hash_function#Fibonacci_hashing
  DEFAULT_KNUTH_FACTOR = 11400714819323198485
  ```
- It documents a struct/instance field or other declaration that has no
  body to narrate. Its valid states, invariants, or concurrency rules are
  not derivable from the declaration itself. For example:
  ```c
  // Accessed under the GVL for most functions EXCEPT on_gvl_waiting(),
  // which writes to it without the GVL.
  long gvl_waiting_at;
  ```

**NEVER write:**

- Narration of nearby code. The comment restates in prose what a block,
  loop, or call already does. For example:
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
- Section banners and scaffolding. For example:
  ```ruby
  # ---- Helpers ----
  # Step 1: parse input
  # Step 2: validate
  ```
- Repetition of what a good name already says. If the identifier is the
  weak link, rename it. Otherwise delete the comment.
- Type restatements in prose (non-public surfaces). Type it in `sig/`
  instead (`write-rbs` skill). For example:
  ```ruby
  # @param [TraceOperation] trace
  # @return [Boolean]
  def match?(trace)
  ```
- Duplicates of a nearby docstring or README. State it once, in the most
  discoverable place.
- The same comment copy-pasted across multiple sites in one diff.
  Consolidate into one place and reference it.
- Narration of the change or of your own process. That belongs in the
  commit message or PR description. For example:
  ```ruby
  # Added error handling
  # Now using the new API
  ```
- Comments on obvious imports, getters/setters, or trivial one-line
  wrappers.

**Ratio check before finishing:** keep the diff at roughly one comment per 15
lines of new code, at most. Also cut any comment that stays true after
deleting the code it narrates. Exempt declaration-only blocks (struct/instance
field docs with no accompanying logic) from the ratio. Density there does not
imply narration.

**When editing existing files:** do not add comments to code you merely moved
or reformatted. Do not remove comments outside your change's scope unless
they are now wrong. That is unrelated churn. Comments on code you are
actually touching still follow the rules above.

**Prefer over commenting:** a clearer name, an extracted well-named function,
a named constant instead of a literal, or a test that demonstrates the
behavior.

## Removing existing comments

When reviewing or deleting existing comments:

- **Do not lose information.** Before deleting, move it where it belongs.
  Rename the identifier the comment repeats. Move a type to `sig/`. Replace
  copy-pasted comments with a shared one. Or check that the information is
  already there (the `.rbs` actually declares the type, for example).
- **Check multi-line comments line by line.** Delete the narration. Keep a
  line that explains a hazard, a why, or cites a source.
- **A tag and its continuation lines go together.** Remove both. Then re-read
  the docstring to check it is still complete and consistent.
- **One file or module per commit** for bulk cleanups, so a repeated mistake
  shows up in the first file.

## Style

Always be terse. One line beats a paragraph. A fragment beats a full
sentence. For example:

```ruby
# Workaround for JRuby not supporting Process.fork.
```

not:

```ruby
# This is a workaround that we need because JRuby does not support
# the Process.fork method, which is used elsewhere in this codebase.
```

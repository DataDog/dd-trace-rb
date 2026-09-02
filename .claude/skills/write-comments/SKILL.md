---
name: write-comments
description: 'Use whenever writing or reviewing a code comment anywhere in this repo (lib, ext, spec, sig, docs, CI config, etc.) – e.g. "add a comment", "explain this in a comment", "is this comment worth keeping". Enforces dd-trace-rb comment-noise conventions.'
---

# Writing code comments

## Code comments

Default to **no comment**. A comment must earn its place by saying something the code cannot. Always be terse.

**Write a comment only when:**

- It explains *why*, not *what*: a non-obvious tradeoff, a workaround for an upstream bug (link it), a perf choice that looks wrong but isn't. E.g.:
  ```ruby
  # Note: this does not use Core::Utils::Time.now because this constant
  # gets initialized before a user has a chance to configure the library.
  START_TIME = ::Time.now.utc.freeze
  ```
- It warns of a real hazard: ordering constraints, thread/async safety, mutation of a shared value, a caller invariant that isn't type-enforced. E.g.:
  ```ruby
  # Supports synchronous code flow *only*. Usage across
  # multiple threads will result in incorrect relationships.
  # For async support, a {Datadog::Tracing::TraceOperation} should be employed
  # per execution context (e.g. Thread, etc.)
  class TraceOperation
  ```
- It documents a public API contract in YARD docstring format — and only for exported/public surfaces. E.g.:
  ```ruby
  # Returns the baggage for the current trace.
  #
  # If there is no active trace, a new one is created.
  #
  # @return [Datadog::Tracing::Distributed::Baggage] The baggage for the current trace.
  # @public_api
  def baggage
  ```
- It cites an external source: spec section, RFC, ticket, formula, algorithm name. This is a public repo — never cite or link an internal-only resource (an internal RFC, wiki page, Slack thread, JIRA ticket, incident, or other datadoghq-internal reference), even by name with no URL; cite only sources a non-Datadog reader can look up themselves. E.g.:
  ```ruby
  # Golden ratio constant for optimal distribution.
  # @see https://en.wikipedia.org/wiki/Hash_function#Fibonacci_hashing
  DEFAULT_KNUTH_FACTOR = 11400714819323198485
  ```

**Never write:**

- Narration of code the comment sits near — not just the literal next line, but any nearby block, loop, or call whose behavior the comment merely describes in prose. E.g.:
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
- Repetition of what a good name already says — if the comment adds no information the identifier doesn't already convey, delete the comment; if the identifier is too vague to convey it, rename instead of commenting.
- Restatements of the type signature in prose on non-public surfaces. Type the parameter in `sig/` (see the `write-rbs` skill) instead of restating it in a `@param`/`@return` comment. This does not apply to `@public_api` YARD docs (see the `baggage` example above) — those tags are the public contract, not internal type narration. E.g.:
  ```ruby
  # @param mod [Module] The module
  def safe_mod_name(mod)
  ```
- Duplicates of something already stated in a nearby docstring or README. State it once, in the most discoverable place.
- The same comment copy-pasted across multiple call sites or files in one diff — a "shotgun surgery" signal. Consolidate the logic or the explanation into one place and reference it from the others, rather than repeating it.
- Narration of the change or of your own process. That belongs in the commit message or PR description. E.g.:
  ```ruby
  # Added error handling
  # Now using the new API
  ```
- Comments on obvious imports, getters/setters, or trivial one-line wrappers.

**Ratio check before finishing:** if a diff has more than roughly one comment per 15 lines of new code, or if any comment would still be true after deleting the code it narrates, cut comments until that stops being the case.

**When editing existing files:** do not add comments to code you merely moved or reformatted. For comments outside the scope of your change, don't remove them unless they are now factually wrong — that's unrelated cleanup churn. Comments on code you're actually touching or reviewing still follow the "Never write" rules above, even if factually correct.

**Prefer over commenting:** a clearer name, an extracted well-named function, a named constant instead of a literal, or a test that demonstrates the behavior.

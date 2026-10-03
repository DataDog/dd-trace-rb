# Inline RBS

Inline RBS keeps a file's types in the `.rb` itself as comments the rbs-inline
transpiler reads, in place of a separate `sig/*.rbs`. It has two comment
syntaxes for methods: doc-style `# @rbs` annotations and compact
`#: (...) -> ...` signatures. Attributes take a trailing `#:`.

## Rules

- Standalone `sig/` is the repo default – inline mode is opt-in per file via
  `inline: true` in the `Steepfile`; without that line the comments go unchecked
- Prefer one mode per file, but a file MAY keep a `sig/*.rbs` alongside
  `inline: true` when some information can't yet live inline; Steep reads both
- SHOULD keep a file inline only when it is small and self-contained; otherwise
  mirror it in `sig/`
- SHOULD use doc-style annotations for new method signatures – one
  `# @rbs <param>:` line per parameter plus a `# @rbs return:` line
- MUST NOT rewrite an existing valid compact `#: (...) -> ...` signature solely
  for style
- NEVER mix doc-style and compact annotations on the same method
- When using doc-style annotations, ALWAYS give a `# @rbs return:` line, `void`
  included – NEVER leave the return implicit
- Attributes have no `# @rbs` form – MUST type them with a trailing `#: Type`, their
  only inline syntax

## Examples

Every method annotates its return, `void` included:

```ruby
# Good
# @rbs name: String
# @rbs return: void
def name=(name)
  @name = name
end

# Bad – return left implicit
# @rbs name: String
def name=(name)
  @name = name
end
```

Prefer doc-style annotations for new signatures, preserve existing compact
signatures, and don't mix the forms on the same method:

```ruby
# Good – preferred for new signatures
# @rbs key: String
# @rbs value: String
# @rbs return: void
def set_tag(key, value)
  tags[key] = value
end

# Good – preserve an existing compact signature
#: (String, String) -> void
def set_tag(key, value)
  tags[key] = value
end

# Bad – per-param `# @rbs` mixed with a compact `#:` method-type on the same method
# @rbs key: String
#: (String, String) -> void
def set_tag(key, value)
  tags[key] = value
end
```

Readers take a trailing `#:` – there is no `# @rbs` form for them:

```ruby
# Good
attr_reader :name #: String

# Bad – no `# @rbs` attribute form exists
# @rbs name: String
attr_reader :name
```

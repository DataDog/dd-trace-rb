# Type aliases

Use a type alias when the same composite shape repeats, or a shape carries a
domain meaning worth naming

## Rules

- SHOULD extract a repeated shape into `type name =` and bind every use, so it
  cannot drift between declarations
- MUST define the alias where the value is produced, not where it is consumed
- MUST name the alias after the domain concept, NEVER after its representation
  (`struct`, `structure`, `hash`)
- NEVER alias a single-use shape – inline it, and promote only on reuse or domain
  meaning
- SHOULD layer aliases when a value is a union of already-named types

## Examples

Bind every signature to one name, so the shape can't drift apart:

```rbs
# Good – one shape, one name
type tags = Hash[String, String]

def fixed_tags: () -> tags

def merge_tags: (tags base, tags extra) -> tags

# Bad – copy-pasted shape, already drifting (Symbol values crept in)
def fixed_tags: () -> Hash[String, String]

def merge_tags: (Hash[String, String] base, Hash[String, Symbol] extra) -> Hash[String, String]
```

Name it for what it means, not how it's built:

```rbs
# Good – the domain concept
type dependency = Hash[Symbol, String]

# Bad – leaks the representation, breaks encapsulation
type struct = Hash[Symbol, String]
```

Don't alias a shape used once – the indirection buys nothing:

```rbs
# Good – used once, inline it
def id: () -> Integer

# Bad – an alias with a single use
type id = Integer

def id: () -> id
```

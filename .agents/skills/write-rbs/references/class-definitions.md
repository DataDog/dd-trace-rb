# Class definitions

Use these when typing a constant built with `Class.new` or `Struct.new`, or
declaring a method that is both instance and singleton

## Rules

- MUST open the class for an empty subclass – `class Foo < Bar` / `end` – NEVER a
  bare `Foo: Bar` constant, which Steep will not type as the class
- MUST type a `Struct.new(...)` constant as a real class – parameterize
  `Struct[E]` with the member value type (a union for mixed members, NEVER a
  tuple), add an `attr_accessor` per member, and a `self.new` returning
  `instance` – NEVER `untyped`
- NEVER leak `struct` / `structure` naming into the public type – it names the
  representation, not the concept
- SHOULD use `def self?.method` for a method that is both instance and singleton

## Examples

Open the class – a bare constant types it as an instance, not the class itself:

```rbs
# Good
class InvalidToken < StandardError
end

# Bad – Steep will not type a bare constant as the class
InvalidToken: StandardError
```

Type a `Struct.new` constant as a real class – accessors and a typed constructor:

```rbs
# Good
class Point < Struct[Integer]
  attr_accessor x: Integer

  attr_accessor y: Integer

  def self.new: (Integer x, Integer y) -> instance
end

# Bad – untyped element leaves point[0], each, to_a untyped
class Point < Struct[untyped]
  attr_accessor x: Integer

  attr_accessor y: Integer

  def self.new: (Integer x, Integer y) -> instance
end
```

`Struct[untyped]` is acceptable only when members are reached solely through the
named accessors; once anything uses the generic Struct API (`#[]`, `#each`,
`#to_a`), type the element with the member value type – a union for mixed
members, NEVER a tuple, which mistypes `#[]` as the whole tuple

Declare a dual instance/singleton method once, so the two can't drift:

```rbs
# Good
def self?.now: () -> Time

# Bad – two declarations that will drift apart
def now: () -> Time

def self.now: () -> Time
```

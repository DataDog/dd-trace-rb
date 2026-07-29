# Class definitions

Use these when typing a constant built with `Class.new` or `Struct.new`, or
declaring a method that is both instance and singleton

## Rules

- MUST open the class for an empty subclass — `class Foo < Bar` / `end` — never a
  bare `Foo: Bar` constant, which Steep will not type as the class
- MUST type a `Struct.new(...)` constant as a real class — `attr_accessor` per
  member and a `self.new` returning `instance` — never `untyped`
- NEVER leak `struct` / `structure` naming into the public type — it names the
  representation, not the concept
- SHOULD use `def self?.method` for a method that is both instance and singleton

## Examples

Open the class — a bare constant types it as an instance, not the class itself:

```rbs
# Good
class InvalidToken < StandardError
end

# Bad — Steep will not type a bare constant as the class
InvalidToken: StandardError
```

Type a `Struct.new` constant as a real class — accessors and a typed constructor:

```rbs
# Good
class Point < Struct[[Integer, Integer]]
  attr_accessor x: Integer

  attr_accessor y: Integer

  def self.new: (?Integer x, ?Integer y) -> instance
end

# Bad — untyped members leave point[0], each, to_a, members untyped
class Point < Struct[untyped]
  attr_accessor x: Integer

  attr_accessor y: Integer

  def self.new: (?Integer x, ?Integer y) -> instance
end
```

`Struct[untyped]` is acceptable only when the code reaches members solely
through the named accessors — the tuple pays off once anything uses the generic
Struct API

Declare a dual instance/singleton method once, so the two can't drift:

```rbs
# Good
def self?.now: () -> Time

# Bad — two declarations that will drift apart
def now: () -> Time

def self.now: () -> Time
```

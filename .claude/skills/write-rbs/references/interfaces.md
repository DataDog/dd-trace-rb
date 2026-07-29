# Interfaces

Use an interface when a parameter or return is duck-typed — you depend on a set
of methods, not a concrete class

## Rules

- MUST name an interface with a leading underscore — `interface _Name`
- MUST list only the domain methods you actually call
- NEVER pad an interface with predicates like `nil?` or `is_a?` just to satisfy
  the checker
- SHOULD prefer an interface over a concrete type when the real object varies
  across versions or frameworks
- NEVER let a prose comment stand in for a contract you could state as an interface

## Examples

Capture what you call, so the signature survives a subclass or a proxy the
framework really hands you:

```rbs
# Good — any object that yields strings fits
interface _Body
  def each: () { (String) -> void } -> void
end

class Writer
  def write: (_Body body) -> void
end

# Bad — Array works in a test, breaks on the body proxy passed in production
class Writer
  def write: (Array[String] body) -> void
end
```

Keep it to the methods you call; don't grow it to silence the checker:

```rbs
# Good — only the domain method the caller uses
interface _Store
  def fetch: (String key) -> String?
end

# Bad — padded with predicates that have nothing to do with the contract
interface _Store
  def fetch: (String key) -> String?
  def nil?: () -> bool
  def is_a?: (Class) -> bool
end
```

State the contract instead of leaving it in a comment:

```rbs
# Good
interface _Callable
  def call: (Env env) -> Response
end

class Stack
  def use: (_Callable middleware) -> void
end

# Bad — the contract lives in a comment, unchecked
class Stack
  # middleware must respond to #call(env)
  def use: (untyped middleware) -> void
end
```

`untyped` is fine when you genuinely can't enumerate the methods — the
anti-pattern above is the comment describing a contract you could have typed

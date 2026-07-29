# Procs

Use a proc type when a value is callable — a stored block, lambda, or proc

## Rules

- MUST type a callable as a proc `^(args) -> ret`, even a loose one — NEVER
  erase its shape to the bare `Proc` class or `untyped`
- SHOULD annotate a rebound receiver with `[self: Type]` inside the proc type

## Examples

State the call shape, even when the arguments are loose:

```rbs
# Good — the callable's shape is visible and checked
@on_error: ^(Exception error) -> void
@hook: ^(*untyped) -> void

# Bad — Proc says "callable" but not its shape; args and return go unchecked
@on_error: Proc
```

When the block runs in a rebound context, say what `self` becomes inside it:

```rbs
# Good — self is the settings context inside the block
type setter = ^(String value) [self: Settings] -> void

# Bad — no self, so method calls in the block resolve against the wrong receiver
type setter = ^(String value) -> void
```

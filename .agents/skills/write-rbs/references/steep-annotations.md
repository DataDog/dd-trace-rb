# Steep annotations

Use these when the Ruby code is correct but Steep cannot infer a type. There
are two forms, a trailing **assertion** and an **annotation** on the line
above, plus `steep:ignore` as a last resort

## Rules

- SHOULD use one only when the code is correct and Steep cannot infer the
  type. NEVER change working Ruby or loosen a signature to satisfy the checker
- A **type assertion** trails an expression as `#: Type`. It narrows a value
  Steep infers too widely, most often an empty literal that has no element type
  to infer. NEVER assert to `untyped`
- An **annotation** sits on its own `# @type` line above the code it governs.
  Use `# @type self: Type` for a `class_eval` / `instance_eval` / DSL block
  Steep cannot follow. Use `# @type var x: Type` / `# @type ivar @x: Type`
  when Steep infers a local, block parameter, or instance variable wrong. Pin
  the real type, NEVER `untyped`
- `steep:ignore` is the last resort. SHOULD scope it to the specific diagnostic
  (`steep:ignore NoMethod`), NEVER bare. To ignore several consecutive lines,
  put `# steep:ignore:start` before them and `# steep:ignore:end` after them

## Examples

Assert an empty literal – it has no element type to infer:

```ruby
# Good – later pushes are checked against the element type
metrics = [] #: Array[String]

# Bad – bare [] infers Array[untyped]; every push goes unchecked
metrics = []
```

Annotate `self` for a DSL block Steep does not follow:

```ruby
# Good – self is the settings context inside the block
# @type self: Configuration::Options::_Settings
apply_defaults { |name| set(name, defaults[name]) }

# Bad – no self annotation; Steep resolves set/defaults on the wrong type and flags them
apply_defaults { |name| set(name, defaults[name]) }
```

Annotate a block parameter Steep infers too widely – an assertion cannot trail it:

```ruby
# Good – names the block parameter to its real type
on_failure_proc: ->(log_failure: true) do
  # @type var log_failure: bool
  component_failed(:worker, log_failure: log_failure)
end

# Bad – no annotation; log_failure stays untyped and the call goes unchecked
on_failure_proc: ->(log_failure: true) do
  component_failed(:worker, log_failure: log_failure)
end
```

When an escape hatch is unavoidable, scope it to the one diagnostic:

```ruby
# Good – only the NoMethod error on this line is ignored
value = raw.dynamic_call # steep:ignore NoMethod

# Bad – a bare ignore hides every present and future error on the line
value = raw.dynamic_call # steep:ignore
```

# Steep annotations

Reach for these when the Ruby is correct but Steep cannot infer a type – never to
reshape working code or loosen a signature. There are two forms plus a last
resort: a trailing **assertion**, an above-the-line **annotation**, and
`steep:ignore`

## Rules

- SHOULD reach for one only when the code is correct and uninferrable – NEVER
  reshape working Ruby or loosen a signature to satisfy the checker
- A **type assertion** trails an expression as `#: Type` – it narrows a value
  Steep infers too widely, most often an empty literal that has no element type
  to infer; NEVER assert to `untyped`
- An **annotation** sits on its own `# @type` line above the code it governs:
  `# @type self: Type` for a `class_eval` / `instance_eval` / DSL block Steep
  cannot follow, and `# @type var x: Type` / `# @type ivar @x: Type` for a local,
  block parameter, or instance variable Steep infers wrong; pin the real type,
  NEVER `untyped`
- `steep:ignore` is the last resort – SHOULD scope it to the specific diagnostic
  (`steep:ignore NoMethod`), NEVER bare, and bracket a run with
  `steep:ignore:start` / `steep:ignore:end`

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

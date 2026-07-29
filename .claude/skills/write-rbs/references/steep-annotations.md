# Steep annotations

Use an inline `# @type` annotation when the Ruby is already correct but Steep
cannot infer the type — a rebound `self`, or a local the checker narrows wrong

## Rules

- SHOULD reach for an annotation only when the code is correct and uninferrable —
  NEVER reshape working Ruby or loosen a signature to satisfy the checker
- MUST pin `self` with `# @type self: Type` inside a `class_eval` / `instance_eval`
  / DSL block Steep cannot follow
- MUST pin a mis-narrowed local or instance variable with `# @type var x: Type` /
  `# @type ivar @x: Type`, to its real type — never `untyped`
- SHOULD keep the annotation and a one-line reason at the top of the block it
  governs
- `steep:ignore` is the last resort — SHOULD scope it to the specific diagnostic
  (`steep:ignore NoMethod`), never bare, and bracket a run with
  `steep:ignore:start` / `steep:ignore:end`

## Examples

Steep does not update `self` for a DSL block — name it, don't silence the errors:

```ruby
# Good — self is the settings context inside the block
# @type self: Configuration::Options::_Settings
apply_defaults { |name| set(name, defaults[name]) }

# Bad — suppresses the resulting errors instead of typing self
apply_defaults { |name| set(name, defaults[name]) } # steep:ignore NoMethod
```

Pin a narrowed variable to its real type, not `untyped`:

```ruby
# Good — the rescue binds a nilable Exception the checker widened
# @type var e: Exception?
e = last_error

# Bad — untyped pins nothing and disables checking on e
# @type var e: untyped
e = last_error
```

When an escape hatch is unavoidable, scope it to the one diagnostic:

```ruby
# Good — only the NoMethod error on this line is ignored
value = raw.dynamic_call # steep:ignore NoMethod

# Bad — a bare ignore hides every present and future error on the line
value = raw.dynamic_call # steep:ignore
```

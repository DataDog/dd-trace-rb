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
- A trailing `#: Type` assertion comments out the rest of the line. NEVER
  close parentheses after it: `super(&(block #: ^() -> void))` swallows
  the closing parens and leaves the file unparseable. Steep reports a
  FALSE GREEN on that broken file. Hoist to a local instead –
  `# @type var wrapped: ^() -> void` above `wrapped = block`
- An **annotation** sits on its own `# @type` line above the code it governs:
  `# @type self: Type` for a `class_eval` / `instance_eval` / DSL block Steep
  cannot follow, and `# @type var x: Type` / `# @type ivar @x: Type` for a local,
  block parameter, or instance variable Steep infers wrong; pin the real type,
  NEVER `untyped`
- Never wrap the whole type of an annotation in parentheses. Write
  `# @type var klass: ::Class & _Iface` and
  `# @type var cb: ^(::String) -> void`. The parenthesized forms
  `# @type var klass: (::Class & _Iface)` and
  `# @type var cb: (^(::String) -> void)` fail to parse in Steep.
- A guard (`if x`, `is_a?`) narrows locals. It does not narrow a fresh
  method call or an ivar, and ivar narrowing dies at ANY method call –
  even an assignment followed directly by `@x.foo` can flag. Hoist the
  value to a local first: `worker = @worker; worker.stop`. Prefer `&.`
  only when nil is genuinely acceptable at that point
- `respond_to?` narrows unreliably on union receivers; `is_a?(Class)`
  narrows every time. Prefer `is_a?` in typed code
- A `# @type self:` annotation applies per scope: a SECOND one later in
  the same method body poisons the FIRST for the whole method. Split the
  scopes instead: annotate the block body, or hoist the differing
  operation into its own method, or use one annotation for the method
  position: the declared block type MUST be assignable INTO the
  annotation. It can widen an `untyped` parameter, but never narrow a
  generic one like `option_type`. To specialize a wide block input, use
  an `is_a?` passthrough guard instead – no annotation can do it
- `steep:ignore` is the last resort – SHOULD scope it to the specific diagnostic
  (`steep:ignore NoMethod`), NEVER bare, and bracket a run with
  `steep:ignore:start` / `steep:ignore:end`
- `steep:ignore` works in trailing form on the code line itself:
  `result = super(*args) # steep:ignore UnexpectedPositionalArgument`.
  A standalone comment line above the code does not suppress the error
  and instead adds a `RedundantIgnoreComment` warning. Use the bare
  diagnostic name without the `Ruby::` prefix.
- A local first assigned `nil` and only later given a value is typed
  `nil` forever. Annotate before the first assignment:
  `# @type var style_name: String?` then `style_name = nil`

## Examples

Assert an empty literal – it has no element type to infer:

```ruby
# Good – later pushes are checked against the element type
metrics = [] #: Array[String]

# Bad – bare [] infers Array[untyped]; every push goes unchecked
metrics = []
```

Annotate `self` where Steep resolves it wrong, but only inside the
body. Two cases: a DSL block Steep does not follow, and a module
method whose host contract it cannot see. When the receiving method's
signature declares the
block's self type, an annotation above the call does nothing. When a
method is defined in a nested module that calls the parent module's
methods, an annotation above the `def` does nothing. Option DSL procs
and prepended-module
methods both need the annotation as the first line inside the body:

```ruby
# Good – self is the settings context inside the block
# @type self: Configuration::Options::_Settings
apply_defaults { |name| set(name, defaults[name]) }

# Good for signature-declared block self – annotate inside the body
option :service do |o|
  o.helper(:service_without_fallback) do
    # @type self: Datadog::Core::Configuration::Settings
    service_name = service
  end
end

# Good for a prepended module – the host includes the parent module,
# which Steep cannot model; annotate inside the def body
module PrependedMethods
  def perform(*args)
    # @type self: Datadog::Core::Workers::Queue
    if work_pending?
      super(*dequeue)
    end
  end
end

# Bad – no self annotation; Steep resolves set on the wrong type and flags it
apply_defaults { |name| set(name, defaults[name]) }
```

Annotate a block parameter Steep infers too widely – an assertion cannot trail it. This works only when the declared block parameter is `untyped` or the annotation accepts everything the caller may pass. When the block type is a wide generic such as `option_type`, no annotation can narrow it – guard instead:

```ruby
# Good – the declared type is untyped, the annotation names the real one
on_failure_proc: ->(log_failure: true) do
  # @type var log_failure: bool
  component_failed(:worker, log_failure: log_failure)
end

# Bad – option_type is generic; this annotation errors under strict checking
o.setter do |value|
  # @type var value: ::Array[::String]?
  next value if value.empty?
end

# Good – narrow a generic block input with a passthrough guard
o.setter do |value|
  next value unless value.is_a?(::Array)
  next value if value.empty?
end
```

When a value's static type is an interface, it loses `is_a?`, `==`,
`class`, and `Hash#key`. Intersect with `Object` in the signature to
restore them – `_Duck & Object` keeps the interface contract and grants
Object's methods:

```rbs
# Good – class checks and Hash#key work on elements of this array
@propagators: Array[_Propagator & Object]

# Bad – is_a? on a plain interface type flags NoMethod
@propagators: Array[_Propagator]
```

When an escape hatch is unavoidable, scope it to the one diagnostic:

```ruby
# Good – only the NoMethod error on this line is ignored
value = raw.dynamic_call # steep:ignore NoMethod

# Bad – a bare ignore hides every present and future error on the line
value = raw.dynamic_call # steep:ignore
```

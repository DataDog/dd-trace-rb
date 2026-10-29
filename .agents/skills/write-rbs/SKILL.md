---
name: write-rbs
description: 'Use when writing, reviewing, or modifying RBS type signatures (sig/**/*.rbs, vendor/rbs/**/*.rbs, or inline #: annotations) or running Steep – e.g. "write rbs", "add type signatures", "type this class", "run steep", "check types". Enforces dd-trace-rb RBS conventions.'
---

# Writing RBS

Signatures live in `sig/`, mirroring `lib/` one `.rbs` per `.rb`. Vendored gem
stubs live in `vendor/rbs/`. ALWAYS check for an existing `.rbs` before writing a
new one

## Core rules

- MUST leave a blank line between every signature
- NEVER add a leading `::` to a Ruby core class – write `Hash`, not `::Hash`
- MUST keep the `::` when the enclosing namespace shadows a core or
  standard-library name – `class Datadog::Core::Logger < ::Logger`, else it
  inherits from itself
- NEVER add a leading `::` to the library's own modules; omit the namespace
  instead – write `Internal::ClassName`, not `::Datadog::Internal::ClassName`
- ALWAYS write a nilable as `Type?`, never `Type | nil`
- NEVER copy Ruby comments into the `.rbs`
- NEVER use `untyped` when the type is inferable from the code
- ALWAYS read the rbs gem's own stdlib declaration before casting a stdlib
  or core-class return (`Gem::Specification.find_by_name("rbs").gem_dir`);
  its declaration is ground truth, and a cast that disagrees with it is
  hiding a real nil
- RBS expresses only `public` and `private` visibility. Declare a
  `protected` method with no modifier.
- NEVER loosen a signature just to satisfy Steep – a signature MUST harden the
  code's real contract, not paper over a checker error
- Use `any` only when every possible type is intentionally valid and the code
  does not depend on the concrete type; use `untyped` when the type is merely
  not-yet-modeled, and be sparing with `any`
- SHOULD reuse the signatures already present, and upgrade any `untyped` you can
  infer

## Vendored signatures

- NEVER write a `vendor/rbs` signature from how the calling code uses the gem –
  inference from usage can be wrong, and the caller may misuse the gem
- ALWAYS read the gem's real source first; ask for its location if you lack it
- SHOULD update stale or missing stubs, but only after seeing that source
- SHOULD pin superclasses, arity, and keyword defaults by probing the
  installed gem or Ruby (`Net::BufferedIO.superclass`,
  `Net::HTTP.instance_method(:initialize).parameters`) before writing a
  stub; the obvious guess is often wrong (BufferedIO's superclass is Object,
  not IO)
- NEVER use `any` in a vendored stub – `any` is a dd-trace-rb type alias, not a
  vendored concept; use `untyped` for genuinely open values there

## Advanced techniques

Open the matching reference when a value calls for more than a plain type:

- duck-typed – you call methods, not a concrete class → `references/interfaces.md`
- a shape that repeats or carries a domain meaning → `references/type-aliases.md`
- an output type that depends on the input type → `references/generics.md`
- a callable → `references/procs.md`
- a `Class.new`/`Struct.new` constant → `references/class-definitions.md`
- correct Ruby the checker can't infer, or a one-off cast → `references/steep-annotations.md`
- a file whose whole signature lives in the `.rb` (rbs-inline) → `references/inline-rbs.md`

## Signature generation

```bash
bundle exec rake "rbs:prototype[lib/<path>.rb]"
```

Prototypes over-emit `untyped` and leading `::`; clean the result against the
rules above

## Steep checks

Always pass `--no-daemon` when using a non-default Steepfile. The daemon
returns stale or empty results for a Steepfile it did not start with, and
silently hides every error.

Validate a new Steepfile or target with a deliberately broken scratch
file, for example a planted `1 + "string"`, before trusting zero-error
output.

Constant errors that appear only in a scoped run may be phantom: scoped
runs skip inline RBS entries (`inline: true`), so constants declared
that way resolve only in full runs. Confirm with a full run before
fixing.

Known rbs 4.2.0 stdlib gaps, verified empirically. Prefer the listed
workaround over a scoped ignore:

- `Numeric#to_i` is not declared. Use `to_int`, which is behavior-
  identical for every Numeric that has `to_i`
- No core class implements `Time::_Timeout`, so `ConditionVariable#wait`
  rejects any typed timeout, and `Numeric` lacks `*`. Keep timing
  values `untyped`, as IntervalLoop already does
- `Net::HTTP#initialize`, `#on_connect`, and `Net::BufferedIO` are
  missing. They are reopened in `vendor/rbs/ruby/0/net_http.rbs`,
  grounded by probing the installed Ruby; extend that file for further
  `Net` gaps instead of adding call-site ignores
- A missing member in a *gem* goes in `vendor/rbs/<gem>/<version>/`;
  a missing member in *stdlib or core Ruby* goes in
  `vendor/rbs/ruby/0/` (never `sig/`, which must mirror `lib/` files);
  a *core-class* return the stdlib types loosely (e.g.
  `RubyVM::YJIT.runtime_stats` as `Hash[untyped, untyped]?`) is best
  absorbed by typing our own wrapper methods, not by casting every call
  site

To test a Steep semantics hypothesis fast, append a scratch `.rbs`
plus `.rb` probe pair to a file already in the checked target. Run the
scoped check, then revert. One such run settled three interface
questions at once.

Pass explicit .rb file paths to `steep check`, never a directory. A
directory argument silently checks zero files and prints a false green.
Confirm the run by checking the file-count progress dots.

While iterating, scope the check to the edited file's Ruby source – a `sig/`
path silently passes even on a broken signature:

```bash
bundle exec steep check lib/datadog/<path>.rb
```

This checks only that file; it will NOT catch breaks in signatures that
reference it. ALWAYS run the full check before treating types as done:

```bash
bundle exec steep check
```

## Known Steep limitations

Verified empirically on PR #6587:

- Steep checks a parameter's default value against the union of its
  overloads' param types. A sentinel-defaulted param
  (`default_value = UNSET` where `UNSET: Object`) can never be narrowed
  by overloads; keep the signature loose (`?Object?`) and cast at call
  sites (`ConfigHelper#fetch`)
- Steep does not flow-narrow ivars: a `return unless @x` guard does not
  narrow later `@x` reads in the same method. Hoist to a local first
  (`lib/datadog/opentelemetry/api/context.rb`,
  `lib/datadog/core/workers/async.rb`)

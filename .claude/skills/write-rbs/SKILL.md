---
name: write-rbs
description: Use when writing, reviewing, or modifying RBS type signatures (sig/**/*.rbs, vendor/rbs/**/*.rbs, or inline # : annotations) or running Steep — e.g. "write rbs", "add type signatures", "type this class", "run steep", "check types". Enforces dd-trace-rb RBS conventions.
---

# Writing RBS

Signatures live in `sig/`, mirroring `lib/` one `.rbs` per `.rb`. Vendored gem
stubs live in `vendor/rbs/`. ALWAYS check for an existing `.rbs` before writing a
new one

## Core rules

- MUST leave a blank line between every signature
- NEVER add a leading `::` to Ruby core classes — write `Hash`, not `::Hash`
- NEVER add a leading `::` to the library's own modules; omit the namespace
  instead — write `Internal::ClassName`, not `::Datadog::Internal::ClassName`
- ALWAYS write a nilable as `Type?`, never `Type | nil`
- NEVER copy Ruby comments into the `.rbs`
- NEVER use `untyped` when the type is inferable from the code
- NEVER loosen a signature just to satisfy Steep — a signature MUST harden the
  code's real contract, not paper over a checker error
- Use `any` only when every possible type is intentionally valid and the code
  does not depend on the concrete type; use `untyped` when the type is merely
  not-yet-modeled, and be sparing with `any`
- SHOULD reuse the signatures already present, and upgrade any `untyped` you can
  infer

## Vendored signatures

- NEVER write a `vendor/rbs` signature from how the calling code uses the gem —
  inference from usage can be wrong, and the caller may misuse the gem
- ALWAYS read the gem's real source first; ask for its location if you lack it
- SHOULD update stale or missing stubs, but only after seeing that source
- NEVER use `any` in a vendored stub — `any` is a dd-trace-rb type alias, not a
  vendored concept; use `untyped` for genuinely open values there

## Advanced techniques

Open the matching reference when a value calls for more than a plain type:

- duck-typed — you call methods, not a concrete class → `references/interfaces.md`
- a shape that repeats or carries a domain meaning → `references/type-aliases.md`
- an output type that depends on the input type → `references/generics.md`
- a callable → `references/procs.md`
- a `Class.new`/`Struct.new` constant → `references/class-definitions.md`
- correct Ruby the checker can't infer → `references/steep-annotations.md`
- a type kept in the `.rb` file, or a one-off cast → `references/inline-rbs.md`

## Signature generation

```bash
bundle exec rbs prototype rb lib/<path>.rb > sig/<path>.rbs
```

Prototypes over-emit `untyped` and leading `::`; clean the result against the
rules above

## Steep checks

A single-target run checks only that file — it will NOT catch breaks in
signatures that reference it. ALWAYS run the full check before treating types as
done

Quick single-target run while iterating:

```bash
bundle exec steep check sig/datadog/<path>.rbs
```

Full, authoritative check:

```bash
bundle exec steep check
```

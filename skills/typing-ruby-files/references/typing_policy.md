# Typing Policy

## Contents

1. Target prioritization
2. Shared type aliases
3. Boolean types: `bool`, `bool?`, and `boolish`
4. Primitive types: `::` prefixes and `any` vs `untyped`
5. Scope gates
6. Mandatory checks
7. Steepfile un-ignoring
8. Progress tracking
9. Upstream improvements
10. Pull request conventions
11. Transient-gap comment rules
12. Compromise reporting schema
13. Report completeness checklist

## Target prioritization

Work through files in order of typing difficulty — low-hanging fruit first.

### Tier 1: easy wins (do first)

Pick files where every type is unambiguous from the source alone:

- Return types are literals, frozen strings, simple primitives (`Integer`, `String`, `bool`).
- No branching between different return types.
- No metaprogramming, dynamic dispatch, or DSL-generated methods.
- Small surface area (few public methods, short file).

Examples: constant readers, simple formatters, environment wrappers.

### Tier 2: moderate (do next)

Files where types are precise but require reading callers or related files:

- Nullable returns (`String?`) with clear guard patterns.
- Union types across a small, closed set (`String | Symbol`).
- Methods that delegate to well-typed dependencies.

### Tier 3: complex (do last)

Files where full precision requires design decisions or is blocked:

- Heavy metaprogramming or `define_method`/`method_missing`.
- Open-ended hashes, generic containers, callback registries.
- Types that depend on untyped upstream gems or Steep/RBS limitations.

### Selection rule

When choosing the next file to type, scan the existing `sig/` files for `untyped` occurrences and pick the lowest-tier candidate. Within the same tier, prefer files with fewer `untyped` occurrences (faster to complete) and files that are dependencies of other untyped code (unblocks future work).

## Shared type aliases

When a type pattern repeats across many signatures, define it once in a shared location and reference it everywhere. This avoids drift and makes the type vocabulary consistent.

Shared aliases live in `vendor/rbs/` stubs. For example, Rack types are defined in `vendor/rbs/rack/0/rack.rbs`:

```rbs
module Rack
  type env = ::Hash[::String, untyped]
  type response = [::Integer, ::Hash[::String, ::String], ::Array[::String]]
  type app = ^(env) -> response
end
```

All Rack middleware signatures should use `Rack::env`, `Rack::response`, and `Rack::app` instead of inline types or local aliases.

When introducing a shared alias:

1. Check if the type already exists in `vendor/rbs/` or `sig/`.
2. If a local duplicate exists (e.g. module-scoped `rack_response`), replace it with the shared version.
3. Do not reorder or reformat unrelated lines in files like Steepfile — keep diffs minimal.
4. Preserve the existing order of methods and declarations in RBS files. New declarations (e.g. `@app:`) may be added in the conventional place (instance variables before methods) but existing methods must not be reordered.

## Boolean types: `bool`, `bool?`, and `boolish`

RBS provides three ways to express truthiness. Choose based on semantic intent, not convenience.

### `bool` (`true | false` only)

Use when the method always returns `true` or `false`. This is the right choice for most predicate methods.

```rbs
def empty?: () -> bool
def available?: () -> bool
```

### `boolish` (`= top` — any Ruby value used for its truthiness)

Use **only** for block return types in iterator methods where the only thing that matters is whether the block's return is truthy or falsy:

```rbs
def select: () { (Elem) -> boolish } -> Array[Elem]
def filter_map: () { (Elem) -> boolish } -> Array[untyped]
```

`boolish` is defined as `type boolish = top` in RBS (any Ruby value). It signals that only the truthy/falsy nature is used, not the value itself. **Do not use `boolish` as a standalone method return type** — use `bool` or `bool?` for method return types.

### `bool?` (`nil | true | false`) — use sparingly

Use only when `nil` has **distinct semantic meaning from `false`** to callers — i.e., callers write `result.nil?` or distinguish nil from false explicitly.

**`?` methods and `bool?` are usually a mismatch.** Methods ending in `?` are predicate methods. Callers use their return value as a condition (`if obj.available?`), treating both `nil` and `false` identically. Adding `nil` to the type only widens it without adding information. The common case where a `?` method appears to return `bool?` is because its body has an expression like `defined?(x) && x.responds_to?(y)` — which Steep types as `nil | bool`. This is a Steep inference artifact, not a semantic choice. When you see this, prefer `bool` if callers never get `nil` in practice, or leave it as `bool?` only if you cannot narrow it without an inline assertion.

**Rule of thumb:** before writing `bool?` for a `?` method, ask "would a caller ever write `result.nil?`?" If no, use `bool`.

## Primitive types: `::` prefixes and `any` vs `untyped`

### Always prefix Ruby built-in types with `::`

When referencing native Ruby types in RBS signatures, prefix them with `::` to make clear they resolve from the root namespace, not a local constant:

```rbs
# Good
def process: (::String name, ::Integer count) -> ::Array[::Symbol]

# Avoid
def process: (String name, Integer count) -> Array[Symbol]
```

This applies to: `::String`, `::Integer`, `::Float`, `::Symbol`, `::Array`, `::Hash`, `::Proc`, `::IO`, `::Mutex`, `::Thread`, `::Logger`, and all other stdlib types.

Exception: type aliases defined within this project (e.g. `any`, `Rack::env`, `WAF::Result`) do not need `::` prefixes — they already live in the correct namespace.

### `any` vs `untyped`: intentional vs undecided

This project defines a type alias in `sig/datadog.rbs`:

```rbs
type any = untyped
```

Use these two differently:

| Type | Meaning | When to use |
|------|---------|-------------|
| `any` | **Intentionally open** — the value is genuinely polymorphic and accepting anything is correct | Buffers, caches, generic containers, public APIs that accept arbitrary user objects |
| `untyped` | **Undecided** — we haven't determined the right type yet; this is a placeholder | Every other case; it marks work still to be done |

```rbs
# Good: buffer stores any object by design
def push: (any item) -> void

# Good: type not yet determined, mark as todo
def obscure_transform: (untyped input) -> untyped

# Bad: using untyped to mean "accepts anything" obscures intent
def push: (untyped item) -> void
```

When you are improving a signature and the current `untyped` is genuinely intentional (e.g. a hash of arbitrary user data), replace it with `any`. When you are leaving something untyped because you don't know the right type, leave `untyped` as-is — it signals future work.

## Scope gates

1. Accept only a small target list under `lib/**/*.rb`.
2. Detect stale paths first.
3. For each existing target, require mapped `sig/**/*.rbs` path:
   `lib/path/file.rb` -> `sig/path/file.rbs`.
4. Fail if any target is stale or any mapped signature is missing.
5. Keep work limited to the resolved scope unless diagnostics prove a cross-file typing dependency.

## Mandatory checks

1. Before edits, capture `untyped` inventory in mapped signatures.
2. After edits, capture inventory again and compute delta.
3. Run both:
   `bundle exec steep check <scope>`
   `bundle exec steep check --severity-level=information <scope>`
4. If any `lib/**` runtime code changed, run targeted behavior tests and capture output with:
   `2>&1 | tee /tmp/full_rspec.log | grep -E 'Pending:|Failures:|Finished' -A 99`
5. Do not mark the work complete without report artifacts that include:
   `scope.json`, `untyped.before.json`, `untyped.after.json`, `steep.json`, and final report files.

## Steepfile un-ignoring

After completing typing work, check whether any files ignored in the Steepfile can now pass `steep check` and be un-ignored. Reducing the ignore list is a high-value outcome of typing work — it means more code is covered by continuous type checking.

### Workflow

1. Identify ignored files related to the current work:
   `grep 'ignore.*<pattern>' Steepfile`
2. Temporarily remove their ignore directives.
3. Run `steep check` on each file individually to get per-file error counts.
4. For files with 0 errors: remove the ignore directive permanently.
5. For files with a small number of fixable errors (1-3): fix them if the fixes are trivial (e.g. local variable for type narrowing, adding an ivar declaration). Include the fixes in the same PR.
6. For files with many errors or errors requiring significant work: leave them ignored. Optionally note the error count in a comment for future reference.
7. After removing any ignore directives, run the full `steep check` to confirm no regressions.

### What counts as a trivial fix

- Assigning a repeated method call to a local variable so Steep can narrow the type through a guard (e.g. `&&`, `if`).
- Adding a missing instance variable declaration (`@foo: Type`) to the RBS file.
- Adding an inline Steep type assertion (`#:`) to help Steep through control flow it cannot prove.

### What does not count

- Adding new RBS stubs for external gems.
- Rewriting Ruby code to satisfy the type checker.
- Suppressing errors with `untyped` just to pass.

## Pull request conventions

Use a simple title in one of these formats:

- `Add typing for <Name>` — when typing a file for the first time or adding new type precision.
- `Fix typing for <Name>` — when correcting an existing signature.

`<Name>` is either the class/module name (e.g. `Core::Chunker`) or the Ruby file name (e.g. `core/chunker.rb`). Keep the title short — use the class name or basename when the full path is long.

## Transient-gap comment rules

Apply this only when the gap is likely a Steep/RBS limitation, not a local refactorable design issue.

Comment requirements in affected Ruby/RBS code:

1. State transient rationale.
2. Include upstream issue link.
3. State explicit removal condition.

Issue lookup order:

1. Steep search:
   `https://github.com/soutaro/steep/issues?q=is%3Aissue%20MY_TEXT`
2. RBS search:
   `https://github.com/ruby/rbs/issues?q=is%3Aissue%20MY_TEXT`

If no relevant issue exists, include:

`no known upstream issue as of YYYY-MM-DD`

Use the current execution date for `YYYY-MM-DD`.

Do not classify a gap as transient when a reasonable refactor can remove it. Report the required refactor as actionable debt instead.

## Compromise reporting schema

For each remaining typing compromise, report all fields:

```json
{
  "offence": "what typing gap remains",
  "cause": "why the gap exists",
  "chosen_solution": "containment now + follow-up action",
  "evidence": {
    "file": "path/to/file.rbs",
    "line": 123,
    "diagnostic_id": "Ruby::SomeDiagnostic",
    "message": "diagnostic message text"
  }
}
```

If no direct steep diagnostic exists, set:

```json
{
  "evidence": "no direct diagnostic"
}
```

Also include complete post-edit file:line inventory of all remaining `untyped` in scope.

## Progress tracking

Maintain a tracking file at `skills/typing-ruby-files/references/typing_progress.md` that records every file typed and every Steepfile un-ignore. This provides continuity across sessions and prevents duplicate work.

The tracking file should list:
- Each PR merged or open, with its branch name and number.
- The files typed in each PR and what changed (e.g. "replaced untyped with Rack types").
- Steepfile ignores removed.
- Known blockers or files deferred with reasons.

Update the tracking file at the end of each typing session or PR.

## Upstream improvements

When a typing gap could be resolved by contributing to an upstream RBS definition (Ruby stdlib via `ruby/rbs`, or a gem's RBS repo), record it in `skills/typing-ruby-files/references/upstream_improvements.md` instead of accepting a local workaround indefinitely.

Each entry should include: the upstream file and repo, the problem, the suggested RBS change, and a reference to our local workaround.

## Report completeness checklist

1. Stale-path check result.
2. Mapping check result (`lib` <-> `sig`).
3. `untyped` before/after totals and delta.
4. Full post-edit `untyped` file:line inventory.
5. Steep results for normal and information severity.
6. Targeted test command and result if runtime `lib/**` changed.
7. Compromise entries with offence/cause/chosen_solution/evidence.

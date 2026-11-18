# Maintainability

Duplication, dead code, comments, naming, and test value.

For comments, apply the [write-comment skill](../../write-comment/SKILL.md) rules instead of restating them here.

**When planning:** take the rules below into account when designing the change.

**When reviewing:** report a finding when the diff matches a rule's `Flag:` line and no `Not when:` applies, or when it has a clear problem in this lens's area that no rule covers (mark it `no rule`). Cite the rule ID and point to the existing helper or simpler shape.

## 1. Duplication and reuse

### MAINT-1.1: Reuse existing helpers and built-ins instead of reimplementing them
- Flag: an `env_parser` or `o.setter` that redoes the coercion `o.type :int`/`:float`/`:bool` already performs (`Integer(...)`, `Float(...)`, `to_i` with a fallback; see `coerce_env_variable` in `core/configuration/option.rb`), even inside a local helper; fallback logic that `CaptureLimits.resolve` already implements; or near-duplicate rake tasks without a shared helper.
- ❌ `o.env_parser { |value| Integer(value, 10) }`
- ✅ `o.type :int`

### MAINT-1.2: Use one generic mechanism with a guard instead of special-casing one input
- Flag: packaging or script code that special-cases one gem, file, or job name where a generic rule with an explicit conflict check would cover every case.
- ❌ `if [[ "$gem" == datadog-* ]]; then cp "$orig/lib/libdatadog.so" "$dest/lib/"; fi`
- ✅ `cp -an "${orig}/." "${dest}/"` after checking that no shared path differs.

### MAINT-1.3: Write CI retries as a loop in one step, not repeated action steps
- Flag: the same workflow step copied once per attempt, with backoff steps between them and outputs gathered afterwards.

### MAINT-1.4: Name shared wire keys and magic numbers as constants
- Flag: a metadata or wire key (including any `_dd.*` or `__dd_*` key) written as a string literal outside the subsystem's `ext.rb`, a key literal repeated in both writer and reader, or bit masks such as `0x7F` and `0x80` inline.
- ❌ `while value > 0x7F; bytes << ((value & 0x7F) | 0x80)`
- ✅ `while value > LOW_7_BITS_MASK; bytes << ((value & LOW_7_BITS_MASK) | CONTINUATION_BIT)`

### MAINT-1.5: Match the idiom of sibling methods
- Flag: one method in a group of siblings switching to a different access or nil-safety pattern.
- ❌ `stats = ::RubyVM::YJIT.runtime_stats; stats[:ratio_in_yjit] if stats`
- ✅ `::RubyVM::YJIT.runtime_stats&.[](:ratio_in_yjit)` (as its siblings do)

## 2. Dead and redundant code

### MAINT-2.1: Remove forwarding-only wrappers
- Flag: a method whose body only forwards to another method with the same arguments, or a wrapper that only specs call.
- Not when: the wrapper is a product facade or public API (see `DES-1.1`).

### MAINT-2.2: Remove guards for states that can't happen, and never let a guard silently accept bad input
- Flag: every new `&.`, `nil?`, `is_a?` or `respond_to?` guard in the diff on a value whose type is already guaranteed (an ivar set in `initialize`, an `Integer` status code from a built-in adapter), with no comment naming the case it handles (for example, custom adapters). Also flag a guard in an `o.setter` or `env_parser` that returns the raw value, `nil`, `false`, or a default for a wrongly typed or unrecognised value; declare `o.type` or raise `ArgumentError` instead.
- Not when: warn-and-fall-back is the agreed cross-SDK behaviour for that product's env vars.
- ❌ `o.setter { |value| value.respond_to?(:empty?) ? value : nil }`
- ✅ `o.type :array` (or `raise ArgumentError, "Invalid user_id_denylist: #{value.inspect}"`)

### MAINT-2.3: Keep the diff to the change
- Flag: unrelated whitespace, file-mode, or file changes, or a new input or env var equivalent to one already available (for example, `HEAD_SHA` beside `HEAD_REF`).

### MAINT-2.4: Define refresh, staleness detection, and ownership before adding a checked-in generated data file
- Flag: a new or regenerated checked-in data file (JSON/YAML timings, weights, generated lists) where the PR or docs do not say all three of: how to regenerate it, when it must be regenerated (for example, when a task is added or removed), and what detects that it is stale or missing entries. Also ask whether an existing product (for example, CI Visibility) should own the data.

## 3. Naming

### MAINT-3.1: Name classes and fields for what they hold
- Flag: generic class names (`Accumulator`, `Store`, `Manager`), or a field named after a whole concept that holds only part of it (a `tracestate` field holding only other vendors' entries).

### MAINT-3.2: Follow Ruby naming contracts
- Flag: check the body of every new method named `fetch*`, ending in `?`, or named `build`. Flag a `fetch*` that can return `nil` instead of raising (rename to `find*`), a `?` method that can return a non-boolean (including through `||` with a nilable field), or a pure string serializer named `build` instead of `to_s`. Report the naming even if the method has other problems.

### MAINT-3.3: Prefer positive names and conditions
- Flag: every `unless x.empty?`, `unless x.nil?`, `if !x` or `unless !x` in the diff where a positive form exists (`if x.any?`, `if x`), and negative state flags (`@closed`) where a positive one (`@active`) reads as well. Report each location.

### MAINT-3.4: Use descriptive snake_case names
- Flag: single-letter locals for meaningful values (`e` for an entry, `v`, `n`), or camelCase names carried over from another SDK in code, comments, or spec descriptions.
- ❌ `entries.each { |e| flat << e.value }`
- ✅ `entries.each { |entry| values << entry.value }`

## 4. Comments and documentation

### MAINT-4.1: Explain an algorithm once, at its home
- Flag: the same multi-line explanation, spec URL, or `@see` link appearing in two or more places in the diff (search added lines for repeated URLs and repeated sentences), or a constant's comment carrying reasoning that belongs to one call site. Name the one place it should live.

### MAINT-4.2: Give the Ruby version when a comment describes a core API limitation
- Flag: a comment claiming a Ruby core method is missing or behaves differently, without the version that changed it (for example, `ObjectSpace::WeakMap#delete` exists from Ruby 3.3).

### MAINT-4.3: Update YARD `@param` tags when a documented signature changes
- Flag: a parameter added, removed, or renamed on a method that already has `@param` tags, without updating them.

### MAINT-4.4: Keep agent guidance concise and plain
- Flag: in new or changed `AGENTS.md`, skill, or agent-guide text, read every changed line and flag: a new section where a bullet in an existing list would do; jargon or idioms a newcomer would not know (for example, "bracket a run"); emphatic capitals beyond RFC 2119 requirement keywords; links to other SDKs' PRs or discussions that do not help this repo's readers; or a rule a cop already enforces.

## 5. Test value

### MAINT-5.1: Reproduce build-environment fixes in CI
- Flag: a fix for a build, install, or packaging bug (paths with spaces, compiler flags, missing headers, platform quirks) whose only test is a unit spec or none. Ask for a step in `.github/workflows/build-gem.yml`, or the relevant build job, that reproduces the original failure; a spec that stubs the environment does not count.

## Don't flag
- A custom rake task that wraps a tool's Ruby API when the upstream rake task can't express the repo's needs (for example, per-lockfile ignore lists).
- Removing an instruction from a subsystem agent guide when the root `AGENTS.md` already carries it.

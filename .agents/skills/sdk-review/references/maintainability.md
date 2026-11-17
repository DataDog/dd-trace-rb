# Maintainability

Duplication, dead code, comments, naming, and test value.

For comments, apply the [write-comment skill](../../write-comment/SKILL.md) rules instead of restating them here.

**When planning:** take the rules below into account when designing the change.

**When reviewing:** report a finding when the diff matches a rule's `Flag:` line and no `Not when:` applies, or when it has a clear problem in this lens's area that no rule covers (mark it `no rule`). Cite the rule ID and point to the existing helper or simpler shape.

## 1. Duplication and reuse

### MAINT-1.1: Reuse existing helpers and built-ins instead of reimplementing them
- Flag: an `env_parser` that redoes the coercion `o.type :int` already performs, fallback logic that `CaptureLimits.resolve` already implements, or near-duplicate rake tasks without a shared helper.
- ❌ `o.env_parser { |value| Integer(value, 10) }`
- ✅ `o.type :int`

### MAINT-1.2: Use one generic mechanism with a guard instead of special-casing one input
- Flag: packaging or script code that special-cases one gem, file, or job name where a generic rule with an explicit conflict check would cover every case.
- ❌ `if [[ "$gem" == datadog-* ]]; then cp "$orig/lib/libdatadog.so" "$dest/lib/"; fi`
- ✅ `cp -an "${orig}/." "${dest}/"` after checking that no shared path differs.

### MAINT-1.3: Write CI retries as a loop in one step, not repeated action steps
- Flag: the same workflow step copied once per attempt, with backoff steps between them and outputs gathered afterwards.

### MAINT-1.4: Name shared wire keys and magic numbers as constants
- Flag: a metadata or wire key string literal written in both the writer and the reader, or bit masks such as `0x7F` and `0x80` inline. Put keys in the subsystem's `ext.rb`.
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

### MAINT-2.2: Remove guards for states that can't happen, or say when they apply
- Flag: `&.` on an ivar always set in `initialize`, or an `is_a?` check on a value that always has that type, with no comment naming the case it handles (for example, custom adapters).

### MAINT-2.3: Keep the diff to the change
- Flag: unrelated whitespace, file-mode, or file changes, or a new input or env var equivalent to one already available (for example, `HEAD_SHA` beside `HEAD_REF`).

### MAINT-2.4: Define refresh, staleness detection, and ownership before adding a checked-in generated data file
- Flag: a checked-in manifest (timings, weights, generated lists) with no documented refresh procedure or no check that detects when it is stale.

## 3. Naming

### MAINT-3.1: Name classes and fields for what they hold
- Flag: generic class names (`Accumulator`, `Store`, `Manager`), or a field named after a whole concept that holds only part of it (a `tracestate` field holding only other vendors' entries).

### MAINT-3.2: Follow Ruby naming contracts
- Flag: a `fetch*` method that returns `nil` instead of raising (use `find*`), a `?` method that can return a non-boolean, or a pure string serializer named `build` instead of `to_s`.

### MAINT-3.3: Prefer positive names and conditions
- Flag: negative state flags (`@closed`) where a positive one (`@active`) reads as well, or `unless x.empty?` where `if x.any?` works.

### MAINT-3.4: Use descriptive snake_case names
- Flag: single-letter locals for meaningful values (`e` for an entry, `v`, `n`), or camelCase names carried over from another SDK in code, comments, or spec descriptions.
- ❌ `entries.each { |e| flat << e.value }`
- ✅ `entries.each { |entry| values << entry.value }`

## 4. Comments and documentation

### MAINT-4.1: Explain an algorithm once, at its home
- Flag: the same explanation or `@see` link repeated across files, or a constant's comment carrying reasoning that belongs to one call site.

### MAINT-4.2: Give the Ruby version when a comment describes a core API limitation
- Flag: a comment claiming a Ruby core method is missing or behaves differently, without the version that changed it (for example, `ObjectSpace::WeakMap#delete` exists from Ruby 3.3).

### MAINT-4.3: Update YARD `@param` tags when a documented signature changes
- Flag: a parameter added, removed, or renamed on a method that already has `@param` tags, without updating them.

### MAINT-4.4: Keep agent guidance concise and plain
- Flag: new `AGENTS.md` or skill text that adds a section where a bullet in an existing list would do, uses unexplained jargon or emphatic capitals, includes links that don't help this repo's readers, or restates a rule a cop already enforces.

## 5. Test value

### MAINT-5.1: Reproduce build-environment fixes in CI
- Flag: a fix for a build-environment bug (for example, building in a path with spaces) without a step in `.github/workflows/build-gem.yml` or a similar job that reproduces it.

## Don't flag
- A custom rake task that wraps a tool's Ruby API when the upstream rake task can't express the repo's needs (for example, per-lockfile ignore lists).
- Removing an instruction from a subsystem agent guide when the root `AGENTS.md` already carries it.

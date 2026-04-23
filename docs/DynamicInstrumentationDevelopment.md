# Dynamic Instrumentation Development Guide

## Iseq Lifecycle and GC

### Background

DI line probes work by enabling a `TracePoint` targeted at a specific
`RubyVM::InstructionSequence` (iseq) and line number. The iseq must cover
the target line — a whole-file iseq covers all lines, while a per-method
iseq covers only the method body.

`CodeTracker` maintains a registry mapping file paths to iseqs. The
`:script_compiled` tracepoint populates this at load time. The
`backfill_registry` method recovers iseqs for files loaded before tracking
started by walking object space via `DI.all_iseqs` (C extension).

### Iseq types created when Ruby loads a file

When Ruby loads a file via `require`/`require_relative`, it creates several
iseq objects:

| Type | Description | `first_lineno` | Created by |
|------|-------------|-----------------|------------|
| `:top` | Whole-file iseq, covers all lines | 0 | `rb_iseq_new_top` (require/load) |
| `:main` | Entry script only (`ruby script.rb`) | 0 | `rb_iseq_new_main` |
| `:class` | One per class/module body | >= 1 | class/module keyword |
| `:method` | One per method definition | >= 1 | def keyword |
| `:rescue`/`:ensure` | Rescue/ensure blocks | >= 1 | rescue/ensure keyword |

`DI.iseq_type` (wraps `rb_iseq_type`, Ruby 3.1+) returns the type as a
Symbol. On Ruby < 3.1, `first_lineno == 0` identifies whole-file iseqs.

### What survives GC

After file loading completes, iseq objects are subject to garbage collection
like any other Ruby object. What keeps them alive:

| Type | Survives GC? | Reference holder |
|------|-------------|------------------|
| `:method` | **Yes** | Method objects on the class (`UnboundMethod` → iseq) |
| `:class` | **Unreliable** | May survive via class constant, not guaranteed |
| `:top` | **No** | Nothing. `$LOADED_FEATURES` stores path strings, not iseqs. |
| `:rescue`/`:ensure` | **No** | Follow their parent iseq |

The `:top` iseq executes once (defining classes/methods/constants) and is
then unreferenced. GC can collect it at any time.

In practice:
- With no GC pressure, iseqs survive indefinitely (not yet collected)
- With allocation pressure or explicit `GC.start`, `:top` is collected
- After aggressive GC, typically only `:method` iseqs survive

### Implications for backfill

Prior to per-method fallback, `backfill_registry` only stored whole-file
(`:top`/`:main`) iseqs. If the `:top` iseq was GC'd before backfill ran,
the file was completely untargetable — line probes got
`DITargetNotInRegistry`. In a measured Rails app with 146 gems, this
affected 86% of pre-loaded files (1987 of 2309).

**Per-method fallback** addresses this by storing per-method/block/class
iseqs in a separate `per_method_registry` (keyed by path). These iseqs
survive GC because they're referenced by the class's method table via
`UnboundMethod`. They cover only their method body's lines, not the whole
file — but since probes almost always target code inside methods, this
is sufficient.

`backfill_registry` now populates two registries:

1. **`registry`** — whole-file iseqs (`:top`/`:main` with
   `first_lineno == 0`). Require/load produce these via `rb_iseq_new_top`
   with `first_lineno == 0`; this distinguishes them from compile_file
   `:top` iseqs which have `first_lineno == 1`.
2. **`per_method_registry`** — per-method/block/class iseqs, as fallback.

**Lookup:** `iseq_for_line(suffix, line)` checks `registry` first. If no
whole-file iseq exists, it searches `per_method_registry` for an iseq
whose `trace_points` include the target line with a subscribable event
type (`:line`, `:return`, `:b_return` — matching `hook_line`'s event
subscription). Lines that only carry `:call` are excluded: a `def` line
in the per-method iseq for the method being defined has only a `:call`
event (the enclosing scope's iseq has the `:line` event for that line, but
may be GC'd). TracePoint cannot bind `:line` at that position in that iseq.

If neither registry has a match → `DITargetNotInRegistry` → pending state.
This affects ~14% of pre-loaded files: setup-only files that define no
methods and whose `:top` iseq was GC'd.

**`:script_compiled`** (the primary mechanism for files loaded after
tracking starts) is unaffected — it captures whole-file iseqs at load time
before GC can touch them.

#### compile_file iseq filtering

`RubyVM::InstructionSequence.compile_file` compiles a file to bytecode
without executing it. The resulting `:top` iseq is a distinct object from
the require-produced iseq that the runtime actually executes. A targeted
TracePoint bound to a compile_file iseq never fires — no error, no log,
no metric. The probe reports as installed but produces zero snapshots.

The design question: should these iseqs enter `per_method_registry`? No —
they'd cause silent probe failures. Filtering strategy differs by Ruby
version:

- **Ruby 3.1+:** `DI.iseq_type` returns `:top`/`:main` for these iseqs.
  Combined with `first_lineno != 0` (compile_file uses `first_lineno == 1`,
  require/load uses `first_lineno == 0`), backfill skips them.
- **Ruby < 3.1:** No `iseq_type` available. compile_file `:top` iseqs
  have `first_lineno == 1`, making them indistinguishable from method
  iseqs — they leak into `per_method_registry`. If `iseq_for_line`
  selects one, the probe installs but silently never fires. This requires
  the application to call `compile_file` and hold the returned iseq object
  in memory. Bootsnap calls `compile_file` but does not hold the returned
  iseq, so it does not trigger this issue. **Accepted limitation** on
  Ruby < 3.1.

### Test pattern: keeping iseqs alive for backfill tests

Tests that load files before code tracking and then test backfill must
prevent the `:top` iseq from being collected. `GC.disable` alone is
insufficient across multiple tests — after `deactivate_tracking!` clears
the registry (the only reference), GC can collect the iseq before the
next test's backfill.

The correct pattern is to hold a reference in a constant:

```ruby
# At file load time (before RSpec.describe):

# 1. Disable GC so the :top iseq survives long enough to be captured
GC.disable
require_relative "test_class"

# 2. Immediately capture the :top iseq in a constant
TEST_TOP_ISEQ = Datadog::DI.file_iseqs.find { |i|
  i.absolute_path&.end_with?("test_class.rb") &&
    (Datadog::DI.respond_to?(:iseq_type) ? Datadog::DI.iseq_type(i) == :top : i.first_lineno == 0)
}

# 3. Safe to re-enable GC — the constant holds the reference
GC.enable
```

The constant MUST be assigned while GC is still disabled. If GC runs
between `require_relative` and the assignment, the iseq may already be
collected.

See `spec/datadog/di/ext/backfill_integration_spec.rb` for a working
example.

## Starting the Remote Configuration Worker Manually

Add this to your Rails initializer after `Datadog.configure`:

```ruby
# config/initializers/datadog.rb

Datadog.configure do |c|
  c.dynamic_instrumentation.enabled = true
  # This internal setting should only be used when developing the datadog gem itself and
  # **should not** ever be used outside of that.
  c.dynamic_instrumentation.internal.development = true
  c.remote.enabled = true
  # ... other configuration
end

# Start the RC worker
if Datadog.send(:components).remote
  Datadog.send(:components).remote.start
end
```

Verify in logs:

```
D, [timestamp] DEBUG -- datadog: new remote configuration client: <client_id> products: LIVE_DEBUGGING
```

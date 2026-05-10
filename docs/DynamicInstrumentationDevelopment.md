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

`backfill_registry` only stores `:top` or `:main` iseqs because they cover
all lines in the file. Per-method iseqs are filtered out — they cover only
a subset of lines.

If the `:top` iseq was collected before backfill runs, no whole-file iseq
exists for that file. This causes `DITargetNotInRegistry` when installing
a line probe.

**Production:** backfill is best-effort. If the `:top` iseq was already
collected, line probes on that pre-loaded file won't work via backfill.
The `:script_compiled` tracepoint (the primary mechanism) is unaffected —
it captures iseqs at load time before GC can touch them.

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

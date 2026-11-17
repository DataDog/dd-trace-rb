# Correctness

Bugs, races, unhandled edge cases, and tests that pass when they shouldn't.

**When planning:** take the rules below into account when designing the change.

**When reviewing:** report a finding when the diff matches a rule's `Flag:` line and no `Not when:` applies, or when it has a clear problem in this lens's area that no rule covers (mark it `no rule`). Cite the rule ID, location, and the failing input or interleaving.

## 1. Concurrency and fork safety

### COR-1.1: Read a concurrently replaceable global once into a local
- Flag: `Datadog.configuration`, `active_remote`, or another global that can be replaced at runtime, read more than once in a method that uses the values together.
- ❌ `return unless Datadog.configuration.remote.enabled; poll(Datadog.configuration.remote.poll_interval_seconds)`
- ✅ `configuration = Datadog.configuration; return unless configuration.remote.enabled; poll(configuration.remote.poll_interval_seconds)`

### COR-1.2: Initialize state before registering a fork or event callback that reads it
- Flag: a reordering (often made to satisfy Steep) that registers `after_fork!` or an event subscription before the state its callback reads is set.
- ❌ `register_after_fork { @parent_id = @id }; @id ||= SecureRandom.uuid`
- ✅ `@id ||= SecureRandom.uuid; register_after_fork { @parent_id = @id }`

### COR-1.3: Block instrumentation reentrancy in every direction
- Flag: a guard that stops one probe or hook kind firing inside another but not the reverse, or code that holds an instrumentation mutex while calling methods that can themselves be instrumented (for example, `WeakRef#weakref_alive?` under the DI sampler lock).

### COR-1.4: Capture values that must belong together as one pair, including `nil`
- Flag: a trace ID and span ID (or a similar pair) read at different times or from different sources, or one `nil` used for both "captured nothing" and "did not capture".
- ✅ capture `[trace, span]` together at admission, and store an explicit "not captured" state.

## 2. Lifecycle and configuration

### COR-2.1: Rescue and log around each product's lifecycle hook in `Components`
- Flag: a new product call in `startup!`, `shutdown!`, or an `after_fork` hook in `components.rb` without `rescue => e` and a log, so one product's failure skips the remaining products.
- ❌ `@open_feature_activation.shutdown!`
- ✅ `begin; @open_feature_activation.shutdown!; rescue => e; logger.error("Feature Flags failed to shut down: #{e.class}: #{e.message}"); end`

### COR-2.2: Reject invalid setting values instead of passing them through or coercing them silently
- Flag: an `o.setter` or `env_parser` that returns the raw value, `nil`, or a default for a wrongly typed or unrecognised value without raising or warning.
- Not when: warn-and-fall-back is the agreed cross-SDK behaviour for that product's env vars.
- ❌ `o.setter { |value| value.respond_to?(:empty?) ? value : nil }`
- ✅ `o.type :array` (or `raise ArgumentError, "Invalid user_id_denylist: #{value.inspect}"`)

### COR-2.3: Update every reference when moving or renaming a setting
- Flag: a setting moved to a new namespace while `settings.<old_namespace>.*` references remain in `lib/`, `spec/`, `sig/`, docs, or other PRs in the same stack.

### COR-2.4: Forward generic arguments with the pattern in `docs/Delegation.md`
- Flag: a wrapper or monkey patch that forwards `*args, **kwargs` with one definition for every Ruby version, relies on `ruby2_keywords` alone, or drops `**kwargs`. See [Delegation.md](../../../../docs/Delegation.md).

### COR-2.5: Pass prerequisite headers to `have_header` in `extconf.rb`
- Flag: `have_header` for a private Ruby header without the headers it depends on.
- ❌ `have_header("internal/class.h")`
- ✅ `have_header("internal/class.h", "vm_core.h")`

## 3. CI automation

### COR-3.1: Paginate every GitHub API list call whose results are matched or counted
- Flag: `gh api` on a list endpoint (jobs, annotations, check runs) without `--paginate`, especially when a sibling call in the same script paginates.

### COR-3.2: Retry only the failures that match, and check live state before retrying
- Flag: `rerun-failed-jobs` when only some failed jobs match the infrastructure condition, an attempt count read from the triggering event instead of the live `run_attempt`, or a `concurrency:` group shared by unrelated targets (GitHub keeps only one pending run per group and drops the rest).

### COR-3.3: Verify a retried non-idempotent mutation before treating its result as the baseline
- Flag: a retry loop that carries forward a SHA or ID from an attempt that reported an error without confirming it landed, or that stops re-verifying once the head is unchanged.

## 4. Tests

### COR-4.1: Freeze the clock before constructing time-based or rate-limited objects
- Flag: a spec that asserts rate-limiter, bucket, or timeout counts without freezing time (`freeze_rate_limiter_clock` in DI specs, or `Core::Utils::Time.now_provider=`) before the object is built.

### COR-4.2: Keep a strong reference to `WeakRef` referents for the whole example
- Flag: a spec object referenced only through a `WeakRef` or `ObjectSpace::WeakMap` while the example asserts it is alive.

### COR-4.3: Add a regression test for every direction or path a fix covers
- Flag: a fix for a symmetric or multi-path bug (for example, method probe inside line probe and the reverse) tested in only one direction.

## Don't flag
- Requests to drop build-only gems such as `datadog-ruby_core_source` from the SSI package; gemspec resolution requires them.
- Native self-tests (for example, the profiler's `rb_thread_t` layout check) that accept rare false positives rather than dereference values that may come from a wrong struct offset.

# OpenFeature coding guide

This guide applies to contributors and their AI coding tools working under `lib/datadog/open_feature/`, `spec/datadog/open_feature/`, and `sig/datadog/open_feature/`. The goal is to automate conventions and keep human review focused on architecture, APM customer behavior, and correctness. Each rule is grounded in a real finding from this codebase; the guide grows as new patterns emerge. When in doubt, follow the existing files in this directory as the reference.

---

## Must follow

- Keep each PR focused on one thing, under ~1000 added lines, and include tests for the change (see [Pull requests](#pull-requests)).
- PR description follows `.github/PULL_REQUEST_TEMPLATE.md`, at most three sentences per section — high-level intent, not a file-by-file list.
- Change log entry starts with `Yes.` or `None.` — `Yes.` only for changes to customer-observable provider behavior (see [Pull requests](#pull-requests)).
- Complete the [customer and architecture review](#customer-and-architecture-review) before requesting human review.
- Full, descriptive names. Single letters only for block indices, `rescue => e`, or an ignored `_arg` (see [Naming](#naming)).
- Comment the *why* in as few words as possible; delete a comment that only restates the code (see [Comments](#comments)).
- Files and modules follow [Zeitwerk conventions](#file-and-directory-structure): `FlagEvaluation` lives in `flag_evaluation.rb`.
- No dead code — no method, branch, or class that no current caller reaches (see [Code hygiene](#code-hygiene)).
- Small, single-purpose methods. A blank line follows a guard clause (see [Methods](#methods)).
- Rescue only what you intend to handle. A broad `rescue => e` at a product boundary needs a comment explaining why it must never interrupt the caller (see [Error handling](#error-handling)).
- Tests are independent: no reliance on ordering, and singletons like `OpenFeature::API.instance` are reset in `before`/`after` (see [Tests](#tests)).
- Every `.rb` file has a matching `.rbs` in `sig/datadog/open_feature/`. Never silently suppress the type checker (see [Types (RBS)](#types-rbs)).
- Use `instance_double`, not string-name doubles or hand-rolled `Struct` fakes. Assert exact values when you know them.
- Background threads are fork-safe, use a bounded `SizedQueue`, `join(timeout)` on shutdown, and enqueue non-blocking.
- Use `Datadog::Core::Utils::Time.now` (never `Time.now`) and read env vars through `Datadog::Core::Environment::VariableHelpers` (never `ENV`).
- Construct objects through their real constructor, never `.allocate` + `instance_variable_set`.

The sections below explain the reasoning and show the tricky cases. Skim the "bad" examples first — they are the mistakes this guide exists to prevent.

---

## Pull requests

- Keep each PR focused on one thing — a feature, a refactor, or a bug fix, not all three.
- **Tests.** Every behavior change ships with test coverage in the same PR. A PR that changes code without a corresponding test change is incomplete, not a follow-up to file later.
- **Size.** If the resulting diff would exceed roughly 1000 lines of additions, stop and propose a split into smaller, stackable PRs before generating any code.
- **Description.** Use `.github/PULL_REQUEST_TEMPLATE.md` as the structure. At most three sentences per section — high-level intent, not a file-by-file list. Answer *what* and *why*, and call out any non-obvious trade-off; the reviewer reads the diff for the rest. Before opening the PR, count the sentences in each section; if a section runs longer, cut it or move the detail to Additional Notes.
- **Change log entry.** Start with `Yes.` plus a one-sentence customer-facing summary if the change affects observable provider behavior (flag evaluation results, hooks, the public `OpenFeature` API); otherwise `None.` Refactors, tests, and tooling changes internal are always `None.`
- Respond to every review comment with either a fix or an explanation of why the change is not being made. Do not re-request review with open threads unresolved.

---

## Customer and architecture review

Before requesting human review, verify:

- The final application-visible result is represented correctly for success, provider error, runtime default, SDK type mismatch, and hook failure paths.
- Capped or dropped data preserves referential integrity: no encoded field may reference an identifier omitted from another field.
- Fork, shutdown, reconfiguration, and in-flight work cannot leak resources or emit data after the feature is disabled.
- Enabled product paths fail observably. Never silently swallow an internal `require_relative` failure or return `nil` for a missing implementation file.
- Minimum and latest supported OpenFeature SDKs preserve local-root span semantics and the backend wire contract.

Use automated review, StandardRB, and Steep for conventions wherever practical. Ask human reviewers to evaluate open architectural choices, protocol changes, and their effect on APM customers.

---

## File and directory structure

Follow [Zeitwerk's file structure conventions](https://github.com/fxn/zeitwerk#file-structure): one class or module per file, matching the file name, and the file path mirrors the constant's namespace. `Datadog::OpenFeature::FlagEvaluation::Writer` lives in `lib/datadog/open_feature/flag_evaluation/writer.rb`, not `flagevaluation/writer.rb` or a file bundling multiple classes. Wire-level names (API endpoints, protocol fields) stay on the protocol side and do not leak into Ruby file or constant names.

---

## Naming

Use Ruby naming throughout, including comments and test descriptions. Prefer `flattened_context` over `flat`; do not carry camelCase from other languages (`# globalCap` should read `# global_cap`).

---

## Comments

```ruby
# bad: narrates obvious code
# We iterate over the context attributes and increment the counter for each one.
count = 0
attrs.each { |k, v| count += 1 }

# good: one line, explains a non-obvious constraint
# Cap at 256 to match the backend's field limit; extras are silently dropped.
pruned[key] = value if pruned.size < MAX_CONTEXT_FIELDS
```

Do not restate a test description as a comment inside the example. Reference tickets or sibling SDKs only when they define a canonical backend/wire contract or a non-obvious parity requirement; link the source and explain the local constraint. Use ASCII only — no Unicode box-drawing dividers.

---

## Methods

```ruby
# bad: one method doing too much
def process(event)
  key = [event[:flag], event[:variant]].join(":")
  return if @seen.include?(key)
  @seen << key
  @transport.send(flag: event[:flag], count: (@counts[key] || 0) + 1)
end

# good: each step named and separated, blank line after the guard clause
def process(event)
  key = cache_key(event)
  return if already_seen?(key)

  record(key)
  @transport.send(build_payload(key))
end
```

Prefer `return unless condition` over `return nil unless condition` — Ruby implicitly returns nil.

---

## Error handling

```ruby
# bad: catches everything, hides real bugs
begin
  do_work
rescue => e
  logger.debug(e.message)
end

# good: deliberate, narrow, explained
@queue.push(event, true)
rescue ThreadError
  # Queue full. Drop and count; backpressure is reported on the next flush.
  @overflow_count += 1
```

---

## Types (RBS)

```ruby
# bad
result = compute_value # steep:ignore

# good: fix the type or add an explicit annotation
result = compute_value #: String
```

Every `.rb` file needs a matching `.rbs` in `sig/datadog/open_feature/`, mirroring the same relative path. If a suppression is genuinely unavoidable, comment why and call it out in the PR description. Prefer `Type?` over `(nil | Type)`.

---

## Tests

```ruby
# bad: passes even if Writer#enqueue is renamed or removed
let(:writer) { double("Writer", enqueue: nil) }

# good: fails fast when the interface changes
let(:writer) { instance_double(Datadog::OpenFeature::FlagEvaluation::Writer, enqueue: nil) }
```

---

## Concurrency and threads

- **Fork safety.** Background threads die silently when the process forks. Use `Core::Workers::Async::Thread` with `FORK_POLICY_RESTART` so the thread restarts automatically on the next operation.
- **Bounded queues.** Use `SizedQueue.new(capacity)`, not a plain `Array` or `Queue` — an unbounded queue grows until the process runs out of memory under sustained load.
- **Shutdown timeout.** Always call `join(timeout)` when stopping a thread.
- **Non-blocking enqueue.** The hook runs on the caller's flag-evaluation thread; never let a full queue or a stopped worker stall it:

  ```ruby
  # good: drops and counts on overflow, never blocks the caller
  @queue.push(event, true)
  rescue ThreadError
    @overflow_count += 1
  ```

---

## Repo idioms

These apply across the whole repository, not just this directory.

- **Time.** `Datadog::Core::Utils::Time.now` / `.get_time`, not `Time.now` — the provider is injectable for tests and Timecop.
- **Environment variables.** Read through `Datadog::Core::Environment::VariableHelpers` or the settings layer. Run `rake local_config_map:generate` after adding a new one.
- **`filter_map`.** Use `Core::Utils::EnumerableCompat.filter_map` — the native method requires Ruby 2.7+ and this codebase supports 2.5 and 2.6.
- **Settings and component wiring.** New configuration goes in `Configuration::Settings`; new components are built in `Component.build` and wired into `components.rb`.
- **Accessing private members.** `.send(:member)` is accepted when no public accessor exists. Prefer adding a real accessor when practical.

---

## Code hygiene

- No dead code: a method never called, a `rescue` for an exception that can't occur, an `if` branch that's always false, a path added for a future caller that doesn't exist yet. Delete it — version control remembers it.
- Always construct objects through their normal constructor, never `.allocate` + `instance_variable_set`, even in tests or benchmarks. Pass lightweight test doubles through the constructor instead.

---

## Style

Run `bundle exec rake standard:fix` before pushing. StandardRB is fixed and non-configurable by team convention.

---

**Tool note.** Claude Code reads this directory's one-line `CLAUDE.md` import when it discovers work in this subtree. Codex only discovers `AGENTS.md` files from the repo root down to its current working directory; a root-level session does not automatically import this nested file. The root `AGENTS.md` therefore explicitly requires OpenFeature contributors and tools to read this guide before modifying code, specs, or signatures. Verify how other tools (Cursor, Copilot, etc.) discover nested guidance.

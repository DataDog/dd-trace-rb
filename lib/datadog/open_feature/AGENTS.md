# OpenFeature coding guide

This guide applies to contributors and their AI coding tools working under
`lib/datadog/open_feature/`, `spec/datadog/open_feature/`, and `sig/datadog/open_feature/`.
The goal is to keep review conversations focused on design and correctness rather than
conventions. Each rule is grounded in a real finding from this codebase; the guide grows as
new patterns emerge. When in doubt, follow the existing files in this directory as the
reference.

---

## Naming

Ruby values intention-revealing names. Every local variable, method, and parameter should say
what it holds or does.

**Variables: use full, descriptive names.**

```ruby
# bad
flat = flatten_context(attrs)
e    = entries.first
s    = build_string(parts)

# good
flattened_context = flatten_context(attrs)
first_entry       = entries.first
encoded_string    = build_string(parts)
```

Single-letter names are acceptable only for established Ruby idioms:

```ruby
# fine: block index
parts.each_with_index { |part, i| ... }

# fine: rescue variable
rescue => e
  logger.debug(e.message)

# fine: throwaway / ignored argument
def handle(event, _context)
```

**Directories and modules must match.** A module named `FlagEvaluation` lives in
`flag_evaluation/`, not `flagevaluation/`. Wire-level names (API endpoints, protocol fields)
stay on the protocol side and do not leak into Ruby identifiers.

**Use Ruby naming throughout, including comments and test descriptions.** Do not carry
camelCase from other languages:

```ruby
# bad (in comment or RSpec description)
# globalCap controls the upper bound

# good
# global_cap controls the upper bound
```

---

## Comments

Comment the *why*, not the *what*. Use the minimum words needed to explain the constraint,
decision, or non-obvious behaviour. If a comment keeps growing, that is a sign the code
itself needs to be clearer — extract a method or rename a variable instead.

```ruby
# bad: narrates obvious code across multiple lines
# We iterate over the context attributes and increment the counter for each
# one we process, stopping once we reach the maximum allowed field count.
count = 0
attrs.each { |k, v| count += 1 }

# bad: one-liner that still just restates the code
# increment the retry count
retry_count += 1

# good: one line, explains a non-obvious constraint
# Cap at 256 to match the backend's field limit; extras are silently dropped.
pruned[key] = value if pruned.size < MAX_CONTEXT_FIELDS
```

Do not restate a test description as a comment inside the example:

```ruby
# bad
it "returns nil when the flag is missing" do
  # returns nil when the flag is missing
  expect(subject).to be_nil
end

# good
it "returns nil when the flag is missing" do
  expect(subject).to be_nil
end
```

Do not include references that only make sense outside this repository (ticket IDs, "Node
reference", "Python sibling"). The Ruby code stands alone.

Use ASCII characters only. Do not use Unicode box-drawing dividers (`# ─── Section ───`);
they are not used elsewhere in the codebase.

---

## Methods

Keep methods small and single-purpose. Prefer many focused private methods over one large one.

```ruby
# bad: one method doing too much
def process(event)
  key = [event[:flag], event[:variant]].join(":")
  return if @seen.include?(key)
  @seen << key
  payload = { flag: event[:flag], count: (@counts[key] || 0) + 1 }
  @transport.send(payload)
end

# good: each step named and separated
def process(event)
  key = cache_key(event)
  return if already_seen?(key)
  record(key)
  @transport.send(build_payload(key))
end
```

Prefer `return unless condition` over `return nil unless condition` (Ruby implicitly returns
nil):

```ruby
# bad
return nil unless enabled?

# good
return unless enabled?
```

---

## Error handling

Rescue only what you intend to handle, and only as broadly as necessary.

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

A broad `rescue => e` at a product boundary (flag evaluation, trace pipeline) is acceptable
when the intent is to never interrupt the caller. Scope it tightly and comment why.

---

## Types (RBS)

Every file in `lib/datadog/open_feature/` has a matching signature in
`sig/datadog/open_feature/`. Add or update the `.rbs` file in the same change as the Ruby
file. CI enforces this.

Do not suppress the type checker to make an error go away:

```ruby
# bad
result = compute_value # steep:ignore

# good: fix the type or add an explicit annotation
result = compute_value #: String
```

If a suppression is genuinely unavoidable, add a comment explaining why and call it out in
the PR description. Prefer `Type?` over `(nil | Type)`.

---

## Tests

**Use verifying doubles.** `instance_double(RealClass)` raises when you stub a method that
does not exist on the real class. String-name doubles and hand-rolled `Struct` fakes do not.

```ruby
# bad: passes even if Writer#enqueue is renamed or removed
let(:writer) { double("Writer", enqueue: nil) }
let(:writer) { Struct.new(:enqueue).new(nil) }

# good: fails fast when the interface changes
let(:writer) { instance_double(Datadog::OpenFeature::FlagEvaluation::Writer, enqueue: nil) }
```

**Tests must be independent.** Each example must set up its own state and clean up after
itself. Do not rely on test ordering or on state left by a previous example. This matters
especially when a global singleton (like `OpenFeature::API.instance`) is involved: reset it
in `before`/`after` hooks for every example that touches it, and stub every message an object
will receive.

**Assert exact values when you know them.**

```ruby
# bad: passes even if count is wildly wrong
expect(result.count).to be >= 1

# good
expect(result.count).to eq(3)
```

---

## Concurrency and threads

Background threads have a few mandatory properties in this codebase:

- **Fork safety.** When a process forks (e.g. Puma spawning workers), all background threads
  from the parent process die silently in the child — the child starts with no threads even
  though the objects still exist. Use `Core::Workers::Async::Thread` with
  `FORK_POLICY_RESTART`: it detects that the process was forked and restarts the thread
  automatically on the next operation.

- **Bounded queues.** Use `SizedQueue` with an explicit capacity rather than a plain `Array`
  or `Queue`. An unbounded queue accepts events faster than they can be flushed; under
  sustained load it grows until the process runs out of memory. A `SizedQueue` caps growth
  and lets the producer handle the overflow explicitly.

  ```ruby
  # bad: grows without limit
  @queue = Queue.new

  # good: caps at 4096 entries; producer handles ThreadError on overflow
  @queue = SizedQueue.new(4096)
  ```

- **Shutdown timeout.** Always call `join(timeout)` when stopping the thread. Without a
  timeout, a stuck thread prevents the process from exiting.

- **Non-blocking enqueue.** The hook runs on the caller's flag-evaluation thread. Never let
  a full queue or a stopped worker stall that thread. Push non-blocking, catch the overflow,
  and count the drop — do not raise or wait:

  ```ruby
  # bad: blocks the caller if the queue is full
  @queue.push(event)

  # good: drops and counts on overflow, never blocks the caller
  @queue.push(event, true)
  rescue ThreadError
    @overflow_count += 1
  ```

---

## Repo idioms

These apply across the whole repository, not just this directory.

**Time.** Use `Datadog::Core::Utils::Time.now` / `.get_time` instead of `Time.now`. The time
provider is injectable (used by tests and Timecop integrations).

```ruby
# bad
timestamp = Time.now.to_i

# good
timestamp = Core::Utils::Time.get_time
```

**Environment variables.** Read through `Datadog::Core::Environment::VariableHelpers` or the
settings layer, never `ENV` directly. Run `rake local_config_map:generate` after adding a new
environment variable.

**`filter_map`.** Use `Core::Utils::EnumerableCompat.filter_map` instead of the native
`filter_map`. Native `filter_map` requires Ruby 2.7+; this codebase supports Ruby 2.5 and
2.6.

**Settings and component wiring.** New configuration belongs in `Configuration::Settings`
extended via `Core::Configuration::Settings.extend`. New components are built in
`Component.build` and wired into `components.rb`. Follow the existing wiring pattern rather
than inventing a new one.

**Accessing private members.** `.send(:member)` is an accepted pattern here when no public
accessor exists — the tracer uses it in several places. Prefer adding a real public accessor
or seam when one is practical.

---

## Structure and PR hygiene

- One class or module per file, matching the file name.
- Keep PRs focused. Each PR should change one thing: a new feature, a refactor, or a bug
  fix — not all three at once. Mixing concerns makes it hard to understand intent, hard to
  revert, and slow to review.
- No dead code. Dead code is any method, branch, or class that no current caller reaches.
  Common forms: a method defined but never called anywhere; a `rescue` branch for an
  exception the surrounding code cannot raise; an `if` branch whose condition is always
  false; a "forward compatibility" path added for a future caller that does not exist yet.
  Delete it — version control remembers it if it is ever needed again.

  ```ruby
  # dead: start_worker is defined but perform already starts the thread;
  # nothing calls start_worker
  def start_worker
    perform
  end

  # dead branch: the SDK never dispatches :finally today, so this branch
  # is never reached
  def run_hook(stage, context)
    case stage
    when :before  then before(context)
    when :finally then finally(context)  # no caller reaches here
    end
  end
  ```

- Always construct objects through their normal constructor. Do not use `.allocate` +
  `instance_variable_set` to bypass `initialize` — in tests, benchmarks, or anywhere else.
  If the constructor requires collaborators that are hard to supply, pass lightweight
  test doubles through the constructor arguments instead:

  ```ruby
  # bad: bypasses initialize, breaks silently when the constructor changes
  writer = Writer.allocate
  writer.instance_variable_set(:@transport, NoopTransport.new)
  writer.instance_variable_set(:@logger, logger)

  # good: uses the real constructor, passes a lightweight stand-in
  writer = Writer.new(transport: NoopTransport.new, logger: logger)
  ```

- **PR size.** If the resulting diff would exceed roughly 1000 lines of additions, stop and
  warn the contributor before generating the code. Propose a split into smaller, stackable
  PRs instead. Each PR should be reviewable on its own and mergeable independently. Get
  agreement on the breakdown before generating any code.

### PR description

Use `.github/PULL_REQUEST_TEMPLATE.md` as the structure. Fill each section with one or two
sentences — high-level intent, not a list of every changed file. The reviewer reads the diff
for details; the description should answer *what* and *why*, and call out any non-obvious
trade-off or deliberate decision.

```
**What does this PR do?**
Adds an EVP writer that batches flag evaluation events and ships them to the Agent every 10s
via the EVP proxy. The writer is fork-safe and drops events non-blocking on queue overflow.

**Motivation:**
Required by the FFE telemetry spec. Without this, flag evaluation counts never reach the backend.

**Change log entry**
Yes. Flag evaluation counts are now sent to Datadog via the EVP proxy.

**Additional Notes:**
Chose a canonical context key over MD5 so the encoding is auditable without a digest
dependency. Retry on transport failure is deferred — the writer logs and moves on for now.

**How to test the change?**
Covered by the new aggregator and writer specs; integration verified against mock intake.
```

Respond to every review comment with either a fix or an explanation of
why the change is not being made. Do not re-request review with open threads unresolved.

---

## Style

Run `bundle exec rake standard:fix` before pushing. StandardRB is fixed and non-configurable
by team convention.

---

**Tool note.** Claude Code reads `CLAUDE.md`, not `AGENTS.md`. If you use Claude Code,
symlink this file: `ln -s AGENTS.md CLAUDE.md` inside this directory. Verify how your
specific tool (Cursor, Copilot, Codex) discovers nested guide files.

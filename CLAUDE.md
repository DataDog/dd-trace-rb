# Absolute Rules

## Pull Requests

- ALWAYS push branches to `DataDog/dd-trace-rb`, not forks
- ALWAYS use `--repo DataDog/dd-trace-rb` with gh commands (defaults are unreliable)
- PR descriptions MUST use `.github/PULL_REQUEST_TEMPLATE.md` as the starting point
- Write for the developer performing code review; be concise
- Use one sentence per relevant point in summary/motivation sections
- Changelog entries are written for customers only; consider changes from user/customer POV
- Internal changes (telemetry, CI, tooling) = "None" for changelog
- Changelog entry format: MUST start with "Yes." or "None."
  - If changes need CHANGELOG: `Yes. Brief customer-facing summary.`
  - If no CHANGELOG needed: `None.`
  - Never write just the summary without "Yes." prefix
- Add `--label "AI Generated"` when creating PRs (do not mention AI in description; label is sufficient)

## Never

- Use `git commit --amend` unless the user explicitly and clearly requests it (always create new commits by default)
- Push commits to remote (`git push`) unless the user explicitly requests it
- Commit secrets, tokens, or credentials
- Edit files under `gemfiles/` (auto-generated; use `bundle exec rake dependency:generate`)
- Change versioning (`lib/datadog/version.rb`, `CHANGELOG.md`)
- Leave resources open (terminate threads, close files)
- Make breaking public API changes
- Use `sleep` in tests for synchronization (use deterministic waits: Queue, ConditionVariable, flush methods that block, or mock time)

## Ask First

- Modifying dependencies in `datadog.gemspec`, `appraisal/`, or `Matrixfile`
- Editing CI workflows or release automation
- Touching vendored third-party code (except `vendor/rbs`)
- Modifying `@public_api` annotated code (read `docs/PublicApi.md` first)

## GitHub Actions

When creating or modifying workflows in `.github/workflows/`:

### Security

- NEVER interpolate user input directly in `run:` blocks - use `env:` instead:
  ```yaml
  # BAD: run: echo "${{ github.event.comment.body }}"
  # GOOD:
  env:
    COMMENT: ${{ github.event.comment.body }}
  run: echo "$COMMENT"
  ```
- User-controllable inputs: `github.event.comment.body`, `github.event.issue.title`, `github.event.pull_request.title`, `github.head_ref`
- Pin actions to SHA: `uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2`
- Set `permissions: {}` at workflow level; explicit minimal permissions per job
- Prefer `pull_request` over `pull_request_target`

### Shell Scripts

- Always quote variables: `"$VAR"` not `$VAR`
- Quote `$GITHUB_OUTPUT`: `echo "key=value" >> "$GITHUB_OUTPUT"`
- Group multiple redirects: `{ echo "a"; echo "b"; } >> "$GITHUB_OUTPUT"`
- Avoid heredocs; use echo grouping instead

### Validation

```bash
yamllint --strict .github/workflows/your-workflow.yml
actionlint .github/workflows/your-workflow.yml
```

## Code Changes

- Read files before editing them
- When user says "suggest" or asks a question: analyze only, do not modify code
- When user says "fix", "change", "update": make the changes
- If a requested change contradicts code evidence, alert user before proceeding
- If unable to access a requested web page, explicitly state this and explain basis for any suggestions
- Use `Core::Utils::Array.filter_map` instead of `filter_map` for compatibility with Ruby 2.5 and 2.6 (native `filter_map` requires Ruby 2.7+)
- Use `Datadog::Core::Utils::Time.now` instead of `Time.now` everywhere — the time provider is configurable (e.g. for Timecop support) and tests can override it via `Core::Utils::Time.now_provider=`
  - Exception: constants initialized at load time (before user configuration) may use `::Time.now` directly; add a comment explaining why (see `lib/datadog/profiling/collectors/info.rb` for an example)
  - Exception: Dynamic Instrumentation (DI) probe instrumentation code that runs inside customer application methods must use `::Time.now` directly — the time provider supports runtime overrides (the API exists even if rarely used in production), and DI must never invoke customer-provided code during instrumentation

## Component Pattern

Pass dependencies (logger, settings, telemetry) via constructor injection. Do not access
globals (`Datadog.logger`, `Datadog.configuration`) from within component code — that
means a dependency wasn't injected.

`Datadog.send(:components)` is for component boundaries only: RC callbacks, deferred
hooks, threads that outlive component rebuilds. Not a general substitute for injection.

Static methods are appropriate only for pure helpers with no dependencies. If a static
method needs logging, config, or telemetry, convert it to an instance method on a
component.

**Exception:** Tracing contrib/integration code that runs inside monkey-patched methods
must read configuration at call time via globals — patches persist across component
rebuilds and cannot capture injected references. This is the only context where direct
`Datadog.configuration` access is appropriate.

## Error Handling

Every `rescue` block must:
- Log at debug level with exception class AND message: `"component: context: #{e.class}: #{e.message}"`
- Report to telemetry (`Datadog.health_metrics` or equivalent)
- Never silently swallow exceptions (bare `rescue` without logging)

Silent `rescue` blocks are allowed only for intentional cases (timer cleanup, component
lookup before init) and must have a comment explaining why.

Use `warn` only for user-actionable problems (missing config, incompatible runtime).
Use `debug` for operational state (errors, upload outcomes, config changes).

## Ruby Compatibility

Minimum supported Ruby is 2.5. Do not use methods added after 2.5 without a polyfill:
- `filter_map` (2.7+) → use `Core::Utils::Array.filter_map`
- `then` (2.6+) → use `yield_self`

Check the file you're editing for existing polyfill usage before introducing bare
stdlib calls. If three call sites use the polyfill and you write a bare call, that's
a bug.

## Documentation

- **Dynamic Instrumentation docs**: Never mention telemetry in customer-facing documentation (e.g., `docs/DynamicInstrumentation.md`)
  - Telemetry is internal and not accessible to customers
  - Only mention observable behavior (logging, metrics visible to customers)
  - Internal code comments may mention telemetry when describing implementation

## Environment Variables

- Use `DATADOG_ENV`, never `ENV` directly (see `docs/AccessEnvironmentVariables.md`)
- Run `rake local_config_map:generate` when adding new env vars

# Reference

See `AGENTS.md` for:
- Project structure and directory layout
- Docker container setup (`docker compose run --rm tracer-3.4 /bin/bash`)
- Bundle, rake, and rspec commands
- Integration patterns (`patcher.rb`, `integration.rb`, `ext.rb`, `configuration/settings.rb`)

See `docs/` for:
- `DevelopmentGuide.md` - detailed development workflows
- `GettingStarted.md` - user-facing documentation (update when adding settings/env vars)
- `StaticTypingGuide.md` - RBS and Steep usage
- `PublicApi.md` - public API guidelines

## Quick Commands

```bash
bundle exec rake test:main              # Smoke tests
bundle exec rake standard typecheck     # Lint and type check
bundle exec steep check [sources]       # Type check (sources = files or dirs, optional)
bundle exec rspec spec/path/file_spec.rb:123  # Run specific test
```

## Gotchas

- Pipe rspec output: `2>&1 | tee /tmp/rspec.log | grep -E 'Pending:|Failures:|Finished' -A 99`
- Transport noise (`Internal error during Datadog::Tracing::Transport::HTTP::Client request`) is expected
- Profiling specs fail on macOS without additional setup
- `ProbeNotifierWorker#flush` blocks until queues are empty - never add `sleep` after it

# Style

Enforced by StandardRB: `bundle exec rake standard:fix`

Additional team preferences:
- Trailing commas in multi-line arrays, hashes, and arguments
- RBS type definitions in `sig/` mirror `lib/` structure
- Avoid `untyped`; use `Type?` not `(nil | Type)`

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

## Running Tests

Tests MUST be run via rake tasks, not bare `bundle exec rspec`, because most test suites require specific Gemfiles (appraisals) for third-party dependencies. The rake task selects the correct Gemfile for the current Ruby version automatically.

```bash
bundle exec rake test:TASK_KEY          # Correct - always use this
bundle exec rspec spec/path/file.rb     # ONLY for specs covered by test:main
```

### Finding the right rake task

1. **Identify the component**: determine which product or contrib the changed files belong to based on their path under `lib/datadog/` or `spec/datadog/` (e.g. `appsec`, `profiling`, `redis`, `sinatra`)
2. **Search for a matching task**: `bundle exec rake -T test | grep KEYWORD` using the component name as KEYWORD
3. **Verify the task**: check the Rakefile `spec:TASK` definition to confirm which spec files are included/excluded, and check the Matrixfile for Ruby version compatibility

The `test:main` task uses the default Gemfile and its specs can also be run individually with `bundle exec rspec`.

### Docker requirement

- Contrib/integration tests need Docker: `docker compose run --rm tracer-3.4 /bin/bash`, then run the rake task inside
- `test:main` can run locally on any Ruby for quick feedback
- If Bundler fails inside the container (e.g. after a dependency update), run `bundle install` and retry the rake task once before investigating further

### Verifying across Ruby versions

Before marking a task complete, run the relevant test task on both the earliest and latest supported Ruby versions. Regressions in older Rubies are easy to miss when only testing on the latest. Check the component's entry in `Matrixfile` for the supported range, then:

```bash
docker compose run --rm tracer-2.5 bundle exec rake test:TASK_KEY
docker compose run --rm tracer-4.0 bundle exec rake test:TASK_KEY
```

Skip versions the Matrixfile marks as unsupported for that task. For `test:main`, the same applies — swap in the tracer container matching each end of the supported range.

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
bundle exec rspec spec/path/file_spec.rb:123  # Run specific test (only works for test:main specs; see "Running Tests")
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

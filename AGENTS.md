This repository is the source code of a Ruby gem created by Datadog to provide Distributed Tracing (APM), Profiling, App & API Protection (AppSec), Dynamic Instrumentation (DI, Live Debugger), Data Streams Monitoring (DSM), Error Tracking, OpenTelemetry, and OpenFeature to Ruby applications.

# Setup & Quick Commands

**Ruby version compatibility:** Ruby 2.5+ (including 3.x+ and 4.x+)

- Launch MRI container: `docker compose run --rm tracer-4.0 /bin/bash`. Matches CI defaults. Other Ruby versions and variants are in `docker-compose.yml`.
- Install dependencies: `bundle install`. Run once per container/session.
- Discover gemfiles: `bundle exec rake dependency:list`. Shows values for `BUNDLE_GEMFILE`.
- Use an alternate gemfile for matrix-specific jobs: `BUNDLE_GEMFILE=$(pwd)/gemfiles/<name>.gemfile`.
- Smoke verification: `bundle exec rake test:main`. Baseline general testing (no native or integration testing).
- Lint and type check: `bundle exec rake standard typecheck`.
- Type check specific sources: `bundle exec steep check [sources]`.
- Discover tasks: `bundle exec rake -T`.
- Run targeted specs: `bundle exec rspec spec/path/to/file_spec.rb[:line]`. Only use this for specs covered by `test:main` or under `spec/datadog/profiling`; use the relevant rake task for other specs.
- Compile native extensions: `bundle exec rake compile` or `bundle exec rake clean compile`. See `docs/ProfilingDevelopment.md` and `docs/LibdatadogDevelopment.md`.

# Project Structure

- `lib/` - Ruby code that's shipped by this gem
- `ext/` - Native code that's shipped by this gem
- `sig/` - RBS signatures maintained with Steep
- `spec/` - RSpec suites mirroring `lib/`
- `Matrixfile`, `appraisal/` - Test matrix gemset specification
- `gemfiles/` - Generated gemfiles from the matrix (no direct editing)
- `.github`, `tasks/github.rake`, `.gitlab-ci.yml`, `.gitlab` - CI
- `lib/datadog/appsec` - app & api protection implementation (formerly known as appsec)
- `lib/datadog/appsec/contrib` - app & api protection integrations with third-party libraries
- `lib/datadog/core` - product-agnostic glue and shared code
- `lib/datadog/error_tracking` - error tracking
- `lib/datadog/kit` - shared product features
- `lib/datadog/data_streams` - Data Streams Monitoring
- `lib/datadog/di` - dynamic instrumentation (`docs/DynamicInstrumentation.md`)
- `lib/datadog/open_feature` - an implementation of OpenFeature Provider https://openfeature.dev/docs/reference/sdks/server/ruby. Before modifying OpenFeature code, specs, or signatures, read and follow `lib/datadog/open_feature/AGENTS.md`.
- `lib/datadog/opentelemetry` - support OpenTelemetry API for tracing and metrics (`docs/OpenTelemetry.md`)
- `lib/datadog/profiling` - profiling
- `lib/datadog/tracing` - distributed tracing
- `lib/datadog/tracing/contrib` - distributed tracing integrations with third-party libraries
- `ext/datadog_profiling_native_extension` - C extension for profiling
- `ext/libdatadog_api` - C bindings for the Rust [libdatadog](github.com/DataDog/libdatadog) library
- `docs/` - Authoritative developer guides. Includes API documentation, upgrade guides, etc.

## Noteworthy paths

- `lib/datadog.rb` - Gem entry point
- `lib/datadog/auto_instrument.rb`, `**/preload.rb` - Alternative gem entry points (`docs/AutoInstrumentation.md`)
- `lib/datadog/core/configuration/components.rb` `lib/datadog/*/component.rb` - global gem wiring and initialization
- `**/settings.rb` - user configuration definition
- `**/ext.rb` - constants for each subsystem
- `lib/datadog/core/telemetry/` - self telemetry for this gem (`docs/TelemetryDevelopment.md`)

## Integration pattern

Each framework integration (`lib/datadog/*/contrib/`) follows a common pattern:
1. `patcher.rb` - Modifies framework behavior
2. `integration.rb` - Describes the integration
3. `ext.rb` - Constants specific to the integration
4. `configuration/settings.rb` - Integration-specific settings

## One-Pipeline (GitLab CI)

The GitLab CI configuration (`.gitlab-ci.yml`) includes a remote template called
"one-pipeline" via `.gitlab/one-pipeline.locked.yml`. This template defines OCI
packaging, lib-injection image building, and promotion jobs shared across all Datadog
tracing libraries.

- **Source repo**: `DataDog/libdatadog-build` on GitHub (`templates/one-pipeline.yml`)
- **Distribution**: A GitLab CI job publishes the template to
  `gitlab-templates.ddbuild.io` under a content-addressed hash. A campaigner tool then
  opens PRs (titled "chore(ci) update one-pipeline") in all consuming repos to update
  the locked URL in `.gitlab/one-pipeline.locked.yml`.
- **Local overrides**: `.gitlab-ci.yml` overrides template variables like
  `OCI_PACKAGE_MAX_SIZE_BYTES` and `LIB_INJECTION_IMAGE_MAX_SIZE_BYTES`. When
  `package-oci` jobs fail with size limit errors, check the local override values in
  `.gitlab-ci.yml` - the template's error messages hardcode the default limit, not the
  actual override value.
- **Consuming repos**: dd-trace-rb, dd-trace-java, dd-trace-py, dd-trace-dotnet,
  dd-trace-js, dd-trace-php, auto_inject, httpd-datadog, nginx-datadog,
  inject-browser-sdk (listed in `libdatadog-build/campaigner-config.yml`).

## images-rb pin updates

`.github/workflows/update-images.yml` receives a `repository_dispatch` from
images-rb (after its `main` builds successfully) and opens a PR pinning this
repo to the new images. images-rb authenticates via the
`images-rb.notify-consumers` dd-octo-sts trust policy
(`.github/chainguard/images-rb.notify-consumers.sts.yaml`), an in-repo file -
no external grant needed. No local trigger otherwise.

# Guidelines

## Ask First

- Modifying dependencies in `datadog.gemspec`, `appraisal/`, or `Matrixfile`
- Editing CI workflows or release automation
- Touching vendored third-party code (except `vendor/rbs`)
- Storing sensitive data or PII in data structures, passing it as function arguments, or logging it
- Modifying `@public_api` annotated code or making backwards-compatible public API changes; read `docs/PublicApi.md` first

## Never

- Write code comment, unless explicitly requested or instructed
- Use `git commit --amend` unless the user explicitly and clearly requests it; create a new commit by default
- Push commits to a remote unless the user explicitly requests it
- Commit secrets, tokens, or credentials
- Edit files under `gemfiles/`; regenerate them with `bundle exec rake dependency:generate`
- Change versioning (`lib/datadog/version.rb`, `CHANGELOG.md`)
- Leave resources open; terminate threads and close files
- Make breaking public API changes
- Use `sleep` in tests for synchronization; use deterministic waits such as `Queue`, `ConditionVariable`, blocking flush methods, or mocked time

## Code changes

- Use `Core::Utils::EnumerableCompat.filter_map` instead of `filter_map` for compatibility with Ruby 2.5 and 2.6 (native `filter_map` requires Ruby 2.7+).
- Use `Datadog::Core::Utils::Time.now` instead of `Time.now` everywhere. The time provider is configurable (for example, for Timecop support), and tests can override it via `Core::Utils::Time.now_provider=`.

## Documentation

- Never mention telemetry in customer-facing Dynamic Instrumentation documentation such as `docs/DynamicInstrumentation.md`. Telemetry is internal and inaccessible to customers; only mention observable behavior, while internal code comments may describe telemetry.
- All user-facing product documentation lives in `docs/GettingStarted.md`; update it when adding user-facing settings or environment variables.

## Environment variables

- Use `DATADOG_ENV`, never `ENV` directly (see `docs/AccessEnvironmentVariables.md`).
- Run `rake local_config_map:generate` when adding new environment variables.

# Testing

`Matrixfile` defines testing combinations, and `appraisal/` files declare their gemsets. Generated gemfiles live under `gemfiles/`. The `Matrixfile` and `Rakefile` are authoritative.

## Always use rake tasks

Tests must be run via `bundle exec rake test:TASK_KEY`, not bare `bundle exec rspec`, because most suites require specific Gemfiles and the rake task selects the correct one. The `test:main` task uses the default Gemfile; its specs and specs under `spec/datadog/profiling` may be run directly with `bundle exec rspec`.

## Finding the right rake task

1. Identify the component from the changed path under `lib/datadog/` or `spec/datadog/` (for example, `appsec`, `profiling`, `redis`, or `sinatra`).
2. Search with `bundle exec rake -T test | grep KEYWORD` using the component name.
3. Check the Rakefile `spec:TASK` definition for included and excluded specs, and check `Matrixfile` for Ruby version compatibility.

## Docker

- AppSec integration tests need Ruby 3.3. Use Ruby 3.3 installed locally or `docker compose run --rm tracer-3.3 /bin/bash`, then run the rake task inside.
- `test:main` and `bundle exec rspec spec/datadog/profiling` can run locally on any Ruby for quick feedback.
- If Bundler fails inside the container after a dependency update, run `bundle install` and retry the rake task once before investigating further.

## Verifying across Ruby versions

Before marking a task complete, run the relevant test task on the earliest and latest Ruby versions supported by its `Matrixfile` entry. Skip unsupported versions.

```bash
# If mise is available (use 2.6 if 2.5 is unavailable; 2.5 no longer builds on macOS):
mise exec ruby@2.6 -- bundle exec rake test:TASK_KEY
mise exec ruby@4.0 -- bundle exec rake test:TASK_KEY
```

```bash
# Otherwise, use Docker:
docker compose run --rm tracer-2.5 bundle exec rake test:TASK_KEY
docker compose run --rm tracer-4.0 bundle exec rake test:TASK_KEY
```

# Pull Requests

- Push branches to `DataDog/dd-trace-rb`, not forks.
- Use `--repo DataDog/dd-trace-rb` with `gh` commands; defaults are unreliable.
- Use `.github/PULL_REQUEST_TEMPLATE.md` as the starting point for PR descriptions.
- Write concisely for the developer performing code review, using one sentence per relevant summary or motivation point.
- Write changelog entries for customers. Use `None.` for internal CI, tooling, and tracer telemetry consumed only by Datadog engineering.
- Telemetry that powers customer-facing Datadog product features, such as DI autocomplete, profiling, or AppSec, needs a customer-facing changelog entry even though its data flows through the Datadog backend.
- Start changelog entries with `Yes.` or `None.`: `Yes. Brief customer-facing summary.` or `None.`. Never provide a summary without the `Yes.` prefix.
- Add `--label "AI Generated"` when creating PRs; the label is sufficient, so do not mention AI in the description.

# GitHub Actions

When creating or modifying workflows in `.github/workflows/`:

## Security

- Never interpolate user input directly in `run:` blocks; use `env:` instead:

  ```yaml
  # BAD: run: echo "${{ github.event.comment.body }}"
  # GOOD:
  env:
    COMMENT: ${{ github.event.comment.body }}
  run: echo "$COMMENT"
  ```

- User-controllable inputs include `github.event.comment.body`, `github.event.issue.title`, `github.event.pull_request.title`, and `github.head_ref`.
- Pin actions to a SHA: `uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2`.
- Set `permissions: {}` at workflow level and explicit minimal permissions per job.
- Prefer `pull_request` over `pull_request_target`.

## Shell scripts

- Always quote variables: `"$VAR"`, not `$VAR`.
- Quote `$GITHUB_OUTPUT`: `echo "key=value" >> "$GITHUB_OUTPUT"`.
- Group multiple redirects: `{ echo "a"; echo "b"; } >> "$GITHUB_OUTPUT"`.
- Avoid heredocs; use echo grouping instead.

## Validation

```bash
yamllint --strict .github/workflows/your-workflow.yml
actionlint .github/workflows/your-workflow.yml
```

# Style

StandardRB enforces style: `bundle exec rake standard:fix`.

Additional team preferences:
- Use trailing commas in multi-line arrays, hashes, and arguments.
- Mirror the `lib/` structure in RBS definitions under `sig/`.
- Use `Type?` over `(nil | Type)`.
- Type a value with its specific concrete type when it has one, rather than `untyped` or `any`.
- Use a generic type parameter to preserve an input/output relationship (for example, `[T < Object] (T item) -> T`) rather than `untyped` or `any`; `any` is the fallback for genuinely unconstrained values, not a substitute for a generic.
- Use `any` only when every possible type is intentionally valid and the code does not depend on the value's concrete type. If the type is merely unknown or not yet modelled, use `untyped`.

Ruby idioms:
- Prefer `x.to_s` over `x || ''` for nil-safe string conversion.
- Prefer `return unless x` over `return nil unless x` (implicit nil).
- Prefix unused method arguments with `_` (for example, `_unused`) or use `**_opts` for intentionally ignored keyword arguments.

# Gotchas

- Pipe `rspec` and `rake test:*` output through `2>&1 | tee /tmp/full_rspec.log | grep -E 'Pending:|Failures:|Finished' -A 99` for concise but complete results.
- Thread leaks: use `rspec --seed <N>` and inspect `docs/DevelopmentGuide.md#ensuring-tests-dont-leak-resources`.
- `docker compose run` failures: run `docker compose pull` before retrying.
- `ProbeNotifierWorker#flush` blocks until queues are empty; never add `sleep` after it.

# References

- `docs/DevelopmentGuide.md` - detailed development workflows
- `docs/GettingStarted.md` - user-facing documentation
- `docs/StaticTypingGuide.md` - RBS and Steep usage
- `docs/PublicApi.md` - public API guidelines

# How to Use This File

- This file is the source of truth for repository-wide agent guidance; `CLAUDE.md` imports it and should not duplicate it.
- Read files before editing them.
- When the user says "suggest" or asks a question, analyze only; do not modify code.
- When the user says "fix", "change", or "update", make the changes.
- If a requested change contradicts code evidence, alert the user before proceeding.
- If a requested web page is inaccessible, state this and explain the basis for any suggestions.
- Read the specialized personas under `.cursor/rules/` when writing code (`code-style.mdc`) or tests (`testing.mdc`).
- Claude Code skills and hooks live under `.claude/`; see `.claude/hooks/README.md` for the hook build, test, and native re-verification workflow.
- This `AGENTS.md` is a living document; update it when CI or scripts evolve, and update specialized personas as appropriate.

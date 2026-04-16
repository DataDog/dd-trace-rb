This repository is the source code of a Ruby gem created by Datadog to provide Distributed Tracing (APM), Profiling, App & API Protection (AppSec), Dynamic Instrumentation (DI, Live Debugger), Data Streams Monitoring (DSM), Error Tracking, OpenTelemetry, and OpenFeature to Ruby applications.

# Setup & Quick Commands

**Ruby version compatibility:** Ruby 2.5+ (including 3.x+ and 4.x+)

- Launch MRI container: `docker compose run --rm tracer-3.4 /bin/bash`. Matches CI defaults. Other Ruby versions and variants in `docker-compose.yml`.
- Install deps: `bundle install`. Run once per container/session.
- Discover gemfiles: `bundle exec rake dependency:list`. Shows values for `BUNDLE_GEMFILE`.
- Using alternate gemfile: `BUNDLE_GEMFILE=$(pwd)/gemfiles/<name>.gemfile`. For running matrix-specific jobs.
- Smoke verification: `bundle exec rake test:main`. Baseline general testing (no native or integration testing).
- Lint and type check: `bundle exec rake standard typecheck`.
- Discover tasks: `bundle exec rake -T`.
- Targeted test runs (only for `test:main` specs): `bundle exec rspec spec/path/to/file_spec.rb[:line]`. For contrib/integration tests, always use `bundle exec rake test:TASK_KEY` (see "Testing matrix" below).
- Native extension compilation: `bundle exec rake compile` or `bundle exec rake clean compile`. See `docs/ProfilingDevelopment.md` & `docs/LibdatadogDevelopment.md`.

# Project Structure

- @lib/ - Ruby code that's shipped by this gem
- @ext/ - Native code that's shipped by this gem
- @sig/ - RBS signatures maintained with Steep
- @spec/ - RSpec suites mirroring @lib/
- @Matrixfile, @appraisal/ - Test matrix gemset specification
- @gemfiles/ - Generated gemfiles from the matrix (no direct editing)
- @.github, @tasks/github.rake, @.gitlab-ci.yml, @.gitlab - CI
- @lib/datadog/appsec - app & api protection implementation (formely known as appsec)
- @lib/datadog/appsec/contrib - app & api protection integrations with third-party libraries
- @lib/datadog/core - product-agnostic glue and shared code
- @lib/datadog/error_tracking - error tracking
- @lib/datadog/kit - shared product features
- @lib/datadog/data_streams - Data Streams Monitoring
- @lib/datadog/di - dynamic instrumentation (`docs/DynamicInstrumentation.md`)
- @lib/datadog/open_feature - an implementation of OpenFeature Provider https://openfeature.dev/docs/reference/sdks/server/ruby
- @lib/datadog/opentelemetry - support OpenTelemetry API for tracing and metrics (`docs/OpenTelemetry.md`)
- @lib/datadog/profiling - profiling
- @lib/datadog/tracing - distributed tracing
- @lib/datadog/tracing/contrib - distributed tracing integrations with third-party libraries
- @ext/datadog_profiling_native_extension - C extension for profiling
- @ext/libdatadog_api - C bindings for the Rust [libdatadog](github.com/DataDog/libdatadog) library
- @docs/ - Authoritative developer guides. Includes API documentation, upgrade guides, etc.

## Noteworthy paths

- @lib/datadog.rb - Gem entry point
- @lib/datadog/auto_instrument.rb, @**/preload.rb - Alternative gem entry points (`docs/AutoInstrumentation.md`)
- @lib/datadog/core/configuration/components.rb @lib/datadog/*/component.rb - global gem wiring and initialization
- @**/settings.rb - user configuration definition
- @**/ext.rb - constants for each subsystem
- @lib/datadog/core/telemetry/ - self telemetry for this gem (`docs/TelemetryDevelopment.md`)

## Integration pattern

Each framework integration (@lib/datadog/*/contrib/) follows a common pattern:
1. `patcher.rb` - Modifies framework behavior
2. `integration.rb` - Describes the integration
3. `ext.rb` - Constants specific to the integration
4. `configuration/settings.rb` - Integration-specific settings

## Testing matrix

- `Matrixfile` defines testing combinations, and `appraisal/` files declare respective gemsets. `gemfiles/` are tool generated files.
- **The Matrixfile and Rakefile are the authoritative sources of truth.**

### Always use rake tasks

Tests MUST be run via `bundle exec rake test:TASK_KEY`, not bare `bundle exec rspec`. Contrib/integration tests require specific Gemfiles managed by appraisals; running them with `bundle exec rspec` will fail due to missing dependencies. The only exception: specs under `test:main` can also be run individually with `bundle exec rspec`.

### Finding the right rake task

1. **Identify the component**: determine which product or contrib the changed files belong to based on their path under `lib/datadog/` or `spec/datadog/` (e.g. `appsec`, `profiling`, `redis`, `sinatra`)
2. **Search for a matching task**: `bundle exec rake -T test | grep KEYWORD` using the component name as KEYWORD
3. **Verify the task**: check the Rakefile `spec:TASK` definition to confirm which spec files are included/excluded, and check the Matrixfile for Ruby version compatibility

The `test:main` task uses the default Gemfile and its specs can also be run individually with `bundle exec rspec`.

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
  `.gitlab-ci.yml` — the template's error messages hardcode the default limit, not the
  actual override value.
- **Consuming repos**: dd-trace-rb, dd-trace-java, dd-trace-py, dd-trace-dotnet,
  dd-trace-js, dd-trace-php, auto_inject, httpd-datadog, nginx-datadog,
  inject-browser-sdk (listed in `libdatadog-build/campaigner-config.yml`).

# Guidelines

## ⚠️ Ask First
- Adjusting dependencies in `datadog.gemspec`, `appraisal/`, or `Matrixfile`.
- Editing CI workflows, or release automation.
- Touching vendored third-party `lib` code. (`vendor/rbs` is ok).
- Store sensitive data or PII in data structures, or pass as function arguments, nor log them.
- Make backwards-compatible Public API changes.

## 🚫 Never
- Commit secrets, tokens, or credentials.
- Manually edit files under `gemfiles/`; regenerate via rake or let CI do it automatically.
- Change versioning (`lib/datadog/version.rb`, `CHANGELOG.md`).
- Leave resources open (threads must be terminated, files must be closed).
- Make breaking Public API changes.

# Gotchas

- Always pipe stdout and stderr of `rspec` and `rake test:*` to `2>&1 | tee /tmp/full_rspec.log | grep -E 'Pending:|Failures:|Finished' -A 99` to get concise but complete test outputs.
- Transport noise (`Internal error during Datadog::Tracing::Transport::HTTP::Client request`) is expected unless you are debugging transport logic.
- Profiling specs fail on MacOS without additinal setup; ask user if they actually want to run them.
- Thread leaks: use `rspec --seed <N>` and inspect `docs/DevelopmentGuide.md#ensuring-tests-dont-leak-resources`.
- `docker compose run` failures: run `docker compose pull` before retrying.

# How to Use This File

- There are specialized personas under `.cursor/rules/`. You MUST read them if:
  - Writing code: `.cursor/rules/code-style.mdc`.
  - Writing tests: `.cursor/rules/testing.mdc`.
- `docs/GettingStarted.md` is the public documentation of this repo (2900+ lines). All user-facing product documentation lives there.
- This AGENTS.md is a living document: update it when CI or scripts evolve. Update specialized personas as well.

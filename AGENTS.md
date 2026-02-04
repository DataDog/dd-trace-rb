This repository is the source code of a Ruby gem created by Datadog to provide Distributed Tracing (APM), Profiling, App & API Protection (AppSec), Dynamic Instrumentation (DI, Live Debugger), Data Streams Monitoring (DSM), Error Tracking, OpenTelemetry, and OpenFeature to Ruby applications.

# Setup & Quick Commands

**Ruby version compability:** Ruby 2.5 to 4.0.

- Launch MRI container: `docker compose run --rm tracer-3.4 /bin/bash`. Matches CI defaults. Other Ruby versions and variants in `docker-compose.yml`.
- Install deps: `bundle install`. Run once per container/session.
- Discover gemfiles: `bundle exec rake dependency:list`. Shows values for `BUNDLE_GEMFILE`.
- Using alternate gemfile: `BUNDLE_GEMFILE=$(pwd)/gemfiles/<name>.gemfile`. For running matrix-specific jobs.
- Smoke verification: `bundle exec rake test:main`. Baseline general testing (no native or integration testing).
- Lint and type check: `bundle exec rake standard typecheck`.
- Discover tasks: `bundle exec rake -T`.
- Targeted test runs: `bundle exec rspec spec/path/to/file_spec.rb[:line]` or `BUNDLE_GEMFILE=$(pwd)/gemfiles/<name>.gemfile bundle exec rspec spec/path/to/file_spec.rb[:line]`.
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
- This AGENTS.md is a living document: update it when rake tasks, CI, or scripts evolve. Update specialized personas as well.

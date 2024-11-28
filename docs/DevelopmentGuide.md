# Developing

This guide covers some of the common how-tos and technical reference material for developing changes within the trace library.

## Table of Contents

 - [Setting up](#setting-up)
 - [Testing](#testing)
     - [Writing tests](#writing-tests)
     - [Running tests](#running-tests)
     - [Checking code quality](#checking-code-quality)
 - [Appendix](#appendix)
     - [Writing new integrations](#writing-new-integrations)

## Setting up

*NOTE: To test locally, you must have `Docker` and `Docker Compose` installed. See the [Docker documentation](https://docs.docker.com/compose/install/) for details.*

The trace library uses Docker Compose to create a Ruby environment to develop and test within, as well as containers for any dependencies that might be necessary for certain kinds of tests.

To start a development environment, choose a target Ruby version then run the following:

```bash
# In the root directory of the project...
cd ~/dd-trace-rb

# Create and start a Ruby 3.3 test environment with its dependencies
docker compose run --rm tracer-3.3 /bin/bash

# Then inside the container (e.g. `root@2a73c6d8673e:/app`)...
# Install the library dependencies
bundle install
```

Then within this container you can [run tests](#running-tests), or [run code quality checks](#checking-code-quality).

## Testing

The test suite uses [RSpec](https://rspec.info/) tests to verify the correctness of both the core trace library and its integrations.

### Writing tests

New tests should be written as RSpec tests in the `spec/datadog` folder. Test files should generally mirror the structure of `lib`.

All changes should be covered by a corresponding RSpec tests. Unit tests are preferred, and integration tests are accepted where appropriate (e.g. acceptance tests, verifying compatibility with datastores, etc) but should be kept to a minimum.

**Considerations for CI**

All tests should run in CI. When adding new `_spec.rb` files, you may need to add rake task to ensure your test file is run in CI.

 - Ensure that there is a corresponding Rake task defined in `Rakefile` under the `spec` namespace, whose pattern matches your test file. For example

 ```ruby
   namespace :spec do
     RSpec::Core::RakeTask.new(:foo) do |t, args|
       t.pattern = "spec/datadog/tracing/contrib/foo/**/*_spec.rb"
       t.rspec_opts = args.to_a.join(' ')
     end
   end
 ```

 - Ensure the Rake task is configured to run for the appropriate Ruby runtimes, by adding it to our `Matrixfile`. You should find the task with `bundle exec rake -T test:foo` after adding it.

```ruby
  {
    'foo' => {
      # With default dependencies for each Ruby runtime
      ''    => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
      # or with dependency group definition `foo-on-rails`, that includes additional gems
      'foo-on-rails' => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby'
    },
  }
```

### Running tests

`bundle exec rake ci` will run the entire test suite with any given Ruby runtime, just as CI does. However, this is not recommended because it is going take a long time.

**For the core library**

Run the tests for the core library with:

```
$ bundle exec rake test:main
```

**For integrations**

Integrations which interact with dependencies not listed in the `datadog` gemspec will need to load these dependencies to run their tests. Each test task could consist of multiple spec tasks which are executed with different groups of dependencies (likely against different versions or variations).

To get a list of the test tasks, run `bundle exec rake -T test:`

To run test, run `bundle exec rake test:<spec_name>`

Take `bundle exec rake test:redis` as example, multiple versions of `redis` from different dependency definitions are being tested (from `Matrixfile`).


```ruby
{
  'redis' => {
    'redis-3' => '✅ 2.1 / ✅ 2.2 / ✅ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
    'redis-4' => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ✅ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby',
    'redis-5' => '❌ 2.1 / ❌ 2.2 / ❌ 2.3 / ❌ 2.4 / ✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ jruby'
  }
}
```

If the dependency groups are prepared (with up-to-date gemfile and lockfile), the test task would install them before running the test.

**Working with different dependencies**

We are actively developing tools to make it easier to manage dependencies. Currently, we are using rake tasks defined in `tasks/dependency.rake`.

You can find them by running the following command:

```bash
bundle exec rake -T dependency:
```

Dependency group definitions are located under `appraisal/` directory using the same DSL provided by [Appraisal](https://github.com/thoughtbot/appraisal). These definitions are used to generate `gemfiles/*.gemfile` and then `gemfiles/*.lock`. All the files are underscored and prefixed with Ruby runtime.

> [!IMPORTANT]
> Do NOT manually edit `gemfiles/*.gemfile` or `gemfiles/*.lock`. Instead, make changes to `appraisal/*.rb` and propagates your changes programmatically

To find out existing gemfiles in your environment, run

```bash
bundle exec rake dependency:list
```

`dependency:list` is convenient to look for a specific gemfile path before assigning it to the environment variable `BUNDLE_GEMFILE` for doing all kinds of stuff.

```bash
env BUNDLE_GEMFILE=/app/gemfiles/ruby_3.3_stripe_latest.gemfile bundle update stripe
```

After introducing a new dependency group or changing existing one, run `bundle exec rake dependency:generate` to propagate the changes to the gemfile. `dependency:generate` is idempotent and only changes `gemfiles/*.gemfile` but not `gemfiles/*.lock`.

To keep lockfile up-to-date with the gemfile, run `bundle exec rake dependency:lock`.

To install, run `bundle exec rake dependency:install`.

Both `dependency:lock` and `dependency:install` can be provided with a specific gemfile path (from `dependency:list`) or pattern to target specific groups. For example:

```bash
# Generates lockfiles for all the stripe groups with `stripe_*` pattern
bundle exec rake dependency:lock['/app/gemfiles/ruby_3.3_stripe_*.gemfile']
# or only generate lockfile for `stripe_latest` group
bundle exec rake dependency:lock['/app/gemfiles/ruby_3.3_stripe_latest.gemfile']
```

**Passing arguments to tests**

When running tests, you may pass additional args as parameters to the Rake task. For example:

```
# Runs Redis tests with seed 1234
$ bundle exec rake test:redis'[--seed 1234]'
```

This can be useful for replicating conditions from CI or isolating certain tests.

**Checking test coverage**

You can check test code coverage by creating a report _after_ running a test suite:
```
# Run the desired test suite
$ bundle exec rake test:redis
# Generate report for the suite executed
$ bundle exec rake coverage:report
```

A webpage will be generated at `coverage/report/index.html` with the resulting report.

Because you are likely not running all tests locally, your report will contain partial coverage results.
You *must* check the CI step `coverage` for the complete test coverage report, ensuring coverage is not
decreased.

**Ensuring tests don't leak resources**

Tests execution can create resources that are hard to track: threads, sockets, files, etc. Because these resources can come
from the both the test setup as well as the code under test, making sure all resources are properly disposed is important
to prevent the application from inadvertently creating cumulative resources during its execution.

When running tests that utilize threads, you might see an error message similar to this one:

```
Test leaked 1 thread: "Datadog::Workers::AsyncTransport integration tests"
Ensure all threads are terminated when test finishes:
1: #<Thread:0x00007fcbc99863d0 /Users/marco.costa/work/dd-trace-rb/spec/spec_helper.rb:145 sleep> (Thread)
Thread Creation Site:
        ./dd-trace-rb/spec/datadog/tracing/workers_integration_spec.rb:245:in 'new'
        ./dd-trace-rb/spec/datadog/tracing/workers_integration_spec.rb:245:in 'block (4 levels) in <top (required)>'
Thread Backtrace:
        ./dd-trace-rb/spec/datadog/tracing/workers_integration_spec.rb:262:in 'sleep'
        .dd-trace-rb/spec/datadog/tracing/workers_integration_spec.rb:262:in 'block (5 levels) in <top (required)>'
        ./dd-trace-rb/spec/spec_helper.rb:147:in 'block in initialize'
```

This means that this test did not finish all threads by the time the test had finished. In this case, the thread
creation can be traced to `workers_integration_spec.rb:245:in 'new'`. The thread itself is sleeping at `workers_integration_spec.rb:262:in 'sleep'`.

The actionable in this case would be to ensure that the thread created in `workers_integration_spec.rb:245` is properly terminated by invoking `Thread#join` during the test tear down, which will wait for the thread to finish before returning.

Depending on the situation, the thread in question might need to be forced to terminate. It's recommended to have a mechanism in place to terminate it (a shared variable that changes value when the thread should exit), but as a last resort, `Thread#terminate` forces the thread to finish. Keep in mind that regardless of the termination method, `Thread#join` must be called to ensure that the thread has completely finished its shutdown process.

**The APM Test Agent**

The APM test agent emulates the APM endpoints of the Datadog Agent. The Test Agent container
runs alongside the Ruby tracer locally and in CI, handles all traces during test runs and performs a number
of 'Trace Checks'. For more information on these checks, see:
https://github.com/DataDog/dd-apm-test-agent#trace-invariant-checks

The APM Test Agent also emits helpful logging, which can be viewed in local testing or in CircleCI as a job step for tracer and contrib
tests. Locally, to get Test Agent logs:

    $ docker-compose logs -f testagent

Read more about the APM Test Agent:
https://github.com/datadog/dd-apm-test-agent#readme

### Checking code quality

**Linting**

The trace library uses Rubocop to enforce [code style](https://github.com/bbatsov/ruby-style-guide) and quality. To check, run:

```
$ bundle exec rake rubocop
```

## Appendix

### Writing new integrations

Integrations are extensions to the trace library that add support for external dependencies (gems); they typically add auto-instrumentation to popular gems and frameworks. You will find many of our integrations in the `contrib` folder.

Some general guidelines for adding new integrations:

 - An integration can either be added directly to `dd-trace-rb`, or developed as its own gem that depends on `datadog`.
 - Integrations should implement the configuration API for easy, consistent implementation. (See existing integrations as examples of this.)
 - All new integrations require documentation, unit/integration tests written in RSpec, and passing CI builds.
 - It's highly encouraged to share screenshots or other demos of how the new integration looks and works.

To get started quickly, it's perfectly fine to copy-paste an existing integration to use as a template, then modify it to match your needs. This is usually the fastest, easiest way to bootstrap a new integration and makes the time-to-first-trace often very quick, usually less than an hour if it's a simple implementation.

Once you have it working in your application, you can [add unit tests](#writing-tests), [run them locally](#running-tests), and [check for code quality](#checking-code-quality) using Docker Compose.

Then [open a pull request](../CONTRIBUTING.md#have-a-patch) and be sure to add the following to the description:

 - [Documentation](./GettingStarted.md) for the integration, including versions supported.
 - Links to the repository/website of the library being integrated
 - Screenshots showing a sample trace
 - Any additional code snippets, sample apps, benchmarks, or other resources that demonstrate its implementation are a huge plus!

### Generating GRPC proto stubs for tests

If you modify any of the `.proto` files under `./spec/datadog/tracing/contrib/grpc/support/proto` used for
testing the `grpc` integration, you'll need to regenerate the Ruby code by running:

```
$ docker run \
   --platform linux/amd64 \
   -v ${PWD}:/app \
   -w /app \
   ruby:latest \
   ./spec/datadog/tracing/contrib/grpc/support/gen_proto.sh
```

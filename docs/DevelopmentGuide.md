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
     - [Community pull requests](#community-pull-requests)

## Setting up

*NOTE: To test locally, you must have `Docker` and `Docker Compose` installed. See the [Docker documentation](https://docs.docker.com/compose/install/) for details.*

The trace library uses Docker Compose to create a Ruby environment to develop and test within, as well as containers for any dependencies that might be necessary for certain kinds of tests.

To start a development environment, choose a target Ruby or JRuby version.
Some of the development tooling is only defined for the recent MRI versions,
therefore we suggest using Ruby 3.4 unless you specifically need a different
version. Run the following:

```bash
# In the root directory of the project...
cd ~/dd-trace-rb

# Create and start a Ruby 3.4 test environment with its dependencies
docker compose run --rm tracer-3.4 /bin/bash

# or a JRuby test environment with its dependencies
docker compose run --rm tracer-jruby-9.4 /bin/bash

# Then inside the container (e.g. `root@2a73c6d8673e:/app`)...
# Install the library dependencies
bundle install
```

Within this container, you can [run tests](#running-tests) or [run code quality checks](#checking-code-quality).

## Testing

The test suite uses [RSpec](https://rspec.info/) tests to verify the correctness of both the core trace library and its integrations.

### Writing tests

New tests should be written as RSpec tests in the `spec/datadog` folder. Test files should generally mirror the structure of `lib`.

All changes should be covered by corresponding RSpec tests. Unit tests are preferred, and integration tests are accepted where appropriate (e.g. acceptance tests, verifying compatibility with datastores, etc) but should be kept to a minimum.

### Running tests

#### For the core library

Any file that is **not** inside a `contrib` folder is part of the core library.

You can run all the tests for the core library with:

```
bundle exec rake test:main
```

##### Specific core tests

You can also run only a subset of the core library tests.

For example, for the test files [utils_spec.rb](https://github.com/DataDog/dd-trace-rb/blob/d66a6688f6cddab6a8c3cb1d6e0a6bfe86928e44/spec/datadog/core/utils_spec.rb) and
[error_spec.rb](https://github.com/DataDog/dd-trace-rb/blob/d66a6688f6cddab6a8c3cb1d6e0a6bfe86928e44/spec/datadog/core/error_spec.rb), you can run:

```bash
# Runs all tests in utils_spec.rb
bundle exec rspec spec/datadog/core/utils_spec.rb

# Runs only the test on line 24
bundle exec rspec spec/datadog/core/utils_spec.rb:24

# Runs the test on line 24 of utils_spec.rb and all the tests in error_spec.rb
bundle exec rspec spec/datadog/core/utils_spec.rb:24 spec/datadog/core/error_spec.rb
```

#### All tests

`bundle exec rake ci` will run the entire test suite with any given Ruby runtime, just as CI does.
However, this is not recommended because it will take a long time.

Instead, run [specific core tests](#specific-core-tests), [integation tests](#for-integrations), or [the core library tests](#for-the-core-library).

#### For integrations

Integrations which interact with dependencies not listed in the `datadog` gemspec will need to load these dependencies to run their tests. Each test task could consist of multiple spec tasks which are executed with different groups of dependencies (likely against different versions or variations).

Any file that **is** inside a `contrib` folder is part of an integration.

To get a list of the test tasks, run `bundle exec rake -T test:`

To run a test, run `bundle exec rake test:<spec_name>`

Take `bundle exec rake test:redis` as example: multiple versions of `redis` from different dependency definitions are being tested (from `Matrixfile`).


```ruby
{
  'redis' => {
    'redis-3' => '✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ 3.4 / ✅ jruby',
    'redis-4' => '✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ 3.4 / ✅ jruby',
    'redis-5' => '✅ 2.5 / ✅ 2.6 / ✅ 2.7 / ✅ 3.0 / ✅ 3.1 / ✅ 3.2 / ✅ 3.3 / ✅ 3.4 / ✅ jruby'
  }
}
```

If the dependency groups are prepared (with up-to-date gemfile and lockfile), the test task will install them before running the test.

**Working with different dependencies**

We are actively developing tools to make it easier to manage dependencies. Currently, we are using rake tasks defined in `tasks/dependency.rake`.

You can find them by running the following command:

```bash
bundle exec rake -T dependency:
```

Dependency group definitions are located under the `appraisal/` directory using the same DSL provided by [Appraisal](https://github.com/thoughtbot/appraisal). These definitions are used to generate `gemfiles/*.gemfile` and then `gemfiles/*.lock`. All the files are underscored and prefixed with the Ruby or JRuby runtime version.

> [!IMPORTANT]
> Do NOT manually edit `gemfiles/*.gemfile` or `gemfiles/*.lock`. Instead, make changes to `appraisal/*.rb` and propagate your changes programmatically.

To find the existing gemfiles in your environment, run

```bash
bundle exec rake dependency:list
```

`dependency:list` is convenient to look for a specific gemfile path before assigning it to the environment variable `BUNDLE_GEMFILE`. `BUNDLE_GEMFILE` is useful for doing all kinds of stuff, such as:

```bash
env BUNDLE_GEMFILE=/app/gemfiles/ruby_3.4_stripe_latest.gemfile bundle update stripe
```

After introducing a new dependency group or changing an existing one, run `bundle exec rake dependency:generate` to propagate the changes to the gemfile. `dependency:generate` is idempotent and only changes `gemfiles/*.gemfile` but not `gemfiles/*.lock`.

To keep lockfiles up-to-date with the gemfile, run `bundle exec rake dependency:lock`.

To install the dependencies, run `bundle exec rake dependency:install`.

Both `dependency:lock` and `dependency:install` can be provided with a specific gemfile path (from `dependency:list`) or pattern to target specific groups. For example:

```bash
# Generate lockfiles for all the stripe groups with `stripe_*` pattern
bundle exec rake dependency:lock['/app/gemfiles/ruby_3.4_stripe_*.gemfile']
# or only generate lockfile for the `stripe_latest` group
bundle exec rake dependency:lock['/app/gemfiles/ruby_3.4_stripe_latest.gemfile']
```

**How to add a new dependency group**

> [!IMPORTANT]
> Add a new group only if the existing groups do not meet your requirements, or if adding a new dependency to an existing group is impractical.
> Remember, each new group increases maintenance and CI costs.

1. Choose the Ruby runtime and group name for your tests. When defining a new group, follow the format `scope:group`.
For example, if you want tests to run only on Ruby 3.3 for tracing, you can define this in the [`Matrixfile`](../Matrixfile).

```ruby
{
  'tracing:ruby_on_rails' => {
    # With default dependencies for each Ruby runtime
    '' => '❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ 3.3 / ❌ 3.4 / ❌ jruby'
    # or with dependency group definition `ruby-on-rails`, that includes additional gems or specific versions
    'rails-1' => '❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ 3.3 / ❌ 3.4 / ❌ jruby'
    # ...
    'rails-edge' => '❌ 2.5 / ❌ 2.6 / ❌ 2.7 / ❌ 3.0 / ❌ 3.1 / ❌ 3.2 / ✅ 3.3 / ❌ 3.4 / ❌ jruby'
  }
}
```

2. Define the required gems in the corresponding Appraisal file. For this example, we are going to use [`Appraisal/ruby-3.3.rb`](../Appraisal/ruby-3.3.rb). Let's define what the `rails-edge` group needs.

```ruby
appraise 'rails-edge' do
  gem 'rails', '>= 8'
end
```

3. Now let's generate that dependency Gemfile with `rake`. Simply run

> [!IMPORTANT]
> Ensure you are either using Ruby 3.3 as the current Ruby version (`ruby -v`) or running commands within a Docker container.

```console
$ bundle exec rake dependency:generate
...
ruby-3.3_rails-edge
```

Verify that the new dependency appears in the list.

```console
$ bundle exec rake dependency:list
Ahoy! Here is a list of gemfiles you are looking for:

========================================
...
/Users/DataDog/dd-trace-rb/gemfiles/ruby_3.3_rails_edge.gemfile
```

4. Use the following command to lock the gem versions.

```console
$ bundle exec rake dependency:lock[]
BUNDLE_GEMFILE=/Users/DataDog/dd-trace-rb/gemfiles/ruby_3.3_rails_edge.gemfile bundle lock --add-platform x86_64-linux aarch64-linux
Fetching gem metadata from https://rubygems.org/...........
Resolving dependencies...
Writing lockfile to /Users/DataDog/dd-trace-rb/gemfiles/ruby_3.3_rails_edge.gemfile.lock
```

5. The last step is to associate the newly generated group with some tests. It can be done in the [`Rakefile`](../Rakefile).

> [!IMPORTANT]
> Ensure the `scope:group` format matches the rake task name.
> In our case, we should define it as `tracing:ruby_on_rails` under `spec` namespace.

```ruby
namespace :spec do
  namespace :tracing do
    RSpec::Core::RakeTask.new(:ruby_on_rails) do |t, args|
      t.pattern = "spec/datadog/tracing/contrib/ruby_on_rails/**/*_spec.rb"
      t.rspec_opts = args.to_a.join(' ')
    end
  end
end
```

and now you should be able to find it by running

```console
$ bundle exec rake -T test:tracing
rake test:tracing:ruby_on_rails[task_args]  # Run spec:tracing:ruby_on_rails tests
```

At this point, the new tests will be automatically included in the CI that runs on every pull request.

**Passing arguments to tests**

When running tests, you may pass additional args as parameters to the Rake task. For example:

```
# Run Redis tests with seed 1234
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
You *must* check the CI step `coverage` for the complete test coverage report, ensuring coverage does not
decrease.

**Ensuring tests don't leak resources**

Test execution can create resources that are hard to track: threads, sockets, files, etc. Because these resources can come
from both the test setup as well as the test code itself, making sure all resources are properly disposed of is important
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

The actionable in this case would be to ensure that the thread created in `workers_integration_spec.rb:245` is properly terminated by invoking `Thread#join` during the test teardown, which will wait for the thread to finish before returning.

Depending on the situation, the thread in question might need to be forced to terminate. It's recommended to have a mechanism in place to terminate it (a shared variable that changes value when the thread should exit), but as a last resort, `Thread#terminate` forces the thread to finish. Keep in mind that regardless of the termination method, `Thread#join` must be called to ensure that the thread has completely finished its shutdown process.

**The APM Test Agent**

The APM test agent emulates the APM endpoints of the Datadog Agent. The Test Agent container
runs alongside the Ruby tracer locally and in CI, handles all traces during test runs, and performs a number
of 'Trace Checks'. For more information on these checks, see:
https://github.com/DataDog/dd-apm-test-agent#trace-invariant-checks

The APM Test Agent also emits helpful logging, which can be viewed in local testing or in CI as a job step for tracer and contrib
tests. Locally, to get Test Agent logs run:

```
docker-compose logs -f testagent
```

Read more about the APM Test Agent:
https://github.com/datadog/dd-apm-test-agent#readme

### Checking code quality

**Linting**

Most of the library uses Rubocop to enforce [code style](https://github.com/bbatsov/ruby-style-guide) and quality. To check, run:

```
bundle exec rake rubocop
```

To change your code to the version that rubocop wants, run:

```
bundle exec rake rubocop -A
```

Profiling and Dynamic Instrumentation use [standard](https://github.com/standardrb/standard)
instead of Rubocop. To check files with standard, run:

```
bundle exec rake standard
```

To change your code to the version that standard wants, run:

```
bundle exec rake standard:fix
```

For non-Ruby code, follow the instructions below to debug locally, if CI failed with the respective linter.

- For `yamllint`, run:
```bash
docker run --rm -v $(pwd):/dd-trace-rb -w /dd-trace-rb cytopia/yamllint .
```

- For `actionlint`, run:
```bash
docker run --rm -v $(pwd):/dd-trace-rb -w /dd-trace-rb rhysd/actionlint -color
```

- For `zizmor`, run:
```bash
docker run --rm -v $(pwd):/dd-trace-rb -w /dd-trace-rb -e GH_TOKEN=$(gh auth token) ghcr.io/woodruffw/zizmor --min-severity low .
```

## Accessing Environment Variables

If you need to access any environment variables via `ENV`, please see
[Access Environment Variables](./AccessEnvironmentVariables.md) for the
required procedure.

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
docker run \
  --platform linux/amd64 \
  -v ${PWD}:/app \
  -w /app \
  ruby:latest \
  ./spec/datadog/tracing/contrib/grpc/support/gen_proto.sh
```

### Community pull requests

> [!NOTE]
> This is relevant for **internal** use only.

To trigger CI for community PRs, you need to clone the PR branch locally and
push it to the `dd-trace-rb` repository. Here's how to do it using [GitHub CLI](https://cli.github.com/):

```console
$ gh pr checkout 9999
From github.com:DataDog/dd-trace-rb
 * [new ref]               refs/pull/9999/head -> some-branch
Switched to branch 'some-branch'
```

Next, push that branch to the `dd-trace-rb` repository with an arbitrary name.
For example, use `community/pr-9999`:

```console
$ git push origin HEAD:community/pr-9999
Enumerating objects: 45, done.
Counting objects: 100% (42/42), done.
Delta compression using up to 16 threads
Compressing objects: 100% (25/25), done.
Writing objects: 100% (25/25), 7.41 KiB | 7.41 MiB/s, done.
Total 25 (delta 17), reused 0 (delta 0), pack-reused 0 (from 0)
remote: Resolving deltas: 100% (17/17), completed with 15 local objects.
remote:
remote: Create a pull request for 'community/pr-9999' on GitHub by visiting:
remote:      https://github.com/DataDog/dd-trace-rb/pull/new/community/pr-9999
remote:
To github.com:DataDog/dd-trace-rb.git
 * [new branch]            some-branch -> community/pr-9999
```

Finally, create a draft PR with a clear title indicating this is a trigger PR
that **should not** be merged:

```console
$ gh pr create --draft --head community/pr-9999 --title "[IGNORE] Community PR 9999" --body ":warning: DO NOT MERGE :warning:"
Creating pull request for community/pr-9999 into master in DataDog/dd-trace-rb

https://github.com/DataDog/dd-trace-rb/pull/0000
```

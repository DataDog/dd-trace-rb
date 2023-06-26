# Developing

This guide covers some of the common how-tos and technical reference material for developing changes within the trace library.

## Table of Contents

 - [Setting up](#setting-up)
 - [Testing](#testing)
     - [Writing tests](#writing-tests)
     - [Running tests](#running-tests)
     - [Checking code quality](#checking-code-quality)
     - [Running benchmarks](#running-benchmarks)
 - [Appendix](#appendix)
     - [Writing new integrations](#writing-new-integrations)
     - [Custom transport adapters](#custom-transport-adapters)

## Setting up

*NOTE: To test locally, you must have `Docker` and `Docker Compose` installed. See the [Docker documentation](https://docs.docker.com/compose/install/) for details.*

The trace library uses Docker Compose to create a Ruby environment to develop and test within, as well as containers for any dependencies that might be necessary for certain kinds of tests.

To start a development environment, choose a target Ruby version then run the following:

```
# In the root directory of the project...
cd ~/dd-trace-rb

# Create and start a Ruby 3.0 test environment with its dependencies
docker-compose run --rm tracer-3.0 /bin/bash

# Then inside the container (e.g. `root@2a73c6d8673e:/app`)...
# Install the library dependencies
bundle install

# Install build targets
bundle exec appraisal install
```

Then within this container you can [run tests](#running-tests), or [run code quality checks](#checking-code-quality).

## Testing

The test suite uses [RSpec](https://rspec.info/) tests to verify the correctness of both the core trace library and its integrations.

### Writing tests

New tests should be written as RSpec tests in the `spec/ddtrace` folder. Test files should generally mirror the structure of `lib`.

All changes should be covered by a corresponding RSpec tests. Unit tests are preferred, and integration tests are accepted where appropriate (e.g. acceptance tests, verifying compatibility with datastores, etc) but should be kept to a minimum.

**Considerations for CI**

All tests should run in CI. When adding new `spec.rb` files, you may need to add a test task to ensure your test file is run in CI.

 - Ensure that there is a corresponding Rake task defined in `Rakefile` under the the `spec` namespace, whose pattern matches your test file.
 - Verify the Rake task is configured to run for the appropriate Ruby runtimes in the `ci` Rake task.

### Running tests

Simplest way to run tests is to run `bundle exec rake ci`, which will run the entire test suite, just as CI does.

**For the core library**

Run the tests for the core library with:

```
$ bundle exec rake spec:main
```

**For integrations**

Integrations which interact with dependencies not listed in the `ddtrace` gemspec will need to load these dependencies to run their tests.

To do so, load the dependencies using [Appraisal](https://github.com/thoughtbot/appraisal). You can see a list of available appraisals with `bundle exec appraisal list`, or examine the `Appraisals` file.

Then to run tests, prefix the test commain with the appraisal.

`bundle exec appraisal <appraisal_name> rake <test_comand>`


For example:

```
# Runs tests for Rails 6.1 + Postgres
$ bundle exec appraisal ruby-3.0.4-rails61-postgres rake spec:rails
# Runs tests for Redis
$ bundle exec appraisal ruby-3.0.4-contrib rake spec:redis
```

**Passing arguments to tests**

When running RSpec tests, you may pass additional args as parameters to the Rake task. For example:

```
# Runs Redis tests with seed 1234
$ bundle exec appraisal ruby-3.0.4-contrib rake spec:redis'[--seed,1234]'
```

This can be useful for replicating conditions from CI or isolating certain tests.

**Checking test coverage**

You can check test code coverage by creating a report _after_ running a test suite:
```
# Run the desired test suite
$ bundle exec appraisal ruby-3.0.4-contrib rake spec:redis
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
        ./dd-trace-rb/spec/ddtrace/workers_integration_spec.rb:245:in 'new'
        ./dd-trace-rb/spec/ddtrace/workers_integration_spec.rb:245:in 'block (4 levels) in <top (required)>'
Thread Backtrace:
        ./dd-trace-rb/spec/ddtrace/workers_integration_spec.rb:262:in 'sleep'
        .dd-trace-rb/spec/ddtrace/workers_integration_spec.rb:262:in 'block (5 levels) in <top (required)>'
        ./dd-trace-rb/spec/spec_helper.rb:147:in 'block in initialize'
```

This means that this test did not finish all threads by the time the test had finished. In this case, the thread
creation can be traced to `workers_integration_spec.rb:245:in 'new'`. The thread itself is sleeping at `workers_integration_spec.rb:262:in 'sleep'`.

The actionable in this case would be to ensure that the thread created in `workers_integration_spec.rb:245` is properly terminated by invoking `Thread#join` during the test tear down, which will wait for the thread to finish before returning.

Depending on the situation, the thread in question might need to be forced to terminate. It's recommended to have a mechanism in place to terminate it (a shared variable that changes value when the thread should exit), but as a last resort, `Thread#terminate` forces the thread to finish. Keep in mind that regardless of the termination method, `Thread#join` must be called to ensure that the thread has completely finished its shutdown process.

### Checking code quality

**Linting**

The trace library uses Rubocop to enforce [code style](https://github.com/bbatsov/ruby-style-guide) and quality. To check, run:

```
$ bundle exec rake rubocop
```

### Running benchmarks

If your changes can have a measurable performance impact, we recommend running our benchmark suite:

```
$ bundle exec appraisal ruby-3.0.4-contrib rake spec:benchmark
```

Results are printed to STDOUT as well as written to the `./tmp/benchmark/` directory.

## Appendix

### Writing new integrations

Integrations are extensions to the trace library that add support for external dependencies (gems); they typically add auto-instrumentation to popular gems and frameworks. You will find many of our integrations in the `contrib` folder.

Some general guidelines for adding new integrations:

 - An integration can either be added directly to `dd-trace-rb`, or developed as its own gem that depends on `ddtrace`.
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

### Custom transport adapters

The tracer can be configured with transports that customize how data is sent and where it is sent to. This is done through the use of adapters: classes that receive generic requests, process them, and return appropriate responses.

#### Developing HTTP transport adapters

To create a custom HTTP adapter, define a class that responds to `call(env)` which returns a kind of `Datadog::Transport::Response`:

```ruby
require 'ddtrace/transport/response'

class CustomAdapter
  # Sends HTTP request
  # env: Datadog::Transport::HTTP::Env
  def call(env)
    # Add custom code here to send data.
    # Then return a Response object.
    Response.new
  end

  class Response
    include Datadog::Transport::Response

    # Implement the following methods as appropriate
    # for your adapter.

    # Return a String
    def payload; end

    # Return true/false
    # Return nil if it does not apply
    def ok?; end
    def unsupported?; end
    def not_found?; end
    def client_error?; end
    def server_error?; end
    def internal_error?; end
  end
end
```

Optionally, you can register the adapter as a well-known type:

```ruby
Datadog::Transport::HTTP::Builder::REGISTRY.set(CustomAdapter, :custom)
```

Then pass an adapter instance to the tracer configuration:

```ruby
Datadog.configure do |c|
  c.tracing.transport_options = proc { |t|
    # By name
    t.adapter :custom

    # By instance
    custom_adapter = CustomAdapter.new
    t.adapter custom_adapter
  }
end
```

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

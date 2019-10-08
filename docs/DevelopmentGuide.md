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
       - [Configuration for integrations](#configuration-for-integrations)
     - [Custom transport adapters](#custom-transport-adapters)

## Setting up

*NOTE: To test locally, you must have `Docker` and `Docker Compose` installed. See the [Docker documentation](https://docs.docker.com/compose/install/) for details.*

The trace library uses Docker Compose to create a Ruby environment to develop and test within, as well as containers for any dependencies that might be necessary for certain kinds of tests.

To start a development environment, choose a target Ruby version then run the following:

```
# In the root directory of the project...
cd ~/dd-trace-rb

# Create and start a Ruby 2.3 test environment with its dependencies
docker-compose run --rm tracer-2.3 /bin/bash

# Then inside the container (e.g. `root@2a73c6d8673e:/app`)...
# Install the library dependencies
bundle install

# Install build targets
appraisal install
```

Then within this container you can [run tests](#running-tests), or [run code quality checks](#checking-code-quality).

## Testing

The test suite uses both [Minitest](https://github.com/seattlerb/minitest) and [RSpec](https://rspec.info/) tests to verify the correctness of both the core trace library and its integrations.

Minitest is deprecated in favor of RSpec; all new tests should be written in RSpec, and only existing minitests should be updated.

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
# Run Minitest
$ bundle exec rake test:main
# Run RSpec
$ bundle exec rake spec:main
```

**For integrations**

Integrations which interact with dependencies not listed in the `ddtrace` gemspec will need to load these dependencies to run their tests.

To do so, load the dependencies using [Appraisal](https://github.com/thoughtbot/appraisal). You can see a list of available appraisals with `bundle exec appraisal list`, or examine the `Appraisals` file.

Then to run tests, prefix the test commain with the appraisal. For example:

```
# Runs tests for Rails 3.2 + Postgres
$ bundle exec appraisal rails32-postgres spec:rails
# Runs tests for Redis
$ bundle exec appraisal contrib rake spec:redis
```

**Passing arguments to tests**

When running RSpec tests, you may pass additional args as parameters to the Rake task. For example:

```
# Runs Redis tests with seed 1234
$ bundle exec appraisal contrib rake spec:redis'[--seed,1234]'
```

This can be useful for replicating conditions from CI or isolating certain tests.

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

 - An integration can either be added directly to `dd-trace-rb`, or developed as its own gem that depends on `ddtrace`.
 - Integrations should implement the configuration API for easy, consistent implementation. (See existing integrations as examples of this.)
 - All new integrations require documentation, unit/integration tests written in RSpec, and passing CI builds.
 - It's highly encouraged to share screenshots or other demos of how the new integration looks and works.

To get started quickly, it's perfectly fine to copy-paste an existing integration to use as a template, then modify it to match your needs. This is usually the fastest, easiest way to bootstrap a new integration and makes the time-to-first-trace often very quick, usually less than an hour if it's a simple implementation.

Once you have it working in your application, you can [add unit tests](#writing-tests), [run them locally](#running-tests), and [check for code quality](#checking-code-quality) using Docker Compose.

Then [open a pull request](https://github.com/DataDog/dd-trace-rb/CONTRIBUTING.md#have-a-patch) and be sure to add the following to the description:

 - [Documentation](https://github.com/DataDog/dd-trace-rb/docs/GettingStarted.md) for the integration, including versions supported.
 - Links to the repository/website of the library being integrated
 - Screenshots showing a sample trace
 - Any additional code snippets, sample apps, benchmarks, or other resources that demonstrate its implementation are a huge plus!

#### Configuration for integrations

Integrations can define their own custom settings, which can be configured by the user via:

```ruby
Datadog.configure do |c|
  # Hash syntax
  c.use :my_integration, my_option: 'my-config-value'

  # Block syntax
  c.use :my_integration do |integration|
    integration.my_option = 'my-config-value'
  end
end
````

These settings can then be accessed, and used by the integration to drive behavior for the instrumentation via:

```ruby
Datadog.configuration[:my_integration][:my_option]`
```

They are defined by creating a class that inherits from `Datadog::Contrib::Configuration::Settings`:

```ruby
class Datadog::Contrib::MyIntegration::Configuration::Settings < Contrib::Configuration::Settings
  # Configuration definitions go here...
  option :my_option, default: 'my-default_value'
end
```

**Defining options**

Options store a value that can be set by users and subsequently used by instrumentation.

Options can be defined using `#option`:

```
option OPTION_NAME, META = {}, &BLOCK
```

 - `OPTION_NAME`: A `Symbol` name for the option
 - `META` (optional): A `Hash` of attributes that describes how the option should behave (see list below)
 - `BLOCK` (optional): A `Proc` that accepts an `option` argument, and describes how the option should behave (see list below)

Attributes for options:

**default**

Defines default value for this option. Defaults to `nil`. Default value is eagerly evaluated once.

```ruby
# Hash syntax
option :my_option, default: 'default'

# Block syntax
option :my_option do |o|
  o.default 'default'
end
```

When passed a block and `lazy` is set to true, the block will be evaluated once, at first access time:

```ruby
# Hash syntax
option :my_option, default: -> { 'default' }, lazy: true

# Block syntax
option :my_option do |o|
  o.default { 'default' }
  o.lazy
end
```

Default is ignored if `delegate_to` is defined, which acts as a substitute.

**delegate_to**

Defines a "passthrough" default function, for when the option is not set. Useful if you want to defer to some other value by default, but retain the ability to override it.

```ruby
# Hash syntax
option :my_option, delegate_to: -> { SecureRandom.uuid }

# Block syntax
option :my_option do |o|
  o.delegate_to { SecureRandom.uuid }
end

# Example behavior
settings.my_option # => '2133b034-0f84-44e6-9ee8-2671c118c40a'
settings.my_option # => 'c7078bd2-75e7-4d1e-bc36-b0b6f84ba638'
settings.my_option = 'b37118ef-d67f-44f4-9a2a-f97b99c6f0d7'
settings.my_option # => 'b37118ef-d67f-44f4-9a2a-f97b99c6f0d7'
```

Although they have similar purpose, `delegate_to` and `default` are different in that `default` is only evaluated once, and the value is stored, and `delegate_to` is evaluated each time the option is accessed *until* a value is assigned to the option, after which the assigned value is returned.

**depends_on**

List of options this option depends on. Used when an option depends on another option already being initialized.

```ruby
# Hash syntax
option :my_option, depends_on: [:parent_a, :parent_b]

# Block syntax
option :my_option do |o|
  o.depends_on :parent_a, :parent_b
end

# Example usage
option :child do |o|
  o.depends_on :parent_a, :parent_b
  o.setter do |value|
    "#{value}, child of #{get_option(:parent_a)} and #{get_option(:parent_b)}"
  end
end
```

**helper**

Describes helper function to be added to the settings object.

```ruby
# Block syntax
option :my_option do |o|
  o.helper :my_option_enabled? do
    !get_option(:my_option).nil?
  end
end

# Example behavior
settings.my_option # => nil
settings.my_option_enabled? # => false
settings.my_option = true
settings.my_option_enabled? # => true
```

It can be used to override the default get/set helper methods on the settings object:

```ruby
# Block syntax
option :my_option do |o|
  o.helper :my_option do |&block|
    block_given? ? yield : get_option(:my_option)
  end
end

# Example behavior
settings.my_option = 'default'
settings.my_option # => 'default'
settings.my_option { 'block' } # => 'block'
```

**lazy**

Changes evaluation of default value from eager to access time.

```ruby
# NOTE: This $value would be eagerly evaluated as the default
#       if not placed inside a block and given :lazy.
$value = :a

# Hash syntax
option :my_option, default: -> { $value }, lazy: true

# Block syntax
option :my_option do |o|
  o.default { $value }
  o.lazy
end

# Example behavior
$value = :b
settings.my_option # => :b
```

**on_set**

Defines a callback that is each time after the value is set (except on reset.)

```ruby
# Hash syntax
option :my_option, on_set: -> { |value| puts "Set #{value}!" }

# Block syntax
option :my_option do |o|
  o.on_set { |value| puts "Set #{value}!" }
end

# Example behavior
settings.my_option = 'my-value'
# Set my-value!
# => 'my-value'
```

**resetter**

Defines how the value is reset. Return value is set as the option's value. By default it is reset to `nil`.

```ruby
# Hash syntax
option :my_option, resetter: -> { |value| value.clear }

# Block syntax
option :my_option do |o|
  o.resetter { |value| value.clear }
end

# Example behavior
settings.my_option = [:a]
settings.my_option.object_id # => 46931674974120
settings.reset!
settings.my_option # => []
settings.my_option.object_id # => 46931674974120
```

**setter**

Defines how the value is set. Return value is set as the option's value. Useful for sanitizing, normalizing, or validating input. By default it is the value given.

```ruby
# Hash syntax
option :my_option, setter: -> { |value| value + 1 }

# Block syntax
option :my_option do |o|
  o.setter { |value| value + 1 }
end

# Example behavior
settings.my_option = 1
settings.my_option # => 2
```

**Defining settings subgroups**

Subgroups can be used to group options together. Useful for compartmentalizing configuration options together, and presenting a cleaner interface.

Subgroups can be defined using `#settings`:

```
settings GROUP_NAME &BLOCK
```

 - `GROUP_NAME`: A `Symbol` name for the subgroup
 - `BLOCK`: A `Proc` that can be evaluated as a settings class.

```ruby
settings :debug do
  option :level, default: Logger::INFO

  settings :stdout do
    option :enabled, default: false
  end

  settings :log do
    option :enabled, default: false
    option :filepath, default: 'logs/trace.log'
  end
end

# Example behavior
settings.debug.level # => Logger::INFO
settings.debug.stdout.enabled # => false
settings.debug.log.enabled # => false
settings.debug.log.filepath # => 'logs/trace.log'
```

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
  c.tracer transport_options: proc { |t|
    # By name
    t.adapter :custom

    # By instance
    custom_adapter = CustomAdapter.new
    t.adapter custom_adapter
  }
end
```

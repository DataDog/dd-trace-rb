# Getting started

Setting up tracing for your Ruby application takes only two steps:

1. Setup the Datadog agent
2. Configure your Ruby application

## Setup the Datadog Agent

Before adding the tracing library to your application, you will need to install the Datadog Agent, which receives trace data and forwards it to Datadog.

Check out our instructions for how to [install and configure the Datadog Agent](https://docs.datadoghq.com/tracing/setup). You can also see additional documentation for [tracing Docker applications](https://docs.datadoghq.com/tracing/setup/docker).

## Quickstart for Rails applications

1. Add the `ddtrace` gem to your Gemfile:

    ```ruby
    source 'https://rubygems.org'
    gem 'ddtrace'
    ```

2. Install the gem with `bundle install`
3. Create a `config/initializers/datadog.rb` file containing:

    ```ruby
    Datadog.configure do |c|
      # This will activate auto-instrumentation for Rails
      c.use :rails
    end
    ```

    Within this configuration block, you can also activate additional integrations here; (see [Integration instrumentation](#integration-instrumentation) for more information.)

## Quickstart for Ruby applications

1. Install the gem with `gem install ddtrace`
2. Add a configuration block to your Ruby application:

    ```ruby
    require 'ddtrace'
    Datadog.configure do |c|
      # Configure the tracer here.
      # Activate integrations, change tracer settings, etc...
      # By default without additional configuration, nothing will be traced.
    end
    ```

3. Add or activate instrumentation by doing either of the following:
    - Activate integration instrumentation (see [Integration instrumentation](#integration-instrumentation))
    - Add manual instrumentation around your code (see [Manual instrumentation](#manual-instrumentation))

## Quickstart for OpenTracing

1. Install the gem with `gem install ddtrace`
2. To your OpenTracing configuration file, add the following:

    ```ruby
    require 'opentracing'
    require 'ddtrace'
    require 'ddtrace/opentracer'

    # Activate the Datadog tracer for OpenTracing
    OpenTracing.global_tracer = Datadog::OpenTracer::Tracer.new
    ```

3. (Optional) Add a configuration block to your Ruby application to configure Datadog with:

    ```ruby
    Datadog.configure do |c|
      # Configure the Datadog tracer here.
      # Activate integrations, change tracer settings, etc...
      # By default without additional configuration,
      # no additional integrations will be traced, only
      # what you have instrumented with OpenTracing.
    end
    ```

    *NOTE*: Ensure `Datadog.configure` runs only after `OpenTracing.global_tracer` has been configured, to preserve any configuration settings you may set.

4. (Optional) Add or activate additional instrumentation by doing either of the following:
    - Activate Datadog integration instrumentation (see [Integration instrumentation](#integration-instrumentation))
    - Add Datadog manual instrumentation around your code (see [Manual instrumentation](#manual-instrumentation))

## Final steps for installation

After setting up, your services will appear on the [APM services page](https://app.datadoghq.com/apm/services) within a few minutes. Learn more about [using the APM UI](https://docs.datadoghq.com/tracing/visualization/).

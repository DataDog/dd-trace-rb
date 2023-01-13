**Supported tracing frameworks**:

| Type          | Documentation                                        | Datadog version | Gem version support |
| ------------- | ---------------------------------------------------- | --------------- | ------------------- |
| OpenTelemetry | https://github.com/open-telemetry/opentelemetry-ruby | 1.9.0+          | >= 1.1.0            |

#### Configuring OpenTelemetry

1. Add the `ddtrace` gem to your Gemfile:

    ```ruby
    source 'https://rubygems.org'
    gem 'ddtrace'
    ```

1. Install the gem with `bundle install`
1. To your OpenTelemetry configuration file, add the following:

    ```ruby
    require 'opentelemetry'
    require 'datadog/opentelemetry'
    ```

1. Add a configuration block to your application:

    ```ruby
    Datadog.configure do |c|
      # Configure the Datadog tracer here.
      # Activate integrations, change tracer settings, etc...
      # By default without additional configuration,
      # no additional integrations will be traced, only
      # what you have instrumented with OpenTelemetry.
    end
    ```

   Using this block you can:

    - [Add additional Datadog configuration settings](#additional-configuration)
    - [Activate or reconfigure Datadog instrumentation](#integration-instrumentation)

1. OpenTelemetry spans and Datadog APM spans will now be combined into a single trace your application.

   [Integration instrumentations](#integration-instrumentation) and OpenTelemetry [Automatic instrumentations](https://opentelemetry.io/docs/instrumentation/ruby/automatic/) are also supported.

##### Limitations

There are a few limitations to OpenTelemetry Tracing when the APM integration is activated:

make it table

1. [Context Propagation](https://opentelemetry.io/docs/instrumentation/ruby/manual/#context-propagation) configuration is not supported. The Ruby Tracer [Distributed header format](#distributed-header-formats) configuration is used instead.
1. [Span processors](https://opentelemetry.io/docs/reference/specification/trace/sdk/#span-processor) and [Span Exporters](https://opentelemetry.io/docs/reference/specification/trace/sdk/#span-exporter) are not supported.
1. The `OpenTelemetry.logger` is set to the same object as `Datadog.logger`, and can be configured through [Custom logging](#custom-logging).
1. Trace and Span [Id Generators](https://opentelemetry.io/docs/reference/specification/trace/sdk/#id-generators) are handled by the Ruby Tracer.

##### Exporting OpenTelemetry-only traces

You can send OpenTelemetry traces directly to the Datadog agent (without `ddtrace`) by using [OTLP](https://open-telemetry.github.io/opentelemetry-ruby/opentelemetry-exporter-otlp/latest).
Check out our documentation on [OTLP ingest in the Datadog Agent](https://docs.datadoghq.com/tracing/setup_overview/open_standards/#otlp-ingest-in-datadog-agent) for details.

Datadog APM spans will not be sent through the OTLP exporter.

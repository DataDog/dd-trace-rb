# OpenTelemetry

**Supported OpenTelemetry features**:

| Type          | Documentation                                        | datadog version | Gem version support |
| ------------- | ---------------------------------------------------- | --------------- | ------------------- |
| Tracing       | https://github.com/open-telemetry/opentelemetry-ruby | 1.9.0+          | >= 1.1.0            |
| Metrics SDK   | https://rubygems.org/gems/opentelemetry-metrics-sdk  | 2.23.0+         |  >= 0.8             |
| OTLP Metrics Exporter | https://rubygems.org/gems/opentelemetry-exporter-otlp-metrics  | 2.23.0+         |  >= 0.4            |

## Configuring OpenTelemetry Tracing

1. Add the `datadog` gem to your Gemfile:

    ```ruby
    source 'https://rubygems.org'
    gem 'datadog'
    ```

1. Install the gem with `bundle install`
1. To your OpenTelemetry configuration file, add the following:

    ```ruby
    require 'opentelemetry/sdk'
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

## Configuring OpenTelemetry Metrics

1. Add the required gems to your Gemfile:

    ```ruby
    gem 'datadog'
    gem 'opentelemetry-metrics-sdk', '~> 0.8'
    gem 'opentelemetry-exporter-otlp-metrics', '~> 0.4'
    ```

1. Install gems with `bundle install`

1. Enable metrics export:

    ```ruby
    # Set environment variable before initializing metrics support
    ENV['DD_METRICS_OTEL_ENABLED'] = 'true'
    require 'opentelemetry/sdk'
    require 'datadog/opentelemetry'

    Datadog.configure do |c|
      # Configure Datadog settings here
    end

    # Call after Datadog.configure to initialize metrics.
    # Can be called multiple times to pick up configuration changes.
    # Requires: opentelemetry/exporter/otlp_metrics and opentelemetry/exporter/otlp_metrics
    OpenTelemetry::SDK.configure
    ```

1. Use the [OpenTelemetry Metrics API](https://opentelemetry.io/docs/languages/ruby/instrumentation/#metrics) to create and record metrics.

**Note:** Call `OpenTelemetry::SDK.configure` after `Datadog.configure` and call it again whenever Datadog configuration changes to update the meter provider.

**Configuration Options:**

- `DD_METRICS_OTEL_ENABLED` - Enable metrics export (default: false)
- `OTEL_EXPORTER_OTLP_METRICS_PROTOCOL` - Protocol: `http/protobuf` (default); `grpc` and `http/json` are not yet supported.
- `OTEL_EXPORTER_OTLP_METRICS_ENDPOINT` - Custom endpoint (defaults to the Datadog agent otlp endpoint)
- `OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE` - `delta` (default) or `cumulative`
- `OTEL_METRIC_EXPORT_INTERVAL` - Export interval in milliseconds (default: 10000)

[General OTLP settings](https://opentelemetry.io/docs/languages/sdk-configuration/otlp-exporter/) (`OTEL_EXPORTER_OTLP_*`) serve as defaults if metrics-specific settings are not provided.

**Note:** Minimum `opentelemetry-metrics-sdk` is v0.8.0 (contains critical bug fixes). Minimum `opentelemetry-exporter-otlp-metrics` is v0.4.0. Use the latest versions for best support. If you spot any issue with the OpenTelemetry API affecting the `datadog` gem, [please do open a GitHub issue](https://github.com/DataDog/dd-trace-rb/issues).

## Configuring OpenTelemetry Logs

**Configuration Options:**

- `DD_LOGS_OTEL_ENABLED` - Enable logs export (default: false)
- `OTEL_EXPORTER_OTLP_LOGS_PROTOCOL` - Protocol: `http/protobuf` (default); `grpc` and `http/json` are not yet supported.
- `OTEL_EXPORTER_OTLP_LOGS_ENDPOINT` - Custom endpoint (defaults to the Datadog agent otlp endpoint)

> [!WARNING]
> When OpenTelemetry logs export is enabled, Datadog log injection is disabled to avoid duplicate trace correlation fields.

## Exporting Traces via OTLP

Set `OTEL_TRACES_EXPORTER=otlp` to export finished traces over OTLP (`http/json`) to an OpenTelemetry-compatible endpoint instead of the Datadog agent trace endpoint. Agent interaction (`/info`, Remote Configuration, and telemetry) is unaffected — only the trace transport changes.

**Configuration Options:**

- `OTEL_TRACES_EXPORTER` - Set to `otlp` to enable OTLP trace export. (`none` disables tracing.)
- `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` - Full traces endpoint URL, used as-is.
- `OTEL_EXPORTER_OTLP_ENDPOINT` - Fallback endpoint; `/v1/traces` is appended. Defaults to `http://<DD_AGENT_HOST or localhost>:4318/v1/traces`.
- `OTEL_EXPORTER_OTLP_TRACES_HEADERS` - Comma-separated `key=value` headers sent with each request (fallback: `OTEL_EXPORTER_OTLP_HEADERS`).
- `OTEL_EXPORTER_OTLP_TRACES_TIMEOUT` - Request timeout in milliseconds (fallback: `OTEL_EXPORTER_OTLP_TIMEOUT`, default 10000).
- `OTEL_EXPORTER_OTLP_TRACES_PROTOCOL` - Only `http/json` is honored (fallback: `OTEL_EXPORTER_OTLP_PROTOCOL`).

The trace sampling rate is controlled by the usual Datadog settings (`DD_TRACE_SAMPLE_RATE`, `DD_TRACE_SAMPLING_RULES`) and the `OTEL_TRACES_SAMPLER`/`OTEL_TRACES_SAMPLER_ARG` mapping. Only sampled traces are exported.

> [!NOTE]
> Setting `DD_TRACE_AGENT_PROTOCOL_VERSION` forces the Datadog agent trace transport and disables OTLP trace export.

## Limitations

There are a few limitations to OpenTelemetry Tracing when the APM integration is activated:

| Feature                                                                                                    | Support?    | Explanation                                                                       | Recommendation                                       |   |
|------------------------------------------------------------------------------------------------------------|-------------|-----------------------------------------------------------------------------------|------------------------------------------------------|---|
| [Context propagation](https://opentelemetry.io/docs/instrumentation/ruby/manual/#context-propagation)      | Unsupported | Datadog [distributed header format](#distributed-header-formats) is used instead. | N/A                                                  |   |
| [Span processors](https://opentelemetry.io/docs/reference/specification/trace/sdk/#span-processor)         | Unsupported |                                                                                   | N/A                                                  |   |
| [Span Exporters](https://opentelemetry.io/docs/reference/specification/trace/sdk/#span-exporter)           | Unsupported |                                                                                   | N/A                                                  |   |
| `OpenTelemetry.logger`                                                                                     | Special     | `OpenTelemetry.logger` is set to the same object as `Datadog.logger`.             | Configure through [Custom logging](#custom-logging). |   |
| Trace/span [ID generators](https://opentelemetry.io/docs/reference/specification/trace/sdk/#id-generators) | Special     | ID generation is performed by `datadog`.                                          | N/A                                                  |   |

## Exporting OpenTelemetry-only traces

You can send OpenTelemetry traces directly to the Datadog agent (without `datadog`) by using [OTLP](https://open-telemetry.github.io/opentelemetry-ruby/opentelemetry-exporter-otlp/latest).
Check out our documentation on [OTLP ingest in the Datadog Agent](https://docs.datadoghq.com/tracing/setup_overview/open_standards/#otlp-ingest-in-datadog-agent) for details.

Datadog APM spans will not be sent through the OTLP exporter.

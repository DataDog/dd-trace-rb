# Upgrading ddtrace from 1.x to 2.0

Upgrading `ddtrace` from 1.x to 2.0 introduces some breaking changes which are outlined below.

[**Basic Usage**](#2.0-basic-usage)

In most cases, (e.g. when you use out-of-the-box instrumentation and a configuration file) only minor changes to your current setup are needed: most applications take just minutes to update.

- [Requires Ruby 2.5+](#2.0-requires-ruby-2.5+)
- [Extracts datadog-ci gem](#2.0-extracts-ci)
- [Configuration changes](#2.0-configuration-changes)
  - [Replace `use` with `instrument`](#2.0-use-instrument)
  - [Type checking](#2.0-type-checking)
  - [Propagation default](#2.0-propagation-default)
  - [Options](#2.0-options)

---

[**Advanced Usage**](#2.0-advanced-usage)

If you have custom instrumentation, sampling or processing behavior, additional changes may be required. See the following sections for details about what features changed and how to use them.

- [Frozen String Literal](#2.0-frozen-string)
- [Tracing API](#2.0-tracing-api)
- [Configuration API](#2.0-configuration-api)
- [Log Correlation](#2.0-log-correlation)
- [Distributed Tracing](#2.0-distributed-tracing)
- [Transport](#2.0-transport)
- [Sampling](#2.0-sampling)

---

[**Upgrade Instrumentations**](#2.0-upgrade-instrumentations)

Outlines the changes for our instrumentations.

- [Error Handling](#2.0-error-handling)
- [Option `error_status_codes`](#2.0-error-status-codes)
- [List of Integration changes](#2.0-list-of-integration-changes)

<h2 id="2.0-basic-usage">Basic Usage</h2>

<h3 id="2.0-requires-ruby-2.5+">Requires Ruby 2.5+</h3>

The minimum Ruby version requirement for ddtrace 2.x is 2.5.0. For prior Ruby versions, you can use ddtrace 1.x. see more with our support policy.

<h3 id="2.0-extracts-ci">Extracts datadog-ci gem</h3>

The CI visibility component has been extracted as a separate gem named [datadog-ci](https://github.com/DataDog/datadog-ci-rb), and will no longer be installed together with ddtrace.

If you are using our CI visibility product, include `datadog-ci` in your Gemfile and learn more about the [setup](https://github.com/DataDog/datadog-ci-rb).

```ruby
gem 'ddtrace', '>= 2'

group :test do
  gem 'datadog-ci'
end
```

If you do not want to install `datadog-ci`, make sure to remove CI-related configuration( `Datadog.configure { |c| c.ci.* }`)

<h3 id="2.0-configuration-changes">Configuration changes</h3>

<h4 id="2.0-use-instrument">Replace `use` with `instrument`</h4>

```ruby
# === with 1.x ===
Datadog.configure do |c|
  c.tracing.use :mysql2
end

# === with 2.0 ===
Datadog.configure do |c|
  c.tracing.instrument :mysql2
end
```

<h4 id="2.0-type-checking">Enforce type checking</h4>

Configuration options are type checked. When validation fails, an `ArgumentError` is raised.

For example `c.env` and `c.service` now have to be `String`.

```ruby
# === with 1.x ===
Datadog.configure do |c|
  c.env = :production
end

# === with 2.0 ===
Datadog.configure do |c|
  c.env = 'production'
end
```

Note that skipping validation with `ENV['DD_EXPERIMENTAL_SKIP_CONFIGURATION_VALIDATION']` has also been removed.

<h4 id="2.0-propagation-default">Propagation default</h4>

B3 propagation has been removed from the default propagation for distributed tracing. If you want to configure B3 propagation, see [document](GettingStarted.md#distributed-header-formats).

| 1.x                               | 2.0                    |
| --------------------------------- | ---------------------- |
| `datadog,b3multi,b3,tracecontext` | `datadog,tracecontext` |

<h4 id="2.0-options">Options</h4>

- Option `c.tracing.client_ip.enabled`: `ENV['DD_TRACE_CLIENT_IP_HEADER_DISABLED']` is removed. Use `ENV['DD_TRACE_CLIENT_IP_ENABLED']` instead.

- The following programmatic configuration options have been changed. Their corresponding environment variables (if any) are unchanged:

  | 1.x                                                      | 2.0                                   |
  | -------------------------------------------------------- | ------------------------------------- |
  | `tracing.distributed_tracing.propagation_extract_first`  | `tracing.propagation_extract_first`   |
  | `tracing.distributed_tracing.propagation_extract_style`  | `tracing.propagation_style_extract`   |
  | `tracing.distributed_tracing.propagation_inject_style`   | `tracing.propagation_style_inject`    |
  | `tracing.distributed_tracing.propagation_style`          | `tracing.propagation_style`           |
  | `diagnostics.health_metrics.enabled`                     | `health_metrics.enabled`              |
  | `diagnostics.health_metrics.statsd`                      | `health_metrics.statsd`               |
  | `profiling.advanced.max_events`                          | Removed                               |
  | `profiling.advanced.legacy_transport_enabled`            | Removed                               |
  | `profiling.advanced.force_enable_new_profiler`           | Removed                               |
  | `profiling.advanced.force_enable_legacy_profiler`        | Removed                               |
  | `profiling.advanced.allocation_counting_enabled`         | Removed                               |
  | `profiling.advanced.experimental_allocation_sample_rate` | Removed                               |
  | `profiling.advanced.experimental_timeline_enabled`       | `profiling.advanced.timeline_enabled` |

<h2 id="2.0-advanced-usage">Advanced Usage</h2>

<h3 id="2.0-frozen-string">Frozen String Literal</h3>

All strings are frozen by default. Make sure your code does not mutate them.

<h3 id="2.0-configuration-api">Configuration API</h3>

If you are [writing your own instrumentation](DevelopmentGuide.md#writing-new-integrations),
configuration options are now lazily evaluated by default. The `.lazy` option needs to be removed from all option configurations.

```ruby
class MySettings < Datadog::Tracing::Contrib::Configuration::Settings
  option :boom do |o|
    o.default do
      true
    end
    o.lazy # === Remove this with 2.0 ===
  end
end
```

<h3 id="2.0-tracing-api">Tracing API</h3>

Remove the option `span_type` from the `Datadog::Tracing.trace` method. Additionally, the following alias methods have been removed:

| 1.x                                            | Replacement in 2.0                        |
| ---------------------------------------------- | ----------------------------------------- |
| `Datadog::Tracing.trace(name, span_type: ...)` | `Datadog::Tracing.trace(name, type: ...)` |
| `Datadog::Tracing::SpanOperation#span_id`      | `Datadog::Tracing::SpanOperation#id`      |
| `Datadog::Tracing::SpanOperation#span_type`    | `Datadog::Tracing::SpanOperation#type`    |
| `Datadog::Tracing::SpanOperation#span_type=`   | `Datadog::Tracing::SpanOperation#type=`   |
| `Datadog::Tracing::Span#span_id`               | `Datadog::Tracing::Span#id`               |
| `Datadog::Tracing::Span#span_type`             | `Datadog::Tracing::Span#type`             |
| `Datadog::Tracing::Span#span_type=`            | `Datadog::Tracing::Span#type=`            |

If you are using [manual instrumentation](GettingStarted.md#manual-instrumentation) or [processing pipeline](GettingStarted.md#processing-pipeline)

```ruby
# === with 1.x ===
Datadog::Tracing.trace('my_span', span_type: 'custom') do |span|
  puts span.span_id

  span.span_type = "...."
end

# === with 2.0 ===
Datadog::Tracing.trace('my_span', type: 'custom') do |span|
  puts span.id

  span.type = "...."
end
```

<h3 id="2.0-log-correlation">Log Correlation</h3>

The following fields have been from `Datadog::Tracing::Correlation::Identifier`, and it no longer responds to them

- `Datadog::Tracing::Correlation::Identifier#span_name`
- `Datadog::Tracing::Correlation::Identifier#span_resource`
- `Datadog::Tracing::Correlation::Identifier#span_service`
- `Datadog::Tracing::Correlation::Identifier#span_type`
- `Datadog::Tracing::Correlation::Identifier#trace_name`
- `Datadog::Tracing::Correlation::Identifier#trace_resource`
- `Datadog::Tracing::Correlation::Identifier#trace_service`

The values returned from `Datadog::Tracing::Correlation::Identifier#trace_id` and `Datadog::Tracing::Correlation::Identifier#span_id` change from `Integer` to `String`. If you are [manually correlating logs](GettingStarted.md#trace-correlation), check if it is still compatible.

```ruby
# === with 1.x ===
Datadog::Tracing.correlation.span_id
# => 50288418819650436

# === with 2.0 ===
Datadog::Tracing.correlation.span_id
# => '50288418819650436'
```

<h3 id="2.0-distributed-tracing">Distributed Tracing</h3>

<h4 id="2.0-distributed-tracing-api">Propagation API changes</h4>

If you are [manually propagating distributed tracing metadata](GettingStarted.md#using-the-http-propagator) `Datadog::Tracing::Propagation::HTTP` has moved to `Datadog::Tracing::Contrib::HTTP`.

```ruby
# === with 1.x ===
Datadog::Tracing::Propagation::HTTP.inject!
Datadog::Tracing::Propagation::HTTP.extract

# === with 2.0 ===
Datadog::Tracing::Contrib::HTTP.inject
Datadog::Tracing::Contrib::HTTP.extract
```

<h4 id="2.0-distributed-tracing-env">Environment variable changes</h4>

| 1.x                            | 2.0                                  |
| ------------------------------ | ------------------------------------ |
| `DD_PROPAGATION_STYLE_INJECT`  | `DD_TRACE_PROPAGATION_STYLE_INJECT`  |
| `DD_PROPAGATION_STYLE_EXTRACT` | `DD_TRACE_PROPAGATION_STYLE_EXTRACT` |

The values from the environment variables `DD_TRACE_PROPAGATION_STYLE`, `DD_TRACE_PROPAGATION_STYLE_INJECT`, and `DD_TRACE_PROPAGATION_STYLE_EXTRACT` are now considered case-insensitive. Hence, the values mapped to different b3 strategies (single header vs. multiple headers) also changed.

| Constant                                                                                | Value     | Strategy         |
| --------------------------------------------------------------------------------------- | --------- | ---------------- |
| `Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER` | `b3`      | single header    |
| `Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_MULTI_HEADER`  | `b3multi` | multiple headers |

<h4>Constant changes</h4>

Remove constants at `Datadog::Tracing::Distributed::Headers::Ext`. see table below:

| 1.x                                                                            | 2.0                                                             |
| ------------------------------------------------------------------------------ | --------------------------------------------------------------- |
| `Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TRACE_ID`            | `Datadog::Tracing::Distributed::Datadog::TRACE_ID_KEY`          |
| `Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_PARENT_ID`           | `Datadog::Tracing::Distributed::Datadog::PARENT_ID_KEY`         |
| `Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_SAMPLING_PRIORITY`   | `Datadog::Tracing::Distributed::Datadog::SAMPLING_PRIORITY_KEY` |
| `Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_ORIGIN`              | `Datadog::Tracing::Distributed::Datadog::ORIGIN_KEY`            |
| `Datadog::Tracing::Distributed::Headers::Ext::HTTP_HEADER_TAGS`                | `Datadog::Tracing::Distributed::Datadog::TAGS_KEY`              |
| `Datadog::Tracing::Distributed::Headers::Ext::B3_HEADER_TRACE_ID`              | `Datadog::Tracing::Distirbuted::B3Multi::B3_TRACE_ID_KEY`       |
| `Datadog::Tracing::Distributed::Headers::Ext::B3_HEADER_SPAN_ID`               | `Datadog::Tracing::Distirbuted::B3Multi::B3_SPAN_ID_KEY`        |
| `Datadog::Tracing::Distributed::Headers::Ext::B3_HEADER_SAMPLED`               | `Datadog::Tracing::Distirbuted::B3Multi::B3_SAMPLED_KEY`        |
| `Datadog::Tracing::Distributed::Headers::Ext::B3_HEADER_SINGLE`                | `Datadog::Tracing::Distirbuted::B3Single::B3_SINGLE_HEADER_KEY` |
| `Datadog::Tracing::Distributed::Headers::Ext::GRPC_METADATA_TRACE_ID`          | `Datadog::Tracing::Distributed::Datadog::TRACE_ID_KEY`          |
| `Datadog::Tracing::Distributed::Headers::Ext::GRPC_METADATA_PARENT_ID`         | `Datadog::Tracing::Distributed::Datadog::PARENT_ID_KEY`         |
| `Datadog::Tracing::Distributed::Headers::Ext::GRPC_METADATA_SAMPLING_PRIORITY` | `Datadog::Tracing::Distributed::Datadog::SAMPLING_PRIORITY_KEY` |
| `Datadog::Tracing::Distributed::Headers::Ext::GRPC_METADATA_ORIGIN`            | `Datadog::Tracing::Distributed::Datadog::ORIGIN_KEY`            |

<h3 id="2.0-transport">Transport</h3>

The `c.tracing.transport_options` option has been removed and cannot be configured with a custom transport adapter. The following options have been added to replace options previously only available via `transport_options`:

- `c.agent.timeout_seconds` or `DD_TRACE_AGENT_TIMEOUT_SECONDS`
- `c.agent.uds_path`
- `c.agent.use_ssl`

see [configure transport layer](GettingStarted.md#configuring-the-transport-layer).

See table below for constant and method changes:

| 1.x                                                              | 2.0                                                     |
| ---------------------------------------------------------------- | ------------------------------------------------------- |
| `Datadog::Transport::Ext::HTTP`                                  | `Datadog::Core::Transport::Ext::HTTP`                   |
| `Datadog::Transport::Ext::Test`                                  | `Datadog::Core::Transport::Ext::Test`                   |
| `Datadog::Transport::Ext::UnixSocket`                            | `Datadog::Core::Transport::Ext::UnixSocket`             |
| `Datadog::Core::Configuration::Ext::Transport::ENV_DEFAULT_HOST` | `Datadog::Core::Configuration::Agent::ENV_DEFAULT_HOST` |
| `Datadog::Tracing::Transport::HTTP#default_hostname`             | Removed                                                 |
| `Datadog::Tracing::Transport::HTTP#default_port`                 | Removed                                                 |
| `Datadog::Tracing::Transport::HTTP#default_url`                  | Removed                                                 |
| `Datadog::Core::Remote::Transport::HTTP#default_hostname`        | Removed                                                 |
| `Datadog::Core::Remote::Transport::HTTP#default_port`            | Removed                                                 |
| `Datadog::Core::Remote::Transport::HTTP#default_url`             | Removed                                                 |

<h3 id="2.0-sampling">Sampling</h3>

Custom sampling classes have been removed in 2.0.

Sampling should be configured using a combination of [Ingestion Controls](https://docs.datadoghq.com/tracing/trace_pipeline/ingestion_controls/) and [user-defined rules](https://docs.datadoghq.com/tracing/trace_pipeline/ingestion_mechanisms/?tab=ruby&code-lang=ruby#in-tracing-libraries-user-defined-rules),
as such configurations are more maintainable and auditable than custom application sampling objects.

If you still need a custom sampler, see [Custom Sampling](GettingStarted.md#custom-sampling) for the new detailed requirements of a custom sampler object.

#### Sampling objects removed

| 1.x                                                | 2.0     |
| -------------------------------------------------- | ------- |
| `Datadog::Tracing::Sampling::AllSampler`           | Removed |
| `Datadog::Tracing::Sampling::Matcher`              | Removed |
| `Datadog::Tracing::Sampling::SimpleMatcher`        | Removed |
| `Datadog::Tracing::Sampling::ProcMatcher`          | Removed |
| `Datadog::Tracing::Sampling::PrioritySampler`      | Removed |
| `Datadog::Tracing::Sampling::RateByKeySampler`     | Removed |
| `Datadog::Tracing::Sampling::RateByServiceSampler` | Removed |
| `Datadog::Tracing::Sampling::RateLimiter`          | Removed |
| `Datadog::Tracing::Sampling::TokenBucket`          | Removed |
| `Datadog::Tracing::Sampling::UnlimitedLimiter`     | Removed |
| `Datadog::Tracing::Sampling::RateSampler`          | Removed |
| `Datadog::Tracing::Sampling::Rule`                 | Removed |
| `Datadog::Tracing::Sampling::SimpleRule`           | Removed |
| `Datadog::Tracing::Sampling::RuleSampler`          | Removed |
| `Datadog::Tracing::Sampling::Sampler`              | Removed |

#### Other sampling changes

The configuration option `c.tracing.priority_sampling` has been removed.
Disabling priority sampling affects the auditability of simply decisions.

To disable priority sampling in 2.0, you now have to create a custom sampler.

<h2 id="2.0-upgrade-instrumentations">Upgrade Instrumentations</h2>

<h3 id='2.0-error-handling'>Error Handling</h3>

The `error_handler` options have been replaced by `on_error` to align with `options` for our public API `Datadog::Tracing.trace(name, options)`.

For the majority of integrations, rename the `error_handler` option to `on_error` in your configuration. See details for [`active_job`](#activejob), [`grpc`](#grpc), [`faraday`](#faraday) and [`excon`](#excon), which have unique implementation changes.

<h3 id='2.0-error-status-codes'>Option `error_status_codes`</h3>

Option `error_status_codes` has been introduced to various http integrations. It tags the span with an error based on http status from a response header. Its value can be a range (`400...600`), or an array of ranges/integers `[403, 500...600]`. If configured with environment variable, use a dash for an end-excluded range (`'400-599'`) and a comma for adding element into an array (`'403,500-599'`)

```ruby
Datadog.configure do |c|
  c.tracing.instrument :http, error_status_codes: [403, 500...600]
  # equivalent to ENV['DD_TRACE_HTTP_ERROR_STATUS_CODES'] = '403,500-599'
end
```

<h3 id='2.0-list-of-integration-changes'>List of Integration Changes</h3>

#### ActionPack

- Removed: `exception_controller` option.

#### ActiveJob

- Removed: `error_handler` option.

#### DelayedJob

- Rename `error_handler` option to `on_error`. See [Error Handling](#2.0-error-handling)

#### Elasticsearch

- Only ElasticSearch "transport" can be configured.

  ```ruby
  # === with 1.x ===
  Datadog.configure_onto(client, **options)
  Datadog.configure_onto(client.transport, **options)

  # === with 2.0 ===
  Datadog.configure_onto(client.transport, **options)
  ```

#### Excon

- Removed: `error_handler` option. Use `error_status_codes` option to tag span with an error based on http status from response header, the default is `400...600` (Only server errors are tagged in 1.x). Additionally, configure `on_error` option to control behavior when an exception (ie. `Excon::Error::Timeout`) is raised.

  ```ruby
  # === with 1.x ===
  Datadog.configure do |c|
    c.tracing.instrument :excon, error_handler: lambda do |response|
      (400...600).cover?(response[:status])
    end
  end

  # === with 2.0 ===
  Datadog.configure do |c|
    c.tracing.instrument :excon, error_status_codes: 400...600
  end
  ```

#### Faraday

- Removed: `error_handler` option. Use `error_status_codes` option to tag span with an error based on http status from response header, the default is `400...600` (Only server errors are tagged in 1.x). Additionally, configure `on_error` option to control behavior when an exception (ie.`Faraday::ConnectionFailed`) is raised.

  ```ruby
  # === with 1.x ===
  Datadog.configure do |c|
    c.tracing.instrument :faraday, error_handler: lambda do |env|
      (400...600).cover?(env[:status])
    end
  end

  # === with 2.0 ===
  Datadog.configure do |c|
    c.tracing.instrument :faraday, error_status_codes: 400...600
  end
  ```

#### Grape

- Removed: `error_statuses` option. Use `error_status_codes` instead.

  ```ruby
  # === with 1.x ===
  Datadog.configure do |c|
    c.tracing.instrument :grape, error_statuses: '400,500-599'
  end

  # === with 2.0 ===
  Datadog.configure do |c|
    c.tracing.instrument :grape, error_status_codes: [400, 500..599]
  end
  ```

#### GraphQL

- Support changes:

  - Supports `graphql` versions `>= 2.2.6`, and the below backported versions:

    | Branch   | Version             |
    | -------- | ------------------- |
    | `2.1.x`  | `>= 2.1.11, < 2.2`  |
    | `2.0.x`  | `>= 2.0.28, < 2.1`  |
    | `1.13.x` | `>= 1.13.21, < 2.0` |

  - Does **NOT** support or patch defined-based schema.

- Option `schemas` becomes optional. Providing GraphQL schemas is not required. By default, every schema is instrumented.

- Instrument with `GraphQL::Tracing::DataDogTrace`. Set `with_deprecated_tracer` option to `true` to rollback instrumentation with deprecated `GraphQL::Tracing::DataDogTracing`.

#### GRPC

- `error_handler`, `server_error_handler` and `client_error_handler` options are removed. Replace them with option `on_error`, which is invoked on both server and client side instrumentation. Merge your implementation for `server_error_handler` and `client_error_handler` to `on_error`. The implementation for `on_error` should distinguish between the server and client.

  ```ruby
  Datadog.configure do |c|
    c.tracing.instrument :grpc, on_error: proc do |span, error|
      if span.name == 'grpc.service'
        # Do something for server instrumentation
      end

      if span.name == 'grpc.client'
        # Do something for client instrumentation
      end
    end
  end
  ```

#### Net/Http

- `Datadog::Tracing::Contrib::HTTP::Instrumentation.after_request` has been removed.

#### OpenTracing

- Removed entirely.

#### PG

- Rename `error_handler` option to `on_error`. See [Error Handling](#2.0-error-handling)

#### Qless

- Removed entirely.

#### Que

- Rename `error_handler` option to `on_error`. See [Error Handling](#2.0-error-handling)

<h4 id='2.0-instrumentation-rack'>Rack</h4>

- The type for `request_queuing` option is `Boolean`, the value can no longer be `Symbol`. When enabled, the 1.x `:exclude_request` behavior becomes the new default behavior(`include_request` was the default). The original `http_server.queue` span will be renamed to `http.proxy.request` and an additional `http.proxy.queue` span is created to represent the time spent in a load balancer queue before reaching application.

  ```ruby
  # === with 1.x ===
  Datadog.configure do |c|
    c.tracing.instrument :rack, request_queuing: :true
    # or
    c.tracing.instrument :rack, request_queuing: :include_request # Same as `true` in 1.x
    # or
    c.tracing.instrument :rack, request_queuing: :exclude_request # Becomes `true` in 2.x
  end

  # === with 2.0 ===
  Datadog.configure do |c|
    c.tracing.instrument :rack, request_queuing: true # :exclude_request behavior from 1.x
  end
  ```

  Changing the name of the top-level span (`http_server.queue` to `http.proxy.request`) would break functionality such as monitoring, dashboards and notebooks. The following snippet renames the top-level span back to assist with migration.

  ```ruby
  Datadog::Tracing.before_flush(
    Datadog::Tracing::Pipeline::SpanProcessor.new do |span|
      if span.name == 'http.proxy.request'
        span.name = 'http_server.queue'
      end
    end
  )
  ```

#### Rails

- Support changes: Support Rails 4+ (Drops Rails 3)

- Removed: `exception_controller` option.

- See [Rack](#2.0-instrumentation-rack)

#### Resque

- Rename `error_handler` option to `on_error`. See [Error Handling](#2.0-error-handling)

#### Sinatra

- Removed following constants:
  - `Datadog::Tracing::Contrib::Sinatra::Ext::RACK_ENV_REQUEST_SPAN`
  - `Datadog::Tracing::Contrib::Sinatra::Ext::RACK_ENV_MIDDLEWARE_START_TIME`
  - `Datadog::Tracing::Contrib::Sinatra::Ext::RACK_ENV_MIDDLEWARE_TRACED`

#### Shoryuken

- Rename `error_handler` option to `on_error`. See [Error Handling](#2.0-error-handling)

#### Sidekiq

- Rename `error_handler` option to `on_error`. See [Error Handling](#2.0-error-handling)

- Removed: `tag_args` option. Use `quantize` instead.

  ```ruby
  # === with 1.x ===
  Datadog.configure do |c|
    c.tracing.instrument :sidekiq, tag_args: true
  end

  # === with 2.0 ===
  Datadog.configure do |c|
    c.tracing.instrument :sidekiq, quantize: { args: { show: :all } }
  end
  ```

* No longer support worker specific configuration from `#datadog_tracer_config` method.

#### Sneakers

- Rename `error_handler` option to `on_error`. See [Error Handling](#2.0-error-handling)

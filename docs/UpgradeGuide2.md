# Upgrading ddtrace to 2.0

## From 1.x to 2.0

Upgrading `ddtrace` from 1.x to 2.0 introduces some breaking changes which are outlined below.

**How to upgrade basic usage**

- [Requires Ruby 2.5+](#2.0-requires-ruby-2.5+)
- [Extracts datadog-ci gem](#2.0-extracts-ci)
- [Configuration changes](#2.0-configuration-changes)
  - [Replace `use` with `instrument`](#2.0-use-instrument)
  - [Type checking](#2.0-type-checking)
  - [Propagation default](#2.0-propagation-default)
  - [Namespace](#2.0-namespace)

**Additional upgrades for advanced usage**

For users with an advanced implementation of `ddtrace` (custom instrumentation, sampling or processing behavior, etc), some additional namespace and behavioral changes may be required. See the following sections for details about what features changed and how to use them.

- [Frozen String](#2.0-frozen-string)
- [Tracing API](#2.0-tracing-api)
- [Log Correlation](#2.0-log-correlation)
- [Distributed Tracing](#2.0-distributed-tracing)
- [Transport](#2.0-transport)
- [Sampling](#2.0-sampling)


**Instrumentations**

- [Instrumentation Changes](#2.0-instrumentation)
  - [Error Handling with `error_handler`](#2.0-error-handling)
  - [Setting `error_status_codes` option with ENV](#2.0-error-status-codes)

<h3 id="2.0-requires-ruby-2.5+">Requires Ruby 2.5+</h3>

The minimum Ruby version requirement for ddtrace 2.x is 2.5.0. For prior Ruby versions, you can use ddtrace 1.x. see more with our support policy.

<!-- OpenTracing is no longer supported -->

<h3 id="2.0-extracts-ci">Extracts datadog-ci gem</h3>

CI visibility component has been extracted as a separate gem named [datadog-ci](https://github.com/DataDog/datadog-ci-rb), and will no longer be installed together with ddtrace.

If you are using our CI visibility product, include `datadog-ci` in your Gemfile and learn more about the [setup](https://github.com/DataDog/datadog-ci-rb).

```ruby
gem 'ddtrace', '>= 2'
gem 'datadog-ci'
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
<!--
Configuration options of types ':int' and ':float' now have stricter type validation:
Fractional numbers are no longer considered valid for ':int' options.
Empty values (nil or empty string) are no longer considered valid for ':int' or ':float' options.
This applies to both environment variable and programmatic configuration. -->

Configuration options are type checked. When validation fails, it raises `ArgumentError` . Skipping validation with `ENV['DD_EXPERIMENTAL_SKIP_CONFIGURATION_VALIDATION']` has now been removed.

For example `c.env` and `c.service` now have to be `String`.

```ruby
# === with 1.x ===
Datadog.configure do |c|
  c.env = :production

  c.agent.port = '8160'
  c.tracing.sampling.rate_limit = 50.0
end

# === with 2.0 ===
Datadog.configure do |c|
  c.env = 'production' # Must be string

  # Must be Integer
  c.agent.port = 8160
  c.tracing.sampling.rate_limit = 50
end
```

Here's the list of all affected options:
[Insert all :int and :float options at release time!!!]

<!-- Configuration options can no longer be defined as lazy. All options are lazily evaluated, making this redundant. -->

Configuration `c.tracing.client_ip.enabled` with `ENV['DD_TRACE_CLIENT_IP_HEADER_DISABLED']` is removed, use `ENV['DD_TRACE_CLIENT_IP_ENABLED']` instead.

<h4 id="2.0-propagation-default">Propagation default</h4>

The default distributed tracing propagation extraction style is now `Datadog,tracecontext`.

<h4 id="2.0-namespace">Namespace</h4>

Programmatic configuration options have been made more consistent with their respective environment variables:

| 1.x                                                     | 2.0                                 | Environment Variable (unchanged)     |
| ------------------------------------------------------- | ----------------------------------- | ------------------------------------ |
| `tracing.distributed_tracing.propagation_extract_first` | `tracing.propagation_extract_first` | `DD_TRACE_PROPAGATION_EXTRACT_FIRST` |
| `tracing.distributed_tracing.propagation_extract_style` | `tracing.propagation_style_extract` | `DD_TRACE_PROPAGATION_STYLE_EXTRACT` |
| `tracing.distributed_tracing.propagation_inject_style`  | `tracing.propagation_style_inject`  | `DD_TRACE_PROPAGATION_STYLE_INJECT`  |
| `tracing.distributed_tracing.propagation_style`         | `tracing.propagation_style`         | `DD_TRACE_PROPAGATION_STYLE`         |
| `diagnostics.health_metrics.enabled`                    | `health_metrics.enabled`            | `DD_HEALTH_METRICS_ENABLED`          |
| `diagnostics.health_metrics.statsd`                     | `health_metrics.statsd`             | (none)                               |
| `profiling.advanced.max_events`                         | Removed                             | (none)                               |
| `profiling.advanced.legacy_transport_enabled`           | Removed                             | (none)                               |
| `profiling.advanced.force_enable_new_profiler`          | Removed                             | (none)                               |
| `profiling.advanced.force_enable_legacy_profiler`       | Removed                             | (none)                               |

<h2 id="2.0-advanced-upgrade">Upgrading advanced usage</h1>

<h3 id="2.0-frozen-string">Frozen String</h3>

All strings the strings are frozen by default. Make sure your code does not mutate them.

<h3 id="2.0-tracing-api">Tracing API</h3>

Remove option `span_type` from `Datadog::Tracing.trace` method and the following alias methods

| 1.x                                            | 2.0                                       |
| ---------------------------------------------- | ----------------------------------------- |
| `Datadog::Tracing.trace(name, span_type: ...)` | `Datadog::Tracing.trace(name, type: ...)` |
| `Datadog::Tracing::SpanOperation#span_id`      | `Datadog::Tracing::SpanOperation#id`      |
| `Datadog::Tracing::SpanOperation#span_type`    | `Datadog::Tracing::SpanOperation#type`    |
| `Datadog::Tracing::SpanOperation#span_type=`   | `Datadog::Tracing::SpanOperation#type=`   |
| `Datadog::Tracing::Span#span_id`               | `Datadog::Tracing::Span#id`               |
| `Datadog::Tracing::Span#span_type`             | `Datadog::Tracing::Span#type`             |
| `Datadog::Tracing::Span#span_type=`            | `Datadog::Tracing::Span#type=`            |

If you are manual instrumentation or pipeline processors

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

Remove obsolete fields from `Datadog::Tracing::Correlation::Identifier`, and responds to `#env`, `#service`, `#version`, `#trace_id`, `#span_id` and `#to_log_format`. The values returned from `#trace_id` and `#span_id` are now `String`.

Check if your usage still compatible when manually correlating logs.

<h3 id="2.0-distributed-tracing">Distributed Tracing</h3>

`Datadog::Tracing::Propagation::HTTP` has moved to `Datadog::Tracing::Contrib::HTTP`.

```ruby
# === with 1.x ===
Datadog::Tracing::Propagation::HTTP.inject!
Datadog::Tracing::Propagation::HTTP.extract

# === with 2.0 ===
Datadog::Tracing::Contrib::HTTP.inject
Datadog::Tracing::Contrib::HTTP.extract
```

Environment variable changes

| 1.x                            | 2.0                                  |
| ------------------------------ | ------------------------------------ |
| `DD_PROPAGATION_STYLE_INJECT`  | `DD_TRACE_PROPAGATION_STYLE_INJECT`  |
| `DD_PROPAGATION_STYLE_EXTRACT` | `DD_TRACE_PROPAGATION_STYLE_EXTRACT` |

The the values for the environment variables `DD_TRACE_PROPAGATION_STYLE`, `DD_TRACE_PROPAGATION_STYLE_INJECT`, and `DD_TRACE_PROPAGATION_STYLE_EXTRACT` are now considered case-insensitive. The major impact of this change is that, previously, B3 would configure Tracing with the B3 Multiple Headers propagator. Now B3 will configure it with the B3 Single Header propagator.

The deprecated B3 and B3 single header propagation style configuration values have been removed, use b3multi and b3 respectively instead.

Remove deprecated constants at `Datadog::Tracing::Distributed::Headers::Ext`. These constants have been moved to `Datadog::Tracing::Distributed::Datadog` and `Datadog::Tracing::Distributed::B3`.

<h3 id="2.0-transport">Transport</h3>

The `c.tracing.transport_options` option has been removed and cannot be configured with a custom transport adapter.

- See [Test adapter](GettingStarted.md#transporting-in-test-mode)
- See [Unix Domain Socket (UDS) adapter](GettingStarted.md#unix-domain-socket-uds)

Changes

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

Most custom sampling can be accomplished with a combination of Ingestion Controls and user-defined rules. This is the preferred option, as it is more maintainable and auditable than custom sampling.

If you still need a custom sampler, its API has been simplified in 2.0 by privatizing sampling objects. See [Custom Sampling](GettingStarted.md#custom-sampling) for the new detailed requirements of a custom sampler.

The custom sampler class `Datadog::Tracing::Sampling::RateSampler` now accepts a `sample_rate` of zero. This will drop all spans. Before 2.0, the RateSampler would fall back to a sample rate of 1.0 when provided with a `sample_rate` of zero.

The configuration option `c.tracing.priority_sampling` has been removed. To disable priority sampling, you now have to create a custom sampler.

<!-- EXAMPLE -->
```ruby
```

#### Objects privatized

| 1.x                                                | 2.0        |
| -------------------------------------------------- | ---------- |
| `Datadog::Tracing::Sampling::AllSampler`           | Privatized |
| `Datadog::Tracing::Sampling::Matcher`              | Privatized |
| `Datadog::Tracing::Sampling::SimpleMatcher`        | Privatized |
| `Datadog::Tracing::Sampling::ProcMatcher`          | Privatized |
| `Datadog::Tracing::Sampling::PrioritySampler`      | Privatized |
| `Datadog::Tracing::Sampling::RateByKeySampler`     | Privatized |
| `Datadog::Tracing::Sampling::RateByServiceSampler` | Privatized |
| `Datadog::Tracing::Sampling::RateLimiter`          | Privatized |
| `Datadog::Tracing::Sampling::TokenBucket`          | Privatized |
| `Datadog::Tracing::Sampling::UnlimitedLimiter`     | Privatized |
| `Datadog::Tracing::Sampling::RateSampler`          | Privatized |
| `Datadog::Tracing::Sampling::Rule`                 | Privatized |
| `Datadog::Tracing::Sampling::SimpleRule`           | Privatized |
| `Datadog::Tracing::Sampling::RuleSampler`          | Privatized |
| `Datadog::Tracing::Sampling::Sampler`              | Privatized |

<h2 id="2.0-instrumentation">Instrumentation changes</h2>

<h3 id='2.0-error-handling'>Error Handling</h3>

The `error_handler` options have been replaced by `on_error` to align with `options` for our public API `Datadog::Tracing.trace(options)`.

Rename `error_handler` option  to `on_error` in your configuration, except for [`active_job`](#activejob), [`grpc`](#grpc), [`faraday`](#faraday) and [`excon`](#excon).

<h3 id='2.0-error-status-codes'>Setting `error_status_codes` option with ENV</h3>

Option `error_status_codes` is introduced to various http integrations. It tags the span with an error based on http status from response header. Its value can be a range (`400...600`), or an array of ranges/integers `[403, 500...600]`. If configured with environment variable, use dash for an end-excluded range (`'400-599'`) and comma for adding element into an array (`'403,500-599'`)

#### ActiveJob

Remove `error_handler` option.

#### DelayedJob

Rename `error_handler` option to `on_error`. See [Error Handling](#2.0-error-handling)

#### Elasticsearch

Only ElasticSearch "transport" can be configured.

```ruby
# === with 1.x ===
Datadog.configure_onto(client, **options)
Datadog.configure_onto(client.transport, **options)

# === with 2.0 ===
Datadog.configure_onto(client.transport, **options)
```

#### Excon

Remove option `error_handler`, and use `error_status_codes` instead.

Configure option `error_status_codes` to tag span with an error based on http status from response header, the default is 400...600 (Only server errors are tagged in 1.x).

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

Additionally, configure `on_error` option to control behaviour when an exception (ie. `Excon::Error::Timeout`) is raised.

#### Faraday

Remove option `error_handler`, and use `error_status_codes` instead.

Configure option `error_status_codes` to tag span with an error based on http status from response header, the default is 400...600 (Only server errors are tagged in 1.x).

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

Additionally, configure `on_error` option to control behaviour when an exception (ie.`Faraday::ConnectionFailed`) is raised.

#### Grape

Option `error_statuses` has been removed, use `error_status_codes` instead.

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

Support `graphql-ruby` versions `>= 2.2.6`, which breaking changes were introduced. No longer support and patch GraphQL's defined-based schema.

* `schemas` : Optional (default: `[]`). Providing GraphQL schemas is not required. By default, every schema is instrumented.

* `with_deprecated_tracer` : Optional (default: `false`). Spans are generated by `GraphQL::Tracing::DataDogTrace`. When `true` , spans are generated by deprecated `GraphQL::Tracing::DataDogTracing`

Notes: `GraphQL::Tracing::DataDogTrace` is only available With `graphql-ruby(>= 2.0.19)`. Otherwise, it will fallback to the `GraphQL::Tracing::DataDogTracing`

Notes: The changes are backported to previous `graphql-ruby` versions

| branch   | version             |
| -------- | ------------------- |
| `1.13.x` | `>= 1.13.21, < 2.0` |
| `2.0.x`  | `>= 2.0.28, < 2.1`  |
| `2.1.x`  | `>= 2.1.11, > 2.2`  |

#### GRPC

Replace options `error_handler`, `server_error_handler` and `client_error_handler` with `on_error`

`on_error` options would be invoked on both server and client side instrumentation. Merge your `server_error_handler` and `client_error_handler` to `on_error`. The implementation for `on_error` should distinguish between the server and client.

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

`Datadog::Tracing::Contrib::HTTP::Instrumentation.after_request` has been removed.

#### PG

Rename `error_handler` option to `on_error`. See [Error Handling](#2.0-error-handling)

#### Qless

Removed

#### Que

Rename `error_handler` option to `on_error`. See [Error Handling](#2.0-error-handling)

#### Rack

`request_queuing` option on rack/rails must be boolean.

```ruby
# === with 1.x ===
Datadog.configure do |c|
  c.tracing.instrument :rack, request_queuing: :include_request
  # or
  c.tracing.instrument :rack, request_queuing: :exclude_request
end

# === with 2.0 ===
Datadog.configure do |c|
  c.tracing.instrument :rack, request_queuing: true
end
```

With `request_queuing` enabled, the behaviour changes from 1 span to 2 spans. The original `http_server.queue` span rename to `http.proxy.request`, with an additional `http.proxy.queue` span representing the time spent in a load balancer queue before reaching application.

Changing the name of the top-level span (`http_server.queue` -> `http.proxy.request`) would break a lot of stuff (monitors, dashboards, notebooks). The following snippet rename the top-level span back to help migration.

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

No longer support Rails 3

The `exception_controller` configuration option has been removed for Rails and Action Pack because it is automatically detected.

#### Resque

Rename `error_handler` option to `on_error`. See [Error Handling](#2.0-error-handling)

#### Shoryuken

Rename `error_handler` option to `on_error`. See [Error Handling](#2.0-error-handling)

#### Sidekiq

Rename `error_handler` option to `on_error`. See [Error Handling](#2.0-error-handling)

`tag_args` option is removed, use `quantize` instead

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

Remove Sidekiq worker specific configuration

Defining `datadog_tracer_config` on Sidekiq worker is never documented and publicly supported.

Removed constants

```ruby
Datadog::Tracing::Contrib::Sinatra::Ext::RACK_ENV_REQUEST_SPAN
Datadog::Tracing::Contrib::Sinatra::Ext::RACK_ENV_MIDDLEWARE_START_TIME
Datadog::Tracing::Contrib::Sinatra::Ext::RACK_ENV_MIDDLEWARE_TRACED
```

#### Sneakers

Rename `error_handler` option to `on_error`. See [Error Handling](#2.0-error-handling)

## Ensure traces reach the agent

Datadog::Tracing.reject! now only changes the priority sampling, as documented, instead of preventing the trace from reaching the Datadog Agent. Now, rejected traces will correctly count towards trace metrics.

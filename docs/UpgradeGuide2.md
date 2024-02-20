# Upgrading ddtrace to 2.0

## From 1.x to 2.0

Upgrading `ddtrace` from 1.x to 2.0 introduces some breaking changes which are outlined below.

**How to upgrade basic usage**

For users with a basic implementation (configuration file + out-of-the-box instrumentation), only minor changes to your configuration file are required: most applications take just minutes to update. Check out the following sections for a step-by-step guide.

- [Support changes](#2.0-support)
- [General](#2.0-general)
- [Dependency changes](#2.0-dependencies)
- [Configuration changes](#2.0-configuration)
  - [Distributed Tracing](#2.0-distributed-tracing)
  - [Transport](#2.0-transport)
  - [Sampling](#2.0-sampling)
- [Instrumentation changes](#2.0-instrumentation)

<h3 id="2.0-support">Support changes</h3>

The minimum version of Ruby supported by ddtrace 2.x is 2.5.0.
To install ddtrace for Ruby 2.1, 2.2, 2.3, or 2.4, you can use ddtrace 1.x.

OpenTracing is no longer supported

<h3 id="2.0-general">General changes</h3>

#### Frozen strings

🚨 All strings the strings are frozen by default. Make sure your code does not mutate them.

#### Data model

🚨 Remove option `span_type` from `Datadog::Tracing.trace` method and the following alias methods

- `Datadog::Tracing::SpanOperation#span_id`
- `Datadog::Tracing::SpanOperation#span_type`
- `Datadog::Tracing::SpanOperation#span_type=`
- `Datadog::Tracing::Span#span_id`
- `Datadog::Tracing::Span#span_type`
- `Datadog::Tracing::Span#span_type=`

If you are accessing `Datadog::Tracing::SpanOperation` with manual instrumentation or pipeline processors

Change `span_op.span_id` to `span_op.id`
Change `span_op.span_type` to `span_op.type`
Change `span_op.span_type =` to `span_op.type =`

For example:

```ruby
# === with 1.x ===
Datadog::Tracing.trace('my_span', span_type: 'custom') do |span_op|
  span_op.span_type = "...."
end

# === with 2.0 ===
Datadog::Tracing.trace('my_span', type: 'custom') do |span_op|
  span_op.type = "...."
end
```

#### Log Correlation

🚨 Remove obsolete fields from `Datadog::Tracing::Correlation::Identifier` , and responds to `#env`, `#service`, `#version`, `#trace_id`, `#span_id` and `#to_log_format`. The values returned from `#trace_id` and `#span_id` are now `String`.

Make sure to check if your usage still compatible when manually correlating logs.

<h3 id="2.0-dependencies">Dependencies changes</h3>

CI visibility component has been extracted as a separate gem named datadog-ci, and will no longer be installed together with ddtrace.

🚨 If you are using our CI visibility product, you will need to include `datadog-ci` in the project's Gemfile (learn more about the setup)

```ruby
gem 'ddtrace', '>= 2'
gem 'datadog-ci'
```

If you do not want to install `datadog-ci`, please ensure any CI related configuration under `Datadog.configure { |c| c.ci.* }` is removed.

```ruby
Datadog.configure do |c|
  c.ci.enabled = true

  c.ci.instrument :rspec
  c.ci.instrument :cucumber
end
```

<h3 id="2.0-configuration">Configuration changes</h3>

🚨 Remove `use` method for configuration, replace with `instrument`.

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

#### Stricter validation for integer and float configuration

Configuration options of types ':int' and ':float' now have stricter type validation:

Fractional numbers are no longer considered valid for ':int' options.

Empty values (nil or empty string) are no longer considered valid for ':int' or ':float' options.

This applies to both environment variable and programmatic configuration.

Here's the list of all affected options:
[Insert all :int and :float options at release time!!!]

🚨 The environment variable `DD_EXPERIMENTAL_SKIP_CONFIGURATION_VALIDATION` has been removed.

🚨 Configuration options can no longer be defined as lazy. All options are lazily evaluated, making this redundant.

🚨 `c.env` and `c.service` now have to be `String`.

🚨 Configuration `c.tracing.client_ip.enabled` with `ENV['DD_TRACE_CLIENT_IP_HEADER_DISABLED']` is removed, use `ENV['DD_TRACE_CLIENT_IP_ENABLED']` instead.

#### Remove distributed_tracing option namespacing

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

<h4 id="2.0-distributed-tracing">Distributed Tracing</h4>

🚨 The default distributed tracing propagation extraction style is now `Datadog,tracecontext`.

🚨 `Datadog::Tracing::Propagation::HTTP` has moved to `Datadog::Tracing::Contrib::HTTP`.

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
| ---                            | ---                                  |

The the values for the environment variables `DD_TRACE_PROPAGATION_STYLE`, `DD_TRACE_PROPAGATION_STYLE_INJECT`, and `DD_TRACE_PROPAGATION_STYLE_EXTRACT` are now considered case-insensitive. The major impact of this change is that, previously, B3 would configure Tracing with the B3 Multiple Headers propagator. Now B3 will configure it with the B3 Single Header propagator.

The deprecated B3 and B3 single header propagation style configuration values have been removed, use b3multi and b3 respectively instead.

Remove deprecated constants at `Datadog::Tracing::Distributed::Headers::Ext`. These constants have been moved to `Datadog::Tracing::Distributed::Datadog` and `Datadog::Tracing::Distributed::B3`.

<h4 id="2.0-transport">Transport</h4>


🚨 The `c.tracing.transport_options` option has been removed. The library can no longer be configured with a custom transport adapter. The default, or test adapter must be used. All agent transport configuration options can be set via the `Datadog.configure` block, or environment variables.

The following options have been added to replace configuration options previously only available via `transport_options`:

- `c.agent.timeout_seconds` or DD_TRACE_AGENT_TIMEOUT_SECONDS
- `c.agent.uds_path` or DD_TRACE_AGENT_UDS_PATH
- `c.agent.use_ssl` or DD_AGENT_USE_SSL

Setting uds path or the use of SSL via `DD_TRACE_AGENT_URL` continues to work as it did in 1.x.

To use the test adapter set `c.agent.tracing.test_mode.enabled = true`

🚨 Constant changes

| 1.x                                                              | 2.0                                                     |
| ---------------------------------------------------------------- | ------------------------------------------------------- |
| `Datadog::Transport::Ext::HTTP`                                  | `Datadog::Core::Transport::Ext::HTTP`                   |
| `Datadog::Transport::Ext::Test`                                  | `Datadog::Core::Transport::Ext::Test`                   |
| `Datadog::Transport::Ext::UnixSocket`                            | `Datadog::Core::Transport::Ext::UnixSocket`             |
| `Datadog::Core::Configuration::Ext::Transport::ENV_DEFAULT_HOST` | `Datadog::Core::Configuration::Agent::ENV_DEFAULT_HOST` |


🚨 Removed unused, non-public methods:

- `Datadog::Tracing::Transport::HTTP#default_hostname`
- `Datadog::Tracing::Transport::HTTP#default_port`
- `Datadog::Tracing::Transport::HTTP#default_url`
- `Datadog::Core::Remote::Transport::HTTP#default_hostname`
- `Datadog::Core::Remote::Transport::HTTP#default_port`
- `Datadog::Core::Remote::Transport::HTTP#default_url`

<h4 id="2.0-sampling">Sampling</h4>

🚨 The following sampling classes have been removed from the public API:

```ruby
Datadog::Tracing::Sampling::AllSampler
Datadog::Tracing::Sampling::Matcher
Datadog::Tracing::Sampling::SimpleMatcher
Datadog::Tracing::Sampling::ProcMatcher
Datadog::Tracing::Sampling::PrioritySampler
Datadog::Tracing::Sampling::RateByKeySampler
Datadog::Tracing::Sampling::RateByServiceSampler
Datadog::Tracing::Sampling::RateLimiter
Datadog::Tracing::Sampling::TokenBucket
Datadog::Tracing::Sampling::UnlimitedLimiter
Datadog::Tracing::Sampling::RateSampler
Datadog::Tracing::Sampling::Rule
Datadog::Tracing::Sampling::SimpleRule
Datadog::Tracing::Sampling::RuleSampler
Datadog::Tracing::Sampling::Sampler
```

Most custom sampling can be accomplished with a combination of Ingestion Controls and user-defined rules. This is the preferred option, as it is more maintainable and auditable than custom sampling.

If you still need a custom sampler, its API has been simplified in 2.0. See https://github.com/DataDog/dd-trace-rb/blob/2.0/docs/GettingStarted.md#custom-sampling for the new detailed requirements of a custom sampler.

🚨 The custom sampler class `Datadog::Tracing::Sampling::RateSampler` now accepts a `sample_rate` of zero. This will drop all spans. Before 2.0, the RateSampler would fall back to a sample rate of 1.0 when provided with a `sample_rate` of zero.

🚨 The configuration setting `c.tracing.priority_sampling` has been removed. This option was used to disable priority sampling, which was enabled by default. To disable priority sampling, you now have to create a custom sampler.

<h3 id="2.0-instrumentation">Instrumentation changes</h3>

🚨 The `error_handler` settings have been replaced by `on_error` to align with the options for `Datadog::Tracing.trace(options)`.

#### ActiveJob

🚨 Remove `error_handler` option, it was never used.

#### DelayedJob

🚨 Rename `error_handler` option to `on_error`

#### Elasticsearch

🚨 Only ElasticSearch "transport" can be configured.

```ruby
# === with 1.x ===
Datadog.configure_onto(client, **options)
Datadog.configure_onto(client.transport, **options)

# === with 2.0 ===
Datadog.configure_onto(client.transport, **options)
```

#### Excon

🚨 Remove option `error_handler`

Add `on_error` and `error_status_codes`

Configure option  `error_status_codes` to control tagging span with error, the default is 400...600 (previous only server servers are tagged.)

Configure option `on_error` to control behaviour when exception is raised.

#### Faraday

🚨 Remove option `error_handler`

Add `on_error` and `error_status_codes`

Configure option  `error_status_codes` to control tagging span with error, the default is 400...600 (previous only server servers are tagged.)

Configure option `on_error` to control behaviour when exception is raised. For example: `Faraday::ConnectionFailed/Excon::Error::Timeout`

#### Grape

🚨 Replace option `error_statuses` with `error_status_codes`.

Change your configuration from string to array of ranges or integers.

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

🚨 No longer support and patch GraphQL's defined-based schema

🚨 Support `graphql-ruby` versions `>= 2.2.6`, which breaking changes were introduced.

The changes are backported to previous `graphql-ruby` versions

| branch   | version             |
| -------- | ------------------- |
| `1.13.x` | `>= 1.13.21, < 2.0` |
| `2.0.x`  | `>= 2.0.28, < 2.1`  |
| `2.1.x`  | `>= 2.1.11, > 2.2`  |

Configuration changes:

`schemas` : Optional (default: `[]`). GraphQL schemas are no longer required to be explicitly provided. By default, every schema is instrumented.

`with_deprecated_tracer` : Optional (default: `false`). Spans are generated by `GraphQL::Tracing::DataDogTrace`. When `true` , spans are generated by deprecated `GraphQL::Tracing::DataDogTracing`

Notes: `GraphQL::Tracing::DataDogTrace` is only available With `graphql-ruby(>= 2.0.19)`. Otherwise, it will fallback to the `GraphQL::Tracing::DataDogTracing`

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

🚨 `Datadog::Tracing::Contrib::HTTP::Instrumentation.after_request` has been removed.

This hook was intrusive, only restricted to the net/http client, and was not generalizable to other HTTP client gems. If you require this hook, please open a "Feature request" stating your use case so we can asses how to best support it.

#### PG

🚨 Rename `error_handler` option to `on_error`

#### Qless

🚨 Removed

#### Que

🚨 Rename `error_handler` option to `on_error`

#### Rack

🚨 `request_queuing` option on rack/rails must be boolean.

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

🚨 No longer support Rails 3

🚨 The `exception_controller` configuration option has been removed for Rails and Action Pack because it is automatically detected.

#### Resque

🚨 Rename `error_handler` option to `on_error`


#### Shoryuken

🚨 Rename `error_handler` option to `on_error`

#### Sidekiq

🚨 Rename `error_handler` option to `on_error`

🚨 `tag_args` option is removed, use `quantize` instead

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

🚨 Remove Sidekiq worker specific configuration

Defining `datadog_tracer_config` on Sidekiq worker is never documented and publicly supported.

🚨 Removed constants

```ruby
Datadog::Tracing::Contrib::Sinatra::Ext::RACK_ENV_REQUEST_SPAN
Datadog::Tracing::Contrib::Sinatra::Ext::RACK_ENV_MIDDLEWARE_START_TIME
Datadog::Tracing::Contrib::Sinatra::Ext::RACK_ENV_MIDDLEWARE_TRACED
```

#### Sneakers

🚨 Rename `error_handler` option to `on_error`

---

#### Remove unused module Compression

The unused module Datadog::Core::Utils::Compression has been removed

#### Fix error_status_codes options

Fix and standardize the way to configure an array of ranges for error_status_codes from environment variables.

## Ensure traces reach the agent

Datadog::Tracing.reject! now only changes the priority sampling, as documented, instead of preventing the trace from reaching the Datadog Agent. Now, rejected traces will correctly count towards trace metrics.

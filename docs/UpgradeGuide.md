# Upgrading datadog

# From 0.x to 1.0

Upgrading `ddtrace` from 0.x to 1.x introduces some breaking changes which are outlined below.

**How to upgrade basic usage**

For users with a basic implementation (configuration file + out-of-the-box instrumentation), only minor changes to your configuration file are required: most applications take just minutes to update. Check out the following sections for a step-by-step guide.

- [Configuration](#1.0-configuration)
  - [`require` paths have changed](#1.0-configuration-requires)
  - [Settings have been renamed](#1.0-configuration-settings)
  - [Activating instrumentation](#1.0-configuration-instrumentation)
- [Instrumentation](#1.0-instrumentation)
  - [Service naming](#1.0-instrumentation-service-naming)

**Additional upgrades for advanced usage**

For users with an advanced implementation of `ddtrace` (custom instrumentation, sampling or processing behavior, etc), some additional namespace and behavioral changes may be required. See the following sections for details about what features changed and how to use them.

- [Namespacing](#1.0-namespacing)
- [Trace API](#1.0-trace-api)
  - [Removed `Datadog.tracer`](#1.0-trace-api-removed-tracer)
  - [Removed access to `Datadog::Context`](#1.0-trace-api-removed-context)
  - [Manual tracing & trace model](#1.0-trace-api-manual-tracing)
  - [Accessing trace state](#1.0-trace-api-trace-state)
  - [Distributed tracing](#1.0-trace-api-distributed)
    - [Over HTTP](#1.0-trace-api-distributed-http)
    - [Over gRPC](#1.0-trace-api-distributed-grpc)
    - [Between threads](#1.0-trace-api-distributed-threads)
  - [Sampling](#1.0-trace-api-sampling)
  - [Processing pipeline](#1.0-trace-api-pipeline)

**Appendix**

For a comprehensive list of everything that changed, the appendix hosts some helpful and detailed tables with recommendations.

  - [Namespace mappings](#1.0-appendix-namespace)
    - [Constants](#1.0-appendix-namespace-constants)
  - [Breaking changes](#1.0-appendix-breaking-changes)

<h1 id="1.0-basic-upgrade">Upgrading basic usage</h1>

<h2 id="1.0-configuration">Configuration</h2>

<h3 id="1.0-configuration-requires">`require` paths have changed</h3>

If you `require` any of the following paths, update them accordingly:

| 0.x `require` path          | 1.0 `require` path          |
|-----------------------------|-----------------------------|
| `ddtrace/opentelemetry`     | Removed                     |
| `ddtrace/opentracer`        | `datadog/opentracer`        |
| `ddtrace/profiling/preload` | `datadog/profiling/preload` |

Using `require 'ddtrace'` will load all features by default. To load individual features, you may use the following paths instead:

| Feature     | 1.0 `require` path   |
|-------------|----------------------|
| AppSec      | `datadog/appsec`     |
| CI          | `datadog/ci`         |
| OpenTracing | `datadog/opentracer` |
| Profiling   | `datadog/profiling`  |
| Tracing     | `datadog/tracing`    |

<h3 id="1.0-configuration-settings">Settings have been renamed</h3>

Configuration settings have been sorted into smaller configuration groups, by feature.

 - `Datadog.configure { |c| c.* }`: Datadog configuration settings
 - `Datadog.configure { |c| c.tracing.* }`: Tracing configuration settings
 - `Datadog.configure { |c| c.profiling.* }`: Profiling configuration settings
 - `Datadog.configure { |c| c.ci.* }`: CI configuration settings

For existing applications, configuration files should be updated accordingly. For example:

```ruby
# config/initializers/datadog.rb
require 'ddtrace'

### Old 0.x ###
Datadog.configure do |c|
  # Global settings
  c.tracer.hostname = '127.0.0.1'
  c.tracer.port = 8126
  c.runtime_metrics_enabled = true
  c.service = 'billing-api'

  # Tracing settings
  c.analytics.enabled = true
  c.tracer.partial_flush.enabled = true

  # CI settings
  c.ci_mode = (ENV['DD_ENV'] == 'ci')

  # Instrumentation
  c.use :rails
  c.use :redis, service_name: 'billing-redis'
  c.use :rspec
end


### New 1.0 ###
Datadog.configure do |c|
  # Global settings
  c.agent.host = '127.0.0.1'
  c.agent.port = 8126
  c.runtime_metrics.enabled = true
  c.service = 'billing-api'

  # Tracing settings
  c.tracing.analytics.enabled = true
  c.tracing.partial_flush.enabled = true

  # CI settings
  c.ci.enabled = (ENV['DD_ENV'] == 'ci')

  # Instrumentation
  c.tracing.instrument :rails
  c.tracing.instrument :redis, service_name: 'billing-redis'
  c.ci.instrument :rspec
end
```

Check out the table below for a list of common mappings:

| 0.x setting                            | 1.0 setting                     |
|----------------------------------------|---------------------------------|
| `analytics.enabled`                    | `tracing.analytics.enabled`     |
| `ci_mode.context_flush`                | `ci.context_flush`              |
| `ci_mode.enabled`                      | `ci.enabled`                    |
| `ci_mode.writer_options`               | `ci.writer_options`             |
| `distributed_tracing`                  | `tracing.distributed_tracing`   |
| `logger=`                              | `logger.instance=`              |
| `profiling.exporter.transport_options` | Removed                         |
| `report_hostname`                      | `tracing.report_hostname`       |
| `runtime_metrics_enabled`              | `runtime_metrics.enabled`       |
| `runtime_metrics(options)`             | Removed                         |
| `sampling`                             | `tracing.sampling`              |
| `test_mode`                            | `tracing.test_mode`             |
| `tracer=`                              | Removed                         |
| `tracer.debug`                         | `diagnostics.debug`             |
| `tracer.enabled`                       | `tracing.enabled`               |
| `tracer.env`                           | `env`                           |
| `tracer.hostname`                      | `agent.host`                    |
| `tracer.instance`                      | `tracing.instance`              |
| `tracer.log`                           | `logger.instance`               |
| `tracer.partial_flush`                 | `tracing.partial_flush.enabled` |
| `tracer.port`                          | `agent.port`                    |
| `tracer.sampler`                       | `tracing.sampler`               |
| `tracer.tags`                          | `tags`                          |
| `tracer.transport_options`             | `tracing.transport_options`     |
| `tracer.transport_options(options)`    | Removed                         |
| `tracer.writer`                        | `tracing.writer`                |
| `tracer.writer_options`                | `tracing.writer_options`        |
| `use`                                  | `tracing.instrument`            |

<h3 id="1.0-configuration-instrumentation">Activating instrumentation</h3>

 - The `use` function has been renamed to `instrument`.
 - `instrument` has been namespaced within the feature to which it belongs.

As an example:

```ruby
### Old 0.x ###
Datadog.configure do |c|
  # Tracing instrumentation
  c.use :rails

  # CI instrumentation
  c.use :cucumber
end


### New 1.0 ###
Datadog.configure do |c|
  # Tracing instrumentation
  c.tracing.instrument :rails

  # CI instrumentation
  c.ci.instrument :cucumber
end
```

Similarly, if you were accessing configuration for instrumentation, you will need to use the appropriate namespace:

```ruby
### Old 0.x ###
Datadog.configuration[:rails][:service_name]
Datadog.configuration[:cucumber][:service_name]

### New 1.0 ###
Datadog.configuration.tracing[:rails][:service_name]
Datadog.configuration.ci[:cucumber][:service_name]
```

<h2 id="1.0-instrumentation">Instrumentation</h2>

<h3 id="1.0-instrumentation-service-naming">Service naming</h3>

**Define an application service name**

We recommend setting the application's service name with `DD_SERVICE`, or by adding the following configuration:

```ruby
Datadog.configure do |c|
  c.service = 'billing-api' # Or DD_SERVICE. Defaults to process name.
end
```

If this is not set, it will default to the process name.

**Update service names for your integrations**

Spans now inherit the global `service` name by default, unless otherwise explicitly set. This means, generally speaking, spans generated by Datadog integrations will default to the global `service` name, unless the `service_name` setting is configured for that integration.

Spans that describe external services (e.g. `mysql`) will continue to default to some other name that describes the external service instead. (e.g. `mysql`)

```ruby
### Old 0.x ###
Datadog.configure do |c|
  # Instrumentation that measures internal behavior
  c.use :rails, service_name: 'billing-api'
  c.use :resque, service_name: 'billing-api'
  c.use :sidekiq, service_name: 'billing-api'

  # Instrumentation that measures external services
  c.use :active_record, service_name: 'billing-api_mysql' # Defaults to DB type e.g. mysql
  c.use :http, service_name: 'billing-api_http' # Defaults to net/http
  c.use :redis, service_name: 'billing-api_redis' # Defaults to redis
end

### New 1.0 ###
Datadog.configure do |c|
  c.service = 'billing-api'

  # Instrumentation that measures internal behavior
  # now inherits the application's service name.
  c.tracing.instrument :rails
  c.tracing.instrument :resque
  c.tracing.instrument :sidekiq

  # Instrumentation that measures external services
  # defaults to adapter-specific names. You may still override
  # these names with the `service_name:` option.
  c.tracing.instrument :active_record, service_name: 'billing-api_mysql' # Defaults to DB type e.g. mysql
  c.tracing.instrument :http, service_name: 'billing-api_http' # Defaults to net/http
  c.tracing.instrument :redis, service_name: 'billing-api_redis' # Defaults to redis
end
```

**Update Rails instrumentation**

If your application activates and configures `rails` instrumentation, you will need to adjust your settings slightly.

The following options have been removed; instead, configure the underlying instrumentation directly.

| 0.x setting                                 | 1.0 setting                                                    |
|---------------------------------------------|----------------------------------------------------------------|
| `use :rails, cache_service: <SERVICE>`      | `tracing.instrument :active_support, cache_service: <SERVICE>` |
| `use :rails, controller_service: <SERVICE>` | `tracing.instrument :action_pack, service_name: <SERVICE>`     |
| `use :rails, database_service: <SERVICE>`   | `tracing.instrument :active_record, service_name: <SERVICE>`   |
| `use :rails, job_service: <SERVICE>`        | `tracing.instrument :active_job, service_name: <SERVICE>`      |
| `use :rails, log_injection: true`           | `tracing.log_injection = true` (Is `true` by default.)         |

```ruby
### Old 0.x ###
Datadog.configure do |c|
  c.use :rails, service_name: 'billing-api',
                cache_service: 'billing-api-cache',
                controller_service: 'billing-api-controllers',
                database_service: 'billing-api-db',
                job_service: 'billing-api-jobs',
                log_injection: true
end

### New 1.0 ###
Datadog.configure do |c|
  c.service = 'billing-api'

  c.tracing.instrument :rails
  c.tracing.instrument :active_support, cache_service: 'billing-api-cache'
  c.tracing.instrument :action_pack, service_name: 'billing-api-controllers'
  c.tracing.instrument :active_record, service_name: 'billing-api-db'
  c.tracing.instrument :active_job, service_name: 'billing-api-jobs'
end
```

<h1 id="1.0-advanced-upgrade">Upgrading advanced usage</h1>

<h2 id="1.0-namespacing">Namespacing</h2>

Many files and constants within `ddtrace` have been recategorized by feature. The new categorization scheme is as follows:

| Feature          | Namespace                | File path               |
|------------------|--------------------------|-------------------------|
| Globals          | `Datadog`                | `ddtrace`               |
|                  |                          |                         |
| CI               | `Datadog::CI`            | `datadog/ci`            |
| Core (Internals) | `Datadog::Core`          | `datadog/core`          |
| OpenTelemetry    | `Datadog::OpenTelemetry` | `datadog/opentelemetry` |
| OpenTracing      | `Datadog::OpenTracer`    | `datadog/opentracer`    |
| Profiling        | `Datadog::Profiling`     | `datadog/profiling`     |
| Security         | `Datadog::AppSec`        | `datadog/appsec`        |
| Tracing          | `Datadog::Tracing`       | `datadog/trace`         |

As a result, if your application referenced file paths or constants affected by this change, they will need to be updated. Check out the [namespace mappings](#1.0-appendix-namespace) for some common cases and how to update them.

<h2 id="1.0-trace-api">Trace API</h2>

Usage of `Datadog.tracer` has been replaced with the `Datadog::Tracing` trace API. This module contains most of the functions that `Datadog.tracer` had, and most use cases will map one-to-one.

For example:

```ruby
### Old 0.x ###
Datadog.tracer.trace
Datadog.tracer.active_span
Datadog.tracer.active_correlation.to_s


### New 1.0 ###
Datadog::Tracing.trace
Datadog::Tracing.active_span
Datadog::Tracing.log_correlation

# ...and more...
```

See the table below for most common mappings:

| 0.x usage                                                                                    | 1.0 usage                                   | Note                                                                |
|----------------------------------------------------------------------------------------------|---------------------------------------------|---------------------------------------------------------------------|
| `Datadog.tracer.active_correlation.to_s`                                                     | `Datadog::Tracing.log_correlation`          | Returns `String` with trace identifiers for logging.                |
| `Datadog.tracer.active_correlation`                                                          | `Datadog::Tracing.correlation`              | Returns `Datadog::Tracing::Correlation::Identifier`                 |
| `Datadog.tracer.active_root_span`                                                            | Removed                                     | Consider `Datadog::Tracing.active_trace` instead.                   |
| `Datadog.tracer.active_span.context.sampling_priority = Datadog::Ext::Priority::USER_KEEP`   | `Datadog::Tracing.keep!`                    | See [sampling](#1.0-trace-api-sampling) for details.                |
| `Datadog.tracer.active_span.context.sampling_priority = Datadog::Ext::Priority::USER_REJECT` | `Datadog::Tracing.reject!`                  | See [sampling](#1.0-trace-api-sampling) for details.                |
| `Datadog.tracer.active_span.context`                                                         | Removed                                     | Consider `Datadog::Tracing.active_trace` instead.                   |
| `Datadog.tracer.active_span`                                                                 | `Datadog::Tracing.active_span`              | See [trace state](#1.0-trace-api-trace-state) for details.          |
| `Datadog.tracer.call_context`                                                                | Removed                                     | See [trace state](#1.0-trace-api-trace-state) for details.          |
| `Datadog.tracer.configure(options)`                                                          | `Datadog.configure { \|c\| ... }`           | Use configuration API instead.                                      |
| `Datadog.tracer.provider.context = context`                                                  | `Datadog::Tracing.continue_trace!(digest)`  | See [distributed tracing](#1.0-trace-api-distributed) for details.  |
| `Datadog.tracer.set_tags(tags)`                                                              | `Datadog.configure { \|c\| c.tags = tags }` |                                                                     |
| `Datadog.tracer.shutdown!`                                                                   | `Datadog::Tracing.shutdown!`                |                                                                     |
| `Datadog.tracer.start_span`                                                                  | `Datadog::Tracing.trace`                    | See [manual tracing](#1.0-trace-api-manual-tracing) for details.    |
| `Datadog.tracer.trace`                                                                       | `Datadog::Tracing.trace`                    | See [manual tracing](#1.0-trace-api-manual-tracing) for details.    |


Also check out the functions defined within `Datadog::Tracing` in our [public API](https://www.rubydoc.info/gems/ddtrace/) for more details on their usage.

<h3 id="1.0-trace-api-removed-tracer">Removed `Datadog.tracer`</h3>

Many of the functions accessed directly through `Datadog.tracer` have been moved to `Datadog::Tracing` instead.

<h3 id="1.0-trace-api-removed-context">Removed access to `Datadog::Context`</h3>

Direct usage of `Datadog::Context` has been removed. Previously, it was used to modify or access active trace state. Most use cases have been replaced by our [public trace API](https://www.rubydoc.info/gems/ddtrace/).

<h3 id="1.0-trace-api-manual-tracing">Manual tracing & trace model</h3>

Manual tracing is now done through the [public API](https://www.rubydoc.info/gems/ddtrace/).

Whereas in 0.x, the block would provide a `Datadog::Span` as `span`, in 1.0, the block provides a `Datadog::Tracing::SpanOperation` as `span` and `Datadog::Tracing::TraceOperation` as `trace`.

```ruby
### Old 0.x ###
Datadog.tracer.trace('my.job') do |span|
  # Do work...
  # span => #<Datadog::Tracing::Span>
end


### New 1.0 ###
Datadog::Tracing.trace('my.job') do |span, trace|
  # Do work...
  # span => #<Datadog::Tracing::SpanOperation>
  # trace => #<Datadog::Tracing::TraceOperation>
end
```

The provided `span` is nearly identical in behavior, except access to some fields (like `context`) been removed. Instead, the provided `trace`, which models the trace itself, grants access to new functions, of which some replace old `span` behavior.

For more details about new behaviors and the trace model, see [this pull request](https://github.com/DataDog/dd-trace-rb/pull/1783).

<h3 id="1.0-trace-api-trace-state">Accessing trace state</h3>

The public API provides new functions to access active trace data:

```ruby
### Old 0.x ###
# Returns the active context (contains trace state)
Datadog.tracer.call_context
# Returns the active Span
Datadog.tracer.active_span
# Returns an immutable set of identifiers for the current trace state
Datadog.tracer.active_correlation


### New 1.0 ###
# Returns the active TraceOperation for the current thread (contains trace state)
Datadog::Tracing.active_trace
# Returns the active SpanOperation for the current thread (contains span state)
Datadog::Tracing.active_span
# Returns an immutable set of identifiers for the current trace state
Datadog::Tracing.correlation
```

Use of `active_root_span` has been removed.

<h3 id="1.0-trace-api-distributed">Distributed tracing</h3>

Previously, distributed tracing required building new `Datadog::Context` objects, then replacing the context within the tracer.

Instead, users must use `TraceDigest` objects derived from a trace. `TraceDigest` represents the state of a trace. It can be used to propagate a trace across execution boundaries (processes, threads) or to continue a trace locally.

```ruby
### Old 0.x ###
# Get trace continuation from active trace
env = {}
Datadog::HTTPPropagator.inject(Datadog.tracer.call_context, env)
context = Datadog::HTTPPropagator.extract(env)

# Continue a trace: implicit continuation
Datadog.tracer.provider.context = context

# Next trace inherits trace properties
Datadog.tracer.trace('my.job') do |span|
  span.trace_id == context.trace_id
end


### New 1.0 ###
# Get trace continuation from active trace
trace_digest = Datadog::Tracing.active_trace.to_digest

# Continue a trace: implicit continuation
# Digest will be "consumed" by the next `trace` operation
Datadog::Tracing.continue_trace!(trace_digest)

# Next trace inherits trace properties
Datadog::Tracing.trace('my.job') do |span, trace|
  trace.id == trace_digest.trace_id
end

# Second trace does NOT inherit trace properties
Datadog::Tracing.trace('my.job') do |span, trace|
  trace.id != trace_digest.trace_id
end
```

New in 1.0, it's also possible to explicitly assign a trace block to continue from a specific trace, rather than implicitly inherit an active context. This gives users fine-grained control in applications where multiple traces run concurrently in the same execution context:

```ruby
### New 1.0 ###
# Get trace continuation from active trace
trace_digest = Datadog::Tracing.active_trace.to_digest

# Continue a trace: explicit continuation
# Inherits trace properties from the trace digest
Datadog::Tracing.trace('my.job', continue_from: trace_digest) do |span, trace|
  trace.id == trace_digest.trace_id
end

# Continue a trace: explicit continuation (using #continue_trace!)
Datadog::Tracing.continue_trace!(trace_digest) do
  # Traces implicitly continue within the block
  Datadog::Tracing.trace('my.job') do |span, trace|
    trace.id == trace_digest.trace_id
  end
end
```

<h4 id="1.0-trace-api-distributed-http">Over HTTP</h4>

To propagate active trace to a remote service:

```ruby
### Old 0.x ###
headers = {}
context = Datadog.tracer.call_context
Datadog::HTTPPropagator.inject!(context, headers)

outgoing = Net::HTTP::Get.new(uri)
headers.each { |name, value| outgoing[name] = value }

### New 1.0 ###
headers = {}
trace_digest = Datadog::Tracing.active_trace.to_digest
Datadog::Tracing::Propagation::HTTP.inject!(trace_digest, headers)

outgoing = Net::HTTP::Get.new(uri)
headers.each { |name, value| outgoing[name] = value }
```

To continue a trace from a remote service:

```ruby
### Old 0.x ###
incoming = Rack::Request.new(env)
context = Datadog::HTTPPropagator.extract(incoming.env)
Datadog.tracer.provider.context = context

### New 1.0 ###
incoming = Rack::Request.new(env)
trace_digest = Datadog::Tracing::Propagation::HTTP.extract(incoming.env)
Datadog::Tracing.continue_trace!(trace_digest)
```

<h4 id="1.0-trace-api-distributed-grpc">Over gRPC</h4>

To propagate active trace to a remote service:

```ruby
### Old 0.x ###
context = Datadog.tracer.call_context
Datadog::GRPCPropagator.inject!(context, metadata)

### New 1.0 ###
trace_digest = Datadog::Tracing.active_trace.to_digest
Datadog::Tracing::Propagation::GRPC.inject!(trace_digest, metadata)
```

To continue a trace from a remote service:

```ruby
### Old 0.x ###
context = Datadog::GRPCPropagator.extract(metadata)
Datadog.tracer.provider.context = context

### New 1.0 ###
trace_digest = Datadog::Tracing::Propagation::GRPC.extract(metadata)
Datadog::Tracing.continue_trace!(trace_digest)
```

<h4 id="1.0-trace-api-distributed-threads">Between threads</h4>

Traces do not implicitly propagate across threads, as they are considered different execution contexts.

However, if you wish to do this, trace propagation across threads is similar to cross-process. A `TraceDigest` should be produced by the parent thread and consumed by the child thread.

NOTE: The same `TraceOperation` object should never be shared between threads; this would create race conditions.

```ruby
### New 1.0 ###
# Get trace digest
trace = Datadog::Tracing.active_trace

# NOTE: We must produce the digest BEFORE starting the thread.
#       Otherwise if it's lazily evaluated within the thread,
#       the thread's trace may follow the wrong parent span.
trace_digest = trace.to_digest

Thread.new do
  # Inherits trace properties from the trace digest
  Datadog::Tracing.trace('my.job', continue_from: trace_digest) do |span, trace|
    trace.id == trace_digest.trace_id
  end
end
```

<h3 id="1.0-trace-api-sampling">Sampling</h3>

Accessing `call_context` to set explicit sampling has been removed.

Instead, use the `TraceOperation` to set the sampling decision.

```ruby
### Old 0.x ###
# From within the trace:
Datadog.tracer.trace('web.request') do |span|
  span.context.sampling_priority = Datadog::Ext::Priority::USER_REJECT if env.path == '/healthcheck'
end

# From outside the trace:
# Keeps current trace
Datadog.tracer.active_span.context.sampling_priority = Datadog::Ext::Priority::USER_KEEP
# Drops current trace
Datadog.tracer.active_span.context.sampling_priority = Datadog::Ext::Priority::USER_REJECT


### New 1.0 ###
# From within the trace:
Datadog::Tracing.trace('web.request') do |span, trace|
  trace.reject! if env.path == '/healthcheck'
end

# From outside the trace:
Datadog::Tracing.keep! # Keeps current trace
Datadog::Tracing.reject! # Drops current trace
```

<h3 id="1.0-trace-api-pipeline">Processing pipeline</h3>

When using a trace processor in the processing pipeline, the block provides a `TraceSegment` as `trace` (instead of `Array[Datadog::Span]`.) This object can be directly mutated.

```ruby
### Old 0.x ###
Datadog::Pipeline.before_flush do |trace|
  # Processing logic...
  trace # => Array[Datadog::Span]
end


### New 1.0 ###
Datadog::Tracing.before_flush do |trace|
   # Processing logic...
   trace # => #<Datadog::Tracing::TraceSegment>
end
```

<h2 id="1.0-appendix">Appendix</h2>

<h3 id="1.0-appendix-namespace">Namespace mappings</h3>

<h4 id="1.0-appendix-namespace-constants">Constants</h3>

| `0.x Constant`                                                  | `1.0 Constant`                                                                          |
|-----------------------------------------------------------------|-----------------------------------------------------------------------------------------|
| `Datadog::AllSampler`                                           | `Datadog::Tracing::Sampling::AllSampler`                                                |
| `Datadog::Buffer`                                               | `Datadog::Core::Buffer::Random`                                                         |
| `Datadog::Chunker`                                              | `Datadog::Core::Chunker`                                                                |
| `Datadog::Configuration`                                        | `Datadog::Core::Configuration`                                                          |
| `Datadog::ContextFlush`                                         | `Datadog::Tracing::Flush`                                                               |
| `Datadog::CRubyBuffer`                                          | `Datadog::Core::Buffer::CRuby`                                                          |
| `Datadog::Diagnostics`                                          | `Datadog::Core::Diagnostics`                                                            |
| `Datadog::DistributedTracing`                                   | `Datadog::Tracing::Distributed`                                                         |
| `Datadog::Encoding`                                             | `Datadog::Core::Encoding`                                                               |
| `Datadog::Error`                                                | `Datadog::Core::Error`                                                                  |
| `Datadog::Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED`          | `Datadog::Tracing::Configuration::Ext::Analytics::ENV_TRACE_ANALYTICS_ENABLED`          |
| `Datadog::Ext::Analytics`                                       | `Datadog::Tracing::Metadata::Ext::Analytics`                                            |
| `Datadog::Ext::AppTypes`                                        | `Datadog::Tracing::Metadata::Ext::AppTypes`                                             |
| `Datadog::Ext::Correlation::ENV_LOGS_INJECTION_ENABLED`         | `Datadog::Tracing::Configuration::Ext::Correlation::ENV_LOGS_INJECTION_ENABLED`         |
| `Datadog::Ext::Correlation`                                     | `Datadog::Tracing::Correlation::Identifier`                                             |
| `Datadog::Ext::Diagnostics`                                     | `Datadog::Core::Diagnostics::Ext`                                                       |
| `Datadog::Ext::Distributed::ENV_PROPAGATION_STYLE_EXTRACT`      | `Datadog::Tracing::Configuration::Ext::Distributed::ENV_PROPAGATION_STYLE_EXTRACT`      |
| `Datadog::Ext::Distributed::ENV_PROPAGATION_STYLE_INJECT`       | `Datadog::Tracing::Configuration::Ext::Distributed::ENV_PROPAGATION_STYLE_INJECT`       |
| `Datadog::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER` | `Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3_SINGLE_HEADER` |
| `Datadog::Ext::Distributed::PROPAGATION_STYLE_B3`               | `Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_B3`               |
| `Datadog::Ext::Distributed::PROPAGATION_STYLE_DATADOG`          | `Datadog::Tracing::Configuration::Ext::Distributed::PROPAGATION_STYLE_DATADOG`          |
| `Datadog::Ext::Distributed`                                     | `Datadog::Tracing::Metadata::Ext::Distributed`                                          |
| `Datadog::Ext::DistributedTracing::TAG_ORIGIN`                  | `Datadog::Tracing::Metadata::Ext::Distributed::TAG_ORIGIN`                              |
| `Datadog::Ext::DistributedTracing::TAG_SAMPLING_PRIORITY`       | `Datadog::Tracing::Metadata::Ext::Distributed::TAG_SAMPLING_PRIORITY`                   |
| `Datadog::Ext::DistributedTracing`                              | `Datadog::Tracing::Distributed::Headers::Ext`                                           |
| `Datadog::Ext::Environment`                                     | `Datadog::Core::Environment::Ext`                                                       |
| `Datadog::Ext::Errors`                                          | `Datadog::Tracing::Metadata::Ext::Errors`                                               |
| `Datadog::Ext::Git`                                             | `Datadog::Core::Git::Ext`                                                               |
| `Datadog::Ext::HTTP`                                            | `Datadog::Tracing::Metadata::Ext::HTTP`                                                 |
| `Datadog::Ext::Integration`                                     | `Datadog::Tracing::Metadata::Ext`                                                       |
| `Datadog::Ext::NET::ENV_REPORT_HOSTNAME`                        | `Datadog::Tracing::Configuration::Ext::NET::ENV_REPORT_HOSTNAME`                        |
| `Datadog::Ext::NET`                                             | `Datadog::Tracing::Metadata::Ext::NET`                                                  |
| `Datadog::Ext::Priority`                                        | `Datadog::Tracing::Sampling::Ext::Priority`                                             |
| `Datadog::Ext::Runtime`                                         | `Datadog::Core::Runtime::Ext`                                                           |
| `Datadog::Ext::Sampling::ENV_RATE_LIMIT`                        | `Datadog::Tracing::Configuration::Ext::Sampling::ENV_RATE_LIMIT`                        |
| `Datadog::Ext::Sampling::ENV_SAMPLE_RATE`                       | `Datadog::Tracing::Configuration::Ext::Sampling::ENV_SAMPLE_RATE`                       |
| `Datadog::Ext::Sampling`                                        | `Datadog::Tracing::Metadata::Ext::Sampling`                                             |
| `Datadog::Ext::SQL`                                             | `Datadog::Tracing::Metadata::Ext::SQL`                                                  |
| `Datadog::Ext::Test`                                            | `Datadog::Tracing::Configuration::Ext::Test`                                            |
| `Datadog::Ext::Transport::HTTP::ENV_DEFAULT_HOST`               | `Datadog::Core::Configuration::Ext::Transport::ENV_DEFAULT_HOST`                     |
| `Datadog::Ext::Transport::HTTP::ENV_DEFAULT_PORT`               | `Datadog::Tracing::Configuration::Ext::Transport::ENV_DEFAULT_PORT`                     |
| `Datadog::Ext::Transport::HTTP::ENV_DEFAULT_URL`                | `Datadog::Tracing::Configuration::Ext::Transport::ENV_DEFAULT_URL`                      |
| `Datadog::Ext::Transport`                                       | `Datadog::Transport::Ext`                                                               |
| `Datadog::GRPCPropagator`                                       | `Datadog::Tracing::Propagation::GRPC`                                                   |
| `Datadog::HTTPPropagator`                                       | `Datadog::Tracing::Propagation::HTTP`                                                   |
| `Datadog::Logger`                                               | `Datadog::Core::Logger`                                                                 |
| `Datadog::Metrics`                                              | `Datadog::Core::Metrics::Client`                                                        |
| `Datadog::PrioritySampler`                                      | `Datadog::Tracing::Sampling::PrioritySampler`                                           |
| `Datadog::Quantization`                                         | `Datadog::Contrib::Utils::Quantization`                                                 |
| `Datadog::RateByKeySampler`                                     | `Datadog::Tracing::Sampling::RateByKeySampler`                                          |
| `Datadog::RateByServiceSampler`                                 | `Datadog::Tracing::Sampling::RateByServiceSampler`                                      |
| `Datadog::RateSampler`                                          | `Datadog::Tracing::Sampling::RateSampler`                                               |
| `Datadog::Runtime`                                              | `Datadog::Core::Runtime`                                                                |
| `Datadog::Sampler`                                              | `Datadog::Tracing::Sampling::Sampler`                                                   |
| `Datadog::Tagging::Analytics`                                   | `Datadog::Tracing::Metadata::Analytics`                                                 |
| `Datadog::Tagging::Metadata`                                    | `Datadog::Tracing::Metadata::Tagging`                                                   |
| `Datadog::ThreadSafeBuffer`                                     | `Datadog::Core::Buffer::ThreadSafe`                                                     |
| `Datadog::Utils`                                                | `Datadog::Core::Utils`                                                                  |
| `Datadog::Vendor::ActiveRecord`                                 | `Datadog::Contrib::ActiveRecord::Vendor`                                                |
| `Datadog::Vendor::Multipart`                                    | `Datadog::Core::Vendor::Multipart`                                                      |
| `Datadog::Worker`                                               | `Datadog::Core::Worker`                                                                 |
| `Datadog::Workers`                                              | `Datadog::Core::Workers`                                                                |

<h3 id="1.0-appendix-breaking-changes">Breaking changes</h3>

| **Category**                          | **Type** | **Description**                                                                                                     | **Change / Alternative**                                                                                                                                                  |
|---------------------------------------|----------|---------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| General                               | Changed  | Many constants have been moved from `Datadog` to `Datadog::Core`, `Datadog::Tracing`                                | Update your references to these [new namespaces](#1.0-appendix-namespace-constants) where appropriate.                                                                    |
| General                               | Changed  | Some `require` paths have been moved from `ddtrace` to `datadog`                                                    | Update your references to these [new paths](#1.0-appendix-namespace-requires) where appropriate.                                                                          |
| General                               | Removed  | Support for trace agent API v0.2                                                                                    | Use v0.4 instead (default behavior.)                                                                                                                                      |
| General                               | Removed  | `Datadog.configure` can no longer be called without a block                                                         | Remove uses of `Datadog.configure` without a block.                                                                                                                       |
| CI API                                | Changed  | `DD_TRACE_CI_MODE_ENABLED` environment variable is now `DD_TRACE_CI_ENABLED`                                        | Use `DD_TRACE_CI_ENABLED` instead.                                                                                                                                        |
| Configuration                         | Changed  | Many settings have been namespaced under specific categories                                                        | Update your configuration to these [new settings](#1.0-configuration-settings) where appropriate.                                                                         |
| Configuration                         | Removed  | `Datadog.configure(client, options)`                                                                                | Use `Datadog.configure_onto(client, options)` instead.                                                                                                           |
| Configuration                         | Removed  | `DD_#{integration}_ANALYTICS_ENABLED` and `DD_#{integration}_ANALYTICS_SAMPLE_RATE` environment variables           | Use `DD_TRACE_#{integration}_ANALYTICS_ENABLED` and `DD_TRACE_#{integration}_ANALYTICS_SAMPLE_RATE` instead.                                                              |
| Configuration                         | Removed  | `DD_PROPAGATION_INJECT_STYLE` and `DD_PROPAGATION_EXTRACT_STYLE` environment variables                              | Use `DD_TRACE_PROPAGATION_STYLE_INJECT` and `DD_TRACE_PROPAGATION_STYLE_EXTRACT` instead.                                                                                             |
| Integrations                          | Changed  | `-` in HTTP header tag names are kept, and no longer replaced with `_`                                              | For example: `http.response.headers.content_type` is changed to `http.response.headers.content-type`.                                                                     |
| Integrations                          | Changed  | `Contrib::Configurable#default_configuration` moved to `Tracing::Contrib::Configurable#new_configuration`           | Use `Tracing::Contrib::Configurable#new_configuration` instead.                                                                                                           |
| Integrations                          | Changed  | `Datadog.configuration.registry` moved to `Datadog.registry`                                                        | Use `Datadog.registry` instead.                                                                                                                                           |
| Integrations                          | Changed  | `service_name` option from each integration uses the default service name, unless it represents an external service | Set `c.service` or `DD_SERVICE`, and remove `service_name` option from integration to inherit default service name. Set `service_name` option on integration to override. |
| Integrations                          | Removed  | `tracer` integration option from all integrations                                                                   | Remove this option from your configuration.                                                                                                                               |
| Integrations - ActiveJob              | Removed  | `log_injection` option                                                                                              | Use `c.tracing.log_injection` instead.                                                                                                                                    |
| Integrations - ActiveModelSerializers | Removed  | service_name configuration                                                                                          | Remove this option from your configuration.                                                                                                                               |
| Integrations - ConcurrentRuby         | Removed  | unused option `service_name`                                                                                        | Remove this option from your configuration.                                                                                                                               |
| Integrations - Presto                 | Changed  | `out.host` tag now contains only client hostname. Before it contained `"#{hostname}:#{port}"`.                      |                                                                                                                                                                           |
| Integrations - Rails                  | Changed  | `service_name` does not propagate to sub-components (e.g. `c.use :rails, cache_service: 'my-cache'`)                | Use `c.service` instead.                                                                                                                                                  |
| Integrations - Rails                  | Changed  | Sub-components service_name options are now consistently called `:service_name`                                     | Update your configuration to use `:service_name`.                                                                                                                         |
| Integrations - Rails                  | Changed  | Trace-logging correlation is enabled by default                                                                     | Can be disabled using the environment variable `DD_LOGS_INJECTION=false`.                                                                                                 |
| Integrations - Rails                  | Removed  | `log_injection` option.                                                                                             | Use global `c.tracing.log_injection` instead.                                                                                                                             |
| Integrations - Rails                  | Removed  | `orm_service_name` option.                                                                                          | Remove this option from your configuration.                                                                                                                               |
| Integrations - Rails                  | Removed  | 3.0 and 3.1 support.                                                                                                | Not supported.                                                                                                                                                            |
| Integrations - Resque                 | Removed  | `workers` option. (All Resque workers are now automatically instrumented.)                                          | Remove this option from your configuration.                                                                                                                               |
| Tracing API                           | Changed  | `Correlation#to_s` to `Correlation#to_log_format`                                                                   | Use `Datadog::Tracing.log_correlation` instead.                                                                                                                           |
| Tracing API                           | Changed  | `Tracer#trace` implements keyword args                                                                              | Omit invalid options from `trace` calls.                                                                                                                                  |
| Tracing API                           | Changed  | Distributed tracing takes and returns `TraceDigest` instead of `Context`                                            | Update your usage of distributed tracing to use `continue_from` and `to_digest`.                                                                                          |
| Tracing API                           | Changed  | Rules for RuleSampler now return `TraceOperation` instead of `Span`                                                 | Update Rule sampler usage to use `TraceOperation`.                                                                                                                        |
| Tracing API                           | Changed  | Trace processors return `TraceSegment` instead of `Array[Span]`                                                     | Update pipeline callbacks to use `TraceSegment instead.                                                                                                                   |
| Tracing API                           | Removed  | `child_of:` option from `Tracer#trace`                                                                              | Not supported.                                                                                                                                                            |
| Tracing API                           | Removed  | `Datadog.tracer`                                                                                                    | Use methods in `Datadog::Tracing` instead.                                                                                                                                |
| Tracing API                           | Removed  | `Pin.get_from(client)`                                                                                              | Use `Datadog::Tracing.configure_for(client)` instead.                                                                                                                     |
| Tracing API                           | Removed  | `Pin.new(service, config: { option: value }).onto(client)`                                                          | Use `Datadog.configure_onto(client, service_name: service, option: value)` instead.                                                                              |
| Tracing API                           | Removed  | `Pipeline.before_flush`                                                                                             | Use `Datadog::Tracing.before_flush` instead.                                                                                                                              |
| Tracing API                           | Removed  | `SpanOperation#context`                                                                                             | Use `Datadog::Tracing.active_trace` instead.                                                                                                                              |
| Tracing API                           | Removed  | `SpanOperation#parent`/`SpanOperation#parent=`                                                                      | Not supported.                                                                                                                                                            |
| Tracing API                           | Removed  | `SpanOperation#sampled`                                                                                             | Use `Datadog::Tracing::TraceOperation#sampled?` instead.                                                                                                                           |
| Tracing API                           | Removed  | `Tracer#active_correlation.to_log_format`                                                                           | Use `Datadog::Tracing.log_correlation` instead.                                                                                                                           |
| Tracing API                           | Removed  | `Tracer#active_correlation`                                                                                         | Use `Datadog::Tracing.correlation` instead.                                                                                                                               |
| Tracing API                           | Removed  | `Tracer#active_root_span`                                                                                           | Use `Datadog::Tracing.active_trace` instead.                                                                                                                              |
| Tracing API                           | Removed  | `Tracer#build_span`                                                                                                 | Use `Datadog::Tracing.trace` instead.                                                                                                                                     |
| Tracing API                           | Removed  | `Tracer#call_context`                                                                                               | Use `Datadog::Tracing.active_trace` instead.                                                                                                                              |
| Tracing API                           | Removed  | `Tracer#configure`                                                                                                  | Not supported.                                                                                                                                                            |
| Tracing API                           | Removed  | `Tracer#services`                                                                                                   | Not supported.                                                                                                                                                            |
| Tracing API                           | Removed  | `Tracer#set_service_info`                                                                                           | Not supported.                                                                                                                                                            |
| Tracing API                           | Removed  | `Tracer#start_span`                                                                                                 | Use `Datadog::Tracing.trace` instead.                                                                                                                                     |
| Tracing API                           | Removed  | `Writer#write` and `SyncWriter#write` `services` argument                                                           | Not supported.                                                                                                                                                            |

# Upgrading ddtrace

# From 0.x to 1.0

- [Namespacing & the public API](#namespacing--the-public-api)
- [Configuration](#configuration)
- [Instrumentation](#instrumentation)
- [Full list of breaking changes](#full-list-of-breaking-changes)

Upgrading `ddtrace` from 0.x to 1.x introduces some changes to namespacing, the public API, and the underlying trace data structure.

Here's a list of the most common changes you may encounter:

## Namespacing & the public API

To avoid naming conflicts with new Datadog features and products, many of the constants and functions defined directly under `Datadog` have moved to `Datadog::Tracing`.

The most commonly used functions have been moved to our [public API](), with accompanying documentation. e.g.

```ruby
### Old 0.x ###
Datadog.configure
Datadog.tracer.trace
Datadog.tracer.active_span
Datadog.tracer.active_correlation.to_s

### New 1.0 ###
Datadog::Tracing.configure
Datadog::Tracing.trace
Datadog::Tracing.active_span
Datadog::Tracing.log_correlation
# ...and more...
```

Use of some of the functions in this API will be described in use cases below. We hope this API will be a much simpler way to implement tracing in your application. Please check out [our documentation]() for detailed specifications.

## Configuration

### Settings have been namespaced

Configuration settings have been sorted into smaller configuration groups, by product.

 - `Datadog.configure { |c| c.tracing }`: Trace configuration settings
 - `Datadog.configure { |c| c.profiling }`: Profiling configuration settings
 - `Datadog.configure { |c| c.ci }`: CI configuration settings

Existing applications should update their configuration files and settings accordingly. For example:

```ruby
# config/initializers/datadog.rb
require 'ddtrace'

### Old 0.x ###
Datadog.configure do |c|
  # Global settings
  c.diagnostics.debug = true
  c.service = 'billing-api'

  # Profiling settings
  c.profiling.enabled = true

  # Tracer settings
  c.analytics.enabled = true
  c.runtime_metrics.enabled = true
  c.tracer.hostname = '127.0.0.1'
  c.tracer.port = 8126

  # CI settings
  c.ci_mode = (ENV['DD_ENV'] == 'ci')

  # Instrumentation
  c.instrument :rails
  c.instrument :redis, service_name: 'billing-redis'
  c.instrument :resque
end

### New 1.0 ###
Datadog.configure do |c|
  # Global settings
  c.agent.hostname = '127.0.0.1'
  c.agent.port = 8126
  c.diagnostics.debug = true
  c.service = 'billing-api'

  # Profiling settings
  c.profiling.enabled = true

  # Tracer settings
  c.tracing.analytics.enabled = true
  c.tracing.runtime_metrics.enabled = true

  # CI settings
  c.ci.enabled = (ENV['DD_ENV'] == 'ci')

  # Instrumentation
  c.instrument :rails
  c.instrument :redis, service_name: 'billing-redis'
  c.instrument :resque
end
```

List of all settings that changed:

 - `ci_mode` --> `ci.enabled`
 - `tracer.hostname` --> `agent.hostname`
 - `tracer.port` --> `agent.port`
 - **TODO: Add more here!**

### Activating instrumentation

The `use` function has been renamed to `instrument`:

```ruby
### Old 0.x ###
Datadog.configure do |c|
  c.use :rails
end

### New 1.0 ###
Datadog.configure do |c|
  c.instrument :rails
end
```

## Instrumentation

### Manual tracing & trace model

Manual tracing is now done through the public API.

Whereas in 0.x, the block would yield a `Datadog::Span` as `span`, in 1.0, the block yields a `Datadog::SpanOperation` as `span` and `Datadog::TraceOperation` as `trace`.

```ruby
### Old 0.x ###
Datadog.tracer.trace('my.job') do |span|
  # Do work...
  # span => #<Datadog::Span>
end

### New 1.0 ###
Datadog::Tracing.trace('my.job') do |span, trace|
  # Do work...
  # span => #<Datadog::SpanOperation>
  # trace => #<Datadog::TraceOperation>
end
```

The yielded `span` is nearly identical in behavior, except access to some fields (like `context`) been removed. Instead, the `trace`, which models the trace itself, grants access to new functions.

For more details about new behaviors and the trace model, see [this pull request](https://github.com/DataDog/dd-trace-rb/pull/1783).

### Accessing trace state

The public API provides new functions to access active trace data:

```ruby
# Retuns the active TraceOperation for the current thread
Datadog::Tracing.active_trace
# Returns the active SpanOperation for the current thread
Datadog::Tracing.active_span
# Returns an immutable set of identifiers for the current trace state
Datadog::Tracing.correlation
```

Use of `active_root_span` has been removed.

### Distributed tracing

Previously, distributed tracing required building new `Datadog::Context` objects, then replacing the context within the tracer.

Instead, users utilize `TraceDigest` objects derived from a trace. This object which represents the state of a trace. It can be used to propagate a trace across execution boundaries (processes, threads), or to continue a trace locally.

```ruby
# Get trace digest
trace = Datadog::Tracing.active_trace
trace_digest = trace.to_digest

# Continue a trace: explicit continuation
# Inherits trace properties from the trace digest
Datadog::Tracing.trace('my.job', continue_from: trace_digest) do |span, trace|
  trace.id == trace_digest.trace_id
end

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

#### Propagation over HTTP/gRPC

To propagate a local trace to a remote service:

```ruby
# HTTP
# `headers` should behave like a Hash
Datadog::HTTPPropagator.inject!(trace_digest, headers)

# gRPC
# `headers` should behave like a Hash
Datadog::GRPCPropagator.inject!(trace_digest, headers)
```

To continue a propagated trace locally:

```ruby
# HTTP
digest = HTTPPropagator.extract(request.env)
digest # => #<Datadog::TraceDigest>

# gRPC
digest = Datadog::GRPCPropagator.extract(metadata)
digest # => #<Datadog::TraceDigest>
```

#### Propagation between threads

Traces do not implicitly propagate across threads, as they are considered different execution contexts.

However, if you wish to do this, trace propagation across threads is similar to cross-process. A `TraceDigest` should be produced and consumed.

NOTE: The same `TraceOperation` object should never be shared between threads; this would create race conditions.

```ruby
# Get trace digest
trace = Datadog::Tracing.active_trace

# NOTE: We must produce the digest BEFORE starting the thread.
#       Otherwise if its lazily evaluated within the thread,
#       the thread's trace may follow the wrong parent span.
trace_digest = trace.to_digest

Thread.new do
  # Inherits trace properties from the trace digest
  Datadog::Tracing.trace('my.job', continue_from: trace_digest) do |span, trace|
    trace.id == trace_digest.trace_id
  end
end
```

### Sampling

Accessing `call_context` to set explicit sampling has been removed.

Instead, use the `TraceOperation` to set the sampling decision.

```ruby
# From within the trace:
Datadog::Tracing.trace('web.request') do |span, trace|
  trace.reject! if env.path == '/healthcheck'
end

# From outside the trace:
Datadog::Tracing.keep! # Keeps current trace
Datadog::Tracing.reject! # Drops current trace
```

### Processing pipeline

When using a trace processor in the processing pipeline, the block yields a `TraceSegment` as `trace` instead of `Array[Datadog::Span]`. This object can be modified by reference.

```ruby
Datadog::Tracing.before_flush do |trace|
   # Processing logic...
   trace
end
```

### Service naming

In 0.x, The `service` field on spans generated by Datadog integrations would typically default to the package name, e.g. `http` or `sidekiq`. This would often result in many "services" being generated by one application, one for each instrumented package. Users would often rectify this by overriding the `service_name` setting on each integration to get matching `service` names.

To remedy this in later 0.x versions, we introduced the global `service` name setting (also set via `DD_SERVICE`), which is the recommended way to set the name of your application. However, the Datadog integrations still did not employ this field.

In 1.0, spans now inherit the global `service` name by default, unless otherwise explicitly set. This means for spans generated by Datadog integrations, they will default to the global `service` name, unless the `service_name` setting is configured for that integration.

Spans that describe external services (e.g. `mysql`), will still default to some other name that describes the external service, so as to avoid mixing up spans that belong to different applications.

As a result, expect the following code & trace in 0.x:

```ruby
Datadog.configure do |c|
  c.service = 'billing-api'
  c.use :rails
end
```

*(Picture of 0.x trace here)*

To reflect the following trace instead:

*(Picture of 1.0 trace here)*

### Removed `Datadog.tracer`

Many of the functions accessed directly through `Datadog.tracer` have been moved to `Datadog::Tracing` instead.

### Context

Direct usage of `Datadog::Context` has been removed. Previously, it was used to modify or access active trace state. Most of these use cases have been replaced by `TraceOperation` and have been given new APIs.

## Full list of breaking changes

| **Category**  | **Type** | **Description**                                                                                                      | **Change / Alternative**                                                                                                                                                  |
|---------------|----------|----------------------------------------------------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| General       | Changed  | Many constants have been moved from `Datadog` to `Datadog::Core`, `Datadog::Tracing`, `Datadog::Profiling`           | Update your references to these new namespaces where appropriate.                                                                                                         |
| General       | Removed  | `Datadog.tracer`                                                                                                     | Use methods in `Datadog::Tracing` instead.                                                                                                                                |
| General       | Removed  | Support for trace agent API v0.2.                                                                                    | Use v0.4 instead (default behavior)                                                                                                                                       |
| CI API        | Changed  | `DD_TRACE_CI_MODE_ENABLED` environment variable is now `DD_TRACE_CI_ENABLED`.                                        | Use `DD_TRACE_CI_ENABLED` instead.                                                                                                                                        |
| Configuration | Changed  | `Datadog.configuration` raises errors if you attempt to access non-global settings.                                  | Use `Datadog::Tracing.configuration`, `Datadog::Profiling.configuration`, or `Datadog::CI.configuration` when appropriate.                                                |
| Configuration | Changed  | `Datadog.configure` raises errors if you attempt to configure non-global settings.                                   | Use `Datadog::Tracing.configure`, `Datadog::Profiling.configure`, or `Datadog::CI.configure` when appropriate.                                                            |
| Configuration | Changed  | `c.tracer.hostname` moved to `c.agent.host`.                                                                         | Use `c.agent.host` instead.                                                                                                                                               |
| Configuration | Changed  | `c.tracer.port` moved to `c.agent.port`.                                                                             | Use `c.agent.port` instead.                                                                                                                                               |
| Configuration | Removed  | `c.tracer.transport_options(option: value)`.                                                                         | Use `c.tracer.transport_options { \|t\| t.option = value }` instead.                                                                                                        |
| Configuration | Removed  | `c.analytics_enabled` option                                                                                         | Use `c.tracing.analytics.enabled` instead.                                                                                                                                |
| Configuration | Removed  | `c.logger = custom_object` keyword options                                                                           | Use `c.logger.instance = custom_object` instead.                                                                                                                          |
| Configuration | Removed  | `c.tracer(option: value)` keyword options                                                                            | Use `c.tracing.option = value` instead.                                                                                                                                   |
| Configuration | Removed  | `c.runtime_metrics(option: value)` keyword options                                                                   | Use `c.runtime_metrics.option = value` instead.                                                                                                                           |
| Configuration | Removed  | `c.runtime_metrics_enabled` option                                                                                   | Use `c.runtime_metrics.enabled` instead.                                                                                                                                  |
| Configuration | Removed  | `Datadog.configure(client, options)`                                                                                 | Use `Datadog::Tracing.configure_onto(client, options)` instead.                                                                                                           |
| Configuration | Removed  | `DD_#{integration}_ANALYTICS_ENABLED` and `DD_#{integration}_ANALYTICS_SAMPLE_RATE` environment variables            | Use `DD_TRACE_#{integration}_ANALYTICS_ENABLED` and `DD_TRACE_#{integration}_ANALYTICS_SAMPLE_RATE` instead                                                               |
| Configuration | Removed  | `DD_PROPAGATION_INJECT_STYLE` and `DD_PROPAGATION_EXTRACT_STYLE` environment variables                               | Use `DD_PROPAGATION_STYLE_INJECT` and `DD_PROPAGATION_STYLE_EXTRACT` instead                                                                                              |
| Configuration | Removed  | Setting a hash on `c.tracer.transport_options`                                                                       | Use a proc instead to pass the options to the desired adapter                                                                                                             |
| Configuration | Removed  | Unused profiler configuration `c.profiling.exporter.transport_options`.                                              | Not supported.                                                                                                                                                            |
| Integrations  | Changed  | `-` in HTTP header tag names are kept, and no longer replaced with `_`.                                              | For example: `http.response.headers.content_type` is changed to `http.response.headers.content-type`.                                                                     |
| Integrations  | Changed  | `Contrib::Configurable#default_configuration` moved to `Tracing::Contrib::Configurable#new_configuration`.           | Use `Tracing::Contrib::Configurable#new_configuration` instead.                                                                                                           |
| Integrations  | Changed  | `Datadog.configuration.registry` moved to `Datadog.registry`.                                                        | Use `Datadog.registry` instead.                                                                                                                                           |
| Integrations  | Changed  | `Datadog::Ext::Integration` to `Datadog::Ext::Metadata`                                                              | Update your references.                                                                                                                                                   |
| Integrations  | Changed  | `service_name` option from each integration uses the default service name, unless it represents an external service. | Set `c.service` or `DD_SERVICE`, and remove `service_name` option from integration to inherit default service name. Set `service_name` option on integration to override. |
| Integrations  | Changed  | Presto: `out.host` tag now contains only client hostname. Before it contained `""#{hostname}:#{port}""`.             |                                                                                                                                                                           |
| Integrations  | Changed  | Rails: service_name does not propagate to sub-components (e.g. `c.use :rails, cache_service: 'my-cache'`).           | Use `c.service` instead.                                                                                                                                                  |
| Integrations  | Changed  | Rails: Sub-components service_name options are now consistently called `:service_name`.                              | Update your configuration to use `:service_name`                                                                                                                          |
| Integrations  | Changed  | Rails: Trace-logging correlation is enabled by default.                                                              | Can be disabled using the environment variable `DD_LOGS_INJECTION=false`.                                                                                                 |
| Integrations  | Removed  | `tracer` integration option from all integrations.                                                                   | Remove this option from your configuration                                                                                                                                |
| Integrations  | Removed  | ActiveJob: `log_injection` option.                                                                                   | Use `c.tracing.log_injection` instead.                                                                                                                                    |
| Integrations  | Removed  | ActiveModelSerializers: service_name configuration.                                                                  | Remove this option from your configuration                                                                                                                                |
| Integrations  | Removed  | ConcurrentRuby: unused option `service_name`.                                                                        | Remove this option from your configuration                                                                                                                                |
| Integrations  | Removed  | Rails: 3.0 and 3.1 support.                                                                                          | Not supported.                                                                                                                                                            |
| Integrations  | Removed  | Rails: `log_injection` option.                                                                                       | Use global `c.tracing.log_injection` instead.                                                                                                                             |
| Integrations  | Removed  | Rails: `orm_service_name` option.                                                                                    | Remove this option from your configuration                                                                                                                                |
| Integrations  | Removed  | Resque: `workers` option. (All Resque workers are now automatically instrumented.)                                   | Remove this option from your configuration                                                                                                                                |
| Profiling API | Changed  | `require 'ddtrace/profiling/preload'` moved to `require 'datadog/profiling/preload'`.                                | Use `require 'datadog/profiling/preload'` instead.                                                                                                                        |
| Tracing API   | Changed  | `Correlation#to_s` to `Correlation#to_log_format`                                                                    | Use `Datadog::Tracing.log_correlation` instead.                                                                                                                           |
| Tracing API   | Changed  | `Tracer#trace` implements keyword args.                                                                              | Omit invalid options from `trace` calls.                                                                                                                                  |
| Tracing API   | Changed  | Distributed tracing takes and yields `TraceDigest` instead of `Context`                                              | Update your usage of distributed tracing to use `continue_from` and `to_digest`.                                                                                          |
| Tracing API   | Changed  | Renamed `ContextFlush` (and configuration) to `TraceFlush`                                                           | Update your references.                                                                                                                                                   |
| Tracing API   | Changed  | Rules for RuleSampler now yield `TraceOperation` instead of `Span`                                                   | Update Rule sampler usage to use `TraceOperation`.                                                                                                                        |
| Tracing API   | Changed  | Trace processors yield `TraceSegment` instead of `Array[Span]`.                                                      | Update pipeline callbacks to use `TraceSegment instead.                                                                                                                   |
| Tracing API   | Changed  | Various constant names in the `Ext` namespace for sampling, distributed tracing.                                     | Update your references.                                                                                                                                                   |
| Tracing API   | Removed  | `child_of:` option from `Tracer#trace`                                                                               | Not supported.                                                                                                                                                            |
| Tracing API   | Removed  | `Pipeline.before_flush`                                                                                              | Use `Datadog::Tracing.before_flush` instead.                                                                                                                              |
| Tracing API   | Removed  | `SpanOperation#allocations`. This value could contain inaccuracies and was expensive to calculate.                   | Not supported.                                                                                                                                                            |
| Tracing API   | Removed  | `SpanOperation#context`                                                                                              | Use `Datadog::Tracing.active_trace` instead.                                                                                                                              |
| Tracing API   | Removed  | `SpanOperation#parent`/`SpanOperation#parent=`                                                                       | Not supported.                                                                                                                                                            |
| Tracing API   | Removed  | `SpanOperation#sampled`                                                                                              | Use `Datadog::TraceOperation#sampled?` instead.                                                                                                                           |
| Tracing API   | Removed  | `Tracer#active_correlation`                                                                                          | Use `Datadog::Tracing.correlation` instead.                                                                                                                               |
| Tracing API   | Removed  | `Tracer#active_correlation.to_log_format`                                                                            | Use `Datadog::Tracing.log_correlation` instead.                                                                                                                           |
| Tracing API   | Removed  | `Tracer#active_root_span`                                                                                            | Use `Datadog::Tracing.active_trace` instead.                                                                                                                              |
| Tracing API   | Removed  | `Tracer#build_span`                                                                                                  | Use `Datadog::Tracing.trace` instead.                                                                                                                                     |
| Tracing API   | Removed  | `Tracer#call_context`                                                                                                | Use `Datadog::Tracing.active_trace` instead.                                                                                                                              |
| Tracing API   | Removed  | `Tracer#configure`                                                                                                   | Not supported.                                                                                                                                                            |
| Tracing API   | Removed  | `Tracer#services`                                                                                                    | Not supported.                                                                                                                                                            |
| Tracing API   | Removed  | `Tracer#set_service_info`                                                                                            | Not supported.                                                                                                                                                            |
| Tracing API   | Removed  | `Tracer#start_span`                                                                                                  | Use `Datadog::Tracing.trace` instead.                                                                                                                                     |
| Tracing API   | Removed  | `Writer#write` and `SyncWriter#write` `services` argument                                                            | Not supported.                                                                                                                                                            |

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

**TODO: Replace with table instead**

### General

- **Removed**: Tracer transport v0.2. Use transport v0.4 instead, which is the default.

### Configuration

- **Changed**: `Datadog.configure` raises errors if you attempt to configure non-global settings. Use `Datadog::Tracing.configure`, `Datadog::Profiling.configure`, or `Datadog::CI.configure` when appropriate.
- **Changed**: `Datadog.configuration` raises errors if you attempt to access non-global settings. Use `Datadog::Tracing.configuration`, `Datadog::Profiling.configuration`, or `Datadog::CI.configuration` when appropriate.
- **Removed**: `Datadog.tracer` instance. Use methods in `Datadog::Tracing` instead.
- **Removed**: `Datadog.configure(client, options)`. Use `Datadog::Tracing.configure_onto(client, options)` instead.
- **Removed**: `#use` option. Use `#instrument` instead.
- **Changed**: `DD_PROPAGATION_INJECT_STYLE` and `DD_PROPAGATION_EXTRACT_STYLE` environment variables renamed to `DD_PROPAGATION_STYLE_INJECT` and `DD_PROPAGATION_STYLE_EXTRACT`, respectively.
- **Changed**: `DD_#{integration}_ANALYTICS_ENABLED` and `DD_#{integration}_ANALYTICS_SAMPLE_RATE` environment variables renamed to `DD_TRACE_#{integration}_ANALYTICS_ENABLED` and `DD_TRACE_#{integration}_ANALYTICS_SAMPLE_RATE`, respectively, for all integrations. For example, `DD_GRPC_ANALYTICS_ENABLED` and `DD_GRPC_ANALYTICS_SAMPLE_RATE` are renamed to `DD_TRACE_GRPC_ANALYTICS_ENABLED` and `DD_TRACE_GRPC_ANALYTICS_SAMPLE_RATE`.
- **Removed**: `c.analytics_enabled` option. Use `c.analytics.enabled` instead.
- **Removed**: `c.tracer option: value` keyword options. Use `c.tracing.option = value` instead.
- **Removed**: `c.logger = custom_object` keyword options. Use `c.logger.instance = custom_object` instead.
- **Removed**: Unused profiler configuration `c.profiling.exporter.transport_options`.

### Integrations

- **Changed**: Rails: Trace-Logging correlation is enabled by default. Can be disabled using the environment variable `DD_LOGS_INJECTION=false`.
- **Changed**: `Datadog::Ext::Integration` to `Datadog::Ext::Metadata`
- **Changed**: The `service_name` option from each integration uses the default service name, unless it represents an external service. Users should set `c.service` or `DD_SERVICE` to configure the service name for these integrations. `service_name` for all integrations can still be configured.
  - For embedded processes like "sidekiq", when users want to distinguish these processes as different services, they should set a different `DD_SERVICE` when starting that process, or add logic to their `Datadog.configure` block to determine and set `c.service` when the process loads.
  - Rails still tries to detect the Rails application name, if a service name is not configured in `ddtrace`.
- **Removed**: Active Model Serializers: service name configuration.
- **Removed**: ConcurrentRuby: unused option `service_name`.
- **Changed**: Presto: `out.host` tag now contains only client hostname. Before it contained `"#{hostname}:#{port}"`.
- **Removed**: Rails: 3.0 and 3.1 support. Rails 3.2 or newer continue to be supported.
- **Removed**: Rails: service name propagation to sub-components (e.g. `c.use :rails, cache_service: 'my-cache'`).
- **Removed**: Rails: Sub-components service name options are now consistently called `:service_name`.
- **Removed**: Rails: `orm_service_name` option.
- **Removed**: Rails: `log_injection` option. Use global `c.log_injection` instead.
- **Removed**: ActiveJob: `log_injection` option. Use global `c.log_injection` instead.
- **Removed**: Resque: `workers` option. All Resque workers are now automatically instrumented.
- **Removed**: `tracer` integration option. All integrations now use the global tracer instance.
- **Changed**: `Datadog.configuration.registry` moved to `Datadog.registry`.

### Tracing API

 - **Changed**: `Tracer#trace` implements keyword args. You must splat optional args.
 - **Changed**: `Correlation#to_s` to `Correlation#to_log_format`
 - **Changed**: Renamed `ContextFlush` (and configuration) to `TraceFlush`
 - **Changed**: Trace processors yield `TraceSegment` instead of `Array[Span]`.
 - **Changed**: Distributed tracing takes and yields `TraceDigest` instead of `Context`
 - **Changed**: Rules for RuleSampler now yield `TraceOperation` instead of `SpanOperation`
 - **Changed**: Various constant names for sampling, distributed tracing.
 - **Removed**: `child_of:` option from `Tracer#trace`. No replacement.
 - **Removed**: `Tracer#configure`. No replacement.
 - **Removed**: `Tracer#start_span`. Use `Datadog::Tracing.trace` instead.
 - **Removed**: `Tracer#build_span`. No replacement.
 - **Removed**: `Tracer#active_root_span`. No replacement.
 - **Removed**: `Tracer#call_context`. No replacement.
 - **Removed**: Unused `Tracer#services`.
 - **Removed**: Unused `Tracer#set_service_info`.
 - **Removed**: `SpanOperation#parent` and `SpanOperation#parent=`. Use `SpanOperation#parent_id` and `SpanOperation#parent_id=` instead, respectively.
 - **Removed**: `SpanOperation#context`. No replacement.
 - **Removed**: `SpanOperation#sampled`. Use `Datadog::TraceOperation#sampled?` instead.
 - **Removed**: Unused `Writer#write` and `SyncWriter#write` `services` argument.

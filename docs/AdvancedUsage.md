# Advanced Usage

## Adjusting tracer settings

To change the default behavior of the Datadog tracer, you can provide custom options inside the `Datadog.configure` block:

```ruby
# config/initializers/datadog-tracer.rb

Datadog.configure do |c|
  c.tracer option_name: option_value, ...
end
```

Available options are:

 - `enabled`: defines if the `tracer` is enabled or not. If set to `false` the code could be still instrumented because of other settings, but no spans are sent to the local trace agent.
 - `debug`: set to true to enable debug logging.
 - `hostname`: set the hostname of the trace agent.
 - `port`: set the port the trace agent is listening on.
 - `env`: set the environment. Rails users may set it to `Rails.env` to use their application settings.
 - `tags`: set global tags that should be applied to all spans. Defaults to an empty hash
 - `log`: defines a custom logger.
 - `partial_flush`: set to `true` to enable partial trace flushing (for long running traces.) Disabled by default. *Experimental.*

### Custom logging

By default, all logs are processed by the default Ruby logger. When using Rails, you should see the messages in your application log file.

Datadog client log messages are marked with `[ddtrace]` so you should be able to isolate them from other messages.

Additionally, it is possible to override the default logger and replace it by a custom one. This is done using the `log` attribute of the tracer.

```ruby
f = File.new("my-custom.log", "w+")           # Log messages should go there
Datadog.configure do |c|
  c.tracer log: Logger.new(f)                 # Overriding the default tracer
end

Datadog::Tracer.log.info { "this is typically called by tracing code" }
```

## Environment and tags

By default, the trace agent (not this library, but the program running in the background collecting data from various clients) uses the tags set in the agent config file, see our [environments tutorial](https://app.datadoghq.com/apm/docs/tutorials/environments) for details.

These values can be overridden at the tracer level:

```ruby
Datadog.configure do |c|
  c.tracer tags: { 'env' => 'prod' }
end
```

This enables you to set this value on a per tracer basis, so you can have for example several applications reporting for different environments on the same host.

Ultimately, tags can be set per span, but `env` should typically be the same for all spans belonging to a given trace.

## Sampling

The tracer can perform trace sampling. While the trace agent already samples traces to reduce bandwidth usage, client sampling reduces the performance overhead.

`Datadog::RateSampler` samples a ratio of the traces. For example:

```ruby
# Sample rate is between 0 (nothing sampled) to 1 (everything sampled).
sampler = Datadog::RateSampler.new(0.5) # sample 50% of the traces
Datadog.configure do |c|
  c.tracer sampler: sampler
end
```

### Priority sampling

Priority sampling decides whether to keep a trace by using a priority attribute propagated for distributed traces. Its value indicates to the Agent and the backend about how important the trace is.

The sampler can set the priority to the following values:

 - `Datadog::Ext::Priority::AUTO_REJECT`: the sampler automatically decided to reject the trace.
 - `Datadog::Ext::Priority::AUTO_KEEP`: the sampler automatically decided to keep the trace.

Priority sampling is enabled by default. Enabling it ensures that your sampled distributed traces will be complete. Once enabled, the sampler will automatically assign a priority of 0 or 1 to traces, depending on their service and volume.

You can also set this priority manually to either drop a non-interesting trace or to keep an important one. For that, set the `context#sampling_priority` to:

 - `Datadog::Ext::Priority::USER_REJECT`: the user asked to reject the trace.
 - `Datadog::Ext::Priority::USER_KEEP`: the user asked to keep the trace.

When not using [distributed tracing](https://github.com/DataDog/dd-trace-rb/blob/master/docs/DistributedTracing.md), you may change the priority at any time, as long as the trace incomplete. But it has to be done before any context propagation (fork, RPC calls) to be useful in a distributed context. Changing the priority after the context has been propagated causes different parts of a distributed trace to use different priorities. Some parts might be kept, some parts might be rejected, and this can cause the trace to be partially stored and remain incomplete.

If you change the priority, we recommend you do it as soon as possible - when the root span has just been created.

```ruby
# First, grab the active span
span = Datadog.tracer.active_span

# Indicate to reject the trace
span.context.sampling_priority = Datadog::Ext::Priority::USER_REJECT

# Indicate to keep the trace
span.context.sampling_priority = Datadog::Ext::Priority::USER_KEEP
```

## Configuring the transport layer

By default, the tracer submits trace data using `Net::HTTP` to `127.0.0.1:8126`, the default location for the Datadog trace agent process. However, the tracer can be configured to send its trace data to alternative destinations, or by alternative protocols.

Some basic settings, such as hostname and port, can be configured using [tracer settings](#adjusting-tracer-settings).

#### Using the Net::HTTP adapter

The `Net` adapter submits traces using `Net::HTTP` over TCP. It is the default transport adapter.

```ruby
Datadog.configure do |c|
  c.tracer transport_options: proc do |t|
    # Hostname, port, and additional options. :timeout is in seconds.
    t.adapter :net_http, '127.0.0.1', 8126, { timeout: 1 }
  }
end
```

#### Using the Unix socket adapter

The `UnixSocket` adapter submits traces using `Net::HTTP` over Unix socket.

To use, first configure your trace agent to listen by Unix socket, then configure the tracer with:

```ruby
Datadog.configure do |c|
  c.tracer transport_options: proc { |t|
    # Provide filepath to trace agent Unix socket
    t.adapter :unix, '/tmp/ddagent/trace.sock'
  }
end
```

#### Using the transport test adapter

The `Test` adapter is a no-op transport that can optionally buffer requests. For use in test suites or other non-production environments.

```ruby
Datadog.configure do |c|
  c.tracer transport_options: proc { |t|
    # Set transport to no-op mode. Does not retain traces.
    t.adapter :test

    # Alternatively, you can provide a buffer to examine trace output.
    # The buffer must respond to '<<'.
    t.adapter :test, []
  }
end
```

#### Using a custom transport adapter

Custom adapters can be configured with:

```ruby
Datadog.configure do |c|
  c.tracer transport_options: proc { |t|
    # Initialize and pass an instance of the adapter
    custom_adapter = CustomAdapter.new
    t.adapter custom_adapter
  }
end
```

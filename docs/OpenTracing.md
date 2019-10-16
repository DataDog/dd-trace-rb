# OpenTracing

## Quickstart for setting up Datadog with OpenTracing

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

    *NOTE*: Ensure `Datadog.configure` runs only after `OpenTracing.global_tracer` has been configured, to preserve any configuration settings you may have specified.

4. (Optional) Add or activate additional instrumentation by doing either of the following:

    - Activate Datadog integration instrumentation (see [Integration instrumentation](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md)
    - Add Datadog manual instrumentation around your code (see [Manual instrumentation](https://github.com/DataDog/dd-trace-rb/blob/master/README.md#manual-instrumentation)


## Configuring Datadog tracer settings

The underlying Datadog tracer can be configured by passing options (which match `Datadog::Tracer`) when configuring the global tracer:

```ruby
# Where `options` is a Hash of options provided to Datadog::Tracer
OpenTracing.global_tracer = Datadog::OpenTracer::Tracer.new(options)
```

It can also be configured by using `Datadog.configure` described in the [Tracer settings](https://github.com/DataDog/dd-trace-rb/blob/master/docs/AdvancedUsage.md#adjusting-tracer-settings) section.

## Activating and configuring integrations

By default, configuring OpenTracing with Datadog will not automatically activate any additional instrumentation provided by Datadog. You will only receive spans and traces from OpenTracing instrumentation you have in your application.

However, additional instrumentation provided by Datadog can be activated alongside OpenTracing using `Datadog.configure`, which can be used to enhance your tracing further. To activate this, see [Integration instrumentation](https://github.com/DataDog/dd-trace-rb/blob/master/docs/Integrations.md) for more details.

## Supported serialization formats

| Type                           | Supported? | Additional information |
| ------------------------------ | ---------- | ---------------------- |
| `OpenTracing::FORMAT_TEXT_MAP` | Yes        |                        |
| `OpenTracing::FORMAT_RACK`     | Yes        | Because of the loss of resolution in the Rack format, please note that baggage items with names containing either upper case characters or `-` will be converted to lower case and `_` in a round-trip respectively. We recommend avoiding these characters or accommodating accordingly on the receiving end. |
| `OpenTracing::FORMAT_BINARY`   | No         |                        |

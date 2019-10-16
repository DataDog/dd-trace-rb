# Metrics

The tracer and its integrations can produce some additional metrics that can provide useful insight into the performance of your application. These metrics are collected with `dogstatsd-ruby`, and can be sent to the same Datadog agent to which you send your traces.

To configure your application for metrics collection:

1. [Configure your Datadog agent for StatsD](https://docs.datadoghq.com/developers/dogstatsd/#setup)
2. Add `gem 'dogstatsd-ruby'` (>= 3.3.0) to your Gemfile

## For application runtime

If runtime metrics are configured, the trace library will automatically collect and send metrics about the health of your application.

To configure runtime metrics, add the following configuration:

```ruby
# config/initializers/datadog.rb
require 'datadog/statsd'
require 'ddtrace'

Datadog.configure do |c|
  # To enable runtime metrics collection, set `true`. Defaults to `false`
  # You can also set DD_RUNTIME_METRICS_ENABLED=true to configure this.
  c.runtime_metrics_enabled = true

  # Optionally, you can configure the Statsd instance used for sending runtime metrics.
  # Statsd is automatically configured with default settings if `dogstatsd-ruby` is available.
  # You can configure with host and port of Datadog agent; defaults to 'localhost:8125'.
  c.runtime_metrics statsd: Datadog::Statsd.new
end
```

See the [Dogstatsd documentation](https://www.rubydoc.info/github/DataDog/dogstatsd-ruby/master/frames) for more details about configuring `Datadog::Statsd`.

The stats sent will include:

| Name                        | Type    | Description                                              |
| --------------------------  | ------- | -------------------------------------------------------- |
| `runtime.ruby.class_count`  | `gauge` | Number of classes in memory space.                       |
| `runtime.ruby.thread_count` | `gauge` | Number of threads.                                       |
| `runtime.ruby.gc.*`.        | `gauge` | Garbage collection statistics (one per value in GC.stat) |

In addition, all metrics include the following tags:

| Name         | Description                                             |
| ------------ | ------------------------------------------------------- |
| `language`   | Programming language traced. (e.g. `ruby`)              |
| `service`    | List of services this associated with this metric.      |

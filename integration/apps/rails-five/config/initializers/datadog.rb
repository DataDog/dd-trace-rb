require 'datadog/statsd'
require 'ddtrace'

Datadog.configure do |c|
  c.service = 'acme-rails-five'
  c.diagnostics.debug = true if Datadog::DemoEnv.feature?('debug')
  c.runtime_metrics.enabled = true if Datadog::DemoEnv.feature?('runtime_metrics')

  if Datadog::DemoEnv.feature?('tracing')
    c.tracing.analytics.enabled = true if Datadog::DemoEnv.feature?('analytics')

    c.tracing.instrument :rails
    c.tracing.instrument :redis, service_name: 'acme-redis'
    c.tracing.instrument :resque
  end

  if Datadog::DemoEnv.feature?('pprof_to_file')
    # Reconfigure transport to write pprof to file
    c.profiling.exporter.transport = Datadog::DemoEnv.profiler_file_transport
  end
end

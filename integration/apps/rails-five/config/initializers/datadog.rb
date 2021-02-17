require 'ddtrace'

Datadog.configure do |c|
  c.diagnostics.debug = true if Datadog::DemoEnv.feature?('debug')
  c.analytics_enabled = true if Datadog::DemoEnv.feature?('analytics')
  c.runtime_metrics.enabled = true if Datadog::DemoEnv.feature?('runtime_metrics')

  if Datadog::DemoEnv.feature?('tracing')
    c.use :rails, service_name: 'acme-rails-five'
    c.use :redis, service_name: 'acme-redis'
    c.use :resque, service_name: 'acme-resque'
  end

  if Datadog::DemoEnv.feature?('pprof_to_file')
    # Reconfigure transport to write pprof to file
    c.profiling.exporter.transport = Datadog::DemoEnv.profiler_file_transport
  end
end

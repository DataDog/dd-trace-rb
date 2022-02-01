require 'datadog/demo_env'
require 'ddtrace'

Datadog.configure do |c|
  c.diagnostics.debug = true if Datadog::DemoEnv.feature?('debug')
  c.runtime_metrics.enabled = true if Datadog::DemoEnv.feature?('runtime_metrics')
end

Datadog::Tracing.configure do |c|
  c.analytics.enabled = true if Datadog::DemoEnv.feature?('analytics')
end

Datadog::Profiling.configure do |c|
  if Datadog::DemoEnv.feature?('pprof_to_file')
    # Reconfigure transport to write pprof to file
    c.profiling.exporter.transport = Datadog::DemoEnv.profiler_file_transport
  end
end

require 'datadog/demo_env'
require 'datadog'

Datadog.configure do |c|
  c.diagnostics.debug = true if Datadog::DemoEnv.feature?('debug')
  c.runtime_metrics.enabled = true if Datadog::DemoEnv.feature?('runtime_metrics')
  c.tracing.analytics.enabled = true if Datadog::DemoEnv.feature?('analytics')
  if Datadog::DemoEnv.feature?('pprof_to_file')
    # Reconfigure transport to write pprof to file
    c.profiling.exporter.transport = Datadog::DemoEnv.profiler_file_transport
  end
end

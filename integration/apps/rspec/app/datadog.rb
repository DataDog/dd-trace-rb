require 'datadog/demo_env'
require 'datadog/ci'

Datadog.configure do |c|
  c.service = 'acme-rspec'
  c.diagnostics.debug = true if Datadog::DemoEnv.feature?('debug')
  c.runtime_metrics.enabled = true if Datadog::DemoEnv.feature?('runtime_metrics')

  if Datadog::DemoEnv.feature?('tracing')
    c.tracing.analytics.enabled = true if Datadog::DemoEnv.feature?('analytics')
  end

  if Datadog::DemoEnv.feature?('ci')
    c.ci.enabled = true
    c.ci.instrument :rspec
  end

  if Datadog::DemoEnv.feature?('pprof_to_file')
    # Reconfigure transport to write pprof to file
    c.profiling.exporter.transport = Datadog::DemoEnv.profiler_file_transport
  end
end

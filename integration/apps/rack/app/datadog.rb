require 'datadog/demo_env'
require 'datadog'
require 'datadog/appsec'

Datadog.configure do |c|
  c.service = 'acme-rack'
  c.diagnostics.debug = true if Datadog::DemoEnv.feature?('debug')
  c.runtime_metrics.enabled = true if Datadog::DemoEnv.feature?('runtime_metrics')

  if Datadog::DemoEnv.feature?('tracing')
    c.tracing.analytics.enabled = true if Datadog::DemoEnv.feature?('analytics')
    c.tracing.instrument :rack
  end

  if Datadog::DemoEnv.feature?('appsec')
    c.appsec.enabled = true

    c.appsec.instrument :rack
  end

  if Datadog::DemoEnv.feature?('pprof_to_file')
    # Reconfigure transport to write pprof to file
    c.profiling.exporter.transport = Datadog::DemoEnv.profiler_file_transport
  end
end

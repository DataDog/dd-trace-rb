require 'datadog/demo_env'
require 'datadog'

require 'opentelemetry/sdk'
require 'datadog/opentelemetry'

Datadog.configure do |c|
  c.diagnostics.debug = true if Datadog::DemoEnv.feature?('debug')
  c.runtime_metrics.enabled = true if Datadog::DemoEnv.feature?('runtime_metrics')
  c.tracing.analytics.enabled = true if Datadog::DemoEnv.feature?('analytics')
  if Datadog::DemoEnv.feature?('pprof_to_file')
    # Reconfigure transport to write pprof to file
    c.profiling.exporter.transport = Datadog::DemoEnv.profiler_file_transport
  end

  c.tracing.partial_flush.min_spans_threshold = 1 # Ensure tests flush spans quickly
end

::OpenTelemetry::SDK.configure do |_c|
end
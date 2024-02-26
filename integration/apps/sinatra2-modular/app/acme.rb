require 'sinatra/base'
require 'sinatra/router'
require 'datadog'

# require 'datadog/auto_instrument'

Datadog.configure do |c|
  c.service = 'acme-sinatra2-modular'
  c.diagnostics.debug = true if Datadog::DemoEnv.feature?('debug')
  c.runtime_metrics.enabled = true if Datadog::DemoEnv.feature?('runtime_metrics')

  if Datadog::DemoEnv.feature?('tracing')
    c.tracing.analytics.enabled = true if Datadog::DemoEnv.feature?('analytics')
    c.tracing.instrument :sinatra
  end

  if Datadog::DemoEnv.feature?('appsec')
    c.appsec.enabled = true
    c.appsec.instrument :sinatra
  end

  if Datadog::DemoEnv.feature?('pprof_to_file')
    # Reconfigure transport to write pprof to file
    c.profiling.exporter.transport = Datadog::DemoEnv.profiler_file_transport
  end
end

require_relative './basic'
require_relative './health'

class Acme < Sinatra::Base
  # # Use Sinatra App as middleware
  # use Health
  # use Basic

  # # Use Sinatra::Router to mount different modular Sinatra applications
  use Sinatra::Router do
    mount ::Health
    mount ::Basic
  end

  get '/' do
    'Hello world!'
  end
end

require 'active_record'
require 'sidekiq'
require 'redis'
require 'ddtrace'

Datadog.configure do |c|
  c.env = 'integration'
  c.service = ENV['DD_SERVICE'] || 'acme-rails-seven'
  c.diagnostics.debug = true if Datadog::DemoEnv.feature?('debug')
  c.runtime_metrics.enabled = true if Datadog::DemoEnv.feature?('runtime_metrics')

  if Datadog::DemoEnv.feature?('tracing')
    c.tracing.analytics.enabled = true if Datadog::DemoEnv.feature?('analytics')

    c.tracing.instrument :active_record
    c.tracing.instrument :redis, service_name: 'acme-redis'
    c.tracing.instrument :delayed_job
    c.tracing.instrument :rack
    c.tracing.instrument :rails
    c.tracing.instrument :redis
    c.tracing.instrument :sidekiq
  end
end

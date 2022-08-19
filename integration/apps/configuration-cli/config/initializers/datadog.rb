require 'ddtrace'

Datadog.configure do |c|
  c.agent.host = 'ddagent'
  c.agent.port = 8126
  c.env = 'integration'
  c.service = 'acme-configuration-cli'
  c.tracing.instrument :rails
  c.tracing.instrument :redis
  c.tracing.instrument :resque
end

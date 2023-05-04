# frozen_string_literal: true

begin
  # Load tracing
  require_relative 'datadog/tracing'
  require_relative 'datadog/tracing/contrib'

  # Load other products (must follow tracing)
  require_relative 'datadog/profiling'
  require_relative 'datadog/appsec'
  require_relative 'datadog/ci'
  require_relative 'datadog/kit'

  # module Util
  #   def self.to_underscore(str)
  #     str.gsub(/::/, '/').
  #       gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').
  #       gsub(/([a-z\d])([A-Z])/, '\1_\2').
  #       tr("-", "_").
  #       downcase
  #   end
  # end
  #
  # Datadog.configuration.diagnostics.debug = true
end

# Declare ddtrace components
#
# module Datadog
#   module Settings
#     # Our existing settings
#     'agent.host'
#     'agent.port'
#     'runtime_metrics.enabled'
#     'tracing.enabled'
#     'sampling.rules'
#   end
# end
#
# class Tracer
#   extend ComponentMixin
#
#   setting(:enabled, 'tracing.enabled')
#   component(:sampler)
#   component(:agent_settings) # Datadog.internal.components[:agent_settings]
#   component(:writer)
#   def initialize(enabled, agent_settings, sampler, writer)
#     puts "New Tracer"
#     @enabled = enabled
#     @agent_settings = agent_settings
#     @sampler = sampler
#     @writer = writer
#   end
# end
#
# class Sampler
#   extend ComponentMixin
#
#   setting(:rate_limit,'tracing.sampling.rate_limit')
#   def initialize(rate_limit)
#     puts "New Sampler"
#     @rate_limit = rate_limit
#   end
#
#   def rate_limit=(limit)
#     # Trivial to update at runtime
#     @rate_limit = limit
#   end
# end
#
# class Writer
#   extend ComponentMixin
#
#   component(:agent_settings)
#   def initialize(agent_settings)
#     puts "New Writer"
#   end
# end
#
# class AgentSettings
#   extend ComponentMixin
#
#   setting(:host, 'agent.host')
#   setting(:port, 'agent.port')
#   def initialize(host, port)
#     puts "New AgentSettings"
#     @host = host
#     @port = port
#   end
# end
#
# class RuntimeMetrics
#   extend ComponentMixin
#
#   component(:agent_settings) # Datadog.internal.components[:agent_settings]
#   setting(:enabled, 'runtime_metrics.enabled')
#   def initialize(enabled, agent_settings)
#     puts "New RuntimeMetrics"
#     @enabled = enabled
#     @agent_settings = agent_settings
#   end
# end
#
# Datadog.dependencies.resolve_all
# Datadog.dependencies.change_settings({ 'tracing.sampling.rate_limit' => 0.5 })
# Datadog.dependencies.change_settings({ 'agent.host' => 'not.local.host' })
# Datadog.dependencies.change_settings({ 'tracing.sampling.rate_limit' => 0.5, 'runtime_metrics.enabled' => false })
# Datadog.dependencies.change_settings({ 'agent.host' => 'not.local.host', 'runtime_metrics.enabled' => false, 'tracing.sampling.rate_limit' => 0.5 })





# Real one
# Datadog::Core.dependency_registry.resolve_all
#
# Datadog.configure {}
# Datadog.configure {}
#
# Datadog::Core.dependency_registry.change_settings({ 'logger.level' => Logger::DEBUG })

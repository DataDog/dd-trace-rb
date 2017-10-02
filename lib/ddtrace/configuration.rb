require_relative 'configuration/proxy'

module Datadog
  # Configuration provides a unique access point for configurations
  class Configuration
    InvalidIntegrationError = Class.new(StandardError)

    def initialize(options = {})
      @registry = options.fetch(:registry, Datadog.registry)
    end

    def [](integration_name)
      integration = fetch_integration(integration_name)
      Proxy.new(integration)
    end

    def use(integration_name, options = {})
      integration = fetch_integration(integration_name)

      options.each_with_object(Proxy.new(integration)) do |(name, value), proxy|
        proxy[name] = value
      end

      integration.patch if integration.respond_to?(:patch)
    end

    private

    def fetch_integration(name)
      @registry[name] ||
        raise(InvalidIntegrationError, "'#{name}' is not a valid integration.")
    end
  end
end

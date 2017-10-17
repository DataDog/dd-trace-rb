require_relative 'configuration/proxy'
require_relative 'configuration/resolver'

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

      integration.sorted_options.each do |name|
        integration.set_option(name, options[name]) if options.key?(name)
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

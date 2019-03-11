require_relative 'configuration/proxy'
require_relative 'configuration/resolver'
require_relative 'configuration/pin_setup'

module Datadog
  # Configuration provides a unique access point for configurations
  class Configuration
    ENV_TRACE_ANALYTICS_ENABLED = 'DD_TRACE_ANALYTICS_ENABLED'.freeze
    InvalidIntegrationError = Class.new(StandardError)

    attr_writer :analytics_enabled

    def initialize(options = {})
      @registry = options.fetch(:registry) { Datadog.registry }
      @wrapped_registry = {}
      @analytics_enabled = nil
    end

    def analytics_enabled
      @analytics_enabled || begin
        if ENV.key?(ENV_TRACE_ANALYTICS_ENABLED)
          value = ENV[ENV_TRACE_ANALYTICS_ENABLED]
          value.to_s.downcase == 'true'
        end
      end
    end

    def [](integration_name, configuration_name = :default)
      integration = fetch_integration(integration_name)

      if integration.class <= Datadog::Contrib::Integration
        integration.configuration(configuration_name)
      else
        @wrapped_registry[integration_name] ||= Proxy.new(integration)
      end
    end

    def use(integration_name, options = {}, &block)
      integration = fetch_integration(integration_name)

      if integration.class <= Datadog::Contrib::Integration
        configuration_name = options[:describes] || :default
        filtered_options = options.reject { |k, _v| k == :describes }
        integration.configure(configuration_name, filtered_options, &block)
      else
        settings = Proxy.new(integration)
        integration.sorted_options.each do |name|
          settings[name] = options.fetch(name, settings[name])
        end
      end

      integration.patch if integration.respond_to?(:patch)
    end

    def tracer(options = {})
      instance = options.fetch(:instance, Datadog.tracer)

      instance.configure(options)
      instance.class.log = options[:log] if options[:log]
      instance.set_tags(options[:tags]) if options[:tags]
      instance.set_tags(env: options[:env]) if options[:env]
      instance.class.debug_logging = options.fetch(:debug, false)
    end

    private

    def fetch_integration(name)
      @registry[name] ||
        raise(InvalidIntegrationError, "'#{name}' is not a valid integration.")
    end
  end
end

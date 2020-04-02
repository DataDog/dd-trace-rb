require 'forwardable'

require 'ddtrace/configuration/pin_setup'
require 'ddtrace/configuration/settings'
require 'ddtrace/configuration/components'

module Datadog
  # Configuration provides a unique access point for configurations
  module Configuration
    extend Forwardable

    attr_writer :configuration

    def configuration
      @configuration ||= Settings.new
    end

    def configure(target = configuration, opts = {})
      if target.is_a?(Settings)
        yield(target) if block_given?

        # Rebuild immutable components from settings
        rebuild_components!(target)

        target
      else
        PinSetup.new(target, opts).call
      end
    end

    # Helper methods
    def tracer
      configuration.tracer
    end

    def runtime_metrics
      tracer.writer.runtime_metrics
    end

    protected

    def components
      @components ||= Components.new(configuration)
    end

    def rebuild_components!(configuration)
      @components.teardown! if instance_variable_defined?(:@components)
      @components = Components.new(configuration)
    end
  end
end

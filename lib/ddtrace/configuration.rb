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

        # Build immutable components from settings
        @components ||= nil
        @components = if @components
                        replace_components!(target, @components)
                      else
                        build_components(target)
                      end

        target
      else
        PinSetup.new(target, opts).call
      end
    end

    def_delegators \
      :components,
      :health_metrics,
      :logger,
      :profiler,
      :runtime_metrics,
      :tracer

    def shutdown!
      components.shutdown! if instance_variable_defined?(:@components) && @components
    end

    protected

    def components
      @components ||= build_components(configuration)
    end

    private

    def build_components(settings)
      components = Components.new(settings)
      components.startup!(settings)
      components
    end

    def replace_components!(settings, old)
      components = Components.new(settings)

      old.shutdown!(components)
      components.startup!(settings)
      components
    end
  end
end

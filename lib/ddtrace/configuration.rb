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

    def configure(target = configuration, opts = {}, silence_logs = false)
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
      :runtime_metrics,
      :tracer

    def logger
      if instance_variable_defined?(:@components) && @components
        @temp_logger = nil
        components.logger
      else
        # Use default logger without initializing components.
        # This prevents recursive loops while initializing.
        # e.g. Get logger --> Build components --> Log message --> Repeat...
        @temp_logger ||= begin
          logger = configuration.logger.instance || Datadog::Logger.new(STDOUT)
          logger.level = configuration.diagnostics.debug ? ::Logger::DEBUG : configuration.logger.level
          logger
        end
      end
    end

    def shutdown!
      if instance_variable_defined?(:@components) && @components
        components.shutdown!
        @components = nil
      end
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

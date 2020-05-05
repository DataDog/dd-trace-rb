require 'forwardable'
require 'monitor'

require 'ddtrace/configuration/pin_setup'
require 'ddtrace/configuration/settings'
require 'ddtrace/configuration/components'

module Datadog
  # Configuration provides a unique access point for configurations
  module Configuration
    extend Forwardable

    attr_writer :configuration

    def configuration
      return @configuration if @configuration

      MONITOR.synchronize do
        @configuration ||= Settings.new
      end
    end

    def configure(target = configuration, opts = {})
      MONITOR.synchronize do
        if target.is_a?(Settings)
          yield(target) if block_given?

          # Build immutable components from settings
          @components ||= nil
          @components = if @components
                          Components.replace!(@components, target)
                        else
                          Components.new(target)
                        end

          target
        else
          PinSetup.new(target, opts).call
        end
      end
    end

    def_delegators \
      :components,
      :health_metrics,
      :logger,
      :runtime_metrics,
      :tracer

    def shutdown!
      MONITOR.synchronize do
        components.teardown! if @components
      end
    end

    protected

    # TODO: move away from constant into a proper scope
    MONITOR = Monitor.new # Reentrant lock

    def components
      return @components if @components

      MONITOR.synchronize do
        @components ||= Components.new(configuration)
      end
    end
  end
end

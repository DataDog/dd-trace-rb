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
                        Components.replace!(@components, target)
                      else
                        Components.new(target)
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
      :runtime_metrics,
      :tracer

    def shutdown!
      components.teardown! if @components
    end

    protected

    def components
      @components ||= Components.new(configuration)
    end
  end
end

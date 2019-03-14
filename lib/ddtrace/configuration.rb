require 'ddtrace/configuration/pin_setup'
require 'ddtrace/configuration/settings'

module Datadog
  # Configuration provides a unique access point for configurations
  module Configuration
    attr_writer :configuration

    def configuration
      @configuration ||= Settings.new
    end

    def configure(target = configuration, opts = {})
      if target.is_a?(Settings)
        yield(target)
      else
        PinSetup.new(target, opts).call
      end
    end

    # Helper methods
    def tracer
      configuration.tracer
    end
  end
end

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

    def_delegators \
      :components,
      :health_metrics,
      :runtime_metrics,
      :tracer

    protected

    def components
      @components ||= Components.new(configuration)
    end

    def rebuild_components!(configuration)
      # Build new components
      new_components = Components.new(configuration)

      # Teardown old components if they exist
      teardown_components!(@components, new_components) if instance_variable_defined?(:@components)

      # Activate new components
      @components = new_components
    end

    def teardown_components!(old, current)
      # Shutdown the old tracer, unless it's still being used.
      # (e.g. a custom tracer instance passed in.)
      old.tracer.shutdown! unless old.tracer == current.tracer

      # Shutdown the old metrics, unless they are still being used.
      # (e.g. custom Statsd instances.)
      old_statsd = [old.runtime_metrics.statsd, old.health_metrics.statsd].uniq
      new_statsd = [current.runtime_metrics.statsd, current.health_metrics.statsd].uniq
      unused_statsd = (old_statsd - (old_statsd & new_statsd))
      unused_statsd.each(&:close)
    end
  end
end

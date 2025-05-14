# frozen_string_literal: true

require_relative 'di/configuration'
require_relative 'di/extensions'
require_relative 'di/remote'

module Datadog
  # Namespace for Datadog dynamic instrumentation.
  #
  # @api private
  module DI
    class << self
      def enabled?
        Datadog.configuration.dynamic_instrumentation.enabled
      end
    end

    # Expose DI to global shared objects
    Extensions.activate!

    class << self

      # This method is called from DI Remote handler to issue DI operations
      # to the probe manager (add or remove probes).
      #
      # When DI Remote is executing, Datadog.components should be initialized
      # and we should be able to reference it to get to the DI component.
      #
      # Given that we need the current_component anyway for code tracker,
      # perhaps we should delete the +component+ method and just use
      # +current_component+ in all cases.
      def component
        Datadog.send(:components).dynamic_instrumentation
      end
    end
  end
end

# Line probes will not work on Ruby < 2.6 because of lack of :script_compiled
# trace point. Activate DI automatically on supported Ruby versions but
# always load its settings so that, for example, turning DI off when
# we are on Ruby 2.5 does not produce exceptions.
require_relative 'di/boot' if RUBY_VERSION >= '2.6' && RUBY_ENGINE != 'jruby'

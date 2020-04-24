require 'ddtrace/ext/manual_tracing'
require 'ddtrace/tracer'

module Datadog
  module Ext
    # Defines constants for forced tracing
    module ForcedTracing
      @deprecation_warning_shown = false

      def self.const_missing(name)
        super unless Ext::ManualTracing.const_defined?(name)

        # Only log each deprecation warning once (safeguard against log spam)
        unless @deprecation_warning_shown
          Datadog.logger.warn(
            'forced tracing: Datadog::Ext::ForcedTracing has been renamed to Datadog::Ext::ManualTracing'
          )
          @deprecation_warning_shown = true
        end

        Ext::ManualTracing.const_get(name)
      end
    end
  end
end

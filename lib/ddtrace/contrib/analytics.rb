require 'ddtrace/analytics'

module Datadog
  module Contrib
    # Defines analytics behavior for integrations
    module Analytics
      module_function

      # Checks whether analytics should be enabled.
      # `flag` is a truthy/falsey value that represents a setting on the integration.
      def enabled?(flag = nil)
        (Datadog.configuration.analytics_enabled && flag != false) || flag == true
      end

      def set_sample_rate(span, sample_rate)
        Datadog::Analytics.set_sample_rate(span, sample_rate)
      end
    end
  end
end

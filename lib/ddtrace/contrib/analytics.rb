require 'ddtrace/ext/analytics'

module Datadog
  module Contrib
    # Defines sampling behavior for integrations
    module Analytics
      module_function

      # Checks whether analytics should be enabled.
      # `flag` is a truthy/falsey value that represents a setting on the integration.
      def enabled?(flag = nil)
        (Datadog.configuration.analytics_enabled && flag != false) || flag == true
      end

      def set_sample_rate(span, sample_rate)
        return if span.nil? || sample_rate.nil?
        span.set_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE, sample_rate)
      end
    end
  end
end

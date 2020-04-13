require 'ddtrace/ext/analytics'

module Datadog
  # Defines analytics behavior
  module Analytics
    class << self
      def set_sample_rate(span, sample_rate)
        return if span.nil? || !sample_rate.is_a?(Numeric)
        span.set_metric(Datadog::Ext::Analytics::TAG_SAMPLE_RATE, sample_rate)
      end

      def set_measured(span, value = true)
        return if span.nil?
        # rubocop:disable Style/MultipleComparison
        value = value == true || value == 1 ? 1 : 0
        span.set_metric(Datadog::Ext::Analytics::TAG_MEASURED, value)
      end
    end

    # Extension for Datadog::Span
    module Span
      def set_tag(key, value)
        case key
        when Ext::Analytics::TAG_ENABLED
          # If true, set rate to 1.0, otherwise set 0.0.
          value = value == true ? Ext::Analytics::DEFAULT_SAMPLE_RATE : 0.0
          Analytics.set_sample_rate(self, value)
        when Ext::Analytics::TAG_SAMPLE_RATE
          Analytics.set_sample_rate(self, value)
        else
          super if defined?(super)
        end
      end
    end
  end
end

require 'ddtrace/ext/priority'

module Datadog
  module Contrib
    # Defines sampling behavior for integrations
    module Sampling
      module_function

      def set_event_sample_rate(span, sample_rate)
        span.set_metric(Datadog::Ext::Priority::TAG_EVENT_SAMPLE_RATE, sample_rate) unless sample_rate.nil?
      end
    end
  end
end

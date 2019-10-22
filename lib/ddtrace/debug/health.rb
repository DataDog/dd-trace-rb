require 'ddtrace/ext/debug'
require 'ddtrace/metrics'

module Datadog
  module Debug
    # Health-related debugging
    module Health
      # Health metrics for debugging
      class Metrics < ::Datadog::Metrics
        count :api_errors, Ext::Debug::Health::Metrics::METRIC_API_ERRORS
        count :api_requests, Ext::Debug::Health::Metrics::METRIC_API_REQUESTS
        count :api_responses, Ext::Debug::Health::Metrics::METRIC_API_RESPONSES
        count :queue_accepted, Ext::Debug::Health::Metrics::METRIC_QUEUE_ACCEPTED
        count :queue_accepted_lengths, Ext::Debug::Health::Metrics::METRIC_QUEUE_ACCEPTED_LENGTHS
        count :queue_accepted_size, Ext::Debug::Health::Metrics::METRIC_QUEUE_ACCEPTED_SIZE
        count :queue_dropped, Ext::Debug::Health::Metrics::METRIC_QUEUE_DROPPED
        gauge :queue_length, Ext::Debug::Health::Metrics::METRIC_QUEUE_LENGTH
        gauge :queue_max_length, Ext::Debug::Health::Metrics::METRIC_QUEUE_MAX_LENGTH
        gauge :queue_size, Ext::Debug::Health::Metrics::METRIC_QUEUE_SIZE
        gauge :queue_spans, Ext::Debug::Health::Metrics::METRIC_QUEUE_SPANS
        count :traces_filtered, Ext::Debug::Health::Metrics::METRIC_TRACES_FILTERED
        count :writer_cpu_time, Ext::Debug::Health::Metrics::METRIC_WRITER_CPU_TIME
      end

      module_function

      def metrics
        Datadog.configuration.debug.health_metrics
      end
    end
  end
end

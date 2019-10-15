require 'ddtrace/ext/debug'
require 'ddtrace/metrics'

module Datadog
  module Debug
    # Health-related debugging
    module Health
      # Health metrics for debugging
      class Metrics < ::Datadog::Metrics
        distribution :api_errors, Ext::Debug::Health::Metrics::METRIC_API_ERRORS
        distribution :api_requests, Ext::Debug::Health::Metrics::METRIC_API_REQUESTS
        distribution :api_responses, Ext::Debug::Health::Metrics::METRIC_API_RESPONSES
        distribution :queue_accepted, Ext::Debug::Health::Metrics::METRIC_QUEUE_ACCEPTED
        distribution :queue_accepted_lengths, Ext::Debug::Health::Metrics::METRIC_QUEUE_ACCEPTED_LENGTHS
        distribution :queue_accepted_size, Ext::Debug::Health::Metrics::METRIC_QUEUE_ACCEPTED_SIZE
        distribution :queue_dropped, Ext::Debug::Health::Metrics::METRIC_QUEUE_DROPPED
        gauge :queue_length, Ext::Debug::Health::Metrics::METRIC_QUEUE_LENGTH
        gauge :queue_max_length, Ext::Debug::Health::Metrics::METRIC_QUEUE_MAX_LENGTH
        gauge :queue_size, Ext::Debug::Health::Metrics::METRIC_QUEUE_SIZE
        gauge :queue_spans, Ext::Debug::Health::Metrics::METRIC_QUEUE_SPANS
        distribution :traces_filtered, Ext::Debug::Health::Metrics::METRIC_TRACES_FILTERED
        distribution :writer_cpu_time, Ext::Debug::Health::Metrics::METRIC_WRITER_CPU_TIME
      end

      module_function

      def metrics
        Datadog.configuration.debug.health_metrics
      end
    end
  end
end

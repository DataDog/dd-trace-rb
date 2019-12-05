require 'ddtrace/ext/diagnostics'
require 'ddtrace/metrics'

module Datadog
  module Diagnostics
    # Health-related diagnostics
    module Health
      # Health metrics for diagnostics
      class Metrics < ::Datadog::Metrics
        count :api_errors, Ext::Diagnostics::Health::Metrics::METRIC_API_ERRORS
        count :api_requests, Ext::Diagnostics::Health::Metrics::METRIC_API_REQUESTS
        count :api_responses, Ext::Diagnostics::Health::Metrics::METRIC_API_RESPONSES
        count :error_context_overflow, Ext::Diagnostics::Health::Metrics::METRIC_ERROR_CONTEXT_OVERFLOW
        count :error_instrumentation_patch, Ext::Diagnostics::Health::Metrics::METRIC_ERROR_INSTRUMENTATION_PATCH
        count :error_span_finish, Ext::Diagnostics::Health::Metrics::METRIC_ERROR_SPAN_FINISH
        count :error_unfinished_spans, Ext::Diagnostics::Health::Metrics::METRIC_ERROR_UNFINISHED_SPANS
        count :instrumentation_patched, Ext::Diagnostics::Health::Metrics::METRIC_INSTRUMENTATION_PATCHED
        count :queue_accepted, Ext::Diagnostics::Health::Metrics::METRIC_QUEUE_ACCEPTED
        count :queue_accepted_lengths, Ext::Diagnostics::Health::Metrics::METRIC_QUEUE_ACCEPTED_LENGTHS
        count :queue_dropped, Ext::Diagnostics::Health::Metrics::METRIC_QUEUE_DROPPED
        count :traces_filtered, Ext::Diagnostics::Health::Metrics::METRIC_TRACES_FILTERED
        count :writer_cpu_time, Ext::Diagnostics::Health::Metrics::METRIC_WRITER_CPU_TIME

        gauge :queue_length, Ext::Diagnostics::Health::Metrics::METRIC_QUEUE_LENGTH
        gauge :queue_max_length, Ext::Diagnostics::Health::Metrics::METRIC_QUEUE_MAX_LENGTH
        gauge :queue_spans, Ext::Diagnostics::Health::Metrics::METRIC_QUEUE_SPANS
        gauge :sampling_service_cache_length, Ext::Diagnostics::Health::Metrics::METRIC_SAMPLING_SERVICE_CACHE_LENGTH
      end

      module_function

      def metrics
        Datadog.configuration.diagnostics.health_metrics
      end
    end
  end
end

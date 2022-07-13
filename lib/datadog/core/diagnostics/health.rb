# typed: true

require 'datadog/core/diagnostics/ext'
require 'datadog/core/metrics/client'

module Datadog
  module Core
    module Diagnostics
      # Health-related diagnostics
      module Health
        # Health metrics for diagnostics
        class Metrics < Core::Metrics::Client
          def initialize(service:, enabled: true, statsd: nil)
            super(enabled: enabled, statsd: statsd)
            @service = service

            @tags = compile_tags!
          end

          count :api_errors, Ext::Health::Metrics::METRIC_API_ERRORS
          count :api_requests, Ext::Health::Metrics::METRIC_API_REQUESTS
          count :api_responses, Ext::Health::Metrics::METRIC_API_RESPONSES
          count :error_context_overflow, Ext::Health::Metrics::METRIC_ERROR_CONTEXT_OVERFLOW
          count :error_instrumentation_patch, Ext::Health::Metrics::METRIC_ERROR_INSTRUMENTATION_PATCH
          count :error_span_finish, Ext::Health::Metrics::METRIC_ERROR_SPAN_FINISH
          count :error_unfinished_spans, Ext::Health::Metrics::METRIC_ERROR_UNFINISHED_SPANS
          count :instrumentation_patched, Ext::Health::Metrics::METRIC_INSTRUMENTATION_PATCHED
          count :queue_accepted, Ext::Health::Metrics::METRIC_QUEUE_ACCEPTED
          count :queue_accepted_lengths, Ext::Health::Metrics::METRIC_QUEUE_ACCEPTED_LENGTHS
          count :queue_dropped, Ext::Health::Metrics::METRIC_QUEUE_DROPPED
          count :traces_filtered, Ext::Health::Metrics::METRIC_TRACES_FILTERED
          count :transport_trace_too_large, Ext::Health::Metrics::METRIC_TRANSPORT_TRACE_TOO_LARGE
          count :transport_chunked, Ext::Health::Metrics::METRIC_TRANSPORT_CHUNKED
          count :writer_cpu_time, Ext::Health::Metrics::METRIC_WRITER_CPU_TIME

          gauge :queue_length, Ext::Health::Metrics::METRIC_QUEUE_LENGTH
          gauge :queue_max_length, Ext::Health::Metrics::METRIC_QUEUE_MAX_LENGTH
          gauge :queue_spans, Ext::Health::Metrics::METRIC_QUEUE_SPANS
          gauge :sampling_service_cache_length, Ext::Health::Metrics::METRIC_SAMPLING_SERVICE_CACHE_LENGTH

          def default_metric_options
            return super unless @tags

            # Return dupes, so that the constant isn't modified,
            # and defaults are unfrozen for mutation in Statsd.
            super.tap do |options|
              options[:tags] = options[:tags].dup
              options[:tags] << @tags
            end
          end

          private

          # Cache tag strings to avoid recreating them on every flush operation.
          def compile_tags!
            return unless @service

            "#{Environment::Ext::TAG_SERVICE}:#{@service}".freeze
          end
        end
      end
    end
  end
end

module Datadog
  module Tracing
    module Diagnostics
      # @public_api
      module Ext
        # Health
        module Health
          # Metrics
          module Metrics
            METRIC_API_ERRORS = 'datadog.tracer.api.errors'.freeze
            METRIC_API_REQUESTS = 'datadog.tracer.api.requests'.freeze
            METRIC_API_RESPONSES = 'datadog.tracer.api.responses'.freeze
            METRIC_ERROR_CONTEXT_OVERFLOW = 'datadog.tracer.error.context_overflow'.freeze
            METRIC_ERROR_INSTRUMENTATION_PATCH = 'datadog.tracer.error.instrumentation_patch'.freeze
            METRIC_ERROR_SPAN_FINISH = 'datadog.tracer.error.span_finish'.freeze
            METRIC_ERROR_UNFINISHED_SPANS = 'datadog.tracer.error.unfinished_spans'.freeze
            METRIC_INSTRUMENTATION_PATCHED = 'datadog.tracer.instrumentation_patched'.freeze
            METRIC_QUEUE_ACCEPTED = 'datadog.tracer.queue.accepted'.freeze
            METRIC_QUEUE_ACCEPTED_LENGTHS = 'datadog.tracer.queue.accepted_lengths'.freeze
            METRIC_QUEUE_DROPPED = 'datadog.tracer.queue.dropped'.freeze
            METRIC_QUEUE_LENGTH = 'datadog.tracer.queue.length'.freeze
            METRIC_QUEUE_MAX_LENGTH = 'datadog.tracer.queue.max_length'.freeze
            METRIC_QUEUE_SPANS = 'datadog.tracer.queue.spans'.freeze
            METRIC_SAMPLING_SERVICE_CACHE_LENGTH = 'datadog.tracer.sampling.service_cache_length'.freeze
            METRIC_TRACES_FILTERED = 'datadog.tracer.traces.filtered'.freeze
            METRIC_TRANSPORT_CHUNKED = 'datadog.tracer.transport.chunked'.freeze
            METRIC_TRANSPORT_TRACE_TOO_LARGE = 'datadog.tracer.transport.trace_too_large'.freeze
            METRIC_WRITER_CPU_TIME = 'datadog.tracer.writer.cpu_time'.freeze
          end
        end
      end
    end
  end
end

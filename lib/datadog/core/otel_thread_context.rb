# frozen_string_literal: true

module Datadog
  module Core
    # Publishes a per-thread OpenTelemetry context record into a thread-local slot,
    # so an out-of-process reader (e.g. the eBPF profiler) can discover it.
    # See the "OTel Thread Context" OTEP (open-telemetry/opentelemetry-specification#4947).
    #
    # Native functions are implemented in ext/libdatadog_api/otel_thread_context.c
    module OTelThreadContext
      class << self
        def supported?
          Datadog::Core::LIBDATADOG_API_FAILURE.nil? && _native_supported?
        end

        def enable!
          return false unless supported?

          _native_enable
        end

        def set(trace_id:, span_id:, local_root_span_id:)
          _native_set(trace_id, span_id, local_root_span_id)
        end
      end
    end
  end
end

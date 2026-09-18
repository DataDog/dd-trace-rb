# frozen_string_literal: true

module Datadog
  module Tracing
    # Publishes a per-thread OpenTelemetry context record into a thread-local slot,
    # so an out-of-process reader (e.g. the eBPF profiler) can discover it.
    #
    # See the "OTel Thread Context" OTEP:
    # https://github.com/open-telemetry/opentelemetry-specification/blob/main/oteps/profiles/4947-thread-ctx.md
    #
    # Native functions are implemented in ext/libdatadog_api/otel_thread_context.c
    class OTelThreadContext
      UNKNOWN_LOCAL_ROOT_SPAN_ID = 0

      def self.build(tracing_settings)
        return unless tracing_settings.otel_thread_context_enabled

        instance = new
        instance if instance.supported? && instance._native_enable
      end

      private_class_method :new

      def subscribe_to_tracer_events!(events)
        events.span_before_start.subscribe do |event_span_op, event_trace_op|
          set(
            trace_id: event_trace_op.id,
            span_id: event_span_op.id,
            local_root_span_id: event_trace_op.send(:root_span).id
          )
        end

        events.span_finished.subscribe do |_event_span_op, event_trace_op|
          next if event_trace_op.finished?

          update_from_trace_op(event_trace_op)
        end
      end

      def set(trace_id:, span_id:, local_root_span_id:)
        # OTEP requires trace-id and span-id to be either both set or both unset.
        # Zeroes can be used to indicate that no trace and span are active.
        # https://github.com/open-telemetry/opentelemetry-specification/blob/main/oteps/profiles/4947-thread-ctx.md#thread-local-context-record
        return clear if trace_id.zero? || span_id.zero?

        _native_set(trace_id, span_id, local_root_span_id)
      end

      def after_fork
        clear
      end

      def clear
        _native_clear
      rescue => e
        Datadog.logger.debug do
          "Error clearing OTel thread context: #{e.class}: #{e.message}"
        end

        false
      end

      def supported?
        Datadog::Core::LIBDATADOG_API_FAILURE.nil? && _native_supported?
      end

      def update_from_trace_op(trace_op)
        active_span = trace_op.active_span

        if active_span
          set(
            trace_id: trace_op.id,
            span_id: active_span.id,
            local_root_span_id: trace_op.send(:root_span).id
          )
        elsif trace_op.parent_span_id && trace_op.parent_span_id != 0
          set(
            trace_id: trace_op.id,
            span_id: trace_op.parent_span_id,
            local_root_span_id: UNKNOWN_LOCAL_ROOT_SPAN_ID
          )
        else
          clear
        end
      rescue => e
        Datadog.logger.debug do
          "Error updating OTel thread context: #{e.class}: #{e.message}"
        end
      end
    end
  end
end

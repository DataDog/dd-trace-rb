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

      def initialize(tracing_settings)
        @enabled = enable! if tracing_settings.otel_thread_context_enabled
      end

      def subscribe_to_tracer_events!(events)
        return unless @enabled

        events.span_before_start.subscribe do |event_span_op, event_trace_op|
          set(
            trace_id: event_trace_op.id,
            span_id: event_span_op.id,
            local_root_span_id: event_trace_op.send(:root_span).id
          )
        end

        events.span_finished.subscribe do |_event_span_op, event_trace_op|
          # we already clear the context in `trace_finished` subscriber
          next if event_trace_op.finished?

          active_span = event_trace_op.active_span

          if active_span
            set(
              trace_id: event_trace_op.id,
              span_id: active_span.id,
              local_root_span_id: event_trace_op.send(:root_span).id
            )
          elsif event_trace_op.parent_span_id && event_trace_op.parent_span_id != 0
            set(
              trace_id: event_trace_op.id,
              span_id: event_trace_op.parent_span_id,
              local_root_span_id: UNKNOWN_LOCAL_ROOT_SPAN_ID
            )
          else
            clear
          end
        end

        events.trace_activated.subscribe do |event_trace_op|
          active_span = event_trace_op.active_span

          if active_span
            set(
              trace_id: event_trace_op.id,
              span_id: active_span.id,
              local_root_span_id: event_trace_op.send(:root_span).id
            )
          elsif event_trace_op.parent_span_id && event_trace_op.parent_span_id != 0
            set(
              trace_id: event_trace_op.id,
              span_id: event_trace_op.parent_span_id,
              local_root_span_id: UNKNOWN_LOCAL_ROOT_SPAN_ID
            )
          end
        end

        events.trace_deactivated.subscribe do |event_trace_op|
          # we already clear the context in `trace_finished` subscriber
          clear unless event_trace_op.finished?
        end

        events.trace_finished.subscribe do
          clear
        end
      end

      def set(trace_id:, span_id:, local_root_span_id:)
        _native_set(trace_id, span_id, local_root_span_id)
      end

      def clear
        _native_clear
      end

      def supported?
        Datadog::Core::LIBDATADOG_API_FAILURE.nil? && _native_supported?
      end

      private

      def enable!
        return false unless supported?

        _native_enable
      end
    end
  end
end

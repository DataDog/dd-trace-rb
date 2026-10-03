# frozen_string_literal: true

require_relative "guardrails/reason"

module Datadog
  module DI
    # DI guardrails reason codes and the telemetry helpers that emit the
    # +dynamic_instrumentation.guardrails.*+ metrics. A skip is a decision
    # taken before expensive work; a drop discards an event after it has
    # been produced. Each helper tags its metric with the canonical reason
    # so operators can attribute reduced DI work to a specific cause.
    module Guardrails
      PROBE_TYPE_SNAPSHOT = "snapshot"
      PROBE_TYPE_LOG = "log"

      EVENT_TYPE_SNAPSHOT = "snapshot"
      EVENT_TYPE_LOG = "log"
      EVENT_TYPE_DIAGNOSTIC = "diagnostic"

      # Returns the canonical probe_type tag for a probe, derived from
      # whether the probe captures a full snapshot.
      def self.probe_type_tag(probe)
        probe.capture_snapshot? ? PROBE_TYPE_SNAPSHOT : PROBE_TYPE_LOG
      end

      # Maps an internal queue event type symbol to the canonical event_type
      # tag value.
      def self.event_type_tag(event_type)
        case event_type
        when :snapshot then EVENT_TYPE_SNAPSHOT
        when :log then EVENT_TYPE_LOG
        when :status then EVENT_TYPE_DIAGNOSTIC
        else raise ArgumentError, "Unknown DI event type: #{event_type.inspect}"
        end
      end

      # Emits the canonical +guardrails.events.skipped+ count metric.
      def self.skipped(telemetry, reason:, probe_type:)
        telemetry&.inc(
          DI::TELEMETRY_NAMESPACE, "guardrails.events.skipped", 1,
          tags: {reason: reason, probe_type: probe_type},
        )
      end

      # Emits the canonical +guardrails.events.dropped+ count metric, and,
      # when +bytes+ is provided, the +guardrails.queue.dropped_bytes+ count
      # metric.
      def self.dropped(telemetry, reason:, event_type:, bytes: nil)
        telemetry&.inc(
          DI::TELEMETRY_NAMESPACE, "guardrails.events.dropped", 1,
          tags: {reason: reason, event_type: event_type},
        )
        return unless bytes

        telemetry&.inc(
          DI::TELEMETRY_NAMESPACE, "guardrails.queue.dropped_bytes", bytes,
          tags: {reason: reason, event_type: event_type},
        )
      end
    end
  end
end

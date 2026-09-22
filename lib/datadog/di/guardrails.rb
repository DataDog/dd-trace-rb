# frozen_string_literal: true

require_relative "guardrails/reason"

module Datadog
  module DI
    # Canonical DI guardrails observability surface: the reason-code
    # vocabulary and the tagged-telemetry helpers that emit the
    # +dynamic_instrumentation.guardrails.*+ metric family. A skip is a
    # decision taken before expensive work; a drop discards an event after
    # it has been produced. Each helper tags its metric with the canonical
    # reason so operators can attribute reduced DI work to a specific cause
    # across languages.
    module Guardrails
      TELEMETRY_NAMESPACE = "dynamic_instrumentation"

      # Canonical probe_type tag values.
      PROBE_TYPE_SNAPSHOT = "snapshot"
      PROBE_TYPE_LOG = "log"

      # Canonical event_type tag values.
      EVENT_TYPE_SNAPSHOT = "snapshot"
      EVENT_TYPE_LOG = "log"
      EVENT_TYPE_DIAGNOSTIC = "diagnostic"

      # Canonical scope tag value for the process-wide queue.
      SCOPE_GLOBAL = "global"

      # Returns the canonical probe_type tag for a probe, derived from
      # whether the probe captures a full snapshot.
      def self.probe_type_tag(probe)
        probe.capture_snapshot? ? PROBE_TYPE_SNAPSHOT : PROBE_TYPE_LOG
      end

      # Maps an internal queue event type symbol to the canonical event_type
      # tag value. Probe status updates map to diagnostic events.
      def self.event_type_tag(event_type)
        case event_type
        when :snapshot then EVENT_TYPE_SNAPSHOT
        when :status then EVENT_TYPE_DIAGNOSTIC
        else event_type.to_s
        end
      end

      # Emits the canonical +guardrails.events.skipped+ count metric for a
      # no-emission decision made before expensive work.
      def self.skipped(telemetry, reason:, probe_type:)
        return unless telemetry

        telemetry.inc(
          TELEMETRY_NAMESPACE, "guardrails.events.skipped", 1,
          tags: {reason: reason, probe_type: probe_type},
        )
      end

      # Emits the canonical +guardrails.events.dropped+ count metric for a
      # post-production discard, and, when +bytes+ is provided, the
      # +guardrails.queue.dropped_bytes+ count metric.
      def self.dropped(telemetry, reason:, event_type:, bytes: nil)
        return unless telemetry

        telemetry.inc(
          TELEMETRY_NAMESPACE, "guardrails.events.dropped", 1,
          tags: {reason: reason, event_type: event_type},
        )
        return unless bytes

        telemetry.inc(
          TELEMETRY_NAMESPACE, "guardrails.queue.dropped_bytes", bytes,
          tags: {reason: reason, event_type: event_type},
        )
      end
    end
  end
end

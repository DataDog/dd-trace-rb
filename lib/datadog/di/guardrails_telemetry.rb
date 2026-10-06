# frozen_string_literal: true

require_relative "guardrails_telemetry/reason"
require_relative "telemetry_namespace"

module Datadog
  module DI
    # Telemetry reporter for the DI guardrails: the canonical reason codes
    # and the emitters for the +dynamic_instrumentation.guardrails.*+
    # metrics. A skip is a decision taken before expensive work; a drop
    # discards an event after it has been produced. Each emitter tags its
    # metric with the canonical reason so operators can attribute reduced
    # DI work to a specific cause.
    class GuardrailsTelemetry
      PROBE_TYPE_SNAPSHOT = "snapshot"
      PROBE_TYPE_LOG = "log"

      EVENT_TYPE_SNAPSHOT = "snapshot"
      EVENT_TYPE_LOG = "log"
      EVENT_TYPE_DIAGNOSTIC = "diagnostic"

      # @param telemetry [Datadog::Core::Telemetry::Component, nil] component the guardrails metrics are emitted through
      def initialize(telemetry:)
        @telemetry = telemetry
      end

      attr_reader :telemetry

      # Returns the canonical probe_type tag for a probe, derived from
      # whether the probe captures a full snapshot.
      #
      # @param probe [Probe] the probe whose firing is being tagged
      # @return [String] PROBE_TYPE_SNAPSHOT or PROBE_TYPE_LOG
      def self.probe_type_tag(probe)
        probe.capture_snapshot? ? PROBE_TYPE_SNAPSHOT : PROBE_TYPE_LOG
      end

      # Maps an internal queue event type symbol to the canonical event_type
      # tag value.
      #
      # @param event_type [Symbol] internal queue event type
      # @return [String] the canonical event_type tag value
      # @raise [ArgumentError] if event_type is not a known DI event type
      def self.event_type_tag(event_type)
        case event_type
        when :snapshot then EVENT_TYPE_SNAPSHOT
        when :log then EVENT_TYPE_LOG
        when :status then EVENT_TYPE_DIAGNOSTIC
        else raise ArgumentError, "Unknown DI event type: #{event_type.inspect}"
        end
      end

      # Emits the canonical +guardrails.events.skipped+ count metric.
      #
      # @param reason [String] a GuardrailsTelemetry::Reason constant naming the skip cause
      # @param probe_type [String] the canonical probe_type tag value
      # @return [void]
      def skipped(reason:, probe_type:)
        telemetry&.inc(
          DI::TELEMETRY_NAMESPACE, "guardrails.events.skipped", 1,
          tags: skipped_tags(reason, probe_type),
        )
      end

      # Emits the canonical +guardrails.events.dropped+ count metric, and,
      # when +bytes+ is provided, the +guardrails.queue.dropped_bytes+ count
      # metric.
      #
      # @param reason [String] a GuardrailsTelemetry::Reason constant naming the drop cause
      # @param event_type [String] the canonical event_type tag value
      # @param bytes [Integer, nil] encoded bytes discarded, when the drop site knows the count
      # @return [void]
      def dropped(reason:, event_type:, bytes: nil)
        telemetry&.inc(
          DI::TELEMETRY_NAMESPACE, "guardrails.events.dropped", 1,
          tags: {reason: reason, event_type: event_type},
        )
        return nil unless bytes

        telemetry&.inc(
          DI::TELEMETRY_NAMESPACE, "guardrails.queue.dropped_bytes", bytes,
          tags: {reason: reason, event_type: event_type},
        )
      end

      private

      # One frozen tag hash per (reason, probe_type) pair, built on first
      # use, so a rate-limit-rejected probe firing allocates no tag hash.
      # The memo is unlocked: steady state performs no writes, and a racy
      # first write can only discard a duplicate frozen hash.
      def skipped_tags(reason, probe_type)
        reason_tags = @skipped_tags ||= {}
        probe_type_tags = reason_tags[reason] ||= {}
        probe_type_tags[probe_type] ||= {reason: reason, probe_type: probe_type}.freeze
      end
    end
  end
end

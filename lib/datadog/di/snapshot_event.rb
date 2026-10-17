# frozen_string_literal: true

module Datadog
  module DI
    # A snapshot payload queued for sending to the agent, paired with
    # the guardrails event type of the probe that produced it, so drop
    # metrics can be tagged with the probe's classification.
    # @api private
    class SnapshotEvent
      # Initializes the event.
      #
      # @param payload [Hash] the snapshot payload to send to the agent
      # @param event_type [String] one of GuardrailsTelemetry::EVENT_TYPE_SNAPSHOT and EVENT_TYPE_LOG
      # @return [void]
      def initialize(payload:, event_type:)
        @payload = payload
        @event_type = event_type
      end

      # The snapshot payload to send to the agent.
      # @return [Hash]
      attr_reader :payload

      # The guardrails event type of the probe that produced the payload.
      # @return [String] one of GuardrailsTelemetry::EVENT_TYPE_SNAPSHOT and EVENT_TYPE_LOG
      attr_reader :event_type

      # Compares two events by payload and event type.
      #
      # @param other [Object] the object to compare with
      # @return [Boolean] whether the other object is an event with the
      #   same payload and event type
      def ==(other)
        other.is_a?(SnapshotEvent) && other.payload == payload && other.event_type == event_type
      end
    end
  end
end

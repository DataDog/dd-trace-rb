# frozen_string_literal: true

require_relative "event"
require_relative "deduplicator"

module Datadog
  module OpenFeature
    module Exposures
      # Owns the exposure cache and sends new or changed exposures to the Agent
      class Reporter
        def initialize(worker, telemetry:, logger:, datadog_logging_enabled: true)
          @worker = worker
          @logger = logger
          @telemetry = telemetry
          @datadog_logging_enabled = datadog_logging_enabled
          @deduplicator = Deduplicator.new
        end

        # Records the exposure in the cache and, when it is new or changed, sends it to Datadog.
        # The cache records even when Datadog logging is off, so the verdict does not depend on it.
        #
        # @return [Boolean] true when this subject was already exposed to the same assignment
        def record(flag_key:, allocation_key:, variant:, serial_id:, context:, features:)
          key = Event.cache_key(flag_key: flag_key, targeting_key: context.targeting_key)
          value = Event.cache_value(allocation_key: allocation_key, variant: variant, serial_id: serial_id)
          if @deduplicator.duplicate?(key, value)
            skip(flag_key, "duplicate of the last exposure for this subject")
            return true
          end

          unless @datadog_logging_enabled
            skip(flag_key, "Datadog exposure logging is disabled")
            return false
          end

          enqueue(
            Event.build(
              flag_key: flag_key, allocation_key: allocation_key, variant: variant, serial_id: serial_id,
              context: context, features: features,
            ),
          )
          false
        end

        private

        def enqueue(event)
          return unless @worker.enqueue(event)

          @logger.debug do
            "Feature Flags: queued exposure for #{event.dig(:flag, :key).inspect} " \
              "(allocation=#{event.dig(:allocation, :key).inspect}, variant=#{event.dig(:variant, :key).inspect}, " \
              "targeting_key=#{event.dig(:subject, :id).inspect})"
          end
        end

        def skip(flag_key, reason)
          @logger.debug { "Feature Flags: exposure for #{flag_key.inspect} not sent: #{reason}" }
        end
      end
    end
  end
end

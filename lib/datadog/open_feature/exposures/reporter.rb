# frozen_string_literal: true

require_relative "event"
require_relative "deduplicator"

module Datadog
  module OpenFeature
    module Exposures
      # This class is responsible for reporting exposures to the Agent
      class Reporter
        def initialize(worker, telemetry:, logger:)
          @worker = worker
          @logger = logger
          @telemetry = telemetry
          @deduplicator = Deduplicator.new
        end

        # NOTE: Reporting expects evaluation context to be always present, but it
        #       might be missing depending on the customer way of using flags evaluation API.
        #       In addition to that the evaluation result must be marked for reporting.
        def report(result, flag_key:, context:)
          return skip(flag_key, "no evaluation context") if context.nil?
          return skip(flag_key, "the evaluation result is not marked for exposure logging") unless result.log?

          key = Event.cache_key(result, flag_key: flag_key, context: context)
          value = Event.cache_value(result, flag_key: flag_key, context: context)
          return skip(flag_key, "duplicate of the last exposure for this subject") if @deduplicator.duplicate?(key, value)

          event = Event.build(result, flag_key: flag_key, context: context)
          return false unless @worker.enqueue(event)

          begin
            if @logger.debug?
              @logger.debug(
                "Feature Flags: queued exposure for #{flag_key.inspect} (allocation=#{result.allocation_key.inspect}, " \
                  "variant=#{result.variant.inspect}, targeting_key=#{context.targeting_key.inspect})"
              )
            end
          rescue
            nil
          end
          true
        rescue => e
          @logger.debug("OpenFeature: Failed to report resolution details: #{e.class}: #{e.message}") if @logger.debug?
          @telemetry.report(e, description: "OpenFeature: Failed to report resolution details")

          false
        end

        private

        def skip(flag_key, reason)
          @logger.debug("Feature Flags: exposure for #{flag_key.inspect} not recorded: #{reason}") if @logger.debug?
          false
        rescue
          false
        end
      end
    end
  end
end

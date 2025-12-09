# frozen_string_literal: true

require_relative 'event'
require_relative 'deduplicator'

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
          return false if context.nil?
          return false unless result.log?

          key = Event.cache_key(result, flag_key: flag_key, context: context)
          value = Event.cache_value(result, flag_key: flag_key, context: context)
          return false if @deduplicator.duplicate?(key, value)

          event = Event.build(result, flag_key: flag_key, context: context)
          @worker.enqueue(event)
        rescue => e
          @logger.debug { "OpenFeature: Failed to report resolution details: #{e.class}: #{e.message}" }
          @telemetry.report(e, description: 'OpenFeature: Failed to report resolution details')

          false
        end
      end
    end
  end
end

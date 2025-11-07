# frozen_string_literal: true

require_relative 'models/event'
require_relative 'deduplicator'

module Datadog
  module OpenFeature
    module Exposures
      class Reporter
        def initialize(worker, telemetry:, logger: Datadog.logger)
          @worker = worker
          @logger = logger
          @telemetry = telemetry
          @deduplicator = Deduplicator.new
        end

        def report(result, flag_key:, context:)
          return false unless result.do_log

          event = Models::Event.build(result, flag_key: flag_key, context: context)
          return false if @deduplicator.duplicate?(event)

          @worker.enqueue(event)
        rescue => e
          @logger.debug { "OpenFeature: Reporter failed to enqueue exposure: #{e.class}: #{e.message}" }

          false
        end
      end
    end
  end
end

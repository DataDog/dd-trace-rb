# frozen_string_literal: true

require_relative 'event'

require_relative '../workers/polling'
require_relative '../workers/queue'

module Datadog
  module Core
    module Telemetry
      # Accumulates events and sends them to the API at a regular interval, including heartbeat event.
      class Worker
        include Core::Workers::Queue
        include Core::Workers::Polling

        def initialize(heartbeat_interval_seconds:, emitter:, enabled: true)
          @emitter = emitter

          # Workers::Polling settings
          self.enabled = enabled
          # Workers::IntervalLoop settings
          self.loop_base_interval = heartbeat_interval_seconds
          self.fork_policy = Core::Workers::Async::Thread::FORK_POLICY_STOP
        end

        def start
          return if !enabled? || forked?

          perform
        end

        private

        def perform(*_events)
          return if !enabled? || forked?

          heartbeat!
        end

        def heartbeat!
          @emitter.request(Event::AppHeartbeat.new)
        end
      end
    end
  end
end

require_relative '../worker'
require_relative '../workers/polling'

module Datadog
  module Core
    module Telemetry
      # Periodically (every DEFAULT_INTERVAL_SECONDS) sends a heartbeat event to the telemetry API.
      class Heartbeat < Core::Worker
        include Core::Workers::Polling

        DEFAULT_INTERVAL_SECONDS = 60

        def initialize(enabled: true, interval: DEFAULT_INTERVAL_SECONDS, &block)
          # Workers::Polling settings
          self.enabled = enabled
          # Workers::IntervalLoop settings
          self.loop_base_interval = interval
          self.fork_policy = Core::Workers::Async::Thread::FORK_POLICY_STOP
          super(&block)
          start
        end

        def loop_wait_before_first_iteration?
          true
        end

        private

        def start
          perform
        end
      end
    end
  end
end

require 'ddtrace/runtime/metrics'

require 'ddtrace/worker'
require 'ddtrace/workers/async'
require 'ddtrace/workers/loop'

module Datadog
  module Workers
    # Emits runtime metrics asynchronously on a timed loop
    class RuntimeMetrics < Worker
      include Workers::IntervalLoop
      include Workers::Async::Thread

      SHUTDOWN_TIMEOUT = 1

      attr_reader \
        :metrics

      def initialize(metrics = nil, options = {})
        @metrics = metrics || Runtime::Metrics.new

        # Workers::Async::Thread settings
        self.fork_policy = options.fetch(:fork_policy, Workers::Async::Thread::FORK_POLICY_STOP)

        # Workers::IntervalLoop settings
        self.interval = options[:interval] if options.key?(:interval)
        self.back_off_ratio = options[:back_off_ratio] if options.key?(:back_off_ratio)
        self.back_off_max = options[:back_off_max] if options.key?(:back_off_max)
      end

      def perform
        metrics.flush
        true
      end

      def stop(force_stop = false, timeout = SHUTDOWN_TIMEOUT)
        if running?
          # Attempt graceful stop and wait
          stop_loop
          graceful = join(timeout)

          # If timeout and force stop...
          !graceful && force_stop ? terminate : graceful
        else
          false
        end
      end
    end
  end
end

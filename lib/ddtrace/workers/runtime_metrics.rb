require 'forwardable'

require 'ddtrace/runtime/metrics'

require 'ddtrace/worker'
require 'ddtrace/workers/polling'

module Datadog
  module Workers
    # Emits runtime metrics asynchronously on a timed loop
    class RuntimeMetrics < Worker
      extend Forwardable
      include Workers::Polling

      attr_reader \
        :metrics

      def initialize(options = {})
        @metrics = options.fetch(:metrics, Runtime::Metrics.new)

        # Workers::Async::Thread settings
        self.fork_policy = options.fetch(:fork_policy, Workers::Async::Thread::FORK_POLICY_STOP)

        # Workers::IntervalLoop settings
        self.interval = options[:interval] if options.key?(:interval)
        self.back_off_ratio = options[:back_off_ratio] if options.key?(:back_off_ratio)
        self.back_off_max = options[:back_off_max] if options.key?(:back_off_max)

        self.enabled = options.fetch(:enabled, false)
      end

      def perform
        metrics.flush
        true
      end

      def associate_with_span(*args)
        # Start the worker
        metrics.associate_with_span(*args).tap { perform }
      end

      def_delegators \
        :metrics,
        :register_service
    end
  end
end

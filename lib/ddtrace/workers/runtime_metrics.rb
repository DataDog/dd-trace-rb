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

      # In seconds
      DEFAULT_FLUSH_INTERVAL = 10
      DEFAULT_BACK_OFF_MAX = 30

      attr_reader \
        :metrics

      def initialize(options = {})
        self.enabled = options.fetch(:enabled, false)

        @metrics = options.fetch(:metrics) { Runtime::Metrics.new if enabled? }

        # Workers::Async::Thread settings
        self.fork_policy = options.fetch(:fork_policy, Workers::Async::Thread::FORK_POLICY_STOP)

        # Workers::IntervalLoop settings
        self.loop_base_interval = options.fetch(:interval, DEFAULT_FLUSH_INTERVAL)
        self.loop_back_off_ratio = options[:back_off_ratio] if options.key?(:back_off_ratio)
        self.loop_back_off_max = options.fetch(:back_off_max, DEFAULT_BACK_OFF_MAX)
      end

      def perform
        return unless enabled?

        metrics.flush
        true
      end

      # Forwarded to @metrics.
      # @see {Datadog::Runtime::Metrics}
      def associate_with_span(*args)
        return unless enabled?

        # Start the worker
        metrics.associate_with_span(*args).tap { perform }
      end

      # TODO: `close_metrics` is only needed because
      # Datadog::Components directly manipulates the lifecycle of
      # Runtime::Metrics.statsd instances.
      # This should be avoided, as it prevents this class from
      # ensuring correct resource decommission of its internal
      # dependencies.
      def stop(*args, close_metrics: true)
        self.enabled = false
        result = super(*args)
        @metrics.close if @metrics && close_metrics
        result
      end

      # Forwarded to @metrics.
      # @see {Datadog::Runtime::Metrics}
      # TODO: This method has now value as a public API
      # and should be removed from this worker.
      # It is internally used by `#associate_with_span`.
      def register_service(*args)
        return unless enabled?

        metrics.register_service(*args)
      end
    end
  end
end

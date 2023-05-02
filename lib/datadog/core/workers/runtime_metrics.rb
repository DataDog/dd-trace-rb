# frozen_string_literal: true

require_relative '../runtime/metrics'

require_relative '../worker'
require_relative 'async'
require_relative 'polling'

module Datadog
  module Core
    module Workers
      # Emits runtime metrics asynchronously on a timed loop
      class RuntimeMetrics < Worker
        include Workers::Polling

        # In seconds
        DEFAULT_FLUSH_INTERVAL = 10
        DEFAULT_BACK_OFF_MAX = 30

        attr_reader \
          :metrics


        extend Core::Dependency

        component(:metrics)
        setting(:enabled, 'runtime_metrics.enabled')
        def initialize(metrics: Core::Runtime::Metrics.new, enabled: false, fork_policy: Workers::Async::Thread::FORK_POLICY_STOP,
                       interval: DEFAULT_FLUSH_INTERVAL, back_off_ratio: nil, back_off_max: DEFAULT_BACK_OFF_MAX)
          @metrics = metrics

          # Workers::Async::Thread settings
          self.fork_policy = fork_policy

          # Workers::IntervalLoop settings
          self.loop_base_interval = interval
          self.loop_back_off_ratio = back_off_ratio if back_off_ratio
          self.loop_back_off_max = back_off_max

          self.enabled = enabled
        end

        def perform
          metrics.flush
          true
        end

        def register_service(service)
          # Start the worker
          metrics.register_service(service).tap { perform }
        end

        # TODO: `close_metrics` is only needed because
        # Datadog::Core::Configuration::Components directly manipulates
        # the lifecycle of Runtime::Metrics.statsd instances.
        # This should be avoided, as it prevents this class from
        # ensuring correct resource decommission of its internal
        # dependencies.
        def stop(*args, close_metrics: true)
          self.enabled = false
          result = super(*args)
          @metrics.close if close_metrics
          result
        end
      end
    end
  end
end

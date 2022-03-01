# typed: false

require 'datadog/tracing/contrib/active_job/events/discard'
require 'datadog/tracing/contrib/active_job/events/enqueue'
require 'datadog/tracing/contrib/active_job/events/enqueue_at'
require 'datadog/tracing/contrib/active_job/events/enqueue_retry'
require 'datadog/tracing/contrib/active_job/events/perform'
require 'datadog/tracing/contrib/active_job/events/retry_stopped'

module Datadog
  module Tracing
    module Contrib
      module ActiveJob
        # Defines collection of instrumented ActiveJob events
        module Events
          ALL = [
            Events::Discard,
            Events::Enqueue,
            Events::EnqueueAt,
            Events::EnqueueRetry,
            Events::Perform,
            Events::RetryStopped,
          ].freeze

          module_function

          def all
            self::ALL
          end

          def subscriptions
            all.collect(&:subscriptions).collect(&:to_a).flatten
          end

          def subscribe!
            all.each(&:subscribe!)
          end
        end
      end
    end
  end
end

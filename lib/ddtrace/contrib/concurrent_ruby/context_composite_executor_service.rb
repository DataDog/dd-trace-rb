require 'concurrent/executor/executor_service'

module Datadog
  module Contrib
    module ConcurrentRuby
      # wraps existing executor to carry over trace context
      class ContextCompositeExecutorService
        extend Forwardable
        include Concurrent::ExecutorService

        attr_accessor :composited_executor

        def initialize(composited_executor)
          @composited_executor = composited_executor
        end

        # post method runs the task within composited executor - in a different thread
        def post(*args, &task)
          parent_context = datadog_configuration.tracer.provider.context

          @composited_executor.post(*args) do
            begin
              original_context = datadog_configuration.tracer.provider.context
              datadog_configuration.tracer.provider.context = parent_context
              yield
            ensure
              # Restore context in case the current thread gets reused
              datadog_configuration.tracer.provider.context = original_context
            end
          end
        end

        def datadog_configuration
          Datadog.configuration[:concurrent_ruby]
        end

        delegate [:can_overflow?, :serialized?] => :composited_executor
      end
    end
  end
end

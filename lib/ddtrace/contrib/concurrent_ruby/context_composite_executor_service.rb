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

        def post(*args, &task)
          context = datadog_configuration.tracer.provider.context

          @composited_executor.post(*args) do
            datadog_configuration.tracer.provider.context = context
            yield
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

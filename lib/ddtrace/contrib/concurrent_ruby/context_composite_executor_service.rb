require 'concurrent/executor/executor_service'

module Datadog
  module Contrib
    module ConcurrentRuby
      # Wraps existing executor to carry over trace context
      class ContextCompositeExecutorService
        extend Forwardable
        include Concurrent::ExecutorService

        attr_accessor :composited_executor

        def initialize(composited_executor)
          @composited_executor = composited_executor
        end

        # The post method runs the task within composited executor - in a
        # different thread. The original arguments are captured to be
        # propagated to the composited executor post method
        def post(*args, &block)
          parent_context = datadog_configuration.tracer.provider.context

          executor = @composited_executor.is_a?(Symbol) ? Concurrent.executor(@composited_executor) : @composited_executor

          # Pass the original arguments to the composited executor, which
          # pushes them (possibly transformed) as block args
          executor.post(*args) do |*block_args|
            begin
              original_context = datadog_configuration.tracer.provider.context
              datadog_configuration.tracer.provider.context = parent_context

              # Pass the executor-provided block args as they should have been
              # originally passed without composition, see ChainPromise#on_resolvable
              yield(*block_args)
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

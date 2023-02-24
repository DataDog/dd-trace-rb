require 'concurrent/executor/executor_service'

module Datadog
  module Tracing
    module Contrib
      module ConcurrentRuby
        # wraps existing executor to carry over trace context
        class ContextCompositeExecutorService
          include Concurrent::ExecutorService

          attr_accessor :composited_executor

          def initialize(composited_executor)
            @composited_executor = composited_executor
          end

          # post method runs the task within composited executor - in a different thread
          def post(*args, &task)
            tracer = Tracing.send(:tracer)
            parent_context = tracer.provider.context

            @composited_executor.post(*args) do
              begin
                original_context = tracer.provider.context
                tracer.provider.context = parent_context
                yield
              ensure
                # Restore context in case the current thread gets reused
                tracer.provider.context = original_context
              end
            end
          end

          # Respect the {Concurrent::ExecutorService} interface
          def can_overflow?
            @composited_executor.can_overflow?
          end

          # Respect the {Concurrent::ExecutorService} interface
          def serialized?
            @composited_executor.serialized?
          end

          def datadog_configuration
            Datadog.configuration.tracing[:concurrent_ruby]
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

require 'concurrent/executor/executor_service'

module Datadog
  module Tracing
    module Contrib
      module ConcurrentRuby
        # Wraps existing executor to carry over trace context
        class ContextCompositeExecutorService
          include Concurrent::ExecutorService

          attr_accessor :composited_executor

          def initialize(composited_executor)
            @composited_executor = composited_executor
          end

          # post method runs the task within composited executor - in a different thread. The original arguments are
          # captured to be propagated to the composited executor post method
          def post(*args, &task)
            digest = Tracing.active_trace&.to_digest
            executor = @composited_executor.is_a?(Symbol) ? Concurrent.executor(@composited_executor) : @composited_executor

            # Pass the original arguments to the composited executor, which
            # pushes them (possibly transformed) as block args
            executor.post(*args) do |*block_args|
              # Wrap the task in a block so the propagated trace context is restored
              # afterwards, preventing it from leaking across pooled worker threads.
              # `auto_finish_with_block` keeps the default per-span trace lifetime:
              # spans created by the task are not merged into a single block-scoped
              # trace and may be finished after the task returns.
              Tracing.continue_trace!(digest, auto_finish_with_block: true) do
                # Pass the executor-provided block args as they should have been
                # originally passed without composition, see ChainPromise#on_resolvable
                yield(*block_args)
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

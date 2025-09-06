# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module ConcurrentRuby
        # This patches the RubyExecutorService - to provide tracing context propagation for direct usage
        module ExecutorService
          def post(*args, &task)
            return super(*args, &task) unless datadog_configuration.enabled

            # Capture current trace context in the thread that schedules the task
            digest = Tracing.active_trace&.to_digest

            super(*args) do |*block_args|
              # Restore trace context during background task execution
              if digest
                Tracing.continue_trace!(digest) do
                  yield(*block_args)
                end
              else
                yield(*block_args)
              end
            end
          end

          private

          def datadog_configuration
            Datadog.configuration.tracing[:concurrent_ruby]
          end
        end
      end
    end
  end
end

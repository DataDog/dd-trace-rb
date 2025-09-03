# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module ConcurrentRuby
        # This patches the RubyExecutorService - to wrap executor service using context propagation
        module RubyExecutorServicePatch
          def post(*args, &task)
            puts "[DEBUG] RubyExecutorServicePatch#post called with args: #{args}"

            # Capture current trace context
            digest = Tracing.active_trace&.to_digest
            puts "[DEBUG] Current trace digest: #{digest ? 'present' : 'nil'}"

            super(*args) do |*block_args|
              puts '[DEBUG] Inside patched task execution, restoring context'
              # Restore trace context in the new thread
              Tracing.continue_trace!(digest)

              yield(*block_args)
            end
          end
        end
      end
    end
  end
end

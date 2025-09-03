# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module ConcurrentRuby
        # This patches the RubyExecutorService - to provide tracing context propagation for direct usage
        module RubyExecutorServicePatch
          def post(*args, &task)
            # Check if concurrent_ruby instrumentation is enabled
            return super(*args, &task) unless datadog_configuration.enabled

            # Check if we should skip this call (let existing patches handle it)
            # Skip if this is coming from an already instrumented Future/Async/Promises
            caller_locations = caller_locations(1, 10)
            if caller_locations.any? do |loc|
              loc.path.include?('concurrent') && (loc.path.include?('future') || loc.path.include?('async') || loc.path.include?('promise'))
            end
              return super(*args, &task)
            end

            # Capture current trace context
            digest = Tracing.active_trace&.to_digest

            super(*args) do |*block_args|
              # Restore trace context in the new thread
              Tracing.continue_trace!(digest) do
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

# frozen_string_literal: true

require_relative '../../concurrent_ruby/context_composite_executor_service'

module Datadog
  module Tracing
    module Contrib
      module ActiveRecord
        module AsyncExecutor
          # Wrap the base executor in `ContextCompositeExecutorService` to ensure that the context is propagated
          module ConnectionPool
            private

            def build_async_executor
              base_executor = super

              if base_executor
                ConcurrentRuby::ContextCompositeExecutorService.new(base_executor)
              end
            end
          end
        end
      end
    end
  end
end

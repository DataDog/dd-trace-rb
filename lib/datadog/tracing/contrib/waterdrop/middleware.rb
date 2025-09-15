# frozen_string_literal: true

require_relative 'ext'

module Datadog
  module Tracing
    module Contrib
      module WaterDrop
        # Middleware to propagate tracing context in messages produced by WaterDrop
        module Middleware
          class << self
            def call(message)
              trace_op = Datadog::Tracing.active_trace

              if trace_op && Datadog::Tracing::Distributed::PropagationPolicy.enabled?(
                global_config: configuration,
                trace: trace_op
              )
                WaterDrop.inject(trace_op.to_digest, message[:headers] ||= {})
              end

              message
            end

            private

            def configuration
              Datadog.configuration.tracing[:waterdrop]
            end
          end
        end
      end
    end
  end
end

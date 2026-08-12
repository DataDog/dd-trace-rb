# frozen_string_literal: true

require_relative "ext"

module Datadog
  module Tracing
    module Contrib
      module WaterDrop
        # Middleware to propagate tracing context in messages produced by WaterDrop
        module Middleware
          class << self
            def call(message)
              trace_op = Datadog::Tracing.active_trace
              trace_propagation_enabled = trace_op && Datadog::Tracing::Distributed::PropagationPolicy.enabled?(
                global_config: configuration,
                trace: trace_op
              )
              data_streams_enabled = Datadog::DataStreams.enabled?

              if trace_propagation_enabled || data_streams_enabled
                message[:headers] = (message[:headers] || {}).dup
              end

              if trace_propagation_enabled
                WaterDrop.inject(trace_op.to_digest, message[:headers])
              end

              if data_streams_enabled
                Datadog::DataStreams.set_produce_checkpoint(
                  type: "kafka",
                  destination: message[:topic],
                  auto_instrumentation: true
                ) do |key, value|
                  message[:headers][key] = value
                end
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

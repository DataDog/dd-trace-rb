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
                global_config: datadog_configuration(message[:topic]),
                trace: trace_op
              )
                WaterDrop.inject(trace_op.to_digest, message[:headers] ||= {})
              end

              if Datadog::DataStreams.enabled?
                Datadog::DataStreams.set_produce_checkpoint(
                  type: 'kafka',
                  destination: message[:topic],
                  auto_instrumentation: true
                ) do |key, value|
                  message[:headers] ||= {}
                  message[:headers][key] = value
                end
              end

              message
            end

            private

            def datadog_configuration(topic)
              Datadog.configuration.tracing[:waterdrop, topic]
            end
          end
        end
      end
    end
  end
end

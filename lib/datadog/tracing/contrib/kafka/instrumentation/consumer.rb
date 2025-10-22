# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Kafka
        module Instrumentation
          # Instrumentation for Kafka::Consumer
          module Consumer
            def self.included(base)
              base.prepend(InstanceMethods)
            end

            # Instance methods for consumer instrumentation
            module InstanceMethods
              def each_message(**kwargs, &block)
                return super unless Datadog::DataStreams.enabled?

                wrapped_block = proc do |message|
                  Datadog.logger.debug { "Kafka each_message: DSM enabled for topic #{message.topic}" }

                  headers = message.headers || {}
                  Datadog::DataStreams.set_consume_checkpoint(
                    type: 'kafka',
                    source: message.topic,
                    autoinstrumentation: true
                  ) { |key| headers[key] }

                  yield(message) if block
                end

                super(**kwargs, &wrapped_block)
              end

              def each_batch(**kwargs, &block)
                return super unless Datadog::DataStreams.enabled?

                wrapped_block = proc do |batch|
                  Datadog.logger.debug { "Kafka each_batch: DSM enabled for topic #{batch.topic}" }

                  Datadog::DataStreams.set_consume_checkpoint(
                    type: 'kafka',
                    source: batch.topic,
                    autoinstrumentation: true
                  )

                  yield(batch) if block
                end

                super(**kwargs, &wrapped_block)
              end
            end
          end
        end
      end
    end
  end
end

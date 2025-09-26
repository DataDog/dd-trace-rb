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
              # Monkey patch for each_message method
              def each_message(**kwargs, &block)
                # Wrap the block to add DSM processing for each message
                wrapped_block = if Datadog.configuration.tracing.data_streams.enabled
                  proc do |message|
                    # DSM: Create checkpoint for consumed message
                    Datadog.logger.debug { "Kafka each_message: DSM enabled for topic #{message.topic}" }

                    processor = Datadog.configuration.tracing.data_streams.processor

                    # Extract pathway context from message headers if available
                    headers = message.headers || {}
                    processor.set_consume_checkpoint('kafka', message.topic) { |key| headers[key] }

                    # Call the original block if provided
                    yield(message) if block
                  end
                else
                  block
                end

                # Call the original method with wrapped block
                super(**kwargs, &wrapped_block)
              end

              # Monkey patch for each_batch method
              def each_batch(**kwargs, &block)
                # Wrap the block to add DSM processing for each batch
                wrapped_block = if Datadog.configuration.tracing.data_streams.enabled
                  proc do |batch|
                    # DSM: Create checkpoint for consumed batch
                    Datadog.logger.debug { "Kafka each_batch: DSM enabled for topic #{batch.topic}" }

                    processor = Datadog.configuration.tracing.data_streams.processor

                    # For batch processing, we don't have individual message headers
                    # so we create a consume checkpoint without pathway context
                    processor.set_consume_checkpoint('kafka', batch.topic)

                    # Call the original block if provided
                    yield(batch) if block
                  end
                else
                  block
                end

                # Call the original method with wrapped block
                super(**kwargs, &wrapped_block)
              end
            end
          end
        end
      end
    end
  end
end

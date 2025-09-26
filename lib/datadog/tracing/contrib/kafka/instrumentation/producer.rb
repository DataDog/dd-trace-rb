# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Kafka
        module Instrumentation
          # Instrumentation for Kafka::Producer
          module Producer
            def self.included(base)
              base.prepend(InstanceMethods)
            end

            # Instance methods for producer instrumentation
            module InstanceMethods
              def deliver_messages(**kwargs)
                # Only run data streams code if enabled
                if Datadog.configuration.tracing.data_streams.enabled
                  Datadog.logger.debug { 'Kafka producer deliver_messages: DSM enabled' }

                  processor = Datadog.configuration.tracing.data_streams.processor

                  # Access the producer's internal pending message queue
                  # ruby-kafka stores pending messages in @pending_message_queue
                  pending_messages = instance_variable_get(:@pending_message_queue)

                  if pending_messages && !pending_messages.empty?
                    pending_messages.each do |message|
                      message.headers ||= {}
                      processor.set_produce_checkpoint('kafka', message.topic) do |key, value|
                        message.headers[key] = value
                      end
                    end
                  end
                else
                  Datadog.logger.debug { 'Kafka producer deliver_messages: DSM disabled' }
                end

                # Call the original method - spans are created by ActiveSupport::Notifications
                super
              end

              # Monkey patch for send_messages method (async producer)
              def send_messages(messages, **kwargs)
                # Only run DSM code if enabled
                if Datadog.configuration.tracing.data_streams.enabled
                  Datadog.logger.debug { 'Kafka producer send_messages: DSM enabled' }

                  processor = Datadog.configuration.tracing.data_streams.processor

                  # Create checkpoint for async producer (direction:out)
                  messages.each do |message|
                    message[:headers] ||= {}
                    processor.set_produce_checkpoint('kafka', message[:topic]) do |key, value|
                      message[:headers][key] = value
                    end
                  end
                else
                  Datadog.logger.debug { 'Kafka producer send_messages: DSM disabled' }
                end

                # Call the original method - spans are created by ActiveSupport::Notifications
                super
              end
            end
          end
        end
      end
    end
  end
end

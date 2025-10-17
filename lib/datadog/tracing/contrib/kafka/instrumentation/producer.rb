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

            module InstanceMethods
              def deliver_messages(**kwargs)
                if Datadog.configuration.tracing.data_streams.enabled
                  processor = Datadog.configuration.tracing.data_streams.processor
                  pending_messages = instance_variable_get(:@pending_message_queue)

                  if pending_messages && !pending_messages.empty?
                    pending_messages.each do |message|
                      message.headers ||= {}
                      processor.set_produce_checkpoint(type: 'kafka', destination: message.topic) do |key, value|
                        message.headers[key] = value
                      end
                    end
                  end
                end

                super
              end

              def send_messages(messages, **kwargs)
                if Datadog.configuration.tracing.data_streams.enabled
                  processor = Datadog.configuration.tracing.data_streams.processor

                  messages.each do |message|
                    message[:headers] ||= {}
                    processor.set_produce_checkpoint(type: 'kafka', destination: message[:topic]) do |key, value|
                      message[:headers][key] = value
                    end
                  end
                end

                super
              end
            end
          end
        end
      end
    end
  end
end

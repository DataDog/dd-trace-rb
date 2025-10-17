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
                if Datadog.configuration.data_streams.enabled
                  pending_messages = instance_variable_get(:@pending_message_queue)

                  if pending_messages && !pending_messages.empty?
                    pending_messages.each do |message|
                      message.headers ||= {}
                      Datadog.data_streams.set_produce_checkpoint(
                        type: 'kafka',
                        destination: message.topic,
                        manual_checkpoint: false
                      ) do |key, value|
                        message.headers[key] = value
                      end
                    end
                  end
                end

                super
              end

              def send_messages(messages, **kwargs)
                if Datadog.configuration.data_streams.enabled
                  messages.each do |message|
                    message[:headers] ||= {}
                    Datadog.data_streams.set_produce_checkpoint(
                      type: 'kafka',
                      destination: message[:topic],
                      manual_checkpoint: false
                    ) do |key, value|
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

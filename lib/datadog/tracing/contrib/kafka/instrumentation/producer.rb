# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Kafka
        module Instrumentation
          # Instrumentation for Kafka::Producer
          module Producer
            def self.prepended(base)
              base.prepend(InstanceMethods)
            end

            module InstanceMethods
              def deliver_messages(**kwargs)
                if Datadog::DataStreams.enabled?
                  begin
                    pending_messages = instance_variable_get(:@pending_message_queue)

                    if pending_messages && !pending_messages.empty?
                      pending_messages.each do |message|
                        message.headers ||= {}
                        Datadog::DataStreams.set_produce_checkpoint(
                          type: 'kafka',
                          destination: message.topic,
                          auto_instrumentation: true
                        ) do |key, value|
                          message.headers[key] = value
                        end
                      end
                    end
                  rescue => e
                    Datadog.logger.debug("Error setting DSM checkpoint: #{e.class}: #{e}")
                  end
                end

                super
              end

              def send_messages(messages, **kwargs)
                if Datadog::DataStreams.enabled?
                  begin
                    messages.each do |message|
                      message[:headers] ||= {}
                      Datadog::DataStreams.set_produce_checkpoint(
                        type: 'kafka',
                        destination: message[:topic],
                        auto_instrumentation: true
                      ) do |key, value|
                        message[:headers][key] = value
                      end
                    end
                  rescue => e
                    Datadog.logger.debug("Error setting DSM checkpoint: #{e.class}: #{e}")
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

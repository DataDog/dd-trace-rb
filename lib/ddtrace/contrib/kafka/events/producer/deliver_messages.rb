require 'ddtrace/contrib/kafka/ext'
require 'ddtrace/contrib/kafka/event'

module Datadog
  module Contrib
    module Kafka
      module Events
        module Producer
          # Defines instrumentation for deliver_messages.producer.kafka event
          module DeliverMessages
            include Kafka::Event

            EVENT_NAME = 'deliver_messages.producer.kafka'.freeze

            def self.process(span, _event, _id, payload)
              super

              span.set_tag(Ext::TAG_ATTEMPTS, payload[:attempts]) if payload.key?(:attempts)
              span.set_tag(Ext::TAG_MESSAGE_COUNT, payload[:message_count]) if payload.key?(:message_count)
              if payload.key?(:delivered_message_count)
                span.set_tag(Ext::TAG_DELIVERED_MESSAGE_COUNT, payload[:delivered_message_count])
              end
            end

            module_function

            def span_name
              Ext::SPAN_DELIVER_MESSAGES
            end
          end
        end
      end
    end
  end
end

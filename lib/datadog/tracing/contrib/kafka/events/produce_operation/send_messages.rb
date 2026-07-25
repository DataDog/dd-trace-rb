# frozen_string_literal: true

require_relative "../../ext"
require_relative "../../event"

module Datadog
  module Tracing
    module Contrib
      module Kafka
        module Events
          module ProduceOperation
            # Defines instrumentation for send_messages.producer.kafka event
            module SendMessages
              include Kafka::Event

              EVENT_NAME = "send_messages.producer.kafka"

              module_function

              def on_start(span, _event, _id, _payload)
                super

                span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_PRODUCER)
              end

              def on_finish(span, _event, _id, payload)
                super

                # `ruby-kafka` populates these counts inside the block, so they are only available on
                # finish. See APMS-20161.
                span.set_tag(Ext::TAG_MESSAGE_COUNT, payload[:message_count]) if payload.key?(:message_count)
                span.set_tag(Ext::TAG_SENT_MESSAGE_COUNT, payload[:sent_message_count]) if payload.key?(:sent_message_count)
              end

              def span_name
                Ext::SPAN_SEND_MESSAGES
              end

              def span_options
                super.merge({tags: {Tracing::Metadata::Ext::TAG_OPERATION => Ext::TAG_OPERATION_SEND_MESSAGES}})
              end
            end
          end
        end
      end
    end
  end
end

module Datadog
  module Contrib
    module Kafka
      # Defines basic behaviors for an event for a consumer.
      module ConsumerEvent
        def process(span, _event, _id, payload)
          super

          span.set_tag(Ext::TAG_GROUP, payload[:group_id])
        end
      end
    end
  end
end

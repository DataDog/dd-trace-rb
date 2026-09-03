# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Kafka
        module ConsumerGroupEvent
          def on_start(span, _event, _id, payload)
            super

            span.resource = payload[:group_id]
          end
        end
      end
    end
  end
end

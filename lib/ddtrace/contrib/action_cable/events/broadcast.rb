require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/action_cable/event'

module Datadog
  module Contrib
    module ActionCable
      module Events
        # Defines instrumentation for 'broadcast.action_cable' event
        module Broadcast
          include ActionCable::Event

          EVENT_NAME = 'broadcast.action_cable'.freeze

          module_function

          def event_name
            self::EVENT_NAME
          end

          def span_name
            Ext::SPAN_BROADCAST
          end

          def span_type
            Datadog::Ext::AppTypes::CUSTOM
          end

          def process(span, _event, _id, payload)
            channel = payload[:broadcasting]
            span.service = configuration[:service_name]
            span.resource = channel
            span.span_type = span_type

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
            end

            span.set_tag(Ext::TAG_CHANNEL, channel)
            span.set_tag(Ext::TAG_BROADCAST_CODER, payload[:coder])
          end
        end
      end
    end
  end
end

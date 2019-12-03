require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/action_cable/event'

module Datadog
  module Contrib
    module ActionCable
      module Events
        # Defines instrumentation for 'transmit.action_cable' event.
        #
        # A 'transmit' event sends a message to a single client subscribed to a channel.
        module Transmit
          include ActionCable::Event

          EVENT_NAME = 'transmit.action_cable'.freeze

          module_function

          def event_name
            self::EVENT_NAME
          end

          def span_name
            Ext::SPAN_TRANSMIT
          end

          def span_type
            # ActionCable transmits data over WebSockets
            Datadog::Ext::AppTypes::WEB
          end

          def process(span, _event, _id, payload)
            channel_class = payload[:channel_class]

            span.service = configuration[:service_name]
            span.resource = channel_class
            span.span_type = span_type

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
            end

            span.set_tag(Ext::TAG_CHANNEL_CLASS, channel_class)
            span.set_tag(Ext::TAG_TRANSMIT_VIA, payload[:via])
          end
        end
      end
    end
  end
end

require 'ddtrace/contrib/active_support/notifications/event'

module Datadog
  module Contrib
    module ActiveModelSerializers
      # Defines basic behaviors for an ActiveModelSerializers event.
      module Event
        def self.included(base)
          base.send(:include, ActiveSupport::Notifications::Event)
          base.send(:extend, ClassMethods)
        end

        # Class methods for ActiveModelSerializers events.
        # Note, they share the same process method and before_trace method.
        module ClassMethods
          def span_options
            { service: configuration[:service_name] }
          end

          def tracer
            configuration[:tracer]
          end

          def configuration
            Datadog.configuration[:active_model_serializers]
          end

          def process(span, event, _id, payload)
            span.service = configuration[:service_name]

            # Set the resource name and serializer name
            res = resource(payload[:serializer])
            span.resource = res
            span.set_tag('active_model_serializers.serializer', res)

            span.span_type = Datadog::Ext::HTTP::TEMPLATE

            # Will be nil in 0.9
            span.set_tag('active_model_serializers.adapter', payload[:adapter].class) unless payload[:adapter].nil?
          end

          private

          def resource(serializer)
            # Depending on the version of ActiveModelSerializers
            # serializer will be a string or an object.
            if serializer.respond_to?(:name)
              serializer.name
            else
              serializer
            end
          end
        end
      end
    end
  end
end

require 'ddtrace/contrib/active_support/notifications/event'

module Datadog
  module Contrib
    module Racecar
      # Defines basic behaviors for an ActiveRecord event.
      module Event
        def self.included(base)
          base.send(:include, ActiveSupport::Notifications::Event)
          base.send(:extend, ClassMethods)
        end

        # Class methods for Racecar events.
        # Note, they share the same process method and before_trace method.
        module ClassMethods
          def subscription(*args)
            super.tap do |subscription|
              subscription.before_trace { ensure_clean_context! }
            end
          end

          def span_options
            { service: configuration[:service_name] }
          end

          def tracer
            configuration[:tracer]
          end

          def configuration
            Datadog.configuration[:racecar]
          end

          def process(span, event, _id, payload)
            span.service = configuration[:service_name]
            span.resource = payload[:consumer_class]

            span.set_tag('kafka.topic', payload[:topic])
            span.set_tag('kafka.consumer', payload[:consumer_class])
            span.set_tag('kafka.partition', payload[:partition])
            span.set_tag('kafka.offset', payload[:offset]) if payload.key?(:offset)
            span.set_tag('kafka.first_offset', payload[:first_offset]) if payload.key?(:first_offset)
            span.set_tag('kafka.message_count', payload[:message_count]) if payload.key?(:message_count)
            span.set_error(payload[:exception_object]) if payload[:exception_object]
          end

          private

          # Context objects are thread-bound.
          # If Racecar re-uses threads, context from a previous trace
          # could leak into the new trace. This "cleans" current context,
          # preventing such a leak.
          def ensure_clean_context!
            return unless configuration[:tracer].call_context.current_span
            configuration[:tracer].provider.context = Context.new
          end
        end
      end
    end
  end
end

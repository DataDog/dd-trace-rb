require 'ddtrace/contrib/analytics'
require 'ddtrace/contrib/active_support/notifications/event'
require 'ddtrace/contrib/action_cable/ext'

module Datadog
  module Contrib
    module ActionCable
      # Defines basic behaviors for an ActiveRecord event.
      module Event
        def self.included(base)
          base.send(:include, ActiveSupport::Notifications::Event)
          base.send(:extend, ClassMethods)
        end

        # Class methods for ActionCable events.
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
            Datadog.configuration[:action_cable]
          end

          def process(span, event, _id, payload)
            span.service = configuration[:service_name]
            span.resource = payload[:channel_class]

            # Set analytics sample rate
            if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
              Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
            end
            span.set_tag(Ext::TAG_ACTION, payload[:action])
            span.set_tag(Ext::TAG_CHANNEL, payload[:channel_class])
            span.set_error(payload[:exception_object]) if payload[:exception_object]
          end

          private

          # Context objects are thread-bound.
          # If ActionCable re-uses threads, context from a previous trace
          # could leak into the new trace. This "cleans" current context,
          # preventing such a leak. This approach mirrors that found in
          # contrib/racecar/event.rb
          def ensure_clean_context!
            return unless configuration[:tracer].call_context.current_span
            configuration[:tracer].provider.context = Context.new
          end
        end
      end
    end
  end
end

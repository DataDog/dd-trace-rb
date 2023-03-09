require_relative '../../metadata/ext'
require_relative '../active_support/notifications/event'
require_relative '../analytics'
require_relative 'ext'

module Datadog
  module Tracing
    module Contrib
      module Racecar
        # Defines basic behaviors for an ActiveRecord event.
        module Event
          def self.included(base)
            base.include(ActiveSupport::Notifications::Event)
            base.extend(ClassMethods)
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

            def configuration
              Datadog.configuration.tracing[:racecar]
            end

            def process(span, event, _id, payload)
              span.service = configuration[:service_name]
              span.resource = payload[:consumer_class]

              span.set_tag(Contrib::Ext::Messaging::TAG_SYSTEM, Ext::TAG_MESSAGING_SYSTEM)
              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)

              # Tag as an external peer service
              span.set_tag(Tracing::Metadata::Ext::TAG_PEER_SERVICE, span.service)

              # Set analytics sample rate
              if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
              end

              # Measure service stats
              Contrib::Analytics.set_measured(span)

              span.set_tag(Ext::TAG_TOPIC, payload[:topic])
              span.set_tag(Ext::TAG_CONSUMER, payload[:consumer_class])
              span.set_tag(Ext::TAG_PARTITION, payload[:partition])
              span.set_tag(Ext::TAG_OFFSET, payload[:offset]) if payload.key?(:offset)
              span.set_tag(Ext::TAG_FIRST_OFFSET, payload[:first_offset]) if payload.key?(:first_offset)
              span.set_tag(Ext::TAG_MESSAGE_COUNT, payload[:message_count]) if payload.key?(:message_count)
              span.set_error(payload[:exception_object]) if payload[:exception_object]
            end

            private

            # Context objects are thread-bound.
            # If Racecar re-uses threads, context from a previous trace
            # could leak into the new trace. This "cleans" current context,
            # preventing such a leak.
            def ensure_clean_context!
              return unless Tracing.active_span

              Tracing.send(:tracer).provider.context = Context.new
            end
          end
        end
      end
    end
  end
end

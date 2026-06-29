# frozen_string_literal: true

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
            def subscription(*args, **kwargs)
              super.tap do |subscription|
                subscription.before_trace { ensure_clean_context! }
              end
            end

            def span_options
              {service: configuration[:service_name]}
            end

            def configuration
              Datadog.configuration.tracing[:racecar]
            end

            def on_start(span, event, _id, payload)
              span.service = configuration[:service_name]
              span.set_tag(Tracing::Metadata::Ext::TAG_SVC_SRC, Ext::TAG_COMPONENT)
              span.resource = payload[:consumer_class]

              span.set_tag(Contrib::Ext::Messaging::TAG_SYSTEM, Ext::TAG_MESSAGING_SYSTEM)
              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)

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

              set_data_streams_checkpoint(payload) if Datadog::DataStreams.enabled?
            end

            # Sets a Data Streams Monitoring consume checkpoint for the event.
            # Events that consume messages (e.g. message, batch) override this;
            # by default it is a no-op (e.g. the main loop event).
            def consume_checkpoint(_payload)
            end

            # Tracks the consumed offset for Data Streams Monitoring consumer
            # lag, when the payload carries the necessary coordinates.
            def track_consumer_lag(topic, partition, offset)
              return unless topic && partition && offset

              Datadog::DataStreams.track_kafka_consume(topic, partition, offset)
            end

            private

            # DSM must never disrupt message processing, so any failure while
            # setting checkpoints is swallowed and logged at debug level.
            def set_data_streams_checkpoint(payload)
              consume_checkpoint(payload)
            rescue => e
              Datadog.logger.debug { "Error setting DSM consume checkpoint: #{e.class}: #{e.message}" }
            end

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

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
              span.resource = payload[:consumer_class]

              span.set_tag(Contrib::Ext::Messaging::TAG_SYSTEM, Ext::TAG_MESSAGING_SYSTEM)
              span.set_tag(Tracing::Metadata::Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)

              # Set analytics sample rate
              if Contrib::Analytics.enabled?(configuration[:analytics_enabled])
                Contrib::Analytics.set_sample_rate(span, configuration[:analytics_sample_rate])
              end

              # Measure service stats
              Contrib::Analytics.set_measured(span)

              # Tag original global service name if not used
              if span.service != Datadog.configuration.service
                span.set_tag(Tracing::Contrib::Ext::Metadata::TAG_BASE_SERVICE, Datadog.configuration.service)
              end

              span.set_tag(Ext::TAG_TOPIC, payload[:topic])
              span.set_tag(Ext::TAG_CONSUMER, payload[:consumer_class])
              span.set_tag(Ext::TAG_PARTITION, payload[:partition])
              span.set_tag(Ext::TAG_OFFSET, payload[:offset]) if payload.key?(:offset)
              span.set_tag(Ext::TAG_FIRST_OFFSET, payload[:first_offset]) if payload.key?(:first_offset)
              span.set_tag(Ext::TAG_MESSAGE_COUNT, payload[:message_count]) if payload.key?(:message_count)
              span.set_error(payload[:exception_object]) if payload[:exception_object]

              # DSM: Set consume checkpoint and track offset for lag monitoring
              set_dsm_checkpoint(payload)
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

            # Sets DSM consume checkpoint and tracks Kafka consumer offset
            def set_dsm_checkpoint(payload)
              return unless Datadog.configuration.data_streams.enabled
              return unless Datadog::DataStreams.enabled?

              topic = payload[:topic]
              partition = payload[:partition]

              begin
                # Single message processing - has headers for context extraction
                if payload.key?(:offset) && payload.key?(:headers)
                  headers = payload[:headers] || {}
                  Datadog::DataStreams.set_consume_checkpoint(
                    type: 'kafka',
                    source: topic,
                    auto_instrumentation: true
                  ) { |key| headers[key] }

                  # Track offset for consumer lag monitoring
                  Datadog::DataStreams.track_kafka_consume(topic, partition, payload[:offset])

                # Batch processing - no headers in payload, but can still track offsets
                elsif payload.key?(:first_offset) && payload.key?(:last_offset)
                  # For batches, set checkpoint without context extraction
                  Datadog::DataStreams.set_consume_checkpoint(
                    type: 'kafka',
                    source: topic,
                    auto_instrumentation: true
                  )

                  # Track the last offset in the batch for lag monitoring
                  Datadog::DataStreams.track_kafka_consume(topic, partition, payload[:last_offset])
                end
              rescue => e
                Datadog.logger.debug("Error setting Racecar DSM checkpoint: #{e.class}: #{e}")
              end
            end
          end
        end
      end
    end
  end
end

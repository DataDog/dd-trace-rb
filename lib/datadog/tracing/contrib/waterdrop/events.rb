# frozen_string_literal: true

require_relative 'ext'

module Datadog
  module Tracing
    module Contrib
      module WaterDrop
        # Event handlers for WaterDrop monitoring events
        # These run AFTER successful message production
        module Events
          def self.subscribe!(producer)
            # Subscribe to async message production events
            producer.monitor.subscribe('message.produced_async') do |event|
              handle_message_produced(event)
            end

            # Subscribe to sync message production events
            producer.monitor.subscribe('message.produced_sync') do |event|
              handle_message_produced(event)
            end

            # Subscribe to batch production events if they exist
            producer.monitor.subscribe('message.produced_many_async') do |event|
              handle_batch_produced(event)
            end

            producer.monitor.subscribe('message.produced_many_sync') do |event|
              handle_batch_produced(event)
            end
          end

          private

          def self.handle_message_produced(event)
            message = event[:message]
            puts "🔍 [WATERDROP EVENTS] Message produced event received: topic=#{message[:topic]}"
            return unless message

            Tracing.trace(Ext::SPAN_PRODUCE) do |span|
              puts "🔍 [WATERDROP EVENTS] Creating span for message: topic=#{message[:topic]}"
              annotate_span(span, message)
              puts "🔍 [WATERDROP EVENTS] Span created and annotated"
            end
          end

          def self.handle_batch_produced(event)
            messages = event[:messages] || []
            return if messages.empty?

            messages.each do |message|
              Tracing.trace(Ext::SPAN_PRODUCE) do |span|
                annotate_span(span, message)
              end
            end
          end

          def self.annotate_span(span, message)
            configuration = Datadog.configuration.tracing[:waterdrop]

            # Set basic span properties
            span.service = configuration[:service_name] || Ext::DEFAULT_SERVICE_NAME
            span.resource = message[:topic] || 'unknown'
            span.type = 'messaging'

            # Set component and operation tags
            span.set_tag(Ext::TAG_COMPONENT, Ext::TAG_COMPONENT)
            span.set_tag(Ext::TAG_OPERATION_PRODUCE, Ext::TAG_OPERATION_PRODUCE)

            # Set Kafka-specific tags
            span.set_tag(Ext::TAG_TOPIC, message[:topic]) if message[:topic]
            span.set_tag(Ext::TAG_PARTITION, message[:partition]) if message[:partition]
            span.set_tag(Ext::TAG_OFFSET, message[:offset]) if message[:offset]
            span.set_tag(Ext::TAG_MESSAGE_KEY, message[:key]) if message[:key]

            # Set messaging system tag
            span.set_tag(Contrib::Ext::Messaging::TAG_SYSTEM, Ext::TAG_SYSTEM)
            span.set_tag(Contrib::Ext::Messaging::TAG_DESTINATION, message[:topic]) if message[:topic]

            # Set span kind
            span.set_tag(Tracing::Metadata::Ext::TAG_KIND, Tracing::Metadata::Ext::SpanKind::TAG_PRODUCER)
          end
        end
      end
    end
  end
end

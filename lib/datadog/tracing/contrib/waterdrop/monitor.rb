# frozen_string_literal: true

require_relative 'ext'

module Datadog
  module Tracing
    module Contrib
      module WaterDrop
        # Custom monitor for WaterDrop.
        # Creating a custom monitor, instead of subscribing to an event
        # (e.g. `WaterDrop.monitor.subscribe 'worker.processed'`),
        # is required because event subscriptions cannot wrap the event execution (`yield`).
        module Monitor
          TRACEABLE_EVENTS = %w[
            messages.produced_async
            messages.produced_sync
            message.produced_async
            message.produced_sync
          ].freeze

          def configuration
            Datadog.configuration.tracing[:waterdrop]
          end

          def instrument(event_id, payload = {}, &block)
            return super unless TRACEABLE_EVENTS.include?(event_id)

            Datadog::Tracing.trace(Ext::SPAN_PRODUCER) do |span, trace|
              action = nil
              trace_digest = trace.to_digest

              if payload.key?(:messages)
                action = event_id.sub('messages.produced', 'produce_many')

                topics = payload[:messages].map { |m| m[:topic] }.uniq
                span.set_tag(Contrib::Ext::Messaging::TAG_DESTINATION, topics)

                partitions = payload[:messages].map { |m| m[:partition] }.uniq.compact
                span.set_tag(Contrib::Karafka::Ext::TAG_PARTITION, partitions) unless partitions.empty?

                span.set_tag(Contrib::Karafka::Ext::TAG_MESSAGE_COUNT, payload[:messages].size)

                payload[:messages].each { |message| inject(trace_digest, message) } if configuration[:distributed_tracing]
              else
                action = event_id.sub('message.produced', 'produce')

                span.set_tag(Contrib::Ext::Messaging::TAG_DESTINATION, payload[:message][:topic])
                span.set_tag(Contrib::Karafka::Ext::TAG_PARTITION, payload[:message][:partition])
                span.set_tag(Contrib::Karafka::Ext::TAG_MESSAGE_COUNT, 1)

                inject(trace_digest, payload[:message]) if configuration[:distributed_tracing]
              end

              span.resource = "waterdrop.#{action}"

              span.set_tag(Ext::TAG_PRODUCER, payload[:producer_id])
              span.set_tag(Contrib::Ext::Messaging::TAG_SYSTEM, Contrib::Karafka::Ext::TAG_SYSTEM)

              super
            end
          end

          private

          def inject(trace_digest, message)
            message[:headers] ||= {}
            WaterDrop.inject(trace_digest, message[:headers])
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative 'ext'

module Datadog
  module Tracing
    module Contrib
      module WaterDrop
        # Producer integration for WaterDrop
        module Producer
          %i[
            produce_many_sync
            produce_many_async
            produce_sync
            produce_async
          ].each do |method|
            define_method(method) do |messages|
              Datadog::Tracing.trace(Ext::SPAN_PRODUCER, resource: "waterdrop.#{__method__}") do
                extract_span_tags(messages)
                super(messages)
              end
            end
          end

          private

          def extract_span_tags(messages)
            messages = [messages] if messages.is_a?(Hash)
            span = Datadog::Tracing.active_span
            return unless span

            topics = []
            partitions = []
            messages.each do |message|
              topics << message[:topic]
              partitions << message[:partition] if message.key?(:partition)
            end

            span.set_tag(Ext::TAG_PRODUCER, id)
            span.set_tag(Contrib::Karafka::Ext::TAG_MESSAGE_COUNT, messages.size)
            span.set_tag(Contrib::Ext::Messaging::TAG_SYSTEM, Contrib::Karafka::Ext::TAG_SYSTEM)

            span.set_tag(Contrib::Ext::Messaging::TAG_DESTINATION, topics.uniq.sort.join(','))
            span.set_tag(Contrib::Karafka::Ext::TAG_PARTITION, partitions.uniq.sort.join(',')) if partitions.any?
          end
        end
      end
    end
  end
end

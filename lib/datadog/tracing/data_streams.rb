# frozen_string_literal: true

module Datadog
  module Tracing
    module DataStreams
      def self.set_produce_checkpoint(type, target, manual_checkpoint: true, &block)
        Datadog.configuration.tracing.data_streams.processor.set_produce_checkpoint(type, target, &block)
      end

      def self.set_consume_checkpoint(type, source, manual_checkpoint: true, &block)
        Datadog.configuration.tracing.data_streams.processor.set_consume_checkpoint(
          type,
          source,
          manual_checkpoint: manual_checkpoint,
          &block
        )
      end
    end
  end
end

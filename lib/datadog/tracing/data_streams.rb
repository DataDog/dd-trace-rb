# frozen_string_literal: true

module Datadog
  module Tracing
    # Public API for Data Streams Monitoring manual instrumentation
    module DataStreams
      # Manually set a produce checkpoint for outgoing messages
      # @param type [String] The type of the messaging system (e.g., 'kafka', 'kinesis', 'sns')
      # @param destination [String] The destination (e.g., topic, exchange, stream name)
      # @param tags [Array<String>] Additional tags to include
      # @yield [key, value] Block to inject pathway context into message headers
      # @return [String, nil] Base64 encoded pathway context
      def self.checkpoint_produce(type:, destination:, tags: [], &block)
        Datadog.configuration.tracing.data_streams.processor.set_produce_checkpoint(
          type: type,
          destination: destination,
          manual_checkpoint: true,
          tags: tags,
          &block
        )
      end

      # Manually set a consume checkpoint for incoming messages
      # @param type [String] The type of the messaging system (e.g., 'kafka', 'kinesis', 'sns')
      # @param source [String] The source (e.g., topic, exchange, stream name)
      # @param tags [Array<String>] Additional tags to include
      # @yield [key] Block to extract pathway context from message headers
      # @return [String, nil] Base64 encoded pathway context
      def self.checkpoint_consume(type:, source:, tags: [], &block)
        Datadog.configuration.tracing.data_streams.processor.set_consume_checkpoint(
          type: type,
          source: source,
          manual_checkpoint: true,
          tags: tags,
          &block
        )
      end
    end
  end
end

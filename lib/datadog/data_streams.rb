# frozen_string_literal: true

require_relative 'data_streams/processor'
require_relative 'data_streams/pathway_context'
require_relative 'data_streams/configuration/settings'
require_relative 'data_streams/extensions'
require_relative 'core/utils/time'

module Datadog
  # Datadog Data Streams Monitoring public API.
  #
  # The Datadog team ensures that public methods in this module
  # only receive backwards compatible changes, and breaking changes
  # will only occur in new major versions releases.
  # @public_api
  module DataStreams
    class << self
      # Set a produce checkpoint for Data Streams Monitoring
      #
      # @param type [String] The type of the checkpoint (e.g., 'kafka', 'kinesis', 'sns')
      # @param destination [String] The destination (e.g., topic, exchange, stream name)
      # @param auto_instrumentation [Boolean] Whether this checkpoint was set by auto-instrumentation (default: false)
      # @param tags [Hash] Additional tags to include
      # @yield [key, value] Block to inject context into carrier
      # @return [String, nil] Base64 encoded pathway context or nil if disabled
      # @public_api
      def set_produce_checkpoint(type:, destination:, auto_instrumentation: false, tags: {}, &block)
        processor&.set_produce_checkpoint(
          type: type,
          destination: destination,
          manual_checkpoint: !auto_instrumentation,
          tags: tags,
          &block
        )
      end

      # Set a consume checkpoint for Data Streams Monitoring
      #
      # @param type [String] The type of the checkpoint (e.g., 'kafka', 'kinesis', 'sns')
      # @param source [String] The source (e.g., topic, exchange, stream name)
      # @param auto_instrumentation [Boolean] Whether this checkpoint was set by auto-instrumentation (default: false)
      # @param tags [Hash] Additional tags to include
      # @yield [key] Block to extract context from carrier
      # @return [String, nil] Base64 encoded pathway context or nil if disabled
      # @public_api
      def set_consume_checkpoint(type:, source:, auto_instrumentation: false, tags: {}, &block)
        processor&.set_consume_checkpoint(
          type: type,
          source: source,
          manual_checkpoint: !auto_instrumentation,
          tags: tags,
          &block
        )
      end

      # Track Kafka produce offset for lag monitoring
      #
      # @param topic [String] The Kafka topic name
      # @param partition [Integer] The partition number
      # @param offset [Integer] The offset of the produced message
      # @return [Boolean, nil] true if tracking succeeded, nil if disabled
      # @!visibility private
      def track_kafka_produce(topic, partition, offset)
        processor&.track_kafka_produce(topic, partition, offset, Core::Utils::Time.now)
      end

      # Track Kafka message consumption for consumer lag monitoring
      #
      # @param topic [String] The Kafka topic name
      # @param partition [Integer] The partition number
      # @param offset [Integer] The offset of the consumed message
      # @return [Boolean, nil] true if tracking succeeded, nil if disabled
      # @!visibility private
      def track_kafka_consume(topic, partition, offset)
        processor&.track_kafka_consume(topic, partition, offset, Core::Utils::Time.now)
      end

      # Check if Data Streams Monitoring is enabled and available
      #
      # @return [Boolean] true if the processor is available
      # @public_api
      def enabled?
        !processor.nil?
      end

      private

      def processor
        components.data_streams
      end

      def components
        Datadog.send(:components)
      end
    end

    # Expose Data Streams to global shared objects
    Extensions.activate!
  end
end

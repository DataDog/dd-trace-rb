# frozen_string_literal: true

require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Racecar
        module Instrumentation
          # Instrumentation that sets Data Streams Monitoring consume checkpoints
          # for messages consumed by Racecar.
          #
          # This wraps `Racecar::Runner#process` and `#process_batch`, where the
          # individual rdkafka messages (with their headers) are available. A
          # per-message checkpoint preserves N:M pathway topology: each message
          # in a batch keeps its own upstream context, so fan-in from multiple
          # sources is represented as distinct edges.
          module Consumer
            # Extracts the DSM pathway context from a single message and records
            # a consume checkpoint plus the consumed offset for lag tracking.
            def self.set_consume_checkpoint(message)
              return unless Datadog::DataStreams.enabled?

              headers = message.headers
              Datadog::DataStreams.set_consume_checkpoint(
                type: Ext::TAG_MESSAGING_SYSTEM,
                source: message.topic,
                auto_instrumentation: true,
              ) { |key| header_value(headers, key) }

              Datadog::DataStreams.track_kafka_consume(message.topic, message.partition, message.offset)
            rescue => e
              Datadog.logger.debug { "Error setting DSM consume checkpoint: #{e.class}: #{e.message}" }
            end

            # rdkafka returns consumed headers keyed by String (>= 0.13) or by
            # Symbol (<= 0.12), so look the propagation key up both ways.
            def self.header_value(headers, key)
              return unless headers

              if headers.key?(key)
                headers[key]
              else
                headers[key.to_sym]
              end
            end

            def self.prepended(base)
              base.prepend(InstanceMethods)
            end

            # Instance methods for consumer instrumentation
            module InstanceMethods
              def process(message)
                Consumer.set_consume_checkpoint(message)

                super
              end

              def process_batch(messages)
                messages.each { |message| Consumer.set_consume_checkpoint(message) }

                super
              end
            end
          end
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative 'pathway_context'

module Datadog
  module Tracing
    module DataStreams
      # Processor for Data Streams Monitoring
      # This class is responsible for collecting and reporting pathway stats
      class Processor
        attr_accessor :enabled

        def initialize
          @enabled = true
          @pathway_context = PathwayContext.new(0, Time.now.to_f, Time.now.to_f)
        end

        def encode_pathway_context
          return nil unless @enabled

          @pathway_context.encode_b64
        end

        def set_checkpoint(tags, now_sec = nil, payload_size = 0, span = nil)
          nil unless @enabled
          # TODO: Implement checkpoint creation
        end

        def track_kafka_produce(topic, partition, offset, now_sec)
          nil unless @enabled
          # TODO: Implement produce offset tracking
        end

        def track_kafka_commit(group, topic, partition, offset, now_sec)
          nil unless @enabled
          # TODO: Implement commit offset tracking
        end

        def track_kafka_consume(topic, partition, offset, now_sec)
          nil unless @enabled
          # TODO: Implement consume offset tracking for DSM stats
        end

        def decode_pathway_context(encoded_ctx)
          nil unless @enabled
          # TODO: Implement pathway context decoding from base64
        end

        def flush_stats
          nil unless @enabled
          # TODO: Manually flush stats to agent
        end

        def get_current_pathway
          return nil unless @enabled

          @pathway_context
        end

        def set_pathway_context(ctx)
          return unless @enabled

          @pathway_context = ctx if ctx
        end

        def decode_and_set_pathway_context(headers)
          return unless @enabled
          return unless headers && headers['dd-pathway-ctx-base64']

          pathway_ctx = decode_pathway_context(headers['dd-pathway-ctx-base64'])
          set_pathway_context(pathway_ctx) if pathway_ctx
        end
      end
    end
  end
end

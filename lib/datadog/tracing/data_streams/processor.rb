# frozen_string_literal: true

require 'json'
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

          # Stats storage
          @checkpoint_stats = []
          @consumer_stats = []
          @stats_mutex = Mutex.new
        end

        def encode_pathway_context
          return nil unless @enabled

          @pathway_context.encode_b64
        end

        def set_checkpoint(tags, now_sec = nil, payload_size = 0, span = nil)
          return nil unless @enabled

          now_sec ||= Time.now.to_f
          current_context = @pathway_context

          # Calculate new pathway hash from current hash + tags
          new_hash = compute_pathway_hash(current_context.hash, tags)

          # Calculate edge latency (time since last checkpoint)
          edge_latency_sec = now_sec - current_context.current_edge_start_sec

          # Record stats for this checkpoint
          record_checkpoint_stats(
            hash: new_hash,
            parent_hash: current_context.hash,
            edge_latency_sec: edge_latency_sec,
            payload_size: payload_size,
            tags: tags,
            timestamp_sec: now_sec
          )

          # Advance pathway: new edge starts now, but keep original pathway start
          @pathway_context = PathwayContext.new(
            new_hash,
            current_context.pathway_start_sec,  # Keep original pathway start
            now_sec,                            # New edge starts now
            current_context.hash                # Track parent hash for lineage
          )

          # Return encoded context for propagation
          @pathway_context.encode_b64
        end

        def track_kafka_produce(topic, partition, offset, now_sec)
          nil unless @enabled
          # TODO: Implement produce offset tracking
        end

        def track_kafka_commit(group, topic, partition, offset, now_sec)
          nil unless @enabled
          # TODO: Implement commit offset tracking
        end

        def track_kafka_consume(topic, partition, offset, now_sec = nil)
          return nil unless @enabled

          now_sec ||= Time.now.to_f

          # Record stats for this consumer operation
          record_consumer_stats(
            topic: topic,
            partition: partition,
            offset: offset,
            timestamp_sec: now_sec
          )

          # Aggregate stats by topic/partition for reporting
          aggregate_consumer_stats_by_partition(topic, partition, offset, now_sec)

          true
        end

        def decode_pathway_context(encoded_ctx)
          return nil unless @enabled

          PathwayContext.decode_b64(encoded_ctx)
        end

        def flush_stats
          return unless @enabled

          @stats_mutex.synchronize do
            return if @checkpoint_stats.empty? && @consumer_stats.empty?

            # Build payload for agent
            payload = {
              checkpoints: @checkpoint_stats.dup,
              consumer_offsets: @consumer_stats.dup,
              timestamp: Time.now.to_i,
              time_buckets: aggregate_stats_by_time_buckets
            }

            # Send to agent
            send_stats_to_agent(payload)

            # Clear stats after successful send
            @checkpoint_stats.clear
            @consumer_stats.clear
          end
        rescue => e
          # Don't let agent errors break application
          # TODO: Add proper error logging
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

        private

        # Compute new pathway hash using FNV-1a algorithm
        # Combines current hash with tags to create unique pathway identifier
        def compute_pathway_hash(current_hash, tags)
          # FNV-1a 64-bit constants
          fnv_offset_basis = 14695981039346656037 # 0xcbf29ce484222325
          fnv_prime = 1099511628211 # 0x100000001b3

          # Start with current hash as basis
          hash_value = current_hash ^ fnv_offset_basis

          # Hash each tag
          tags.each do |tag|
            tag.each_byte do |byte|
              hash_value ^= byte
              hash_value = (hash_value * fnv_prime) & 0xFFFFFFFFFFFFFFFF
            end
          end

          hash_value
        end

        # Record stats for this checkpoint
        def record_checkpoint_stats(hash:, parent_hash:, edge_latency_sec:, payload_size:, tags:, timestamp_sec:)
          @stats_mutex.synchronize do
            @checkpoint_stats << {
              hash: hash,
              parent_hash: parent_hash,
              edge_latency_sec: edge_latency_sec,
              payload_size: payload_size,
              tags: tags,
              timestamp_sec: timestamp_sec
            }
          end
        end

        # Record consumer offset stats for DSM reporting
        def record_consumer_stats(topic:, partition:, offset:, timestamp_sec:)
          @stats_mutex.synchronize do
            @consumer_stats << {
              topic: topic,
              partition: partition,
              offset: offset,
              timestamp_sec: timestamp_sec
            }
          end
        end

        # Aggregate consumer stats by topic and partition
        def aggregate_consumer_stats_by_partition(topic, partition, offset, timestamp_sec)
          # For now, just record the individual stat
          # TODO: Add actual aggregation logic (latest offsets, lag calculation, etc.)
        end

        # Aggregate stats by time buckets (10 second buckets)
        def aggregate_stats_by_time_buckets
          bucket_size = 10 # seconds
          buckets = {}

          all_stats = @checkpoint_stats + @consumer_stats
          all_stats.each do |stat|
            bucket_timestamp = (stat[:timestamp_sec] / bucket_size).to_i * bucket_size
            buckets[bucket_timestamp] ||= []
            buckets[bucket_timestamp] << stat
          end

          buckets
        end

        # Send stats payload to Datadog agent
        def send_stats_to_agent(payload)
          # Compress if payload is large
          if compress_payload?(payload)
            compressed_data = gzip_compress(payload.to_json)
            headers = { 'Content-Type' => 'application/json', 'Content-Encoding' => 'gzip' }
            data = compressed_data
          else
            headers = { 'Content-Type' => 'application/json' }
            data = payload.to_json
          end

          # Send to agent
          agent_transport.post('/v0.1/pipeline_stats', data, headers)
        end

        # Check if payload should be compressed
        def compress_payload?(payload)
          payload.to_json.bytesize > 1000 # Compress if > 1KB
        end

        # Gzip compress data
        def gzip_compress(data)
          # TODO: Implement actual gzip compression
          "gzipped:#{data}"
        end

        # Get agent transport (placeholder)
        def agent_transport
          # TODO: Use actual Datadog agent transport
          @agent_transport ||= double('AgentTransport')
        end
      end
    end
  end
end

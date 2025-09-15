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

        def initialize(ddsketch_class: Datadog::Core::DDSketch)
          # DDSketch is required for DSM - disable processor if not supported
          unless ddsketch_class.supported?
            @enabled = false
            return
          end

          @enabled = true
          @pathway_context = PathwayContext.new(0, Time.now.to_f, Time.now.to_f)
          @edge_latency_sketch = ddsketch_class.new
          @full_pathway_latency_sketch = ddsketch_class.new
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
            # Check if we have data to send
            return if @edge_latency_sketch.count == 0 && @consumer_stats.empty?

            # Build payload matching Python implementation format
            stats_buckets = serialize_buckets

            payload = {
              'Service' => 'ruby-service', # TODO: Get from config
              'TracerVersion' => '2.0.0',  # TODO: Get actual version
              'Lang' => 'ruby',
              'Stats' => stats_buckets,
              'Hostname' => hostname
            }

            # Send to agent (msgpack + gzip like Python)
            send_stats_to_agent(payload)

            # Clear stats after successful send (DDSketch.encode resets automatically)
            if @ddsketch_available
              @edge_latency_sketch.encode # This resets the sketch
              @full_pathway_latency_sketch.encode # This resets the sketch
            else
              @checkpoint_stats.clear
            end
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

        # Record stats for this checkpoint (matching Python implementation)
        def record_checkpoint_stats(hash:, parent_hash:, edge_latency_sec:, payload_size:, tags:, timestamp_sec:)
          @stats_mutex.synchronize do
            # Use DDSketch for latency distributions (like Python)
            @edge_latency_sketch.add(edge_latency_sec)

            # Calculate full pathway latency
            full_pathway_latency_sec = timestamp_sec - @pathway_context.pathway_start_sec
            @full_pathway_latency_sketch.add(full_pathway_latency_sec)
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

        # Send stats payload to Datadog agent (matching Python implementation)
        def send_stats_to_agent(payload)
          # Use msgpack encoding like Python
          require 'msgpack'
          msgpack_data = MessagePack.pack(payload)

          # Always compress like Python implementation
          compressed_data = gzip_compress(msgpack_data)

          # Headers matching Python format
          headers = {
            'Content-Type' => 'application/msgpack',
            'Content-Encoding' => 'gzip',
            'Datadog-Meta-Lang' => 'ruby',
            'Datadog-Meta-Tracer-Version' => '2.0.0' # TODO: Get actual version
          }

          # Send to agent
          agent_transport.post('/v0.1/pipeline_stats', compressed_data, headers)
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

        # Serialize buckets to match Python implementation format
        def serialize_buckets
          # For now, create a single bucket (TODO: implement time-based bucketing)
          bucket_time_ns = (Time.now.to_f * 1e9).to_i
          bucket_duration_ns = 10 * 1e9 # 10 second buckets like Python

          # Always use DDSketch format (real or fake)
          bucket_stats = [{
            'EdgeTags' => [], # TODO: Implement edge tag aggregation
            'Hash' => 0,      # TODO: Implement pathway hash tracking
            'ParentHash' => 0, # TODO: Implement parent hash tracking
            'PathwayLatency' => @full_pathway_latency_sketch.encode,
            'EdgeLatency' => @edge_latency_sketch.encode,
          }]

          # Create buckets array matching Python format
          [{
            'Start' => bucket_time_ns,
            'Duration' => bucket_duration_ns,
            'Stats' => bucket_stats,
            'Backlogs' => serialize_consumer_backlogs
          }]
        end

        # Serialize consumer offset data as backlogs (matching Python)
        def serialize_consumer_backlogs
          @consumer_stats.map do |stat|
            {
              'Tags' => [
                'type:kafka_consume',
                "topic:#{stat[:topic]}",
                "partition:#{stat[:partition]}"
              ],
              'Value' => stat[:offset]
            }
          end
        end

        # Get hostname for agent payload
        def hostname
          # TODO: Use actual hostname detection
          'ruby-host'
        end

        # Get default DDSketch class (real if available, fake for testing)
        def get_default_ddsketch_class
          require 'datadog/core/ddsketch'
          Datadog::Core::DDSketch.supported? ? Datadog::Core::DDSketch : FakeDDSketch
        rescue LoadError, NameError
          FakeDDSketch
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

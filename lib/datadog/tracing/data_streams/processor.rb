# frozen_string_literal: true

require 'json'
require 'datadog/core/ddsketch'
require_relative 'pathway_context'
require_relative 'pathway_codec'
require_relative '../../version'

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
          @bucket_size_ns = (10 * 1e9).to_i # 10 second buckets
          @buckets = {} # Time-based buckets for stats
          @consumer_stats = []
          @stats_mutex = Mutex.new
          @ddsketch_class = ddsketch_class # Store for creating new sketches
        end

        def encode_pathway_context
          return nil unless @enabled

          @pathway_context.encode_b64
        end

        def set_checkpoint(tags, now_sec = nil, payload_size = 0, span = nil)
          return nil unless @enabled

          now_sec ||= Time.now.to_f

          # Get or create current context ( threading.local behavior)
          current_context = get_current_context
          tags = tags.sort

          # Extract direction
          direction = ""
          tags.each do |tag|
            if tag.start_with?("direction:")
              direction = tag
              break
            end
          end

          # Loop detection logic ( lines 477-489)
          # Only apply loop detection if there's a direction tag and it matches the previous direction
          if !direction.empty? && direction == current_context.previous_direction
            # Same direction - reuse hash from opposite direction
            current_context.hash = current_context.closest_opposite_direction_hash
            if current_context.hash == 0
              # Restart pathway if no opposite direction hash
              current_context.current_edge_start_sec = now_sec
              current_context.pathway_start_sec = now_sec
            else
              # Reuse edge start from opposite direction
              current_context.current_edge_start_sec = current_context.closest_opposite_direction_edge_start
            end
          else
            # New direction or no direction - store current state for future reuse
            current_context.previous_direction = direction
            current_context.closest_opposite_direction_hash = current_context.hash
            current_context.closest_opposite_direction_edge_start = current_context.current_edge_start_sec
          end

          parent_hash = current_context.hash
          new_hash = compute_pathway_hash(parent_hash, tags)

          edge_latency_sec = [now_sec - current_context.current_edge_start_sec, 0.0].max
          full_pathway_latency_sec = [now_sec - current_context.pathway_start_sec, 0.0].max

          # DEBUG: Log latency calculations
          puts "   Edge latency: #{edge_latency_sec}s"
          puts "   Full pathway latency: #{full_pathway_latency_sec}s"

          # Manual flush for testing
          puts "🔍 [DSM DEBUG] Manually flushing stats to test agent communication..."
          flush_stats

          # Record stats for this checkpoint
          record_checkpoint_stats(
            hash: new_hash,
            parent_hash: parent_hash,
            edge_latency_sec: edge_latency_sec,
            payload_size: payload_size,
            tags: tags,
            timestamp_sec: now_sec
          )

          # Update pathway context ( lines 503-504)
          current_context.hash = new_hash
          current_context.current_edge_start_sec = now_sec

          # DEBUG: Log final state

          # Return encoded context for propagation
          current_context.encode_b64
        end

        def track_kafka_produce(topic, partition, offset, now_sec)
          return nil unless @enabled

          now_ns = (now_sec * 1e9).to_i
          partition_key = "#{topic}:#{partition}"

          @stats_mutex.synchronize do
            # Calculate bucket time (align to bucket boundaries )
            bucket_size_ns = 10 * 1e9 # 10 second buckets
            bucket_time_ns = now_ns - (now_ns % bucket_size_ns)

            # Track latest produce offset for this partition ()
            @produce_offsets ||= {}
            @produce_offsets[bucket_time_ns] ||= {}
            @produce_offsets[bucket_time_ns][partition_key] = [
              offset,
              @produce_offsets[bucket_time_ns][partition_key] || 0
            ].max
          end

          true
        end

        def track_kafka_commit(group, topic, partition, offset, now_sec)
          return nil unless @enabled

          now_ns = (now_sec * 1e9).to_i
          consumer_key = "#{group}:#{topic}:#{partition}"

          @stats_mutex.synchronize do
            # Calculate bucket time (align to bucket boundaries )
            bucket_size_ns = 10 * 1e9 # 10 second buckets
            bucket_time_ns = now_ns - (now_ns % bucket_size_ns)

            # Track latest commit offset for this consumer group/partition ()
            @commit_offsets ||= {}
            @commit_offsets[bucket_time_ns] ||= {}
            @commit_offsets[bucket_time_ns][consumer_key] = [
              offset,
              @commit_offsets[bucket_time_ns][consumer_key] || 0
            ].max
          end

          true
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

        def decode_pathway_b64(encoded_ctx)
          return nil unless @enabled

          PathwayContext.decode_b64(encoded_ctx)
        end

        def flush_stats
          return unless @enabled

          @stats_mutex.synchronize do

            # Check if we have data to send
            return if @buckets.empty? && @consumer_stats.empty?

            # Build payload  implementation format
            stats_buckets = serialize_buckets

            payload = {
              'Service' => Datadog.configuration.service,
              'TracerVersion' => Datadog::VERSION::STRING,
              'Lang' => 'ruby',
              'Stats' => stats_buckets,
              'Hostname' => hostname
            }


            # Send to agent (msgpack + gzip )
            send_stats_to_agent(payload)

            # Clear consumer stats after successful send (buckets cleared in serialize_buckets)
            @consumer_stats.clear
          end
        rescue => e
          # Don't let agent errors break application
          Datadog.logger.debug("Failed to flush DSM stats to agent: #{e.message}")
        end

        def get_current_pathway
          return nil unless @enabled

          get_current_context
        end

        # Get or create current context ( threading.local behavior)
        def get_current_context
          @pathway_context ||= PathwayContext.new(0, Time.now.to_f, Time.now.to_f)
        end

        def set_pathway_context(ctx)
          return unless @enabled

          if ctx
            @pathway_context = ctx
            # Reset loop detection fields when setting new context (new service)
            @pathway_context.previous_direction = ""
            @pathway_context.closest_opposite_direction_hash = 0
            @pathway_context.closest_opposite_direction_edge_start = @pathway_context.current_edge_start_sec
          end
        end

        def decode_and_set_pathway_context(headers)
          return unless @enabled
          return unless headers && headers['dd-pathway-ctx-base64']

          pathway_ctx = decode_pathway_context(headers['dd-pathway-ctx-base64'])
          set_pathway_context(pathway_ctx) if pathway_ctx
        end

        private

        # Compute new pathway hash using FNV-1a algorithm ( implementation)
        # Combines service, env, tags, and parent hash to create unique pathway identifier
        def compute_pathway_hash(current_hash, tags)
          # Get service and environment (: self.service + self.env)
          service = Datadog.configuration.service || 'ruby-service'
          env = Datadog.configuration.env || 'none'

          # Build byte string: service + env + tags ()
          bytes = service.bytes + env.bytes
          tags.each { |tag| bytes += tag.bytes }

          # Convert to string for FNV function
          byte_string = bytes.pack('C*')

          # First hash: FNV-1a of service + env + tags ( node_hash)
          node_hash = fnv1_64(byte_string)

          # Second hash: FNV-1a of (node_hash + parent_hash) ()
          combined_bytes = [node_hash, current_hash].pack('QQ') # Little-endian 64-bit
          final_hash = fnv1_64(combined_bytes)


          final_hash
        end

        # FNV-1a 64-bit hash function ( fnv1_64)
        def fnv1_64(data)
          # FNV-1a 64-bit constants
          fnv_offset_basis = 14695981039346656037 # 0xcbf29ce484222325
          fnv_prime = 1099511628211 # 0x100000001b3

          hash_value = fnv_offset_basis
          data.each_byte do |byte|
            hash_value ^= byte
            hash_value = (hash_value * fnv_prime) & 0xFFFFFFFFFFFFFFFF
          end
          hash_value
        end

        # Record stats for this checkpoint ( implementation)
        def record_checkpoint_stats(hash:, parent_hash:, edge_latency_sec:, payload_size:, tags:, timestamp_sec:)
          @stats_mutex.synchronize do
            # Calculate bucket time (align to bucket boundaries )
            now_ns = (timestamp_sec * 1e9).to_i
            bucket_time_ns = now_ns - (now_ns % @bucket_size_ns)


            # Get or create bucket for this time window
            bucket = @buckets[bucket_time_ns] ||= create_bucket

            # Get or create stats for this pathway ( aggr_key = (",".join(edge_tags), hash_value, parent_hash))
            aggr_key = [tags.join(','), hash, parent_hash]


            stats = bucket[:pathway_stats][aggr_key] ||= create_pathway_stats



            # Add latencies to DDSketch ()
            full_pathway_latency_sec = timestamp_sec - @pathway_context.pathway_start_sec
            stats[:edge_latency].add(edge_latency_sec)
            stats[:full_pathway_latency].add(full_pathway_latency_sec)
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

            # Ensure bucket exists for consumer data (even without checkpoints)
            now_ns = (timestamp_sec * 1e9).to_i
            bucket_time_ns = now_ns - (now_ns % @bucket_size_ns)
            @buckets[bucket_time_ns] ||= create_bucket
          end
        end

        # Aggregate consumer stats by topic and partition
        def aggregate_consumer_stats_by_partition(topic, partition, offset, timestamp_sec)
          # Track latest consumer offset progression for lag detection
          partition_key = "#{topic}:#{partition}"

          @stats_mutex.synchronize do
            @latest_consumer_offsets ||= {}
            previous_offset = @latest_consumer_offsets[partition_key] || 0

            # Calculate potential lag (gaps in offset sequence)
            if offset > previous_offset + 1
              # Gap detected - could indicate consumer lag
              @consumer_lag_events ||= []
              @consumer_lag_events << {
                topic: topic,
                partition: partition,
                expected_offset: previous_offset + 1,
                actual_offset: offset,
                gap_size: offset - previous_offset - 1,
                timestamp_sec: timestamp_sec
              }
            end

            # Update latest offset for this partition
            @latest_consumer_offsets[partition_key] = [offset, previous_offset].max
          end
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

        # Send stats payload to Datadog agent ( implementation)
        def send_stats_to_agent(payload)

          # Use msgpack encoding           require 'msgpack'
          msgpack_data = MessagePack.pack(payload)

          # Always compress  implementation
          compressed_data = gzip_compress(msgpack_data)

          # Headers  format
          headers = {
            'Content-Type' => 'application/msgpack',
            'Content-Encoding' => 'gzip',
            'Datadog-Meta-Lang' => 'ruby',
            'Datadog-Meta-Tracer-Version' => Datadog::VERSION::STRING
          }


          # Send to agent using proper transport infrastructure
          response = send_dsm_payload(compressed_data, headers)
          Datadog.logger.debug("DSM stats sent to agent: #{response.code} #{response.message}")
        end

        # Send DSM payload using proper transport infrastructure
        def send_dsm_payload(data, headers)
          require 'net/http'
          require 'uri'

          # Create HTTP request to DSM endpoint
          agent_host = Datadog.configuration.agent.host
          agent_port = Datadog.configuration.agent.port
          uri = URI("http://#{agent_host}:#{agent_port}/v0.1/pipeline_stats")

          http = Net::HTTP.new(uri.host, uri.port)
          http.use_ssl = false

          request = Net::HTTP::Post.new(uri)
          headers.each { |k, v| request[k] = v }

          # Set binary data with proper encoding
          request.body = data.force_encoding('ASCII-8BIT')

          http.request(request)
        end

        # Check if payload should be compressed
        def compress_payload?(payload)
          payload.to_json.bytesize > 1000 # Compress if > 1KB
        end

        # Gzip compress data
        def gzip_compress(data)
          require 'zlib'
          Zlib.gzip(data)
        end

        # Serialize buckets
        def serialize_buckets

          serialized_buckets = []
          bucket_keys_to_clear = []

          @buckets.each do |bucket_time_ns, bucket|

            bucket_keys_to_clear << bucket_time_ns

            # Serialize pathway stats for this bucket
            bucket_stats = []
            bucket[:pathway_stats].each_with_index do |(aggr_key, stats), index|
              edge_tags_str, hash_value, parent_hash = aggr_key

              edge_tags_array = edge_tags_str.split(',')

              bucket_stats << {
                'EdgeTags' => edge_tags_array,
                'Hash' => hash_value,
                'ParentHash' => parent_hash,
                'PathwayLatency' => stats[:full_pathway_latency].encode,
                'EdgeLatency' => stats[:edge_latency].encode,
              }
            end

            # Serialize offset backlogs for this bucket
            backlogs = []
            bucket[:latest_produce_offsets].each do |key, offset|
              topic, partition = key.split(':', 2)
              backlogs << {
                'Tags' => ['type:kafka_produce', "topic:#{topic}", "partition:#{partition}"],
                'Value' => offset
              }
            end
            bucket[:latest_commit_offsets].each do |key, offset|
              group, topic, partition = key.split(':', 3)
              backlogs << {
                'Tags' => ['type:kafka_commit', "consumer_group:#{group}", "topic:#{topic}", "partition:#{partition}"],
                'Value' => offset
              }
            end


            serialized_buckets << {
              'Start' => bucket_time_ns,
              'Duration' => @bucket_size_ns,
              'Stats' => bucket_stats,
              'Backlogs' => backlogs + serialize_consumer_backlogs
            }
          end


          # Clear processed buckets ()
          bucket_keys_to_clear.each { |key| @buckets.delete(key) }

          serialized_buckets
        end

        # Serialize consumer offset data as backlogs ()
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
          Core::Environment::Socket.hostname
        end

        # Create a new time bucket ( bucket structure)
        def create_bucket
          {
            pathway_stats: {},
            latest_produce_offsets: {},
            latest_commit_offsets: {}
          }
        end

        # Create pathway stats with DDSketch instances ( PathwayStats)
        def create_pathway_stats
          {
            edge_latency: @ddsketch_class.new,
            full_pathway_latency: @ddsketch_class.new,
            payload_size_sum: 0,
            payload_size_count: 0
          }
        end

        # Get default DDSketch class (real if available, fake for testing)
        def get_default_ddsketch_class
          require 'datadog/core/ddsketch'
          Datadog::Core::DDSketch.supported? ? Datadog::Core::DDSketch : FakeDDSketch
        rescue LoadError, NameError
          FakeDDSketch
        end

        # Get agent transport (using proper Datadog HTTP transport)
        def agent_transport
          @agent_transport ||= begin
            require_relative '../../transport/http'

            # Use the same transport infrastructure as traces
            agent_settings = Datadog.configuration.agent
            Datadog::Tracing::Transport::HTTP.default(
              agent_settings: agent_settings,
              logger: Datadog.logger
            )
          end
        end
      end
    end
  end
end

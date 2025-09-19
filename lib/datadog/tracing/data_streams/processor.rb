# frozen_string_literal: true

require 'json'
require 'datadog/core/ddsketch'
require_relative 'pathway_context'
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
          @bucket_size_ns = (10 * 1e9).to_i # 10 second buckets like Python
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

          # Get or create current context (matching Python threading.local behavior)
          current_context = get_current_context

          # Sort tags like Python (line 471)
          original_tags = tags.dup
          tags = tags.sort

          # DEBUG: Log the checkpoint creation details
          puts "🔍 [DSM DEBUG] set_checkpoint called:"
          puts "   Original tags: #{original_tags.inspect}"
          puts "   Sorted tags: #{tags.inspect}"
          puts "   Current context hash: #{current_context.hash}"
          puts "   Current context parent_hash: #{current_context.parent_hash}"
          puts "   Current context previous_direction: '#{current_context.previous_direction}'"

          # Extract direction like Python (lines 472-476)
          direction = ""
          tags.each do |tag|
            if tag.start_with?("direction:")
              direction = tag
              break
            end
          end

          # Loop detection logic (matching Python lines 477-489)
          # Only apply loop detection if there's a direction tag and it matches the previous direction
          puts "   🔍 [LOOP DEBUG] Direction: '#{direction}'"
          puts "   🔍 [LOOP DEBUG] Previous direction: '#{current_context.previous_direction}'"
          puts "   🔍 [LOOP DEBUG] Direction match: #{!direction.empty? && direction == current_context.previous_direction}"
          puts "   🔍 [LOOP DEBUG] Current hash before loop detection: #{current_context.hash}"
          puts "   🔍 [LOOP DEBUG] Closest opposite direction hash: #{current_context.closest_opposite_direction_hash}"

          if !direction.empty? && direction == current_context.previous_direction
            # Same direction - reuse hash from opposite direction
            puts "   🔍 [LOOP DEBUG] SAME DIRECTION - reusing opposite direction hash"
            current_context.hash = current_context.closest_opposite_direction_hash
            if current_context.hash == 0
              # Restart pathway if no opposite direction hash
              puts "   🔍 [LOOP DEBUG] Restarting pathway (hash was 0)"
              current_context.current_edge_start_sec = now_sec
              current_context.pathway_start_sec = now_sec
            else
              # Reuse edge start from opposite direction
              puts "   🔍 [LOOP DEBUG] Reusing edge start from opposite direction"
              current_context.current_edge_start_sec = current_context.closest_opposite_direction_edge_start
            end
          else
            # New direction or no direction - store current state for future reuse
            puts "   🔍 [LOOP DEBUG] NEW DIRECTION - storing current state"
            current_context.previous_direction = direction
            current_context.closest_opposite_direction_hash = current_context.hash
            current_context.closest_opposite_direction_edge_start = current_context.current_edge_start_sec
          end

          puts "   🔍 [LOOP DEBUG] Hash after loop detection: #{current_context.hash}"

          # Calculate new pathway hash from current hash + tags (matching Python line 498)
          parent_hash = current_context.hash
          new_hash = compute_pathway_hash(parent_hash, tags)

          # DEBUG: Log hash computation details
          puts "   Computed new_hash: #{new_hash}"
          puts "   Parent hash used: #{parent_hash}"
          puts "   Tags used for hash: #{tags.inspect}"

          # Calculate edge latency (time since last checkpoint) - matching Python line 501
          edge_latency_sec = [now_sec - current_context.current_edge_start_sec, 0.0].max
          full_pathway_latency_sec = [now_sec - current_context.pathway_start_sec, 0.0].max

          # DEBUG: Log latency calculations
          puts "   Edge latency: #{edge_latency_sec}s"
          puts "   Full pathway latency: #{full_pathway_latency_sec}s"

          # Record stats for this checkpoint
          record_checkpoint_stats(
            hash: new_hash,
            parent_hash: parent_hash,
            edge_latency_sec: edge_latency_sec,
            payload_size: payload_size,
            tags: tags,
            timestamp_sec: now_sec
          )

          # Update pathway context (matching Python lines 503-504)
          current_context.hash = new_hash
          current_context.current_edge_start_sec = now_sec

          # DEBUG: Log final state
          puts "   Final context hash: #{current_context.hash}"
          puts "   Final context parent_hash: #{current_context.parent_hash}"
          puts "   Final context previous_direction: '#{current_context.previous_direction}'"
          puts "   Final context closest_opposite_direction_hash: #{current_context.closest_opposite_direction_hash}"
          puts "🔍 [DSM DEBUG] set_checkpoint completed\n"

          # Return encoded context for propagation
          current_context.encode_b64
        end

        def track_kafka_produce(topic, partition, offset, now_sec)
          return nil unless @enabled

          now_ns = (now_sec * 1e9).to_i
          partition_key = "#{topic}:#{partition}"

          @stats_mutex.synchronize do
            # Calculate bucket time (align to bucket boundaries like Python)
            bucket_size_ns = 10 * 1e9 # 10 second buckets
            bucket_time_ns = now_ns - (now_ns % bucket_size_ns)

            # Track latest produce offset for this partition (like Python)
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
            # Calculate bucket time (align to bucket boundaries like Python)
            bucket_size_ns = 10 * 1e9 # 10 second buckets
            bucket_time_ns = now_ns - (now_ns % bucket_size_ns)

            # Track latest commit offset for this consumer group/partition (like Python)
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

        def flush_stats
          return unless @enabled

          @stats_mutex.synchronize do
            puts "🔍 [FLUSH DEBUG] Starting flush_stats"
            puts "🔍 [FLUSH DEBUG] Buckets count: #{@buckets.size}"
            puts "🔍 [FLUSH DEBUG] Consumer stats count: #{@consumer_stats.size}"
            
            # Check if we have data to send
            return if @buckets.empty? && @consumer_stats.empty?

            # Build payload matching Python implementation format
            stats_buckets = serialize_buckets

            payload = {
              'Service' => Datadog.configuration.service,
              'TracerVersion' => Datadog::VERSION::STRING,
              'Lang' => 'ruby',
              'Stats' => stats_buckets,
              'Hostname' => hostname
            }

            puts "🔍 [FLUSH DEBUG] Final payload structure:"
            puts "   Service: #{payload['Service']}"
            puts "   TracerVersion: #{payload['TracerVersion']}"
            puts "   Lang: #{payload['Lang']}"
            puts "   Hostname: #{payload['Hostname']}"
            puts "   Stats buckets count: #{payload['Stats'].size}"
            payload['Stats'].each_with_index do |bucket, index|
              puts "     Bucket #{index}: Start=#{bucket['Start']}, Stats count=#{bucket['Stats'].size}"
            end

            # Send to agent (msgpack + gzip like Python)
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

        # Get or create current context (matching Python threading.local behavior)
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

        # Compute new pathway hash using FNV-1a algorithm (matching Python implementation)
        # Combines service, env, tags, and parent hash to create unique pathway identifier
        def compute_pathway_hash(current_hash, tags)
          # Get service and environment (matching Python: self.service + self.env)
          service = Datadog.configuration.service || 'ruby-service'
          env = Datadog.configuration.env || 'none'

          # Build byte string: service + env + tags (matching Python)
          bytes = service.bytes + env.bytes
          tags.each { |tag| bytes += tag.bytes }

          # Convert to string for FNV function
          byte_string = bytes.pack('C*')

          # First hash: FNV-1a of service + env + tags (matching Python node_hash)
          node_hash = fnv1_64(byte_string)

          # Second hash: FNV-1a of (node_hash + parent_hash) (matching Python)
          combined_bytes = [node_hash, current_hash].pack('QQ') # Little-endian 64-bit
          final_hash = fnv1_64(combined_bytes)

          # DEBUG: Log hash computation details
          puts "   🔍 [HASH DEBUG] compute_pathway_hash:"
          puts "      Service: '#{service}'"
          puts "      Env: '#{env}'"
          puts "      Tags: #{tags.inspect}"
          puts "      Byte string length: #{byte_string.length}"
          puts "      Byte string hex: #{byte_string.unpack('H*').first}"
          puts "      Node hash: #{node_hash}"
          puts "      Parent hash: #{current_hash}"
          puts "      Combined bytes hex: #{combined_bytes.unpack('H*').first}"
          puts "      Final hash: #{final_hash}"

          final_hash
        end

        # FNV-1a 64-bit hash function (matching Python fnv1_64)
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

        # Record stats for this checkpoint (matching Python implementation)
        def record_checkpoint_stats(hash:, parent_hash:, edge_latency_sec:, payload_size:, tags:, timestamp_sec:)
          @stats_mutex.synchronize do
            # Calculate bucket time (align to bucket boundaries like Python)
            now_ns = (timestamp_sec * 1e9).to_i
            bucket_time_ns = now_ns - (now_ns % @bucket_size_ns)
            
            puts "🔍 [BUCKET TIME DEBUG] Bucket time calculation:"
            puts "   Timestamp sec: #{timestamp_sec}"
            puts "   Now ns: #{now_ns}"
            puts "   Bucket size ns: #{@bucket_size_ns}"
            puts "   Now % bucket_size: #{now_ns % @bucket_size_ns}"
            puts "   Calculated bucket_time_ns: #{bucket_time_ns}"

            # Get or create bucket for this time window
            bucket = @buckets[bucket_time_ns] ||= create_bucket

            # Get or create stats for this pathway (Python: aggr_key = (",".join(edge_tags), hash_value, parent_hash))
            aggr_key = [tags.join(','), hash, parent_hash]
            
            puts "🔍 [BUCKET DEBUG] Before adding to bucket:"
            puts "   Bucket time: #{bucket_time_ns}"
            puts "   Existing pathway_stats keys: #{bucket[:pathway_stats].keys.map(&:inspect)}"
            puts "   New aggr_key: #{aggr_key.inspect}"
            puts "   Key exists? #{bucket[:pathway_stats].key?(aggr_key)}"
            
            stats = bucket[:pathway_stats][aggr_key] ||= create_pathway_stats
            
            puts "🔍 [BUCKET DEBUG] After adding to bucket:"
            puts "   Total pathway_stats keys: #{bucket[:pathway_stats].keys.size}"
            puts "   All keys: #{bucket[:pathway_stats].keys.map(&:inspect)}"

            # DEBUG: Log aggregation key details
            puts "   🔍 [AGGREGATION DEBUG] record_checkpoint_stats:"
            puts "      Tags: #{tags.inspect}"
            puts "      Tags joined: '#{tags.join(',')}'"
            puts "      Hash: #{hash}"
            puts "      Parent hash: #{parent_hash}"
            puts "      Aggregation key: #{aggr_key.inspect}"
            puts "      Bucket time: #{bucket_time_ns}"

            # Add latencies to DDSketch (like Python)
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

        # Send stats payload to Datadog agent (matching Python implementation)
        def send_stats_to_agent(payload)
          puts "🔍 [AGENT PAYLOAD DEBUG] Raw payload being sent to agent:"
          puts "   Service: #{payload['Service']}"
          puts "   TracerVersion: #{payload['TracerVersion']}"
          puts "   Lang: #{payload['Lang']}"
          puts "   Hostname: #{payload['Hostname']}"
          puts "   Stats count: #{payload['Stats'].size}"
          
          payload['Stats'].each_with_index do |bucket, bucket_index|
            puts "   Bucket #{bucket_index}:"
            puts "     Start: #{bucket['Start']}"
            puts "     Duration: #{bucket['Duration']}"
            puts "     Stats count: #{bucket['Stats'].size}"
            puts "     Backlogs count: #{bucket['Backlogs'].size}"
            
            bucket['Stats'].each_with_index do |stat, stat_index|
              puts "     Stat #{stat_index}:"
              puts "       EdgeTags: #{stat['EdgeTags']}"
              puts "       Hash: #{stat['Hash']}"
              puts "       ParentHash: #{stat['ParentHash']}"
              puts "       PathwayLatency: #{stat['PathwayLatency'].class} (encoded)"
              puts "       EdgeLatency: #{stat['EdgeLatency'].class} (encoded)"
            end
          end
          
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
            'Datadog-Meta-Tracer-Version' => Datadog::VERSION::STRING
          }

          puts "🔍 [AGENT PAYLOAD DEBUG] Payload sizes:"
          puts "   Raw payload size: #{payload.to_json.bytesize} bytes"
          puts "   Msgpack size: #{msgpack_data.bytesize} bytes"
          puts "   Compressed size: #{compressed_data.bytesize} bytes"

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
          request.body = data

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

        # Serialize buckets to match Python implementation format
        def serialize_buckets
          puts "🔍 [SERIALIZE DEBUG] Starting serialize_buckets"
          puts "🔍 [SERIALIZE DEBUG] Total buckets: #{@buckets.size}"
          
          serialized_buckets = []
          bucket_keys_to_clear = []

          @buckets.each do |bucket_time_ns, bucket|
            puts "🔍 [SERIALIZE DEBUG] Processing bucket: #{bucket_time_ns}"
            puts "🔍 [SERIALIZE DEBUG] Bucket pathway_stats count: #{bucket[:pathway_stats].size}"
            
            bucket_keys_to_clear << bucket_time_ns

            # Serialize pathway stats for this bucket
            bucket_stats = []
            bucket[:pathway_stats].each_with_index do |(aggr_key, stats), index|
              edge_tags_str, hash_value, parent_hash = aggr_key
              puts "🔍 [SERIALIZE DEBUG] Entry #{index}:"
              puts "   Aggr key: #{aggr_key.inspect}"
              puts "   Edge tags str: '#{edge_tags_str}'"
              puts "   Hash value: #{hash_value}"
              puts "   Parent hash: #{parent_hash}"
              puts "   Stats keys: #{stats.keys}"
              
              bucket_stats << {
                'EdgeTags' => edge_tags_str.split(','),
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

            puts "🔍 [SERIALIZE DEBUG] Final bucket_stats count: #{bucket_stats.size}"
            puts "🔍 [SERIALIZE DEBUG] Final backlogs count: #{backlogs.size}"
            
            serialized_buckets << {
              'Start' => bucket_time_ns,
              'Duration' => @bucket_size_ns,
              'Stats' => bucket_stats,
              'Backlogs' => backlogs + serialize_consumer_backlogs
            }
          end

          puts "🔍 [SERIALIZE DEBUG] Total serialized buckets: #{serialized_buckets.size}"
          puts "🔍 [SERIALIZE DEBUG] Serialized buckets structure:"
          serialized_buckets.each_with_index do |bucket, index|
            puts "   Bucket #{index}: Start=#{bucket['Start']}, Stats count=#{bucket['Stats'].size}"
            bucket['Stats'].each_with_index do |stat, stat_index|
              puts "     Stat #{stat_index}: EdgeTags=#{stat['EdgeTags']}, Hash=#{stat['Hash']}, ParentHash=#{stat['ParentHash']}"
            end
          end

          # Clear processed buckets (like Python)
          bucket_keys_to_clear.each { |key| @buckets.delete(key) }

          serialized_buckets
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
          Core::Environment::Socket.hostname
        end

        # Create a new time bucket (matching Python bucket structure)
        def create_bucket
          {
            pathway_stats: {},
            latest_produce_offsets: {},
            latest_commit_offsets: {}
          }
        end

        # Create pathway stats with DDSketch instances (matching Python PathwayStats)
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

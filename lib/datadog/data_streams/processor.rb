# frozen_string_literal: true

require 'zlib'
require_relative 'pathway_context'
require_relative 'transport/http'
require_relative '../version'
require_relative '../core/worker'
require_relative '../core/workers/polling'
require_relative '../core/ddsketch'
require_relative '../core/buffer/cruby'
require_relative '../core/utils/time'
require_relative '../core/utils/fnv'

module Datadog
  module DataStreams
    # Raised when Data Streams Monitoring cannot be initialized due to missing dependencies
    class UnsupportedError < StandardError; end

    # Processor for Data Streams Monitoring
    # This class is responsible for collecting and reporting pathway stats
    # Periodically (every interval, 10 seconds by default) flushes stats to the Datadog agent.
    class Processor < Core::Worker
      include Core::Workers::Polling

      PROPAGATION_KEY = 'dd-pathway-ctx-base64'

      # Default buffer size for lock-free event queue
      # Set to handle high-throughput scenarios (e.g., 10k events/sec for 10s interval)
      DEFAULT_BUFFER_SIZE = 100_000

      attr_reader :pathway_context, :buckets, :bucket_size_ns

      # Initialize the Data Streams Monitoring processor
      #
      # @param interval [Float] Flush interval in seconds (e.g., 10.0 for 10 seconds)
      # @param logger [Datadog::Core::Logger] Logger instance for debugging
      # @param settings [Datadog::Core::Configuration::Settings] Global configuration settings
      # @param agent_settings [Datadog::Core::Configuration::AgentSettings] Agent connection settings
      # @param buffer_size [Integer] Size of the lock-free event buffer for async stat collection
      #   (default: DEFAULT_BUFFER_SIZE). Higher values support more throughput but use more memory.
      # @raise [UnsupportedError] if DDSketch is not available on this platform
      def initialize(interval:, logger:, settings:, agent_settings:, buffer_size: DEFAULT_BUFFER_SIZE)
        raise UnsupportedError, 'DDSketch is not supported' unless Datadog::Core::DDSketch.supported?

        @settings = settings
        @agent_settings = agent_settings
        @logger = logger

        now = Core::Utils::Time.now
        @pathway_context = PathwayContext.new(
          hash_value: 0,
          pathway_start: now,
          current_edge_start: now
        )
        @bucket_size_ns = (interval * 1e9).to_i
        @buckets = {}
        @consumer_stats = []
        @stats_mutex = Mutex.new
        @event_buffer = Core::Buffer::CRuby.new(buffer_size)

        super()
        self.loop_base_interval = interval

        perform
      end

      # Track Kafka produce offset for lag monitoring
      # @param topic [String] The Kafka topic name
      # @param partition [Integer] The partition number
      # @param offset [Integer] The offset of the produced message
      # @param now [Time] Timestamp
      # @return [Boolean] true if tracking succeeded
      def track_kafka_produce(topic, partition, offset, now)
        @event_buffer.push(
          {
            type: :kafka_produce,
            topic: topic,
            partition: partition,
            offset: offset,
            timestamp_ns: (now.to_f * 1e9).to_i
          }
        )
        true
      end

      # Track Kafka message consumption for consumer lag monitoring
      # @param topic [String] The Kafka topic name
      # @param partition [Integer] The partition number
      # @param offset [Integer] The offset of the consumed message
      # @param now [Time] Timestamp
      # @return [Boolean] true if tracking succeeded
      def track_kafka_consume(topic, partition, offset, now)
        @event_buffer.push(
          {
            type: :kafka_consume,
            topic: topic,
            partition: partition,
            offset: offset,
            timestamp: now
          }
        )
        true
      end

      # Set a produce checkpoint
      # @param type [String] The type of the checkpoint (e.g., 'kafka', 'kinesis', 'sns')
      # @param destination [String] The destination (e.g., topic, exchange, stream name)
      # @param manual_checkpoint [Boolean] Whether this checkpoint was manually set (default: true)
      # @param tags [Hash] Additional tags to include
      # @yield [key, value] Block to inject context into carrier
      # @return [String] Base64 encoded pathway context
      def set_produce_checkpoint(type:, destination:, manual_checkpoint: true, tags: {}, &block)
        checkpoint_tags = ["type:#{type}", "topic:#{destination}", 'direction:out']
        checkpoint_tags << 'manual_checkpoint:true' if manual_checkpoint
        checkpoint_tags.concat(tags.map { |k, v| "#{k}:#{v}" }) unless tags.empty?

        span = Datadog::Tracing.active_span
        pathway = set_checkpoint(tags: checkpoint_tags, span: span)

        yield(PROPAGATION_KEY, pathway) if pathway && block

        pathway
      end

      # Set a consume checkpoint
      # @param type [String] The type of the checkpoint (e.g., 'kafka', 'kinesis', 'sns')
      # @param source [String] The source (e.g., topic, exchange, stream name)
      # @param manual_checkpoint [Boolean] Whether this checkpoint was manually set (default: true)
      # @param tags [Hash] Additional tags to include
      # @yield [key] Block to extract context from carrier
      # @return [String] Base64 encoded pathway context
      def set_consume_checkpoint(type:, source:, manual_checkpoint: true, tags: {}, &block)
        if block
          pathway_ctx = yield(PROPAGATION_KEY)
          if pathway_ctx
            decoded_ctx = decode_pathway_b64(pathway_ctx)
            set_pathway_context(decoded_ctx)
          end
        end

        checkpoint_tags = ["type:#{type}", "topic:#{source}", 'direction:in']
        checkpoint_tags << 'manual_checkpoint:true' if manual_checkpoint
        checkpoint_tags.concat(tags.map { |k, v| "#{k}:#{v}" }) unless tags.empty?

        span = Datadog::Tracing.active_span
        set_checkpoint(tags: checkpoint_tags, span: span)
      end

      # Called periodically by the worker to flush stats to the agent
      def perform
        process_events
        flush_stats
        true
      end

      private

      # Drain event buffer and apply updates to shared data structures
      # This runs in the background worker thread, not the critical path
      def process_events
        events = @event_buffer.pop
        return if events.empty?

        @stats_mutex.synchronize do
          events.each do |event_obj|
            # Buffer stores Objects; we know they're hashes with symbol keys
            event = event_obj # : ::Hash[::Symbol, untyped]
            case event[:type]
            when :kafka_produce
              process_kafka_produce_event(event)
            when :kafka_consume
              process_kafka_consume_event(event)
            when :checkpoint
              process_checkpoint_event(event)
            end
          end
        end
      end

      def process_kafka_produce_event(event)
        partition_key = "#{event[:topic]}:#{event[:partition]}"
        bucket_time_ns = event[:timestamp_ns] - (event[:timestamp_ns] % @bucket_size_ns)
        bucket = @buckets[bucket_time_ns] ||= create_bucket

        bucket[:latest_produce_offsets][partition_key] = [
          event[:offset],
          bucket[:latest_produce_offsets][partition_key] || 0
        ].max
      end

      def process_kafka_consume_event(event)
        @consumer_stats << {
          topic: event[:topic],
          partition: event[:partition],
          offset: event[:offset],
          timestamp: event[:timestamp],
          timestamp_sec: event[:timestamp].to_f
        }

        timestamp_ns = (event[:timestamp].to_f * 1e9).to_i
        bucket_time_ns = timestamp_ns - (timestamp_ns % @bucket_size_ns)
        @buckets[bucket_time_ns] ||= create_bucket

        # Track offset gaps for lag detection
        partition_key = "#{event[:topic]}:#{event[:partition]}"
        @latest_consumer_offsets ||= {}
        previous_offset = @latest_consumer_offsets[partition_key] || 0

        if event[:offset] > previous_offset + 1
          @consumer_lag_events ||= []
          @consumer_lag_events << {
            topic: event[:topic],
            partition: event[:partition],
            expected_offset: previous_offset + 1,
            actual_offset: event[:offset],
            gap_size: event[:offset] - previous_offset - 1,
            timestamp_sec: event[:timestamp].to_f
          }
        end

        @latest_consumer_offsets[partition_key] = [event[:offset], previous_offset].max
      end

      def process_checkpoint_event(event)
        now_ns = (event[:timestamp_sec] * 1e9).to_i
        bucket_time_ns = now_ns - (now_ns % @bucket_size_ns)
        bucket = @buckets[bucket_time_ns] ||= create_bucket

        aggr_key = [event[:tags].join(','), event[:hash], event[:parent_hash]]
        stats = bucket[:pathway_stats][aggr_key] ||= create_pathway_stats

        stats[:edge_latency].add(event[:edge_latency_sec])
        stats[:full_pathway_latency].add(event[:full_pathway_latency_sec])
      end

      def encode_pathway_context
        @pathway_context.encode_b64
      end

      def set_checkpoint(tags:, now: nil, payload_size: 0, span: nil)
        now ||= Core::Utils::Time.now

        current_context = get_current_context
        tags = tags.sort

        direction = nil #: ::String?
        tags.each do |tag|
          if tag.start_with?('direction:')
            direction = tag
            break
          end
        end

        # Loop detection: consecutive same-direction checkpoints reuse the opposite direction's hash
        if direction && direction == current_context.previous_direction
          current_context.hash = current_context.closest_opposite_direction_hash
          if current_context.hash == 0
            current_context.current_edge_start = now
            current_context.pathway_start = now
          else
            current_context.current_edge_start = current_context.closest_opposite_direction_edge_start
          end
        else
          current_context.previous_direction = direction
          current_context.closest_opposite_direction_hash = current_context.hash
          current_context.closest_opposite_direction_edge_start = current_context.current_edge_start
        end

        parent_hash = current_context.hash
        new_hash = compute_pathway_hash(parent_hash, tags)

        # Tag the APM span with the pathway hash to link DSM and APM
        span&.set_tag('pathway.hash', new_hash.to_s)

        edge_latency_sec = [now - current_context.current_edge_start, 0.0].max
        full_pathway_latency_sec = [now - current_context.pathway_start, 0.0].max

        record_checkpoint_stats(
          hash: new_hash,
          parent_hash: parent_hash,
          edge_latency_sec: edge_latency_sec,
          full_pathway_latency_sec: full_pathway_latency_sec,
          payload_size: payload_size,
          tags: tags,
          timestamp_sec: now.to_f
        )

        current_context.parent_hash = current_context.hash
        current_context.hash = new_hash
        current_context.current_edge_start = now

        current_context.encode_b64
      end

      def decode_pathway_context(encoded_ctx)
        PathwayContext.decode_b64(encoded_ctx)
      end

      def decode_pathway_b64(encoded_ctx)
        PathwayContext.decode_b64(encoded_ctx)
      end

      def flush_stats
        payload = nil # : ::Hash[::String, untyped]?

        @stats_mutex.synchronize do
          return if @buckets.empty? && @consumer_stats.empty?

          stats_buckets = serialize_buckets

          payload = {
            'Service' => @settings.service,
            'TracerVersion' => Datadog::VERSION::STRING,
            'Lang' => 'ruby',
            'Stats' => stats_buckets,
            'Hostname' => hostname
          }

          if @settings.experimental_propagate_process_tags_enabled && payload
            process_tags = Core::Environment::Process.serialized
            # Datadog Agent expects an array of tag strings, not a single serialized string
            # Otherwise it fails at "Error decoding request msgp: attempted to decode type \"str\" with method for \"array\" at ProcessTags"}
            # Split "key1:val1,key2:val2" into ["key1:val1", "key2:val2"]
            unless process_tags.empty?
              payload['ProcessTags'] = process_tags.split(',')
            end
          end

          # Clear consumer stats even if sending fails to prevent unbounded memory growth
          # Must be done inside mutex before we release it
          @consumer_stats.clear
        end

        # Send to agent outside mutex to avoid blocking customer code if agent is slow/hung
        send_stats_to_agent(payload) if payload
      rescue => e
        @logger.debug("Failed to flush DSM stats to agent: #{e.class}: #{e}")
      end

      def get_current_pathway
        get_current_context
      end

      def get_current_context
        @pathway_context ||= begin
          now = Core::Utils::Time.now
          PathwayContext.new(
            hash_value: 0,
            pathway_start: now,
            current_edge_start: now
          )
        end
      end

      def set_pathway_context(ctx)
        if ctx
          @pathway_context = ctx
          @pathway_context.previous_direction = nil
          @pathway_context.closest_opposite_direction_hash = 0
          @pathway_context.closest_opposite_direction_edge_start = @pathway_context.current_edge_start
        end
      end

      def decode_and_set_pathway_context(headers)
        return unless headers && headers['dd-pathway-ctx-base64']

        pathway_ctx = decode_pathway_context(headers['dd-pathway-ctx-base64'])
        set_pathway_context(pathway_ctx) if pathway_ctx
      end

      # Compute new pathway hash using FNV-1a algorithm.
      # Combines service, env, tags, and parent hash to create unique pathway identifier.
      def compute_pathway_hash(current_hash, tags)
        service = @settings.service || 'ruby-service'
        env = @settings.env || 'none'

        bytes = service.bytes + env.bytes

        # If there is a propagation checksum, add it to DSM back propagation
        # Follows Python: https://github.com/DataDog/dd-trace-py/blob/8b739fe0837a22cab76116050e8b7e4b45407c6c/ddtrace/internal/datastreams/processor.py#L423
        # bytes order is service + env + process tags + container tags
        if @settings.experimental_propagate_process_tags_enabled
          propagation_checksum = Datadog.send(:components).agent_info.propagation_checksum
          if propagation_checksum
            bytes += [propagation_checksum].pack('Q<').bytes
          end
        end

        tags.each { |tag| bytes += tag.bytes }
        byte_string = bytes.pack('C*')

        node_hash = Core::Utils::FNV.fnv1_64(byte_string)
        combined_bytes = [node_hash, current_hash].pack('QQ')
        Core::Utils::FNV.fnv1_64(combined_bytes)
      end

      def record_checkpoint_stats(
        hash:, parent_hash:, edge_latency_sec:, full_pathway_latency_sec:, payload_size:, tags:,
        timestamp_sec:
      )
        @event_buffer.push(
          {
            type: :checkpoint,
            hash: hash,
            parent_hash: parent_hash,
            edge_latency_sec: edge_latency_sec,
            full_pathway_latency_sec: full_pathway_latency_sec,
            payload_size: payload_size,
            tags: tags,
            timestamp_sec: timestamp_sec
          }
        )
        true
      end

      def record_consumer_stats(topic:, partition:, offset:, timestamp:)
        # Already handled by track_kafka_consume pushing to buffer
        # This method kept for API compatibility but does nothing
      end

      def send_stats_to_agent(payload)
        response = transport.send_stats(payload)
        @logger.debug("DSM stats sent to agent: ok=#{response.ok?}")
      end

      def transport
        @transport ||= Transport::HTTP.default(
          agent_settings: @agent_settings,
          logger: @logger
        )
      end

      def serialize_buckets
        serialized_buckets = []
        bucket_keys_to_clear = []

        @buckets.each do |bucket_time_ns, bucket|
          bucket_keys_to_clear << bucket_time_ns

          bucket_stats = []
          bucket[:pathway_stats].each do |aggr_key, stats|
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

        bucket_keys_to_clear.each { |key| @buckets.delete(key) }

        serialized_buckets
      end

      def serialize_consumer_backlogs
        @consumer_stats.map do |stat|
          {
            'Tags' => [
              'type:kafka_commit',
              "topic:#{stat[:topic]}",
              "partition:#{stat[:partition]}"
            ],
            'Value' => stat[:offset]
          }
        end
      end

      def hostname
        Core::Environment::Socket.hostname
      end

      def create_bucket
        {
          pathway_stats: {},
          latest_produce_offsets: {},
          latest_commit_offsets: {}
        }
      end

      def create_pathway_stats
        {
          edge_latency: Datadog::Core::DDSketch.new,
          full_pathway_latency: Datadog::Core::DDSketch.new,
          payload_size_sum: 0,
          payload_size_count: 0
        }
      end
    end
  end
end

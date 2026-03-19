# frozen_string_literal: true

require 'msgpack'
require_relative '../../version'
require_relative '../../core/environment/socket'
require_relative 'ext'

module Datadog
  module Tracing
    module Stats
      # Serializes stats buckets into the ClientStatsPayload msgpack format
      # expected by the agent's /v0.6/stats endpoint.
      #
      # Wire format (ClientStatsPayload):
      #   Hostname    string
      #   Env         string
      #   Version     string
      #   Stats       []ClientStatsBucket
      #   Lang        string
      #   TracerVersion string
      #   RuntimeID   string
      #   Sequence    uint64
      #   AgentAggregation string
      #   Service     string
      #   ContainerID string
      #   Tags        []string
      #
      # ClientStatsBucket:
      #   Start       uint64 (nanoseconds)
      #   Duration    uint64 (nanoseconds)
      #   Stats       []ClientGroupedStats
      #
      # ClientGroupedStats:
      #   Service     string
      #   Name        string
      #   Resource    string
      #   HTTPStatusCode uint32
      #   Type        string
      #   DBType      string
      #   Hits        uint64
      #   Errors      uint64
      #   Duration    uint64
      #   OkSummary   bytes (encoded DDSketch)
      #   ErrorSummary bytes (encoded DDSketch)
      #   Synthetics  bool
      #   TopLevelHits uint64
      #   SpanKind    string
      #   PeerTags    []string
      #   IsTraceRoot int32  (Trilean)
      #   GRPCStatusCode uint32
      #   HTTPMethod  string
      #   HTTPEndpoint string
      module Serializer
        module_function

        # Serialize a flush result into a ClientStatsPayload hash suitable for msgpack encoding.
        #
        # @param flushed_buckets [Hash] bucket_time => { key => group_stats }
        # @param env [String, nil] the environment tag
        # @param service [String, nil] the service name
        # @param version [String, nil] the application version
        # @param runtime_id [String] the runtime ID for this process
        # @param sequence [Integer] monotonically increasing sequence number
        # @param container_id [String, nil] container ID if running in a container
        # @return [Hash] the serialized payload
        def serialize(
          flushed_buckets,
          env:,
          service:,
          version: nil,
          runtime_id: '',
          sequence: 0,
          container_id: ''
        )
          {
            'Hostname' => hostname,
            'Env' => env || '',
            'Version' => version || '',
            'Stats' => serialize_buckets(flushed_buckets),
            'Lang' => 'ruby',
            'TracerVersion' => Datadog::VERSION::STRING,
            'RuntimeID' => runtime_id,
            'Sequence' => sequence,
            'AgentAggregation' => '',
            'Service' => service || '',
            'ContainerID' => container_id || '',
            'Tags' => [],
          }
        end

        # Encode the payload as msgpack bytes.
        #
        # @param payload [Hash] the serialized payload from {.serialize}
        # @return [String] msgpack-encoded bytes
        def encode(payload)
          MessagePack.pack(payload)
        end

        # @param flushed_buckets [Hash] bucket_time => { key => group_stats }
        # @return [Array<Hash>]
        def serialize_buckets(flushed_buckets)
          flushed_buckets.map do |bucket_time, groups|
            {
              'Start' => bucket_time,
              'Duration' => Ext::BUCKET_DURATION_NS,
              'Stats' => serialize_groups(groups),
            }
          end
        end

        # @param groups [Hash] aggregation_key => group_stats
        # @return [Array<Hash>]
        def serialize_groups(groups)
          groups.map do |key, stats|
            {
              'Service' => key.service,
              'Name' => key.name,
              'Resource' => key.resource,
              'HTTPStatusCode' => key.http_status_code,
              'Type' => key.type,
              'DBType' => '',
              'Hits' => stats[:hits],
              'Errors' => stats[:errors],
              'Duration' => stats[:duration],
              'OkSummary' => encode_sketch(stats[:ok_distribution]),
              'ErrorSummary' => encode_sketch(stats[:error_distribution]),
              'Synthetics' => key.synthetics,
              'TopLevelHits' => stats[:top_level_hits],
              'SpanKind' => key.span_kind,
              'PeerTags' => key.peer_tags,
              'IsTraceRoot' => key.is_trace_root,
              'GRPCStatusCode' => key.grpc_status_code,
              'HTTPMethod' => key.http_method,
              'HTTPEndpoint' => key.http_endpoint,
            }
          end
        end

        # Encode a DDSketch into its protobuf representation.
        #
        # @param sketch [Datadog::Core::DDSketch]
        # @return [String] encoded bytes (empty string if sketch is not supported)
        def encode_sketch(sketch)
          return ''.b unless sketch.respond_to?(:encode)

          sketch.encode
        rescue => _e
          ''.b
        end

        # @return [String] the hostname
        def hostname
          Core::Environment::Socket.hostname
        rescue => _e
          ''
        end
      end
    end
  end
end

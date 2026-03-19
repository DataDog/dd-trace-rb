# frozen_string_literal: true

module Datadog
  module Tracing
    module Stats
      # Constants for client-side stats computation
      module Ext
        ENV_ENABLED = 'DD_TRACE_STATS_COMPUTATION_ENABLED'

        # Time bucket duration in nanoseconds (10 seconds)
        BUCKET_DURATION_NS = 10_000_000_000

        # DDSketch parameters
        DDSKETCH_RELATIVE_ACCURACY = 0.01
        DDSKETCH_MAX_BINS = 2048

        # Trilean values for is_trace_root
        TRILEAN_NOT_SET = 0
        TRILEAN_TRUE = 1
        TRILEAN_FALSE = 2

        # gRPC status code tag names (in priority order)
        GRPC_STATUS_CODE_TAGS = [
          'rpc.grpc.status_code',
          'grpc.code',
          'rpc.grpc.status.code',
          'grpc.status.code',
        ].freeze

        # Span kinds that make a span eligible for stats
        ELIGIBLE_SPAN_KINDS = %w[server client producer consumer].freeze

        # Span kinds that use peer tags
        PEER_TAG_SPAN_KINDS = %w[client producer consumer].freeze

        # Tags used for peer_tags aggregation
        PEER_TAG_KEYS = %w[
          _dd.base_service
          peer.service
          peer.hostname
          out.host
          db.instance
          db.system
          messaging.destination
          network.destination.name
        ].freeze
      end
    end
  end
end

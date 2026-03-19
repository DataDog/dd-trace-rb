# frozen_string_literal: true

module Datadog
  module Tracing
    module Stats
      # Represents the 12-dimension aggregation key for client-side stats.
      #
      # Each unique combination of these dimensions maps to a separate stats group
      # within a time bucket, tracking hits, errors, duration, and latency distributions.
      class AggregationKey
        attr_reader :service,
          :name,
          :resource,
          :type,
          :http_status_code,
          :grpc_status_code,
          :span_kind,
          :synthetics,
          :is_trace_root,
          :peer_tags,
          :http_method,
          :http_endpoint

        def initialize(
          service:,
          name:,
          resource:,
          type: '',
          http_status_code: 0,
          grpc_status_code: 0,
          span_kind: '',
          synthetics: false,
          is_trace_root: Ext::TRILEAN_NOT_SET,
          peer_tags: nil,
          http_method: '',
          http_endpoint: ''
        )
          @service = service || ''
          @name = name || ''
          @resource = resource || ''
          @type = type || ''
          @http_status_code = http_status_code || 0
          @grpc_status_code = grpc_status_code || 0
          @span_kind = span_kind || ''
          @synthetics = synthetics || false
          @is_trace_root = is_trace_root || Ext::TRILEAN_NOT_SET
          @peer_tags = peer_tags || []
          @http_method = http_method || ''
          @http_endpoint = http_endpoint || ''
        end

        def ==(other)
          other.is_a?(AggregationKey) &&
            @service == other.service &&
            @name == other.name &&
            @resource == other.resource &&
            @type == other.type &&
            @http_status_code == other.http_status_code &&
            @grpc_status_code == other.grpc_status_code &&
            @span_kind == other.span_kind &&
            @synthetics == other.synthetics &&
            @is_trace_root == other.is_trace_root &&
            @peer_tags == other.peer_tags &&
            @http_method == other.http_method &&
            @http_endpoint == other.http_endpoint
        end

        alias_method :eql?, :==

        def hash
          [
            @service, @name, @resource, @type,
            @http_status_code, @grpc_status_code,
            @span_kind, @synthetics, @is_trace_root,
            @peer_tags, @http_method, @http_endpoint,
          ].hash
        end
      end
    end
  end
end

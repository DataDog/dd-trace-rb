# frozen_string_literal: true

require_relative '../metadata/ext'
require_relative 'ext'
require_relative 'aggregation_key'

module Datadog
  module Tracing
    module Stats
      # Builds an AggregationKey from a span, extracting the 12 aggregation dimensions.
      module KeyBuilder
        module_function

        # Build an AggregationKey from a span.
        #
        # @param span [Datadog::Tracing::Span] the span to extract dimensions from
        # @param synthetics [Boolean] whether the trace originates from a Synthetics test
        # @param agent_peer_tags [Array<String>, nil] peer tags from the agent /info response
        # @return [AggregationKey]
        def build(span, synthetics: false, agent_peer_tags: nil)
          AggregationKey.new(
            service: span.service,
            name: span.name,
            resource: span.resource,
            type: span.type,
            http_status_code: extract_http_status_code(span),
            grpc_status_code: extract_grpc_status_code(span),
            span_kind: extract_span_kind(span),
            synthetics: synthetics,
            is_trace_root: extract_is_trace_root(span),
            peer_tags: extract_peer_tags(span, agent_peer_tags),
            http_method: extract_http_method(span),
            http_endpoint: extract_http_endpoint(span),
          )
        end

        # @param span [Datadog::Tracing::Span]
        # @return [Integer] HTTP status code, or 0 if not present
        def extract_http_status_code(span)
          code = span.meta[Metadata::Ext::HTTP::TAG_STATUS_CODE]
          return 0 if code.nil?

          code.to_i
        end

        # @param span [Datadog::Tracing::Span]
        # @return [Integer] gRPC status code, or 0 if not present
        def extract_grpc_status_code(span)
          Ext::GRPC_STATUS_CODE_TAGS.each do |tag|
            code = span.meta[tag]
            return code.to_i unless code.nil?
          end

          0
        end

        # @param span [Datadog::Tracing::Span]
        # @return [String] span kind, or empty string
        def extract_span_kind(span)
          span.meta.fetch(Metadata::Ext::TAG_KIND, '')
        end

        # @param span [Datadog::Tracing::Span]
        # @return [Integer] Trilean value for is_trace_root
        def extract_is_trace_root(span)
          if span.parent_id == 0
            Ext::TRILEAN_TRUE
          else
            Ext::TRILEAN_FALSE
          end
        end

        # Extract peer tags for client/producer/consumer spans.
        #
        # For spans with kind internal that have _dd.base_service set
        # (service override), also include peer tags.
        #
        # @param span [Datadog::Tracing::Span]
        # @param agent_peer_tags [Array<String>, nil] peer tag keys from agent /info
        # @return [Array<String>] sorted list of "key:value" peer tag strings
        def extract_peer_tags(span, agent_peer_tags)
          kind = span.meta.fetch(Metadata::Ext::TAG_KIND, '')

          # Determine if we should collect peer tags
          should_collect = Ext::PEER_TAG_SPAN_KINDS.include?(kind)

          # For internal spans with a service override (_dd.base_service set),
          # also collect peer tags
          if !should_collect && kind == Metadata::Ext::SpanKind::TAG_INTERNAL
            should_collect = span.meta.key?('_dd.base_service')
          end

          return [] unless should_collect

          # Use agent-provided peer tag keys if available, otherwise use defaults
          tag_keys = agent_peer_tags || Ext::PEER_TAG_KEYS

          tags = []
          tag_keys.each do |key|
            value = span.meta[key]
            tags << "#{key}:#{value}" if value && !value.empty?
          end

          tags.sort!
          tags
        end

        # @param span [Datadog::Tracing::Span]
        # @return [String] HTTP method, or empty string
        def extract_http_method(span)
          span.meta.fetch(Metadata::Ext::HTTP::TAG_METHOD, '')
        end

        # @param span [Datadog::Tracing::Span]
        # @return [String] HTTP endpoint (from http.endpoint tag or empty)
        def extract_http_endpoint(span)
          span.meta.fetch(Metadata::Ext::HTTP::TAG_ENDPOINT, '')
        end
      end
    end
  end
end

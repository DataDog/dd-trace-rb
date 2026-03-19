# frozen_string_literal: true

require_relative '../metadata/ext'
require_relative 'ext'

module Datadog
  module Tracing
    module Stats
      # Determines whether a span is eligible for client-side stats computation.
      #
      # A span is eligible if it meets ANY of these criteria:
      # - It is a top-level span (has _dd.top_level metric)
      # - It is measured (has _dd.measured metric)
      # - Its span.kind is one of: server, client, producer, consumer
      #
      # Partial flush snapshots are excluded.
      module SpanEligibility
        module_function

        # @param span [Datadog::Tracing::Span] the span to check
        # @param partial [Boolean] whether the span comes from a partial flush
        # @return [Boolean] true if the span is eligible for stats
        def eligible?(span, partial: false)
          return false if partial

          top_level?(span) || measured?(span) || eligible_span_kind?(span)
        end

        # @param span [Datadog::Tracing::Span] the span to check
        # @return [Boolean] true if the span is top-level
        def top_level?(span)
          span.metrics.fetch(Metadata::Ext::TAG_TOP_LEVEL, 0).to_i == 1
        end

        # @param span [Datadog::Tracing::Span] the span to check
        # @return [Boolean] true if the span is measured
        def measured?(span)
          span.metrics.fetch(Metadata::Ext::Analytics::TAG_MEASURED, 0).to_i == 1
        end

        # @param span [Datadog::Tracing::Span] the span to check
        # @return [Boolean] true if the span has an eligible span kind
        def eligible_span_kind?(span)
          kind = span.meta.fetch(Metadata::Ext::TAG_KIND, nil)
          return false if kind.nil?

          Ext::ELIGIBLE_SPAN_KINDS.include?(kind)
        end
      end
    end
  end
end

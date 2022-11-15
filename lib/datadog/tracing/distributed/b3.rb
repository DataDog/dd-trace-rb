# frozen_string_literal: true
# typed: true

require_relative 'ext'
require_relative 'helpers'
require_relative '../trace_digest'

module Datadog
  module Tracing
    module Distributed
      # B3-style trace propagation.
      # @see https://github.com/openzipkin/b3-propagation#multiple-headers
      class B3
        def initialize(
          fetcher:,
          trace_id_key: Ext::B3_HEADER_TRACE_ID,
          span_id_key: Ext::B3_HEADER_SPAN_ID,
          sampled: Ext::B3_HEADER_SAMPLED
        )
          @trace_id_key = trace_id_key
          @span_id_key = span_id_key
          @sampled = sampled
          @fetcher = fetcher
        end

        def inject!(digest, data = {})
          return if digest.nil?

          # DEV: We need these to be hex encoded
          data[@trace_id_key] = digest.trace_id.to_s(16)
          data[@span_id_key] = digest.span_id.to_s(16)

          if digest.trace_sampling_priority
            sampling_priority = Helpers.clamp_sampling_priority(
              digest.trace_sampling_priority
            )
            data[@sampled] = sampling_priority.to_s
          end

          data
        end

        def extract(data)
          # DEV: B3 doesn't have "origin"
          fetcher = @fetcher.new(data)
          trace_id = fetcher.id(@trace_id_key, 16)
          span_id = fetcher.id(@span_id_key, 16)
          # We don't need to try and convert sampled since B3 supports 0/1 (AUTO_REJECT/AUTO_KEEP)
          sampling_priority = fetcher.number(@sampled)

          # Return early if this propagation is not valid
          return unless trace_id && span_id

          TraceDigest.new(
            trace_id: trace_id,
            span_id: span_id,
            trace_sampling_priority: sampling_priority
          )
        end
      end
    end
  end
end

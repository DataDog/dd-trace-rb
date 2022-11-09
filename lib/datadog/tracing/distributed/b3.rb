# typed: true

require_relative 'ext'
require_relative 'helpers'
require_relative '../trace_digest'

module Datadog
  module Tracing
    module Distributed
      # B3 provides helpers to inject or extract headers for B3 style headers
      # @see https://github.com/openzipkin/b3-propagation#multiple-headers
      class B3
        def initialize(
          trace_id: Ext::B3_HEADER_TRACE_ID,
          span_id: Ext::B3_HEADER_SPAN_ID,
          sampled: Ext::B3_HEADER_SAMPLED,
          fetcher: Fetcher
        )
          @trace_id = trace_id
          @span_id = span_id
          @sampled = sampled
          @fetcher = fetcher
        end

        def inject!(digest, data = {})
          return if digest.nil?

          # DEV: We need these to be hex encoded
          data[@trace_id] = digest.trace_id.to_s(16)
          data[@span_id] = digest.span_id.to_s(16)

          if digest.trace_sampling_priority
            sampling_priority = Helpers.clamp_sampling_priority(
              digest.trace_sampling_priority
            )
            data[@sampled] = sampling_priority.to_s
          end

          data
        end

        def extract(data)
          # Extract values from headers
          # DEV: B3 doesn't have "origin"
          headers = @fetcher.new(data)
          trace_id = headers.id(@trace_id, 16)
          span_id = headers.id(@span_id, 16)
          # We don't need to try and convert sampled since B3 supports 0/1 (AUTO_REJECT/AUTO_KEEP)
          sampling_priority = headers.number(@sampled)

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

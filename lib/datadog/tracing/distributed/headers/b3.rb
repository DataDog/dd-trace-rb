# typed: true

require 'datadog/tracing/distributed/headers/parser'
require 'datadog/tracing/distributed/helpers'
require 'datadog/tracing/distributed/headers/ext'
require 'datadog/tracing/trace_digest'

module Datadog
  module Tracing
    module Distributed
      module Headers
        # B3 provides helpers to inject or extract headers for B3 style headers
        module B3
          include Ext

          def self.inject!(digest, env)
            return if digest.nil?

            # DEV: We need these to be hex encoded
            env[B3_HEADER_TRACE_ID] = digest.trace_id.to_s(16)
            env[B3_HEADER_SPAN_ID] = digest.span_id.to_s(16)

            if digest.trace_sampling_priority
              sampling_priority = Helpers.clamp_sampling_priority(
                digest.trace_sampling_priority
              )
              env[B3_HEADER_SAMPLED] = sampling_priority.to_s
            end

            env
          end

          def self.extract(env)
            # Extract values from headers
            # DEV: B3 doesn't have "origin"
            headers = Parser.new(env)
            trace_id = headers.id(B3_HEADER_TRACE_ID, 16)
            span_id = headers.id(B3_HEADER_SPAN_ID, 16)
            # We don't need to try and convert sampled since B3 supports 0/1 (AUTO_REJECT/AUTO_KEEP)
            sampling_priority = headers.number(B3_HEADER_SAMPLED)

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
end

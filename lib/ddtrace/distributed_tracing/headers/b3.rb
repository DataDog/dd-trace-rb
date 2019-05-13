require 'ddtrace/ext/distributed'
require 'ddtrace/distributed_tracing/headers/headers'
require 'ddtrace/distributed_tracing/headers/helpers'

module Datadog
  module DistributedTracing
    module Headers
      # B3 provides helpers to inject or extract headers for B3 style headers
      module B3
        include Ext::DistributedTracing

        def self.inject!(context, env)
          return if context.nil?

          # DEV: We need these to be hex encoded
          env[B3_HEADER_TRACE_ID] = context.trace_id.to_s(16)
          env[B3_HEADER_SPAN_ID] = context.span_id.to_s(16)

          unless context.sampling_priority.nil?
            sampling_priority = DistributedTracing::Headers::Helpers.clamp_sampling_priority(context.sampling_priority)
            env[B3_HEADER_SAMPLED] = sampling_priority.to_s
          end
        end

        def self.extract(env)
          # Extract values from headers
          # DEV: B3 doesn't have "origin"
          headers = Headers.new(env)
          trace_id = headers.id(B3_HEADER_TRACE_ID, 16)
          span_id = headers.id(B3_HEADER_SPAN_ID, 16)
          # We don't need to try and convert sampled since B3 supports 0/1 (AUTO_REJECT/AUTO_KEEP)
          sampling_priority = headers.number(B3_HEADER_SAMPLED)

          # Return early if this propagation is not valid
          return unless trace_id && span_id

          ::Datadog::Context.new(trace_id: trace_id,
                                 span_id: span_id,
                                 sampling_priority: sampling_priority)
        end
      end
    end
  end
end

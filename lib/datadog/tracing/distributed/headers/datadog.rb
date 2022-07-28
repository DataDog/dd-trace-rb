# typed: true

require_relative 'parser'
require_relative 'ext'
require_relative '../../trace_digest'

module Datadog
  module Tracing
    module Distributed
      module Headers
        # Datadog provides helpers to inject or extract headers for Datadog style headers
        module Datadog
          include Ext

          def self.inject!(digest, env)
            return if digest.nil?

            env[HTTP_HEADER_TRACE_ID] = digest.trace_id.to_s
            env[HTTP_HEADER_PARENT_ID] = digest.span_id.to_s
            env[HTTP_HEADER_SAMPLING_PRIORITY] = digest.trace_sampling_priority.to_s if digest.trace_sampling_priority
            env[HTTP_HEADER_ORIGIN] = digest.trace_origin.to_s unless digest.trace_origin.nil?

            env
          end

          def self.extract(env)
            # Extract values from headers
            headers = Parser.new(env)
            trace_id = headers.id(HTTP_HEADER_TRACE_ID)
            parent_id = headers.id(HTTP_HEADER_PARENT_ID)
            origin = headers.header(HTTP_HEADER_ORIGIN)
            sampling_priority = headers.number(HTTP_HEADER_SAMPLING_PRIORITY)

            # Return early if this propagation is not valid
            # DEV: To be valid we need to have a trace id and a parent id
            #      or when it is a synthetics trace, just the trace id.
            # DEV: `Parser#id` will not return 0
            return unless (trace_id && parent_id) || (origin && trace_id)

            # Return new trace headers
            TraceDigest.new(
              span_id: parent_id,
              trace_id: trace_id,
              trace_origin: origin,
              trace_sampling_priority: sampling_priority
            )
          end
        end
      end
    end
  end
end

require 'ddtrace/ext/distributed'
require 'ddtrace/distributed_tracing/headers/headers'

module Datadog
  module DistributedTracing
    module Headers
      # Datadog provides helpers to inject or extract headers for Datadog style headers
      module Datadog
        include Ext::DistributedTracing

        def self.inject!(context, env)
          return if context.nil?

          env[HTTP_HEADER_TRACE_ID] = context.trace_id.to_s
          env[HTTP_HEADER_PARENT_ID] = context.span_id.to_s
          env[HTTP_HEADER_SAMPLING_PRIORITY] = context.sampling_priority.to_s unless context.sampling_priority.nil?
          env[HTTP_HEADER_ORIGIN] = context.origin.to_s unless context.origin.nil?
        end

        def self.extract(env)
          # Extract values from headers
          headers = Headers.new(env)
          trace_id = headers.id(HTTP_HEADER_TRACE_ID)
          parent_id = headers.id(HTTP_HEADER_PARENT_ID)
          origin = headers.header(HTTP_HEADER_ORIGIN)
          sampling_priority = headers.number(HTTP_HEADER_SAMPLING_PRIORITY)

          # Return early if this propagation is not valid
          # DEV: To be valid we need to have a trace id and a parent id or when it is a synthetics trace, just the trace id
          # DEV: `DistributedHeaders#id` will not return 0
          return unless (trace_id && parent_id) || (origin && trace_id)

          # Return new context
          ::Datadog::Context.new(trace_id: trace_id,
                                 span_id: parent_id,
                                 origin: origin,
                                 sampling_priority: sampling_priority)
        end
      end
    end
  end
end

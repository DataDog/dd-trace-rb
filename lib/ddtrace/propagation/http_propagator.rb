require 'ddtrace/context'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/distributed_headers'

module Datadog
  # HTTPPropagator helps extracting and injecting HTTP headers.
  module HTTPPropagator
    include Ext::DistributedTracing

    # inject! popolates the env with span ID, trace ID and sampling priority
    def self.inject!(span, env)
      headers = { HTTP_HEADER_TRACE_ID => span.trace_id.to_s,
                  HTTP_HEADER_PARENT_ID => span.span_id.to_s }
      if span.sampling_priority
        headers[HTTP_HEADER_SAMPLING_PRIORITY] = span.sampling_priority.to_s
      end
      env.merge! headers
      env.delete(HTTP_HEADER_SAMPLING_PRIORITY) unless span.sampling_priority
    end

    # extract returns a context containing the span ID, trace ID and
    # sampling priority defined in env.
    def self.extract(env)
      headers = DistributedHeaders.new(env)
      return Datadog::Context.new unless headers.valid?
      Datadog::Context.new(trace_id: headers.trace_id,
                           span_id: headers.parent_id,
                           sampling_priority: headers.sampling_priority)
    end
  end
end

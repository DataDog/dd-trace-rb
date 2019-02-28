require 'ddtrace/context'
require 'ddtrace/ext/distributed'
require 'ddtrace/propagation/distributed_headers'

module Datadog
  # HTTPPropagator helps extracting and injecting HTTP headers.
  module HTTPPropagator
    include Ext::DistributedTracing

    # inject! popolates the env with span ID, trace ID and sampling priority
    def self.inject!(context, env)
      # Prevent propagation from being attempted if context provided is nil.
      if context.nil?
        Datadog::Tracer.log.debug('Cannot inject context into env to propagate over HTTP: context is nil.'.freeze)
        return
      end

      env[HTTP_HEADER_TRACE_ID] = context.trace_id.to_s
      env[HTTP_HEADER_PARENT_ID] = context.span_id.to_s
      env[HTTP_HEADER_SAMPLING_PRIORITY] = context.sampling_priority.to_s
      env[HTTP_HEADER_ORIGIN] = context.origin.to_s if context.origin
      env.delete(HTTP_HEADER_SAMPLING_PRIORITY) unless context.sampling_priority
    end

    # extract returns a context containing the span ID, trace ID and
    # sampling priority defined in env.
    def self.extract(env)
      headers = DistributedHeaders.new(env)
      return Datadog::Context.new unless headers.valid?
      Datadog::Context.new(trace_id: headers.trace_id,
                           span_id: headers.parent_id,
                           sampling_priority: headers.sampling_priority,
                           origin: headers.origin)
    end
  end
end

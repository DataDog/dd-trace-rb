require 'ddtrace/configuration'
require 'ddtrace/context'
require 'ddtrace/ext/distributed'
require 'ddtrace/ext/priority'
require 'ddtrace/propagation/distributed_headers'

module Datadog
  # HTTPPropagator helps extracting and injecting HTTP headers.
  # rubocop:disable Metrics/ModuleLength
  module HTTPPropagator
    include Ext::DistributedTracing

    # inject! popolates the env with span ID, trace ID and sampling priority
    def self.inject!(context, env)
      # Prevent propagation from being attempted if context provided is nil.
      if context.nil?
        Datadog::Tracer.log.debug('Cannot inject context into env to propagate over HTTP: context is nil.'.freeze)
        return
      end

      # Check if they want to propagate with B3 headers
      if Datadog.configuration.propagation_inject_style.include?(PROPAGATION_STYLE_B3)
        inject_b3_header(context, env)
      end

      # Check if they want to propagate with B3 single header
      if Datadog.configuration.propagation_inject_style.include?(PROPAGATION_STYLE_B3_SINGLE_HEADER)
        inject_b3_single_header(context, env)
      end

      # Check if they want to propagate with Datadog headers
      if Datadog.configuration.propagation_inject_style.include?(PROPAGATION_STYLE_DATADOG)
        inject_datadog_headers(context, env)
      end
    end

    # extract returns a context containing the span ID, trace ID and
    # sampling priority defined in env.
    def self.extract(env)
      context = nil
      dd_context = nil
      Datadog.configuration.propagation_extract_style.each do |style|
        extracted_context = nil
        case style
        when PROPAGATION_STYLE_DATADOG
          extracted_context = extract_datadog_headers(env)
          # Keep track of the Datadog extract context, we want to return
          #   this one if we have one
          dd_context = extracted_context
        when PROPAGATION_STYLE_B3
          extracted_context = extract_b3_headers(env)
        when PROPAGATION_STYLE_B3_SINGLE_HEADER
          extracted_context = extract_b3_single_header(env)
        end

        # Skip this style if no valid headers were found
        next if extracted_context.nil?

        # No previously extracted context, use the one we just extracted
        if context.nil?
          context = extracted_context
        else
          # Return no context if we have a mismatch in values extracted
          # DEV: Return from `self.extract` not this each block
          msg = "#{context.trace_id} != #{extracted_context.trace_id} && #{context.span_id} != #{extracted_context.span_id}"
          Datadog::Tracer.log.debug("Cannot extract context from HTTP: extracted contexts differ, #{msg}".freeze)
          return nil unless context.trace_id == extracted_context.trace_id && context.span_id == extracted_context.span_id
        end
      end

      # Return the extracted context if we found one
      # Always return the Datadog context if one exists since it has more
      #   information than the B3 headers e.g. origin, expanded priority
      #   sampling values, etc
      dd_context || context
    end

    class << self
      include Ext::DistributedTracing

      private

      def clamp_priority_sampling(sampling_priority)
        # B3 doesn't have our -1 (USER_REJECT) and 2 (USER_KEEP) priorities so convert to acceptable 0/1
        if sampling_priority < 0
          sampling_priority = Ext::Priority::AUTO_REJECT
        elsif sampling_priority > 1
          sampling_priority = Ext::Priority::AUTO_KEEP
        end

        sampling_priority
      end

      def inject_b3_header(context, env)
        # DEV: We need these to be hex encoded
        env[B3_HEADER_TRACE_ID] = context.trace_id.to_s(16)
        env[B3_HEADER_SPAN_ID] = context.span_id.to_s(16)

        unless context.sampling_priority.nil?
          sampling_priority = clamp_sampling_priority(context.sampling_priority)
          env[B3_HEADER_SAMPLED] = sampling_priority.to_s
        end
      end

      def inject_b3_single_header(context, env)
        # Header format:
        #   b3: {TraceId}-{SpanId}-{SamplingState}-{ParentSpanId}
        # https://github.com/apache/incubator-zipkin-b3-propagation/tree/7c6e9f14d6627832bd80baa87ac7dabee7be23cf#single-header
        # DEV: `{SamplingState}` and `{ParentSpanId`}` are optional

        # DEV: We need these to be hex encoded
        header = "#{context.trace_id.to_s(16)}-#{context.span_id.to_s(16)}"

        unless context.sampling_priority.nil?
          sampling_priority = clamp_sampling_priority(context.sampling_priority)
          header += "-#{sampling_priority}"
        end

        env[B3_HEADER_SINGLE] = header
      end

      def inject_datadog_headers(context, env)
        env[HTTP_HEADER_TRACE_ID] = context.trace_id.to_s
        env[HTTP_HEADER_PARENT_ID] = context.span_id.to_s
        env[HTTP_HEADER_SAMPLING_PRIORITY] = context.sampling_priority.to_s unless context.sampling_priority.nil?
        env[HTTP_HEADER_ORIGIN] = context.origin.to_s unless context.origin.nil?
      end

      def extract_datadog_headers(env)
        # Extract values from headers
        headers = DistributedHeaders.new(env)
        trace_id = headers.id(HTTP_HEADER_TRACE_ID)
        parent_id = headers.id(HTTP_HEADER_PARENT_ID)
        origin = headers.header(HTTP_HEADER_ORIGIN)
        sampling_priority = headers.number(HTTP_HEADER_SAMPLING_PRIORITY)

        # Return early if this propagation is not valid
        # DEV: To be valid we need to have a trace id and a parent id or when it is a synthetics trace, just the trace id
        # DEV: `DistributedHeaders#id` will not return 0
        return unless (trace_id && parent_id) || (origin == 'synthetics' && trace_id)

        # Return new context
        Datadog::Context.new(trace_id: trace_id,
                             span_id: parent_id,
                             origin: origin,
                             sampling_priority: sampling_priority)
      end

      def extract_b3_headers(env)
        # Extract values from headers
        # DEV: B3 doesn't have "origin"
        headers = DistributedHeaders.new(env)
        trace_id = headers.id(B3_HEADER_TRACE_ID, 16)
        span_id = headers.id(B3_HEADER_SPAN_ID, 16)
        # We don't need to try and convert sampled since B3 supports 0/1 (AUTO_REJECT/AUTO_KEEP)
        sampling_priority = headers.number(B3_HEADER_SAMPLED)

        # Return early if this propagation is not valid
        return unless trace_id && span_id

        Datadog::Context.new(trace_id: trace_id,
                             span_id: span_id,
                             sampling_priority: sampling_priority)
      end

      def extract_b3_single_header(env)
        # Header format:
        #   b3: {TraceId}-{SpanId}-{SamplingState}-{ParentSpanId}
        # https://github.com/apache/incubator-zipkin-b3-propagation/tree/7c6e9f14d6627832bd80baa87ac7dabee7be23cf#single-header
        # DEV: `{SamplingState}` and `{ParentSpanId`}` are optional

        headers = DistributedHeaders.new(env)
        value = headers.header(B3_HEADER_SINGLE)
        return if value.nil?

        parts = value.split('-')
        trace_id = headers.value_to_id(parts[0], 16) unless parts.empty?
        span_id = headers.value_to_id(parts[1], 16) if parts.length > 1
        sampling_priority = headers.value_to_number(parts[2]) if parts.length > 2

        # Return early if this propagation is not valid
        return unless trace_id && span_id

        Datadog::Context.new(trace_id: trace_id,
                             span_id: span_id,
                             sampling_priority: sampling_priority)
      end
    end
  end
end

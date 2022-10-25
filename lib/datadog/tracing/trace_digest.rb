# typed: true

module Datadog
  module Tracing
    # Trace digest that represents the important parts of an active trace.
    # Used to propagate context and continue traces across execution boundaries.
    # @public_api
    class TraceDigest
      attr_reader \
        :span_id,
        :span_name,
        :span_resource,
        :span_service,
        :span_type,
        :trace_distributed_tags,
        :trace_hostname,
        :trace_id,
        :trace_name,
        :trace_origin,
        :trace_process_id,
        :trace_resource,
        :trace_runtime_id,
        :trace_sampling_priority,
        :trace_service

      def initialize(
        span_id: nil,
        span_name: nil,
        span_resource: nil,
        span_service: nil,
        span_type: nil,
        trace_distributed_tags: nil,
        trace_hostname: nil,
        trace_id: nil,
        trace_name: nil,
        trace_origin: nil,
        trace_process_id: nil,
        trace_resource: nil,
        trace_runtime_id: nil,
        trace_sampling_priority: nil,
        trace_service: nil
      )
        @span_id = span_id
        @span_name = span_name && span_name.dup.freeze
        @span_resource = span_resource && span_resource.dup.freeze
        @span_service = span_service && span_service.dup.freeze
        @span_type = span_type && span_type.dup.freeze
        @trace_distributed_tags = trace_distributed_tags && trace_distributed_tags.dup.freeze
        @trace_hostname = trace_hostname && trace_hostname.dup.freeze
        @trace_id = trace_id
        @trace_name = trace_name && trace_name.dup.freeze
        @trace_origin = trace_origin && trace_origin.dup.freeze
        @trace_process_id = trace_process_id
        @trace_resource = trace_resource && trace_resource.dup.freeze
        @trace_runtime_id = trace_runtime_id && trace_runtime_id.dup.freeze
        @trace_sampling_priority = trace_sampling_priority
        @trace_service = trace_service && trace_service.dup.freeze

        freeze
      end
    end
  end
end

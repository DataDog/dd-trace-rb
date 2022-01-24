require 'ddtrace/ext/metadata'
require 'ddtrace/ext/net'
require 'datadog/core/environment/identity'
require 'datadog/core/environment/socket'
require 'datadog/core/runtime/ext'

require 'ddtrace/trace_segment'

module Datadog
  module Transport
    # Prepares traces for transport
    class TraceFormatter
      attr_reader \
        :root_span,
        :trace

      def self.format!(trace)
        new(trace).format!
      end

      def initialize(trace)
        @trace = trace
        @root_span = find_root_span(trace)
      end

      # Modifies a trace so suitable for transport
      def format!
        return unless trace
        return trace unless root_span

        # Because the trace API does not support
        # trace metadata, we must put our trace
        # metadata on the root span. This "root span"
        # is needed by the agent/API to ingest the trace.
        set_resource!

        tag_agent_sample_rate!
        tag_hostname!
        tag_lang!
        tag_origin!
        tag_process_id!
        tag_rule_sample_rate!
        tag_runtime_id!
        tag_rate_limiter_rate!
        tag_sample_rate!
        tag_sampling_priority!

        trace
      end

      protected

      def set_resource!
        # If the trace resource is undefined, or the root span wasn't
        # specified, don't set this. We don't want to overwrite the
        # resource of a span that is in the middle of the trace.
        return if trace.resource.nil? || !@found_root_span

        root_span.resource = trace.resource
      end

      def tag_agent_sample_rate!
        return unless trace.agent_sample_rate

        root_span.set_tag(
          Ext::Sampling::TAG_AGENT_RATE,
          trace.agent_sample_rate
        )
      end

      def tag_hostname!
        return unless trace.hostname

        root_span.set_tag(
          Ext::NET::TAG_HOSTNAME,
          trace.hostname
        )
      end

      def tag_lang!
        return if trace.lang.nil? || root_span.get_tag(Ext::Metadata::TAG_PEER_SERVICE)

        root_span.set_tag(
          Core::Runtime::Ext::TAG_LANG,
          trace.lang
        )
      end

      def tag_origin!
        return unless trace.origin

        root_span.set_tag(
          Ext::DistributedTracing::TAG_ORIGIN,
          trace.origin
        )
      end

      def tag_process_id!
        return unless trace.process_id

        root_span.set_tag(
          Core::Runtime::Ext::TAG_PID,
          trace.process_id
        )
      end

      def tag_rate_limiter_rate!
        return unless trace.rate_limiter_rate

        root_span.set_tag(
          Ext::Sampling::TAG_RATE_LIMITER_RATE,
          trace.rate_limiter_rate
        )
      end

      def tag_rule_sample_rate!
        return unless trace.rule_sample_rate

        root_span.set_tag(
          Ext::Sampling::TAG_RULE_SAMPLE_RATE,
          trace.rule_sample_rate
        )
      end

      def tag_runtime_id!
        return unless trace.runtime_id

        root_span.set_tag(
          Core::Runtime::Ext::TAG_ID,
          trace.runtime_id
        )
      end

      def tag_sample_rate!
        return unless trace.sample_rate

        root_span.set_tag(
          Ext::Sampling::TAG_SAMPLE_RATE,
          trace.sample_rate
        )
      end

      def tag_sampling_priority!
        return unless trace.sampling_priority

        root_span.set_metric(
          Ext::DistributedTracing::TAG_SAMPLING_PRIORITY,
          trace.sampling_priority
        )
      end

      private

      def find_root_span(trace)
        # TODO: Should we memoize this?
        #       Would be safe, but `spans` is mutable, so if
        #       the root span were removed, it would be a stale reference.
        #       Figure out a better way to deal with this.
        root_span_id = trace.send(:root_span_id)
        root_span = trace.spans.find { |s| s.id == root_span_id } if root_span_id
        @found_root_span = !root_span.nil?
        root_span || trace.spans.last
      end
    end
  end
end

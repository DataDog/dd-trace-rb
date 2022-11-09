# frozen_string_literal: true
# typed: true

require_relative '../metadata/ext'
require_relative '../trace_digest'
require_relative 'datadog_tags_codec'

module Datadog
  module Tracing
    module Distributed
      # Datadog-style trace propagation.
      class Datadog
        def initialize(
          trace_id: Ext::HTTP_HEADER_TRACE_ID,
          parent_id: Ext::HTTP_HEADER_PARENT_ID,
          sampling_priority: Ext::HTTP_HEADER_SAMPLING_PRIORITY,
          origin: Ext::HTTP_HEADER_ORIGIN,
          tags: Ext::HTTP_HEADER_TAGS,
          fetcher: Fetcher
        )
          @trace_id = trace_id
          @parent_id = parent_id
          @sampling_priority = sampling_priority
          @origin = origin
          @tags = tags
          @fetcher = fetcher
        end

        def inject!(digest, data)
          return if digest.nil?

          data[@trace_id] = digest.trace_id.to_s
          data[@parent_id] = digest.span_id.to_s
          data[@sampling_priority] = digest.trace_sampling_priority.to_s if digest.trace_sampling_priority
          data[@origin] = digest.trace_origin.to_s unless digest.trace_origin.nil?

          inject_tags(digest, data)

          data
        end

        def extract(data)
          fetcher = @fetcher.new(data)
          trace_id = fetcher.id(@trace_id)
          parent_id = fetcher.id(@parent_id)
          sampling_priority = fetcher.number(@sampling_priority)
          origin = fetcher[@origin]

          # Return early if this propagation is not valid
          # DEV: To be valid we need to have a trace id and a parent id
          #      or when it is a synthetics trace, just the trace id.
          # DEV: `Fetcher#id` will not return 0
          return unless (trace_id && parent_id) || (origin && trace_id)

          trace_distributed_tags = extract_tags(fetcher)

          TraceDigest.new(
            span_id: parent_id,
            trace_id: trace_id,
            trace_origin: origin,
            trace_sampling_priority: sampling_priority,
            trace_distributed_tags: trace_distributed_tags,
          )
        end

        private

        # Export trace distributed tags through the `x-datadog-tags` key.
        #
        # DEV: This method accesses global state (the active trace) to record its error state as a trace tag.
        # DEV: This means errors cannot be reported if there's not active span.
        # DEV: Ideally, we'd have a dedicated error reporting stream for all of ddtrace.
        # DEV: The same comment applies to the {.extract_tags}.
        def inject_tags(digest, data)
          return if digest.trace_distributed_tags.nil? || digest.trace_distributed_tags.empty?

          if ::Datadog.configuration.tracing.x_datadog_tags_max_length <= 0
            active_trace = Tracing.active_trace
            active_trace.set_tag('_dd.propagation_error', 'disabled') if active_trace
            return
          end

          encoded_tags = DatadogTagsCodec.encode(digest.trace_distributed_tags)

          if encoded_tags.size > ::Datadog.configuration.tracing.x_datadog_tags_max_length
            active_trace = Tracing.active_trace
            active_trace.set_tag('_dd.propagation_error', 'inject_max_size') if active_trace

            ::Datadog.logger.warn(
              "Failed to inject x-datadog-tags: tags are too large (size:#{encoded_tags.size} " \
                "limit:#{::Datadog.configuration.tracing.x_datadog_tags_max_length}). This limit can be configured " \
                'through the DD_TRACE_X_DATADOG_TAGS_MAX_LENGTH environment variable.'
            )
            return
          end

          data[@tags] = encoded_tags
        rescue => e
          active_trace = Tracing.active_trace
          active_trace.set_tag('_dd.propagation_error', 'encoding_error') if active_trace
          ::Datadog.logger.warn(
            "Failed to inject x-datadog-tags: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
          )
        end

        # Import `x-datadog-tags` tags as trace distributed tags.
        # Only tags that have the `_dd.p.` prefix are processed.
        def extract_tags(data)
          tags = data[@tags]
          return if !tags || tags.empty?

          if ::Datadog.configuration.tracing.x_datadog_tags_max_length <= 0
            active_trace = Tracing.active_trace
            active_trace.set_tag('_dd.propagation_error', 'disabled') if active_trace
            return
          end

          if tags.size > ::Datadog.configuration.tracing.x_datadog_tags_max_length
            active_trace = Tracing.active_trace
            active_trace.set_tag('_dd.propagation_error', 'extract_max_size') if active_trace

            ::Datadog.logger.warn(
              "Failed to extract x-datadog-tags: tags are too large (size:#{tags.size} " \
                "limit:#{::Datadog.configuration.tracing.x_datadog_tags_max_length}). This limit can be configured " \
                'through the DD_TRACE_X_DATADOG_TAGS_MAX_LENGTH environment variable.'
            )
            return
          end

          tags_hash = DatadogTagsCodec.decode(tags)
          # Only extract keys with the expected Datadog prefix
          tags_hash.select! do |key, _|
            key.start_with?(Tracing::Metadata::Ext::Distributed::TAGS_PREFIX) && key != EXCLUDED_TAG
          end
          tags_hash
        rescue => e
          active_trace = Tracing.active_trace
          active_trace.set_tag('_dd.propagation_error', 'decoding_error') if active_trace
          ::Datadog.logger.warn(
            "Failed to extract x-datadog-tags: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
          )
        end

        # We want to exclude tags that we don't want to propagate downstream.
        EXCLUDED_TAG = '_dd.p.upstream_services'
        private_constant :EXCLUDED_TAG
      end
    end
  end
end

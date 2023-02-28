# frozen_string_literal: true

require_relative '../metadata/ext'
require_relative '../trace_digest'
require_relative 'datadog_tags_codec'

module Datadog
  module Tracing
    module Distributed
      # Datadog-style trace propagation.
      class Datadog
        TRACE_ID_KEY = 'x-datadog-trace-id'
        PARENT_ID_KEY = 'x-datadog-parent-id'
        SAMPLING_PRIORITY_KEY = 'x-datadog-sampling-priority'
        ORIGIN_KEY = 'x-datadog-origin'
        # Distributed trace-level tags
        TAGS_KEY = 'x-datadog-tags'

        # Prefix used by all Datadog-specific distributed tags
        TAGS_PREFIX = 'x-datadog-'

        def initialize(
          fetcher:,
          trace_id_key: TRACE_ID_KEY,
          parent_id_key: PARENT_ID_KEY,
          sampling_priority_key: SAMPLING_PRIORITY_KEY,
          origin_key: ORIGIN_KEY,
          tags_key: TAGS_KEY
        )
          @trace_id_key = trace_id_key
          @parent_id_key = parent_id_key
          @sampling_priority_key = sampling_priority_key
          @origin_key = origin_key
          @tags_key = tags_key
          @fetcher = fetcher
        end

        def inject!(digest, data)
          return if digest.nil?

          data[@trace_id_key] = digest.trace_id.to_s
          data[@parent_id_key] = digest.span_id.to_s
          data[@sampling_priority_key] = digest.trace_sampling_priority.to_s if digest.trace_sampling_priority
          data[@origin_key] = digest.trace_origin.to_s if digest.trace_origin

          inject_tags(digest, data)

          data
        end

        def extract(data)
          fetcher = @fetcher.new(data)
          trace_id = fetcher.id(@trace_id_key)
          parent_id = fetcher.id(@parent_id_key)
          sampling_priority = fetcher.number(@sampling_priority_key)
          origin = fetcher[@origin_key]

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
        def inject_tags(digest, data)
          return if digest.trace_distributed_tags.nil? || digest.trace_distributed_tags.empty?
          return set_tags_propagation_error(reason: 'disabled') if tags_disabled?

          tags = DatadogTagsCodec.encode(digest.trace_distributed_tags)

          return set_tags_propagation_error(reason: 'inject_max_size') if tags_too_large?(tags.size, scenario: 'inject')

          data[@tags_key] = tags
        rescue => e
          set_tags_propagation_error(reason: 'encoding_error')
          ::Datadog.logger.warn(
            "Failed to inject x-datadog-tags: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
          )
        end

        # Import `x-datadog-tags` tags as trace distributed tags.
        # Only tags that have the `_dd.p.` prefix are processed.
        #
        # DEV: This method accesses global state (the active trace) to record its error state as a trace tag.
        # DEV: This means errors cannot be reported if there's not active span.
        # DEV: Ideally, we'd have a dedicated error reporting stream for all of ddtrace.
        def extract_tags(fetcher)
          tags = fetcher[@tags_key]

          return if !tags || tags.empty?
          return set_tags_propagation_error(reason: 'disabled') if tags_disabled?
          return set_tags_propagation_error(reason: 'extract_max_size') if tags_too_large?(tags.size, scenario: 'extract')

          tags_hash = DatadogTagsCodec.decode(tags)
          # Only extract keys with the expected Datadog prefix
          tags_hash.select! do |key, _|
            key.start_with?(Tracing::Metadata::Ext::Distributed::TAGS_PREFIX) && key != EXCLUDED_TAG
          end
          tags_hash
        rescue => e
          set_tags_propagation_error(reason: 'decoding_error')
          ::Datadog.logger.warn(
            "Failed to extract x-datadog-tags: #{e.class.name} #{e.message} at #{Array(e.backtrace).first}"
          )
        end

        def set_tags_propagation_error(reason:)
          active_trace = Tracing.active_trace
          active_trace.set_tag('_dd.propagation_error', reason) if active_trace
          nil
        end

        def tags_disabled?
          ::Datadog.configuration.tracing.x_datadog_tags_max_length <= 0
        end

        def tags_too_large?(size, scenario:)
          return false if size <= ::Datadog.configuration.tracing.x_datadog_tags_max_length

          ::Datadog.logger.warn(
            "Failed to #{scenario} x-datadog-tags: tags are too large for configured limit (size:#{size} >= " \
              "limit:#{::Datadog.configuration.tracing.x_datadog_tags_max_length}). This limit can be configured " \
              'through the DD_TRACE_X_DATADOG_TAGS_MAX_LENGTH environment variable.'
          )

          true
        end

        # We want to exclude tags that we don't want to propagate downstream.
        EXCLUDED_TAG = '_dd.p.upstream_services'
        private_constant :EXCLUDED_TAG
      end
    end
  end
end

# frozen_string_literal: true

module Datadog
  module Tracing
    module Distributed
      # Cross-language keys used for distributed tracing.
      # DEV-2.0: These constants are part of the public API through {Datadog::Tracing::Distributed::Headers::Ext}.
      # DEV-2.0: We should not expose these constants, as we might not move them during refactor, and they are easily
      # DEV-2.0: and publicly documented in Datadog's and B3's documentation.
      module Ext
        HTTP_HEADER_TRACE_ID = 'x-datadog-trace-id'
        HTTP_HEADER_PARENT_ID = 'x-datadog-parent-id'
        HTTP_HEADER_SAMPLING_PRIORITY = 'x-datadog-sampling-priority'
        HTTP_HEADER_ORIGIN = 'x-datadog-origin'
        # Distributed trace-level tags
        HTTP_HEADER_TAGS = 'x-datadog-tags'

        # Prefix used by all Datadog-specific distributed tags
        DATADOG_PREFIX = 'x-datadog-'

        # B3 keys used for distributed tracing.
        # @see https://github.com/openzipkin/b3-propagation
        B3_HEADER_TRACE_ID = 'x-b3-traceid'
        B3_HEADER_SPAN_ID = 'x-b3-spanid'
        B3_HEADER_SAMPLED = 'x-b3-sampled'
        B3_HEADER_SINGLE = 'b3'
      end
    end
  end
end

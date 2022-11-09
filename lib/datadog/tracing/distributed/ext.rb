module Datadog
  module Tracing
    module Distributed
      # Cross-language keys used for distributed tracing.
      # DEV-2.0: These constants are part of the public API through {Datadog::Tracing::Distributed::Headers::Ext}.
      # DEV-2.0: We should not expose these constants, as we might not move them during refactor, and they are easily
      # DEV-2.0: and publicly documented in Datadog's and B3's documentation.
      module Ext
        HTTP_HEADER_TRACE_ID = 'x-datadog-trace-id'.freeze
        HTTP_HEADER_PARENT_ID = 'x-datadog-parent-id'.freeze
        HTTP_HEADER_SAMPLING_PRIORITY = 'x-datadog-sampling-priority'.freeze
        HTTP_HEADER_ORIGIN = 'x-datadog-origin'.freeze
        # Distributed trace-level tags
        HTTP_HEADER_TAGS = 'x-datadog-tags'.freeze

        # Prefix used by all Datadog-specific distributed tags
        DATADOG_PREFIX = 'x-datadog-'.freeze

        # B3 keys used for distributed tracing.
        # @see https://github.com/openzipkin/b3-propagation
        B3_HEADER_TRACE_ID = 'x-b3-traceid'.freeze
        B3_HEADER_SPAN_ID = 'x-b3-spanid'.freeze
        B3_HEADER_SAMPLED = 'x-b3-sampled'.freeze
        B3_HEADER_SINGLE = 'b3'.freeze
      end
    end
  end
end

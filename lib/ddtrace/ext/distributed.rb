module Datadog
  module Ext
    module DistributedTracing
      # HTTP headers one should set for distributed tracing.
      # These are cross-language (eg: Python, Go and other implementations should honor these)
      HTTP_HEADER_TRACE_ID = 'x-datadog-trace-id'.freeze
      HTTP_HEADER_PARENT_ID = 'x-datadog-parent-id'.freeze
      HTTP_HEADER_SAMPLING_PRIORITY = 'x-datadog-sampling-priority'.freeze
      SAMPLING_PRIORITY_KEY = '_sampling_priority_v1'.freeze
    end
  end
end

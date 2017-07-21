module Datadog
  module Ext
    module DistributedTracing
      # HTTP headers one should set for distributed tracing.
      # These are cross-language (eg: Python, Go and other implementations should honor these)
      HTTP_HEADER_TRACE_ID = 'x-datadog-trace-id'.freeze
      HTTP_HEADER_PARENT_ID = 'x-datadog-parent-id'.freeze
    end
  end
end

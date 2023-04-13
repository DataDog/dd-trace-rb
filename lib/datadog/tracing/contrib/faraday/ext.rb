module Datadog
  module Tracing
    module Contrib
      module Faraday
        # Faraday integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_FARADAY_ENABLED'.freeze
          ENV_SERVICE_NAME = 'DD_TRACE_FARADAY_SERVICE_NAME'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_FARADAY_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_FARADAY_ANALYTICS_SAMPLE_RATE'.freeze
          DEFAULT_PEER_SERVICE_NAME = 'faraday'.freeze
          SPAN_REQUEST = 'faraday.request'.freeze
          TAG_COMPONENT = 'faraday'.freeze
          TAG_OPERATION_REQUEST = 'request'.freeze
        end
      end
    end
  end
end

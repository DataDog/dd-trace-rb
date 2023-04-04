module Datadog
  module Tracing
    module Contrib
      module Excon
        # Excon integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_EXCON_ENABLED'.freeze
          ENV_SERVICE_NAME = 'DD_TRACE_EXCON_SERVICE_NAME'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_EXCON_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_EXCON_ANALYTICS_SAMPLE_RATE'.freeze
          DEFAULT_PEER_SERVICE_NAME = 'excon'.freeze
          SPAN_REQUEST = 'excon.request'.freeze
          TAG_COMPONENT = 'excon'.freeze
          TAG_OPERATION_REQUEST = 'request'.freeze
        end
      end
    end
  end
end

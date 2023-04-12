module Datadog
  module Tracing
    module Contrib
      module Ethon
        # Ethon integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_ETHON_ENABLED'.freeze
          ENV_SERVICE_NAME = 'DD_TRACE_ETHON_SERVICE_NAME'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_ETHON_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_ETHON_ANALYTICS_SAMPLE_RATE'.freeze
          DEFAULT_PEER_SERVICE_NAME = 'ethon'.freeze
          SPAN_REQUEST = 'ethon.request'.freeze
          SPAN_MULTI_REQUEST = 'ethon.multi.request'.freeze
          NOT_APPLICABLE_METHOD = 'N/A'.freeze
          TAG_COMPONENT = 'ethon'.freeze
          TAG_OPERATION_REQUEST = 'request'.freeze
          TAG_OPERATION_MULTI_REQUEST = 'multi.request'.freeze
        end
      end
    end
  end
end

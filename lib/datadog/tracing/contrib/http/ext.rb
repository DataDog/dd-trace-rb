# typed: true

module Datadog
  module Tracing
    module Contrib
      module HTTP
        # HTTP integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_HTTP_ENABLED'.freeze
          ENV_SERVICE_NAME = 'DD_TRACE_NET_HTTP_SERVICE_NAME'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_HTTP_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_HTTP_ANALYTICS_SAMPLE_RATE'.freeze
          ENV_RESPONSE_CODE_ERRORS = 'DD_TRACE_HTTP_RESPONSE_CODE_ERRORS'.freeze
          DEFAULT_PEER_SERVICE_NAME = 'net/http'.freeze
          SPAN_REQUEST = 'http.request'.freeze
          TAG_COMPONENT = 'net/http'.freeze
          TAG_OPERATION_REQUEST = 'request'.freeze
        end
      end
    end
  end
end

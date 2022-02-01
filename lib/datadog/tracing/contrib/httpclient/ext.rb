# typed: true
module Datadog
  module Tracing
    module Contrib
      module Httpclient
        # Httpclient integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_HTTPCLIENT_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_HTTPCLIENT_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_HTTPCLIENT_ANALYTICS_SAMPLE_RATE'.freeze
          DEFAULT_PEER_SERVICE_NAME = 'httpclient'.freeze
          SPAN_REQUEST = 'httpclient.request'.freeze
          TAG_COMPONENT = 'httpclient'.freeze
          TAG_OPERATION_REQUEST = 'request'.freeze
        end
      end
    end
  end
end

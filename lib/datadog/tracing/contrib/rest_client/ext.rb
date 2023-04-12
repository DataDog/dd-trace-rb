module Datadog
  module Tracing
    module Contrib
      module RestClient
        # RestClient integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_REST_CLIENT_ENABLED'.freeze
          ENV_SERVICE_NAME = 'DD_TRACE_REST_CLIENT_SERVICE_NAME'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_REST_CLIENT_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_REST_CLIENT_ANALYTICS_SAMPLE_RATE'.freeze
          DEFAULT_PEER_SERVICE_NAME = 'rest_client'.freeze
          SPAN_REQUEST = 'rest_client.request'.freeze
          TAG_COMPONENT = 'rest_client'.freeze
          TAG_OPERATION_REQUEST = 'request'.freeze
        end
      end
    end
  end
end

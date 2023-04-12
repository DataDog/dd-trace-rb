# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module RestClient
        # RestClient integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_REST_CLIENT_ENABLED'
          ENV_SERVICE_NAME = 'DD_TRACE_REST_CLIENT_SERVICE_NAME'
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_REST_CLIENT_ANALYTICS_ENABLED'
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_REST_CLIENT_ANALYTICS_SAMPLE_RATE'
          DEFAULT_PEER_SERVICE_NAME = 'rest_client'
          SPAN_REQUEST = 'rest_client.request'
          TAG_COMPONENT = 'rest_client'
          TAG_OPERATION_REQUEST = 'request'
        end
      end
    end
  end
end

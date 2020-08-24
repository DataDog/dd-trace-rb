module Datadog
  module Contrib
    module RestClient
      # RestClient integration constants
      module Ext
        APP = 'rest_client'.freeze
        ENV_ENABLED = 'DD_TRACE_REST_CLIENT_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_REST_CLIENT_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_REST_CLIENT_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_REST_CLIENT_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_REST_CLIENT_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'rest_client'.freeze
        SPAN_REQUEST = 'rest_client.request'.freeze
      end
    end
  end
end

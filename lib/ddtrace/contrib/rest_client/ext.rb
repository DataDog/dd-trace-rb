module Datadog
  module Contrib
    module RestClient
      # RestClient integration constants
      module Ext
        APP = 'rest_client'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_REST_CLIENT_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_REST_CLIENT_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'rest_client'.freeze
        SPAN_REQUEST = 'rest_client.request'.freeze
      end
    end
  end
end

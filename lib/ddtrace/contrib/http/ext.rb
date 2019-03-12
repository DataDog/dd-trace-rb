module Datadog
  module Contrib
    module HTTP
      # HTTP integration constants
      module Ext
        APP = 'net/http'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_HTTP_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_HTTP_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'net/http'.freeze
        SPAN_REQUEST = 'http.request'.freeze
      end
    end
  end
end

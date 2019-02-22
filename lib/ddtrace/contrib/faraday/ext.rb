module Datadog
  module Contrib
    module Faraday
      # Faraday integration constants
      module Ext
        APP = 'faraday'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_FARADAY_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_FARADAY_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'faraday'.freeze
        SPAN_REQUEST = 'faraday.request'.freeze
      end
    end
  end
end

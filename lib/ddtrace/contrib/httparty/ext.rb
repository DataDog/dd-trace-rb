module Datadog
  module Contrib
    module HTTParty
      # HTTParty integration constants
      module Ext
        APP = 'httparty'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_HTTPARTY_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_HTTPARTY_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'httparty'.freeze
        SPAN_REQUEST = 'httparty.request'.freeze
      end
    end
  end
end

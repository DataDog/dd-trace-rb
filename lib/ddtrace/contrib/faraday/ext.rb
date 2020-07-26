module Datadog
  module Contrib
    module Faraday
      # Faraday integration constants
      module Ext
        APP = 'faraday'.freeze
        ENV_ENABLED = 'DD_TRACE_FARADAY_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_FARADAY_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_FARADAY_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_FARADAY_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_FARADAY_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'faraday'.freeze
        SPAN_REQUEST = 'faraday.request'.freeze
      end
    end
  end
end

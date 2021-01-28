module Datadog
  module Contrib
    module Httpclient
      # Httpclient integration constants
      module Ext
        APP = 'httpclient'.freeze
        ENV_ENABLED = 'DD_TRACE_HTTPCLIENT_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_HTTPCLIENT_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_HTTPCLIENT_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_HTTPCLIENT_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_HTTPCLIENT_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'httpclient'.freeze
        SPAN_REQUEST = 'httpclient.request'.freeze
      end
    end
  end
end

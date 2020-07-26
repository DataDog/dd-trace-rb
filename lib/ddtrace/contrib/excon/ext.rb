module Datadog
  module Contrib
    module Excon
      # Excon integration constants
      module Ext
        APP = 'excon'.freeze
        ENV_ENABLED = 'DD_TRACE_EXCON_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_EXCON_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_EXCON_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_EXCON_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_EXCON_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'excon'.freeze
        SPAN_REQUEST = 'excon.request'.freeze
      end
    end
  end
end

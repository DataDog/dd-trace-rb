module Datadog
  module Contrib
    module Ethon
      # Ethon integration constants
      module Ext
        APP = 'ethon'.freeze
        ENV_ENABLED = 'DD_TRACE_ETHON_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_ETHON_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_ETHON_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_ETHON_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_ETHON_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'ethon'.freeze
        SPAN_REQUEST = 'ethon.request'.freeze
        SPAN_MULTI_REQUEST = 'ethon.multi.request'.freeze
        NOT_APPLICABLE_METHOD = 'N/A'.freeze
      end
    end
  end
end

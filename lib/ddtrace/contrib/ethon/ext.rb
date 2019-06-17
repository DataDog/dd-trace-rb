module Datadog
  module Contrib
    module Ethon
      # Ethon integration constants
      module Ext
        APP = 'ethon'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_ETHON_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_ETHON_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'ethon'.freeze
        SPAN_REQUEST = 'ethon.request'.freeze
      end
    end
  end
end

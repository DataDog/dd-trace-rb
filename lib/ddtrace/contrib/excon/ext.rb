module Datadog
  module Contrib
    module Excon
      # Excon integration constants
      module Ext
        APP = 'excon'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_EXCON_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_EXCON_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'excon'.freeze
        SPAN_REQUEST = 'excon.request'.freeze
      end
    end
  end
end

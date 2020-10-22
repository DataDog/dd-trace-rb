module Datadog
  module Contrib
    module Cucumber
      # Cucumber integration constants
      module Ext
        APP = 'cucumber'.freeze
        ENV_ENABLED = 'DD_TRACE_CUCUMBER_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_CUCUMBER_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_CUCUMBER_ANALYTICS_SAMPLE_RATE'.freeze
      end
    end
  end
end

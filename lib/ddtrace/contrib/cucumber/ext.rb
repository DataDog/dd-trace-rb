module Datadog
  module Contrib
    module Cucumber
      # Cucumber integration constants
      module Ext
        APP = 'cucumber'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_CUCUMBER_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_CUCUMBER_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ENABLED = 'DD_TRACE_CUCUMBER_ENABLED'.freeze
        ENV_OPERATION_NAME = 'DD_TRACE_CUCUMBER_OPERATION_NAME'.freeze
        FRAMEWORK = 'cucumber'.freeze
        OPERATION_NAME = 'cucumber.test'.freeze
        SERVICE_NAME = 'cucumber'.freeze
        STEP_SPAN_TYPE = 'step'.freeze
        TEST_TYPE = 'test'.freeze
      end
    end
  end
end

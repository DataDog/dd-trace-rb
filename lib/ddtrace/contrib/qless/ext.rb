module Datadog
  module Contrib
    module Qless
      # Qless integration constants
      module Ext
        APP = 'qless'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_QLESS_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_QLESS_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'qless'.freeze
        SPAN_JOB = 'qless.job'.freeze
      end
    end
  end
end

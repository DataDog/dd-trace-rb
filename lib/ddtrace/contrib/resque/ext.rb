module Datadog
  module Contrib
    module Resque
      # Resque integration constants
      module Ext
        APP = 'resque'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_RESQUE_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_RESQUE_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'resque'.freeze
        SPAN_JOB = 'resque.job'.freeze
      end
    end
  end
end

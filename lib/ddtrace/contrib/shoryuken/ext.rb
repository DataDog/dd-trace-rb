module Datadog
  module Contrib
    module Shoryuken
      # Shoryuken integration constants
      module Ext
        APP = 'shoryuken'.freeze
        ENV_ENABLED = 'DD_TRACE_SHORYUKEN_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_SHORYUKEN_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_SHORYUKEN_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_SHORYUKEN_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_SHORYUKEN_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'shoryuken'.freeze
        SPAN_JOB = 'shoryuken.job'.freeze
        TAG_JOB_ID = 'shoryuken.id'.freeze
        TAG_JOB_QUEUE = 'shoryuken.queue'.freeze
        TAG_JOB_ATTRIBUTES = 'shoryuken.attributes'.freeze
        TAG_JOB_BODY = 'shoryuken.body'.freeze
      end
    end
  end
end

module Datadog
  module Contrib
    module DelayedJob
      # DelayedJob integration constants
      module Ext
        APP = 'delayed_job'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_DELAYED_JOB_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_DELAYED_JOB_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'delayed_job'.freeze
        SPAN_JOB = 'delayed_job'.freeze
        TAG_ATTEMPTS = 'delayed_job.attempts'.freeze
        TAG_ID = 'delayed_job.id'.freeze
        TAG_PRIORITY = 'delayed_job.priority'.freeze
        TAG_QUEUE = 'delayed_job.queue'.freeze
      end
    end
  end
end

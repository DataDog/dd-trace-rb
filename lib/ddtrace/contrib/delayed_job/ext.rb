module Datadog
  module Contrib
    module DelayedJob
      # DelayedJob integration constants
      module Ext
        APP = 'delayed_job'.freeze
        ENV_ENABLED = 'DD_TRACE_DELAYED_JOB_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_DELAYED_JOB_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_DELAYED_JOB_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_DELAYED_JOB_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_DELAYED_JOB_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'delayed_job'.freeze
        CLIENT_SERVICE_NAME = 'delayed_job-client'.freeze
        SPAN_JOB = 'delayed_job'.freeze
        SPAN_ENQUEUE = 'delayed_job.enqueue'.freeze
        TAG_ATTEMPTS = 'delayed_job.attempts'.freeze
        TAG_ID = 'delayed_job.id'.freeze
        TAG_PRIORITY = 'delayed_job.priority'.freeze
        TAG_QUEUE = 'delayed_job.queue'.freeze
      end
    end
  end
end

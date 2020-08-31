module Datadog
  module Contrib
    module Sidekiq
      # Sidekiq integration constants
      module Ext
        APP = 'sidekiq'.freeze
        CLIENT_SERVICE_NAME = 'sidekiq-client'.freeze
        ENV_ENABLED = 'DD_TRACE_SIDEKIQ_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_SIDEKIQ_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_SIDEKIQ_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_SIDEKIQ_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_SIDEKIQ_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_TAG_JOB_ARGS = 'DD_SIDEKIQ_TAG_JOB_ARGS'.freeze
        SERVICE_NAME = 'sidekiq'.freeze
        SPAN_PUSH = 'sidekiq.push'.freeze
        SPAN_JOB = 'sidekiq.job'.freeze
        TAG_JOB_DELAY = 'sidekiq.job.delay'.freeze
        TAG_JOB_ID = 'sidekiq.job.id'.freeze
        TAG_JOB_QUEUE = 'sidekiq.job.queue'.freeze
        TAG_JOB_RETRY = 'sidekiq.job.retry'.freeze
        TAG_JOB_RETRY_COUNT = 'sidekiq.job.retry_count'.freeze
        TAG_JOB_WRAPPER = 'sidekiq.job.wrapper'.freeze
        TAG_JOB_ARGS = 'sidekiq.job.args'.freeze
      end
    end
  end
end

module Datadog
  module Contrib
    module Sidekiq
      # Sidekiq integration constants
      module Ext
        APP = 'sidekiq'.freeze
        CLIENT_SERVICE_NAME = 'sidekiq-client'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_SIDEKIQ_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_SIDEKIQ_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'sidekiq'.freeze
        SPAN_PUSH = 'sidekiq.push'.freeze
        SPAN_JOB = 'sidekiq.job'.freeze
        TAG_JOB_DELAY = 'sidekiq.job.delay'.freeze
        TAG_JOB_ID = 'sidekiq.job.id'.freeze
        TAG_JOB_QUEUE = 'sidekiq.job.queue'.freeze
        TAG_JOB_RETRY = 'sidekiq.job.retry'.freeze
        TAG_JOB_WRAPPER = 'sidekiq.job.wrapper'.freeze
      end
    end
  end
end

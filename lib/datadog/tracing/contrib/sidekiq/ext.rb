module Datadog
  module Tracing
    module Contrib
      module Sidekiq
        # Sidekiq integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          CLIENT_SERVICE_NAME = 'sidekiq-client'.freeze
          ENV_ENABLED = 'DD_TRACE_SIDEKIQ_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_SIDEKIQ_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_SIDEKIQ_ANALYTICS_SAMPLE_RATE'.freeze
          ENV_TAG_JOB_ARGS = 'DD_SIDEKIQ_TAG_JOB_ARGS'.freeze
          SERVICE_NAME = 'sidekiq'.freeze
          SPAN_PUSH = 'sidekiq.push'.freeze
          SPAN_JOB = 'sidekiq.job'.freeze
          SPAN_JOB_FETCH = 'sidekiq.job_fetch'.freeze
          SPAN_REDIS_INFO = 'sidekiq.redis_info'.freeze
          SPAN_HEARTBEAT = 'sidekiq.heartbeat'.freeze
          SPAN_SCHEDULED_PUSH = 'sidekiq.scheduled_push'.freeze
          SPAN_SCHEDULED_WAIT = 'sidekiq.scheduled_poller_wait'.freeze
          SPAN_STOP = 'sidekiq.stop'.freeze
          TAG_JOB_DELAY = 'sidekiq.job.delay'.freeze
          TAG_JOB_ID = 'sidekiq.job.id'.freeze
          TAG_JOB_QUEUE = 'sidekiq.job.queue'.freeze
          TAG_JOB_RETRY = 'sidekiq.job.retry'.freeze
          TAG_JOB_RETRY_COUNT = 'sidekiq.job.retry_count'.freeze
          TAG_JOB_WRAPPER = 'sidekiq.job.wrapper'.freeze
          TAG_JOB_ARGS = 'sidekiq.job.args'.freeze
          TAG_COMPONENT = 'sidekiq'.freeze
          TAG_OPERATION_PUSH = 'push'.freeze
          TAG_OPERATION_JOB = 'job'.freeze
          TAG_OPERATION_JOB_FETCH = 'job_fetch'.freeze
          TAG_OPERATION_REDIS_INFO = 'redis_info'.freeze
          TAG_OPERATION_HEARTBEAT = 'heartbeat'.freeze
          TAG_OPERATION_SCHEDULED_PUSH = 'scheduled_push'.freeze
          TAG_OPERATION_SCHEDULED_WAIT = 'scheduled_poller_wait'.freeze
          TAG_OPERATION_STOP = 'stop'.freeze
        end
      end
    end
  end
end

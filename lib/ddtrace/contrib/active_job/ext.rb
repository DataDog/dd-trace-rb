# typed: true
module Datadog
  module Contrib
    module ActiveJob
      module Ext
        APP = 'active_job'.freeze
        SERVICE_NAME = 'active_job'.freeze

        ENV_ENABLED = 'DD_TRACE_ACTIVE_JOB_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_ACTIVE_JOB_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_ACTIVE_JOB_ANALYTICS_SAMPLE_RATE'.freeze

        SPAN_DISCARD = 'active_job.discard'.freeze
        SPAN_ENQUEUE = 'active_job.enqueue'.freeze
        SPAN_ENQUEUE_RETRY = 'active_job.enqueue_retry'.freeze
        SPAN_PERFORM = 'active_job.perform'.freeze
        SPAN_RETRY_STOPPED = 'active_job.retry_stopped'.freeze

        TAG_ADAPTER = 'active_job.adapter'.freeze
        TAG_JOB_ERROR = 'active_job.job.error'.freeze
        TAG_JOB_EXECUTIONS = 'active_job.job.executions'.freeze
        TAG_JOB_ID = 'active_job.job.id'.freeze
        TAG_JOB_PRIORITY = 'active_job.job.priority'.freeze
        TAG_JOB_QUEUE = 'active_job.job.queue'.freeze
        TAG_JOB_RETRY_WAIT = 'active_job.job.retry_wait'.freeze
        TAG_JOB_SCHEDULED_AT = 'active_job.job.scheduled_at'.freeze
      end
    end
  end
end

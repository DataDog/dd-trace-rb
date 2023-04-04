module Datadog
  module Tracing
    module Contrib
      module ActiveJob
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_ACTIVE_JOB_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_ACTIVE_JOB_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_ACTIVE_JOB_ANALYTICS_SAMPLE_RATE'.freeze

          SPAN_DISCARD = 'active_job.discard'.freeze
          SPAN_ENQUEUE = 'active_job.enqueue'.freeze
          SPAN_ENQUEUE_RETRY = 'active_job.enqueue_retry'.freeze
          SPAN_PERFORM = 'active_job.perform'.freeze
          SPAN_RETRY_STOPPED = 'active_job.retry_stopped'.freeze

          TAG_COMPONENT = 'active_job'.freeze
          TAG_OPERATION_DISCARD = 'discard'.freeze
          TAG_OPERATION_ENQUEUE = 'enqueue'.freeze
          TAG_OPERATION_ENQUEUE_AT = 'enqueue_at'.freeze
          TAG_OPERATION_ENQUEUE_RETRY = 'enqueue_retry'.freeze
          TAG_OPERATION_PERFORM = 'perform'.freeze
          TAG_OPERATION_RETRY_STOPPED = 'retry_stopped'.freeze

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
end

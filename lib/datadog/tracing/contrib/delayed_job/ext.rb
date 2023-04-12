module Datadog
  module Tracing
    module Contrib
      module DelayedJob
        # DelayedJob integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_DELAYED_JOB_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_DELAYED_JOB_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_DELAYED_JOB_ANALYTICS_SAMPLE_RATE'.freeze
          SPAN_JOB = 'delayed_job'.freeze
          SPAN_ENQUEUE = 'delayed_job.enqueue'.freeze
          SPAN_RESERVE_JOB = 'delayed_job.reserve_job'.freeze
          TAG_ATTEMPTS = 'delayed_job.attempts'.freeze
          TAG_ID = 'delayed_job.id'.freeze
          TAG_PRIORITY = 'delayed_job.priority'.freeze
          TAG_QUEUE = 'delayed_job.queue'.freeze
          TAG_COMPONENT = 'delayed_job'.freeze
          TAG_OPERATION_ENQUEUE = 'enqueue'.freeze
          TAG_OPERATION_JOB = 'job'.freeze
          TAG_OPERATION_RESERVE_JOB = 'reserve_job'.freeze
        end
      end
    end
  end
end

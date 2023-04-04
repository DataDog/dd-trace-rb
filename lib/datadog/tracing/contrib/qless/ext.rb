module Datadog
  module Tracing
    module Contrib
      module Qless
        # Qless integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_QLESS_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_QLESS_ANALYTICS_SAMPLE_RATE'.freeze
          ENV_TAG_JOB_DATA = 'DD_QLESS_TAG_JOB_DATA'.freeze
          ENV_TAG_JOB_TAGS = 'DD_QLESS_TAG_JOB_TAGS'.freeze
          SERVICE_NAME = 'qless'.freeze
          SPAN_JOB = 'qless.job'.freeze
          TAG_JOB_ID = 'qless.job.id'.freeze
          TAG_JOB_DATA = 'qless.job.data'.freeze
          TAG_JOB_QUEUE = 'qless.job.queue'.freeze
          TAG_JOB_TAGS = 'qless.job.tags'.freeze
          TAG_COMPONENT = 'qless'.freeze
          TAG_OPERATION_JOB = 'job'.freeze
        end
      end
    end
  end
end

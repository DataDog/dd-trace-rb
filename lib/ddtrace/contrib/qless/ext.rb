module Datadog
  module Contrib
    module Qless
      # Qless integration constants
      module Ext
        APP = 'qless'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_QLESS_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_QLESS_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_TAG_JOB_DATA = 'DD_QLESS_TAG_JOB_DATA'.freeze
        ENV_TAG_JOB_TAGS = 'DD_QLESS_TAG_JOB_TAGS'.freeze
        SERVICE_NAME = 'qless'.freeze
        SPAN_JOB = 'qless.job'.freeze
        TAG_JOB_ID = 'qless.job.id'.freeze
        TAG_JOB_DATA = 'qless.job.data'.freeze
        TAG_JOB_QUEUE = 'qless.job.queue'.freeze
        TAG_JOB_TAGS = 'qless.job.tags'.freeze
      end
    end
  end
end

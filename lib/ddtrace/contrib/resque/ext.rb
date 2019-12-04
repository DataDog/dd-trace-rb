module Datadog
  module Contrib
    module Resque
      # Resque integration constants
      module Ext
        APP = 'resque'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_RESQUE_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_RESQUE_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'resque'.freeze
        SPAN_JOB = 'resque.job'.freeze
        SPAN_JOB_PERFORM = 'resque.job.perform'.freeze
        SPAN_ENQUEUE = 'resque.enqueue'.freeze
        SPAN_JOB_AFTER_HOOK = 'resque.job.after_hook'.freeze
        SPAN_JOB_FAILURE_HOOK = 'resque.job.failure_hook'.freeze
        SPAN_JOB_AROUND_HOOK = 'resque.job.around_hook'.freeze
        SPAN_JOB_BEFORE_HOOK = 'resque.job.before_hook'.freeze
        TAG_QUEUE = 'resque.queue'.freeze
        TAG_CLASS = 'resque.class'.freeze
      end
    end
  end
end

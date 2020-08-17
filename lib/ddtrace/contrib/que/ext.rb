# frozen_string_literal: true

module Datadog
  module Contrib
    module Que
      # Sneakers integration constants
      module Ext
        APP = 'que'.freeze
        ENV_ENABLED = 'DD_TRACE_QUE_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_QUE_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_QUE_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_QUE_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_QUE_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'que'.freeze
        SPAN_JOB = 'que.job'.freeze
        TAG_JOB_ID = 'que.job.id'.freeze
        TAG_JOB_EXPIRED_AT = 'que.job.expired_at'.freeze
        TAG_JOB_FINISHED_AT = 'que.job.finished_at'.freeze
        TAG_JOB_ARGS = 'que.job.args'.freeze
        TAG_JOB_QUEUE = 'que.job.queue'.freeze
        TAG_JOB_PRIORITY = 'que.job.priority'.freeze
      end
    end
  end
end

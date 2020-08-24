# frozen_string_literal: true

module Datadog
  module Contrib
    module Sneakers
      # Sneakers integration constants
      module Ext
        APP = 'sneakers'.freeze
        ENV_ENABLED = 'DD_TRACE_SNEAKERS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_SNEAKERS_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_SNEAKERS_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_SNEAKERS_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_SNEAKERS_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'sneakers'.freeze
        SPAN_JOB = 'sneakers.job'.freeze
        TAG_JOB_ROUTING_KEY = 'sneakers.routing_key'.freeze
        TAG_JOB_QUEUE = 'sneakers.queue'.freeze
        TAG_JOB_BODY = 'sneakers.body'.freeze
      end
    end
  end
end

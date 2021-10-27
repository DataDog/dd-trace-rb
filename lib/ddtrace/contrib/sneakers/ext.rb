# typed: strict
# frozen_string_literal: true

module Datadog
  module Contrib
    module Sneakers
      # Sneakers integration constants
      module Ext
        APP = 'sneakers'
        ENV_ENABLED = 'DD_TRACE_SNEAKERS_ENABLED'
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_SNEAKERS_ANALYTICS_ENABLED'
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_SNEAKERS_ANALYTICS_SAMPLE_RATE'
        SERVICE_NAME = 'sneakers'
        SPAN_JOB = 'sneakers.job'
        TAG_JOB_ROUTING_KEY = 'sneakers.routing_key'
        TAG_JOB_QUEUE = 'sneakers.queue'
        TAG_JOB_BODY = 'sneakers.body'
      end
    end
  end
end

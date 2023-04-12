module Datadog
  module Tracing
    module Contrib
      module Shoryuken
        # Shoryuken integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_SHORYUKEN_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_SHORYUKEN_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_SHORYUKEN_ANALYTICS_SAMPLE_RATE'.freeze
          SERVICE_NAME = 'shoryuken'.freeze
          SPAN_JOB = 'shoryuken.job'.freeze
          TAG_JOB_ID = 'shoryuken.id'.freeze
          TAG_JOB_QUEUE = 'shoryuken.queue'.freeze
          TAG_JOB_ATTRIBUTES = 'shoryuken.attributes'.freeze
          TAG_JOB_BODY = 'shoryuken.body'.freeze
          TAG_COMPONENT = 'shoryuken'.freeze
          TAG_OPERATION_JOB = 'job'.freeze
          TAG_MESSAGING_SYSTEM = 'amazonsqs'.freeze
        end
      end
    end
  end
end

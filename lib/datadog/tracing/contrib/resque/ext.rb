module Datadog
  module Tracing
    module Contrib
      module Resque
        # Resque integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_RESQUE_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_RESQUE_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_RESQUE_ANALYTICS_SAMPLE_RATE'.freeze
          SERVICE_NAME = 'resque'.freeze
          SPAN_JOB = 'resque.job'.freeze
          TAG_COMPONENT = 'resque'.freeze
          TAG_OPERATION_JOB = 'job'.freeze
        end
      end
    end
  end
end

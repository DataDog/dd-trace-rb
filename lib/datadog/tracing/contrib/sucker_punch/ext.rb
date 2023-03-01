module Datadog
  module Tracing
    module Contrib
      module SuckerPunch
        # SuckerPunch integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_SUCKER_PUNCH_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_SUCKER_PUNCH_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_SUCKER_PUNCH_ANALYTICS_SAMPLE_RATE'.freeze
          SERVICE_NAME = 'sucker_punch'.freeze
          SPAN_PERFORM = 'sucker_punch.perform'.freeze
          SPAN_PERFORM_ASYNC = 'sucker_punch.perform_async'.freeze
          SPAN_PERFORM_IN = 'sucker_punch.perform_in'.freeze
          TAG_PERFORM_IN = 'sucker_punch.perform_in'.freeze
          TAG_QUEUE = 'sucker_punch.queue'.freeze
          TAG_COMPONENT = 'sucker_punch'.freeze
          TAG_OPERATION_PERFORM = 'perform'.freeze
          TAG_OPERATION_PERFORM_ASYNC = 'perform_async'.freeze
          TAG_OPERATION_PERFORM_IN = 'perform_in'.freeze
        end
      end
    end
  end
end

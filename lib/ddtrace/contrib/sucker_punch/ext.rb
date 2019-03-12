module Datadog
  module Contrib
    module SuckerPunch
      # SuckerPunch integration constants
      module Ext
        APP = 'sucker_punch'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_SUCKER_PUNCH_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_SUCKER_PUNCH_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'sucker_punch'.freeze
        SPAN_PERFORM = 'sucker_punch.perform'.freeze
        SPAN_PERFORM_ASYNC = 'sucker_punch.perform_async'.freeze
        SPAN_PERFORM_IN = 'sucker_punch.perform_in'.freeze
        TAG_PERFORM_IN = 'sucker_punch.perform_in'.freeze
        TAG_QUEUE = 'sucker_punch.queue'.freeze
      end
    end
  end
end

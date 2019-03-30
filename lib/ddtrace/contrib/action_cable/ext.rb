module Datadog
  module Contrib
    module ActionCable
      # ActionCable integration constants
      module Ext
        APP = 'action_cable'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_ACTION_CABLE_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_ACTION_CABLE_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'action_cable'.freeze
        SPAN_PERFORM_ACTION = 'perform_action.action_cable'.freeze
        TAG_ACTION = 'action_cable.perform_action'.freeze
        TAG_CHANNEL = 'action_cable.channel_class'.freeze
      end
    end
  end
end

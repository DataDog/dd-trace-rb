module Datadog
  module Contrib
    module ActionCable
      # ActionCable integration constants
      module Ext
        APP = 'action_cable'.freeze
        ENV_ENABLED = 'DD_TRACE_ACTION_CABLE_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_ACTION_CABLE_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_ACTION_CABLE_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_ACTION_CABLE_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_ACTION_CABLE_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'action_cable'.freeze
        SPAN_ACTION = 'action_cable.action'.freeze
        SPAN_BROADCAST = 'action_cable.broadcast'.freeze
        SPAN_ON_OPEN = 'action_cable.on_open'.freeze
        SPAN_TRANSMIT = 'action_cable.transmit'.freeze
        TAG_ACTION = 'action_cable.action'.freeze
        TAG_BROADCAST_CODER = 'action_cable.broadcast.coder'.freeze
        TAG_CHANNEL = 'action_cable.channel'.freeze
        TAG_CHANNEL_CLASS = 'action_cable.channel_class'.freeze
        TAG_CONNECTION = 'action_cable.connection'.freeze
        TAG_TRANSMIT_VIA = 'action_cable.transmit.via'.freeze
      end
    end
  end
end

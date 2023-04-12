module Datadog
  module Tracing
    module Contrib
      module ActionCable
        # ActionCable integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_ACTION_CABLE_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_ACTION_CABLE_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_ACTION_CABLE_ANALYTICS_SAMPLE_RATE'.freeze
          SPAN_ACTION = 'action_cable.action'.freeze
          SPAN_BROADCAST = 'action_cable.broadcast'.freeze
          SPAN_ON_OPEN = 'action_cable.on_open'.freeze
          SPAN_TRANSMIT = 'action_cable.transmit'.freeze
          TAG_ACTION = 'action_cable.action'.freeze
          TAG_BROADCAST_CODER = 'action_cable.broadcast.coder'.freeze
          TAG_CHANNEL = 'action_cable.channel'.freeze
          TAG_CHANNEL_CLASS = 'action_cable.channel_class'.freeze
          TAG_COMPONENT = 'action_cable'.freeze
          TAG_CONNECTION = 'action_cable.connection'.freeze
          TAG_OPERATION_ACTION = 'action'.freeze
          TAG_OPERATION_BROADCAST = 'broadcast'.freeze
          TAG_OPERATION_ON_OPEN = 'on_open'.freeze
          TAG_OPERATION_TRANSMIT = 'transmit'.freeze
          TAG_TRANSMIT_VIA = 'action_cable.transmit.via'.freeze
        end
      end
    end
  end
end

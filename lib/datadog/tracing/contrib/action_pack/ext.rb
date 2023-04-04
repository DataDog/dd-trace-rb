module Datadog
  module Tracing
    module Contrib
      module ActionPack
        # ActionPack integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_ACTION_PACK_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_ACTION_PACK_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_ACTION_PACK_ANALYTICS_SAMPLE_RATE'.freeze
          SPAN_ACTION_CONTROLLER = 'rails.action_controller'.freeze
          TAG_COMPONENT = 'action_pack'.freeze
          TAG_OPERATION_CONTROLLER = 'controller'.freeze
          TAG_ROUTE_ACTION = 'rails.route.action'.freeze
          TAG_ROUTE_CONTROLLER = 'rails.route.controller'.freeze
        end
      end
    end
  end
end

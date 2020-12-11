module Datadog
  module Contrib
    module ActionPack
      # ActionPack integration constants
      module Ext
        APP = 'action_pack'.freeze
        ENV_ENABLED = 'DD_TRACE_ACTION_PACK_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_ACTION_PACK_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED_OLD = 'DD_ACTION_PACK_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_ACTION_PACK_ANALYTICS_SAMPLE_RATE'.freeze
        ENV_ANALYTICS_SAMPLE_RATE_OLD = 'DD_ACTION_PACK_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'action_pack'.freeze
        SPAN_ACTION_CONTROLLER = 'rails.action_controller'.freeze
        TAG_ROUTE_ACTION = 'rails.route.action'.freeze
        TAG_ROUTE_CONTROLLER = 'rails.route.controller'.freeze
      end
    end
  end
end

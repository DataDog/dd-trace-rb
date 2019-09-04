module Datadog
  module Contrib
    module ActionPack
      # ActionPack integration constants
      module Ext
        APP = 'action_pack'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_ACTION_PACK_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_ACTION_PACK_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'action_pack'.freeze
        SPAN_ACTION_CONTROLLER = 'rails.action_controller'.freeze
        TAG_ROUTE_ACTION = 'rails.route.action'.freeze
        TAG_ROUTE_CONTROLLER = 'rails.route.controller'.freeze
      end
    end
  end
end

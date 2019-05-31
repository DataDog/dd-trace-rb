module Datadog
  module Contrib
    module ActionPack
      # ActionPack integration constants
      module Ext
        APP = 'action_pack'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_ACTION_PACK_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_ACTION_PACK_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'action_pack'.freeze
      end
    end
  end
end

require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/action_pack/ext'

module Datadog
  module Contrib
    module ActionPack
      module Configuration
        # Custom settings for the ActionPack integration
        class Settings < Contrib::Configuration::Settings
          option :analytics_enabled do |o|
            o.default { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, nil) }
            o.lazy
          end

          option :analytics_sample_rate do |o|
            o.default { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) }
            o.lazy
          end

          option :controller_service
          option :exception_controller
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end

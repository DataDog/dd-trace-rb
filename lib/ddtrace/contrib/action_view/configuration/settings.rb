require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/action_view/ext'

module Datadog
  module Contrib
    module ActionView
      module Configuration
        # Custom settings for the ActionView integration
        class Settings < Contrib::Configuration::Settings
          option  :analytics_enabled,
                  default: -> { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) },
                  lazy: true

          option  :analytics_sample_rate,
                  default: -> { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) },
                  lazy: true

          option :service_name, default: Ext::SERVICE_NAME
          option :template_base_path, default: 'views/'
        end
      end
    end
  end
end

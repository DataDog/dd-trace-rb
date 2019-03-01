require 'ddtrace/contrib/configuration/settings'

module Datadog
  module Contrib
    module Shoryuken
      module Configuration
        # Default settings for the Shoryuken integration
        class Settings < Contrib::Configuration::Settings
          option  :analytics_enabled,
                  default: -> { env_to_bool(Ext::ENV_ANALYTICS_ENALBED, nil) },
                  lazy: true

          option  :analytics_sample_rate,
                  default: -> { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) },
                  lazy: true

          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end

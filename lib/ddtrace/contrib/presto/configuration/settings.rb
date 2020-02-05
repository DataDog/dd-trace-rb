require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/presto/ext'

module Datadog
  module Contrib
    module Presto
      module Configuration
        # Custom settings for the Presto integration
        class Settings < Contrib::Configuration::Settings
          option  :analytics_enabled,
                  default: -> { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) },
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

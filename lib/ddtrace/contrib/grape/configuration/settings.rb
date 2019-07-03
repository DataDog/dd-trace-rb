require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/ext/http'
require 'ddtrace/contrib/grape/ext'

module Datadog
  module Contrib
    module Grape
      module Configuration
        # Custom settings for the Grape integration
        class Settings < Contrib::Configuration::Settings
          option  :analytics_enabled,
                  default: -> { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, nil) },
                  lazy: true

          option  :analytics_sample_rate,
                  default: -> { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) },
                  lazy: true

          option :enabled, default: true
          option :service_name, default: Ext::SERVICE_NAME
          option :error_for_4xx, default: true
        end
      end
    end
  end
end

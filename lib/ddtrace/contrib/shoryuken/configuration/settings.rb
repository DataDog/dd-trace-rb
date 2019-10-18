require 'ddtrace/contrib/configuration/settings'

module Datadog
  module Contrib
    module Shoryuken
      module Configuration
        # Default settings for the Shoryuken integration
        class Settings < Contrib::Configuration::Settings
          option :analytics_enabled do |o|
            o.default { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) }
            o.lazy
          end

          option :analytics_sample_rate do |o|
            o.default { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) }
            o.lazy
          end

          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end

require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/mongodb/ext'

module Datadog
  module Contrib
    module MongoDB
      module Configuration
        # Custom settings for the MongoDB integration
        class Settings < Contrib::Configuration::Settings
          DEFAULT_QUANTIZE = { show: [:collection, :database, :operation] }.freeze

          option  :analytics_enabled,
                  default: -> { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) },
                  lazy: true

          option  :analytics_sample_rate,
                  default: -> { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) },
                  lazy: true

          option :quantize, default: DEFAULT_QUANTIZE
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end

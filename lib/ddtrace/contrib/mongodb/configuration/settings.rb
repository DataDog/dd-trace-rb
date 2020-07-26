require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/mongodb/ext'

module Datadog
  module Contrib
    module MongoDB
      module Configuration
        # Custom settings for the MongoDB integration
        class Settings < Contrib::Configuration::Settings
          DEFAULT_QUANTIZE = { show: [:collection, :database, :operation] }.freeze

          option :enabled do |o|
            o.default { env_to_bool(Ext::ENV_ENABLED, true) }
            o.lazy
          end

          option :analytics_enabled do |o|
            o.default { env_to_bool([Ext::ENV_ANALYTICS_ENABLED, Ext::ENV_ANALYTICS_ENABLED_OLD], false) }
            o.lazy
          end

          option :analytics_sample_rate do |o|
            o.default { env_to_float([Ext::ENV_ANALYTICS_SAMPLE_RATE, Ext::ENV_ANALYTICS_SAMPLE_RATE_OLD], 1.0) }
            o.lazy
          end

          option :quantize, default: DEFAULT_QUANTIZE
          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end

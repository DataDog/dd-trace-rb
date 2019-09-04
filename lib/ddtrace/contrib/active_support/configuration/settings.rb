require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/active_support/ext'

module Datadog
  module Contrib
    module ActiveSupport
      module Configuration
        # Custom settings for the ActiveSupport integration
        class Settings < Contrib::Configuration::Settings
          option  :analytics_enabled,
                  default: -> { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) },
                  lazy: true

          option  :analytics_sample_rate,
                  default: -> { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) },
                  lazy: true

          option :cache_service, default: Ext::SERVICE_CACHE
        end
      end
    end
  end
end

require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/excon/ext'

module Datadog
  module Contrib
    module Excon
      module Configuration
        # Custom settings for the Excon integration
        class Settings < Contrib::Configuration::Settings
          option  :analytics_enabled,
                  default: -> { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) },
                  lazy: true

          option  :analytics_sample_rate,
                  default: -> { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) },
                  lazy: true

          option :distributed_tracing, default: true
          option :error_handler, default: nil
          option :service_name, default: Ext::SERVICE_NAME
          option :split_by_domain, default: false
        end
      end
    end
  end
end

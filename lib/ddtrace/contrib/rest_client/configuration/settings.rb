require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/rest_client/ext'

module Datadog
  module Contrib
    module RestClient
      module Configuration
        # Custom settings for the RestClient integration
        class Settings < Contrib::Configuration::Settings
          option  :analytics_enabled,
                  default: -> { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, false) },
                  lazy: true

          option  :analytics_sample_rate,
                  default: -> { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) },
                  lazy: true

          option :distributed_tracing, default: true
          option :service_name, default: Ext::SERVICE_NAME, depends_on: [:tracer] do |value|
            get_option(:tracer).set_service_info(value, Ext::APP, Datadog::Ext::AppTypes::WEB)
            value
          end
        end
      end
    end
  end
end

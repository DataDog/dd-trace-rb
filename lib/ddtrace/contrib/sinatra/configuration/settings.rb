require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/ext/app_types'
require 'ddtrace/contrib/sinatra/ext'

module Datadog
  module Contrib
    module Sinatra
      module Configuration
        # Custom settings for the Sinatra integration
        class Settings < Contrib::Configuration::Settings
          DEFAULT_HEADERS = {
            response: %w[Content-Type X-Request-ID]
          }.freeze

          option  :analytics_enabled,
                  default: -> { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, nil) },
                  lazy: true

          option  :analytics_sample_rate,
                  default: -> { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) },
                  lazy: true

          option :distributed_tracing, default: true
          option :headers, default: DEFAULT_HEADERS
          option :resource_script_names, default: false

          option :service_name, default: Ext::SERVICE_NAME, depends_on: [:tracer] do |value|
            get_option(:tracer).set_service_info(value, Ext::APP, Datadog::Ext::AppTypes::WEB)
            value
          end
        end
      end
    end
  end
end

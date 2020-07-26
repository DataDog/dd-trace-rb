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

          option :enabled do |o|
            o.default { env_to_bool(Ext::ENV_ENABLED, true) }
            o.lazy
          end

          option :analytics_enabled do |o|
            o.default { env_to_bool([Ext::ENV_ANALYTICS_ENABLED, Ext::ENV_ANALYTICS_ENABLED_OLD], nil) }
            o.lazy
          end

          option :analytics_sample_rate do |o|
            o.default { env_to_float([Ext::ENV_ANALYTICS_SAMPLE_RATE, Ext::ENV_ANALYTICS_SAMPLE_RATE_OLD], 1.0) }
            o.lazy
          end

          option :distributed_tracing, default: true
          option :headers, default: DEFAULT_HEADERS
          option :resource_script_names, default: false

          option :service_name, default: Ext::SERVICE_NAME
        end
      end
    end
  end
end

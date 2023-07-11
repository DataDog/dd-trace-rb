require_relative '../../configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Sinatra
        module Configuration
          # Custom settings for the Sinatra integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            DEFAULT_HEADERS = {
              response: %w[Content-Type X-Request-ID]
            }.freeze

            option :enabled do |o|
              o.env_var Ext::ENV_ENABLED
              o.default true
              o.setter do |value|
                val_to_bool(value)
              end
            end

            option :analytics_enabled do |o|
              o.env_var Ext::ENV_ANALYTICS_ENABLED
              o.setter do |value|
                val_to_bool(value) if value
              end
            end

            option :analytics_sample_rate do |o|
              o.env_var Ext::ENV_ANALYTICS_SAMPLE_RATE
              o.default 1.0
              o.setter do |value|
                val_to_float(value)
              end
            end

            option :distributed_tracing, default: true
            option :headers, default: DEFAULT_HEADERS
            option :resource_script_names, default: false

            option :service_name
          end
        end
      end
    end
  end
end

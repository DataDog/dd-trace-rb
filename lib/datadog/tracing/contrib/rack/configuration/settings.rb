require_relative '../../configuration/settings'
require_relative '../ext'

module Datadog
  module Tracing
    module Contrib
      module Rack
        module Configuration
          # Custom settings for the Rack integration
          # @public_api
          class Settings < Contrib::Configuration::Settings
            DEFAULT_HEADERS = {
              response: %w[
                Content-Type
                X-Request-ID
              ]
            }.freeze

            option :enabled do |o|
              o.default { env_to_bool(Ext::ENV_ENABLED, true) }
              o.lazy
            end

            option :analytics_enabled do |o|
              o.default { env_to_bool(Ext::ENV_ANALYTICS_ENABLED, nil) }
              o.lazy
            end

            option :analytics_sample_rate do |o|
              o.default { env_to_float(Ext::ENV_ANALYTICS_SAMPLE_RATE, 1.0) }
              o.lazy
            end

            option :application
            option :distributed_tracing, default: true
            option :headers, default: DEFAULT_HEADERS
            option :middleware_names, default: false
            option :quantize, default: {}
            option :request_queuing, default: false

            option :service_name

            option :web_service_name, default: Ext::DEFAULT_PEER_WEBSERVER_SERVICE_NAME
          end
        end
      end
    end
  end
end

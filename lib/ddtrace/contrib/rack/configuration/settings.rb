require 'ddtrace/contrib/configuration/settings'
require 'ddtrace/contrib/rack/ext'

module Datadog
  module Contrib
    module Rack
      module Configuration
        # Custom settings for the Rack integration
        class Settings < Contrib::Configuration::Settings
          DEFAULT_HEADERS = {
            response: [
              'Content-Type',
              'X-Request-ID'
            ]
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

          option :application
          option :distributed_tracing, default: true
          option :headers, default: DEFAULT_HEADERS
          option :middleware_names, default: false
          option :quantize, default: {}
          option :request_queuing, default: false

          option :service_name, default: Ext::SERVICE_NAME

          option :web_service_name, default: Ext::WEBSERVER_SERVICE_NAME
        end
      end
    end
  end
end

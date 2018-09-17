require 'ddtrace/contrib/configuration/settings'

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

          option :distributed_tracing, default: false
          option :middleware_names, default: false
          option :quantize, default: {}
          option :application
          option :service_name, default: 'rack', depends_on: [:tracer] do |value|
            get_option(:tracer).set_service_info(value, Integration::APP, Ext::AppTypes::WEB)
            value
          end
          option :request_queuing, default: false
          option :web_service_name, default: 'web-server', depends_on: [:tracer, :request_queuing] do |value|
            if get_option(:request_queuing)
              get_option(:tracer).set_service_info(value, 'webserver', Ext::AppTypes::WEB)
            end
            value
          end
          option :headers, default: DEFAULT_HEADERS
        end
      end
    end
  end
end

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

          option :application
          option :distributed_tracing, default: false
          option :event_sample_rate, default: 1.0
          option :headers, default: DEFAULT_HEADERS
          option :middleware_names, default: false
          option :quantize, default: {}
          option :request_queuing, default: false

          option :service_name, default: Ext::SERVICE_NAME, depends_on: [:tracer] do |value|
            get_option(:tracer).set_service_info(value, Ext::APP, Datadog::Ext::AppTypes::WEB)
            value
          end

          option :web_service_name, default: Ext::WEBSERVER_SERVICE_NAME, depends_on: [:tracer, :request_queuing] do |value|
            if get_option(:request_queuing)
              get_option(:tracer).set_service_info(value, Ext::WEBSERVER_APP, Datadog::Ext::AppTypes::WEB)
            end
            value
          end
        end
      end
    end
  end
end

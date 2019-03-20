module Datadog
  module Contrib
    module Rack
      # Rack integration constants
      module Ext
        APP = 'rack'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_RACK_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_RACK_ANALYTICS_SAMPLE_RATE'.freeze
        RACK_ENV_REQUEST_SPAN = 'datadog.rack_request_span'.freeze
        SERVICE_NAME = 'rack'.freeze
        SPAN_HTTP_SERVER_QUEUE = 'http_server.queue'.freeze
        SPAN_REQUEST = 'rack.request'.freeze
        WEBSERVER_APP = 'webserver'.freeze
        WEBSERVER_SERVICE_NAME = 'web-server'.freeze
      end
    end
  end
end

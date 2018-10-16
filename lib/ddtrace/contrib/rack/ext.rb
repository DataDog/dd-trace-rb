module Datadog
  module Contrib
    module Rack
      # Rack integration constants
      module Ext
        APP = 'rack'.freeze
        SERVICE_NAME = 'rack'.freeze
        WEBSERVER_APP = 'webserver'.freeze
        WEBSERVER_SERVICE_NAME = 'web-server'.freeze

        RACK_ENV_REQUEST_SPAN = 'datadog.rack_request_span'.freeze

        SPAN_HTTP_SERVER_QUEUE = 'http_server.queue'.freeze
        SPAN_REQUEST = 'rack.request'.freeze
      end
    end
  end
end

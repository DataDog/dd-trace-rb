module Datadog
  module Tracing
    module Contrib
      module Rack
        # Rack integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_RACK_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_RACK_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_RACK_ANALYTICS_SAMPLE_RATE'.freeze
          RACK_ENV_REQUEST_SPAN = 'datadog.rack_request_span'.freeze
          SPAN_HTTP_PROXY_REQUEST = 'http.proxy.request'.freeze
          SPAN_HTTP_PROXY_QUEUE = 'http.proxy.queue'.freeze
          SPAN_HTTP_SERVER_QUEUE = 'http_server.queue'.freeze
          SPAN_REQUEST = 'rack.request'.freeze
          TAG_COMPONENT = 'rack'.freeze
          TAG_COMPONENT_HTTP_PROXY = 'http_proxy'.freeze
          TAG_OPERATION_REQUEST = 'request'.freeze
          TAG_OPERATION_HTTP_PROXY_REQUEST = 'request'.freeze
          TAG_OPERATION_HTTP_PROXY_QUEUE = 'queue'.freeze
          TAG_OPERATION_HTTP_SERVER_QUEUE = 'queue'.freeze
          WEBSERVER_APP = 'webserver'.freeze
          DEFAULT_PEER_WEBSERVER_SERVICE_NAME = 'web-server'.freeze
        end
      end
    end
  end
end

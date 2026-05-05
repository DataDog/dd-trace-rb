# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Rack
        # Rack integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_RACK_ENABLED'
          ENV_DISTRIBUTED_TRACING = 'DD_TRACE_RACK_DISTRIBUTED_TRACING'
          # @!visibility private
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_RACK_ANALYTICS_ENABLED'
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_RACK_ANALYTICS_SAMPLE_RATE'
          RACK_ENV_REQUEST_SPAN = 'datadog.rack_request_span'
          SPAN_HTTP_PROXY_REQUEST = 'http.proxy.request'
          SPAN_HTTP_PROXY_QUEUE = 'http.proxy.queue'
          SPAN_REQUEST = 'rack.request'
          TAG_COMPONENT = 'rack'
          TAG_COMPONENT_HTTP_PROXY = 'http_proxy'
          TAG_OPERATION_REQUEST = 'request'
          TAG_OPERATION_HTTP_PROXY_REQUEST = 'request'
          TAG_OPERATION_HTTP_PROXY_QUEUE = 'queue'
          TAG_OPERATION_HTTP_SERVER_QUEUE = 'queue'
          WEBSERVER_APP = 'webserver'
          DEFAULT_PEER_WEBSERVER_SERVICE_NAME = 'web-server'

          # @!visibility private
          HEADER_X_DD_PROXY = 'HTTP_X_DD_PROXY'
          HEADER_X_DD_PROXY_REQUEST_TIME_MS = 'HTTP_X_DD_PROXY_REQUEST_TIME_MS'
          HEADER_X_DD_PROXY_PATH = 'HTTP_X_DD_PROXY_PATH'
          HEADER_X_DD_PROXY_RESOURCE_PATH = 'HTTP_X_DD_PROXY_RESOURCE_PATH'
          HEADER_X_DD_PROXY_HTTPMETHOD = 'HTTP_X_DD_PROXY_HTTPMETHOD'
          HEADER_X_DD_PROXY_DOMAIN_NAME = 'HTTP_X_DD_PROXY_DOMAIN_NAME'
          HEADER_X_DD_PROXY_STAGE = 'HTTP_X_DD_PROXY_STAGE'
          HEADER_X_DD_PROXY_ACCOUNT_ID = 'HTTP_X_DD_PROXY_ACCOUNT_ID'
          HEADER_X_DD_PROXY_API_ID = 'HTTP_X_DD_PROXY_API_ID'
          HEADER_X_DD_PROXY_REGION = 'HTTP_X_DD_PROXY_REGION'
          HEADER_X_DD_PROXY_USER = 'HTTP_X_DD_PROXY_USER'

          PROXY_AWS_APIGATEWAY = 'aws-apigateway'
          PROXY_AWS_HTTPAPI = 'aws-httpapi'

          SPAN_AWS_APIGATEWAY = 'aws.apigateway'
          SPAN_AWS_HTTPAPI = 'aws.httpapi'

          PROXY_SPAN_NAMES = {
            PROXY_AWS_APIGATEWAY => SPAN_AWS_APIGATEWAY,
            PROXY_AWS_HTTPAPI => SPAN_AWS_HTTPAPI,
          }.freeze

          TAG_INFERRED_SPAN = '_dd.inferred_span'
        end
      end
    end
  end
end

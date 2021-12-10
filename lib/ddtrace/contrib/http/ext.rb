# typed: true
module Datadog
  module Contrib
    module HTTP
      # HTTP integration constants
      module Ext
        ENV_ENABLED = 'DD_TRACE_HTTP_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_HTTP_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_HTTP_ANALYTICS_SAMPLE_RATE'.freeze
        DEFAULT_PEER_SERVICE_NAME = 'net/http'.freeze
        SPAN_REQUEST = 'http.request'.freeze
        TAG_COMPONENT = 'net/http'.freeze
        TAG_OPERATION_REQUEST = 'request'.freeze
      end
    end
  end
end

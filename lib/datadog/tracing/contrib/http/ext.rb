# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module HTTP
        # HTTP integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_HTTP_ENABLED'
          ENV_SERVICE_NAME = 'DD_TRACE_NET_HTTP_SERVICE_NAME'
          ENV_PEER_SERVICE = 'DD_TRACE_NET_HTTP_PEER_SERVICE'
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_HTTP_ANALYTICS_ENABLED'
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_HTTP_ANALYTICS_SAMPLE_RATE'
          ENV_ERROR_STATUS_CODES = 'DD_TRACE_HTTP_ERROR_STATUS_CODES'
          DEFAULT_PEER_SERVICE_NAME = 'net/http'
          SPAN_REQUEST = 'http.request'
          TAG_COMPONENT = 'net/http'
          TAG_OPERATION_REQUEST = 'request'
          PEER_SERVICE_SOURCES = Array[
            Tracing::Metadata::Ext::TAG_PEER_HOSTNAME,
            Tracing::Metadata::Ext::NET::TAG_DESTINATION_NAME,
            Tracing::Metadata::Ext::NET::TAG_TARGET_HOST,].freeze
        end
      end
    end
  end
end

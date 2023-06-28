# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Faraday
        # Faraday integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_FARADAY_ENABLED'
          ENV_SERVICE_NAME = 'DD_TRACE_FARADAY_SERVICE_NAME'
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_FARADAY_ANALYTICS_ENABLED'
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_FARADAY_ANALYTICS_SAMPLE_RATE'
          DEFAULT_PEER_SERVICE_NAME = 'faraday'
          SPAN_REQUEST = 'faraday.request'
          TAG_COMPONENT = 'faraday'
          TAG_OPERATION_REQUEST = 'request'
        end
      end
    end
  end
end

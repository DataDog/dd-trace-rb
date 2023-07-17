# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Excon
        # Excon integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_EXCON_ENABLED'
          ENV_SERVICE_NAME = 'DD_TRACE_EXCON_SERVICE_NAME'
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_EXCON_ANALYTICS_ENABLED'
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_EXCON_ANALYTICS_SAMPLE_RATE'
          DEFAULT_PEER_SERVICE_NAME = 'excon'
          SPAN_REQUEST = 'excon.request'
          TAG_COMPONENT = 'excon'
          TAG_OPERATION_REQUEST = 'request'
        end
      end
    end
  end
end

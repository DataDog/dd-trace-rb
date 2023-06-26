# frozen_string_literal: true

module Datadog
  module Tracing
    module Contrib
      module Dalli
        # Dalli integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_DALLI_ENABLED'
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_DALLI_ANALYTICS_ENABLED'
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_DALLI_ANALYTICS_SAMPLE_RATE'
          ENV_SERVICE_NAME = 'DD_TRACE_DALLI_SERVICE_NAME'
          QUANTIZE_MAX_CMD_LENGTH = 100
          DEFAULT_PEER_SERVICE_NAME = 'memcached'
          SPAN_COMMAND = 'memcached.command'
          SPAN_TYPE_COMMAND = 'memcached'
          TAG_COMMAND = 'memcached.command'
          TAG_COMPONENT = 'dalli'
          TAG_OPERATION_COMMAND = 'command'
          TAG_SYSTEM = 'memcached'
        end
      end
    end
  end
end

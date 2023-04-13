module Datadog
  module Tracing
    module Contrib
      module Dalli
        # Dalli integration constants
        # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
        module Ext
          ENV_ENABLED = 'DD_TRACE_DALLI_ENABLED'.freeze
          ENV_ANALYTICS_ENABLED = 'DD_TRACE_DALLI_ANALYTICS_ENABLED'.freeze
          ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_DALLI_ANALYTICS_SAMPLE_RATE'.freeze
          ENV_SERVICE_NAME = 'DD_TRACE_DALLI_SERVICE_NAME'.freeze
          QUANTIZE_MAX_CMD_LENGTH = 100
          DEFAULT_PEER_SERVICE_NAME = 'memcached'.freeze
          SPAN_COMMAND = 'memcached.command'.freeze
          SPAN_TYPE_COMMAND = 'memcached'.freeze
          TAG_COMMAND = 'memcached.command'.freeze
          TAG_COMPONENT = 'dalli'.freeze
          TAG_OPERATION_COMMAND = 'command'.freeze
          TAG_SYSTEM = 'memcached'.freeze
        end
      end
    end
  end
end

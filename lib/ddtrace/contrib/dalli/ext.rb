# typed: true
module Datadog
  module Contrib
    module Dalli
      # Dalli integration constants
      # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
      module Ext
        APP = 'dalli'.freeze
        ENV_ENABLED = 'DD_TRACE_DALLI_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_DALLI_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_DALLI_ANALYTICS_SAMPLE_RATE'.freeze
        QUANTIZE_MAX_CMD_LENGTH = 100
        SERVICE_NAME = 'memcached'.freeze
        SPAN_COMMAND = 'memcached.command'.freeze
        SPAN_TYPE_COMMAND = 'memcached'.freeze
        TAG_COMMAND = 'memcached.command'.freeze
      end
    end
  end
end

module Datadog
  module Contrib
    module Dalli
      # Dalli integration constants
      module Ext
        APP = 'dalli'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_DALLI_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_DALLI_ANALYTICS_SAMPLE_RATE'.freeze
        QUANTIZE_MAX_CMD_LENGTH = 100
        SERVICE_NAME = 'memcached'.freeze
        SPAN_COMMAND = 'memcached.command'.freeze
        SPAN_TYPE_COMMAND = 'memcached'.freeze
        TAG_COMMAND = 'memcached.command'.freeze
      end
    end
  end
end

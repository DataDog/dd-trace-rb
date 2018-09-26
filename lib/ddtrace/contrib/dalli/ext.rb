module Datadog
  module Contrib
    module Dalli
      # Dalli integration constants
      module Ext
        APP = 'dalli'.freeze
        SERVICE_NAME = 'memcached'.freeze

        QUANTIZE_MAX_CMD_LENGTH = 100
        SPAN_COMMAND = 'memcached.command'.freeze
        TAG_COMMAND = 'memcached.command'.freeze
      end
    end
  end
end

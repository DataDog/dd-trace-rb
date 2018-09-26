module Datadog
  module Contrib
    module Excon
      # Excon integration constants
      module Ext
        APP = 'excon'.freeze
        SERVICE_NAME = 'excon'.freeze

        SPAN_REQUEST = 'excon.request'.freeze
      end
    end
  end
end

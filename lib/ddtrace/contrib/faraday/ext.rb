module Datadog
  module Contrib
    module Faraday
      # Faraday integration constants
      module Ext
        APP = 'faraday'.freeze
        SERVICE_NAME = 'faraday'.freeze

        SPAN_REQUEST = 'faraday.request'.freeze
      end
    end
  end
end

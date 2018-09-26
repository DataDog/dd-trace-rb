module Datadog
  module Contrib
    module HTTP
      # HTTP integration constants
      module Ext
        APP = 'net/http'.freeze
        SERVICE_NAME = 'net/http'.freeze

        SPAN_REQUEST = 'http.request'.freeze
      end
    end
  end
end

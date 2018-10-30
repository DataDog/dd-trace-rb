module Datadog
  module Contrib
    module RestClient
      # RestClient integration constants
      module Ext
        APP = 'rest_client'.freeze
        SERVICE_NAME = 'rest_client'.freeze

        SPAN_REQUEST = 'rest_client.request'.freeze
      end
    end
  end
end

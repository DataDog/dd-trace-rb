module Datadog
  module Ext
    module HTTP
      BASE_URL = 'http.base_url'.freeze
      ERROR_RANGE = 500...600
      METHOD = 'http.method'.freeze
      STATUS_CODE = 'http.status_code'.freeze
      TEMPLATE = 'template'.freeze
      TYPE_INBOUND = 'web'.freeze
      TYPE_OUTBOUND = 'http'.freeze
      TYPE_PROXY = 'proxy'.freeze
      URL = 'http.url'.freeze

      # General header functionality
      module Headers
        module_function

        def to_tag(name)
          name.to_s.downcase.gsub(/[-\s]/, '_')
        end
      end

      # Request headers
      module RequestHeaders
        PREFIX = 'http.request.headers'.freeze

        module_function

        def to_tag(name)
          "#{PREFIX}.#{Headers.to_tag(name)}"
        end
      end

      # Response headers
      module ResponseHeaders
        PREFIX = 'http.response.headers'.freeze

        module_function

        def to_tag(name)
          "#{PREFIX}.#{Headers.to_tag(name)}"
        end
      end
    end
  end
end

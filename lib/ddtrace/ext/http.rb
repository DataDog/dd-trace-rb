module Datadog
  module Ext
    module HTTP
      BASE_URL = 'http.base_url'.freeze
      ERROR_RANGE = 500...600
      METHOD = 'http.method'.freeze
      STATUS_CODE = 'http.status_code'.freeze
      TEMPLATE = 'template'.freeze
      TYPE = 'http'.freeze
      URL = 'http.url'.freeze

      # Metadata headers
      HEADER_META_LANG = 'Datadog-Meta-Lang'.freeze
      HEADER_META_LANG_INTERPRETER = 'Datadog-Meta-Lang-Interpreter'.freeze
      HEADER_META_LANG_VERSION = 'Datadog-Meta-Lang-Version'.freeze
      HEADER_META_TRACER_VERSION = 'Datadog-Meta-Tracer-Version'.freeze

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

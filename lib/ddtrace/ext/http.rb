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

      # Constants for request headers
      module RequestHeaders
        CACHE_CONTROL = 'http.request.headers.cache_control'.freeze
        REQUEST_ID = 'http.request.headers.request_id'.freeze

        ALL = {
          'CACHE-CONTROL' => CACHE_CONTROL,
          'X-CORRELATION-ID' => REQUEST_ID,
          'X-REQUEST-ID' => REQUEST_ID
        }.freeze

        private_constant :ALL

        module_function

        def from_name(name)
          ALL[name.to_s.upcase.gsub(/[_\s]/, '-')]
        end
      end

      # Constants for response headers
      module ResponseHeaders
        CONTENT_TYPE = 'http.response.headers.content_type'.freeze
        CACHE_CONTROL = 'http.response.headers.cache_control'.freeze
        ETAG = 'http.response.headers.etag'.freeze
        EXPIRES = 'http.response.headers.expires'.freeze
        LAST_MODIFIED = 'http.response.headers.last_modified'.freeze
        REQUEST_ID = 'http.response.headers.request_id'.freeze

        ALL = {
          'CONTENT-TYPE' => CONTENT_TYPE,
          'CACHE-CONTROL' => CACHE_CONTROL,
          'ETAG' => ETAG,
          'EXPIRES' => EXPIRES,
          'LAST-MODIFIED' => LAST_MODIFIED,
          'X-CORRELATION-ID' => REQUEST_ID,
          'X-REQUEST-ID' => REQUEST_ID
        }.freeze

        private_constant :ALL

        module_function

        def from_name(name)
          ALL[name.to_s.upcase.gsub(/[_\s]/, '-')]
        end
      end
    end
  end
end

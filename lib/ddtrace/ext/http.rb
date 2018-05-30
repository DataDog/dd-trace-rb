module Datadog
  module Ext
    module HTTP
      TYPE = 'http'.freeze
      TEMPLATE = 'template'.freeze
      URL = 'http.url'.freeze
      BASE_URL = 'http.base_url'.freeze
      METHOD = 'http.method'.freeze
      REQUEST_ID = 'http.request_id'.freeze
      STATUS_CODE = 'http.status_code'.freeze
      ETAG = 'http.etag'.freeze
      CACHE_CONTROL = 'http.cache_control'.freeze
      ERROR_RANGE = 500...600
    end
  end
end

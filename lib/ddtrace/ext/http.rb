module Datadog
  module Ext
    module HTTP
      TYPE = 'http'.freeze
      TEMPLATE = 'template'.freeze
      URL = 'http.url'.freeze
      BASE_URL = 'http.base_url'.freeze
      METHOD = 'http.method'.freeze
      STATUS_CODE = 'http.status_code'.freeze
      ERROR_RANGE = 500...600
    end
  end
end

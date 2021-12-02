# typed: true
module Datadog
  module Ext
    # @public_api
    module Correlation
      ATTR_ENV = 'dd.env'.freeze
      ATTR_SERVICE = 'dd.service'.freeze
      ATTR_SPAN_ID = 'dd.span_id'.freeze
      ATTR_TRACE_ID = 'dd.trace_id'.freeze
      ATTR_VERSION = 'dd.version'.freeze

      ENV_LOGS_INJECTION_ENABLED = 'DD_LOGS_INJECTION'.freeze
    end
  end
end

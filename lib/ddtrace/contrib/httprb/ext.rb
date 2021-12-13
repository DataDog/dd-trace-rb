# typed: true
module Datadog
  module Contrib
    module Httprb
      # Httprb integration constants
      # @public_api
      module Ext
        APP = 'httprb'.freeze
        ENV_ENABLED = 'DD_TRACE_HTTPRB_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_HTTPRB_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_EHTTPRB_ANALYTICS_SAMPLE_RATE'.freeze
        SERVICE_NAME = 'httprb'.freeze
        SPAN_REQUEST = 'httprb.request'.freeze
      end
    end
  end
end

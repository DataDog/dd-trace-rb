# typed: true
module Datadog
  module Contrib
    module Httprb
      # Httprb integration constants
      # @public_api Changing resource names, tag names, or environment variables creates breaking changes.
      module Ext
        ENV_ENABLED = 'DD_TRACE_HTTPRB_ENABLED'.freeze
        ENV_ANALYTICS_ENABLED = 'DD_TRACE_HTTPRB_ANALYTICS_ENABLED'.freeze
        ENV_ANALYTICS_SAMPLE_RATE = 'DD_TRACE_EHTTPRB_ANALYTICS_SAMPLE_RATE'.freeze
        DEFAULT_PEER_SERVICE_NAME = 'httprb'.freeze
        SPAN_REQUEST = 'httprb.request'.freeze
        TAG_COMPONENT = 'httprb'.freeze
        TAG_OPERATION_REQUEST = 'request'.freeze
      end
    end
  end
end

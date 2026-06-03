# frozen_string_literal: true

module Datadog
  module AppSec
    # Sets the always-on span tags built from a fixed allowlist of request and
    # response headers.
    #
    # NOTE: Unlike {Event#record}, which reports request headers only when
    #       a security event fires, these are tagged on every request/response
    #
    # @api private
    module DefaultHeaderTags
      WAF_VENDOR_HEADERS_TAGS = %w[
        x-amzn-trace-id
        cloudfront-viewer-ja3-fingerprint
        cf-ray
        x-cloud-trace-context
        x-appgw-trace-id
        x-sigsci-requestid
        x-sigsci-tags
        akamai-user-risk
      ].freeze

      RESPONSE_HEADERS_TAGS = %w[
        content-length
        content-type
        content-encoding
        content-language
      ].freeze

      module_function

      def tag_request(span, headers)
        WAF_VENDOR_HEADERS_TAGS.each do |name|
          value = headers.get(name)
          span.set_tag("http.request.headers.#{name}", value) if value
        end
      end

      def tag_response(span, headers)
        RESPONSE_HEADERS_TAGS.each do |name|
          value = headers.get(name)
          span.set_tag("http.response.headers.#{name}", value.to_s) if value
        end
      end
    end
  end
end

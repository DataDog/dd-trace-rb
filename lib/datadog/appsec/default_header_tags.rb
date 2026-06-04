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
      # NOTE: Contains additional WAF vendor headers
      REQUEST_HEADERS_TAGS = %w[
        accept
        content-type
        user-agent
        akamai-user-risk
        x-amzn-trace-id
        x-cloud-trace-context
        x-appgw-trace-id
        x-sigsci-requestid
        x-sigsci-tags
        cf-ray
        cloudfront-viewer-ja3-fingerprint
      ].freeze

      RESPONSE_HEADERS_TAGS = %w[
        content-type
        content-length
        content-encoding
        content-language
      ].freeze

      module_function

      def tag_request(span, headers)
        REQUEST_HEADERS_TAGS.each do |name|
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

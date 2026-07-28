# frozen_string_literal: true

require_relative "header_collection"
require_relative "../utils/quantization/http"

module Datadog
  module Tracing
    module Contrib
      module Rack
        # Matches Rack-style headers with a matcher and sets matching headers into a span.
        module HeaderTagging
          DATADOG_REQUEST_ATTRIBUTION_HEADERS = [
            "x-datadog-endpoint-scan",
            "x-datadog-security-test"
          ].freeze

          # Headers whose values are URLs. Their values are quantized before
          # tagging so query-string content (which may carry PII) is stripped.
          HEADERS_WITH_URLS = %w[
            Referer
            Location
          ].freeze

          def self.tag_request_headers(span, env, configuration)
            # Wrap env in a case-insensitive Rack-style accessor.
            headers = env.is_a?(Header::RequestHeaderCollection) ? env : Header::RequestHeaderCollection.new(env)

            # Use global DD_TRACE_HEADER_TAGS if integration-level configuration is not provided
            tags = if configuration.using_default?(:headers) && !Datadog.configuration.tracing.using_default?(:header_tags)
              Datadog.configuration.tracing.header_tags.request_tags(headers)
            else
              whitelist = configuration[:headers][:request] || []
              whitelist.each_with_object({}) do |header, result|
                header_value = headers.get(header)
                unless header_value.nil?
                  header_tag = Tracing::Metadata::Ext::HTTP::RequestHeaders.to_tag(header)
                  result[header_tag] = header_value
                end
              end
            end

            tags = quantize_header_tag_urls(
              tags, configuration, Datadog.configuration.tracing.header_tags.request_headers
            ) do |header|
              Tracing::Metadata::Ext::HTTP::RequestHeaders.to_tag(header)
            end

            span.set_tags(tags)
            tag_datadog_request_attribution_headers(span, headers)
          end

          def self.tag_response_headers(span, headers, configuration)
            headers = Core::Utils::Hash::CaseInsensitiveWrapper.new(headers) # Make header access case-insensitive

            # Use global DD_TRACE_HEADER_TAGS if integration-level configuration is not provided
            tags = if configuration.using_default?(:headers) && !Datadog.configuration.tracing.using_default?(:header_tags)
              Datadog.configuration.tracing.header_tags.response_tags(headers)
            else
              whitelist = configuration[:headers][:response] || []
              whitelist.each_with_object({}) do |header, result|
                header_value = headers[header]

                next if header_value.nil?

                header_tag = Tracing::Metadata::Ext::HTTP::ResponseHeaders.to_tag(header)

                # Maintain the value format between Rack 2 and 3
                #
                # Rack 2.x => { 'foo' => 'bar,baz' }
                # Rack 3.x => { 'foo' => ['bar', 'baz'] }
                result[header_tag] = if header_value.is_a? Array
                  header_value.join(",")
                else
                  header_value
                end
              end
            end

            tags = quantize_header_tag_urls(
              tags, configuration, Datadog.configuration.tracing.header_tags.response_headers
            ) do |header|
              Tracing::Metadata::Ext::HTTP::ResponseHeaders.to_tag(header)
            end

            span.set_tags(tags)
          end

          # Quantizes the URL value of any tagged URL-bearing header so
          # query-string content (which may carry PII) is stripped before the
          # value becomes a span tag. Covers both the standard tag name (used by
          # the integration whitelist and default DD_TRACE_HEADER_TAGS) and any
          # custom tag name assigned via DD_TRACE_HEADER_TAGS ("referer:my_tag").
          #
          # @api private
          private_class_method def self.quantize_header_tag_urls(tags, configuration, header_tag_names)
            # The whitelist branches build a Hash; the DD_TRACE_HEADER_TAGS
            # branches build an Array of [tag, value] pairs. Normalize so the
            # lookup and rewrite below work for both.
            tags = tags.to_h
            # HeaderTagging is shared across integrations (Rack, Sinatra, ...).
            # Only Rack defines the :quantize option, so integrations without it
            # fall back to default quantization rather than raising InvalidOptionError.
            quantize_options = (configuration.option_defined?(:quantize) && configuration[:quantize]) || {}

            quantized_tag_names(header_tag_names) { |header| yield(header) }.each do |tag|
              next unless tags.key?(tag)

              value = tags[tag]
              # The DD_TRACE_HEADER_TAGS response path does not join multi-value
              # headers, so a Rack 3 Array can reach here; HTTP.url needs a String.
              value = value.join(",") if value.is_a?(Array)
              tags[tag] = Contrib::Utils::Quantization::HTTP.url(value, quantize_options)
            end

            tags
          end

          # Tag names that hold URL values: the standard tag name for each
          # URL-bearing header, plus any custom name mapped from one of those
          # headers via DD_TRACE_HEADER_TAGS ("referer:my_tag").
          #
          # @api private
          private_class_method def self.quantized_tag_names(header_tag_names)
            HEADERS_WITH_URLS.each_with_object([]) do |header, names|
              names << yield(header)
              header_tag_names.each { |source, tag| names << tag if source.casecmp?(header) }
            end.uniq
          end

          # Datadog-originated requests use these headers for request attribution.
          # They are tagged independently of user-configured header tagging so
          # downstream systems can distinguish them from regular application traffic.
          #
          # @api private
          private_class_method def self.tag_datadog_request_attribution_headers(span, headers)
            DATADOG_REQUEST_ATTRIBUTION_HEADERS.each do |header|
              header_value = headers.get(header)
              next unless header_value

              header_tag = Tracing::Metadata::Ext::HTTP::RequestHeaders.to_tag(header)
              span.set_tag(header_tag, header_value)
            end
          end
        end
      end
    end
  end
end

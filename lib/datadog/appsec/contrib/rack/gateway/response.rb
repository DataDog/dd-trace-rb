# frozen_string_literal: true

require_relative '../../../instrumentation/gateway/argument'

module Datadog
  module AppSec
    module Contrib
      module Rack
        module Gateway
          # Gateway Response argument.
          class Response < Instrumentation::Gateway::Argument
            attr_reader :body, :status, :headers, :scope

            def initialize(body, status, headers, scope:)
              super()
              @body = body
              @status = status
              @headers = headers.each_with_object({}) { |(k, v), h| h[k.downcase] = v }
              @scope = scope
            end

            def parsed_body
              return unless Datadog.configuration.appsec.parse_response_body

              unless body.instance_of?(Array)
                Datadog.logger.debug do
                  "Response body type unsupported: #{body.class}"
                end
                return
              end

              return unless json_content_type?

              result = ''.dup
              all_body_parts_are_string = true

              body.each do |body_part|
                if body_part.is_a?(String)
                  result.concat(body_part)
                else
                  all_body_parts_are_string = false
                  break
                end
              end

              return unless all_body_parts_are_string

              begin
                JSON.parse(result)
              rescue JSON::ParserError => e
                Datadog.logger.debug { "Failed to parse response body. Error #{e.class}. Message #{e.message}" }
                nil
              end
            end

            def response
              @response ||= ::Rack::Response.new(body, status, headers)
            end

            private

            VALID_JSON_TYPES = [
              'application/json',
              'text/json'
            ].freeze

            def json_content_type?
              content_type = headers['content-type']
              VALID_JSON_TYPES.include?(content_type)
            end
          end
        end
      end
    end
  end
end

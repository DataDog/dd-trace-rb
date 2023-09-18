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
              return unless body.instance_of?(Array)
              return unless supported_response_type

              body_dup = body.dup # avoid interating over the body. This is just in case code.
              result = ''.dup
              all_body_parts_are_string = true

              body_dup.each do |body_part|
                if body_part.is_a?(String)
                  result.concat(body_part)
                else
                  all_body_parts_are_string = false
                  break
                end
              end

              return unless all_body_parts_are_string

              if json?
                JSON.parse(result)
              else
                result
              end
            end

            def response
              @response ||= ::Rack::Response.new(body, status, headers)
            end

            private

            def supported_response_type
              json? || text?
            end

            def json?
              headers['content-type'].include?('json')
            end

            def text?
              headers['content-type'].include?('text')
            end
          end
        end
      end
    end
  end
end

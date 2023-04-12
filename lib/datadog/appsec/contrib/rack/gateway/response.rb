# frozen_string_literal: true

require_relative '../../../instrumentation/gateway/argument'

module Datadog
  module AppSec
    module Contrib
      module Rack
        module Gateway
          # Gateway Response argument.
          class Response < Instrumentation::Gateway::Argument
            attr_reader :body, :status, :headers, :active_context

            def initialize(body, status, headers, active_context:)
              super()
              @body = body
              @status = status
              @headers = headers.each_with_object({}) { |(k, v), h| h[k.downcase] = v }
              @active_context = active_context
            end

            def response
              @response ||= ::Rack::Response.new(body, status, headers)
            end
          end
        end
      end
    end
  end
end

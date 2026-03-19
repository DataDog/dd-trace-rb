# frozen_string_literal: true

require_relative '../../../instrumentation/gateway/argument'

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        module Gateway
          class Response < Instrumentation::Gateway::Argument
            attr_reader :context

            def initialize(response, context:)
              super()
              @response = response || {}
              @context = context
            end

            def status
              @response['statusCode'] || 200
            end

            def headers
              @headers ||= (@response['headers'] || {}).each_with_object({}) do |(key, value), hash|
                hash[key.downcase] = value
              end
            end

            def response
              self
            end
          end
        end
      end
    end
  end
end

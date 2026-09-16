# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        # Response facade used by API Security sampling for Lambda invocations.
        class Response
          attr_reader :status, :headers, :body

          def self.from_normalized(response)
            new(
              status: response["status_code"].to_i,
              headers: response["headers"] || {},
              body: response["body"],
            )
          end

          def initialize(status:, headers:, body:)
            @status = status
            @headers = headers
            @body = body
          end
        end
      end
    end
  end
end

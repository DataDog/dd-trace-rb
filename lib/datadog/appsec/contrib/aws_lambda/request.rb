# frozen_string_literal: true

module Datadog
  module AppSec
    module Contrib
      module AwsLambda
        # Request facade used when recording AppSec events for Lambda invocations.
        class Request
          attr_reader :host, :user_agent, :remote_addr, :headers, :request_method, :path

          def self.from_normalized(event)
            headers = (event["headers"] || {}).each_with_object({}) do |(name, value), normalized|
              normalized[name.to_s.downcase] = value
            end

            new(
              remote_addr: event["source_ip"],
              headers: headers,
              request_method: event["method"],
              path: event["path"],
            )
          end

          def initialize(remote_addr:, headers:, request_method:, path:)
            @headers = headers
            @host = headers["host"]
            @user_agent = headers["user-agent"]
            @remote_addr = remote_addr
            @request_method = request_method
            @path = path
          end
        end
      end
    end
  end
end

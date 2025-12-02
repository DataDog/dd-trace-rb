# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      # Request builds the request body from a Session and processes the response
      class Request
        REQUEST_PATH = '/evaluate'

        def initialize(session)
          @session = session
        end

        def perform
          raw_response = AIGuard.api_client.post(path: REQUEST_PATH, request_body: build_request_body)

          Response.new(raw_response)
        end

        private

        def build_request_body
          {
            data: {
              attributes: {
                messages: @session.messages
              }
            }
          }
        end
      end
    end
  end
end

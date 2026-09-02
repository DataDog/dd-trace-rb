# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      # Request builds the request body for the AI Guard /evaluate endpoint
      class Request
        REQUEST_PATH = "/evaluate"

        def initialize(messages)
          @messages = messages
        end

        def body
          {
            data: {
              attributes: {
                messages: @messages.map(&:to_h),
                meta: {
                  service: Datadog.configuration.service,
                  env: Datadog.configuration.env,
                }
              }
            }
          }
        end
      end
    end
  end
end

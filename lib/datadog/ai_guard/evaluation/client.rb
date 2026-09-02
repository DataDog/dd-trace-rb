# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      module Client
        def self.evaluate(messages)
          request = Request.new(messages)
          transport = AIGuard.transport

          # This should never happen, as we are only calling this method when AI Guard is enabled,
          # and this means the transport was not initialized properly.
          #
          # Please report this at https://github.com/datadog/dd-trace-rb/blob/master/CONTRIBUTING.md#found-a-bug
          raise "AI Guard transport not initialized" unless transport

          response = Response.new(
            transport.post(Request::REQUEST_PATH, body: request.body)
          )

          redaction =
            if Datadog.configuration.ai_guard.redaction_enabled
              Redaction.apply(messages, replacements: response.redaction_replacements)
            else
              Redaction.skipped(messages)
            end

          result = Result.new(response, messages: redaction.messages)

          Outcome.new(result, redaction, blocking_enabled: response.blocking_enabled?)
        end
      end
    end
  end
end

# frozen_string_literal: true

module Datadog
  module AIGuard
    # class that performs AI Guard Evaluation and creates `ai_guard` span
    class Evaluation
      class AIGuardAbortError < StandardError
        def initialize(reason)
          @reason = reason
        end

        def to_s
          "Request aborted. #{@reason}"
        end
      end

      def initialize(messages)
        @messages = messages
      end

      def perform(allow_raise: false)
        response = Request.new(@messages).perform

        # TODO: add option to either do nothing, or block using appsec rack middleware, or raise
        raise Evaluation::AIGuardAbortError, response.reason if allow_raise && (response.deny? || response.abort?)

        response
      end
    end
  end
end

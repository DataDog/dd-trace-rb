# frozen_string_literal: true

module Datadog
  module AIGuard
    module Redaction
      class Result
        attr_reader :messages, :applied, :failures

        def initialize(messages, applied:, failures:, performed:)
          @messages = messages
          @applied = applied
          @failures = failures
          @performed = performed
        end

        def performed?
          @performed
        end

        def redacted?
          applied.positive?
        end
      end
    end
  end
end

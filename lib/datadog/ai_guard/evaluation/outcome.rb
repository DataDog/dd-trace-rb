# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      class Outcome
        attr_reader :result, :redaction

        def initialize(result:, redaction:, blocking_enabled:)
          @result = result
          @redaction = redaction
          @blocking_enabled = blocking_enabled
        end

        def block?
          @blocking_enabled && (result.deny? || result.abort?)
        end
      end
    end
  end
end

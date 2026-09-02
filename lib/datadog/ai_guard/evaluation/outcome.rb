# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      class Outcome
        attr_reader :result, :redaction

        def initialize(result, redaction)
          @result = result
          @redaction = redaction
        end
      end
    end
  end
end

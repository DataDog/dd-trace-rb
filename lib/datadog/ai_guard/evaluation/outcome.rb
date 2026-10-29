# frozen_string_literal: true

module Datadog
  module AIGuard
    module Evaluation
      # Internal outcome of an evaluation request
      #
      # @api private
      class Outcome
        attr_reader :result, :redaction, :extra_tags, :extra_metastruct

        def initialize(result:, redaction:, blocking_enabled:, extra_tags:, extra_metastruct:)
          @result = result
          @redaction = redaction
          @blocking_enabled = blocking_enabled
          @extra_tags = extra_tags
          @extra_metastruct = extra_metastruct
        end

        def block?
          @blocking_enabled && (result.deny? || result.abort?)
        end
      end
    end
  end
end

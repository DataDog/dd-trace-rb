# frozen_string_literal: true

module Datadog
  module AIGuard
    module Redaction
      # A result of applying redaction replacements
      #
      # @api private
      class Result
        attr_reader :messages, :applied_count, :failures_count

        def initialize(messages, applied_count:, failures_count:, performed: true)
          @messages = messages
          @applied_count = applied_count
          @failures_count = failures_count
          @performed = performed
        end

        def performed?
          @performed
        end

        def redacted?
          applied_count.positive?
        end
      end
    end
  end
end

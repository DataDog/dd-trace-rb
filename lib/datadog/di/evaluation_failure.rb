# frozen_string_literal: true

module Datadog
  module DI
    # An expression evaluation failure reported in a snapshot's evaluation
    # errors: the expression that failed and the error description.
    # @api private
    class EvaluationFailure
      # Initializes the failure.
      #
      # @param expr [String] name of the capture expression, or source of the condition or template expression, that failed to evaluate or serialize
      # @param message [String] error description of the failed evaluation
      # @return [void]
      def initialize(expr:, message:)
        @expr = expr
        @message = message
      end

      # The name of the capture expression, or the source of the condition or
      # template expression, that failed to evaluate or serialize.
      # @return [String]
      attr_reader :expr

      # @return [String] the error description of the failed evaluation
      attr_reader :message
    end
  end
end

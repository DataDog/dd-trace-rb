# frozen_string_literal: true

module Datadog
  module DI
    class CaptureExpressionEvaluator
      # The result of evaluating a probe's capture expressions: the
      # serialized values and the evaluation errors.
      class Result
        # Initializes the result.
        #
        # @param serialized_values [Hash{String => untyped}] serialized values keyed by capture expression name
        # @param errors [Array<Hash{Symbol => String}>] evaluation errors of the expressions that failed to evaluate or serialize
        # @return [void]
        def initialize(serialized_values:, errors:)
          @serialized_values = serialized_values
          @errors = errors
        end

        # The serialized values keyed by capture expression name. Entries for
        # expressions skipped by the capture time budget hold
        # +{notCapturedReason: "timeout"}+.
        # @return [Hash{String => untyped}]
        attr_reader :serialized_values

        # The evaluation errors; one +{expr: expression name, message: error
        # description}+ entry per expression that failed to evaluate or
        # serialize.
        # @return [Array<Hash{Symbol => String}>]
        attr_reader :errors
      end
    end
  end
end

# frozen_string_literal: true

module Datadog
  module OpenFeature
    # A proxy that delegates to the current evaluator instance.
    # This prevents issues with cached references to old evaluators after reconfiguration.
    class EvaluatorProxy
      def initialize(initial_evaluator)
        @current_evaluator = initial_evaluator
      end

      def update_evaluator!(new_evaluator)
        @current_evaluator = new_evaluator
      end

      def get_assignment(flag_key, default_value:, expected_type:, context:)
        @current_evaluator.get_assignment(
          flag_key,
          default_value: default_value,
          expected_type: expected_type,
          context: context
        )
      end
    end
  end
end

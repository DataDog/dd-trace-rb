# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Hooks
      class EvaluationTelemetryOptOutHook
        PARAMETER = "dd_evaluation_telemetry_opt_out"

        def self.opted_out?(evaluation_context)
          evaluation_context&.fields&.[](PARAMETER).equal?(true)
        end

        def initialize(hook)
          @hook = hook
        end

        def finally(hook_context:, evaluation_details:, **options)
          return if self.class.opted_out?(hook_context.evaluation_context)

          @hook.finally(hook_context: hook_context, evaluation_details: evaluation_details, **options)
        end
      end
    end
  end
end

# frozen_string_literal: true

module Datadog
  module OpenFeature
    module Hooks
      # Each SDK evaluation gets its own wrapper, including on SDK versions without hook data.
      class EvaluationTelemetryOptOutHook
        PARAMETER = "dd_evaluation_telemetry_opt_out"

        def self.opted_out?(evaluation_context)
          evaluation_context&.fields&.[](PARAMETER).equal?(true)
        end

        def initialize(hook)
          @hook = hook
          @opted_out = false
        end

        def before(hook_context:, **_opts)
          @opted_out = self.class.opted_out?(hook_context.evaluation_context)
          nil
        end

        def error(hook_context:, **_opts)
          # A failing application before hook can skip our before stage.
          @opted_out ||= self.class.opted_out?(hook_context.evaluation_context)
        end

        def finally(hook_context:, evaluation_details:, **options)
          return if @opted_out || self.class.opted_out?(hook_context.evaluation_context)

          @hook.finally(hook_context: hook_context, evaluation_details: evaluation_details, **options)
        end
      end
    end
  end
end

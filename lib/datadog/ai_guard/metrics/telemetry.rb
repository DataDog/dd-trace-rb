# frozen_string_literal: true

module Datadog
  module AIGuard
    # Namespace for metrics
    #
    # @api private
    module Metrics
      # A module for telemetry metrics reporting
      module Telemetry
        NAMESPACE = "ai_guard"
        CLIENT_ERROR = "client_error"
        REDACTION_ERROR = "redaction_error"

        module_function

        def report_evaluation(outcome, blocked:)
          telemetry = AIGuard.telemetry
          return unless telemetry

          result = outcome.result
          redaction = outcome.redaction

          tags = {action: result.action, block: blocked.to_s, error: "false"}
          tags[:redacted] = redaction.redacted?.to_s if redaction.performed?

          telemetry.inc(NAMESPACE, "requests", 1, tags: tags)
          if redaction.failures.positive?
            telemetry.inc(NAMESPACE, "error", redaction.failures, tags: {type: REDACTION_ERROR})
          end
        end

        def report_error
          telemetry = AIGuard.telemetry
          return unless telemetry

          telemetry.inc(NAMESPACE, "requests", 1, tags: {error: "true"})
          telemetry.inc(NAMESPACE, "error", 1, tags: {type: CLIENT_ERROR})
        end
      end
    end
  end
end

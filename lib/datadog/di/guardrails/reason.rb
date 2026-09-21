# frozen_string_literal: true

module Datadog
  module DI
    # Canonical DI guardrails observability surface: reason-code vocabulary
    # and tagged-telemetry helpers for skip and drop events.
    #
    # This module and {Reason} implement RFC C24 (canonical skip/drop reason
    # codes) and the skip/drop subset of C22 (the
    # +dynamic_instrumentation.guardrails.*+ metric family).
    module Guardrails
      # Canonical skip and drop reason codes from the Live Debugger
      # Guardrails and Circuit Breakers RFC (Observability section and
      # Appendix B). The values are fixed strings shared across every
      # tracer language; Ruby-specific spellings are prohibited.
      module Reason
        # Skip reasons: no-emission decisions made before expensive work.

        RATE_LIMIT_PROBE = "rateLimitProbe"
        RATE_LIMIT_GLOBAL = "rateLimitGlobal"
        EVALUATION_TIMEOUT = "evaluationTimeout"
        EVALUATION_ERROR_THROTTLED = "evaluationErrorThrottled"
        BUDGET_EXCEEDED_INVOCATION = "budgetExceededInvocation"
        BUDGET_EXCEEDED_GLOBAL = "budgetExceededGlobal"
        QUEUE_FULL = "queueFull"
        QUEUE_HIGH_WATERMARK = "queueHighWatermark"

        # Drop reasons: post-production discards. QUEUE_FULL and
        # QUEUE_HIGH_WATERMARK are shared with the skip vocabulary.

        PAYLOAD_TOO_LARGE = "payloadTooLarge"
        BATCH_BYTES_EXCEEDED = "batchBytesExceeded"
      end
    end
  end
end

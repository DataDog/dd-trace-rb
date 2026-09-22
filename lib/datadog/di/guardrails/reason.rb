# frozen_string_literal: true

module Datadog
  module DI
    module Guardrails
      # Canonical skip and drop reason codes. The values are fixed strings
      # shared verbatim across every tracer language.
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

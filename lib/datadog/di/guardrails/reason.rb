# frozen_string_literal: true

module Datadog
  module DI
    module Guardrails
      # Canonical skip and drop reason codes. Most codes are shared with the
      # other Datadog tracers; the remaining codes are Ruby-only forward
      # declarations for guardrails not yet implemented in Ruby.
      module Reason
        # Skip reasons.

        RATE_LIMIT_PROBE = "rateLimitProbe"
        RATE_LIMIT_GLOBAL = "rateLimitGlobal"
        EVALUATION_TIMEOUT = "evaluationTimeout"
        EVALUATION_ERROR_THROTTLED = "evaluationErrorThrottled"
        BUDGET_EXCEEDED_INVOCATION = "budgetExceededInvocation"
        BUDGET_EXCEEDED_GLOBAL = "budgetExceededGlobal"
        QUEUE_FULL = "queueFull"
        QUEUE_HIGH_WATERMARK = "queueHighWatermark"

        # Drop reasons. QUEUE_FULL and QUEUE_HIGH_WATERMARK are shared with
        # the skip vocabulary.

        PAYLOAD_TOO_LARGE = "payloadTooLarge"
        BATCH_BYTES_EXCEEDED = "batchBytesExceeded"
      end
    end
  end
end

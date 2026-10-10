# frozen_string_literal: true

module Datadog
  module DI
    class GuardrailsTelemetry
      # Canonical skip, drop and capture-incomplete reason codes. The
      # +di:+ debug logs and the guardrails metrics tag each guardrail
      # decision with one of these strings.
      module Reason
        # Skip reason emitted when a probe firing is rejected by the
        # probe's own rate limiter. Matches the reason code of the same
        # name in the other Datadog tracers.
        RATE_LIMIT_PROBE = "rateLimitProbe"

        # Skip reason emitted when a probe firing is rejected by the
        # process-wide rate limiter. Matches the reason code of the same
        # name in the other Datadog tracers.
        RATE_LIMIT_GLOBAL = "rateLimitGlobal"

        # Skip reason emitted when a capture expression evaluation exceeds
        # the capture time budget. Matches the reason code of the same
        # name in the other Datadog tracers.
        EVALUATION_TIMEOUT = "evaluationTimeout"

        # Skip reason emitted when a condition-evaluation failure
        # notification is rejected by the per-probe limiter. Ruby's name
        # for the evaluation-throttle guardrail decision.
        EVALUATION_ERROR_THROTTLED = "evaluationErrorThrottled"

        # Skip reason naming the per-invocation DI time budget guardrail
        # decision. Ruby's name for the invocation budget guardrail.
        BUDGET_EXCEEDED_INVOCATION = "budgetExceededInvocation"

        # Skip reason naming the process-wide DI time budget guardrail
        # decision. Ruby's name for the global budget guardrail.
        BUDGET_EXCEEDED_GLOBAL = "budgetExceededGlobal"

        # Skip and drop reason emitted when an event is discarded at a
        # full worker queue. Matches the reason code of the same name in
        # the other Datadog tracers.
        QUEUE_FULL = "queueFull"

        # Skip and drop reason naming the queue high-watermark guardrail
        # decision. Ruby's name for the queue high-watermark guardrail.
        QUEUE_HIGH_WATERMARK = "queueHighWatermark"

        # Drop reason emitted when a snapshot exceeds the serialized
        # payload limit. Matches the reason code of the same name in the
        # other Datadog tracers.
        PAYLOAD_TOO_LARGE = "payloadTooLarge"

        # Drop reason naming the batch byte-cap guardrail decision.
        # Ruby's name for the batch byte-cap guardrail.
        BATCH_BYTES_EXCEEDED = "batchBytesExceeded"

        # Capture-incomplete reason emitted when a capture or
        # serialization runtime exception ends the capture of a value
        # early. Matches the reason code of the same name in the GA RFC.
        RUNTIME_ERROR = "runtimeError"

        # Capture-incomplete reason emitted when the capture time budget
        # ends the capture of a value early. Matches the reason code of
        # the same name in the GA RFC.
        TIMEOUT = "timeout"

        # Capture-incomplete reason emitted when a value at the maximum
        # capture depth is not captured. Matches the reason code of the
        # same name in the GA RFC.
        DEPTH = "depth"

        # Capture-incomplete reason emitted when an object with more
        # fields than the capture limit is partially captured. Matches
        # the reason code of the same name in the GA RFC.
        FIELD_COUNT = "fieldCount"

        # Capture-incomplete reason emitted when a collection with more
        # items than the capture limit is partially captured. Matches the
        # reason code of the same name in the GA RFC.
        COLLECTION_SIZE = "collectionSize"

        # Capture-incomplete reason emitted when a captured string is
        # trimmed to the capture limit. Matches the reason code of the
        # same name in the GA RFC.
        STRING_LENGTH = "stringLength"

        # Capture-incomplete reason naming a capture limit the GA RFC
        # enum leaves to the tracer. Ruby's name for the remaining
        # early-capture causes; currently unused.
        OTHER = "other"
      end
    end
  end
end

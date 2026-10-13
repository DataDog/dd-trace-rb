# frozen_string_literal: true

module Datadog
  module DI
    class GuardrailsTelemetry
      # Canonical guardrails reason codes. Codes
      # shared with the other Datadog tracers keep the exact shared
      # spelling; codes with no shared counterpart use the Ruby tracer's
      # own name for the same decision.
      module Reason
        # Skip reason emitted when a probe firing is rejected by the
        # probe's own rate limiter.
        RATE_LIMIT_PROBE = "rateLimitProbe"

        # Skip reason emitted when a probe firing is rejected by the
        # process-wide rate limiter.
        RATE_LIMIT_GLOBAL = "rateLimitGlobal"

        # Skip reason emitted when a capture expression evaluation exceeds
        # the capture time budget.
        EVALUATION_TIMEOUT = "evaluationTimeout"

        # Skip reason named in the +di: debug log when a condition-evaluation
        # failure notification is rejected by the per-probe limiter.
        EVALUATION_ERROR_THROTTLED = "evaluationErrorThrottled"

        # Skip reason naming the per-invocation DI time budget guardrail
        # decision.
        BUDGET_EXCEEDED_INVOCATION = "budgetExceededInvocation"

        # Skip reason naming the process-wide DI time budget guardrail
        # decision.
        BUDGET_EXCEEDED_GLOBAL = "budgetExceededGlobal"

        # Skip and drop reason emitted when an event is discarded at a
        # full worker queue.
        QUEUE_FULL = "queueFull"

        # Skip and drop reason naming the queue high-watermark guardrail
        # decision.
        QUEUE_HIGH_WATERMARK = "queueHighWatermark"

        # Drop reason emitted when a snapshot exceeds the serialized
        # payload limit.
        PAYLOAD_TOO_LARGE = "payloadTooLarge"

        # Drop reason naming the batch byte-cap guardrail decision.
        BATCH_BYTES_EXCEEDED = "batchBytesExceeded"

        # Capture-incomplete reason emitted when a capture or
        # serialization runtime exception ends the capture of a value
        # early.
        RUNTIME_ERROR = "runtimeError"

        # Capture-incomplete reason emitted when a value at the maximum
        # capture depth is not captured.
        DEPTH = "depth"

        # Capture-incomplete reason emitted when an object with more
        # fields than the capture limit is partially captured.
        FIELD_COUNT = "fieldCount"

        # Capture-incomplete reason emitted when a collection with more
        # items than the capture limit is partially captured.
        COLLECTION_SIZE = "collectionSize"

        # Capture-incomplete reason emitted when a captured string is
        # trimmed to the capture limit.
        STRING_LENGTH = "stringLength"

        # Capture-incomplete reason for an early-capture cause with no
        # more specific code.
        OTHER = "other"

        # The skip reasons the events.skipped metric tags with the firing
        # probe's id; every other skip reason names a process-wide
        # decision and carries no probe id.
        PROBE_SCOPED_REASONS = [RATE_LIMIT_PROBE, EVALUATION_TIMEOUT].freeze
      end
    end
  end
end

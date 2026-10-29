# frozen_string_literal: true

module Datadog
  module AIGuard
    # AI Guard specific constants
    module Ext
      PRODUCT_BIT = 0x20

      SPAN_NAME = "ai_guard"
      TARGET_TAG = "ai_guard.target"
      TOOL_NAME_TAG = "ai_guard.tool_name"
      ACTION_TAG = "ai_guard.action"
      REASON_TAG = "ai_guard.reason"
      BLOCKED_TAG = "ai_guard.blocked"
      REDACTED_TAG = "ai_guard.redacted"
      EVENT_TAG = "ai_guard.event"

      METASTRUCT_TAG = "ai_guard"

      RESERVED_EXTRA_TAGS = [
        TARGET_TAG,
        TOOL_NAME_TAG,
        ACTION_TAG,
        REASON_TAG,
        BLOCKED_TAG,
        REDACTED_TAG,
        EVENT_TAG,
        "analytics.enabled",
        "_sampling_priority_v1",
        "_sample_rate",
        "env",
        "version",
        "span.kind",
        "error.type",
        "error.message",
        "error.stack",
        "language",
        "runtime-id",
        "process_id",
      ].freeze

      RESERVED_EXTRA_METASTRUCT_KEYS = [
        "messages",
        "attack_categories",
        "sds",
        "tag_probs",
      ].freeze

      TRACE_EXECUTED_TAG = "_dd.ai_guard.executed"
      TRACE_HTTP_USERAGENT_TAG = "_dd.ai_guard.http.useragent"
      TRACE_HTTP_CLIENT_IP_TAG = "_dd.ai_guard.http.client_ip"
      TRACE_NETWORK_CLIENT_IP_TAG = "_dd.ai_guard.network.client.ip"

      TRACE_ANOMALY_DETECTION_TAGS = [
        TRACE_HTTP_USERAGENT_TAG,
        TRACE_HTTP_CLIENT_IP_TAG,
        TRACE_NETWORK_CLIENT_IP_TAG,
      ].freeze
    end
  end
end

# frozen_string_literal: true

module Datadog
  module AIGuard
    # AI Guard specific constants
    module Ext
      SPAN_NAME = "ai_guard"
      TARGET_TAG = "ai_guard.target"
      TOOL_NAME_TAG = "ai_guard.tool_name"
      ACTION_TAG = "ai_guard.action"
      REASON_TAG = "ai_guard.reason"
      BLOCKED_TAG = "ai_guard.blocked"
      EVENT_TAG = "ai_guard.event"

      METASTRUCT_TAG = "ai_guard"

      TRACE_EXECUTED_TAG = "_dd.ai_guard.executed"
      TRACE_HTTP_USERAGENT_TAG = "_dd.ai_guard.http.useragent"
      TRACE_HTTP_CLIENT_IP_TAG = "_dd.ai_guard.http.client_ip"
      TRACE_NETWORK_CLIENT_IP_TAG = "_dd.ai_guard.network.client.ip"

      TRACE_ANOMALY_DETECTION_TAGS = [
        TRACE_HTTP_USERAGENT_TAG,
        TRACE_HTTP_CLIENT_IP_TAG,
        TRACE_NETWORK_CLIENT_IP_TAG
      ].freeze
    end
  end
end

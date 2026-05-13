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
      SERVICE_ENTRY_EXECUTED_TAG = "_dd.ai_guard.executed"
      METASTRUCT_TAG = "ai_guard"

      # Service-entry attributes mirrored onto every AI Guard span so the
      # anomaly-detection pipeline can operate on AI Guard spans alone
      # (without the corresponding service-entry span, which may arrive in
      # a different trace chunk under partial flush or async LLM completion).
      HTTP_USERAGENT_TAG = "ai_guard.http.useragent"
      HTTP_CLIENT_IP_TAG = "ai_guard.http.client_ip"
      NETWORK_CLIENT_IP_TAG = "ai_guard.network.client.ip"

      SERVICE_ENTRY_ATTRIBUTE_KEYS = [
        HTTP_USERAGENT_TAG,
        HTTP_CLIENT_IP_TAG,
        NETWORK_CLIENT_IP_TAG,
      ].freeze

      # Prefix that converts an AI Guard span tag name into the corresponding
      # internal stash trace-tag (e.g. "ai_guard.http.useragent" ->
      # "_dd.ai_guard.http.useragent"). The Rack middleware writes the stash
      # at request entry and clears it on exit; AI Guard evaluation reads
      # the stash to mirror values onto the AI Guard span.
      STASH_TAG_PREFIX = "_dd."
    end
  end
end

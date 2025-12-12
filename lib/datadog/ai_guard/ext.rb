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
      METASTRUCT_TAG = "ai_guard"
    end
  end
end

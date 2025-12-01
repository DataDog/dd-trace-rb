# frozen_string_literal: true

module Datadog
  module AIGuard
    module Configuration
      # This module contains constants for AI Guard component
      module Ext
        ENV_AI_GUARD_ENABLED = "DD_AI_GUARD_ENABLED"
        ENV_AI_GUARD_ENDPOINT = "DD_AI_GUARD_ENDPOINT"
        ENV_AI_GUARD_API_KEY = "DD_AI_GUARD_API_KEY"
        ENV_AI_GUARD_TIMEOUT = "DD_AI_GUARD_TIMEOUT"
        ENV_AI_GUARD_MAX_CONTENT_SIZE = "DD_AI_GUARD_MAX_CONTENT_SIZE"
        ENV_AI_GUARD_MAX_MESSAGES_LENGTH = "DD_AI_GUARD_MAX_MESSAGES_LENGTH"
      end
    end
  end
end

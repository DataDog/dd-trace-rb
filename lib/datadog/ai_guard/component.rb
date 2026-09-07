# frozen_string_literal: true

require_relative "http_client"
require_relative "evaluation"
require_relative "evaluation/request"
require_relative "evaluation/response"
require_relative "evaluation/client"
require_relative "evaluation/result"
require_relative "evaluation/outcome"
require_relative "evaluation/no_op_result"
require_relative "evaluation/message"
require_relative "evaluation/tool_call"
require_relative "evaluation/content_part"
require_relative "evaluation/content_builder"
require_relative "redaction"
require_relative "redaction/result"
require_relative "metrics/telemetry"
require_relative "ext"

module Datadog
  module AIGuard
    # Component for API Guard product
    class Component
      attr_reader :http_client, :logger, :telemetry

      def self.build(settings, logger:, telemetry:)
        return unless settings.respond_to?(:ai_guard) && settings.ai_guard.enabled

        http_client = HTTPClient.new(
          endpoint: settings.ai_guard.endpoint,
          api_key: settings.api_key,
          application_key: settings.ai_guard.app_key,
          timeout: settings.ai_guard.timeout_ms / 1_000
        )

        new(http_client, logger: logger, telemetry: telemetry)
      end

      def initialize(http_client, logger:, telemetry:)
        @http_client = http_client
        @logger = logger
        @telemetry = telemetry
      end

      def shutdown!
        # no-op
      end
    end
  end
end

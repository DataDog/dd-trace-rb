# frozen_string_literal: true

require_relative "transport"
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
require_relative "ext"

module Datadog
  module AIGuard
    # Component for API Guard product
    class Component
      attr_reader :transport, :logger, :telemetry

      def self.build(settings, logger:, telemetry:)
        return unless settings.respond_to?(:ai_guard) && settings.ai_guard.enabled

        transport = Transport.new(
          endpoint: settings.ai_guard.endpoint,
          api_key: settings.api_key,
          application_key: settings.ai_guard.app_key,
          timeout: settings.ai_guard.timeout_ms / 1_000
        )

        new(transport, logger: logger, telemetry: telemetry)
      end

      def initialize(transport, logger:, telemetry:)
        @transport = transport
        @logger = logger
        @telemetry = telemetry
      end

      def shutdown!
        # no-op
      end
    end
  end
end

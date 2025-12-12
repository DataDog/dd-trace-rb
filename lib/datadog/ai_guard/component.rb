# frozen_string_literal: true

require_relative 'api_client'
require_relative 'evaluation'
require_relative 'evaluation/request'
require_relative 'evaluation/result'
require_relative 'evaluation/no_op_result'
require_relative 'evaluation/message'
require_relative 'evaluation/tool_call'
require_relative 'ext'

module Datadog
  module AIGuard
    # Component for API Guard product
    class Component
      attr_reader :api_client, :logger

      def self.build(settings, logger:, telemetry:)
        return unless settings.respond_to?(:ai_guard) && settings.ai_guard.enabled

        api_client = APIClient.new(
          endpoint: settings.ai_guard.endpoint,
          api_key: settings.api_key,
          application_key: settings.app_key,
          timeout: settings.ai_guard.timeout_ms / 1000
        )

        new(api_client, logger: logger, telemetry: telemetry)
      end

      def initialize(api_client, logger:, telemetry:)
        @api_client = api_client
        @logger = logger
        @telemetry = telemetry
      end

      def shutdown!
        # no-op
      end
    end
  end
end

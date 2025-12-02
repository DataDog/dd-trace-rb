# frozen_string_literal: true

require_relative 'api_client'
require_relative 'evaluation/request'
require_relative 'evaluation/response'
require_relative 'session'

module Datadog
  module AIGuard
    # Component for API Guard product
    class Component
      attr_reader :api_client

      def self.build(settings, logger:, telemetry:)
        return unless settings.respond_to?(:ai_guard) && settings.ai_guard.enabled

        # TODO: validate settings
        api_client = APIClient.new(
          endpoint: settings.ai_guard.endpoint,
          api_key: settings.ai_guard.api_key,
          application_key: settings.ai_guard.application_key,
          timeout: settings.ai_guard.timeout
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

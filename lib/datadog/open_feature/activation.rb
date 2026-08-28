# frozen_string_literal: true

require_relative "component"
require_relative "remote"

module Datadog
  module OpenFeature
    # Owns the lazy lifecycle of the OpenFeature component.
    class Activation
      attr_reader :component

      def initialize(settings, agent_settings, remote, logger:, telemetry:)
        @settings = settings
        @agent_settings = agent_settings
        @remote = remote
        @logger = logger
        @telemetry = telemetry
        @component = nil
        @activated = false
        @shutdown = false
        @mutex = Mutex.new
      end

      def activate
        @mutex.synchronize do
          return if @shutdown

          return @component if @activated

          @activated = true
          @component = Component.build(
            @settings,
            @agent_settings,
            logger: @logger,
            telemetry: @telemetry,
          )
          if @component
            register_remote_configuration
            @remote&.start
          end
          @component
        end
      end

      def activated?
        @mutex.synchronize { @activated }
      end

      def shutdown!
        component = @mutex.synchronize do
          return if @shutdown

          @shutdown = true
          @component
        end

        component&.shutdown!
      end

      private

      def register_remote_configuration
        receivers = Remote.receivers(@telemetry)
        @remote&.register(
          capabilities: Remote.capabilities,
          products: Remote.products,
          receivers: receivers,
        )
      end
    end
  end
end

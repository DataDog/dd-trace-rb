# frozen_string_literal: true

require_relative "../../core/encoding"
require_relative "../../core/transport/http"
require_relative "diagnostics"
require_relative "input"

module Datadog
  module DI
    module Transport
      # Namespace for HTTP transport components
      module HTTP
        DIAGNOSTICS = Diagnostics::API::Endpoint.new(
          "/debugger/v1/diagnostics",
          Core::Encoding::JSONEncoder,
        )

        INPUT = Input::API::Endpoint.new(
          "/debugger/v2/input",
          Core::Encoding::JSONEncoder,
        )

        LEGACY_INPUT = Input::API::Endpoint.new(
          # We used to use /debugger/v1/input, but now input
          # payloads should be going to the diagnostics endpoint
          # which I gather performs data redaction.
          "/debugger/v1/diagnostics",
          Core::Encoding::JSONEncoder,
        )

        # Builds a new Transport::HTTP::Client with default settings
        # Pass a block to override any settings.
        def self.diagnostics(
          agent_settings:,
          logger:,
          headers: nil
        )
          Core::Transport::HTTP.build(
            logger: logger,
            agent_settings: agent_settings,
            headers: headers,
          ) do |transport|
            transport.api "diagnostics", DIAGNOSTICS

            # Call block to apply any customization, if provided
            yield(transport) if block_given?
          end.to_transport(DI::Transport::Diagnostics::Transport)
        end

        # Builds the snapshot input transport, wiring the telemetry and
        # guardrails telemetry components into it. Pass a block to override
        # any transport settings.
        #
        # @param agent_settings [Datadog::Core::Configuration::AgentSettings] agent connection settings
        # @param logger [DI::Logger] logger for transport diagnostics
        # @param headers [Hash{String => String}, nil] headers to send with every request
        # @param telemetry [Datadog::Core::Telemetry::Component, nil] component transport errors are reported through
        # @param guardrails_telemetry [GuardrailsTelemetry] emitter for the canonical guardrails drop metric
        # @return [DI::Transport::Input::Transport]
        # @yield [builder] block overriding the default transport builder settings
        def self.input(
          agent_settings:,
          logger:,
          guardrails_telemetry:,
          headers: nil,
          telemetry: nil
        )
          builder = Core::Transport::HTTP.build(
            logger: logger,
            agent_settings: agent_settings,
            headers: headers,
          ) do |transport|
            transport.api "input", INPUT, fallback: "legacy_input", default: true
            transport.api "legacy_input", LEGACY_INPUT

            # Call block to apply any customization, if provided
            yield(transport) if block_given?
          end

          # Create transport with telemetry
          DI::Transport::Input::Transport.new(
            builder.to_api_instances,
            builder.default_api,
            logger: logger,
            telemetry: telemetry,
            guardrails_telemetry: guardrails_telemetry,
          )
        end
      end
    end
  end
end

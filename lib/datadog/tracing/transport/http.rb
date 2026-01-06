# frozen_string_literal: true

require_relative '../../core/encoding'
require_relative '../../core/environment/container'
require_relative '../../core/environment/ext'
require_relative '../../core/transport/ext'
require_relative '../../core/transport/http'
require_relative 'http/traces'

module Datadog
  module Tracing
    module Transport
      # Namespace for HTTP transport components
      module HTTP
        V4 = Traces::API::Endpoint.new(
          '/v0.4/traces',
          Core::Encoding::MsgpackEncoder,
          service_rates: true
        )

        V3 = Traces::API::Endpoint.new(
          '/v0.3/traces',
          Core::Encoding::MsgpackEncoder,
        )

        module_function

        # Builds a new Transport::HTTP::Client with default settings
        # Pass a block to override any settings.
        def default(
          agent_settings:,
          logger: Datadog.logger,
          headers: nil
        )
          Core::Transport::HTTP.build(
            agent_settings: agent_settings,
            logger: logger,
            headers: headers
          ) do |transport|
            transport.api 'v0.4', V4, fallback: 'v0.3', default: true
            transport.api 'v0.3', V3

            # Call block to apply any customization, if provided
            yield(transport) if block_given?
          end.to_transport(Transport::Traces::Transport)
        end
      end
    end
  end
end

# frozen_string_literal: true

require_relative '../../core/environment/container'
require_relative '../../core/environment/ext'
require_relative '../../core/transport/ext'
require_relative '../../core/transport/http'
require_relative 'http/api'
require_relative '../../../datadog/version'

module Datadog
  module Tracing
    module Transport
      # Namespace for HTTP transport components
      module HTTP
        module_function

        # Builds a new Transport::HTTP::Client with default settings
        # Pass a block to override any settings.
        def default(
          agent_settings:,
          api_version: nil,
          headers: nil
        )
          Core::Transport::HTTP.build(api_instance_class: API::Instance) do |transport|
            transport.adapter(agent_settings)
            transport.headers Core::Transport::HTTP.default_headers

            apis = API.defaults

            transport.api API::V4, apis[API::V4], fallback: API::V3, default: true
            transport.api API::V3, apis[API::V3]

            # Apply any settings given by options
            if api_version
              transport.default_api = api_version
            end
            if headers
              transport.headers(headers)
            end

            # Call block to apply any customization, if provided
            yield(transport) if block_given?
          end.to_transport(Transport::Traces::Transport)
        end
      end
    end
  end
end

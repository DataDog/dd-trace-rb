# frozen_string_literal: true

require 'uri'

require_relative '../../core/environment/container'
require_relative '../../core/environment/ext'
require_relative '../../core/transport/ext'
require_relative 'diagnostics'
require_relative 'input'
require_relative 'http/api'
require_relative '../../core/transport/http'
require_relative '../../../datadog/version'

module Datadog
  module DI
    module Transport
      # Namespace for HTTP transport components
      module HTTP
        module_function

        # Builds a new Transport::HTTP::Client
        def new(klass, &block)
          Core::Transport::HTTP.build(
            api_instance_class: API::Instance, &block
          ).to_transport(klass)
        end

        # Builds a new Transport::HTTP::Client with default settings
        # Pass a block to override any settings.
        def diagnostics(
          agent_settings:,
          api_version: nil,
          headers: nil
        )
          new(DI::Transport::Diagnostics::Transport) do |transport|
            transport.adapter(agent_settings)
            transport.headers Core::Transport::HTTP.default_headers

            apis = API.defaults

            transport.api API::DIAGNOSTICS, apis[API::DIAGNOSTICS]

            # Apply any settings given by options
            if api_version
              transport.default_api = api_version
            end
            if headers
              transport.headers(headers)
            end

            # Call block to apply any customization, if provided
            yield(transport) if block_given?
          end
        end

        # Builds a new Transport::HTTP::Client with default settings
        # Pass a block to override any settings.
        def input(
          agent_settings:,
          api_version: nil,
          headers: nil
        )
          new(DI::Transport::Input::Transport) do |transport|
            transport.adapter(agent_settings)
            transport.headers Core::Transport::HTTP.default_headers

            apis = API.defaults

            transport.api API::INPUT, apis[API::INPUT]

            # Apply any settings given by options
            if api_version
              transport.default_api = api_version
            end
            if headers
              transport.headers(headers)
            end

            # Call block to apply any customization, if provided
            yield(transport) if block_given?
          end
        end
      end
    end
  end
end

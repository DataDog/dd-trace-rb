# frozen_string_literal: true

require_relative '../../environment/container'
require_relative '../../environment/ext'
require_relative '../../transport/ext'
require_relative '../../transport/http'

# TODO: Improve negotiation to allow per endpoint selection
#
# Since endpoint negotiation happens at the `API::Spec` level there can not be
# a mix of endpoints at various versions or versionless without describing all
# the possible combinations as specs. See http/api.
#
# Below should be:
# require_relative '../../transport/http/api'
require_relative 'http/api'

# TODO: Decouple transport/http
#
# Because a new transport is required for every (API, Client, Transport)
# triplet and endpoints cannot be negotiated independently, there can not be a
# single `default` transport, but only endpoint-specific ones.

module Datadog
  module Core
    module Remote
      module Transport
        # Namespace for HTTP transport components
        module HTTP
          module_function

          # Builds a new Transport::HTTP::Client with default settings
          # Pass a block to override any settings.
          def root(
            agent_settings:,
            api_version: nil,
            headers: nil
          )
            Core::Transport::HTTP.build(api_instance_class: API::Instance) do |transport|
              transport.adapter(agent_settings)
              transport.headers(Core::Transport::HTTP.default_headers)

              apis = API.defaults

              transport.api API::ROOT, apis[API::ROOT]

              # Apply any settings given by options
              if api_version
                transport.default_api = api_version
              end
              if headers
                transport.headers(headers)
              end

              # Call block to apply any customization, if provided
              yield(transport) if block_given?
            end.to_transport(Core::Remote::Transport::Negotiation::Transport)
          end

          # Builds a new Transport::HTTP::Client with default settings
          # Pass a block to override any settings.
          def v7(
            agent_settings:,
            api_version: nil,
            headers: nil
          )
            Core::Transport::HTTP.build(api_instance_class: API::Instance) do |transport|
              transport.adapter(agent_settings)
              transport.headers Core::Transport::HTTP.default_headers

              apis = API.defaults

              transport.api API::V7, apis[API::V7]

              # Apply any settings given by options
              unless options.empty?
                transport.default_api = options[:api_version] if options.key?(:api_version)
                transport.headers options[:headers] if options.key?(:headers)
              end

              # Call block to apply any customization, if provided
              yield(transport) if block_given?
            end.to_transport(Core::Remote::Transport::Config::Transport)
          end
        end
      end
    end
  end
end

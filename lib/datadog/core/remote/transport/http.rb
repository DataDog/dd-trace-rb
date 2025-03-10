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

          # Builds a new Transport::HTTP::Client
          def new(klass, &block)
            Core::Transport::HTTP.build(
              api_instance_class: API::Instance, &block
            ).to_transport(klass)
          end

          # Builds a new Transport::HTTP::Client with default settings
          # Pass a block to override any settings.
          def root(
            agent_settings:,
            **options
          )
            new(Core::Remote::Transport::Negotiation::Transport) do |transport|
              transport.adapter(agent_settings)
              transport.headers(default_headers)

              apis = API.defaults

              transport.api API::ROOT, apis[API::ROOT]

              # Apply any settings given by options
              unless options.empty?
                transport.default_api = options[:api_version] if options.key?(:api_version)
                transport.headers options[:headers] if options.key?(:headers)
              end

              # Call block to apply any customization, if provided
              yield(transport) if block_given?
            end
          end

          # Builds a new Transport::HTTP::Client with default settings
          # Pass a block to override any settings.
          def v7(
            agent_settings:,
            **options
          )
            new(Core::Remote::Transport::Config::Transport) do |transport|
              transport.adapter(agent_settings)
              transport.headers default_headers

              apis = API.defaults

              transport.api API::V7, apis[API::V7]

              # Apply any settings given by options
              unless options.empty?
                transport.default_api = options[:api_version] if options.key?(:api_version)
                transport.headers options[:headers] if options.key?(:headers)
              end

              # Call block to apply any customization, if provided
              yield(transport) if block_given?
            end
          end

          def default_headers
            {
              Datadog::Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_TOP_LEVEL => '1',
              Datadog::Core::Transport::Ext::HTTP::HEADER_META_LANG => Datadog::Core::Environment::Ext::LANG,
              Datadog::Core::Transport::Ext::HTTP::HEADER_META_LANG_VERSION =>
                Datadog::Core::Environment::Ext::LANG_VERSION,
              Datadog::Core::Transport::Ext::HTTP::HEADER_META_LANG_INTERPRETER =>
                Datadog::Core::Environment::Ext::LANG_INTERPRETER,
              Datadog::Core::Transport::Ext::HTTP::HEADER_META_TRACER_VERSION =>
                Datadog::Core::Environment::Ext::GEM_DATADOG_VERSION
            }.tap do |headers|
              # Add container ID, if present.
              container_id = Datadog::Core::Environment::Container.container_id
              headers[Datadog::Core::Transport::Ext::HTTP::HEADER_CONTAINER_ID] = container_id unless container_id.nil?
              # Sending this header to the agent will disable metrics computation (and billing) on the agent side
              # by pretending it has already been done on the library side.
              if Datadog.configuration.appsec.standalone.enabled
                headers[Datadog::Core::Transport::Ext::HTTP::HEADER_CLIENT_COMPUTED_STATS] = 'yes'
              end
            end
          end

          def default_adapter
            Datadog::Core::Configuration::Ext::Agent::HTTP::ADAPTER
          end
        end
      end
    end
  end
end
